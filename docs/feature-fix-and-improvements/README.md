# Feature, Fix and Improvement intake

This folder is where PowerFlow work arrives. Bugs found while using the shell, features wanted,
and rough edges worth smoothing all get written down here first and picked up from here.

Two cumulative logs now exist. **Do not reset or clear either** until a copy has been made and
a reset is explicitly asked for — [powerflow_backlog(2).md](<powerflow_backlog(2).md>) carries
that instruction in its own footer.

| Log | Covers | State |
|---|---|---|
| [powerflow_backlog(1).md](<powerflow_backlog(1).md>) | the original 18 items | **all closed** — see the index below |
| [powerflow_backlog(2).md](<powerflow_backlog(2).md>) | 16 items, reset 2026-08-10 | **open** — see "Round 2" below |

> ### ⚠️ The two logs REUSE THE SAME IDs for different work
>
> Backlog (2) restarted numbering at `PF-FEAT-001`, so **six IDs now mean two different
> things**. `PF-FEAT-001` is `rn --chmod` in round 1 and *guarded VM destroy* in round 2;
> `PF-UX-001` is `pmx start <vm>` in round 1 and *`pmx list` aliases* in round 2.
>
> Everything below is therefore qualified **(b1)** or **(b2)**. An unqualified "PF-FEAT-003"
> in a commit message or a doc is ambiguous and should be treated as a bug in that text —
> which is not hypothetical: round 2''s PF-FEAT-003 assumes round 1''s PF-FEAT-003 (clone,
> shipped in v5.0.0) as its own Phase 1.

<!-- The angle brackets around the link target are required: a filename containing parentheses
     breaks markdown link parsing without them. The "(1)" looks like a browser download suffix —
     renaming the file to powerflow_backlog.md would remove the need, but it is the owner's file
     and the link works as-is. -->

> **Where things stand:** **20 of 20 closed — round 1 is finished.** (Was: PF-FEAT-001 and PF-FEAT-002, both
> unblocked by the flag convention, now done.) Each status below is verified against the
> current tree, not trusted from the report.
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

## Round 1 — all closed

IDs in this table are the **(b1)** numbering. Round 2 reuses the same numbers for different
work, so a bare `PF-FEAT-001` is ambiguous — see the warning at the top.

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
| 12 | PF-FEAT-001 | FEATURE | `rn --chmod <mode>` | **done** — applied to the NEW path and verified by reading it back (chmod can exit 0 and change nothing on a fixed-permission mount). A failed chmod does not roll the rename back. `tests/linux/perms-features.ps1` |
| 13 | PF-FEAT-002 | FEATURE | `ls --perms` | **done** — compact mode view, both notations, ⚠ only where earned (world-writable/setuid/setgid). Windows refuses rather than faking ACLs. `tests/linux/perms-features.ps1` |
| — | PF-FEAT-004 | FEATURE | Linux/VM identity + storage view in `pc-whoami` | **done** — `pc-whoami --system` adds hostname/OS/kernel/arch/virtualization (container reported distinct from VM); `--storage` DELEGATES to `storage report` rather than building a second storage view. `--educate` became universal in the process |
| — | PF-FEAT-005 | FEATURE | safe Linux hostname change with `/etc/hosts` sync | **done** — `pc-name` (alias `pc-hostname`). Previews both edits, backs `/etc/hosts` up, rewrites only the 127.x line naming this host, and verifies the new name resolves. Falls back to `hostname` + `/etc/hostname` where there is no systemd. `tests/linux/hostname-rename.ps1` |
| — | PF-BUG-006 | BUG | `srv <name>` echoes the typed password in cleartext | **fixed** — the Windows askpass helper never cleared `ENABLE_ECHO_INPUT`/`ENABLE_LINE_INPUT`; both are now cleared before the prompt and the original mode restored in `finally`. `tests/network/askpass-echo.ps1` |
| — | PF-BUG-007 | BUG | `swapon` "not recognized" under pwsh on Linux | **fixed** — `/usr/local/sbin`, `/usr/sbin`, `/sbin` appended when present. Found a second, worse bug on the way: `"$env:PATH:$dir"` was REPLACING PATH, not appending. `tests/linux/sbin-path.ps1` |
| — | PF-FEAT-006 | FEATURE | one grouped storage/memory diagnostic instead of five commands | **done** — `storage report`: volumes, memory, swap and disk layout, read-only and no sudo. Composed from adapters, so it needs neither procps nor lsblk to render the rest. `tests/linux/storage-report.ps1` |
| — | PF-FEAT-007 | FEATURE | `--educate` footer explaining the output in plain words | **done** — analogy then one line per element, after the output and opt-in. `components/shared/educate.ps1`; shape enforced by `tests/storage/storage-behaviour.ps1` |
| — | PF-UX-005 | UX | `git-rl` in an un-set-up project said "Release cancelled" | **fixed** — reports what is missing and points at `git-rl -h` (which asks before writing); bare `git-rl` writes nothing, the picker never opens. `tests/git/release-setup.ps1` |

