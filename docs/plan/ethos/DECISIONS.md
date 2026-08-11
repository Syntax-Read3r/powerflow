# Flag & Naming Ethos — Decision Sheet

**Read this one. Sign off on it.** The evidence lives in
[flag-uniformity-audit.md](flag-uniformity-audit.md) (2578 lines, 21 findings, 598 tokens) and
[naming-audit.md](naming-audit.md) (3337 lines, 16 findings, 201 command surfaces). Those are
references, not reviews. This is the review.

Every claim below was reproduced in a clean `pwsh -NoProfile` before it was written down. The
audit proposed 58 conflicts and **refuted 13**, so what follows survived an attempt to kill it.

The one number that governs everything: **45 single-dash words** (`-power`, `-status`, `-recurse`,
`-full`). That is the single token shape whose meaning *flips* depending on which half of the
codebase receives it — a `param()` block binds it as a parameter name, `Split-GnuArgs` shreds it
into letters. A second number worth knowing before you choose: **54 of 301 dashed tokens (18%)
were never authored by anyone.** PowerShell derives them from parameter prefixes, so no help text
can list them and users find them by typo.

---

## Part 1 · Seven safety fixes

These are **bugs, not style**. They are independent of whichever convention you pick, and each
can be fixed on its own. I would do these first regardless of Part 2 — each one causes data loss
or a silent wrong action.

### 1.1 · `rm -force <dir>` performs `rm -rf`

