# Feature, Fix and Improvement intake

This folder is where PowerFlow work arrives. Bugs found while using the shell, features wanted,
and rough edges worth smoothing all get written down here first and picked up from here.

[powerflow_backlog(1).md](<powerflow_backlog(1).md>) is the cumulative log. **Do not reset or
clear it** until a copy has been made and a reset is explicitly asked for.

<!-- The angle brackets around the link target are required: a filename containing parentheses
     breaks markdown link parsing without them. The "(1)" looks like a browser download suffix —
     renaming the file to powerflow_backlog.md would remove the need, but it is the owner's file
     and the link works as-is. -->

> **Where things stand:** 14 of 17 closed. Two remain gated on the flag convention
> (PF-FEAT-001, PF-FEAT-002), and PF-BUG-006 is newly filed with a root cause but not yet fixed.
> Each status below is verified against the current tree, not trusted from the report.
>
> **Three of the reported items collapsed into fewer defects than were filed.** PF-BUG-005 and
> PF-BUG-001 were the *same* defect in two dimensions — a mandatory parameter rejecting a
> deliberately-empty value at a dispatch boundary, while the function body already handled the
> case correctly (an empty *string* and an empty *array*). PF-BUG-002 and PF-BUG-004 were also
> one cause: `ConvertTo-PmxManagementSafeText` truncated every stdout line at 2000 characters,
> which cut single-line `pvesh` JSON mid-token. And PF-BUG-003 was PF-BUG-001 seen from another
> angle. Conversely PF-BUG-001 was *three* commands, not the one reported.
>
> The lesson worth keeping: a bug report describes a symptom at one call site. The count of
> reports is not the count of defects, in either direction.

---

## How to add an item

Append a section to the backlog. Minimum useful report:

```markdown
## PF-BUG-0NN — one line, what is wrong

### Reproduction
`the exact command you typed`

### Actual result
the exact output, pasted, including the error and its file:line

### Expected behaviour
what you thought would happen
```

Two things make a report dramatically cheaper to fix, and both come from the existing entries
being good at them:

**Paste the raw error with its file and line.** `Confirm-PmxAmberPlan: .../vm-change.ps1:67 —
Cannot bind argument to parameter 'NativeCommand' because it is an empty string` located
PF-BUG-005 immediately. A paraphrase would not have.

**Add the native control case.** Several entries show the equivalent `qm` or `docker` command
succeeding. That single line separates "PowerFlow is broken" from "the host is broken", which is
otherwise the most expensive question to answer.

An ID is not required when filing — the next free number in sequence is fine, and it can be
renumbered later. Getting the report down beats formatting it.

## Status key

| Kind | Meaning |
|---|---|
| **BUG** | behaviour is broken, or contradicts the documented command contract |
| **UX** | works as designed, but a clearer or more convenient route should exist |
| **FEATURE** | additive capability |
| **INVESTIGATE** | evidence strongly suggests a defect, but the failing layer needs instrumentation |

---

## Index

Ordered by the backlog's own **Suggested implementation order**, not by ID. Status is as of the
last pass over the tree — items are verified against the current code rather than trusted from
the report, because the tree moves and a report can go stale.