PF-FEAT-004, PF-FEAT-005 and PF-BUG-006 were added after the implementation order was written
and are not in it yet.

---

## Round 2 — [powerflow_backlog(2).md](<powerflow_backlog(2).md>)

16 open items, read and assessed against the tree on 2026-08-18. **Sizes and "already exists"
were verified in code, not taken from the report** — the backlog predates `storage report`,
`--educate`, the flag convention and the `pdm`→`pman` rename, so several items are further
along than they claim and two are further behind.

| ID (b2) | Kind | What | Size | Assessment |
|---|---|---|---|---|
| PF-UX-002 | UX | picker cancellation reported as an error | **done** — `↩ Cancelled.`, dim, at the shared boundary (`Write-PmxResolveFailure`). All five outcomes distinguished; both pickers fixed; the disk picker no longer re-dumps the list after an Escape; `Test-PmxCanPick` names the interactivity rule that was inlined twice. `tests/proxmox/picker-cancellation.ps1` | ~~The cheapest real win here. Escape from a picker returns `Error = ''cancelled''`, which callers render as a failure. **Two pickers, not one** — the VM picker (`vm-read.ps1:80`) and a second disk picker; a fix at only the first leaves two of the item''s own listed tests failing~~ |
| PF-UX-001 | UX | `pmx list` / `pmx status` + typo suggestions | medium | Both targets already exist; the aliases are two `switch` cases in `command.ps1`. Typo suggestions are the new part, and must never auto-execute |
| PF-FEAT-008 | FEATURE | `pmx net` fleet view with SSH reachability | medium | Most of it exists — `Get-PmxVmNetworkModel` is already the single data path. New: the top-level route, the SSH column, and a primary-address choice |
| PF-FEAT-005 | FEATURE | `pman`/`dkr` logs refinement + readable `inspect` | medium | The spine is built: the `logs` verb, the log-command adapter, name resolution. New: timestamps by default, tail grammar, and the `inspect` view |
| PF-UX-003 | INVESTIGATE | word navigation / selection keys | medium | **Probably not PowerFlow''s bug.** It binds only `!` and `$` (`history.ps1:45,63`) and never sets `EditMode`, so `Ctrl+Left/Right` are PSReadLine defaults. Needs reproducing on the real terminal before any code |
| PF-FEAT-004 | FEATURE | `pman events` human time ranges | large | The wrapper exists (as `pman`). New: the `t@HH:MM`/`yd@` grammar and a backend doctor |
| PF-FEAT-002 | FEATURE | reboot/stop/reset, snapshot rollback/delete, suspend/resume, migrate, disk move | large | Nine commands. `Invoke-PmxVmLifecycleChange` is the extension point but is fenced by `[ValidateSet(''start'',''shutdown'')]`. Needs adapter operations on both platforms |
| PF-FEAT-001 | FEATURE | guarded VM destroy / `--purge` | large | Most of the safety chain exists (`Invoke-PmxAmberMutation`, audit, revalidation). **Four blockers below** |
| PF-FEAT-006 | FEATURE | `journal` — Linux timeline over journalctl | large | Only `Get-StabilityEvents` reads the journal today, and narrowly. Largely net-new |
| PF-FEAT-007 | FEATURE | `pman service` — Quadlet + rootless persistence | large | Net-new: zero hits for quadlet/linger/subuid anywhere. Mutating, so it needs the guarded-preview treatment |
| PF-FEAT-011 | FEATURE | `network dns` — status, split-DNS enrol, test, undo | large | Genuinely net-new; `nmcli`/`resolvectl` appear nowhere. The intent-first grammar (`nw dns wg-home use 192.168.8.30 for .test`) is the interesting part |
| PF-FEAT-012 | FEATURE | `network`/`nw`, `svc`, `sys` namespaces | large | ~35 subcommands. Net-new, and the single biggest surface in the file |
| PF-FEAT-013 | FEATURE | fill those namespaces (storage, procs, ports, packages, firewall, hardware, timers, users) | large | **Roughly a quarter already shipped** under other names — `sys storage` is `storage report`; `sys proc`/packages/users are partial. Depends on PF-FEAT-012 |
| PF-FEAT-003 | FEATURE | `server setup` — guided clone → identity → srv → role | large | **Its Phase 1 already shipped** as round 1''s PF-FEAT-003 (clone-and-configure, v5.0.0), and two fzf pickers it lists as missing already exist in `components/proxmox/` |
| PF-FEAT-010 | FEATURE | DNS server role inside `server setup` | large | Depends on PF-FEAT-003 and PF-FEAT-011 both existing first |
| PF-FEAT-009 | FEATURE | PMX SSH connection/session telemetry | large | Lowest value for the size. Needs a guest-exec path that does not exist, and guest-exec is a materially wider blast radius than the current read-only allow-list |

