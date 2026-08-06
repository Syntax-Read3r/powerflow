# REINITIATE PROTOCOL ONE — resuming after a crash, restart or shutdown

> **Owner: you never need to explain a restart again.** One line is enough:
>
> > **"reinitiate"**  (or "PC restarted — reinitiate")
>
> That single word means everything in this file. Do not re-explain the project, the checkpoint,
> the CI state or what was in flight — the agent's job is to work all of that out from the repo,
> the chat log and its own memory before doing anything else.

---

## What this file is (and how it differs from `initiate.md`)

| File | Case it covers |
|---|---|
| `team-room/initiate.md` | The generic startup ritual — the ordered steps themselves (clock, state, day-roll, turn, wake task, repo/CI, watcher, report). |
| **this file** | The **RE**-initiate case: the machine died **mid-checkpoint**, with uncommitted work, armed watchers and possibly a running build. It layers the recovery realities on top of `initiate.md`. |

**Run `initiate.md` top-to-bottom first.** Everything below is the extra care a mid-flight restart
needs. Nothing here replaces a step there.

---

## The agent's contract on hearing "reinitiate"

1. Run `team-room/initiate.md` in order, and do not post to the chat before its day-roll and
   turn-state steps are done.
2. Recover the in-flight checkpoint (below) **before** starting anything new.
3. Report to the owner in a few lines: where the loop was, what survived, what is armed, what
   happens next. Lead with the outcome.

Never start a fresh checkpoint, a build, or a device proof during recovery. Restore the loop first.

---

## Recovery realities this project has actually hit

These are not hypotheticals; each one has cost time at least once.

### 0. The partner's wake task may be DISABLED — re-enable it, don't ask

**Owner directive, 2026-07-29:** "by me saying reinit protocol, that includes codex wake task."

A reboot, and specifically a BIOS/firmware update, can leave the partner's scheduled task **Disabled**
with its definition intact. It happened on 2026-07-29: the zavoya wake task read `Disabled` while the
other project's read `Ready`, so nothing would have woken Codex however correctly the post was filed.

Re-enabling is part of reinitiating, not a decision to escalate:

```
Enable-ScheduledTask -TaskName "TeamChat-Codex-zavoya"
```

Then verify `State=Ready` **and** a real `NextRunTime` — a disabled task can still display a stale
next-run time, so `State` is the field that decides. Only a genuinely **missing** task gets reported
instead of fixed, because recreating one means reconstructing its action, config path and trigger.

### 0a. ARM the wake connector — an enabled task is dormant until you do (owner directive, 2026-08-01)

The team room deliberately does NOT survive a shutdown: the connector refuses every tick with
`dormant-unarmed` until an arm stamp from the CURRENT boot session exists. Re-arming is this
protocol's job and nobody else's:

```
node team-room/bin/teamchat-codex-wake.js arm --by "reinit-<date>"
```

See `initiate.md` §5a for the verification. A reinitiate that re-enables the task but skips the arm
leaves Codex permanently asleep — the two steps are one unit.

### 0b. Check `--status` BEFORE arming the watcher (the reinitiate case is exactly the trap)

A reinitiate almost always lands while **it is your turn** — the partner released a checkpoint, the
machine went down, and that release is still the newest block. That is precisely the case where arming
the watcher blind used to deadlock: it baselines the unread message and waits for a newer one the
partner will never send.

```
node team-room/bin/teamchat-wait.js --status --me "Claude,Fable"
```

- **"FIRE now"** → process the message; do NOT arm and wait.
- **"WAIT"** → you are holding; arm it.

The tool now also carries a startup guard that delivers an already-waiting message rather than
baselining it, so it cannot strand the loop by itself. Ask `--status` anyway — arming a watcher that
will fire instantly for something you have already read is just noise.

### 1. Every background task is dead — and may report "failed"

Watchers, CI pollers, Metro, emulators and `run_in_background` shells do **not** survive. A watcher
that reports `failed` or `stopped` immediately after a restart **is the restart**, not a bug.
Re-arm everything from scratch, harness-tracked — never a shell `&`, which dies silently and never
wakes the agent.

### 2. Uncommitted work usually survives — verify, do not assume

`git status` is the source of truth for product files. Check that the checkpoint's in-flight edits
are all still present before continuing, and confirm the list matches what memory says was being
worked on.

### 3. `node_modules` survives, and that matters here

Patched dependency sources (the `patch-package` targets) live in `node_modules`, which is **not**
wiped by a restart. Confirm the patch markers are still in the patched files. If an `npm ci` ran
before the crash, they may have been reset — re-apply via `npm run postinstall` and re-verify.

### 4. The wall clock can move BACKWARDS across a restart

The RTC resyncs, so `date` can read a few minutes **earlier** than the last chat stamp already
written. Chat stamps must be monotonically increasing, or a post appears to precede the message it
answers. Compare against an external UTC reference (a recent CI run's `created_at`) and never stamp
a post at or before the previous block's time.

Also standing: use plain `date`. `TZ=Europe/London date` silently returns UTC here (no tz database),
one hour behind BST.

### 5. A build or CI run may have finished while the machine was off

Re-check the exact SHA rather than assuming. If a delivery was pending on green, complete that post
now — stamped with the CURRENT time, not the pre-crash time. If a run is still going, re-arm a
run-level watcher.

### 6. A long local build may have left a broken tree

If a Gradle or native build was interrupted, treat its outputs as suspect: sweep the interrupted
build's `.cxx`/`build` outputs before rebuilding. Do not commit anything produced by a build that
did not finish.

### 7. Do not sweep files you did not create

The working tree carries a standing set of unowned housekeeping changes (see the Project card in
`initiate.md`). Recovery never cleans those, and product commits stay path-scoped around them.

---

## The recovery checklist

- [ ] `initiate.md` run top-to-bottom (clock · state · day-roll · turn · wake task · repo/CI · watcher)
- [ ] Wall clock sanity-checked against an external UTC reference; next stamp will be later than the last block
- [ ] In-flight product edits present and matching memory
- [ ] Patched `node_modules` files still carry their markers
- [ ] Interrupted build outputs swept if a native/Gradle build was running
- [ ] Exact-SHA CI state re-checked; run-level watcher re-armed if anything is still running
- [ ] Partner's wake scheduled task verified `Ready` — **and RE-ENABLED if it reads `Disabled`** (§0)
- [ ] Wake connector ARMED for this boot session (§0a) — an enabled task without the arm stamp never wakes anyone
- [ ] `--status` asked BEFORE arming the watcher (§0b) — a waiting message is PROCESSED, not baselined
- [ ] Own chat watcher re-armed, harness-tracked (only when `--status` says WAIT)
- [ ] Short status reported to the owner

---

## What the owner may be asked for

Only things the agent genuinely cannot do itself — for example a billing or account block, an
approval that belongs to the lead, or a decision between materially different approaches. Anything
discoverable from the repo, the chat log or memory is the agent's job, not the owner's.