`Split-GnuArgs` explodes *any* single-dash token into characters
([operations.ps1:61](../../../components/files/operations.ps1#L61)). Measured on the real parser:

| typed | flags actually set | effect |
|---|---|---|
| `-force` | `c e f o r` | **recursive + force** |
| `-verbose` | `b e o r s v` | **recursive** |
| `-interactive` | `a c e i n r t v` | **recursive** (prompts, since `i` beats `f`) |
| `--force` | `f` | force only — correct |

The `r` in "fo**r**ce" is a recursive delete. Shared by `rm`, `mv`, `rmdir`, `touch`, `mkdir`.
Worst part: `ls` *teaches* single-dash words (`-recurse`) as the PowerFlow-friendly spelling, so
the style the tree teaches is the style that is unsafe here.

**Proposed fix.** In `Split-GnuArgs`, for a single-dash token of 2+ characters: if the word is in
the command's `LongMap`, use it; else if every character is a declared flag letter, bundle as
today; else refuse it by name and set nothing. `-rf` keeps working; `-force` starts meaning
force; `-verbose` stops deleting trees.

**Cost.** One function, ~8 lines. Strictly safer — no currently-correct invocation changes.

> **Decision:** ☐ fix now ☐ defer ☐ reject

### 1.2 · `git-bd` force-deletes; the safe version is unreachable

[branches.ps1:265](../../../components/git/branches.ps1#L265) defines `git-bd` (`git branch -d`,
refuses unmerged). [branches.ps1:286](../../../components/git/branches.ps1#L286) defines
`git-bD` (`git branch -D`, force). **PowerShell function names are case-insensitive**, so the
second silently replaces the first. Verified:

```
git-bd -> FORCE: deletes unmerged
git-bD -> FORCE: deletes unmerged
```

`git-bd` even prints "💡 Use git-bD to force delete unmerged branches" — advice from a function
that no longer exists. Losing an unmerged branch loses work.

**Proposed fix.** Rename the force variant so case is not the only difference. Two candidates:
`git-bd-force`, or `git-bd <branch> force` as a word (Option E below). Keep `git-bD` as an alias
only if it can coexist — it cannot today, which is the bug.

> **Decision:** ☐ `git-bd-force` ☐ `git-bd <branch> force` ☐ other: ______ ☐ defer

### 1.3 · `git-a-plus -a` rewrites the last commit

`param([switch]$Quick, [switch]$DryRun, [switch]$AmendLast)`
([commit.ps1:246](../../../components/git/commit.ps1#L246)). PowerShell binds unambiguous
**prefixes**, so `-a` → `-AmendLast`. Verified: `git-a-plus -a` → `AmendLast=True`.

`-a` is git's own "stage everything". Here it runs `git add .` then `git commit --amend`, with
only an fzf message box in between — escape it and you fall into `--amend --no-edit` with no
abort path, then get offered `git push --force-with-lease`.

Same mechanism, same file class: `srv -c lab` binds `$Command='lab'` and **opens an SSH session**
([servers.ps1:174](../../../components/network/servers.ps1#L174)); `history -c` errors demanding
a number where bash would clear history.

**Proposed fix.** Declare explicit one-letter parameters on the commands where a prefix is
dangerous, so `-a` binds something harmless or errors — or hand-parse them. Minimum viable: add
`[Alias()]`-blocked short names on `git-a-plus` and require `--amend` spelled out.

> **Decision:** ☐ fix now ☐ defer ☐ reject

### 1.4 · `pwsh-font --status` installs a font

`param([switch]$status)` ([fonts.ps1:29](../../../components/system/fonts.ps1#L29)). PowerShell
parses `--status` as a positional *value*, never as a parameter name — and because this is a simple
function with no `[CmdletBinding()]`, the token is silently collected into `$args` rather than
erroring. `$status` stays false, execution falls past the read-only branch, and reaches
`Install-NerdFont` at [fonts.ps1:51](../../../components/system/fonts.ps1#L51). Verified:

```
-status   -s   -stat   -Status   ->  READ-ONLY (reports status, installs nothing)
--status                         ->  FELL THROUGH -> would call Install-NerdFont
```

A GNU habit turns a read-only query into a write. Not destructive, but it is one instance of the
*general* class: **`--long` cannot bind on any of the 40 `param()` commands**, and what happens
instead depends on the function's shape — silently ignored, bound as a positional string, a
binding error, or (here) the wrong branch. This is the case where the wrong branch has a side
effect; the audit found five commands in the same shape.

**Proposed fix.** Two layers. *Narrow:* make the read-only path the default so falling through
cannot write. *General:* reject unrecognised `--` tokens instead of letting them vanish into
`$args` — that is Option C's gate doing real safety work rather than only documentation work.

> **Decision:** ☐ narrow fix only ☐ narrow + general ☐ defer

### 1.5 · Three commands advertise something safer than they do

`pwsh-h` is generated from the registry, so a wrong synopsis is a wrong manual. All three
verified by reading the body against its registration:

**`git-f`** — registered as *"fetch and fast-forward the current branch"*
([reset.ps1:45](../../../components/git/reset.ps1#L45)). The body:

```powershell
git reset --hard HEAD
git clean -fdx        # -x includes IGNORED files: .env, node_modules, local config
git fetch --all --prune
```

There **is** a confirmation prompt ("Flush all changes and clean repo?"), so it is not silent —
that matters and is why this is a synopsis fix rather than an emergency. But the name reads as
git's own `fetch`, the manual says fetch, and `clean -fdx` has **no reflog escape**: `reset
--hard` is recoverable, deleted untracked files are not. `.env` is the classic loss.

**`git-next`** — registered as *"jump forward one commit (walk history upward)"*
([reset.ps1:46](../../../components/git/reset.ps1#L46)). The body deletes `.next`,
`node_modules` and `package-lock.json`, then runs `npm install`. It makes no git call at all.
`git next` is also a **real command in `git-extras`** that does what the synopsis claims, so
anyone with git-extras installed is primed to expect the opposite behaviour.

**`git-sh`** — registered as a command with a synopsis that does not match its body
(naming audit §5.6).

**Proposed fix.** Correct the three synopses — one line each, no behaviour change, no naming
decision required. Retiring or renaming `git-f` and `git-next` is a separate, later question,
because it removes public names.

> **Decision:** ☐ fix the synopses now ☐ fix + schedule renames ☐ defer

### 1.6 · `pwsh-recovery` deletes your profile with no backup

Option 5 runs `Remove-Item $PROFILE -Force`
([recovery.ps1:72](../../../components/core/recovery.ps1#L72)) behind a y/n prompt, and takes no
copy. The **same file** already has a timestamped backup helper 50 lines further down
([recovery.ps1:122-124](../../../components/core/recovery.ps1#L122)):

```powershell
$backup = "$profilePath.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item $profilePath $backup -ErrorAction SilentlyContinue
```

A recovery tool is the one place that must never be the thing that loses the file.

**Proposed fix.** Call the existing backup before the delete. ~2 lines, reusing code already
present.

> **Decision:** ☐ fix now ☐ defer

### 1.7 · The CI help gate cannot see the `git-bd` bug class

The gate does `$defined = $defined | Sort-Object -Unique`, and both `Sort-Object -Unique` and
`-notin` are **case-insensitive** in PowerShell. Verified:

```
before:                    git-bd, git-bD, git-b   (3)
after Sort-Object -Unique: git-b,  git-bD          (2)
```

Two functions differing only in case collapse to one entry, so the gate is *structurally
incapable* of reporting 1.2 — or any future repeat of it. This is worth more than any single
rename: it converts a bug class into a build failure.

**Proposed fix.** Add a case-fold duplicate check (~6 lines) that fails the release when two
defined command names differ only by case.

> **Decision:** ☐ add the check ☐ defer

---

## Part 2 · The convention

### What the spread looks like

The five confirmed findings that most affect a user carrying one habit across the shell:

- **`help` has four spellings across seven commands** — `help`, `-h`, `--help`, `/?` — and only
  `pmx` accepts all four. `-h` works on pmx/dkr/storage, is **declared but dead** on `srv` (it
  opens the server picker instead), **errors** on `team-room`, and **hard-errors on `pwsh-h`** —
  the command whose entire job is help. `pwsh-h --help` prints *"Nothing called '--help'"*.
- **`-f` has three parse categories** — force (rm, mv, srv, git-rb, pf), *follow* (dkr, matching
  docker), and "a filename follows" (copy-file, where it is a prefix-match onto a value parameter
  and typing it alone is a binding error).
- **"Skip the prompt" has six spellings**, two of which are silently ignored.
- **`-v` is accepted by nine commands, means four things, and in two means nothing at all** —
  `rm -v` and `rmdir -v` are mapped and then never read. Anyone who confirms `mkdir -v` works
  will reasonably assume `rm -v` does.
- **18% of dashed tokens were never authored** (54 of 301), so they cannot appear in any help text.

Two facts constrain every option, and neither is negotiable:

1. **A `param()` block can never accept `--long`.** Any rule making `--long` canonical requires
   converting 40 commands to hand-parsers, or accepting that `--long` fails on them.
2. **A hand-parser gets no case-insensitivity or prefix matching for free.** Making hand-parsing
   universal means users lose `-Status` and `-st` where they work today, unless each parser
   reimplements the forgiveness.

| | Rule | Cost | Kills the hazards? |
|---|---|---|---|
| **A** GNU-strict | one dash = one letter; words always take two dashes | 45 tokens change, 13 of them *published*; `pc-whoami`, `git-a-plus`, `installed-apps`, `team-room`, `pwsh-h` must become hand-parsers | **Yes** — bundling becomes structurally impossible |
| **B** PowerShell-native | one dash + a word; `--long` accepted as an alias where hand-parsed | Cheapest — ratifies what 40 `param()` commands already do | Partly (needs a guard) |
| **C** Formalise status quo | each command declares its dialect; CI fails on docs/code drift | Zero renames, ~20 doc fixes + one CI gate | **No** for 1.1–1.3; **yes** for 1.4 if the gate also rejects unbindable `--` tokens |
| **D** Words, not flags | `rm force tree`, `pc-whoami power` | Largest; needs a reserved-word list per router | Yes, but relocates the memorisation |

**A and B point in opposite directions, and the tree already has a written rule.**
[listing.ps1:11](../../../components/files/listing.ps1#L11) says *"single dash belongs to Linux.
long dash belongs to PowerFlow"* — that is Option A. Option B inverts it. That contradiction is
the actual decision.

### My recommendation: E — split on whether the command impersonates a native tool

> **Rule:** a command that deliberately impersonates a native tool (`rm`, `mv`, `cp`, `cat`,
> `ls`, `mkdir`, `touch`, `rmdir`, and the 20 LEARN-LINUX brothers) is **GNU-strict**: one dash,
> one letter, and a multi-character single-dash token is refused by name. Everything else is
> **PowerShell-native**: single-dash words, `param()` where convenient, `--long` accepted as an
> alias where hand-parsed. Both halves get Option C's CI gate.

Why this over picking one globally:

- **It is already true.** The GNU-parsed commands exist to be GNU-compatible; the rest are
  PowerShell-shaped. E ratifies both instead of forcing one to lie.
- **It kills 1.1 exactly where the hazard lives** — refusing multi-character single-dash tokens
  in the file commands — without converting `pc-whoami` into `pc-whoami --power`, which is the
  least PowerShell-looking outcome of Option A.
- **The boundary is learnable in one sentence:** *"if the command is named after a Unix tool, it
  speaks Unix."* That is a rule a user can carry, which is what you asked for. Options A and B
  each ask half the shell to lie about what it is.
- **It keeps the written rule honest** rather than deleting it: `listing.ps1:11` stays correct
  *for the file commands it was written about*, and gets scoped rather than reversed.
- **It does not fix 1.4 by itself.** E decides what the canonical spelling *is*; it does not stop
  an unbindable `--status` from vanishing into `$args`. That needs Option C's gate too — which is
  why the recommendation is E **plus** C's gate, not E alone.

Cost: the 1.1 guard, plus C's CI gate, plus scoping the `listing.ps1:11` comment. It does **not**
require renaming the 13 published one-dash words, because they are all on the PowerShell side.

> **Decision:** ☑ **A — GNU-strict** ☐ B ☐ C ☐ D ☐ E ☐ other: ______
>
> **Chosen by the owner:** *"lets go with -s and --short or -sh/--short-hand meaning, you can fix
> that issue your self."* One dash for letters, two for words — Option A, not the recommended E.
> Written up as [ETHOS.md](ETHOS.md); implemented in
> [components/shared/flags.ps1](../../../components/shared/flags.ps1).

### What A cost, versus what the table above predicted

The table said *"45 tokens change, 13 of them published; five commands must become
hand-parsers."* The first half held. The second was avoidable, and the reason is worth keeping:

**`param()` does not merely fail to bind `--word` — it misbinds it.** Measured:

```powershell
function T { param([switch]$Force, [string]$Name) }
T --force      #  Force=False, Name='--force'
T --name bob   #  Name='--name',  and 'bob' falls into $args
```

So the flag lands in whichever value parameter is positionally next and displaces the real
value. `[Alias('-force')]` was tested as a cheaper route and does not work either.

But converting the twelve affected commands to hand-parsers would have destroyed
case-insensitivity and prefix matching — `-Stat`, `-status` and `-STATUS` all stop working, and
each parser reimplements the tolerance `param()` gives free. So the spelling is translated **at
the door** by `Invoke-PFParamCommand`, and the implementations keep their `param()` blocks
untouched. The cost fell from twelve rewrites to twelve one-line shims.

Two implementation facts that cost real debugging time, recorded so they are not rediscovered:

- **Splatting an array passes everything POSITIONALLY.** Rewriting tokens and splatting the
  array cannot work; named binding needs a *hashtable* splat, which is why the parser has to
  know which flags take a value.
- **Interpolating a `[Type]` yields its accelerator.** `"$([switch])"` is `switch`, so
  `-match 'SwitchParameter'` is always false. Compare `ParameterType -eq [switch]`.

### Also needed your call — resolved under the same delegation

- **Deprecation or hard break?** → **accept + note once per session.** Nothing is removed. The
  owner types these daily, so a per-invocation warning would be a tax on the person who asked
  for the change; a signpost that appears once teaches without nagging.
- **Should subcommands ever take a dashed form?** → **never.** A verb is a word: `srv list`,
  `pman stores volumes`. This is already what `dkr` and `storage` do.
- **`--show-native` everywhere?** → still open, and now cheap: it is a normal `--long` flag
  under the rule, so adding it anywhere is a registration plus a branch.

### One thing A does not fix by itself

A decides the *spelling*; it does not stop an unbindable token from vanishing into `$args`
(safety item 1.4 — `pwsh-font --status` installing a font). `Invoke-PFParamCommand` refuses
unknown flags outright and suggests the nearest real one, which is what actually closes it. That
was Option C's gate in a different form, and it was worth keeping.

---

## Part 3 · Naming

The naming audit finished: **201 command surfaces**, 73 proposals, **37 verified**. Of those
surfaces, **74 already sit under a noun with word verbs** (`dkr logs`, `srv list`, `nav roots`,
`pmx vm show`). Of the remaining 127, **20 are coreutil-constrained** and must not change,
leaving **107 that are decisions**. 53 cryptic names are fixable and **22 of them are in git
alone**.

It confirms your `i-a` question is already answered in your own tree — `storage apps` /
`storage big` exist and are untracked, so they are in-flight rather than shipped. Every other
proposal reuses that trick: the new noun is a router, the old function stays as its
implementation, so **no behaviour moves**.

On `storage -D -s`, it found the argument already settled in the codebase rather than by
preference: [storage.ps1:28-33](../../../components/system/storage.ps1#L28) rejects `-D` in
writing, and the third reason is a parser constraint, not taste — PowerShell binds unambiguous
prefixes, so `-D` cannot coexist with `-Detailed`/`-Depth`. That is the defect `pwsh-h` already
carries at [menu.ps1:41-46](../../../components/help/menu.ps1#L41). Reversing it stays open to
you, but it would contradict a decision already recorded in the tree.

### The staging it recommends

**Stage 0 — defects, no naming decision needed.** Nine edits. Overlaps 1.2, 1.5, 1.6 and 1.7
above, plus: `prev-t` registered as an alias of a different function; `pwsh-reminders`'
backslash path silently reverting on Linux; `here` advertising "quick actions" it does not have.

**Stage 1 — safe now: new canonical name, old name kept as an alias.** Minor bumps, cheapest
first: flip four inverted git registrations (zero behaviour change) · `rn` → `rename-file` ·
`here copy` / `here open` · `nav bookmarks add/rm/rename` · `path add` · a `tab` noun for the
seven tab commands · `git-rollback` · `gh-l org` / `gh-l auth` · `pc` · `config`.

`storage` is already in this stage and already written — it needs committing plus two tidy-ups.

**Stage 2 — needs a major version**, because a public name leaves the surface: retiring `git-f`,
`git-next`, `git-a-plus`, and `git-bD` (unavoidable — PowerShell cannot make that name
distinct), and dropping `rn`, which is what actually buys the safety in 5.4.

> **Decision:** ☐ approve Stage 0 wholesale ☐ Stage 0 + pick from Stage 1: ______ ☐ defer all

### Corrections it made to its own proposals

Worth noting, because it shows the verification did work: `set-path` is **not** a shape
violation (the CI gate classifies by case, and lowercase verb-hyphen is house style — the defect
is semantic); `rename` **cannot** be used as a name on Linux because it is a real binary absent
from `bindings.ps1`; `pc` **must** keep its `param()` block because `-min` is read through
`$PSBoundParameters`; and the code simplification promised by retiring `pc-whoami`'s flags is
deferred, possibly permanently, so it should be sold as consistency rather than deletion.

### One correction of mine

I earlier grouped `dirsize`, `diskfree` and `listdisks` into the storage cluster. They are
LEARN-LINUX "brothers" that forward to the real `du`, `df` and `lsblk`; the name-to-tool mapping
*is* their purpose. Leave them alone.

---

## What I have not done

**No existing command has been changed.** `dkr` and `storage` were built *to* the reference
style, but nothing was renamed or re-flagged, because the convention is yours to pick and a
half-applied convention is worse than a documented inconsistency.

Once you mark up Part 1 and Part 2, the work is mechanical and I will stage it: safety fixes
first as their own commit, then the convention, then naming.