| # | ID | Kind | What | Status |
|---|---|---|---|---|
| 1 | PF-BUG-005 | BUG | guarded PMX mutations fail when native display is hidden | **fixed** — `[AllowEmptyString()]`; regression at `tests/proxmox/native-display-contract.ps1` |
| 2 | PF-BUG-001 | BUG | `pmx disk list` leaks a raw empty-array binding exception | **fixed** — was 3 sites, not 1: `pmx disk list`, `pmx vm show`, `pmx vm start`/`shutdown`. `[AllowEmptyCollection()]`; class-wide regression at `tests/proxmox/dispatch-boundary.ps1` |
| 3 | PF-BUG-002 | BUG | `pmx disk list --vm <vm> --table` reports malformed JSON for a valid VM | **fixed** — same cause as PF-BUG-004: the 2000-char stdout truncation. Payload limit raised to 1 MiB; diagnostics keep the 2000-char cap. `tests/proxmox/payload-integrity.ps1` |
| 4 | PF-BUG-004 | BUG | network commands fail the runtime-status read for running VMs | **fixed** — inventory status and runtime status separated; a *display string* no longer gates whether the agent is queried. `tests/proxmox/status-sources.ps1` |
| 5 | PF-BUG-003 | BUG | VM target resolution changes when output flags are present | **fixed** — was PF-BUG-001 from another angle. Invariant locked with the report's own 12-case matrix at `tests/proxmox/resolution-invariance.ps1` |
| 6 | PF-UX-003 | UX | guest-agent state is ambiguous (`unavailable` vs `not-requested`) | **fixed** — four distinct states (`not-configured`, `not-responding`, `query-failed`, `unknown`), each carrying a Reason the view prints. `tests/proxmox/agent-states.ps1` |
| 7 | PF-INVESTIGATE-001 | INVESTIGATE | centralize managed-command response parsing and diagnostics | **closed** — one reporter (`Write-PmxQueryFailure`) in `shared.ps1`, six sites rerouted; wrappers no longer drop `Diagnostics`. `tests/proxmox/response-boundary.ps1` |
| 8 | PF-UX-004 | UX | `pmx vm config` route + targeted hint for `pmx config <vmid>` | **fixed** — alias added without letting `config` reinterpret the namespace. `tests/proxmox/vm-config-route.ps1` |
| 9 | PF-UX-002 | UX | `pmx vm disks [vm]` | **fixed** — routed to the canonical function, so it inherits the picker rather than duplicating it |
| 10 | PF-UX-001 | UX | top-level lifecycle aliases (`pmx start <vm>`) | **fixed** — through the identical guarded path, not a shortcut around it. `tests/proxmox/convenience-routes.ps1` |
| 11 | PF-FEAT-003 | FEATURE | clone-and-configure a VM in one guarded workflow | **done** — validated before anything is created, one confirmation covers the whole sequence, and a partial failure keeps the VM and prints the remaining commands. `tests/proxmox/clone-configure.ps1` |
| 12 | PF-FEAT-001 | FEATURE | `rn --chmod <mode>` | open — unblocked now the convention is `--long`; still sequence with the `rn` rename |
| 13 | PF-FEAT-002 | FEATURE | `ls --perms` | open — unblocked now the convention is `--long` |
| — | PF-FEAT-004 | FEATURE | Linux/VM identity + storage view in `pc-whoami` | open — overlaps `storage`, see below |
| — | PF-FEAT-005 | FEATURE | safe Linux hostname change with `/etc/hosts` sync | open |
| — | PF-BUG-006 | BUG | `srv <name>` echoes the typed password in cleartext | open — **root cause found**, see below |
| — | PF-UX-005 | UX | `git-rl` in an un-set-up project said "Release cancelled" | **fixed** — reports what is missing and points at `git-rl -h` (which asks before writing); bare `git-rl` writes nothing, the picker never opens. `tests/git/release-setup.ps1` |

PF-FEAT-004, PF-FEAT-005 and PF-BUG-006 were added after the implementation order was written
and are not in it yet.

---

## Cross-references this folder should not lose sight of

Three pieces of work outside this folder change what some of these items should look like. They
are recorded here so an item does not get built twice or built against a convention that is
about to change.

**The flag ethos is decided: `-x` short, `--word` long.** The owner chose Option A
(GNU-strict) — see [docs/plan/ethos/ETHOS.md](../plan/ethos/ETHOS.md). **PF-FEAT-001
(`rn --chmod`) and PF-FEAT-002 (`ls --perms`) are unblocked**: both are written with `--long`,
which is now the house rule. `ls` is hand-parsed and takes it directly; `rn` has a `param()`
block, so its flag must route through `Invoke-PFParamCommand`
(`components/shared/flags.ps1`) — a bare `param()` block cannot bind `--word` and misbinds it
into the next value parameter.

**`rn` is proposed for rename.** The naming audit finds `rn` is one edit from `rm` and
recommends `rename-file`. PF-FEAT-001 adds a flag to `rn`, so the two should be sequenced
together rather than shipping a new flag on a name that is about to change.

**`storage` already exists and overlaps PF-FEAT-004.** A `storage` command was built with real
volume enumeration — every drive or mount with size and free space, and a pseudo-filesystem
filter so a Linux mount list is not buried in snap loopbacks and per-session tmpfs. PF-FEAT-004
asks `pc-whoami` for a Linux identity *and* storage view, and its "do not dump
pseudo-filesystems by default" requirement is already implemented in
`Get-StorageVolume`. The honest question is whether PF-FEAT-004 should call `storage` rather
than reimplement it, leaving `pc-whoami` to own identity only.

**Some backlog entries name symbols that no longer exist.** The container adapter was renamed
`*-Docker*` → `*-Container*`, `components/docker/dkr.ps1` became
`components/containers/containers.ps1`, and `dkr` gained a sibling `pman` for podman (`pdm` was
the first spelling and was dropped — it is the name of a widely used Python package manager).
When a report cites a symbol that is gone, the code is the authority, not the report.

