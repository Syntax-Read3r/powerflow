# INITIATE — the agent startup ritual after a PC shutdown / restart

> **Restarted mid-checkpoint (uncommitted work, armed watchers, a build in flight)?** Run this file
> first, then `team-room/reinitate protocol one.md`, which layers the recovery specifics on top.
> The owner's whole prompt for that case is the single word **"reinitiate"**.

> **Audience:** the implementing agent (Claude/Fable here), on its FIRST turn after the machine was
> off or the session was interrupted. Follow the steps IN ORDER, top to bottom, before doing any
> project work. This file lives with the team-room tool so the same ritual ports to any project that
> uses it — the **Project card** at the bottom holds the per-project values; everything above it is
> generic.
>
> The owner's prompt for this is usually one line ("PC was shut down — initiate"). Everything else
> is your job.

---

## 0. Ground rules while initiating

- Do NOT post anything to the chat until step 3 (day-roll) and step 4 (turn state) are done.
- Do NOT start new checkpoint work during initiation — first restore the loop, then resume.
- Background tasks must be HARNESS-TRACKED (your tool's `run_in_background` mechanism), never a
  shell `&` — a shell-forked watcher dies silently and never wakes you.
- Watchers/pollers do not survive a shutdown. Assume every background process you had is dead;
  re-arm everything from scratch. A watcher task that reports "failed" right after a shutdown is
  the shutdown, not a bug.

## 1. Clock sanity

Get the wall-clock time with the method the Project card specifies, and sanity-check it against an
external timestamp if in doubt (e.g. a recent CI run's UTC time). Chat stamps must be monotonically
increasing and consistent with the partner agent's clock — a wrong stamp can make your post appear
to precede the message it answers.

## 2. Read the persistent state (before touching anything)

1. Your memory index + the running delivery-log memory: what checkpoint was live, what phase the
   loop was in (implementing / watching CI / holding), what is parked.
2. `<chat-root>/content.md` → the TOP link under "Current log" is the current day file.
3. The tail of that day file → the NEWEST block header tells you whose turn it is.

## 3. Day-roll (BEFORE any post — the wake connector is NOT calendar-aware)

If today's date has no log file yet, or the top link in `content.md` points at an older day:

1. Create `<chat-root>/<year>/<month>/wk-N/<day month>.md` for TODAY.
2. Move its link to the TOP of the "Current log" list in `content.md`.

The partner's wake connector follows the top pointer, not the clock — skipping this strands its
replies in yesterday's file. (Either agent may have already done the roll; verify, don't assume.)

## 4. Determine the turn state and act on it

- **Newest block is addressed TO you** (e.g. `Codex → Claude`): it arrived while you were away.
  Process it as a fresh instruction — this is your resume point. (Check the block was not already
  answered further down before acting.)
- **Newest block is FROM you** (`Claude → Codex`): you are HOLDING. Do not repost, do not nudge.
  Your resume point is "await the partner's reply" — go to steps 5–7 and then wait.
- **You were interrupted MID-DELIVERY** (memory says CI was running / a post was pending on green):
  check the CI state at the exact SHA (step 6); if it finished green while you were away, complete
  the interrupted post sequence now (stamp with the CURRENT time, not the pre-shutdown time).

## 5. Verify the partner agent's auto-wake is live

The partner (Codex here) is woken by an OS scheduled task. Check it exists and is enabled:

```
schtasks /query /tn "<partner-wake-task-name>"        # Windows — expect Ready or Running
```

- **Ready/Running** → the partner will wake on your next post. Nothing to do.
- **Disabled** → **RE-ENABLE IT. This is part of the protocol, not a question to ask.**
  (Owner directive, 2026-07-29: "by me saying reinit protocol, that includes codex wake task.")
  A reboot or a BIOS/firmware update can silently disable the task while leaving its definition
  intact — that happened on 2026-07-29, and a disabled task means the partner never wakes no matter
  what you post. Enabling is non-destructive and needs no recreation:

  ```
  Enable-ScheduledTask -TaskName "<partner-wake-task-name>"     # then verify State=Ready + a Next Run Time
  ```

- **Missing entirely** (the task does not exist) → still report rather than recreate: rebuilding
  another agent's task means reconstructing its action, config path and trigger, and getting that
  wrong is worse than a clean report. Enabling an existing task is not the same thing as authoring
  one.

Verify with `State` **and** `NextRunTime` — a task can read `Disabled` while still showing a stale
next-run time, so the state field is the one that decides.

Note: "Ready" only means the task will fire on schedule — the partner is "live" in the useful sense
once this task is healthy. If a reply is unusually overdue AFTER you post, mention it to the owner
rather than reposting.

### 5a. ARM the wake connector for THIS boot (owner directive, 2026-08-01)

The team room must NOT survive a PC shutdown. The scheduled task inevitably does (Task Scheduler
definitions persist, and `StartWhenAvailable` fires the missed tick right after boot), so the
connector itself is DORMANT after every reboot until this protocol arms it:

```
node team-room/bin/teamchat-codex-wake.js arm --by "reinit-<date>"     # from the repo root
```

The stamp lives at `team-room/state/armed.json` and is valid ONLY for the boot session that wrote it
(boot identity, not wall-clock — this machine's clock is known to rewind across restarts). A room
that was never re-armed answers every tick with `dormant-unarmed`: no Codex spawn, no state
consumption, nothing. Verify with:

```
node team-room/bin/teamchat-codex-wake.js check --config <state-dir>\config.json   # arm.armed: true
```

Skipping this step means Codex NEVER wakes no matter what you post — the enabled task alone is no
longer sufficient. That is the point.

## 6. Verify repo + CI state

1. `git log -1 --oneline` — is the last commit the one your memory says you delivered?
2. `git status --short` — only the EXPECTED housekeeping dirt (see Project card)? Anything
   unexpected: investigate before any new commit; never sweep working-tree files you didn't create.
3. If a delivery was in flight: `gh run list --commit <last-sha>` — completed green, completed red,
   or still running? Re-arm a run-level watcher (`gh run watch <id> --exit-status`, tracked
   background) for anything still running; diagnose (infra vs real) before any retry if red.

## 7. Arm YOUR watcher (the last step before reporting)

Start the chat watcher as a HARNESS-TRACKED background task:

```
node team-room/bin/teamchat-wait.js --me "<your-names>"
```

It exits when a new block addressed to you appears (your harness then re-invokes you), or exits
non-zero on interruption (a post-shutdown "failed" here is normal — re-arm). Re-arm it after EVERY
post you make to the chat.

**Continuous-coverage rule (2026-08-01): the INSTANT a fired watcher hands you a message, re-arm
with `--skip-current` BEFORE you start working it** — the flag baselines the in-hand message and
fires only on something newer, so a mid-checkpoint follow-up can never land in a dead window (a
16:08 Codex directive once sat unseen past the 16:15 tick because the fired watcher was the only
coverage and it had exited). `--skip-current` is for exactly that moment and nothing else — armed
against an UNPROCESSED message it recreates the 07-30 deadlock.

### 7a. NEVER arm the watcher blind — ask `--status` first

```
node team-room/bin/teamchat-wait.js --status --me "<your-names>"
```

It answers directly:

- **"FIRE now (a message is waiting for me)"** → a message is UNANSWERED. **Process it. Do not arm the
  watcher and wait** — there is nothing to wait for, and the partner is holding for your reply.
- **"WAIT (I owe nothing / it's the other party's turn)"** → you are holding. Arm the watcher.

**Why (2026-07-30):** the watcher takes the newest block as its BASELINE at startup and only fires on
something *newer*. Arming it while a message addressed to you is already newest therefore baselines
that unread message and waits forever for a follow-up the partner will never send — because they are
correctly holding for you. Both sides wait for each other and the loop is silently dead. Observed
exactly that: armed 07:26 against a 01:17 release, `--status` said "FIRE now" while the running watcher
sat idle.

`teamchat-wait.js` now carries a **startup deadlock guard** that delivers an already-waiting message
immediately instead of baselining it, so the tool can no longer strand the loop on its own. The
`--status` check remains the right discipline anyway: it stops you arming a watcher that is about to
fire instantly for something you have already read.

## 8. Report to the owner, briefly

One short status message: what state you found (turn, last checkpoint, CI), what you re-armed, what
you are now doing (resuming X / holding for the partner). The owner cannot read long dumps — keep
it tight, lead with the outcome.

---

## Project card — zavoya (this repo)

| Item | Value |
|---|---|
| Agents | **Codex** (master lead, releases checkpoints, sole approver) · **Claude/Fable** (implementer; implements → verifies → ONE isolated commit → CI green → report → HOLD) |
| Chat root | `teams-chat/` — pointer file `teams-chat/content.md`; logs `teams-chat/main-project/<year>/<month>/wk-N/<day> <month>.md` (e.g. `2026/August/wk-1/1 August.md`) |
| Watcher | `node team-room/bin/teamchat-wait.js --me "Claude,Fable"` from the repo root |
| Partner wake task | Windows scheduled task **`TeamChat-Codex-zavoya`** (`schtasks /query /tn TeamChat-Codex-zavoya`) |
| Wake connector arm (per boot) | `node team-room/bin/teamchat-codex-wake.js arm --by "reinit-<date>"` from the repo root; state dir `D:\CodexData\teamchat-heartbeat\zavoya-f5d71d9e` for the `check` verification |
| Clock | plain `date` in Git Bash (the machine clock IS London wall-time). NEVER `TZ=Europe/London date` — this Git Bash has no tz database and silently returns UTC, one hour behind BST |
| Stamp format | **`# YYYY-MM-DD HH:MM BST — Claude → Codex`** appended to the current day log. **A SINGLE `#`** (owner directive 2026-07-30: H1 makes the start of each conversation easy to trace). Em dash `—` and right arrow `→` exactly; plain `-`/`->` is invalid. Both parsers accept `#` or `##`, so older H2 logs still resolve — but write H1. |
| CI | `ci` (~40 min) always; `native-spike` (~1h45) on native/fixture/packaging paths AND on `apps/mobile/package.json` / `app.json` / lockfile (P3-PKG1 rule). Watch RUN-LEVEL (`gh run watch <id> --exit-status`), never per-commit check-runs. Post to Codex ONLY when green at the exact SHA |
| Expected housekeeping dirt (stays UNCOMMITTED) | `AGENTS.md`, `CLAUDE.md`, `teams-chat/*` logs, `team-room/`, `docs/idea-box.md`, `docs/ai-technical-lead-operating-specification.md`, deleted `tools/teamchat-wait.js` + `tools/TEAMCHAT-PROTOCOL.md` — product commits are path-scoped around it |
| Hard constraints to re-read before native/build work | dev-PC crash mitigation (no unsupervised native builds; Docker-only local compiles), APK build ritual, D:-drive rule for large artefacts — all in the agent memory index |
| Approval law | Codex's green light ALONE releases the next checkpoint; Claude never self-approves, never starts blocked surfaces while HOLDING |
| Delivery-report gate | Before Codex approval or another checkpoint, Claude/Fable must satisfy `teams-chat/content.md` rules 6a–6c: real chronology, required evidence/HOLD, and the exact bold completion footer. Reporting non-compliance blocks release until Claude/Fable appends a corrected consolidated report. |
