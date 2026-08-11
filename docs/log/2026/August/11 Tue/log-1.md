# 11 Aug 2026 — one flag convention, and `components/` stops claiming coreutil names

Three decisions from the owner, and the work that followed each. Plus one bug filed with a root
cause, and two release gates that turned out not to exist.

---

## 1 · `pdm` → `pman`

`pdm` is a widely used Python package manager. A shell that shadows it is a poor guest on any
machine doing Python work. 35 occurrences, one blanket rename, 707 container assertions still
green.

---

## 2 · The flag convention: `-x` short, `--word` long

**Decided:** Option A (GNU-strict) from `docs/plan/ethos/DECISIONS.md` Part 2 — *not* the
recommended Option E. Written up as [ETHOS.md](../../../plan/ethos/ETHOS.md).

A short form is **one or two letters**, because that is how it was asked for (`-s`/`--short`,
`-sh`/`--short-hand`). Two letters is load-bearing rather than a loophole: it makes the GNU
bundles (`-rf`, `-la`) and native pass-throughs (`du -sh`) fall out of the rule instead of
needing an exception each.

### What the audit had measured

- `help` had **four spellings** across seven commands; only `pmx` took all four. `pwsh-h --help`
  printed *"Nothing called '--help'"* — from the command whose entire job is help.
- `-f` meant three things: force, *follow*, and "a filename follows".
- "Skip the prompt" had **six spellings, two silently ignored**.
- `-v` was accepted by nine commands, meant four things, and in two meant nothing.
- **54 of 301 dashed tokens were never implemented.**

### The fact that shaped the implementation

A `param()` block cannot bind `--word`. It does not merely ignore it — it **misbinds** it:

```powershell
function T { param([switch]$Force, [string]$Name) }
T --force      #  Force=False, Name='--force'
T --name bob   #  Name='--name',  and 'bob' falls into $args
```

`[Alias('-force')]` was tested as a cheaper route. It does not work either.

The audit had costed Option A at "five commands must become hand-parsers". That would have
destroyed case-insensitivity and prefix matching — `-Stat`, `-status`, `-STATUS` all stop
working — and made every parser reimplement the forgiveness `param()` gives free. So the
spelling is translated **at the door** by `Invoke-PFParamCommand`, and each implementation keeps
its `param()` block untouched. **Twelve one-line shims instead of twelve rewrites.**

### Three things that cost real debugging time

Recorded because none is obvious and each looked like working code:

1. **Splatting an array passes everything POSITIONALLY.** `& $cmd @($array)` hands the callee one
   collection; a rewritten `-Status` arrives as a string value, not a parameter name. Named
   binding needs a **hashtable** splat — which is why the parser must know which flags take a
   value, which is why it reads the target's parameter *types*.
2. **Interpolating a `[Type]` yields its accelerator.** `"$([switch])"` is `switch`, so
   `-match 'SwitchParameter'` is always false and every switch is mistaken for a value
   parameter. Compare `ParameterType -eq [switch]`.
3. **A `param()`-typed variable coerces on reassignment.** `$targetCmd = Get-Command $Target` was
   first written `$target = ...`; PowerShell names are case-insensitive, so it hit the same
   variable, and `[string]$Target`'s type constraint silently converted the `CommandInfo` back to
   a string. Every flag then read as unknown. Same family as the automatic-variable rule the
   release gate already enforces.

### Also delivered

`--flag` typos are now **refused with a suggestion**, never dropped — DECISIONS 1.4 fixed
generally rather than in one command. The suggestion handles **transpositions**, which needed
their own case: `stauts` → `status` differs in *two* positions, so an "at most one difference"
test misses the most common typo there is.

71 published spellings swept out of help text, because help is how a convention propagates —
teaching the retired spelling and then warning about it is worse than not migrating.

---

## 3 · `components/` claims no GNU coreutil name, and Linux needs no bindings file

**The old arrangement was backwards.** `components/` defined `rm`, `mv`, `cp`, `cat`, `mkdir`,
`touch`; `platform/linux/bindings.ps1` then unpicked every one. Shadowing created
unconditionally, undone conditionally — so anything that stopped the undo from running left a
Linux user with an `rm` that did something else. That file's own header recorded the bug shipping
once already.