### Four things that need a decision before PF-FEAT-001 (destroy) can be built

Destroy is the most dangerous command in the file, so these are listed rather than guessed at:

1. **The grammar does not exist.** `Invoke-PmxVmCommand` reads `$Arguments[0]` as the *action*,
   so `pmx vm 103 destroy` answers *"Unknown VM action ''103''"*. The backlog''s object-first
   form is a router-wide change affecting ~20 subcommands. Action-first (`pmx vm destroy 103`)
   needs no change at all.
2. **"No picker" contradicts a written house rule.** `Resolve-PmxManagedVm` opens an fzf picker
   on any empty selector *by design*, and its own comment calls refusing-where-a-picker-would-do
   "the house anti-pattern". Destroy wants the opposite. That is a deliberate exception, and the
   owner''s call.
3. **There is no RED confirmation primitive.** `Confirm-PmxAmberPlan` is hardwired to
   `[y/N]`. Typing the VM name back needs either a new primitive or a `-Confirm` scriptblock on
   the amber harness.
4. **The disk preview would UNDER-REPORT.** `Get-PmxVirtualDisksFromConfig` matches only
   `^(ide|sata|scsi|virtio)\d+$`, so `efidisk0`, `tpmstate0` and `unused0..N` are invisible —
   and the backlog''s own example preview lists `efidisk0`. A destroy preview that under-states
   what it deletes is wrong in the one direction such a preview must never be wrong.

### Stale wording to fix in the file itself

- **`pdm` is now `pman`** (PF-FEAT-004, 005, 007 and the command matrix). `pdm` is a widely used
  Python package manager; the rename shipped in v5.0.0.
- The matrix''s flag principle — *"Long PowerFlow word flags use `--word`"* — already matches
  the adopted convention ([ETHOS.md](../plan/ethos/ETHOS.md)), so nothing there needs changing.

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

**RESOLVED — this section is kept as the diagnostic record.** The root cause was the 2000-char
stdout truncation in `ConvertTo-PmxManagementSafeText`, which cut single-line `pvesh` JSON
mid-token; the payload limit is now 1 MiB and diagnostics keep the 2000-char cap. No evidence
run is needed. What follows is what was ruled out on the way there, because the eliminations are
worth keeping.

The original request read: the root cause is not found yet, and it cannot be from here — Two
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