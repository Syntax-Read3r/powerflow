# teamchat — portable agent-to-agent coordination

A tiny, **zero-dependency** toolkit that lets two (or more) AI coding agents (e.g. Codex and Claude)
share one append-only chat log and take turns **without a human relaying "you have an update."** It is
a turn-based *file* protocol plus two watchers that wake the right agent when a message addressed to it
arrives.

Everything here uses only Node's standard library (`fs`, `path`, `crypto`, `os`, `child_process`), so
the whole folder is copy-paste portable into any project.

## What's in here

| File | Role |
|------|------|
| `bin/teamchat-wait.js` | **In-session watcher** (Claude/Fable). Runs as a background task; blocks until the *other* party posts a message addressed to you, prints it, and exits so the host harness re-wakes the agent. **One-shot — you must re-arm it each turn** (see *Operational gotchas*). Poll-based, cross-platform. |
| `bin/teamchat-codex-wake.js` | **Unattended wake connector** (Codex). Registers a Windows scheduled task that, every quarter hour, does a zero-token precheck and resumes a *pinned* Codex CLI session **only** when the newest message is from someone else and addressed to Codex. |
| `PROTOCOL.md` | The full turn-marker protocol, the write-lock rule, day-rollover behaviour, and the wake-connector reference. |

The two watchers are independent layers: `teamchat-wait.js` covers the fast ping-pong **within** a live
session; `teamchat-codex-wake.js` covers "the other agent replied while you were offline."

## The one convention

Every message block starts with a header naming sender and recipient — the newest block's *recipient*
is whose turn it is:

```
## 2026-07-21 14:30 BST — Codex → Claude
…message…
```

Because the turn is derived from the file itself, it can never desync. See `PROTOCOL.md` for the full
rules (write-lock, day rollover, replication).

## Quick start

Run the scripts directly with Node (no install needed):

```bash
# In-session watcher (Claude/Fable, 5-min default). Launch as a background task.
node teamchat/bin/teamchat-wait.js --status                  # inspect current turn, don't wait
node teamchat/bin/teamchat-wait.js --me "Claude,Fable"       # arm the watcher

# Unattended Codex wake connector (Windows). Install from the Codex session to pin its thread:
node teamchat/bin/teamchat-codex-wake.js install --interval 15
node teamchat/bin/teamchat-codex-wake.js check   --config "D:\CodexData\teamchat-heartbeat\<project>\config.json"
node teamchat/bin/teamchat-codex-wake.js status  --config "D:\CodexData\teamchat-heartbeat\<project>\config.json"
```

Or, after `npm install` in a consuming project, via the package bins:

```bash
npx teamchat-wait --status
npx teamchat-wake install --interval 15
```

`node teamchat/bin/teamchat-codex-wake.js self-test` (or `npm run self-test`) runs an offline
self-check of the turn logic.

## Operational gotchas (read before relying on auto-wake)

These are the traps that make an agent go silent when it *looks* wired up. Every one bit us in practice.

### 1. Re-arm `teamchat-wait.js` after EVERY message — it fires once, then it's gone

`teamchat-wait.js` is a *one-shot* watcher: it blocks until a message addressed to you appears, prints it,
and **exits**. The host harness re-wakes you *because* the background task exited. That means after you act
on a message and post your reply, you must **relaunch the watcher as a background task again** — otherwise
nothing is watching, and when the other agent replies you will sit idle until a human nudges you.

- **Symptom:** "The other agent replied but I never woke up / I stopped continuing on my own." Almost always
  this is a watcher that was never (re-)armed, **not** a broken connector and **not** anything the human did.
- **Fix / rule of thumb:** at the end of any turn where you're waiting on the other party, (re-)arm it as a
  background task, e.g. `teamchat-wait --me "Claude,Fable"` launched in the background. Arm it *after* you post
  (so its baseline is your own message and it waits for the other party's *next* reply).
- **Harness requirement:** this loop only works on a harness that notifies the agent when a background task
  exits (e.g. Claude Code). An agent whose runtime cannot do that (this is exactly why Codex exists as a
  *scheduled task* — `teamchat-codex-wake.js`) should use the connector instead of the wait watcher.

### 2. Waiting on CI: poll the RUN, not the checks — or your poller stalls and never wakes you

A common pattern is "push, then background a poller that wakes me when CI is green." The wake fires when the
**poller command exits**, so the poller's exit condition decides whether you wake at all.

- **Do:** key the wait on the **run-level status** — `gh run watch <run-id> --exit-status` (blocks until the
  run finishes, exits non-zero on failure), or `until [ "$(gh run view <id> --json status -q .status)" =
  "completed" ]`. The run flips to `completed` promptly.
- **Don't:** wait for every entry of the per-commit **check-runs** endpoint (`/commits/<sha>/check-runs`) to
  reach `completed`. That endpoint **lags** behind the run — a long job can still read `in_progress` there
  after the run itself is done, so the poller never exits and never wakes you.
- **Ignore** the legacy combined-status endpoint `/commits/<sha>/status`: it reads `state=pending` with
  `total_count=0` because GitHub Actions posts *check-runs*, not commit statuses, and a queued deploy-preview
  check-suite (e.g. Netlify) keeps a "pending" look around. The authoritative "green" signal is the **run
  `conclusion == success`** (a run is `success` only when every job passed).

### 3. Roll the day pointer — the connector is not calendar-aware

The Codex connector watches whichever file is the **top link** under `## Current log` in the index it was
given; it follows that pointer, never the clock. At the start of a new day (or after the machine was off),
the first agent to act must create the new dated file and move its link to the top, or a new day's messages
never wake the connector. No date is stored in the private config — only the index pointer changes. See the
*Day rollover* section of `PROTOCOL.md`.

## Porting to another project

1. Copy this entire `teamchat/` folder into the target repo.
2. Point the watchers at that project's log:
   - `teamchat-wait.js` — set the `ADJUST ME` constants at the top (`ME_ALIASES`, `LOG_ROOT`,
     `POLL_INTERVAL_SECONDS`) or pass `--me` / `--root` / `--interval`.
   - `teamchat-codex-wake.js` — pass `--index <path/to/content.md>` at install time (defaults to
     `teams-chat/content.md`).
3. Keep the `## <date> — Sender → Recipient` header convention and the `mkdir`-lock write rule.

Nothing else is project-specific. All session IDs, cursors, locks and runtime logs are stored in an
ignored local config **outside** the repo (on `D:` when present) — never committed.

## Configuration & state

The Codex connector's private config, cursor, lock and activity log live outside the repo (default
`D:\CodexData\teamchat-heartbeat\<project>\` on Windows, else `~/.codex/…`). The committed scripts never
contain or print a complete session/thread ID.
