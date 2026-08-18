# Team-chat auto-notify protocol

Two (or more) AI agents share one append-only daily log and coordinate turns **without a human
relaying "you have an update."** Each agent runs `teamchat/bin/teamchat-wait.js`, which blocks until a
message addressed to it appears, then wakes the agent. Drop these two files into any project to
reuse it.

## The one convention that makes it work

Every message block starts with a header naming the sender and the recipient:

```
## 2026-07-21 — Codex → Claude
…message…
```

That header is the **turn marker**: the newest block's *recipient* is whose turn it is. Because it's
derived from the file itself, it can never desync from reality (a separate `.turn` file can). Only
the party who is *addressed* replies; after replying they address the other party, which flips the
turn. A human can inject `the owner → Claude` (or `→ Both`) and it wakes whoever it names.

## The loop each agent runs

1. **The instant the watcher fires, re-arm it with `--skip-current` BEFORE acting**
   (`node team-room/bin/teamchat-wait.js --skip-current &`). The flag baselines the message you are
   now holding, so the new watcher stays silent about it and fires only on something NEWER —
   coverage is continuous while you implement. (Added 2026-08-01 after a 16:08 Codex directive sat
   unnoticed past the 16:15 tick: the old loop re-armed only at reply time, so every mid-checkpoint
   follow-up landed in a dead window.)
2. **Act** on the message addressed to you.
3. **Write your reply** under the write-lock (below). Address it to the other party — this flips the
   turn. The already-armed watcher simply advances its baseline over your reply; nothing to re-arm.

The watcher exits (and the host notifies the agent) only when the newest block is *from someone
else* and *addressed to you*. When the newest block is yours, it stays quiet. `--skip-current` is
ONLY for step 1's re-arm-while-holding case — arming with it when the newest addressed-to-you block
is UNPROCESSED recreates the 07-30 silent deadlock.

## Writing safely (avoid interleaved appends)

Turn-based watching prevents *logical* collisions, but two simultaneous physical appends (an agent +
a human) could interleave. Wrap every append in an atomic lock — `mkdir` is atomic on every
filesystem:

```bash
until mkdir teams-chat/.lock 2>/dev/null; do sleep 0.3; done
cat >> "$TODAY_FILE" <<'MSG'
## 2026-07-21 — Claude → Codex
…your reply…
MSG
rmdir teams-chat/.lock
```

## The watcher — `teamchat/bin/teamchat-wait.js`

- **Adjustable at the very top** (`ADJUST ME` block):
  - `POLL_INTERVAL_SECONDS` — how often to check. Set per agent, e.g. **300 (5 min) for Fable**,
    **900 (15 min) for Codex**. Overridable with `--interval <seconds>`.
  - `ME_ALIASES` — how you appear as the recipient in headers. This side signs as `Claude`;
    `Fable` is accepted as an alias. Overridable with `--me "Name,Alias"`.
  - `LOG_ROOT` — the directory holding the dated `wk-*/<day>.md` logs. Overridable with `--root`.
- **Day rollover is automatic** — it always follows the newest-mtime `wk-*/…*.md` under `LOG_ROOT`,
  so when tomorrow's file is first written it becomes the target. No calendar math, nothing to reset.
- **`--status`** prints the active log, the last message, whose turn it is, and whether the watcher
  would fire right now — without waiting. Use it to sanity-check before arming.
- **`--skip-current`** (2026-08-01) baselines the newest block even when it is addressed to you and
  fires only on something newer. The one legitimate use: re-arming at the moment a fired watcher
  hands you a message, so coverage never lapses while you work it.

Examples:

```bash
node teamchat/bin/teamchat-wait.js --status                 # inspect current turn
node teamchat/bin/teamchat-wait.js                           # Fable/Claude, 5-min default (from CONFIG)
node teamchat/bin/teamchat-wait.js --me Codex --interval 900 # Codex, 15-min
```

## Honest limitation

The watcher only runs while an agent has an active session with a live background task; when it
fires, the agent acts and re-arms it. It is **not a 24/7 daemon** — if a session ends, nothing
re-arms it. That makes the *ping-pong within an active working session* fully automatic (the common
case). To cover "the other agent replies while you're offline," pair it with a scheduler that
periodically resumes the agent (e.g. a cron/cloud-agent), which is a separate layer.

## Codex wake connector (Windows)

`teamchat-codex-wake.js` supplies that separate layer without using Agent Room. It registers a
Windows task aligned to the wall clock (`:00`, `:15`, `:30`, `:45` by default). Each run first reads
the current link in `teams-chat/content.md` and exits locally when the newest message is not an
unconsumed update addressed to Codex. No model is started for quiet checks.

**The room does not survive a shutdown (owner directive, 2026-08-01).** The scheduled task persists
across reboots by design — so the connector itself carries a boot-session arm guard: `run` is
`dormant-unarmed` (no spawn, no state consumption, no writes) unless `team-room/state/armed.json`
was written during the CURRENT boot session. The stamp stores the boot identity (clock minus
uptime), never a wall-clock comparison, so a machine whose clock rewinds across restarts still
invalidates every stamp at reboot. `arm` (run from the repo root, by the reinit protocol only)
brings the room back; `disarm` kills it deliberately; `check`/`status` report the arm state.
A corrupt or malformed stamp fails CLOSED to dormant.

> **Day rollover (not calendar-aware).** The connector watches whichever file is the **top link**
> under `## Current log` in `teams-chat/content.md` — it follows that pointer, never the system
> clock. When a new day starts, the top link must be moved to the new dated file (which must already
> exist) or the connector keeps watching yesterday's log and a new day's messages never wake Codex.
> This roll is manual and is owned by the first agent to act each day; see the *Day rollover and the
> auto-wake pointer* section of `teams-chat/content.md`. No date is stored in the private config, so
> nothing on `D:` needs editing at rollover — only the `content.md` pointer.

Install it **from the Codex conversation that should be resumed**, so `CODEX_THREAD_ID` identifies
the correct pinned thread:

```powershell
node teamchat/bin/teamchat-codex-wake.js install --interval 15
```

The generated configuration, cursor, lock and activity log are kept outside the repository on
`D:\CodexData\teamchat-heartbeat\...` when `D:` exists. The committed script never contains or
prints the complete thread ID. The task uses `MultipleInstances=IgnoreNew`, plus its own stale lease,
so a second scheduled invocation cannot overlap an existing automated resume. The resume prompt also
requires `ignored-active` when the pinned session is already performing assigned work.

Use the private config path printed by installation for diagnostics:

```powershell
node teamchat/bin/teamchat-codex-wake.js check --config "D:\CodexData\teamchat-heartbeat\<project>\config.json"
node teamchat/bin/teamchat-codex-wake.js status --config "D:\CodexData\teamchat-heartbeat\<project>\config.json"
node teamchat/bin/teamchat-codex-wake.js uninstall --config "D:\CodexData\teamchat-heartbeat\<project>\config.json"
```

`check` never resumes Codex. `run` is the task entry point and should normally be left to Task
Scheduler. This connector does not wake or configure Claude/Fable; Fable's existing live-background
watcher remains independent.

## Replicating in another project

1. Copy the whole `teamchat/` folder into the target repo (it is self-contained and zero-dependency —
   see `README.md`).
2. Set the three `ADJUST ME` constants in `bin/teamchat-wait.js` (interval, your name/aliases, log
   root) — or pass them as flags. For the Codex connector pass `--index <path/to/content.md>` at
   install time (defaults to `teams-chat/content.md`).
3. Keep the `## date — Sender → Recipient` header convention and the `mkdir`-lock write rule.

Nothing else is project-specific.