Now: **`del`** and **`mvf`** are the names on every platform. They are not clones — `del` opens a
picker and confirms, `mvf` with one argument *cuts* — so borrowing `rm`/`mv` meant reflexes
silently getting different behaviour. Both report the name they were **invoked** as, so `rm -rf x`
on Windows says `rm:` and `del -rf x` says `del:`.

- `mkdir` / `touch` / `rmdir` → `windows-only/coreutils.ps1`. Windows ships none of the three.
- `cat` / `cp` → **deleted**. PowerShell already provides both on Windows, so they added nothing
  there while hiding the real tools on Linux.
- `platform/linux/bindings.ps1` → **deleted**. Adding names is now the only operation.

One regression caught only by loading the real profile: `rmdir` is a built-in **alias**, and an
alias outranks a function, so the moved function was unreachable until the alias was cleared.
Static assertions would not have found it.

---

## 4 · Pruned: `git-a-plus`, `git-aa`, `git-aq`, `git-ad`, `git-am`

228 lines. Unused, on the owner's word: *"git-a is enough, those other ones have never been
used."* What goes with them is `--dry-run` and `--amend-last`; both can return as flags on `git-a`.

This also **closes DECISIONS 1.3 by deletion.** `git-a-plus -a` bound to `-AmendLast` by prefix
match and rewrote the last commit behind nothing but an fzf message box. The fix had been to
declare a second A-parameter so `-a` errors as ambiguous — a guard that looks like a redundant
switch and could be removed by anyone who did not know why it was there. A deleted command cannot
be mis-bound at all, so the test now asserts absence rather than the guard.

---

## 5 · Two release gates that did not exist, and one that lied

**`CLAUDE.md` documented a Linux CI job** asserting that `rm`/`mv`/`cat`/`grep` resolve to native
binaries. There is no such job — the workflow has only ever had one, on `windows-latest`. So the
only thing protecting Linux from coreutil shadowing was the bindings file itself, unverified.
Two static gates now exist instead.

**The local gate script was a hand-written copy** of the CI checks, and had drifted five adapter
names out of date — it reported "clean" on a tree the real gate would reject. `tests/gates.ps1`
now parses `release-validate.yml` and runs the real steps. It immediately caught `dkr` and `pman`
failing the help-registry gate: registrations built from a **loop variable** are invisible to a
regex looking for `-Name '<literal>'`, so both commands counted as defined-but-unregistered.

**The adapter-parity gate is no longer hand-maintained.** It matched component calls against a
hardcoded list of ~120 names, and `Get-ContainerMachines` / `Resolve-ContainerConnectionMachine`
were called from `components/` and absent from it. The release checklist even carries an incident
note saying the list is not automatic — the failure mode was known, documented, and happened
anyway, because it relies on a human remembering. The gate now **derives** the contract: adapter
functions that `components/` actually calls. It also fails on a Verb-Noun call that resolves
nowhere, which is the class that produced an invented `Format-PmxIecBytes` earlier in this batch.

---

## 6 · Filed: PF-BUG-006 — `srv` echoes the typed password in cleartext

Reported from a real connection, with the password visible on screen and therefore in scrollback.

Root cause found: `platform/windows/helpers/powerflow-ssh-askpass.cs` opens `CONIN$` and calls
`ReadConsole` **without clearing `ENABLE_ECHO_INPUT`**. A Windows console handle arrives with echo
and line-input on, so the console prints each keystroke, and `ReadConsole` blocks until Enter —
which is why the asterisks land on their own line instead of replacing the typing. Both observed
lines are explained exactly.

The Linux sibling is correct and is the model: `stty -g` to save, `stty -echo`, restore from an
`EXIT HUP INT TERM` trap. Not fixed yet — queued at the owner's request.

---

## Test and gate state

| | |
|---|---|
| Suites | files · flags · safety · containers · storage · proxmox · network · windows — **all green** |
| Gates | 7 runnable, all green (4 skipped locally: they need GitHub's expression context) |
| New this session | `tests/flags/` (56 assertions), `tests/files/command-names.ps1` (39), `tests/gates.ps1` |

**Not done, and it matters for the release:** the checklist's §2 Linux-in-Docker leg
(install → load → exercise → uninstall) was not run. The coreutil change is precisely a
Linux-behaviour change, so that leg is the one most worth running before this ships.