---

## PF-BUG-006 — `srv <name>` echoes the typed password in cleartext

**Severity: this is a credential exposure, not a cosmetic defect.** The password is written to
the terminal, which means it is also in scrollback, in any screen recording or screenshot, and
in the buffer of a shared or recorded session. Reported from a real connection.

Observed:

```text
❯ srv web-prod
Password for 'web-prod': hunter2
********
```

Both lines are real. The first is the console echoing the keystrokes; the second is PowerFlow's
own masking, written *after* the fact.

**Root cause — `platform/windows/helpers/powerflow-ssh-askpass.cs`.** The helper opens `CONIN$`
and reads with `ReadConsole`, but it never calls `SetConsoleMode` to clear the input flags. A
Windows console handle arrives with `ENABLE_ECHO_INPUT` and `ENABLE_LINE_INPUT` **on** by
default, so:

1. `ENABLE_ECHO_INPUT` makes the console print each character as it is typed — the cleartext.
2. `ENABLE_LINE_INPUT` makes `ReadConsole` block until Enter, so the helper's per-character
   `*` writes all arrive afterwards — which is why the asterisks land on their own line
   instead of replacing the typing.

The two flags together explain the output exactly, including its shape.

**The Linux sibling is correct and is the model for the fix.**
`platform/linux/helpers/powerflow-ssh-askpass.sh` saves the terminal state with `stty -g`,
clears echo with `stty -echo`, and restores the saved state from an `EXIT HUP INT TERM` trap. The
Windows helper needs the same three properties: read the current mode, clear
`ENABLE_ECHO_INPUT | ENABLE_LINE_INPUT`, and **restore the original mode in a `finally`** — a
helper that exits leaving echo disabled would hand back a terminal that appears dead.

Worth noting *why* this escaped review: the helper does mask, visibly and per character, so the
code reads as though it handles the secret carefully. The defect is not a missing feature but an
unstated assumption — that a console handle starts in raw mode. It does not.

**Regression test.** The mode manipulation cannot be exercised without a real console, so the
test asserts on the source: that the helper clears both flags, and that it restores the saved
mode on every exit path. That is weaker than a behavioural test and should say so where it
lives.

---

## PF-BUG-002 — what is needed from you

The root cause is **not** found yet, and it cannot be from here: it needs a live Proxmox. Two
of the report's own hypotheses were ruled out first, so the search is narrower now.

**Ruled out — the invocation parser.** `Get-PmxReadInvocation` was run over `--vm 102`,
`--vm 102 --table`, `--table`, `102 --table` and `--table --vm 102`. Every case consumed
`--table` as a switch and resolved the selector to `102`, with clean positionals. So an output
flag does not influence the request, which was the report's leading hypothesis.

**Already fixed — the CD-ROM complaint.** `disk-model.ps1:40` skips `media=cdrom` and
`cloudinit`, so `ide2: none,media=cdrom` is not offered as a growable disk.

**What changed instead.** The error used to collapse eight distinct failures into one sentence,
which is why the bug could be reproduced but not diagnosed. Now:

- the parser tries a strict parse first, and only then attempts to salvage a document with
  leading noise — and when it salvages, it **says so** rather than hiding it, because silently
  accepting contamination would turn a reportable defect into a permanent mystery
- each failure class gets a distinct message: `empty response`, `no JSON document`,
  `malformed`, or `stripped N leading characters`
- scrubbed evidence rides along on the result and prints under `--explain`

So please run:

```powershell
pmx disk list --vm 102 --table --explain
```

and paste the `EVIDENCE` block. It reports the command class, transport (`local` or `ssh`),
exit code, stdout/stderr byte counts, whether the payload even starts with `{` or `[`, and a
preview of what actually arrived. That distinguishes a banner ahead of the JSON from native
text from an empty response — which is the whole question.

Every previewed byte passes through `Protect-PmxDiagnosticText` first, so addresses,
`user@host` and tokens are redacted before display. That is asserted by
`tests/proxmox/parse-diagnostics.ps1` against deliberately hostile input, because a payload
preview is exactly where an endpoint would otherwise escape PowerFlow's alias-only contract.

It is possible the salvage path alone fixes it — if the failure was a banner ahead of the
payload, `pmx disk list` may simply work now, and report that it stripped something. That is
still worth telling me, because the banner should not be there in the first place.