# Command Naming — Audit and Options

**Status:** Evidence and options. One convention is recommended in §7, but nothing here is
decided. The owner names PowerFlow's commands.
**Date:** 2026-08-08
**Scope:** All 201 user-facing command surfaces in `components/`, `windows-only/`, plus the
adapter and CI surfaces a rename would touch.
**Method:** Every claim below was written, then attacked. Where a claim could be executed it
was executed in `pwsh -NoProfile` and corrected or dropped if it did not survive. Two claims
were verified at runtime rather than read (§5.1 and the `prev-t` registration in §5.9) and
are marked as such. Line numbers are the corrected ones.
**Where this sits.** [`DECISIONS.md`](DECISIONS.md) is the sign-off sheet;
[`flag-uniformity-audit.md`](flag-uniformity-audit.md) is the token-shape evidence. **This
document completes `DECISIONS.md` Part 3**, which currently reads "the naming audit is still
running" and lists five preliminary findings. All five are confirmed and expanded below:
`git-c.sb` (§9, Git), `close-t` vs `close-ct` (§5.9), `whoamifull` vs `pc-whoami` (§5.11), the
five coexisting families (§3), and the `i-a` answer (§4).

Two deliberate overlaps, so the owner is not handed two competing recommendations:

- **`git-bd`** is `DECISIONS.md` §1.2 *and* §5.1 here. Same defect, same fix, and it should be
  taken as a safety item on that sheet rather than waiting on any naming decision. §5.1 adds the
  runtime verification, the `Invoke-DeleteBranch` auto-escalation that the rename alone does not
  fix, and the case-fold CI gate that would close the whole bug class.
- **`pwsh-font --status`** is `DECISIONS.md` §1.4 and is folded into §5.12 here as
  `config font status`. If the safety fix lands first, §5.12 inherits it rather than redoing it.

`flag-uniformity-audit.md` overlaps in exactly one place — a flag that selects which program runs
is both a flag problem and a naming problem — and that overlap is where the two documents agree.

---

## 1 · What the owner asked

> *"what should `i-a` / `installed-apps` have been called? other functions need the same
> treatment. `dkr` is the style."*

Three requests, worth keeping apart because they have different answers:

1. **A specific name.** What should `installed-apps` have been? §4 answers that in full.
2. **A general rule.** "Other functions need the same treatment" only means something once
   the treatment is stated as a rule. §2 extracts one from `dkr`.
3. **A yardstick.** `dkr` is nominated as the model. §2 states what `dkr` actually embodies,
   because the useful part is not the three letters — it is the grammar underneath them.

The owner also floated `storage -D -s` in conversation. That form contradicts the model just
chosen, and §2.1 sets out why without pretending the question is settled.

---

## 2 · The reference, stated as a rule

`dkr` (`components/docker/dkr.ps1`) embodies one rule in four clauses:

> **A command is a NOUN the user already thinks in. What to do with that noun is a WORD after
> it. A flag may only MODIFY an action that has already been named — never choose which action
> runs. Where the target is ambiguous, offer a picker instead of an error.**

Each clause is visible in the source rather than inferred:

```powershell
# dkr.ps1:20-27
# CONVENIENCE IS THE POINT — nobody should have to remember flags. Anything `dkr` does
# can be printed as the real docker command with --show-native, so it teaches rather
# than hides.
#
# NO param() BLOCK — DO NOT ADD ONE
#
# PowerShell would bind `-a` and `-f` as PARAMETER NAMES and reject everything else,
# which is exactly the bug that had to be undone in nav. $args is hand-parsed instead.
```

The noun is `dkr`. The verbs `logs`, `shell`, `restart`, `stop`, `start`, `up`, `down` are
words, each registered as its own help row with a space in the name (`dkr.ps1:541-556`). The
four surviving flags — `-a/--all`, `-f/--follow`, `-y/--yes`, `--show-native` — are all
modifiers, paired short and long, and none of them changes which program runs. Ambiguity
opens a picker: `dkr stop` with no name offers the running containers, and `dkr start` with no
name inverts the pool to the *stopped* ones (`dkr.ps1:482`), because those are the only ones
you can start.

That is the whole yardstick. Two consequences follow that are easy to miss.

**The head noun must be a word, not the initials of a name.** `dkr` is a contraction of
`docker`, a noun the user already thinks in. `i-a` is not short for anything a user thinks; it
is the initials of a label PowerFlow chose. The test is not length — `pmx`, `srv`, `nav` and
`dkr` are all three or four characters and all pass, because each is a recognisable shortening
of a noun already in the user's head. `d-b`, `i-a`, `git-rb` and `gh-l` fail the same test at
the same length.

**A name with no verb slot cannot grow.** `installed-apps` is an adjective plus a noun with no
verb position, so the uninstall and delete actions it already performs have nowhere to live
and end up as digits in a numbered menu. `dkr` has a verb slot, which is why `dkr logs` could
be added without renaming anything. This is the structural reason the `i-a` question has an
answer at all: the problem is not that `i-a` is cryptic, it is that `installed-apps` is
grammatically full.

### 2.1 The tension: `storage -D -s` versus `storage big`

Under the rule above, `-D` (pick drive D:) and `-s` (summary instead of detail) are both
**selectors** — each chooses which of several screens runs — and the rule reserves flags for
modifiers. The consistent forms are `storage D:` and `storage big`: the volume is a positional
target, the view is a word.

This is not a matter of taste, and the strongest argument against the flag form was written by
the owner. `components/system/storage.ps1:28-33` already rejects `-D`, in the file's own
header, with three reasons:

```powershell
# WHY THE VOLUME IS POSITIONAL AND NOT `-D`
#
# A flag per drive letter is an unbounded set (-C -D -E -F …), which is exactly the
# "memorise flags" trap. It also cannot survive the port: Linux has no drive letters, so
# `-D` would have to mean something different there. And PowerShell resolves unambiguous
# parameter PREFIXES, so a `-D` switch silently competes with -Detailed and -Depth — the
# same class of collision as pwsh-h's [switch]$a / $advanced / $all.
```

The third reason is mechanical and decisive on its own: PowerShell binds unambiguous
*prefixes* of parameter names, so a `[switch]$D` cannot coexist with `-Detailed` or `-Depth`
in the same block without the short spelling becoming ambiguous. That is a parser constraint,
not a style objection — and it is the same defect `pwsh-h` already carries, where
`[switch]$a`, `$advanced` and `$all` are all declared and `-all` is then never read
(`components/help/menu.ps1:41-46`).

The honest statement of the tension: **the flag-shaped proposal is not merely inconsistent
with `dkr`, it is inconsistent with a decision already taken and documented in this
codebase.** If the owner wants the flag form after all, the right move is to reverse
`storage.ps1:28-33` explicitly and record why — not to add a second convention beside it.

One place already shows what letters-as-selectors cost at scale: `git-a-plus`, whose own
registered synopsis reads `'git-a with modes: -Quick, -DryRun, -AmendLast'`
(`commit.ps1:459`). §5.7 works through it. It is the closest thing the tree has to a preview
of the flag-selector style, and it is the strongest available evidence for the word form.

---

## 3 · The surface today

**74 of 201 command surfaces (37%) sit under a noun head with word verbs. 127 do not.** Of
those 127, twenty are coreutil names that must not change (§6), leaving **107 flat top-level
names that are naming decisions rather than constraints.**

The four disciplined families are `pmx` (44 surfaces), `nav` (14), `srv` (8) and `dkr` (8). A
fifth, `storage` (4 registered rows), is in-flight and untracked — see §4.

| Naming family | Count | Examples | Constrained? |
|---|---:|---|---|
| **noun + word verb** | 53 | `dkr logs`, `pmx disk grow`, `srv add`, `nav roots`, `pc-cap restore` | — this is the target shape |
| coreutil / shell-builtin name | 20 | `rm`, `mv`, `cat`, `ls`, `export`, `jobs`, `history` | **yes** — §6 |
| `squashed-words` | 29 | `changemode`, `lookupentry`, `listprocs`, `firstlines`, `whoamifull` | mostly teaching brothers — §6 |
| `prefixed-family` | 24 | `pwsh-config`, `pwsh-font`, `git-log`, `gh-l-org`, `powerflow-update` | no |
| `cryptic-suffix` | 22 | `git-f`, `git-rb`, `git-aq`, `git-bD`, `gh-l`, `mv-t` | no |
| `hyphen-abbreviated` | 14 | `open-nt`, `close-ct`, `next-t`, `nav create-b`, `copy-pwd` | no |
| other (bare nouns, punctuation, one-offs) | 39 | `pmx disks`, `here`, `..`, `~`, `git-c.sb`, `Get-PowerFlowVersion` | partly — `..`/`~` are idioms |

Guessability, scored as "could a user who knows the goal but not this tool find the name":

| | Count | Share |
|---|---:|---:|
| obvious | 98 | 49% |
| guessable | 48 | 24% |
| **cryptic** | **55** | **27%** |

Two of the 55 are deliberate and should stay: `z` (borrowed zoxide muscle memory,
`nav.ps1:361`) and `l` (alias of `lesson`, `lessons.ps1:722`). That leaves **53 fixable
cryptic names, and 22 of them are in one domain — git.**

The registry is smaller than the inventory: 136 `Register-PFCommand` rows, 136 unique names,
no duplicates. The gap between 201 surfaces and 136 rows is sub-verbs that dispatch inside a
`switch` and never received a help row — `nav cb`, `nav db`, `pmx vm nic`, `srv rename`. Those
are invisible in `pwsh-h` today, which matters for §5: several renames below make the surface
*more* discoverable even where behaviour is unchanged, because they add rows that should
already have existed.

### 3.1 Where one user noun wears several unrelated names

This is the pattern worth acting on, because it is the one a user actually collides with.

| The thing the user wants | Names it answers to | Files |
|---|---|---|
| where did my space go | `installed-apps`/`i-a`, `disk-big`/`d-b`, `dirsize`, `diskfree`, `listdisks` | `apps.ps1:268,343`; `brothers.ps1:165-167` |
| settings | `pwsh-config` (the OS), `pwsh-settings` (one JSON file), `pwsh-profile`, `pwsh-starship`, `pwsh-font`, `linux-lessons` | `sysconfig.ps1:45`; `config-files.ps1:12,21,32`; `fonts.ps1:28`; `teach.ps1:36` |
| a terminal tab | `open-nt`, `open-t`, `close-t`, `close-ct`, `next-t`, `prev-t`, `send-keys` | `tabs.ps1:17-54` |
| commit and push | `git-a`, `git-a-plus`, `git-aa`, `git-aq`, `git-ad`, `git-am` | `commit.ps1:11,244,452-455` |
| PowerFlow itself | `powerflow-version`, `Get-PowerFlowVersion`, `powerflow-update`, `powerflow-uninstall`, `pwsh-recovery`, `pwsh-reminders` | `version.ps1:152,223,259,265`; `recovery.ps1:19,97` |
| this folder | `here`, `copy-pwd`, `open-pwd`/`op` | `directory.ps1:21,230`; `clipboard.ps1:21,41` |
| my GitHub repos / my saved token | `gh-l`, `gh-l-org`, `gh-l-status`, `gh-l-reset` | `browser.ps1:111,367,381,395` |
| a bookmark | `nav b`, `nav cb`, `nav db`, `nav rb`, `nav list` | `nav.ps1:103-106,131` |

---

## 4 · The worked example: `i-a` / `installed-apps`

### 4.1 The answer, and where it already is

**`installed-apps` should have been `storage apps`. `i-a` should not have existed.** And the
codebase has already reached that conclusion: `components/system/storage.ps1` implements
exactly that surface today. It is **untracked** — `git status` reports `?? components/system/storage.ps1`
and `?? tests/storage/`, so it is in-flight work, not a shipped release — but it is written,
registered and tested, and `COMPONENTS.md:185` already documents it.

So the owner's question has a concrete answer with a concrete precedent, and the precedent is
his own:

```powershell
# storage.ps1:294-300 — four registered rows
Register-PFCommand -Name 'storage'        -Synopsis 'every volume, fullest first; a name drills into one'
Register-PFCommand -Name 'storage apps'   -Synopsis 'installed apps by size band'
Register-PFCommand -Name 'storage big'    -Synopsis 'large folders and files (vhdx, node_modules, caches)'
Register-PFCommand -Name 'storage docker' -Synopsis 'reclaimable container space'
```

And the dispatcher delegates rather than reimplements, which is why the migration cost is near
zero (`storage.ps1:264-278`):

```powershell
'apps'   {
    # Delegates rather than reimplements: installed-apps already owns the size-band
    # browser, and duplicating it would create two things to keep in step.
    if ($rest.Count) { installed-apps @rest } else { installed-apps -o }
    return
}
```

That delegation is the whole trick, and it generalises to every finding in §5: **the new name
is a router; the old function stays as its implementation.** No behaviour moves, so nothing
can regress.

### 4.2 The five-command spread it replaces

"Where did my space go" answers to five names in two files, across two `pwsh-h` sections:

| Command | File:line | What it answers | Section |
|---|---|---|---|
| `installed-apps` / `i-a` | `apps.ps1:268`, alias `:327` | installed programs ≥1 GB, by size band | 🗄️ DISK RECLAIM |
| `disk-big` / `d-b` | `apps.ps1:343`, alias `:328` | large folders and files that are not apps | 🗄️ DISK RECLAIM |
| `dirsize` | `brothers.ps1:165` | `du` — how big is this folder | 🎓 LEARN LINUX |
| `diskfree` | `brothers.ps1:166` | `df` — how much space is left | 🎓 LEARN LINUX |
| `listdisks` | `brothers.ps1:167` | `lsblk` — what drives exist | 🎓 LEARN LINUX |

Three of the five are in a section about *learning Linux*, so a user hunting disk space finds
two of the five and has no reason to think the other three exist. And none of the five could
answer the question that comes first — *which drive is full* — which is the gap
`storage.ps1:11-17` was written to close:

```powershell
# `installed-apps` and `disk-big` both answer "where did my space go", under two unrelated
# names — and NEITHER could answer the question that comes first: *which drive* is full.
# Get-DiskHotspot only ever returned system-drive locations ($env:LOCALAPPDATA,
# $env:ProgramFiles, $HOME\...), so on a machine with data drives everything but C: was
# invisible. Measured on the author's own box: four volumes, three of them unreachable,
# including a 1.8 TB external.
```

There is also a cross-reference that proves the tree already treats these as one topic:
`pc-whoami`'s low-disk warning hard-codes another command's name as its hint
(`health.ps1:196`):

```powershell
if ($pct -le 10) { $warn = "only $pct% free"; $hint = 'installed-apps 1gb-5gb' }
```

That string is a hard dependency between two findings. If `installed-apps` is retired, this
line prints a dead command; if `pc-whoami` becomes `pc` (§5.11) it must be edited anyway.
Sequence the two together.

### 4.3 The full proposed surface

```
storage                    every volume, fullest first
storage D:                 one volume in detail        (positional target, never -D)
storage /mnt/data          the same word on Linux — the reason it is not a drive-letter flag
storage apps               installed programs by size band     [was installed-apps]
storage apps 2gb-4gb       the band is a value, not a flag
storage big                large folders and files             [was disk-big]
storage big 50gb-200gb
storage docker             reclaimable container space
--show-native              print the real command                (modifier, dkr-style)
```

Two additions worth considering while the file is still uncommitted, because both remove a
flag-as-selector that `storage` currently inherits from its delegates:

- **`storage apps` bare should be the overview.** `installed-apps -o` / `-Overview` is a
  selector: it chooses the all-bands summary instead of the single-band browser
  (`apps.ps1:272`, `:281-296`). `storage.ps1:267` already passes `-o` when no band is given,
  so the behaviour is right and only the flag is left over. Retire `-o` as a public spelling
  and the last selector in this noun is gone.
- **`storage free` and `storage drives`** would absorb `diskfree` and `listdisks` as words.
  But those two are *teaching brothers* — their entire purpose is to print the real `df` and
  `lsblk` command they wrap — so folding them in would break the teaching contract. §6 treats
  them as constrained. The honest answer is that `storage` should not absorb them, and the
  five-way spread reduces to a three-way one, not a one-way one.

### 4.4 What breaks, and which aliases to retain

Almost nothing, because `storage` was built additively.

**Retain permanently: `installed-apps`, `i-a`, `disk-big`, `d-b`.** All four already keep
working — the registrations at `apps.ps1:570-571` are untouched and the verbs delegate to the
functions. `COMPONENTS.md:185` states this as a design commitment ("Nothing is renamed"), and
it is the right call: `i-a -o` is in the owner's fingers, and `installed-apps 1gb-5gb` is
printed to users by `health.ps1:196`.

Note the registration direction here is already **correct**, unlike git: `apps.ps1:570`
registers `-Name 'installed-apps' -Aliases @('i-a')`, so `pwsh-h` leads with the readable name
and shows the initialism inline. That is the pattern §5.5 asks the git family to adopt.

**The one real decision left:** whether `installed-apps` and `disk-big` keep their own
`pwsh-h` rows, or become `-Aliases` on the `storage apps` / `storage big` rows. Today they
have their own rows, so 🗄️ DISK RECLAIM shows six rows for four behaviours. Folding the old
names into `-Aliases` gives four rows with the old spellings rendered inline, which is what
`dkr shell` already does for `dkr sh` (`dkr.ps1:546`). That is a `pwsh-h` presentation change
with no behaviour change, and it is free.

**Doc surface:** `COMPONENTS.md:185` (already written), and `README.md`'s disk-reclaim table
plus `pwsh-h` are the only places the six-row surface is visible. `docs/features.md` does not
name any of the four.

---

## 5 · Findings

Sixteen findings, ordered by severity and then by blast radius — cheapest first within a
severity, because a high-severity finding with a one-line doc footprint should be fixed before
an expensive one.

Two of these are **live defects, not naming preferences**: §5.1 is a command that force-deletes
under the spelling documented as safe, and §5.2 is a destructive command whose help text
describes a different, harmless operation. Both are fixable today, independently of any naming
decision, and both should be.

### 5.1 `git-bd` / `git-bD` — a case-only distinction PowerShell cannot honour · HIGH

**Verified at runtime, not inferred.** Loading `branches.ps1` in `pwsh -NoProfile` with the
registry stubbed leaves exactly one function of that name, and its body is the force version:

```
git-b      ->  other
git-bd     ->  FORCE (-D)
git-branch ->  other
```

`components/git/branches.ps1:265` defines `git-bd` (`git branch -d`, safe) and `:286` defines
`git-bD` (`git branch -D`, force). PowerShell's function table is case-insensitive, so the
later definition silently wins the whole name. **The documented-safe spelling performs the
destructive action.** Its own failure hint at `:282` — "Use git-bD to force delete unmerged
branches" — points at a name that now resolves to the code the user just ran.

The registry compounds it: `:380` registers `-Name 'git-bd' -Aliases @('git-bD')` with the
synopsis `'delete a branch (bD forces)'`, so `pwsh-h` teaches a distinction that cannot exist.

**Proposed:** `git-bd <name>` performs the safe delete; force moves behind `-f`/`--force`,
which is the one legitimate use of a flag under the reference rule — a modifier on an action
already named. Delete `git-bD` outright.

**Two costs the rename alone does not pay.** First, `Invoke-DeleteBranch`
(`branches.ps1:221-227`) auto-escalates: `if ($isMerged) { git branch -d } else { git branch -D }`.
If the new safe path routes through it, `-f` is decorative and the defect survives under a
better name — it needs a `[switch]$Force` and the escalation must become conditional. Second,
`git-branch` has no `param()` block and drops straight into fzf, so a `-f` must be hand-parsed
from `$args`; a `param()` block would bind it as a parameter name, which is the trap already
recorded at `COMPONENTS.md:162` footnote 5 (`nav -srv complete` never reached the body).

**`git-bD` cannot be retained.** PowerShell's alias table is case-insensitive too, so
`Set-Alias git-bD` and `Set-Alias git-bd` are one entry. Anyone typing `git-bD` will land on
the safe command — a behaviour change in the safe direction, which is the correct way to fail,
but it must be announced. Put the new spelling in the failure path, where the user is
standing: `💡 add --force to delete an unmerged branch`.

**Migration cost — the smallest in the audit.** `COMPONENTS.md:171` is the *only* doc in the
repo that names either spelling; a full-tree grep returns six hits, all in `branches.ps1` and
that one row. `README.md` documents `git-b` (`:278`, `:482`) and never `git-bd`. Zero tests
reference either name. CI is unaffected — the help gate's `-CaseSensitive '^function ([a-z]...)'`
matches `git-bD` (leading `g` is lowercase), so the pair passes today; the gate never had a
chance to catch this, and `Sort-Object -Unique` is case-insensitive, so it cannot.

**Release class:** strictly a bugfix, but it silently changes what an existing invocation does,
so treat it as breaking (major) per `CLAUDE.md`. **Worth adding:** a structural CI check that
fails on any two functions in `components/` differing only by case — roughly six lines, and it
closes the whole bug class rather than this one instance.

### 5.2 `git-f` — help says "fetch and fast-forward"; the body destroys untracked files · HIGH

The full body, verified (`components/git/reset.ps1:11-22`):

```powershell
function git-f {
    $confirm = Read-Host "⚠️  Flush all changes and clean repo? (y/n)"
    if ($confirm -eq 'y') {
        Write-Host "🧹 Flushing..." -ForegroundColor Yellow
        git reset --hard HEAD        # Reset to last commit
        git clean -fdx              # Remove all untracked files and directories
        git fetch --all --prune     # Fetch latest and prune deleted branches
```

And the registration, four lines below (`reset.ps1:45`):

```powershell
Register-PFCommand -Name 'git-f' -Section '🎯 ENHANCED GIT WORKFLOW' -Synopsis 'fetch and fast-forward the current branch'
```

`git clean -fdx` deletes untracked **and ignored** files: `.env`, `node_modules`, build output,
local scratch. None of that is in the reflog. It never fast-forwards anything. A user who reads
`pwsh-h` and types it loses work that git cannot recover — so this is a data-loss defect in the
help system, not a naming preference.

The letter makes it worse: `f` reads as *fetch* or *force*, never *flush*, and `git-f` is one
edit from `git-a`, `git-b`, `git-l`, `git-p`, `git-r` and `git-s` — every casual command in the
family. Both the misread path and the typo path end in unrecoverable deletion.

**Proposed:** the fix is a split, not a rename, because the three operations differ in
recoverability and should not share one confirm:

```
git-discard              discard uncommitted changes to TRACKED files (list them, then confirm)
git-discard --untracked  additionally remove untracked files
git-discard --ignored    additionally remove ignored files — names .env / node_modules
                         explicitly and requires typing something back
```

Do **not** call the destructive form `--hard`. Real `git reset --hard` leaves untracked and
ignored files alone, so `--hard` would still hide the `clean -fdx` and would surprise a
git-literate user into losing `.env` — the same failure under a more respectable name.

Drop `git fetch --all --prune` from the body entirely. It is orthogonal to discarding, and it
is the only reason `f` was ever plausible.

**Do not keep `git-f` as a working alias.** The spelling *is* the hazard: the risk is a user
typing it believing it fetches. A stub that prints "git-f was renamed to git-discard — it
deletes untracked and ignored files, it does not fetch" and exits without acting is strictly
safer than a transparent forward.

**The synopsis fix is mandatory regardless of whether the name moves,** and it is one line.

**Migration cost: 2 code files, 1 doc line.** `reset.ps1` (header `:7`, function `:11`,
registration `:45`, prompt text `:12`) and `COMPONENTS.md:176`. `README.md`, `docs/features.md`,
`docs/`, `docs/log/` and `CHANGELOG.md` contain **zero** references — verified by unfiltered
grep. `Microsoft.PowerShell_profile.ps1:130` loads the file by path, not by function name, so
it needs no edit. No tests reference it, and no test asserts that the confirm prompt exists —
so a careless edit could remove the only guard silently. A `tests/git/reset.ps1` asserting
(a) the confirm fires without `-y` and (b) `--untracked` is required before `git clean` runs is
the honest cost of touching this function.

### 5.3 `git-next` — no git call in the body, and the synopsis describes a real, different command · HIGH

`components/git/reset.ps1:24-42`: a y/n prompt, then
`Remove-Item -Recurse -Force .next,node_modules,package-lock.json`, then `npm install`. There
is no `git` anywhere in it. Yet it lives in `components/git/reset.ps1`, is registered under the
git section, and `reset.ps1:46` reads:

```powershell
Register-PFCommand -Name 'git-next' -Section '🎯 ENHANCED GIT WORKFLOW' -Synopsis 'jump forward one commit (walk history upward)'
```

That synopsis is not merely wrong — it describes a command that exists in the wild. `git-extras`
ships `git next`, which walks history forward exactly as written. So a user who knows
`git-extras` types this expecting to move a commit and instead loses `node_modules` and a
tracked file: `package-lock.json` is deleted without the prompt saying so.

**Proposed:** `deps reset`, in a new file outside `components/git/`. Reject `node clean` — a
function named `node` would shadow the Node.js binary on both platforms, which is the same
class of bug §5.10 flags for `gh` and §6 flags for `service`. The synopsis must state the
destruction and the assumptions: the command hard-codes `.next` and `npm`, so it fits
Next.js-on-npm projects only.

**Do not retain `git-next` as a silent alias** — the `git-extras` collision is the reason for
the rename. If a grace period is wanted, keep it one release as a shim that prints the new name
and forwards, registered with the *corrected* synopsis so `pwsh-h` stops lying immediately.

**Migration cost: four occurrences of the string in the whole repo.** `reset.ps1:6` (the
header Purpose, which advertises "deep clean Next.js projects" inside a git-reset file), `:7`,
`:24`, `:46`, plus `COMPONENTS.md:176`. `README.md` and `docs/` have zero references.

Two non-obvious steps. **The component loader is a hand-maintained ordered array**, not a
folder scan (`Microsoft.PowerShell_profile.ps1`, `$_pf_components`) — a new file that is not
added to it simply never loads and the command silently does not exist. And
`$script:PF_HelpSections` (`components/help/registry.ps1:32-48`) has no node/deps section: add
one and map it into `$script:PF_HelpChapters` (a section left out of every chapter renders
under "MORE"), or park `deps reset` in the existing 🧱 PROJECT GENERATORS, which is a poor fit
since nothing is generated. This is the only judgement call in the migration.

**Fix `git-f`'s synopsis in the same commit** (§5.2). It is two lines away and equally false;
shipping one corrected synopsis beside an uncorrected one is worse than fixing neither.

### 5.4 `rn` is one edit from `rm` · HIGH

`components/files/rename.ps1:23` defines `rn` (rename); `components/files/operations.ps1:72`
defines `rm` (delete). Both accept a bare filename, both resolve fuzzy names, and both then act
on it — so a fat-fingered `rm` for `rn` goes straight to a delete prompt with no error to warn
you. This is the worst adjacency in the file domain.

Only one side can move: `rm` is a coreutil name kept deliberately by policy (§6).

**Proposed:** `rename-file <file> [newname]`, and specifically **not** `rename`. `rename` is a
real binary on Debian-family systems (util-linux and perl variants), and
`platform/linux/bindings.ps1` covers only `rm`, `mv`, `cp`, `cat`, `mkdir`, `touch`, `rmdir`,
`which` and `grep` — `rename` is absent, so a PowerShell function of that name would outrank
the native binary on Linux. That is exactly the shadowing bug `service` already has (§6), and
it must not be reproduced. Also unavailable: `ren` and `rni` are built-in `Rename-Item`
aliases.

**Retaining `rn` is what cancels the benefit.** The whole point is to increase the edit
distance from `rm`; an alias keeps the hazardous string alive. This is the one place in the
audit where I would argue against retention. If a short form is wanted, pick one that is not a
single keystroke from `rm`.

**Two things worth fixing while renaming**, both of which argue for `rename-path` over
`rename-file` if taken: `rn` filters directories out of its picker (`:37`, `:80`, `:85`), so
"rename this folder" has no command anywhere in PowerFlow; and it uses a hand-rolled numbered
`Read-Host` list for multiple matches (`:95`) where `ls`, `srv` and `rm` all use fzf, plus
fzf's `--print-query` over static help text as a text-input widget for the new name
(`:137-149`). Cost these separately — directory support also means fixing the two `$_.Length`
size formatters at `:46-48` and `:115-117`, which are null on a `DirectoryInfo`.

**Migration cost: 1 code file (5 lines), 3 docs (5 lines), zero tests.** `rename.ps1:7`, `:20`,
`:21`, `:23`, `:210`; `README.md:292-293` and `:497`; `COMPONENTS.md:167`;
`docs/migration/v3-upgrade.md:130` is a historical record and should be left. The *file* keeps
its name, so `docs/plan/linux/architecture.md:152` (which names the module, not the command)
needs no edit. No adapter or parity impact — the file calls only `Get-ChildItem`, `Get-Item`,
`Test-Path`, `Join-Path`, `Rename-Item` and fzf.

### 5.5 The git registry is inverted in six places · HIGH, and free

Every `git-*` pair registers the cryptic letter as `-Name` and the readable word as its alias —
and in four of the six, the readable name is the actual implementation being demoted:

| Registration | Line | Real implementation | Wrapper |
|---|---|---|---|
| `-Name 'git-b' -Aliases @('git-branch')` | `branches.ps1:378` | `git-branch` (`:11`, ~130 lines) | `git-b` (`:256`, one line) |
| `-Name 'git-l' -Aliases @('git-log')` | `interactive.ps1:290` | `git-l` (`:11`) | `git-log` (`:73`) |
| `-Name 'git-s' -Aliases @('git-st')` | `interactive.ps1:291` | `git-s` (`:77`) | `git-st` (`:144`) |
| `-Name 'git-p' -Aliases @('git-pick')` | `interactive.ps1:292` | `git-pick` (`:146`) | `git-p` (`:158`) |
| `-Name 'git-r' -Aliases @('git-remote')` | `interactive.ps1:294` | `git-remote` (`:217`) | `git-r` (`:287`) |
| `-Name 'git-rl' -Aliases @('git-release')` | `release.ps1:475` | `git-release` (`:205`) | `git-rl` (`:472`) |

Every other family in the tree does the opposite: `installed-apps`/`i-a` (`apps.ps1:570`),
`dkr shell`/`dkr sh` (`dkr.ps1:546`), `lesson`/`l`, `open-pwd`/`op`. So `pwsh-h`'s git chapter
is a column of two-letter stems while the words that would make it browsable sit in
parentheses.

**Proposed:** flip four of them — `git-branch`, `git-log`, `git-pick`, `git-remote`. One line
each, zero behaviour change, both spellings keep resolving exactly as today. The only visible
difference is which name `pwsh-h` prints first.

**Two corrections to the obvious version of this proposal.**

`git-s`/`git-st` is a wash — both are cryptic, so flipping gains nothing. It only becomes
worth doing if a third name (`git-status`) is added, which needs a new function; and note the
CI gate is one-directional (defined ⊆ registered), so a *registered but undefined* name ships
silently as a help row that throws `CommandNotFound`. See §5.6.

**Do not flip `release.ps1:475`.** `git-rl` is what `CLAUDE.md:90` and `:101` tell contributors
to run, and it is named in `install.ps1:213-225`, `docs/release-checklist.md`,
`docs/instructions.md`, `docs/git-rl/` (a *directory*, hardcoded at `release.ps1:31-42` and
asserted by `release-validate-linux.yml:168-171`) and roughly forty more lines of prose.
Promoting `git-release` in the registry while forty lines of documentation say `git-rl` trades
one inconsistency for another. `release-validate-linux.yml:232` also asserts `pwsh-h` output
matches `\bgit-rl\b`; aliases render inline so a demotion should still pass, but that gate
fails a release silently and is not worth gambling on.

**Migration cost: 3 code files, 4 one-line edits, zero tests, zero CI edits.** The help gate
(`release-validate.yml:176-181`) pools `-Name` and `-Aliases` into one set, so flipping is
invisible to it. Aliases to keep registered: `git-b`, `git-l`, `git-p`, `git-r`, and their
partners — all already are.

One recommended add-on: `components/help/menu.ps1:220-221` stamps the preview cache with the
registry *count*, which is unchanged by a pure rename (136 before and after), so existing
installs' `pwsh-h -a` preview panes break for the renamed rows until something else changes the
count. Hash the rendered names into the stamp instead.

**Doc pressure:** 16 lines in `README.md`, 3 rows in `COMPONENTS.md`, 3 in
`docs/installation.md`, 1 in `docs/troubleshooting.md` are the ones a reader would compare
against `pwsh-h`. Leave `CHANGELOG.md` and `docs/log/**` alone.

### 5.6 `git-s` / `git-st` / `git-sh` — three names one character apart, one of them stash · HIGH

`git-s` (`interactive.ps1:77`) and `git-st` (`:144`) are status. `git-sh` (`:286`) is the stash
manager — its body is literally `git-stash` — and it is registered as its own command with a
synopsis describing something else entirely (`:295`): `'show a commit, interactively chosen'`.
So `pwsh-h` prints two unrelated-looking rows for one behaviour and tells you one of them shows
a commit. `sh` also reads universally as *shell*.

All three operate on the same uncommitted work, and `git-s`'s menu option 4 runs
`git checkout --`, which is unrecoverable.

**Split this into two changes,** because one is a shipping defect and the other is a rename.

**(1) Bug fix, no rename, two lines.** Delete the false registration at `interactive.ps1:295`
and fold the name in as an alias:

```powershell
Register-PFCommand -Name 'git-stash' -Aliases @('git-sh') -Section '🎯 ENHANCED GIT WORKFLOW' -Synopsis 'interactive stash manager'
```

That removes the duplicate row and the false synopsis at once. `git-sh` appears in no doc
except `COMPONENTS.md:173` and the file's own header at `:7`.

**(2) Rename plus new surface.** `git-status` as primary with `git-s` and `git-st` retained as
aliases — and, the real prize, **`git-stash save`**. Today the stash noun is half-built: the
command can only *read* existing stashes and exits with `📭 No stashes found`, so the thing a
user most often wants from the word "stash" — shelve what I am doing right now — has no command
anywhere in PowerFlow. That is roughly 30-40 new lines (dirty-tree check, message prompt,
`git stash push -u -m`), so it is a feature, not a rename, and should be costed separately.

While in the file: `git-s`'s fzf header advertises `Space: Stage/Unstage | Ctrl-D: Diff |
Ctrl-R: Reset` and **none of those keys are bound**. The header lies about a menu whose option
4 is unrecoverable.

**Migration cost.** Fix (1): one file, two lines. Fix (2): `interactive.ps1` only, plus
`COMPONENTS.md:173`, `README.md:280` and `:483`, `docs/installation.md:132` and `:233`. No
tests exist — `tests/` holds docker, linux, network, proxmox, storage, windows and there is no
git suite at all, so nothing asserts the old names and nothing will catch a regression. The
gate's `-Name '([^']+)'` regex accepts the space in `'git-stash save'` (precedent:
`dkr logs`). Minor bump if aliases are retained; major only if `git-st`/`git-sh` are actually
deleted, which is the reason not to delete them.

### 5.7 Six names for one commit workflow · HIGH

`components/git/commit.ps1` defines `git-a` (`:11`), `git-a-plus` (`:244`), `git-aa` (`:452`),
`git-aq` (`:453`), `git-ad` (`:454`) and `git-am` (`:455`) — six names for one workflow. The
last four are one-line wrappers, and two of them are byte-identical:

```powershell
# commit.ps1:452-455
function git-aa { git-a-plus -Quick }
function git-aq { git-a-plus -Quick }
function git-ad { git-a-plus -DryRun }
function git-am { git-a-plus -AmendLast }
```

`git-aa` and `git-aq` are the same behaviour under two names, with `git-aq` registered as an
*alias* of `git-aa` although it is a separate function. And `git-a-plus`'s own registered
synopsis states the violation out loud (`:459`): `'git-a with modes: -Quick, -DryRun,
-AmendLast'` — three flags choosing which program runs. `git-aa`, `git-ad` and `git-am` are
those same modes promoted to one-edit-apart top-level names.

`-plus` means nothing to a user. `-a` in real git means `--all`, a modifier. `am` collides with
real `git am` (apply a mailbox patch), which does something else entirely.

**Proposed:** `git-a` stays as the head noun — that is what makes this cheap, since nothing the
owner types daily moves — and the three modes become the words they already are conceptually:

```
git-a                the fzf workflow (unchanged)
git-a quick
git-a preview        (was -DryRun / git-ad)
git-a amend
git-a --dry-run      genuine modifier, stays a flag
```

Retire `git-a-plus` entirely: once the modes are words the dispatcher has no name to wear.
`git-aq` can go immediately — it is a provable duplicate.

**Two behaviour traps that only survive because they hide behind flag-named wrappers,** and
that a word verb puts in front of the user:

- The `-Quick` path calls a bare `git push` (`commit.ps1:438`) with no upstream handling and no
  remote creation, so the "fast path" fails on a fresh branch while plain `git-a` handles
  exactly that case (`:165-232`). Route quick's push through `git-a`'s block.
- `git-am`'s body runs `git add .` **before** `--amend` on both paths (`:317`, `:321`), so
  unrelated work sitting in the tree is silently folded into the previous commit — which its
  synopsis ("amend the last commit with a new message") does not say — and it then offers
  `git push --force-with-lease`. Either drop the staging or state it. Announce this in
  `CHANGELOG` as a behaviour change, not a fix: the owner may be relying on `git-am` to sweep
  the tree.

**Aliases, and the mechanical catch.** `git-a` must not move — `release-validate-linux.yml:104`
and `:209` assert it resolves on Linux, and it is in `README.md`, `docs/installation.md`,
`docs/troubleshooting.md`, `IMPORT_ORDER.md:77` and `Microsoft.PowerShell_profile.ps1:123`.
Keep `git-aa`, `git-ad`, `git-am` as thin wrappers. **PowerShell `Set-Alias` cannot carry an
argument**, so `Set-Alias git-aa 'git-a quick'` is not expressible — each must stay a wrapper
*function* forwarding to the word, and each is then a kebab-named function that the help gate
(`release-validate.yml:166`) requires be listed in some `-Aliases @(...)`.

**Migration cost: 1 code file, 3 doc edits, zero tests, zero CI edits.** `commit.ps1` (header
`:7`, the `git-a-plus` body `:244-450` deleted, the four wrappers `:452-455`, five
registrations `:458-462` collapsing to one plus an alias list, the hint string at `:387`).
`COMPONENTS.md:170`; `README.md:475`; and `docs/features.md:25`, which still documents
`git-a -vr` — a flag removed in v2.0.0. That last one is not optional: today it is a silent
no-op, and it becomes a hard error the moment `git-a` gains argument validation. Fix it in the
same commit.

**Release class:** dropping `git-a-plus` from the public surface is breaking, so major.

### 5.8 Four unrelated `git-r*` commands, one of which publishes a release · HIGH

`git-r` browses remotes (`interactive.ps1:287`). `git-rb` creates a rollback branch
(`rollback.ps1:171`). `git-rba`/`grba` commits and pushes on one (`:11`, `:169`). `git-rl`
rewrites version files, commits, tags and pushes to origin, firing the CI release pipeline
(`release.ps1:472`). Four names, four unrelated consequences — and the most consequential is
one inserted character from `git-l`, the read-only log browser.

**The realistic fix is asymmetric, and saying so is the point.** `git-rl` must not move (§5.5).
What can move is everything around it, so the letters stop competing:

```
git-rollback              bare → fzf commit picker, reusing git-l's list
git-rollback new <hash>   create and check out rollback-<n>     [was git-rb]
git-rollback commit       add · message · commit · push · PR link  [was git-rba/grba]
```

`rb` reads as *rebase* to every git user and it does not rebase. `git-rba` is
initials-of-initials, and it is hard-gated to branches matching `^rollback-[a-zA-Z0-9]+$` — it
refuses to run anywhere else, which makes it a **mode**, and a mode is exactly what a word verb
under a noun expresses. Note the verb should be `commit`, not `push`: the body is
add → commit → push → PR link, not just a push.

**State plainly what this does not fix.** `git-rl` and `git-l` both stay, so the dangerous
adjacency itself survives — only the surrounding noise goes. If the owner wants that adjacency
actually gone, the options are renaming `git-l` (cheap: `COMPONENTS.md` and `CHANGELOG.md`
only, and `git-log` already exists as the better name — see §5.5) or adding a confirmation to
`git-rl` before the tag push. The first half is cheap and probably worth doing.

**One creed fix to fold in:** `git-rb` takes a mandatory positional hash with no picker, so
using it means running `git-l`, copying a hash and coming back. Bare `git-rb` today drops into
PowerShell's raw "Supply values for the following parameters: commitHash:" prompt. `pmx disk
grow` and `pmx vm show` both open a picker in exactly this situation, and `git-l`'s own body
already produces the hash list (`interactive.ps1:20-21`) — though it is inline, not a callable
helper, so this is ~10 lines adapted rather than a free call.

**Also worth fixing while renaming:** `git-rb` derives its branch name from the **last three
characters** of the short hash (`rollback-<3 chars>`), which will collide across a long
history, and it force-deletes any existing same-named branch to get there.

**Migration cost: small — roughly an hour, and almost none of it the rename.** The work is the
picker and the verb dispatch. `rollback.ps1` (header `:7`, functions `:11` and `:171`,
`Set-Alias -Name grba` `:169`, registrations `:274-275`). Docs: `README.md:274-275` and
`:478-480`, `COMPONENTS.md:172-173`. **Bonus fix in scope:** `README.md:480` documents
`git-mrb` (merge rollback branch), which exists nowhere in the codebase — delete the row or
implement it as a reserved `git-rollback merge`.

Zero tests: `grep -rn rollback tests/` returns nothing.

**Aliases:** keep `git-rb` and `git-rba` as shims (whole-project muscle memory). `grba` is the
only real `Set-Alias` in `components/git/` and the only name without the `git-` prefix, so it
neither tab-completes alongside its siblings nor reads as belonging to them — but retiring it
is a keystroke tax paid entirely by the owner. Deprecate, then remove on his say-so. **If it is
removed, delete both `rollback.ps1:169` and the `-Aliases @('grba')` at `:275`** — a stale
registry entry passes CI silently, because the gate only checks defined → registered.

### 5.9 Seven tab commands, two one-edit pairs, one destructive · HIGH

`components/terminal/tabs.ps1` is 73 lines and every function is a one-line adapter call, so
this is a pure naming problem with an unusually cheap fix. The names:

| Name | Line | What it does |
|---|---|---|
| `send-keys` | `:17` | type keystrokes into whatever has focus |
| `open-nt` | `:22` | open a **new** tab |
| `close-ct` | `:27` | body is literally `exit` |
| `next-t` | `:29` | next tab |
| `prev-t` | `:35` | previous tab |
| `open-t` | `:41` | **switch to** tab N |
| `close-t` | `:54` | close tab N |

`open-nt` and `open-t` are one edit apart, and the typo teleports you instead of giving you a
shell. `close-t` and `close-ct` are one edit apart, and one of them ends your shell — with no
confirmation on either. The `-t` suffix also means three different things across the tree:
tab here, "to/there" in `mv-t`, and `-c` means "current" in `close-ct` but "cancel" in `mv-c`.

**Three registry defects the rename fixes for free.**

*Verified by reading the registration rather than assuming:* `tabs.ps1:70` registers
`-Name 'next-t' -Aliases @('prev-t')`, but `prev-t` is a separate **function** at `:35`. So
`pwsh-h` renders "next-t (prev-t)" and `pwsh-h prev-t` shows the next-t row with the next-t
synopsis. The registry is lying to satisfy the CI alias-coverage gate. Under one noun both
become real rows with real synopses and the lie disappears.

Second: all six registrations carry `-Platform 'Windows'` (`:68-73`), although
`platform/linux/adapters/terminal.ps1` implements `Send-TerminalKeys` (`:49`), `New-TerminalTab`
(`:56`), `Switch-TerminalTab` (`:88`) and `Close-TerminalTabAt` (`:103`) via tmux. **Linux users
have these commands and can never see them in `pwsh-h`.** Correcting this to `Both` is a visible
behaviour change on Linux and belongs in the changelog.

Third: `open-nt`'s `-Shell` parameter appears in no registration, which hides that
`open-nt ubuntu` is a third route to a WSL tab (alongside `open-ubuntu` and
`open-wsl-simple`, `windows-only/wsl.ps1:12`, `:81`).

**Proposed:**

```
tab                  list tabs — on Windows, say plainly that Windows Terminal cannot be enumerated
tab new [shell]      new tab here; the shell becomes a visible word  [was open-nt]
tab 3                switch to tab 3                                 [was open-t 3]
tab next · tab prev
tab close 3          close tab 3                                     [was close-t 3]
tab close            REFUSES — "which tab? (tab close 3, or tab close . for this one)"
tab close .          close THIS tab — confirms first
```

**Three deltas from the obvious version of this proposal.**

*Bare `tab close` must not be the destructive path.* Forgetting an index is far likelier than
the typo this change exists to fix.

*Drop `tab keys`.* Keystroke sending has no tab target on either platform — `send-keys` takes
no target argument at all, so keys go wherever focus already is, while its synopsis (`:73`)
promises "send keystrokes to another tab". A `tab keys` verb would keep the exact promise it is
meant to retire. Delete the `send-keys` wrapper and let `Send-TerminalKeys` stand as a
documented adapter in `COMPONENTS.md`. Reinstate the verb only if a `-Tab N` target is actually
implemented.

*Retire `close-ct` outright.* Its body is `exit`, which adds nothing over typing `exit`, and on
Linux it is the precise footgun `pwsh-exit` (`components/system/login.ps1:104`) exists to
prevent, because PowerFlow can be the SSH login shell there.

**Bare `tab` is honest work, not free.** The Windows adapter drives `wt` entirely through
SendKeys and cannot enumerate tabs; worse, `Switch-TerminalTab` returns `$true` unconditionally
(`platform/windows/adapters/terminal.ps1:117`), so "Switched to tab 7" prints happily when there
is no tab 7, and `Close-TerminalTabAt` (`:128`) does the same. Either fix those, or bare `tab`
must say plainly that Windows Terminal cannot be enumerated rather than inventing a list. Also
note `close-t`'s Windows path is a timing-dependent SendKeys pair (Alt+N, 100 ms sleep,
Ctrl+Shift+W): if the first key does not land it closes whatever has focus.

**Name check:** `tab` is unclaimed. `tabs` is **not** — Git for Windows ships
`C:\Program Files\Git\usr\bin\tabs.exe`, so the singular is the only safe spelling.

**Migration cost: 1 code file rewritten, 5 live docs, zero tests.** 73 lines becomes roughly
180-220: one `tab` dispatcher hand-parsing `$args` (`dkr.ps1:389-409` is the template), six
deprecation shims, seven registrations. The header comment at `:7` names all seven functions
and must be rewritten too.

Docs to edit: `README.md:637-640` (the whole 3-row Terminal Management table),
`COMPONENTS.md:178`, `docs/features.md:152`, `:154`, `:155`, `IMPORT_ORDER.md:82`.

Docs **not** to edit: `CHANGELOG.md:1990`, `:2123`, `:2213-2231` and
`docs/plan/linux/phase-0-refactor.md:64`, `:124` are historical records.
`docs/migration/v3-upgrade.md:12` is a **published compatibility promise** that
`open-ubuntu` / `open-nt u` "still work" — keep the alias; do not quietly edit the promise
away.

**Aliases:** retain `open-nt`, `open-t`, `next-t`, `prev-t`, `close-t`, `send-keys`. As in
§5.7, aliases cannot carry arguments, so each stays a shim function — and **attach each
deprecated name to the specific subcommand row it maps to** (`open-nt` on `tab new`, `open-t`
on `tab`, `close-t` on `tab close`). Dumping all six into one `-Aliases` on the bare `tab` row
reproduces exactly the `prev-t` defect this finding exists to fix: an alias resolving to a row
whose synopsis is false for it.

### 5.10 `gh-l`, `gh-l-org`, `gh-l-status`, `gh-l-reset` — cryptic suffixes on a cryptic stem · HIGH

`components/github/browser.ps1` defines `gh-l` (`:111`), `gh-l-reset` (`:367`), `gh-l-status`
(`:381`) and `gh-l-org` (`:395`). The `l` carries no meaning and puts a repo browser one
keystroke from `git-l`, the log viewer.

Two of the four are not even the same noun. `gh-l-status` and `gh-l-reset` are four lines of
`cmdkey /list:` and `cmdkey /delete:` on the credential `gh-l-github-token` — they answer "is
my token saved", touch no repositories, and "the status of gh-l" reads as *repo* status.
"reset" is also the wrong verb for "delete my saved credential" in a git-adjacent tree where
`reset` means `git reset` and `git-f` performs an actual hard reset (§5.2).

**`gh-l-org` is the proof that only the naming is wrong.** Bare, it fetches `/user/orgs` and
opens an org picker; with a name it skips straight in (`:395`). That is the creed implemented —
bare does the useful thing, refinement is a word, ambiguity gets a picker — with the word "org"
trapped inside the function name where nobody can find it. Turn the name inside out and it
becomes `gh-l org [name]` with no behaviour change at all.

**The head noun must not be `gh`.** The GitHub CLI ships a real `gh` binary, and PowerFlow
shells out to it directly: `components/git/remote.ps1:13` (`gh auth status`), `:189`
(`gh repo create`), and the probe at `commit.ps1:175`. A PowerShell function outranks a native
binary, so naming the family `gh` would silently break `git-a`'s create-the-GitHub-repo path on
both platforms.

**Proposed — keep the `gh-l` stem, convert only the suffixes to words:**

```
gh-l                  your repos, newest push first (unchanged)
gh-l 20               still the count — the numeric positional must keep binding
gh-l org [<name>]     [was gh-l-org]
gh-l auth             is a token saved?          [was gh-l-status]
gh-l auth forget      delete it                  [was gh-l-reset]
```

`auth`, not `token`: it matches `gh auth status`, the vocabulary PowerFlow itself invokes at
`remote.ps1:13`, and "token" reads as "print my secret". Keep "forget".

If a guessable head is wanted later, `github` is free and `repo` reads well for repositories —
but `repo` reads wrong for credentials ("repo auth forget"), and on Linux an alias outranks
Google's AOSP `repo` binary if that is ever installed. Treat it as a second-order decision.

**Do not rename the credential string.** `gh-l-github-token` (`:14`, `:32`, `:122`, `:368`,
`:382`) is the live Windows Credential Manager key. Renaming it silently invalidates every
existing saved token — the user is re-prompted and the old credential is orphaned with no
command able to delete it. This is the single highest-risk edit here and it is invisible from
the function signatures. Leave the string with a comment saying why.

**A pre-existing architecture violation this rename surfaces.** `_GhL-SetToken` /
`_GhL-GetToken` call `cmdkey` and P/Invoke `advapi32` `CredRead` directly from inside
`components/` — a Windows-only OS call, which `CLAUDE.md`'s architecture rule forbids. There is
no credential adapter in `platform/*/adapters/`, and `cmdkey` is absent from the CI forbidden
regex (`release-validate.yml:106`), so it slipped through. None of the four registrations
(`:642-645`) carries `-Platform`, so on Linux `gh-l-status` reports "no token saved" rather
than failing — worse than failing. Cheapest honest fix now: `-Platform 'Windows'` on the auth
rows. Proper fix (separate item): `Save-PFSecret` / `Get-PFSecret` / `Remove-PFSecret` on both
platforms — and those must then be hand-added to the parity regex at
`release-validate.yml:208`, which is a hardcoded list.

**Three more defects worth fixing rather than carrying across:** `gh-l` prints leftover
developer debug output to real users on every run ("🔍 Debugging: Sorting…", "🔍 Debug:
Selection = …"); permanent repository **deletion** is option 4 of a numbered menu under a
command whose synopsis says "browse"; and `-Count` is declared as a param *and* separately
re-read from `$args[0]` (`:117-119`), so two forms exist for one thing.

**Migration cost: 1 code file, 6 live docs, zero tests.** Roughly 60-90 minutes for the pure
rename. `browser.ps1`: header `:7`, `:11`; the four functions; four registrations `:642-645`;
the self-referential string at `:326` ("run gh-l again to refresh"); User-Agent strings `:174`,
`:430`.

Live docs: `README.md:147`, `:305`, `:306`, `:309`, `:310`; `COMPONENTS.md:177` (Functions
column *and* the Platform column, which currently implies Both for `cmdkey`-backed code);
`docs/installation.md:171`, `:175`; `docs/troubleshooting.md:345`, `:348`, `:354`, `:357`,
`:363` (a copy-paste recipe users follow); `docs/instructions.md:480`;
`docs/migration/v3-upgrade.md:129`.

Historical, leave alone: `CHANGELOG.md:2038`, `:2167`, `:2201-2214`; ~10 files under
`docs/log/`. `docs/plan/github/org-clone.md:30-33` records the interface decision this
overturns ("A dedicated gh-l-org is consistent with the existing pattern") — add a
"superseded by" line rather than rewriting it.

**Aliases:** `gh-l` is the head and does not move. `gh-l-org`, `gh-l-status` and `gh-l-reset`
stay as the *implementations*, reached by the new words — a `Set-Alias` cannot append a
subcommand, so they keep working by continuing to exist, and each must appear in some
`-Aliases @(...)` or the help gate fails the release.

### 5.11 `pc-whoami`'s four flags choose which program runs · HIGH

`components/system/health.ps1:70`. `-power`, `-crashes`, `-bios` and `-ram` are four flags that
select which of five screens runs — the clearest flag-as-selector in the tree. And the cost is
in the code, not in taste. The parameter block carries two positional slots and a twelve-line
comment explaining why (`:71-90`):

```powershell
    param(
        # TWO positional slots, both load-bearing:
        #
        #  position 0  the program name for `-ram java`. Without it "java" bound to the first
        #              bare parameter — [int]$days — and died with "cannot convert to Int32".
        #  position 1  the program name for `--ram java`. PowerShell has no double-dash switch
        #              syntax: it parses `--ram` as the literal STRING "--ram" and hands it to
        #              position 0, which then leaves "java" with nowhere to go ("a positional
        #              parameter cannot be found"). Slot 1 catches it. No process can be called
        #              "--ram", so reading that token as a flag is unambiguous.
```

Then `:95-103` is a branch whose only job is to intercept the retired `--ram` string, and
`:107` infers `-ram` from a bare name because `pc-whoami java` used to print the dashboard and
silently ignore the word typed. **That is real code written to defend a flag design, and a word
selector needs none of it:** `pc ram java` has nowhere to go wrong.

Half the command is already correct. The `-ram` sub-tree takes **word** arguments —
`huge`/`large`/`medium`/`small`/`tiny`, or a program name — so the flag is the only non-word
link left in the chain. And `pc-cap` (`health.ps1:779`), in the same file, is already the
reference shape: bare reads the current cap, a number sets it, `restore` is a word, zero flags.

**Proposed:**

```
pc                                   the vitals dashboard (unchanged)
pc power · pc bios · pc crashes
pc crashes -days 30 -export          genuine modifiers, stay flags
pc ram [huge|large|medium|small|tiny|<program>]
pc ram -min 2
pc cap 85 · pc cap restore           [was pc-cap — shape unchanged]
```

Dropping "whoami" also fixes a real collision: `whoamifull` (`brothers.ps1:147`) answers "who
am I" about the **user**, while `pc-whoami` answers it about the **hardware** — the same odd
verb for unrelated subjects, three files apart.

**Four corrections to the obvious version of this proposal.**

*Keep the `param()` block.* `-min` is read via `$PSBoundParameters.ContainsKey('min')` at
`health.ps1:129`; a `dkr`-style pure `$args` parser would have to re-implement that. Use
`param()` with positional words.

*Single dash for `-days`/`-min`/`-export`.* `health.ps1:76-79` documents exactly why
PowerShell cannot bind `--days`.

*Keep `pc ram -min N`.* It is live today (`README.md:528`, `COMPONENTS.md:184`, hint at
`health.ps1:439`).

*Do not promise code simplification on day one.* `pc-whoami` must keep working, and a plain
`Set-Alias` forwards `-ram` unchanged — so either `pc` retains the four switches as hidden
deprecated synonyms for a release, or `pc-whoami` becomes a shim that maps them. Either way the
param block does not shrink immediately, and if the switches are kept permanently for muscle
memory it never shrinks. **Sell this as consistency, not as code removal.** The consistency is
still worth it; the code saving is deferred and may never arrive.

**The head noun `pc` lands in a busy neighbourhood.** It is a transposition from `cp` (a real
`Set-Alias` to `Copy-Item`, `listing.ps1:161`) and one edit from `ps` (PowerShell's
`Get-Process` alias, which still resolves). Neither is destructive, so this is a legibility
cost rather than a hazard — but it is real, and `pc-whoami`'s length is currently doing some
protective work. `machine` or `vitals` carries the same shape with no adjacency.

**Migration cost: 4 code files, 4 docs, zero tests — and the bulk is hint strings, not logic.**
`health.ps1` carries 62 references in an 872-line file. The param block and three guards
(`:70-132`) are the restructure; the expensive part is ~20 user-visible drill-in strings, each
load-bearing because the design rule at `:16` is "every ⚠️ names the flag that drills in":
`:240`, `:254`, `:262`, `:270-271`, `:279`, `:282`, `:321`, `:378`, `:437-439`, `:476`,
`:505-506`, `:530`, plus the comment-help block `:54-69` and `pc-cap`'s at `:768-777`. Miss one
and the tool teaches a dead command.

Header-only: `platform/windows/adapters/health.ps1:6`, `:80`;
`platform/linux/adapters/health.ps1:6`. Cross-file comments citing `pc-whoami -ram` as the house
picker precedent: `components/files/listing.ps1:86`, `components/proxmox/vm-read.ps1:57`,
`:186`.

Docs: `README.md` 16 lines (`:80-87` prose, `:155-157` quick-start, `:523-531` the reference
table); `COMPONENTS.md:108`, `:110`, `:111`, `:184`. `docs/plan/pc-whoami/README.md` has 24
references but is an **implemented design record** — do not rewrite it; add a status block
resolving its own Open Q1, which foresaw a `pc` front at `:198`. `docs/plan/docker/dkr.md:1073`
has a literal `pc-whoami -ram` example inside the "connect it to pc-whoami" section; note that
file is modified-uncommitted, so coordinate with the in-flight Docker work.

**No tests.** `grep -rn "pc-whoami\|pc-cap" tests/` returns nothing, and that is the risk, not
the relief. `docs/log/2026/July/17 Fri/log-1.md:43` describes a 21-assertion `pc-cap`
restoration-guarantee suite with mocked adapters that was **never committed**. `pc-cap`'s
record-first / verify-before-forget ordering (`health.ps1:838-861`) is the most
safety-critical logic in the file and has no regression test. **Write that test before touching
`pc-cap`.**

**Sequence with §4:** `health.ps1:196` hard-codes `installed-apps 1gb-5gb`.

### 5.12 `pwsh-settings` and `pwsh-config` have swapped nouns · HIGH

`pwsh-settings` (`config-files.ps1:32`) opens **one Windows Terminal JSON file**.
`pwsh-config` (`sysconfig.ps1:45`) is the menu that changes the **operating system** —
timezone, locale, hostname, time-sync. "Settings" and "config" are synonyms to every user, and
here they are attached to the two least-related things in the tree, with the more
general-sounding word on the narrower command.

This is a semantic inversion, not a spelling clash, which makes it worse than a cryptic name:
both names are guessable and each leads to the wrong place. No split between "config" and
"settings" can ever be learnable, because the two words are synonyms — so the answer is not to
rename one, it is to stop having two.

Underneath sit three file-openers that differ only in which path they hand to `Open-Editor`:
`pwsh-profile` (`:12`), `pwsh-starship` (`:21`), `pwsh-settings` (`:32`) — the entire contents
of `config-files.ps1`, 8-16 lines each. That is one noun plus three word verbs.

`pwsh-config` itself needs no shape change: bare opens an fzf menu listing every changeable
setting **with its current value**, refinement is already a word with generous synonyms
(`kb`/`keys`, `tz`/`time`, `loc`/`lang`, `host`/`name`, `ntp`/`sync`), and it has no flags at
all. It should supply the head noun's bare behaviour rather than be renamed around.

**Proposed:**

```
config                     the fzf picker — every setting, current values shown
config profile             open $PROFILE                        [was pwsh-profile]
config prompt              open starship.toml                   [was pwsh-starship]
config terminal            open Windows Terminal settings.json  [was pwsh-settings]
config font                install the Nerd Font                [was pwsh-font]
config font status         report only, install nothing         [was pwsh-font -status]
config system              the OS-settings sub-picker           [was pwsh-config]
config tz | loc | host | ntp | kb    every existing synonym kept
config lessons [full|hint|off]       [was linux-lessons]
config reminders [on|off]            [was pwsh-reminders]
config login [on|off]                [was pwsh-autologin, Linux only]
```

`config prompt` fixes the worst guessability failure of the three: `pwsh-starship` names the
third-party tool, so someone who wants to change how their prompt looks must already know
PowerFlow's prompt *is* Starship. "prompt" is the goal; "starship" is the implementation.
`pwsh-font -status` folds in as a word because the command has exactly two modes, so the word
costs nothing.

`linux-lessons` (`teach.ps1:36`) and `pwsh-reminders` (`version.ps1:265`) belong here too: both
are persisted preferences written into `config/PowerFlow.settings.ps1` by regex, yet
`linux-lessons` is filed under 🎓 LEARN LINUX where nobody hunting "turn that off" will look,
and it is one letter from `lesson`, which *teaches* a command rather than setting a mode.
Include `pwsh-autologin` too, or the split is simply rebuilt.

**Three amendments worth making explicit.**

*Every word above must also be a row in the bare `config` picker* — using the existing
`Owner='powerflow'` mechanism plus a new `Kind='open'` for the file-openers. Otherwise the head
noun promises "every setting" while hiding four of its own words.

*`config font` should report by default and install behind the word `install`.* Bare
`pwsh-font` installs a package and can bootstrap Scoop; a `config` noun should not do that
unasked. `flag-uniformity-audit.md:86` already records that `--status` silently installs.

*The `config terminal` synopsis must say "(Windows)" in text.* `-Platform` is per-command and
cannot mark a single word.

**Two live bugs the consolidation should fix rather than inherit.** `pwsh-settings` is
registered `-Platform 'Windows'` (`config-files.ps1:53`) although the function is defined on
both platforms and degrades with a helpful message (`:36`) — Linux users are denied a message
that exists. And `pwsh-reminders` builds its settings path as
`Join-Path $PowerFlowRoot "config\PowerFlow.settings.ps1"` with a hard-coded **backslash**
(`version.ps1:266`, duplicated at `:106`): on Linux that is one literal filename, `Test-Path`
fails, the file is never rewritten — yet the in-memory flag is set and the success message
still prints, so the setting silently reverts on the next shell. Land `config reminders` and
`config lessons` in one place and that path is written once.

**Migration cost: MODERATE — the largest doc surface in the audit.** Build it as a
`storage.ps1`-shaped dispatcher (`storage.ps1:248` is the template): no `param()`, walk
`$args`, switch on `$words[0]`, delegate to the existing functions unchanged. Do not rewrite
them.

**The CI trap, and it is the most likely way this change fails.** The help gate collects
`^function [a-z]` case-sensitively across `components/`, so if the five old functions remain as
private implementations, CI still counts them as user-facing and fails the release unless they
stay registered. Retiring them from `pwsh-h` therefore *requires* either (a) listing each old
name in `-Aliases @(...)` on the matching new registration — the right answer, since the gate
harvests `-Aliases` into `$registered` — or (b) renaming them to Verb-Noun
(`Open-PFProfile`, `Install-PFNerdFont`) and moving them to `COMPONENTS.md`.

**Runtime strings outside the component files — the cost people forget.**
`components/navigation/roots.ps1:563` prints "Switch with: pwsh-config → User folders";
`platform/windows/adapters/fonts.ps1:107` and `:120` print `pwsh-font` and `pwsh-settings` from
inside an **adapter**; `install.ps1:353` and `:371` tell every fresh user to run `pwsh-font`.
`install.ps1` is the worst of these — it is what a brand-new user reads first, and it is
shipped by the remote installer, so a v(N-1) installer will print `pwsh-font` at a v(N) shell.
That alone means the name can never stop working.

**Docs:** `README.md` 13 lines (`:62`, `:208`, `:236`, `:469`, `:517`, `:585`, `:586`, `:590`,
`:646-648`, `:673`, `:730`) — and `:646-648` is a three-row table that collapses, while `:586`
documents `pwsh-font -status`, the flag being removed. Leaving that stale is exactly the
"README documented behaviour a release had reversed" failure `CLAUDE.md`'s checklist exists to
catch. `COMPONENTS.md:93`, `:100`, `:180`, `:188`, `:190`, plus a new row.
`docs/installation.md:149`, `docs/troubleshooting.md:119`. `CHANGELOG.md`'s 15 references and
`docs/plan/**`'s ~28 lines are historical — leave them.

**Tests:** effectively free. `tests/windows/font-prerequisite.ps1:16` is a comment; nothing
asserts any of these six names.

**Aliases to retain permanently:** `pwsh-config`, `pwsh-settings`, `pwsh-profile`,
`pwsh-starship`, `pwsh-font`, `pwsh-reminders`, `linux-lessons`, `pwsh-autologin`. `pwsh-font`
and `pwsh-config` are hard requirements — printed by `install.ps1`, two adapters and
`roots.ps1`. The one thing no alias can preserve is `pwsh-font -status` once `-status` becomes
a word; since `flag-uniformity-audit.md:86` documents that spelling as actively hazardous,
letting it break loudly is arguably correct, but it is the one piece of muscle memory this
change genuinely costs.

**A lower-cost variant worth naming:** keep `pwsh-config` as the head and make the four openers
words under it. Same de-duplication, same flag retired, no claim on the shell's most general
word — at the cost of leaving a `pwsh-` name on a command that changes the OS.

### 5.13 `powerflow-` and `pwsh-` are two prefixes for one noun · MEDIUM

`components/core/recovery.ps1` makes it starkest: `pwsh-recovery` at `:19` and
`powerflow-uninstall` at `:97` — same file, same subject, different prefixes. The prefix
carries no information because it is applied inconsistently: `pwsh-` means "PowerFlow itself"
in `pwsh-h`, `pwsh-recovery` and `pwsh-reminders`, but "a thing on this machine PowerFlow
opens or toggles" in `pwsh-profile`, `pwsh-starship`, `pwsh-settings`, `pwsh-config`,
`pwsh-font`, `pwsh-autologin` and `pwsh-exit`.

Two prefix collisions, and in both the pair has opposite consequences:

- **`powerflow-u`** needs eleven characters before `update` and `uninstall` separate.
- **`pwsh-re`** sits between `pwsh-reminders` (silences a notification) and `pwsh-recovery`,
  whose option 5 deletes `$PROFILE` behind a bare y/n **with no backup** — while
  `powerflow-uninstall`, twelve lines below at `:114-125`, lists its targets, demands the typed
  word "yes", and backs `$PROFILE` up with a timestamp first.

There is also an unambiguous duplicate: `powerflow-version` (`version.ps1:259`) prints version,
repo and profile path; `Get-PowerFlowVersion` (`:223`) prints those same three facts plus
whether `$PROFILE` exists, how many of five dependencies resolve and how many bookmarks are
configured. The second is a strict superset — the clearest merge candidate in the tree.

`Get-PowerFlowVersion` is also the **only Verb-Noun name in the entire registry**, which
`CLAUDE.md` explicitly forbids ("Internal helpers (Verb-Noun names) go in COMPONENTS.md, not
the registry — pwsh-h is a command reference, not a function index"). It appears in help only
because it was hand-registered at `version.ps1:309`, and the CI gate is case-sensitive so it
could never have caught it.

**Proposed:**

```
powerflow                 version · repo · $PROFILE · deps N/5 · bookmark count
powerflow update          [was powerflow-update]
powerflow remove          [was powerflow-uninstall]
powerflow fix             [was pwsh-recovery]
powerflow reminders [on|off]   [was pwsh-reminders]
powerflow help
```

`remove` rather than `uninstall`, so no two verbs share a first letter and the collision cannot
return if a subcommand completer is ever added. Delete the `Get-PowerFlowVersion` registration
and keep the function as the renderer bare `powerflow` calls, documented in `COMPONENTS.md`.

**`powerflow fix` needs a no-fzf path**, because it is the command you reach for when the
install is already broken and its own options 2 and 3 exist to detect a missing dependency.
Today it is a numbered 1-9 `Read-Host` menu where options 7, 8 and 9 are merely other commands
(`powerflow-version`, `powerflow-update`, `pwsh-h`) — delete those; they are one word away. And
option 2 hard-codes the tool list where option 3 calls `Get-RequiredTools`, so the two can
drift; there is a third copy at `version.ps1:233`.

**Two things no rename may break.** `powerflow-update` is called internally as
`powerflow-update -Yes` from the startup prompt (`version.ps1:102`), and `install.sh:546`
passes `-Yes` to the generated uninstall script — so a token-loop-only dispatcher breaks both.
Keep `-Yes` accepted alongside any `--yes`.

**And two user-facing strings outside `components/` that a working-tree diff will not show
you.** `install.ps1:441` prints `powerflow-uninstall` at the end of every install on both
platforms. `.github/workflows/release-generate-scripts.yml:119` **bakes the string into every
generated release note.** Published release notes are immutable, so that alias can never be
retired — it is permanent, not transitional. Miss that line and the next release documents a
command that no longer exists, which is precisely the failure `CLAUDE.md`'s checklist exists
to catch.

**Note the head noun is nine characters,** which is worse to type than what exists today for
the read case. The win here is the collision fix and the merge, not brevity. `pf` — the obvious
short form — is currently taken by `paste-file` (`clipboard.ps1:213`), which §5.16 would free.

**Migration cost: 2 code files, 5 live docs, 1 workflow, zero tests.** `version.ps1` (the
dispatcher, the merged renderer, registrations `:307-310`, and strings at `:86`, `:102`,
`:113`, `:283`); `recovery.ps1` (`:35`, `:36`, `:80`, `:83`, the option-5 guard at `:69-75`,
registrations `:166-167`). Docs: `README.md` 7 lines including the table at `:626-628`;
`COMPONENTS.md:93`, `:95`; `docs/installation.md` 7 lines; `docs/troubleshooting.md` 7 lines —
but note `:589` pastes the entire `pwsh-recovery` body inline into a safe-mode profile users
copy when PowerFlow will not load, so trimming the menu makes that copy wrong. It needs
rewriting, not find-and-replace, and arguably should not be renamed at all since it is not a
PowerFlow command reference.

**Aliases to retain, all five:** `powerflow-update`, `powerflow-version`,
`powerflow-uninstall`, `pwsh-recovery`, `pwsh-reminders`. The first three are non-negotiable
for the reasons above. Every one must appear in an `-Aliases @(...)` or its shim fails the help
gate.

**Fix the backslash bug** (`version.ps1:266`, `:106`) while in the file — see §5.12.

### 5.14 `nav`'s bookmark verbs are the one place `nav` breaks its own pattern · MEDIUM

`nav` is the closest thing in the tree to the reference, which is what makes this finding
small. Its own switch statement contains both the right pattern and the wrong one, eight lines
apart (`components/navigation/nav.ps1:103-116`): `nav roots add`, `nav roots rm`,
`nav roots reset` and `nav anchors rm` are proper words with generous synonyms
(`rm`/`remove`/`d`/`delete`, `nav.ps1:61`), while the bookmark verbs are:

| Spelling | Line | Means |
|---|---|---|
| `nav create-b` / `nav cb` | `:103` | create a bookmark |
| `nav delete-b` / `nav db` | `:104` | **delete** a bookmark |
| `nav rename-b` / `nav rb` | `:105` | rename a bookmark |
| `nav list` / `nav l` | `:106` | list bookmarks |
| `nav b <name>` | `:131` | go to a bookmark |

`cb`, `db` and `rb` are mutually one edit apart and one edit from `nav b`, which **navigates**.
`nav db docs` versus `nav b docs` is the difference between deleting a bookmark and going to
it. And `db` reads as *database* to every developer alive, `rb` as *rollback* or *Ruby*. The
`-b` suffix also buries the noun inside the verb, the exact inverse of the reference shape.

**Proposed:**

```
nav b <name>                       KEEP EXACTLY — the daily driver and the documented contract
nav b . [<name>]                   KEEP — a shipped v4.2.0 feature
nav bookmarks                      list and manage         [was nav list / nav l]
nav bookmarks add [<name>]         [was nav cb / create-b]
nav bookmarks rm <name>            [was nav db / delete-b]
nav bookmarks rename <old> <new>   [was nav rb / rename-b]
```

Accept `bookmarks`, `bookmark` and `bm` for the namespace token, mirroring how `nav.ps1:60`
already accepts both `anchors` and `anchor`. `nav bookmarks` is also more honest than
`nav list`: under a command whose whole subject is directories, `nav list` listing *bookmarks*
is a guess.

**Rejected:** `nav go` and the nounless `nav save` / `nav forget`. `nav go` collides with the
`~/go` workspace and displaces a documented hot path (`README.md:442`, `roots.ps1:391`, the
registration at `nav.ps1:365`) for a two-character gain; and `nav`'s own roots/anchors
precedent puts the noun first.

**Two pre-existing defects to clean up rather than inherit.** `nav`'s help card advertises the
list as "manage bookmarks (Enter go · ctrl-d delete)" (`nav.ps1:88`), implying fzf — but
`Show-BookmarkList` (`bookmarks.ps1:160`) is a plain `Read-Host` numbered menu with no fzf and
no ctrl-d. So the help describes a picker that does not exist. And that prompt teaches a
**third** verb vocabulary inside itself (`bookmarks.ps1:183`): `'c <name>'` to create,
`'d <name>'` to delete, `'r <old> <new>'` to rename. Changing the prompt to `add`/`rm`/`rename`
while keeping `c`/`d`/`r` accepted is the difference between fixing the inconsistency and
relocating it.

**Migration cost: 3 code files, ~9 doc lines, zero tests — and the retained spellings are
free**, because the switch already matches with `-in @(...)`, so each old token is one array
element.

`nav.ps1`: the switch `:103-106`; the help card `:86-89` (line 89 deleted outright); error
hints `:142`, `:154`, `:158`; the registration and example at `:365`.
`bookmarks.ps1`: three usage strings `:77`, `:99`, `:133`, plus the inner REPL vocabulary at
`:180-186`. `roots.ps1:391` needs no change under this shape — a second reason to keep `nav b`.

Docs: `README.md:257`, `:259`, `:443`, `:447`; `COMPONENTS.md:163`;
`docs/installation.md:131`, `:226` (an install verification checkbox a user types);
`docs/troubleshooting.md:18`. Leave `CHANGELOG.md:262-263`.

**Retain, accepted but removed from help:** `cb`, `create-b`, `db`, `delete-b`, `rb`,
`rename-b`, `l`, `list` — the `CHANGELOG.md:206` precedent ("Removed from the help; still
accepted so no existing script breaks"). `db` in particular is harmless to keep as a silent
synonym but must never be repurposed to anything non-destructive, or old muscle memory becomes
a wrong action.

**No CI exposure:** the help gate scans only `^function <kebab>` and `^Set-Alias <kebab>`, so
switch-string sub-verbs are invisible to it. It will neither force the new registrations nor
catch a stale one — verify `pwsh-h` by eye.

**Residual risk:** reserving `bookmarks`/`bookmark`/`bm` in nav's command position removes them
from fuzzy-search queries, joining the words `nav` already reserves (`b`, `list`, `roots`,
`anchors`, `home`, `code`, `projects`, `~`). A directory literally named "bookmarks" becomes
unreachable via bare `nav`, though still reachable by path or anchor.

**The separable half:** the `Show-BookmarkList` fzf rewrite (~63 lines, copying
`Show-PFServerPicker` at `servers.ps1:399-450`) fixes a help card that already lies and can
ship on its own, before or after the rename. That is the lower-risk ordering and it is ~80% of
the effort.

### 5.15 `set-path` reads as a `Set-*` cmdlet that replaces the PATH, and its one verb is lonely · MEDIUM

`components/system/path.ps1:12`. Every PowerShell `Set-*` cmdlet replaces a value, so the name
says it overwrites the PATH — when the body **appends**: it skips the directory if already
present, warns but still adds if the folder does not exist, and makes it live in the current
session. The file's own header says "Add directories". A user who reads the name and hesitates
is right to.

Note the shape itself is **not** a violation, and an earlier reading of this was wrong:
`CLAUDE.md` and the CI gate classify by *case*, and lowercase-verb-first-hyphen is house style
(`copy-pwd`, `open-nt`, `send-keys`). The defect is semantic, not structural.

The single verb it has is also lonely: nothing in PowerFlow lists or removes a PATH entry, so a
user who mistypes a directory has no remedy inside the tool.

**Proposed, in two clearly separated parts.**

*Rename only — small, half a day:*

```
path add <dir>            what set-path does today
path add <dir> -system    -system stays a real switch; the adapter owns elevation
path <dir>                accepted as `path add`, so the retained set-path alias works
```

Keep the `-system` switch, which means the `param()` block can stay and the unquoted
`ValueFromRemainingArguments` join survives untouched. Adopting `--system` instead forces
hand-parsed `$args` and a hand-rolled re-implementation of that join — avoid it.

*Follow-on feature, blocked on one decision:*

```
path            list every entry with a live/dead tick (the Show-NavSearchRoots pattern)
path list       explicit synonym
path rm <dir>   picker on ambiguity
```

**The decision that must be made first**, because it changes what both new verbs mean: does
`path` mean the whole PATH or only PowerFlow-managed entries? The Windows adapter reads the
entire registry value; the Linux adapter reads only its own `PF_PATH_ENTRY` lines. As written,
`path list` would show ~40 entries on Windows and 2 on Linux, and `path rm` would delete
anything on Windows but only PowerFlow's own entries on Linux. Narrowing Windows needs a marker
mechanism the registry has no room for; widening Linux means parsing the user's rc files, which
`platform/linux/adapters/env.ps1:11-14` explicitly rejects:

> PowerFlow owns exactly one file so it can add and remove entries cleanly without ever
> rewriting a file the user owns.

That comment is close to a documented decision against the widened reading. Respect it.

The follow-on also needs a **new adapter function on both platforms** —
`Remove-PersistentPathEntry` does not exist anywhere today, and `Get-PersistentPathEntries` is
Linux-only (Windows has only `Get-PersistentPath`, returning a `;`-joined string). Windows
removal means rewriting a registry PATH value, which is destructive and wants machine-scope
`Assert-Admin`; Linux removal means rewriting PowerFlow's fragment file without touching
user-owned lines, with `/etc/profile.d` needing sudo. And **both names must be hand-added to
the parity regex at `release-validate.yml:208`**, which is a maintained list — miss it and the
missing platform explodes at runtime unchecked.

**Migration cost of the rename alone: wider than it looks, and mostly not prose.**
`.github/workflows/release-validate-linux.yml:209` hard-codes `set-path` in a command smoke
list and **fails the Linux release** if the name changes with no alias kept — so keep the alias
*and* add the new name to that list. `config/paths.linux.ps1:18` and, more subtly,
`platform/linux/adapters/env.ps1:91` writes the string "regenerated by set-path" **into the
user's generated `~/.config/powerflow/path.ps1`**, so stale text persists on disk in
already-generated files after a rename.

Docs: `README.md:599-600` (note `:600` documents the single-dash `-system` spelling),
`COMPONENTS.md:182` and `:38` (the adapter contract row), `docs/future-dev-plan.md:224`.
Historical, leave: `CHANGELOG.md:1999`, `docs/migration/v3-upgrade.md:130`,
`docs/plan/linux/phase-0-refactor.md:124`, `docs/log/2026/July/13 Mon/log-1.md:4`.

**Dispatcher wrinkle:** `path` bare must list while `path <dir>` must add, so the first token
needs verb-versus-directory disambiguation — `add`, `list` and `rm` are all legal directory
names. `nav` accepts the same ambiguity.

**Retain `set-path` permanently:** README-documented since v3 and asserted by Linux CI.

### 5.16 `here`, `copy-pwd`, `open-pwd`/`op` — one noun, three names, two help sections · MEDIUM

`here` (`directory.ps1:21`) answers "what is this folder?" — path, dir and file counts, size,
git branch, and a guess at the project type. The two things a user then wants to *do* with this
folder already exist: `copy-pwd` (`directory.ps1:230`) copies its path, `open-pwd`/`op`
(`clipboard.ps1:21`, `:41`) opens it in the file manager. They are a genuine two-member family
that nobody would ever find as a family, because they live in different files **and** different
`pwsh-h` sections — `copy-pwd` under 🧭 SMART NAVIGATION, `open-pwd` under 📂 ENHANCED FILE
OPERATIONS.

`pwd` in a name is shell jargon for "here", so the noun is already spelled correctly once and
in jargon twice. And the rename settles a registry lie: `here` is registered as "show where you
are, **with quick actions**" (`directory.ps1:238`) and there are no quick actions in the body —
it prints and returns. Adding the two verbs makes the synopsis true rather than editing it
down.

**Proposed:** `here` · `here copy` · `here open`. No behaviour change — both bodies are one
adapter call each (`Copy-ToClipboard`, `Open-Path`), correctly routed, so nothing crosses the
architecture rule.

**Migration cost: 2 code files, 4 doc lines, zero tests.** `directory.ps1` gains hand-parsed
`$args` dispatch (the `dkr` pattern, not `param()`), folds both bodies in, and replaces the two
registrations at `:238`/`:241` with three. `clipboard.ps1` loses `open-pwd` (`:21-39`) and `op`
(`:41-43`) and the registration at `:223`; its stale "Windows File Explorer" docstring at
`:13-18` and header at `:6-7` need fixing too. The file then keeps only its genuine members
(`copy-file`/`paste-file`/`cf`/`pf`), which improves its cohesion — `open-pwd` was the odd one
out.

**The one mechanical trap** is the same as §5.7 and §5.9: `Set-Alias` cannot bind a name to a
function *plus* an argument, so all three compat names must be wrapper functions, and the help
gate then demands a registration for each — which would re-add exactly the three rows this
change consolidates. Fix: `-Name 'here copy' -Aliases @('copy-pwd')` and
`-Name 'here open' -Aliases @('open-pwd','op')`. The gate harvests `-Aliases` into
`$registered`, so this passes with the old names rendering inline instead of as separate rows.

**Docs:** `COMPONENTS.md:164` and `:168`; `docs/plan/linux/phase-0-refactor.md:124`; and
`docs/instructions.md:490`, which uses `copy-pwd` as the canonical example of the kebab-case
naming rule — leave it and the style guide cites a dead command. `README.md` and
`docs/features.md` have zero references.

**Aliases:** keep `copy-pwd` and `open-pwd`. `op` is the judgement call — two characters, the
strongest muscle memory of the three, and its entire value is brevity against a 9-character
`here open`. Note it already shadows the 1Password CLI (`op`) on both platforms; keeping it
keeps that collision, which this finding does not create.

**Filed separately, not bundled:** `clr` (`listing.ps1:155`) is a `Set-Alias` to `clear` — a
command that already exists and is already short — registered under 📂 ENHANCED FILE OPERATIONS
despite having nothing to do with files. It shares a domain, not a noun, and retiring it costs
real muscle memory for two keystrokes. Decide it on its own.

---

## 6 · Do not touch

These are constraints, not oversights. Several are documented as deliberate in the source, and
one of them is enforced by CI.

**Coreutil and shell-builtin names — 20 surfaces.** `rm`, `mv`, `cp`, `cat`, `ls`, `la`, `ll`,
`mkdir`, `touch`, `rmdir`, plus the bash builtins `export`, `unset`, `source`, `alias`,
`unalias`, `jobs`, `fg`, `bg`, `history`, and `shutdown`. `platform/linux/bindings.ps1` exists
to keep PowerFlow's versions from shadowing GNU coreutils on Linux — PowerFlow's `rm` and `mv`
are re-exposed as `del` and `mvf` there, and the rest defer to the native tools. The Linux CI
job asserts that `rm`, `mv`, `cp`, `cat`, `mkdir`, `touch`, `rmdir`, `which` and `grep` all
resolve to `Application` (a native binary). Renaming any of these breaks a release, and for the
bash builtins renaming destroys the entire point of `bash-compat.ps1`, which is that muscle
memory works.

**Universal shell idioms.** `..`, `...`, `....`, `.....` (`directory.ps1:65`), `~`
(`:209`), and `cd-` (`:218`). Punctuation names, but every shell user knows them.

Two notes on these rather than renames. The registry declares `...`, `....` and `.....` as
*aliases* of `..` (`directory.ps1:237`) but they are four distinct functions going up 1/2/3/4
levels — they are not aliases, and the synopsis also omits the target-directory feature
entirely, which is the most useful half of the command. And **`back`/`cd-` is dead code**: it
reads `$global:NAV_HISTORY`, and a repo-wide grep finds that variable nowhere except the two
lines that read it (`:219-220`). Nothing ever writes it, so `back` always prints "No previous
directory in history" while being registered as working (`:239`). Any decision about this name
should be a decision about whether to *implement* it.

**The teaching brothers — `components/shell/brothers.ps1`.** `changemode`, `changeowner`,
`changegroup`, `defaultmode`, `whoamifull`, `mygroups`, `lookupentry`, `findfile`, `findtext`,
`removefile`, `listfiles`, `fileinfo`, `makelink`, `firstlines`, `lastlines`, `dirsize`,
`diskfree`, `listdisks`, `listports`, `listprocs`, `stopproc`, `systemlogs`. These are
constrained by purpose, not by policy: each is the full-word name for a cryptic real command,
and each prints the real command it wraps. Folding `dirsize`/`diskfree`/`listdisks` into
`storage` (§4.3) would break that contract, which is why §4 stops at a three-way reduction
rather than a one-way one. The names are ugly by design.

Three observations that are *not* rename proposals but should not be lost:

- **`service` is a genuine shadowing bug.** `/usr/sbin/service` is a real binary on
  Debian/Ubuntu, and `brothers.ps1`'s own justification for the pattern is that "a brother name
  is not a real command and shadows nothing" — which is false for this one. A PowerShell
  function beats a native binary, it is **not** in `platform/linux/bindings.ps1`'s removal list
  and **not** in the CI no-shadow assertion. It also inverts the brother mapping: the brother
  name is the *old* SysV tool and the "real" command is the newer `systemctl`.
- **`systemlogs -u jellyfin -e`** (`brothers.ps1:176`, registration `:229`) is literally
  "the logs for this service" — `dkr logs <name>` in every respect except spelling, with the
  refinement expressed as a flag. It is the single clearest one-to-one mapping onto the
  reference anywhere in the tree, and it is out of scope only because it is a brother.
- **`listports -tulpn`** (the registered example) is a five-letter bundled flag blob the user
  must memorise — the clearest contradiction of "never make users memorise flags" in the
  tree. The useful thing should be what bare `listports` does. Same for `dirsize -sh *`.

**Deliberate short forms.** `z` (`nav.ps1:361`) is borrowed z/zoxide muscle memory — the point
is that it is unguessable. `l` (`lessons.ps1:722`) is a `Set-Alias` to `lesson`. Both stay.

**Names documented as deliberate in the source.**

- `nav b .` — `nav.ps1:132-134` records the owner typing exactly that and getting "Bookmark '.'
  not found", and `CHANGELOG.md:262-263` shipped it as a headline feature.
- `nav --anchor`'s legacy `--start-repo` spelling, kept "because that is what the owner first
  reached for". That comment is evidence, not debt — it records that the flag name is not the
  word users grope for. (The flag *shape* is still the sharpest contradiction of the reference
  inside `nav`: `nav.ps1:32` says outright that "--anchor is a VERB, not a starting point",
  while its sibling `nav anchors rm` is already a word. `nav anchors add .` would resolve it
  with no new vocabulary.)
- `pmx vm clone`'s rewrite comment records that the old form was "four flags, three flag names
  to remember, and the magic value auto", replaced by two positional words because
  `pmx disk grow 101 50G` already read that way. That is the reference rule being applied
  successfully in a second domain, and it is the best in-tree precedent for §5.
- `lesson` exists *because* the flag form (`chmod -lesson`) was tried and removed —
  `lessons.ps1:630-655`. The brothers' surviving `-lesson` flag is the vestige.
- `storage.ps1:28-33` — the `-D` rejection quoted in §2.1.
- `docs/plan/github/org-clone.md:30-33` records the decision that `gh-l-org` should be a
  separate function "consistent with the existing pattern (gh-l-reset, gh-l-status)". §5.10
  overturns it, so it needs a superseding note rather than a silent edit.

**`git-rl` and the `docs/git-rl/` directory.** `CLAUDE.md:90` and `:101` name `git-rl` as the
release command; `release.ps1:31-42` reads the directory path at runtime and
`release-validate-linux.yml:168-171` assert the files survive install. The directory name is
load-bearing. See §5.5.

---

## 7 · Recommendation

### 7.1 The rule

Five lines, and it is the rule `dkr`, `pmx`, `srv`, `nav` and `storage` already follow:

> 1. **The command is a noun the user already thinks in** — or a recognisable shortening of
>    one. Never the initials of a name PowerFlow invented.
> 2. **What to do with it is a word after the noun**, registered as its own `pwsh-h` row.
> 3. **A flag may only modify an action already named.** If a flag decides which screen you
>    see, it should be a word.
> 4. **Values are positional**, not flags — `storage D:`, `pc cap 85`, `pmx disk grow 101 50G`.
> 5. **Ambiguity opens a picker**, never a bare error or a raw parameter prompt.

Two corollaries the audit earned:

**Register the readable name as `-Name` and the short form as `-Aliases`.** Every family does
this except git (§5.5). It costs one line and nothing at the shell.

**A rename is a router, not a move.** `storage.ps1:264-278` is the pattern: the new noun
dispatches to the existing function unchanged. No behaviour moves, so nothing regresses, and
the old name keeps working for free.

And one mechanical rule that will otherwise be rediscovered painfully in every finding:
**PowerShell `Set-Alias` cannot carry an argument.** No old name can be aliased to
`<noun> <word>` — each must remain a wrapper *function*, and each such function must appear in
some `-Aliases @(...)` or the help gate fails the release.

### 7.2 Staged migration

**Stage 0 — fix now; not renames, and not optional.** These are defects, and none needs a
naming decision.

| Fix | Cost |
|---|---|
| §5.1 `git-bd` force-deletes under the safe spelling (= `DECISIONS.md` §1.2) | 1 code file, 1 doc line |
| §5.2 `git-f`'s synopsis says "fetch"; body destroys ignored files | 1 line to fix the synopsis |
| §5.3 `git-next`'s synopsis describes a real, opposite command | 1 line |
| §5.6(1) `git-sh` registered as a command with a false synopsis | 2 lines |
| §5.9 `prev-t` registered as an alias of a different function | 1 line |
| §5.12 `pwsh-reminders` backslash path silently reverts on Linux | 2 lines |
| §5.13 `pwsh-recovery` option 5 deletes `$PROFILE` with no backup | ~10 lines, reuses `:114-125` |
| §5.16 `here` registered as having "quick actions" it does not have | 1 line |
| add a case-fold duplicate check to the help gate | ~6 lines |

The last one is worth more than any single rename: `Sort-Object -Unique` and `-notin` are both
case-insensitive, so the existing gate is structurally blind to the whole §5.1 bug class.

**Stage 1 — safe now: new canonical name, old name retained as alias.** Minor bumps. Ordered
cheapest first.

| Rename | Blast radius |
|---|---|
| §5.5 flip four git registrations | 4 one-line edits, zero behaviour change |
| §5.4 `rn` → `rename-file` | 1 code file, 3 docs |
| §5.16 `here copy` / `here open` | 2 code files, 4 doc lines |
| §5.14 `nav bookmarks add/rm/rename` | 3 code files, 9 doc lines |
| §5.15 `path add` (rename only, no new verbs) | 1 code file + one CI smoke-list line |
| §5.9 the `tab` noun | 1 code file rewritten, 5 docs |
| §5.8 `git-rollback` | 3 code files, 6 doc lines |
| §5.10 `gh-l org` / `gh-l auth` | 1 code file, 6 docs |
| §5.11 `pc` | 4 code files, 4 docs, ~20 hint strings |
| §5.12 `config` | 5 code files, 12 files of user-facing text |

`storage` (§4) is already in this stage and already written — it only needs committing, plus
the two tidy-ups in §4.3.

**Stage 2 — needs a major version**, because a public name leaves the surface:

- §5.2 retiring `git-f` (a deprecation stub that refuses, not a forwarding alias).
- §5.3 retiring `git-next` (the `git-extras` collision is the reason for the rename).
- §5.7 retiring `git-a-plus`.
- §5.1 `git-bD` — unavoidable, since PowerShell cannot make the name distinct.
- §5.4 dropping `rn` — and dropping it is what actually buys the safety.

**Stage 3 — features these renames reveal, costed separately.** Do not let a rename grow a
tail: `git-stash save` (§5.6), `path list` / `path rm` (§5.15), bare `tab` status (§5.9), bare
`storage apps` overview (§4.3), the `Show-BookmarkList` fzf rewrite (§5.14), and
`Save-PFSecret`/`Remove-PFSecret` (§5.10).

**Not worth doing.**

- **Renaming `git-rl`.** Forty-plus lines of prose, a hardcoded directory name, a CI assertion
  and `CLAUDE.md` itself all say `git-rl`. §5.5's asymmetry — move everything around it — is
  the right answer.
- **Renaming the coreutil and brother names.** §6.
- **`storage -D -s`.** §2.1. If the flag form is wanted anyway, reverse `storage.ps1:28-33`
  explicitly and record why; do not run two conventions side by side.
- **`clr`.** Two keystrokes of muscle memory against nothing.
- **`git-s` → `git-status` on its own.** A wash unless the whole family flips (§5.5, §5.6).

### 7.3 The single highest-value change

If only one thing happens: **Stage 0.** Nine small edits, no naming decision required, and two
of them are data-loss defects that `pwsh-h` currently advertises as safe. Every rename in
Stage 1 can wait indefinitely; §5.1 and §5.2 should not wait at all.

---

## 8 · Open questions for the owner

1. **`storage -D -s`, or `storage D:` / `storage big`?** §2.1. This is the fork everything else
   hangs off, and the answer is already written in `storage.ps1:28-33` — so the real question
   is whether to keep that decision or reverse it in writing.
2. **Commit `storage` as it stands?** It is untracked, registered, tested and documented in
   `COMPONENTS.md:185`. Answering (1) either way should probably be the same commit.
3. **Do `installed-apps` and `disk-big` keep their own `pwsh-h` rows, or become `-Aliases` on
   `storage apps` / `storage big`?** §4.4. Today 🗄️ DISK RECLAIM shows six rows for four
   behaviours. Presentation only, no behaviour change.
4. **`pc`, or `machine` / `vitals`?** §5.11. `pc` is a transposition from `cp` and one edit from
   `ps`. Not dangerous, but real.
5. **`config` as a head noun, or keep `pwsh-config` as the head with words under it?** §5.12.
   The first claims the shell's most general word; the second leaves a `pwsh-` name on a
   command that changes the OS.
6. **Does `path` mean the whole PATH or only PowerFlow's entries?** §5.15. Both new verbs are
   blocked on this, and `platform/linux/adapters/env.ps1:11-14` already argues one side.
7. **Is `grba` worth retiring?** §5.8. The case is sound, but the keystroke tax is paid
   entirely by the owner.
8. **Is `op` worth keeping?** §5.16. Two characters against a 9-character `here open` — and it
   shadows the 1Password CLI either way.
9. **Should `back`/`cd-` be implemented or removed?** §6. It has been dead since it was
   written, and it is registered as working.
10. **Does the `-lesson` flag on the brothers survive?** It is the vestige of a design
    `lessons.ps1:630-655` records as already removed once, and it is the last flag-as-selector
    in the teaching layer.

---

## 9 · Appendix: full inventory

All 201 user-facing command surfaces, in load order by domain. Format:

**`name` (aliases)** · family / guessability · user noun · `file:line`
*For* — the goal in the user's words, not the implementation.
*Note* — naming observations, collisions, and drift between the registered synopsis and the
body. Paths are repo-relative.

Guessability is scored as "could a user who knows the goal but not this tool find the name":
**obvious** (they would type it), **guessable** (they would find it on the second try or from
a section heading), **cryptic** (they would not find it).

---

### System — `components/system/`

**`installed-apps` (`i-a`)** · other / guessable · disk · `apps.ps1:268`
*For* — "My drive is full — show me which installed programs are big enough to be worth
deleting, and let me get rid of one right here." Enumerates installed apps at 1 GB or above
inside one size band, then hands the chosen one to an action menu: open its folder, copy its
path, run its real uninstaller, send it to the Recycle Bin, or permanently delete it (typed-name
confirmation).
*Note* — Noun-phrase with no verb (adjective + noun), so it cannot grow word verbs the way
`dkr logs` does; there is nowhere to hang the uninstall and delete verbs that already exist
inside it as a numbered menu. `-o`/`-Overview` chooses **what runs** (all-bands summary instead
of one band), which is the flag-as-selector the reference forbids; the overview is arguably the
most useful bare behaviour, since bare currently throws a band menu at you first. `-Measure` and
`disk-big -Path` are legitimate modifiers. `i-a` is a cryptic initialism. Shares the noun with
`disk-big`, and `pc-whoami`'s own low-disk warning hard-codes `installed-apps 1gb-5gb` as its
hint (`health.ps1:196`), so machine health already treats these as one topic. See §4.

**`disk-big` (`d-b`)** · other / guessable · disk · `apps.ps1:343`
*For* — "Something huge is eating my drive and it is not an app." Walks the immediate children
of the known hot-spot folders (or one `-Path`), sizes each folder and file, and lists whatever
falls in the chosen band — the 169 GB docker vhdx, the 30 GB node_modules, the ISO in
Downloads — then offers the same open / copy / trash / permanent-delete menu, with extra guard
rails for virtual disks.
*Note* — Noun + **adjective**, not noun + verb: `disk big` is one token from being dkr-shaped,
but "big" is a filter, not an action, so the real verbs stay trapped in a numbered menu. Sits in
a four-way split for one noun: `disk-big` (hyphen) plus `diskfree`, `listdisks` and `dirsize`
(squashed, `brothers.ps1`). Those three are deliberately-taught coreutil brothers and are
constrained (§6); `disk-big` is not. `d-b` is cryptic.

**`pwsh-profile`** · prefixed-family / guessable · config · `config-files.ps1:12`
*For* — "Open my PowerShell profile so I can edit it" — one keystroke instead of remembering
where `$PROFILE` lives. Opens it in the configured editor, or says it does not exist.
*Note* — One of three file-openers that differ only in which file they open — a textbook case
for one noun plus word verbs. The `pwsh-` prefix means "PowerFlow's own", which is not a noun a
new user reaches for; they think "config" or "settings". §5.12.

**`pwsh-starship`** · prefixed-family / cryptic · config · `config-files.ps1:21`
*For* — "I want to change how my prompt looks" — opens `starship.toml` in the editor (path
resolved per-OS by the adapter), or reports that it could not be found.
*Note* — Names the third-party tool, not the goal: someone who wants to change their prompt has
to already know PowerFlow's prompt is Starship. "prompt" is the noun; "starship" is the
implementation. §5.12.

**`pwsh-settings`** · prefixed-family / cryptic · config · `config-files.ps1:32`
*For* — "Open Windows Terminal's settings.json so I can edit the terminal itself" (fonts,
profiles, keybindings). On Linux it prints that there is nothing to open.
*Note* — The worst collision in the slice, and a semantic inversion rather than a spelling one:
this opens **one JSON file** while `pwsh-config` changes the **operating system**. Registered
`-Platform 'Windows'` although the function is defined on both and degrades with a message
(`:36`), so Linux users are denied a message that exists. §5.12.

**`pwsh-font`** · prefixed-family / guessable · font · `fonts.ps1:28`
*For* — "My prompt and my `ls` are drawing boxes instead of icons — fix it." Installs the Nerd
Font via the adapter if missing, then prints the one step no tool can do for you (pointing the
terminal at the font). `-status` reports and changes nothing.
*Note* — `-status` is a flag doing a word's job, and the command has exactly two modes so the
word costs nothing. Belongs to the same "how my terminal looks" cluster as `pwsh-starship` and
`pwsh-settings`. §5.12.

**`pc-whoami`** · other / guessable · machine · `health.ps1:70`
*For* — Two jobs behind one name. (1) "What is this machine and is anything wrong with it?" —
CPU/GPU/RAM spec, every physical drive with free space, upgrade headroom from SMBIOS,
motherboard, BIOS age, power plan, CPU cap, hardware faults, crash dumps, each warning naming
the drill-in that explains it. (2) "What is eating my memory, and close it" — `-ram` opens a
five-level memory map, a level, or one named program's processes with command lines, and that
last view is the **only place in PowerFlow a process can be killed**.
*Note* — The clearest flag-as-selector in the tree, and the parameter block documents the cost
in a twelve-line comment (`:71-90`). Half the command is already right: the `-ram` sub-tree
takes word arguments. `-days`, `-min`, `-export` are genuine modifiers. Near-collision:
`whoamifull` (`brothers.ps1:147`) answers "who am I" about the **user**. §5.11.

**`pc-cap`** · noun-verb / guessable · cpu · `health.ps1:779`
*For* — "Throttle this machine's CPU — it is running hot — and guarantee I can put it back
exactly as it was." Bare shows the current cap and any outstanding record; a number sets it
after writing the prior state to disk **first**; `restore` puts it back, verifies by re-query,
and only then forgets the record. Refuses to overwrite an existing record so 100→85→70 cannot
bury the true original.
*Note* — Already dkr-shaped and one of the two best-named commands in the slice: bare does the
useful read-only thing, the refinement is a word, the argument is a value. No flags at all.
`pc-whoami` banners while a cap record exists, so the pairing already reads as one noun with two
verbs. §5.11.

**`pwsh-autologin`** · prefixed-family / guessable · login · `login.ps1:32`
*For* — "Make PowerFlow come up by itself when I log into this server — or stop it" without
re-running the installer. Toggles the guarded `~/.bashrc` hook via the adapter (deliberately
fail-safe: if pwsh vanishes you still land in bash). On Windows it explains there is no hook,
because `$PROFILE` always loads.
*Note* — Already takes word arguments (`on`/`off`/`status`, bare = on) with no flags. Registered
`-Platform 'Linux'` but runs on Windows to print the explanation, which is the right behaviour.
Pairs with `pwsh-exit`.

**`pwsh-exit`** · prefixed-family / cryptic · shell · `login.ps1:104`
*For* — "I need a plain bash prompt on this server but I do NOT want to drop my SSH session."
When PowerFlow is the login shell, plain `exit` disconnects you because there is no bash
underneath; this starts bash as a child so the connection stays up.
*Note* — The name says the opposite of the point: it is one word from the builtin `exit`, and
the entire reason it exists is that `exit` does the destructive thing while this does not. A
user guessing by name would expect it to quit. "bash" or "shell" is the noun they reach for.
Note `close-ct` (`tabs.ps1:27`) is literally `exit` and is the footgun this prevents — three
commands now overlap on "end this session".

**`set-path`** · other / guessable · path · `path.ps1:12`
*For* — "I just installed a tool and the shell cannot find it — add its folder to PATH for
good." Appends to the persistent User PATH (or System with `-System`, where the adapter owns
elevation), skips if already present, warns but still adds if the folder does not exist, and
makes it live in the current session. Accepts unquoted multi-word paths.
*Note* — Reads like a PowerShell `Set-*` cmdlet, i.e. as though it **replaces** the PATH, when
it appends. There is no way to list or remove an entry, so its one verb is both misleading and
lonely. `-System` is a legitimate modifier. §5.15.

**`shutdown` (`s`)** · coreutil-name / obvious · power · `shutdown.ps1:11`
*For* — "Turn this machine off in an hour and a half." Accepts additive time tokens (`1h 30m`),
enforces a 10-minute floor and 6-hour ceiling so nothing shuts down out from under you, and
cancels a pending shutdown with a word.
*Note* — Do not rename, but check the shadowing: this takes the name of a native binary on both
platforms and, unlike `rm`/`mv`/`cp`/`cat`, it is **not** in `platform/linux/bindings.ps1`'s
rename or defer sets — so on Linux a PowerShell function outranks `/sbin/shutdown` with
different semantics (`shutdown now` and `shutdown -h now` are both rejected as an invalid
token). Second problem: `s` is a real **function**, not a `Set-Alias`, and the two disagree —
`shutdown cancel` works, `s c` works, `shutdown c` errors. Third: `s` is one substitution from
`l` (`lesson`) and `z` (`nav`), so the most destructive command in the slice is one keystroke
from two harmless ones. `cancel` is already a word, which is the right shape.

**`start-folder` (`startup`)** · other / cryptic · startup · `startup.ps1:48`
*For* — "What starts up with this machine, and how do I stop one of them?" — the answer the OS
does not give anywhere, merging the Startup folders **and** the registry Run keys on Windows
(with each entry's real enabled/disabled state, since Task Manager disables by flag) or XDG
autostart files on Linux. The fzf picker is the manager: Enter toggles (reversible, so no
confirm), ctrl-d deletes behind a typed-name confirm, ctrl-o opens the folder.
*Note* — The noun is factually wrong and the shape misleads twice: it reads as Verb-Noun
(`Start-Folder`), i.e. "start a folder", using PowerShell's own `Start-*` verb when nothing is
started; and "folder" is stale, because the command's own header says its selling point is that
it **also** covers the registry Run keys, which are not a folder. The alias `startup` is the
accurate name and should be the command. Everything else is already dkr-shaped — bare lists and
picks, refinements are words (`list`, `add <path>`, `open`), no selector flags. A pure head-noun
rename.

**`pwsh-config`** · prefixed-family / guessable · settings · `sysconfig.ps1:45`
*For* — "Change a system setting without knowing what the command for it is called." One fzf
menu listing every changeable setting **with its current value** — timezone, locale, hostname,
time-sync, keyboard on Linux — plus PowerFlow's own "User folders" preference, then applies the
change. `pwsh-config tz` jumps straight to one through a friendly-word table.
*Note* — Refinement is already a word with generous synonyms (`kb`/`keys`, `tz`/`time`,
`loc`/`lang`, `host`/`name`, `ntp`/`sync`), bare already browses and picks, and there are no
flags at all — this, `pc-cap` and `team-room` are the creed working. The problem is purely the
collision with `pwsh-settings`. Note it quietly owns a non-OS setting (user-folders,
`Owner='powerflow'`), so "system config" is already slightly narrower than what it does;
`roots.ps1:563` points users here for it. §5.12.

**`team-room`** · noun-verb / cryptic · agents · `team-room.ps1:249`
*For* — "Something is waking AI agents on my machine in the background — show me what is live
and turn it off." Lists every room with all **three** independent states (the boot-scoped arm
stamp, the scheduled connector task, and any live watcher process) rather than collapsing them
into a fake on/off; `<name>` gives the detail; `stop <name>` disarms and kills watchers,
`start <name>` re-arms, and `-All` extends either to the scheduled task. Exists because the only
previous way to stop a watcher was to ask an agent to stop it.
*Note* — The most dkr-shaped command in the slice: noun, bare lists, verbs are words, verbs are
checked **before** names so a room called "stop" cannot be hit by accident, and `-All` is a true
modifier. Two soft misses: an ambiguous or unknown name prints the list instead of offering a
picker, and the head noun is jargon — a user who notices background agent activity does not know
the phrase "team room". Also filed under 🖥️ MACHINE HEALTH, which is not what it is.

**`storage`** · noun-verb / obvious · disk · `storage.ps1:248` *(untracked)*
*For* — "Where did my space go?" Every volume, fullest first, with a used bar and headroom
colouring; a volume name drills into one; `apps`, `big` and `docker` are word verbs.
*Note* — Not in the 201 count because it is in-flight (`?? components/system/storage.ps1`).
It is the reference rule applied to this audit's own worked example, and its header
(`:28-33`) contains the `-D` rejection quoted in §2.1. §4.

---

### Files — `components/files/`

**`ls`** · coreutil-name / obvious · folder contents · `listing.ps1:36`
*For* — See what is in a folder — and, with a `-<root>` flag, see what is in a folder somewhere
else without cd-ing there first.
*Note* — Constrained (§6); do not propose renaming. Two observations: it has a **second, hidden
job** — `ls -srv complete` calls `Get-PFNamedRoots` and `Resolve-PFRootedDirectory` and can open
an fzf picker, so a chunk of `nav` lives inside the listing command; and `-srv`/`-pics` are flags
that **choose which directory**, i.e. refinement expressed as a flag. `ls -recurse` is also
accepted as a single-dash long flag, breaking the file's own stated rule that single dash belongs
to Linux.

**`la`** · coreutil-name / obvious · folder contents · `listing.ps1:152`
*For* — See the hidden dotfiles too, without remembering which flag does that.
*Note* — Constrained: GNU convention name (`ls -a`).

**`ll`** · coreutil-name / obvious · folder contents · `listing.ps1:153`
*For* — See sizes, dates and permissions rather than just names.
*Note* — Constrained: GNU convention name (`ls -lh`). Collision hazard: `bash-compat.ps1`'s own
doc examples use `alias ll='ls -la'`, and `alias` refuses to shadow rm/mv/cp/cat/ls/chmod/chown/sudo
but **not** `ll` — so a user following the documented example silently replaces PowerFlow's `ll`.

**`clr`** · other / guessable · screen · `listing.ps1:155`
*For* — Wipe the screen when the scrollback has become noise.
*Note* — Vowel-dropped abbreviation of `clear`, a command that already exists and is already
short — it saves two keystrokes. Odd that it is registered in 📂 ENHANCED FILE OPERATIONS at
all: it has nothing to do with files. §5.16 files it separately.

**`cat`** · coreutil-name / obvious · file contents · `listing.ps1:159`
*For* — Read a file's contents onto the screen.
*Note* — Constrained. A `Set-Alias` to `Get-Content` that exists only because Windows has no
`cat`; `platform/linux/bindings.ps1` strips it so GNU `cat` wins.

**`cp`** · coreutil-name / obvious · file · `listing.ps1:161`
*For* — Duplicate a file to another location.
*Note* — Constrained. Worth noting the family incoherence it sits in: `cp` copies a file to a
path, while `cf`/`copy-file` in the same domain "copies" a file to a clipboard slot — same
English verb, two unrelated mechanics.

**`open-pwd` (`op`)** · noun-verb / guessable · folder · `clipboard.ps1:21`
*For* — Get the folder I am standing in onto the screen in the graphical file manager, so I can
drag things or double-click something.
*Note* — `pwd` in the name is shell jargon for "here". Near-collision: `copy-pwd`
(`directory.ps1:230`) copies the path text, so the tree has a `<verb>-pwd` micro-family of two
that nobody would find as a family — they are in different files and different `pwsh-h`
sections. §5.16.

**`op`** · squashed-words / cryptic · folder · `clipboard.ps1:41`
*For* — Same as `open-pwd`.
*Note* — Implemented as a real **function** wrapping `open-pwd` rather than a `Set-Alias`, so
CI's alias-coverage gate cannot see it as an alias; it is registered only via `-Aliases` on
`open-pwd`. Two letters, no mnemonic link to "folder". Also shadows the 1Password CLI (`op`) on
both platforms.

**`paste-file` (`pf`)** · noun-verb / obvious · file · `clipboard.ps1:45`
*For* — Drop a copy of the file I marked earlier into the folder I am in now, and sort out the
name clash if there already is one.
*Note* — **Not** the OS clipboard: it stores the literal text `FILE:<path>` via
`Copy-ToClipboard`, so it does not interoperate with Explorer's Ctrl-C/Ctrl-V and it silently
clobbers whatever text you had copied. `-Force` **changes what happens** (auto-renames to
"name - Copy" instead of asking), and `-Path` is a flag where the reference would use a bare
word. `pf` is one edit from `cf` in the same file, and the two do **opposite** things.

**`pf`** · squashed-words / cryptic · file · `clipboard.ps1:213`
*For* — Same as `paste-file`.
*Note* — One edit from `cf` (`copy-file`), which does the inverse operation — a mistyped letter
silently performs the other half of the workflow. Also a function, not a `Set-Alias`. Blocks
`pf` as a short form for `powerflow` (§5.13).

**`copy-file` (`cf`)** · noun-verb / obvious · file · `clipboard.ps1:180`
*For* — Mark a file now so I can drop a copy of it somewhere else after I have navigated there.
*Note* — Synopsis drift: the registry says "copy a file to the clipboard (fzf picker)" but there
is no picker in the body — `$filePath` is `Parameter(Mandatory)`, so bare `cf` drops the user
into PowerShell's raw "Supply values for the following parameters" prompt. That is the opposite
of "ambiguity gets a picker", and `rm` and `rn` in the same domain **do** have the picker, so the
inconsistency is internal. Also: the name says "copy" but nothing is copied until `pf` runs; it
is really a cut-style hold.

**`cf`** · squashed-words / cryptic · file · `clipboard.ps1:208`
*For* — Same as `copy-file`.
*Note* — One edit from `pf`, which does the inverse. Its own `[string]$filePath` is **not**
mandatory (unlike `copy-file`'s), so bare `cf` fails with an empty path instead of prompting —
the same command with two behaviours depending on which spelling you use.

**`rm`** · coreutil-name / obvious · file · `operations.ps1:72`
*For* — Delete things, and be asked to confirm first unless I say `-f`; with no arguments it
shows a picker of this folder so I can choose what to bin.
*Note* — Constrained. On Linux this function is deleted and re-exposed as `del`, so the same
behaviour answers to two names depending on OS. **One edit from `rn`** (rename, same domain) —
the most dangerous adjacency in the slice (§5.4). Note `removefile` (`brothers.ps1:154`) is a
third spelling of deletion with GNU rather than PowerFlow semantics.

**`mv`** · coreutil-name / obvious · file · `operations.ps1:298`
*For* — Either move/rename something right now, or — with one argument — pick it up and hold it
so I can carry it to another folder and drop it there.
*Note* — Constrained. But it is **two commands wearing one name**, disambiguated by argument
count (2+ args = a real move, 1 arg = cut-and-hold), plus a third mode where bare `mv` prints a
help menu. The one-argument cut runs a three-phase fuzzy search (exact → contains → append
`.txt`/`.md`/`.json`/…), so `mv report` can pick up a file the user never named. `-detailed` is
accepted in both single- and double-dash form despite the project rule. Re-exposed as `mvf` on
Linux.

**`mv-t`** · cryptic-suffix / cryptic · file · `operations.ps1:588`
*For* — I cut a file, I have since walked to where I want it, put it down here.
*Note* — The `-t` is never explained ("to"? "there"?). Three collisions: one edit from `mv-c`,
which does the opposite (abandon vs commit); `-t` means **tab** everywhere else in the tree
(`open-t`, `close-t`, `next-t`, `prev-t`, `close-ct`); and it is the paste half of a hold/paste
pair whose copy half is spelled completely differently (`cf`/`pf`). Refuses outright if source
and destination directory are the same, rather than offering a rename.

**`mv-c`** · cryptic-suffix / cryptic · file · `operations.ps1:668`
*For* — Forget the file I cut — I changed my mind.
*Note* — `-c` for cancel, but `-c` is also "never create" in `touch` and "current tab" in
`close-ct` — the letter is overloaded across the tree. One edit from `mv-t`, opposite effect. A
dkr-shaped tree would spell these `mv drop` / `mv cancel`, except `mv` is a coreutil name, so
the whole hold/paste workflow probably wants to leave the `mv` name entirely — it already does
on Linux, as `mvf`.

**`rmdir`** · coreutil-name / obvious · folder · `operations.ps1:688`
*For* — Get rid of a folder — and if it turns out not to be empty, be asked whether to take
everything inside with it.
*Note* — Constrained; deferred to GNU on Linux, so this body only ever runs on Windows.
Behaviour deliberately **diverges** from GNU: real `rmdir` simply fails on a non-empty
directory, this one offers to recursively delete it. That makes it a softer `rm -r` wearing
`rmdir`'s name, so a Linux user's reflexive "rmdir is safe" assumption does not hold. Accepts
`-p`/`--parents` in the LongMap but never reads the flag.

**`touch`** · coreutil-name / obvious · file · `operations.ps1:750`
*For* — Make an empty file to start working in, or mark an existing one as changed-now.
*Note* — Constrained; deferred to GNU on Linux. Carries a scar comment: the old one-liner used
`New-Item -Force` and silently truncated existing files to zero bytes.

**`mkdir`** · coreutil-name / obvious · folder · `operations.ps1:809`
*For* — Make a folder, and with `-p` make the whole nested path in one go.
*Note* — Constrained; deferred to GNU on Linux. `-p` is a genuine **modifier**, so it is legal
under the reference rule.

**`rn`** · squashed-words / guessable · file · `rename.ps1:23`
*For* — Give a file a different name, picking it out of a list if I cannot remember what it is
called.
*Note* — **One edit from `rm`** in the same domain, and both accept a bare filename and both
resolve fuzzy names, so the wrong one runs without an error to warn you. Mechanically odd: the
"new filename" box is fzf's `--print-query` over a list of static help text, i.e. fzf used as a
text-input widget; and it only ever renames **files** (directories are filtered out), so
"rename this folder" silently has no command. Also deviates from the tree's fzf convention — a
hand-rolled numbered `Read-Host` list for multiple matches, where `ls`, `srv` and `rm` use fzf.
§5.4.

---

### Shell — `components/shell/`

**`export`** · coreutil-name / obvious · environment variable · `bash-compat.ps1:35`
*For* — Set an environment variable for this session the way I would in bash, instead of
learning `$env:` syntax; bare `export` lists them all.
*Note* — Constrained in spirit: a bash **builtin** name, deliberately chosen so muscle memory
works; renaming destroys the point of the file. Not a coreutils binary, so no Linux shadowing
risk. Already dkr-shaped by accident: bare does the useful thing, an argument refines.

**`unset`** · coreutil-name / obvious · environment variable · `bash-compat.ps1:66`
*For* — Get rid of an environment variable I set earlier.
*Note* — Constrained in spirit. Quietly does double duty: falls through to `Remove-Variable` for
PowerShell variables, which bash users will not expect. Silent no-op if the name does not exist,
unlike `unalias` right below it which reports not-found.

**`source`** · coreutil-name / obvious · environment variable · `bash-compat.ps1:87`
*For* — Load the variables out of a `.env` or a script into the shell I am sitting in, rather
than a child process that throws them away.
*Note* — Constrained in spirit. Honest about its limit (parses `KEY=value` lines only, cannot
execute bash syntax), but that means `source setup.sh` on a real script reports
success-ish behaviour after importing almost nothing. Uses `Parameter(Mandatory)`, so bare
`source` drops to PowerShell's raw parameter prompt rather than a picker of nearby `.env` files.

**`alias`** · coreutil-name / obvious · alias · `bash-compat.ps1:138`
*For* — Make a short name that stands in for a command **with** its arguments — the thing
`Set-Alias` cannot do; bare `alias` lists what I have made.
*Note* — Constrained in spirit. Compiles to a global function via `Invoke-Expression`, so an
alias body is executed as PowerShell source. Its shadow-guard denylist is
`@('rm','mv','cp','cat','ls','chmod','chown','sudo')` — a **second, hardcoded list** that does
not match `platform/linux/bindings.ps1`'s (mkdir, touch, rmdir, which, grep are protected there
but not here), so `alias grep='...'` is allowed and would reintroduce exactly the stdin-hang bug
`bindings.ps1` has a backstop for. Aliases are lost on restart — nothing persists them.

**`unalias`** · coreutil-name / obvious · alias · `bash-compat.ps1:178`
*For* — Remove a short name I made, or one PowerShell shipped with.
*Note* — Constrained in spirit. Will happily delete PowerShell's own built-in aliases (the
`Test-Path 'Alias:\$name'` branch), which is more reach than bash's `unalias` has.

**`jobs`** · coreutil-name / obvious · background job · `bash-compat.ps1:200`
*For* — See what I left running in the background and whether it finished or failed.
*Note* — Constrained in spirit. This trio (`jobs`/`fg`/`bg`) is the one place in the slice that
already reads like the reference: bare `jobs` shows the table and prints the two verbs available
under it. It just lacks the picker — `fg` with no id guesses the last Running job instead of
offering a choice.

**`fg`** · coreutil-name / obvious · background job · `bash-compat.ps1:225`
*For* — Pull a background job back to the front and watch it until it is done.
*Note* — Constrained in spirit. Two edits from `bg` and they are near-opposites, but that pair
is inherited from bash so it is defensible, unlike `mv-t`/`mv-c`. Uses `-AutoRemoveJob`, so a
job brought forward is destroyed and cannot be re-listed.

**`bg`** · coreutil-name / obvious · background job · `bash-compat.ps1:241`
*For* — Confirm that something is still chugging away in the background and how to get it back.
*Note* — Constrained in spirit. Does **not** actually resume anything (bash's `bg` un-suspends a
stopped job); it only prints a status line, so the name promises an action it does not perform.
Bare `bg` reports the last job of any state while bare `fg` filters to Running — inconsistent
defaults between the pair.

**`history`** · coreutil-name / obvious · command history · `history.ps1:90`
*For* — See the numbered list of what I have typed so I can find and re-run something.
*Note* — Constrained in spirit; deliberately removes PowerShell's own `history` alias to
`Get-History`. `-Count` is a genuine modifier and is positional, so `history 100` reads as a
word. The file's real feature (`!!` / `!$`) is not a command at all but a pair of PSReadLine key
handlers, so it has no registry entry and cannot appear in `pwsh-h`.

**`changemode`** · squashed-words / guessable · permissions · `brothers.ps1:62`
*For* — Change who is allowed to read, write or run something, while being told the real
`chmod` command I could have typed.
*Note* — Prime cluster member: changemode/changeowner/changegroup/defaultmode/perms are five
commands under one noun, plus `lesson permissions`. `-lesson` is accepted in single- **and**
double-dash form (`^--?lesson$`) and it **chooses what runs** (teach instead of act) — the
pattern the reference forbids; `lesson changemode` already does this correctly as a word. §6.

**`changeowner`** · squashed-words / guessable · permissions · `brothers.ps1:63`
*For* — Hand a file over to a different user (and optionally group), while learning this is
`chown`.
*Note* — One word-edit from `changegroup` and near-identical in effect (chown can set the group
too), so the two overlap rather than partition. Fails with not-available on Windows, by design.

**`changegroup`** · squashed-words / guessable · permissions · `brothers.ps1:64`
*For* — Put a file under a different group so the right team can get at it, while learning this
is `chgrp`.
*Note* — Functionally a subset of `changeowner`. Linux-only in practice.

**`defaultmode`** · squashed-words / cryptic · permissions · `brothers.ps1:79`
*For* — Find out (or set) what permissions brand-new files will be born with in this shell.
*Note* — Worst-named brother: nobody hunting `umask` would guess "defaultmode", and nobody
typing "defaultmode" learns the word `umask` until the hint prints. The only brother not routed
through `Invoke-Brother` (umask is a shell builtin, not a binary), so its `-lesson` handling is
hand-rolled and subtly different — it checks `$args -contains '-lesson'` (exact, single dash)
**or** `$Mask -match '^--?lesson$'`, so `defaultmode --lesson` works but
`defaultmode 022 --lesson` does not.

**`whoamifull`** · squashed-words / guessable · identity · `brothers.ps1:147`
*For* — Find out which user I actually am to the system, and which groups that puts me in.
*Note* — Collision-dense. `whoami` is a real binary on both platforms and this name is a suffix
of it, so the two sit adjacent doing related-but-different things (`id` vs `whoami`).
`pc-whoami` exists elsewhere meaning the **machine's** identity, so "whoami" appears in two
unrelated families. Clusters with `mygroups` and `lookupentry`.

**`mygroups`** · squashed-words / guessable · identity · `brothers.ps1:148`
*For* — Check which groups I belong to, usually to work out why I cannot get at a file.
*Note* — The only brother whose name is first-person, breaking the file's own pattern. Its
output is a strict subset of `whoamifull`'s — two commands, one answer.

**`lookupentry`** · squashed-words / cryptic · identity · `brothers.ps1:149`
*For* — Look up a user or group by name to see whether it exists and what its id is.
*Note* — "entry" is jargon for a database line in nsswitch — a literal translation of
`getent`'s internals, not of the user's goal. With `defaultmode`, the least guessable brother.

**`findfile`** · squashed-words / obvious · file · `brothers.ps1:152`
*For* — Hunt down a file somewhere below here when I only know part of its name.
*Note* — One word-edit from `findtext`, and the pair is a genuine two-member noun family that
would read well as `find file` / `find text`. Also overlaps `nav` and `ls --tree`. On Windows
`find` resolves to `find.exe`, a completely different DOS tool that searches for **strings**, so
`Invoke-Brother`'s `Get-Command find -CommandType Application` check succeeds on Windows and
forwards Linux `find` arguments to the DOS utility.

**`findtext`** · squashed-words / obvious · file contents · `brothers.ps1:153`
*For* — Search inside files for a word or pattern.
*Note* — One word-edit from `findfile`. This is the sanctioned way to reach `grep` —
deliberately **not** a `grep` function, because a PS function does not forward stdin (documented
at length in the file).

**`removefile`** · squashed-words / obvious · file · `brothers.ps1:154`
*For* — Delete a file the plain Linux way, with the real `rm`'s rules rather than PowerFlow's
confirmation.
*Note* — Third spelling of delete with third semantics: `rm` = PowerFlow confirm+picker+recurse,
`del` = the same under a different name on Linux, `removefile` = the raw GNU binary with **no
confirmation at all**. A user who learns "PowerFlow always asks before deleting" is wrong here.
Dead on Windows, and its name says "file" while GNU `rm -r` takes trees.

**`archive`** · other / guessable · archive · `brothers.ps1:155`
*For* — Bundle a folder into one file to move or store it, or unpack one someone sent me.
*Note* — The only brother that is a **bare noun with no verb**, so it reads oddly in a file of
verb-noun compounds — and its two opposite jobs (pack and unpack) are distinguished only by
`tar`'s own cryptic flags (`-cf` vs `-xf`), which is precisely the memorise-the-flags problem
the creed rejects. The strongest dkr-shape candidate among the brothers: `archive pack` /
`archive unpack`, with bare `archive` listing what is in the current folder.

**`listfiles`** · squashed-words / obvious · folder contents · `brothers.ps1:181`
*For* — See what is in a folder, spelled out in full words, while being taught that the real
command is `ls`.
*Note* — The documented **exception** — the only brother that does not shell out to the real
binary; it forwards to PowerFlow's own `ls`. Consequence: its printed "real linux command" hint
never appears (`Invoke-Brother` is bypassed), so the one brother whose lesson would be easiest
to give gives none beyond `-lesson`. Redundant with `ls`/`la`/`ll`.

**`fileinfo`** · squashed-words / obvious · file · `brothers.ps1:158`
*For* — See everything the system knows about one file — size, dates, owner, permissions, inode.
*Note* — Overlaps `perms` and `ll` substantially — three ways to ask "tell me about this file",
one of which (`perms`) is the teaching-rich one. Windows has no `stat.exe`, so Linux-only in
practice despite being registered as Both.

**`makelink`** · squashed-words / obvious · file · `brothers.ps1:157`
*For* — Make a second name that points at the same file, so it appears in two places at once.
*Note* — Its synopsis has to shout "(target FIRST)" because `ln`'s argument order is the classic
trap — a gotcha that a word-verb form or a picker would remove entirely.

**`firstlines`** · squashed-words / obvious · file contents · `brothers.ps1:161`
*For* — Peek at the top of a file without opening the whole thing.
*Note* — One word-edit pair with `lastlines`; both belong under a single noun with word verbs.
Windows has no `head.exe`, so Linux-only in practice.

**`lastlines`** · squashed-words / obvious · file contents · `brothers.ps1:162`
*For* — See the end of a log file, and with `-f` keep watching as new lines arrive.
*Note* — Its `-f`/`--follow` is a textbook legal **modifier** and is exactly the flag pair the
reference cites — preserve it verbatim in any rename. Overlaps `dkr logs -f` conceptually.

**`dirsize`** · squashed-words / obvious · disk · `brothers.ps1:165`
*For* — Find out what is eating my space in this folder.
*Note* — The big cluster and the flag tension. The noun already covers `dirsize` + `diskfree` +
`listdisks` here, plus `disk-big`/`d-b` and `installed-apps`/`i-a` in `apps.ps1` and the whole
🗄️ DISK RECLAIM section — six commands for one noun. This is the cluster the owner floated as
`storage -D -s`; see §2.1 and §4. Note its own registered example is `dirsize -sh *`, i.e. it
already teaches users to memorise bundled flags.

**`diskfree`** · squashed-words / obvious · disk · `brothers.ps1:166`
*For* — Check whether I am about to run out of space before I start a big download or build.
*Note* — Same cluster. One word-edit from `listdisks`, and both answer adjacent questions (space
left vs hardware present) — exactly the "should be one noun" signal.

**`listdisks`** · squashed-words / obvious · disk · `brothers.ps1:167`
*For* — See what drives and partitions actually exist on this machine.
*Note* — Same cluster, and inconsistent with `diskfree` on word order (list-disks vs disk-free)
inside the same six-line block. Windows has no `lsblk`, so Linux-only in practice while
registered as Both.

**`listports`** · squashed-words / obvious · network · `brothers.ps1:170`
*For* — Work out what is already sitting on the port I want, or confirm my service is actually
listening.
*Note* — Its registered example is `listports -tulpn` — a five-letter bundled flag blob the user
must memorise, the clearest violation of "never make users memorise flags" anywhere in the
tree. The useful thing (TCP+UDP listening with process names) should be what bare `listports`
does.

**`listprocs`** · squashed-words / obvious · process · `brothers.ps1:173`
*For* — See what is running so I can find the thing hogging the machine or needing killing.
*Note* — The abbreviation is **inconsistent within the pair** — "procs" here, "proc" in
`stopproc`, three lines apart. A dkr shape would be bare `proc` (table + picker) then
`proc stop`, `proc logs`. Also collides with PowerShell's own `ps` alias for `Get-Process`,
which still resolves and returns objects, so the two give different output shapes.

**`stopproc`** · squashed-words / obvious · process · `brothers.ps1:174`
*For* — Kill something that has hung or is eating the CPU.
*Note* — Requires a numeric PID the user must first get from `listprocs` — two commands and a
copy-paste for one goal, where the creed's answer is a picker. Forwards to `kill`; PowerShell's
`kill` alias exists on Windows but `Get-Command -CommandType Application` filters it out, so
this correctly errors rather than half-working.

**`service`** · other / guessable · service · `brothers.ps1:175`
*For* — Start, stop or check on a background service like jellyfin or nginx.
*Note* — **The one actual shadowing bug.** `/usr/sbin/service` is a real binary on
Debian/Ubuntu, and the file's own justification is that "a brother name is not a real command
and shadows nothing" — false for this one. A PowerShell function beats a native binary, and it
is not in `platform/linux/bindings.ps1`'s removal list nor in the CI no-shadow assertion. It
also inverts the brother mapping: the brother name is the **old** SysV tool and the "real"
command is the newer `systemctl`. And `service status jellyfin` (the registered example) is
`service`'s own argument order, not `systemctl`'s, so the hint prints a command whose argument
order differs from what the user typed. §6.

**`systemlogs`** · squashed-words / obvious · service · `brothers.ps1:176`
*For* — Find out why something died or would not start.
*Note* — Belongs with `service` under one noun: the registered example `systemlogs -u jellyfin -e`
is literally "the logs for this service", i.e. `dkr logs <name>` in every respect except
spelling, with the refinement expressed as a flag. The clearest one-to-one mapping onto the
reference in the tree. `-e` (jump to end) is a legitimate modifier. §6.

**`perms`** · squashed-words / obvious · permissions · `teach.ps1:173`
*For* — Understand what a file's permission string actually means — which column is the owner,
which is the group, and what `x` does on a directory.
*Note* — Already the natural head of the permissions cluster (changemode/changeowner/
changegroup/defaultmode all want to live under it as word verbs) and already dkr-shaped: bare
does the useful thing, a bare word refines it, no flags. Honest Windows refusal rather than a
fake ACL translation.

**`linux-lessons`** · other / guessable · settings · `teach.ps1:36`
*For* — Turn the teaching commentary up or down — or off entirely once I have learned this and
just want plain output.
*Note* — Already dkr-shaped and worth citing as in-tree precedent: bare reports the current
state and lists the options, and the refinement is a **word**. Two frictions: it is a settings
toggle registered under 🎓 LEARN LINUX rather than ⚙️ CONFIGURATION, and it is not in the
`pwsh-*` family that owns every other persisted preference; and plural "lessons" versus the
singular `lesson` command is two names one letter apart where one **sets a mode** and the other
**teaches a command**. §5.12.

**`lesson` (`l`)** · other / obvious · help · `lessons.ps1:667`
*For* — Learn what a Linux command does and how to use it, without any risk of running it.
*Note* — **The best-shaped command in the tree and the model to point at:** bare gives the full
index, refinement is a word (`lesson chmod`, `lesson permissions`), it accepts the real name or
the brother name or a topic, it has tab-completion over all three, it has **zero flags**, and
near-misses get "did you mean" instead of a refusal. It exists precisely **because** the flag
form (`chmod -lesson`) was tried and removed — documented at `lessons.ps1:630-655`. The
brothers' surviving `-lesson` flag is the vestige of that removed design.

**`l`** · squashed-words / cryptic · help · `lessons.ps1:722`
*For* — Same as `lesson`.
*Note* — A single letter, and the only one-character command name. One edit from `ls`, `ll` and
`la` — all three in the same slice and all three listing commands — so it sits in the middle of
the densest short-name neighbourhood PowerFlow has, meaning something unrelated. It is a genuine
`Set-Alias` (unlike `op`/`cf`/`pf`), so CI's alias gate does see it. Deliberate; keep (§6).

---

### Git — `components/git/`

**`git-branch` (`git-b`)** · prefixed-family / obvious · branch · `branches.ps1:11`
*For* — "Show me every branch, local and remote, and let me hop onto one — or get rid of one I
am finished with."
*Note* — This is the real ~130-line implementation and `git-b` is a one-line wrapper, yet the
registry lists `git-b` as **primary** and `git-branch` as its alias (`:378`), demoting the only
guessable name. Body: fzf over local+remote, copies the picked name to the clipboard, then a 1-5
menu (switch / delete local / delete remote / delete both / cancel). Refuses **all** actions if
you pick the current branch, so it cannot be used just to see where you are. Near-homograph of
real `git branch`, so the space form is permanently unavailable. §5.5.

**`git-b`** · cryptic-suffix / cryptic · branch · `branches.ps1:256`
*For* — Same goal as `git-branch`.
*Note* — 1:1 wrapper. One edit from `git-bd`, which **deletes** a branch. `-b` in real git means
*create* a branch (`git checkout -b`), so the letter actively misleads.

**`git-cm`** · cryptic-suffix / cryptic · branch · `branches.ps1:260`
*For* — "Take me back to main."
*Note* — Synopsis drift: registered as "checkout main/master, whichever exists" but the body is a
bare unconditional `git checkout main` — no master fallback, no `$LASTEXITCODE` check, and it
prints "Switched to main branch" even when the checkout failed. `cm` reads as *commit* to most
git users.

**`git-bd` (`git-bD`)** · cryptic-suffix / cryptic · branch · `branches.ps1:265`
*For* — "Delete this branch by name, but only if it is safely merged."
*Note* — **Broken by a case collision, verified at runtime:** `function git-bD` at `:286`
overwrites this one, so after loading only `git-bd` exists and its body is the **force**
version. The documented-safe command force-deletes. Its own hint at `:282` ("Use git-bD to force
delete unmerged branches") points at a name that no longer resolves to anything different. Also:
mandatory branch-name argument, no picker. §5.1.

**`git-bD` (`git-bd`)** · cryptic-suffix / cryptic · branch · `branches.ps1:286`
*For* — "Delete this branch even though it is not merged — I know what I am doing."
*Note* — Distinguished from `git-bd` **only by letter case**, which PowerShell cannot honour, so
it silently wins the collision. Registered as an *alias* of `git-bd` although it does something
materially different. A case-only distinction can never be a valid name here. §5.1.

**`git-c.sb`** · other / cryptic · branch · `branches.ps1:307`
*For* — "Start a new branch for the thing I am about to work on" — or, with no arguments, "let
me pick a branch to switch to."
*Note* — **A dot in the name** — the only dotted command in the tree; it breaks tab-completion
habits and every convention in the file. Nobody can decode "c.sb". Body: bare → fzf switch
picker; with a label → create-or-switch `label` or `label-suffix`; and if the suffix matches
`^[a-f0-9]{6,40}$` it branches from that **commit** instead — an undocumented mode change driven
by argument shape. Overlaps `git-b` and `git-branch` (all three are switch pickers) and sits one
edit from `git-cm`. Its bare-gives-a-picker behaviour is the one genuinely dkr-shaped thing here.

**`git-a`** · cryptic-suffix / cryptic · commit · `commit.ps1:11`
*For* — "Save everything I have done and get it up on GitHub" — the one-shot end-of-work command,
including creating the GitHub repo if this project does not have one yet.
*Note* — The flagship command of the domain and its name is a single letter. Body: offers
`git init` if not a repo; bails if clean; fzf form (branch, remote, changed files, recent
commits) using `--print-query` to capture a typed message; hard-prefixes every message with
"commit - "; `git add .`; commit; if no origin, checks for `gh` and offers
`Create-RemoteRepository`; pushes with `-u` when there is no upstream; and has a recovery path
for a remote deleted on GitHub. Stages everything — no partial staging. `-a` in real git means
`--all`, a modifier, not "do the whole workflow". Entrenched and must not move (§5.7).

**`git-a-plus`** · other / cryptic · commit · `commit.ps1:244`
*For* — "Do the git-a thing, but in one of three other modes" — preview-only, minimal-prompts,
or fix-up-the-last-commit.
*Note* — The direct contradiction of the reference, stated openly in its own registered synopsis
(`:459`): "git-a with modes: -Quick, -DryRun, -AmendLast". Three **flags** choose what runs.
"-plus" means nothing to a user. This is the textbook case for word verbs, and the best available
preview of what a flag-selector convention looks like at scale. §5.7, §2.1.

**`git-aa` (`git-aq`)** · cryptic-suffix / cryptic · commit · `commit.ps1:452`
*For* — "Just ask me for a message and push it — do not show me the big form."
*Note* — Body is exactly `git-a-plus -Quick`, **byte-identical to `git-aq`** — two names, one
behaviour. Behavioural trap: unlike `git-a`, the `-Quick` path calls a bare `git push` (`:438`)
with no upstream handling and no remote creation, so it fails on a fresh branch while claiming to
be the fast path. One edit from `git-ad` and `git-am`, which do different things. §5.7.

**`git-aq` (`git-aa`)** · cryptic-suffix / cryptic · commit · `commit.ps1:453`
*For* — Identical to `git-aa`.
*Note* — Registered as an alias of `git-aa` but it is a duplicate **function**, not a
`Set-Alias` — the same body written twice. Pure naming debt: two cryptic letters competing to
mean "quick". Safe to delete outright.

**`git-ad`** · cryptic-suffix / cryptic · commit · `commit.ps1:454`
*For* — "Before I commit, show me exactly which files would go in."
*Note* — A **modifier** (a dry run) promoted to its own top-level name — the same inversion as
`git-a-plus`, spelled differently. Overlaps `git-s` almost completely (both list changed files
with the same emoji legend, copied code). One edit from `git-aa` and `git-am`.

**`git-am`** · cryptic-suffix / cryptic · commit · `commit.ps1:455`
*For* — "Fix the message on the commit I just made" — and optionally shove the correction over
what I already pushed.
*Note* — **Drift with a data risk:** the synopsis says only "amend the last commit with a new
message", but the body runs `git add .` **before** `--amend` on both paths (`:317`, `:321`), so
any unrelated work in your tree is silently folded into the previous commit. It then offers
`git push --force-with-lease`. `am` collides with real `git am` (apply a mailbox patch), which
does something else entirely. §5.7.

**`git-l` (`git-log`)** · cryptic-suffix / cryptic · commit · `interactive.ps1:11`
*For* — "Look through the history, find the commit I am thinking of, and then do something with
it" — inspect it, branch off it, or pull it onto this branch.
*Note* — Body: fzf over `git log --oneline --graph --all --decorate`, copies the hash, then a 1-4
menu (`git show` / branch from it / cherry-pick / nothing). **This is where cherry-pick actually
lives** — not in `git-p`/`git-pick`, which advertises it. Sits **one edit from `git-rl`**, which
bumps the version, commits, tags and pushes to origin: the most casual command in the domain is
one keystroke from the most consequential. §5.8.

**`git-log` (`git-l`)** · prefixed-family / obvious · commit · `interactive.ps1:73`
*For* — Identical to `git-l`.
*Note* — 1:1 wrapper, and again the guessable name is registered as the alias (`:290`).
Homograph of real `git log`, so the space form is unavailable. §5.5.

**`git-s` (`git-st`)** · cryptic-suffix / cryptic · status · `interactive.ps1:77`
*For* — "What have I changed?" — and then, file by file, stage it, unstage it, look at the diff,
or throw the change away.
*Note* — Body: `git status --porcelain` → emoji lines → `fzf --multi` → per-file 1-4 menu
including "Discard changes" (`git checkout --`, unrecoverable). The fzf header advertises
"Space: Stage/Unstage | Ctrl-D: Diff | Ctrl-R: Reset" and **none of those keys are bound**, so
the header lies about a menu whose option 4 is unrecoverable. `--multi` is enabled but each
selected file gets its own fresh numbered menu. Overlaps `git-ad`. One edit from `git-sh`, which
is stash. §5.6.

**`git-st` (`git-s`)** · cryptic-suffix / cryptic · status · `interactive.ps1:144`
*For* — Identical to `git-s`.
*Note* — 1:1 wrapper. `git-st` and `git-sh` differ by one character and mean status vs stash — a
live confusion between two commands that both operate on your uncommitted work.

**`git-pick` (`git-p`)** · prefixed-family / guessable · commit · `interactive.ps1:146`
*For* — "Get me a commit hash off the history and onto my clipboard" so I can paste it into
another command.
*Note* — Synopsis drift: registered as "fuzzy-pick commits for cherry-pick" — the body **never
cherry-picks**. It is four lines: fzf over the log, regex the hash, `Copy-ToClipboard`. The real
cherry-pick is inside `git-l`. Also the only command in the file with no "not in a git
repository" guard. The name "pick" having been claimed for a clipboard copy is why `git-rb` has
to demand a hash argument instead of offering a picker (§5.8).

**`git-p` (`git-pick`)** · cryptic-suffix / cryptic · commit · `interactive.ps1:158`
*For* — Identical to `git-pick`.
*Note* — The worst-misleading letter in the domain: to any git user `git-p` reads as *push* or
*pull*. It does neither — it copies a hash. Registered as primary over the clearer `git-pick`
(`:292`). One edit from `git-b`, `git-a`, `git-s`, `git-l`, `git-r`, `git-f`. §5.5.

**`git-stash`** · prefixed-family / obvious · stash · `interactive.ps1:162`
*For* — "Get back something I shelved earlier" — apply it, pop it, look at it, or bin it.
*Note* — **Half the noun is missing:** this can only *read* existing stashes. There is no way to
**create** one — the thing a user reaching for "stash" most often wants — and it exits early with
"📭 No stashes found" if the list is empty. Body: fzf over `git stash list` → 1-4 menu (apply /
pop / `show -p` / drop). Homograph of real `git stash`. §5.6.

**`git-remote` (`git-r`)** · prefixed-family / obvious · remote · `interactive.ps1:217`
*For* — "Where does this repo actually push to, and let me fetch from it, push to it, or point it
somewhere else."
*Note* — Body: parses `git remote -v`, host-specific emoji, fzf, then 1-4 menu (fetch / push
current branch / `remote show` / `set-url`). Registered as the alias of the cryptic `git-r`
(`:294`). Overlaps `Create-RemoteRepository` (`remote.ps1`) — creating a remote and managing one
live in two files under two unrelated names. §5.5.

**`git-sh`** · cryptic-suffix / cryptic · stash · `interactive.ps1:286`
*For* — "Get back something I shelved" — the stash manager again, under a third name.
*Note* — The worst name in the domain, on three counts at once. (1) Synopsis drift: registered as
"show a commit, interactively chosen" (`:295`) — the body is literally `git-stash`. Anyone
reading `pwsh-h` is told this shows a commit. (2) One edit from `git-s` and `git-st`, which are
**status**. (3) `sh` universally reads as *shell*. Registered as its own command rather than an
alias, so `pwsh-h` prints two unrelated-looking rows for one behaviour. §5.6.

**`git-r` (`git-remote`)** · cryptic-suffix / cryptic · remote · `interactive.ps1:287`
*For* — Identical to `git-remote`.
*Note* — Head of a four-way cryptic collision: `git-r` (remotes), `git-rb` (rollback branch),
`git-rba` (commit+push on one), `git-rl` (cut and push a release). Four names, four unrelated
consequences, one of which fires a CI release. §5.8.

**`git-release` (`git-rl`)** · prefixed-family / obvious · release · `release.ps1:205`
*For* — "Ship a new version of this project" — work out what version it is on, let me pick how
big a jump it is, write the new number into whatever files hold it, then commit, tag and push so
CI builds the release.
*Note* — **By far the best-behaved command in the domain and the closest thing here to the
reference:** bare does the useful thing, two fzf pickers instead of flags, and exactly one
modifier (`-h`/`-help`/`-?`) that only prints. Resolves the version from the project's native
file (package.json / pyproject.toml / Cargo.toml / *.csproj / build.gradle / VERSION / PowerFlow
settings) or the latest tag; **detects drift** between multiple version files and stops to ask;
fzf patch/minor/major/custom; fzf description form; rewrites every version file by regex (never a
JSON reserialise); refuses to proceed if any file failed; then add → commit → push → tag → push
tag → prints the release URL. Registered as the **alias** of the cryptic `git-rl` (`:475`).

**`git-rl` (`git-release`)** · cryptic-suffix / cryptic · release · `release.ps1:472`
*For* — Identical to `git-release`.
*Note* — **One edit from `git-l`** (insert `r`). `git-l` opens a read-only log browser; `git-rl`
rewrites version files, commits, tags and pushes to origin, firing the CI release pipeline. It is
also the name `CLAUDE.md:90` and `:101` tell contributors to use, so the cryptic form is
entrenched in documentation and must not move. §5.5, §5.8, §6.

**`git-f`** · cryptic-suffix / cryptic · changes · `reset.ps1:11`
*For* — "Throw away absolutely everything I have done since the last commit and give me a clean
checkout again."
*Note* — **The most dangerous drift in the tree.** `pwsh-h` says "fetch and fast-forward the
current branch" (`:45`). The body is `git reset --hard HEAD` + `git clean -fdx` +
`git fetch --all --prune`: it destroys every uncommitted change **and** every untracked and
ignored file — `.env`, `node_modules`, build output — with no reflog escape, and it never
fast-forwards anything. The letter compounds it: `-f` reads as *fetch* or *force*, never *flush*,
and it is one edit from every casual command in the domain. §5.2.

**`git-next`** · prefixed-family / cryptic · node_modules · `reset.ps1:24`
*For* — "My node install is broken — nuke the build cache and dependencies and reinstall."
*Note* — **Not a git command at all** — there is no `git` call anywhere in the body — yet it
lives in `components/git/reset.ps1` and is registered under the git section as "jump forward one
commit (walk history upward)". Body: y/n, then
`Remove-Item -Recurse -Force .next,node_modules,package-lock.json`, then `npm install`. It
deletes `package-lock.json`, a **tracked** file, without saying so, and hard-codes `.next` and
npm. Real `git-extras` ships a `git next` that walks history forward, exactly as this synopsis
describes, so the name has an established and contradictory meaning. §5.3.

**`git-rb`** · cryptic-suffix / cryptic · rollback · `rollback.ps1:171`
*For* — "Put the code back the way it was at some earlier commit, on a throwaway branch, without
wrecking the branch I am on."
*Note* — **Mandatory positional hash, no picker** — to use it you must first run `git-l`, copy a
hash, then come back; bare `git-rb` drops into PowerShell's raw "Supply values for the following
parameters" prompt. Derives the branch name from the **last three characters** of the short hash
(`rollback-<3 chars>`), which will collide across a long history, and force-deletes any existing
same-named branch to get there. `-Force` skips both confirmations, which is a legitimate
modifier. `rb` reads as *rebase*; it does not rebase. §5.8.

**`git-rba` (`grba`)** · cryptic-suffix / cryptic · rollback · `rollback.ps1:11`
*For* — "I have fixed things up on my rollback branch — commit it, push it, and hand me the link
to open the pull request."
*Note* — Initials-of-initials ("rollback branch add"), three letters deep. **Hard-gated:**
refuses to run unless the current branch matches `^rollback-[a-zA-Z0-9]+$`, so it is unusable
anywhere else — a **mode**, not a command. Duplicates `git-a`'s entire workflow with a
branch-name check bolted on, which is what a word verb under a noun avoids. §5.8.

**`grba` (`git-rba`)** · squashed-words / cryptic · rollback · `rollback.ps1:169`
*For* — Identical to `git-rba`.
*Note* — The **only real `Set-Alias` in `components/git/`**, and it abandons the `git-` prefix
every sibling shares, so it neither tab-completes alongside them nor reads as belonging to them.
Unpronounceable — a four-letter squash of a three-letter cryptic suffix. §5.8.

---

### GitHub — `components/github/`

**`gh-l`** · cryptic-suffix / cryptic · repo · `browser.ps1:111`
*For* — "Show me my GitHub repos with the ones I touched most recently at the top, and let me
clone one, open it in the browser, grab its URL — or delete it."
*Note* — Body: token from `-Token` / `$env:GITHUB_TOKEN` / Credential Manager, else prompts
(`AsSecureString`) and offers to save; pages all owner repos; sorts by `pushed_at`; makes **two
extra API calls per repo** for 24h/1w commit counts; fzf table; then a 1-5 menu — clone /
`Open-Url` / copy SSH URL / **delete the repository** (three typed confirmations) / nothing. Four
problems: it prints leftover developer debug output to real users on every run ("🔍 Debugging:
Sorting…", "🔍 Debug: Selection = …"); permanent repo **deletion** is option 4 of a numbered menu
under a command whose synopsis says "browse"; `-Count` is declared as a param **and** re-read
from `$args[0]` (`:117-119`), so two forms exist for one thing; and its token helpers call
`cmdkey` and P/Invoke `advapi32` `CredRead` directly — a Windows-only OS call inside
`components/` — with no `-Platform 'Windows'` on the registration. Also easily mistyped for
`git-l`. §5.10.

**`gh-l-org`** · prefixed-family / guessable · repo · `browser.ps1:395`
*For* — "Look at the repos belonging to one of my orgs" — and if I want, clone the whole org onto
disk in one go.
*Note* — **The one command in the domain that already has the dkr shape:** bare fetches
`/user/orgs` and opens an org **picker**; `gh-l-org my-team` skips straight to it. Exactly "bare
does the useful thing, refinement is a word, ambiguity gets a picker" — the flaw is purely that
the refinement ("org") is welded into the command **name** instead of being a word after a noun.
Also degrades gracefully: on a 403 for `type=all` it retries public-only and warns about the
missing `read:org` scope. §5.10.

**`gh-l-status`** · prefixed-family / cryptic · token · `browser.ps1:381`
*For* — "Have I still got a GitHub token saved, or is it going to ask me again?"
*Note* — Three levels deep on a cryptic stem — "the status of gh-l" reads as *repo* status, not
credential status. Body is four lines of `cmdkey /list:gh-l-github-token`. Windows-only `cmdkey`
inside `components/` with no `-Platform 'Windows'`, so on Linux it reports "no token saved"
rather than failing — worse than failing. Forms a genuine **token** noun with `gh-l-reset`,
buried under a repo-browser name. §5.10.

**`gh-l-reset`** · prefixed-family / cryptic · token · `browser.ps1:367`
*For* — "Forget the GitHub token you saved for me" — usually because it expired or I revoked it.
*Note* — "reset" is the wrong word for "delete my saved credential" in a git-adjacent tree where
`reset` means `git reset` and `git-f` performs an actual hard reset. Same Windows-only OS call
with no `-Platform`. Note the same delete-the-token flow is **also inlined** in `gh-l`'s 401
handler, so the behaviour exists twice under two entry points. §5.10.

---

### Navigation — `components/navigation/`

**`nav` (`z`)** · noun-verb / obvious · directory · `nav.ps1:21`
*For* — "Get me to that folder without typing its path" — you type a fragment of a directory name
and it drops you in it. Bare `nav` prints a help card listing every starting point on this
machine.
*Note* — **Already the dkr shape and the closest thing in the tree to the reference:** a noun
with word verbs (`nav b`, `nav list`, `nav roots`, `nav anchors`). Two deviations: bare `nav`
shows **help**, not the table+picker, where the reference's bare command does the useful thing;
and the starting point is chosen with a **flag** (`nav -pics`), which selects what runs.
Hand-parses `$args` rather than using `param()` — deliberate, documented at `:11-20`, because
`param()` would try to bind `-srv` as a parameter name. `-verbose`/`-v` is the only true modifier
and is legitimately flag-shaped.

**`z`** · other / cryptic · directory · `nav.ps1:361`
*For* — Same as `nav` — a one-keystroke jump for fingers that already learned z/zoxide.
*Note* — Single letter, borrowed muscle memory. Unguessable, but that is the point — it is a
compatibility alias, not a name. Keep regardless of any rename (§6).

**`nav b`** · noun-verb / cryptic · bookmark · `nav.ps1:131`
*For* — "Take me to the place I saved" — jumps straight to a named bookmark, no search, no
picker. `nav b .` inverts it and **saves** the directory you are standing in.
*Note* — The verb is a single letter. One command doing two opposite things (go there / save
here) split only by whether the argument is `.` — the code comment at `:132` records the owner
typing exactly that and getting "Bookmark '.' not found". Within one edit of `nav db` (deletes a
bookmark) and `nav cb` (creates one) — three near-identical names, one destructive. `nav b .` is
a shipped v4.2.0 feature and must keep working (§6). §5.14.

**`nav list` (`nav l`)** · noun-verb / cryptic · bookmark · `nav.ps1:106`
*For* — "Show me everywhere I saved and let me pick one" — a numbered list with a live/dead tick
per path, then a prompt where a number navigates and single letters create/delete/rename.
*Note* — **Behaviour drift:** nav's own help (`:88`) advertises this as "manage bookmarks (Enter
go · ctrl-d delete)", implying fzf. `Show-BookmarkList` (`bookmarks.ps1:160`) is a plain
`Read-Host` numbered menu — no fzf, no ctrl-d, no live filtering. Also "list" does not say list
**what**: under a command whose subject is directories, `nav list` listing *bookmarks* is a
guess. And it hides a **third** cryptic verb set inside the prompt (`bookmarks.ps1:183`):
`'c <name>'`, `'d <name>'`, `'r <old> <new>'`. §5.14.

**`nav create-b` (`nav cb`)** · hyphen-abbreviated / cryptic · bookmark · `nav.ps1:103`
*For* — "Remember this folder under a short name" — saves a bookmark pointing at the current
directory (it never accepts a path; only the name).
*Note* — The `-b` suffix is an abbreviation of the noun the verb acts on, i.e. the noun is buried
in the verb — the exact inverse of the reference shape, where the noun *is* the command.
Duplicates `nav b .` entirely: two names for saving the current directory. Within one edit of
`nav b` and `nav db`. §5.14.

**`nav delete-b` (`nav db`)** · hyphen-abbreviated / cryptic · bookmark · `nav.ps1:104`
*For* — "Forget that saved folder" — removes a bookmark after a y/n confirmation showing the path.
*Note* — `db` reads as *database* to every developer alive; it means "delete bookmark". This is
the destructive member of the cb/db/rb trio and is one edit from `nav b` (navigate) and `nav cb`
(create). A mistyped `nav db docs` versus `nav b docs` is the difference between deleting and
going. §5.14.

**`nav rename-b` (`nav rb`)** · hyphen-abbreviated / cryptic · bookmark · `nav.ps1:105`
*For* — "Call that saved folder something else" — renames a bookmark, keeping its path.
*Note* — `rb` reads as *rollback* or *Ruby*. Third member of the trio; one edit from `nav b`,
`nav cb` and `nav db`. §5.14.

**`nav roots`** · noun-verb / guessable · starting point · `nav.ps1:110`
*For* — "Where does a bare `nav` actually look?" — prints the search roots with a live/dead tick,
and lets you add, remove or reset them so `nav` scans `/srv` or `/mnt/data` too.
*Note* — Sub-verbs are proper words (`add`, `rm`, `reset`) with short forms — **this is the
reference shape done right**, and it is the model §5.14 asks the bookmark verbs to copy. But bare
`nav roots` also prints the **named starting points** (`:117-123`), which are `nav anchors`'
subject, so the two commands overlap in output while claiming to be different concepts.
`roots.ps1:384-390` documents the collision explicitly ("'root' was already taken").

**`nav anchors` (`nav anchor`)** · noun-verb / cryptic · starting point · `nav.ps1:60`
*For* — "What can I put after `nav -`?" — lists every named starting point, marking which are
built into the machine and which you added; `nav anchors rm <name>` deletes one of yours, and
built-ins refuse deletion because there is nothing stored to delete.
*Note* — "Anchor" is a coined term — nobody reaches for it; they reach for "roots", "shortcuts"
or "places". The file itself (`roots.ps1:384`) admits the name exists only because `roots` was
taken. Sub-verb `rm` accepts `rm`/`remove`/`d`/`delete`, which is generous and consistent with
`nav roots`.

**`nav --anchor` (`nav -anchor`, `nav --start-repo`)** · other / cryptic · starting point ·
`nav.ps1:34`
*For* — "Make **here** one of the places `nav` can start from" — saves the current directory (or
a given path) under a short name so `nav -mon <thing>` searches only under it afterwards.
*Note* — **The sharpest contradiction of the reference inside `nav`, and the code says so.**
`nav.ps1:32` states outright: "--anchor is a VERB, not a starting point" — a flag choosing what
runs. Its sibling `nav anchors rm <name>` is already a word verb, so the create path is
flag-shaped while the delete path is word-shaped, inside one command. `nav anchors add .` would
resolve it with no new vocabulary. It also carries a legacy alias `--start-repo` "because that is
what the owner first reached for" — direct evidence the flag name is not the word users grope for
(§6).

**`nav -<start>`** (`-code`, `-pics`, `-docs`, `-dl`, `-srv`, `-www`, `-log`, `-tmp`, `-config`,
`-mnt`, `-opt`, `-etc`, `-home`, `-desktop`, `-music`, `-videos`) · other / guessable · starting
point · `nav.ps1:35`
*For* — "Search for it, but only under my pictures / only under `/srv`" — scopes one search to a
named starting point; with no search word it simply jumps there. An explicit starting point
outranks the bookmark-context inference `nav` otherwise applies.
*Note* — The **names** here are excellent: `pics`, `docs`, `dl`, `srv`, `www` are nouns users
already think in, each with paired long/short forms resolved in `Get-PFRootAliases`
(`roots.ps1:213`). The **shape** is the problem: they are flags, and they select what the command
operates on. Two saving graces: `ls` shares the identical resolver
(`Resolve-PFRootedDirectory`), so the two can never disagree; and an unknown `-token` is refused
with the full list rather than silently swallowed (`:40`) — the picker-for-ambiguity instinct
applied to flags. Only roots that exist on the machine are offered, resolved through the adapter
so OneDrive Known Folder Move does not break `-pics`.

**`nav home` (`nav ~`)** · noun-verb / obvious · directory · `nav.ps1:193`
*For* — "Go home."
*Note* — Undocumented: bare `nav`'s help card never mentions it — it advertises `-home` instead.
So **three** commands go home: top-level `~`, `nav home`/`nav ~`, and `nav -home`.

**`nav code`** · noun-verb / obvious · directory · `nav.ps1:195`
*For* — "Go to my Code folder" — jumps to `~/Code`, or says it does not exist and suggests
bookmarking your own.
*Note* — **Duplicates `nav -code` with different machinery:** this branch hardcodes
`Join-Path $home 'Code'` while `-code` goes through `Get-PFNamedRoots`. Same word, two
implementations, and only one of the two is listed in nav's help.

**`nav projects`** · noun-verb / obvious · directory · `nav.ps1:206`
*For* — "Go to where I keep my projects" — jumps to `~/Code/Projects`.
*Note* — Hardcoded two levels deep into one person's layout, with no `-projects` named-root
equivalent and no mention in nav's help card. The most machine-specific thing in the domain; a
bookmark would carry it.

**`here`** · other / guessable · current directory · `directory.ps1:21`
*For* — "What is this folder?" — prints the current path, how many dirs and files it holds, total
size, the git branch if any, and a guess at the project type from package.json / Cargo.toml /
requirements.txt / go.mod.
*Note* — Synopsis drift: registered as "show where you are, **with quick actions**" (`:238`) —
there are no quick actions in the body, it prints and returns. Bare adverb, no noun: shares its
noun with `copy-pwd` here and `open-pwd` in `clipboard.ps1:21` — three commands, one noun, three
unrelated names, in two `pwsh-h` sections. §5.16.

**`..` (`...`, `....`, `.....`)** · other / obvious · directory · `directory.ps1:65`
*For* — "Up out of here" — one level per dot; if you name a directory after the dots it hands
that name to `nav` to find, and if `nav` finds nothing it lists the directory you landed in so
you are not left blind.
*Note* — Constrained: a universal shell idiom (§6). Two problems worth noting: the registry
declares `...`, `....` and `.....` as **aliases** of `..` (`:237`) but they are four distinct
functions going up 1/2/3/4 levels — they are not aliases; and the synopsis omits the
target-directory feature entirely, which is the most useful half of the command
(`.. management`). Each is within one edit of the others and the difference is silent until you
look at where you landed.

**`~`** · other / obvious · directory · `directory.ps1:209`
*For* — "Go home."
*Note* — Constrained: a universal shell idiom (§6). A one-liner using `$HOME` directly while
every other path in this domain goes through the `Get-HomePath` adapter (`nav ~` at `nav.ps1:193`
does use it) — not a forbidden token, but an inconsistency, and it means the two `~` commands
could theoretically disagree.

**`back` (`cd-`)** · other / obvious · directory · `directory.ps1:218`
*For* — Claims to be "take me back where I just was", the shell equivalent of `cd -`.
*Note* — **This command is dead.** It reads `$global:NAV_HISTORY`, and a repo-wide grep finds
that variable nowhere except the two lines that read it (`:219-220`) — nothing ever writes it,
there is no prompt hook or `Set-Location` wrapper populating it. So `back` and `cd-` always fall
to the else branch and print "No previous directory in history", while being registered in
`pwsh-h` as working (`:239`). Any naming decision here should be a decision about whether to
**implement** it (§6).

**`copy-pwd`** · hyphen-abbreviated / guessable · current directory · `directory.ps1:230`
*For* — "Put this path on my clipboard so I can paste it somewhere else."
*Note* — Requires knowing `pwd` to guess the name. Shares its noun with `here` (same file) and
`open-pwd` (`clipboard.ps1:21`), filed in two different `pwsh-h` sections. Correctly uses the
`Copy-ToClipboard` adapter, not `Set-Clipboard`. Also the canonical kebab-case example in
`docs/instructions.md:490`, which a rename would invalidate. §5.16.

---

### Projects — `components/projects/`

**`create-next` (`create-n`)** · other / obvious · project · `create-next.ps1:11`
*For* — "Give me a working full-stack app to start from, not an empty folder" — nine steps:
checks node 18+, asks for the project name through an fzf prompt, runs `npx create-next-app`
(TypeScript/Tailwind/ESLint/App Router/src), lays out `src/components|lib|types`, writes Prisma
schema + seed + `.env` and `.env.docker`, generates real pages and API routes, writes
`Dockerfile`, `Dockerfile.dev` and both compose files with a Postgres service on local volumes,
adds a GitHub Actions workflow, injects `docker:*`/`prisma:*`/`db:*` npm scripts, installs every
dependency, and leaves you cd'ed inside the new project.
*Note* — **Verb-first** — the exact inversion of the noun-first shape. `create-` reads as the
head of a family (`create-react`, `create-api`) that has exactly one member; the dkr reading is a
`proj`/`new` noun with `proj next` under it. **Takes no arguments at all:** no `param()` block
and no `$args` read anywhere in 1620 lines, so `create-next my-app` silently ignores the name and
prompts through fzf anyway — refinement is not even a flag here, it is a mandatory TUI, the
opposite of `dkr logs <name>`. It also calls fzf with **no availability guard** (unlike
`nav.ps1:267`, which checks and falls back) while carefully checking node and npm, so on a box
without fzf the name prompt collapses to "cancelled - no name provided". The alias `create-n`
lands one edit from `nav create-b`, which creates a **bookmark**. The fzf header still says
"v2.2" while the printed feature list is what actually ships.

---

### Network — `components/network/`

**`srv`** · prefixed-family / guessable · server · `servers.ps1:172`
*For* — Get an SSH session onto a machine I saved earlier without remembering its address; bare
shows every saved box with a live reachability badge and lets me pick one and connect.
*Note* — Truncation of "server", and already the reference shape (bare = picker, verbs are words,
`-f` is a true modifier). Conceptual near-collision with the tree-wide `service` command: a new
user can read `srv` as "service". The noun `srv` is also what `pmx config set host` stores, so
`pmx` depends on this family's names.

**`srv <name>`** · other / obvious · server · `servers.ps1:344`
*For* — Log into one particular saved machine by the nickname I gave it, and be warned before it
tries if the box is not answering on the SSH port.
*Note* — Positional target with no verb — the fall-through after every subcommand. Subcommand
names (`add`, `rm`, `remove`, `list`, `ls`, `help`, `rename`) are reserved as server names
precisely so this fall-through can never be shadowed. Good precedent for `storage`'s
verbs-before-volume ordering.

**`srv <name> info`** · noun-verb / guessable · server · `servers.ps1:353`
*For* — See the real `user@host:port` hiding behind a nickname — but only after proving I can
actually log in, because the endpoint is deliberately hidden from every list, picker and error
message.
*Note* — The verb sits **after** the target (`srv box info`) while every other srv verb sits
before it (`srv add box`, `srv rm box`) — inconsistent verb position inside one command. Unique
in the tree: a **read** that requires interactive authentication.

**`srv add`** · noun-verb / obvious · server · `servers.ps1:183`
*For* — Save a machine under a short name I will actually remember, and find out on the spot
whether SSH really answers there before it gets written down.
*Note* — `-f` means "replace an existing entry" here but "skip the confirm" in `srv rm` — the
same flag letter with two meanings inside one command.

**`srv rm` (`remove`)** · noun-verb / obvious · server · `servers.ps1:251`
*For* — Forget a machine I no longer use, with a confirm unless I say otherwise.
*Note* — Deliberately borrows the coreutil verb `rm`, but as a **subcommand** — no top-level
binding, so the Linux no-shadowing rule does not apply and this must not be flagged on those
grounds. `-f` is a correct modifier.

**`srv rename`** · noun-verb / obvious · server · `servers.ps1:273`
*For* — Change a machine's nickname while keeping its address, its added-date and its last-seen
history, instead of deleting and re-adding it.
*Note* — Also reachable as ctrl-r inside the bare-`srv` picker; the picker is a manager, not just
a launcher. `Show-PFServerPicker` (`:399-450`) is the reusable pattern §5.14 recommends copying.

**`srv list` (`ls`)** · noun-verb / obvious · server · `servers.ps1:324`
*For* — See every machine I saved and whether each is reachable right now — and specifically
whether the box is up but sshd is not answering, which a ping cannot tell me.
*Note* — The `ls` alias is a coreutil name but subcommand-scoped, so it is safe. This is also
what bare `srv` degrades to when fzf is missing or stdout is piped — the good pattern, and the
one `dkr`'s design doc requires of every picker.

**`srv help` (`-h`, `--help`, `/?`)** · other / obvious · server · `servers.ps1:306`
*For* — Find out what `srv` can do without leaving the shell or opening docs.
*Note* — "help" is a reserved server name, so a user can never create a host that shadows it.
Contains a `/?` spelling — the only odd-character command form in the network domain.

---

### Proxmox — `components/proxmox/`

**`pmx`** · noun-verb / guessable · proxmox · `command.ps1:158`
*For* — One screen telling me whether my Proxmox box is healthy: version, uptime, CPU and load,
memory, root disk, how many guests are running, how much storage is active, ZFS health and
cluster quorum.
*Note* — Bare branches on `Test-ProxmoxSupport`: on the host it prints the local dashboard,
elsewhere it prints the configured remote node's status — one word, two different screens
depending on where you type it. Global modifiers are correctly modifier-only: `--dry-run`,
`--json`/`-j`, `--table`/`-t`, `--show-native`, `--explain`. `--help` anywhere in argv is hoisted
to help rather than run.

**`pmx help` (`-h`, `--help`, `/?`)** · other / obvious · proxmox · `command.ps1:171`
*For* — Before running something on a live hypervisor, learn what it does, which native `qm`/
`pvesh` command it becomes, and whether it is safe, amber or destructive.
*Note* — Deliberately sits **above** the Proxmox connection gate so it works on machines with no
Proxmox at all — the reason `pwsh-h` registers `pmx` once instead of eleven sub-routes. Owns a
31-entry topic catalogue; several topics are aliases pointing at the same object, which is where
the duplicate command spellings below become visible.

**`pmx config show` (`pmx config`)** · noun-verb / obvious · config · `config.ps1:421`
*For* — See which Proxmox box `pmx` will act on, what its safety and output defaults are, and
where that settings file lives on disk.
*Note* — Bare `pmx config` == `pmx config show`. Correct "bare does the useful thing" behaviour.

**`pmx config set`** · noun-verb / obvious · config · `config.ps1:422`
*For* — Point `pmx` at a different box, or change a default I keep overriding — output format,
how strictly changes are confirmed, whether an audit log is kept, the timeout, and whether native
commands are echoed.
*Note* — Setting names are kebab words, matching the rule: `host`, `node`, `transport`, `output`,
`show-native`, `explain`, `confirmation`, `audit-log`, `timeout-seconds`. `host` stores an **srv
alias**, never credentials — the seam where the `pmx` noun depends on the `srv` noun.

**`pmx config reset`** · noun-verb / obvious · config · `config.ps1:430`
*For* — Put one setting, or everything, back to how it shipped after experimenting.
*Note* — `all` is a magic positional **value** rather than a flag — consistent with the rule.

**`pmx config validate`** · noun-verb / obvious · config · `config.ps1:438`
*For* — Prove the saved settings actually reach a real node over a real transport, before I trust
them for a change that matters.
*Note* — Silent on success apart from one green line; the only `pmx` verb whose whole output is a
yes/no.

**`pmx config discover` (`pmx discover`)** · noun-verb / guessable · proxmox · `config.ps1:446`
*For* — Same as `pmx discover` — ask the box what actually exists on it.
*Note* — **Exact duplicate route:** identical handler to top-level `pmx discover`, and both are
advertised in the help overview. Two names, one behaviour.

**`pmx discover`** · other / guessable · proxmox · `command.ps1:192`
*For* — Before planning a clone or a resize, ask the box what really exists: which nodes, which
storage names, which bridges, which VMIDs are taken, which templates I can clone, and the next
free ID.
*Note* — Bare verb with no noun under the `pmx` prefix — reads as an action on the whole host.
Overlaps `pmx vm next-id` (it reports the next free ID too) and `pmx storage list` (it reports
storage names too).

**`pmx node status` (`pmx node`)** · noun-verb / obvious · proxmox · `command.ps1:193`
*For* — Read how the hypervisor host itself is doing — version, kernel, uptime, CPU, memory, root
disk — without opening the Proxmox web UI.
*Note* — Bare `pmx node` == `pmx node status`; any other verb is refused outright. Near-duplicate
of bare `pmx` (different code path, near-identical screen), so "how is the host doing" has two
names. Shares its verb with `pmx vm status` — that consistency is good and worth preserving.

**`pmx storage` (`pmx pools`)** · other / cryptic · storage · `command.ps1:201`
*For* — On the Proxmox box itself: see the storage entries and ZFS pools with used/free and
health.
*Note* — Bare `pmx storage` silently forwards to `Show-PmxPools` — identical output to
`pmx pools` — but **only on a local Proxmox host**; off-host the same word demands `list` and
shows a different table. One name, two behaviours chosen by which machine you are on. Its own
help topic calls it a "legacy no-argument alias".

**`pmx storage list`** · noun-verb / obvious · storage · `command.ps1:211`
*For* — Find out which storage can actually hold a VM image and how much room is left, so a clone
or a disk grow will not fail halfway.
*Note* — Third name for the storage noun alongside `pmx storage` and `pmx pools`. Its data is also
re-read internally by `pmx disk grow` for the capacity check. Note the tension with the floated
`storage -D -s` style: a flag-shaped proposal would replace this word verb with letters, the
direction `pmx` has already moved away from (§2.1).

**`pmx pools`** · other / guessable · storage · `command.ps1:231`
*For* — See every Proxmox storage entry and every ZFS pool on the box I am sitting on, with
used/free, fill percentage, fragmentation and health.
*Note* — Bare plural noun with no verb. **Third spelling** of the storage noun. "Pools" also means
two different things in one screen (PVE storage entries and ZFS zpools). Takes no arguments.

**`pmx vm list` (`pmx vm`)** · noun-verb / obvious · vm · `vm-read.ps1:160`
*For* — See every VM and template with its VMID, name, node, running state, cores and memory, so
I can find the one I mean.
*Note* — Bare `pmx vm` == list. Ends by naming the obvious next moves (`pmx vm show`, `pmx vm
ip`, `pmx snapshot list`), which is the pattern the rest of `pmx` should copy. **Excludes LXC
rows**, so it does not agree with `pmx guests`.

**`pmx vm show`** · noun-verb / obvious · vm · `vm-read.ps1:192`
*For* — Open one VM and read what it is made of — cores, memory, whether it autostarts, whether
it is protected, whether it is a template, and which disks are attached.
*Note* — Omitting the VM name opens an fzf picker (`Resolve-PmxManagedVm`) rather than erroring —
"ambiguity gets a picker", and it is inherited by all thirteen VM-taking commands at once. This
is the precedent §5.8 cites for `git-rollback`.

**`pmx vm status`** · noun-verb / obvious · vm · `command.ps1:118`
*For* — Just answer whether this VM is running and for how long, without the full configuration
dump.
*Note* — Same function as `pmx vm show` with `-StatusOnly`, so `show` is a strict superset — two
command names covering one read. Correctly shares the verb with `pmx node status`.

**`pmx vm next-id`** · hyphen-abbreviated / guessable · vm · `command.ps1:119`
*For* — Get a VMID I can safely use for a new VM instead of guessing one and colliding.
*Note* — Hyphen inside a leaf subcommand name — one of only four in the domain (`next-id`,
`set-cpu`, `set-memory`, `capacity-test`). Largely redundant now: `pmx vm clone` resolves the
VMID automatically, and `pmx discover` also reports the next free ID.

**`pmx vm network` (`pmx vm net`)** · noun-verb / obvious · vm network · `command.ps1:120`
*For* — Find out how a VM is wired up and what addresses it actually holds inside, with the guest
agent's availability stated plainly instead of guessed or faked from ARP/DNS/scans.
*Note* — Bare `pmx vm net` with no VM falls through to the fleet-wide list, deliberately
mirroring bare `pmx vm`. Short options here are paired properly (`-t`/`--table`, `-j`/`--json`,
`-4`/`--ipv4`, `-6`/`--ipv6`) — **the only place in the tree that does the reference's short/long
pairing across the board.**

**`pmx vm net` (`pmx vm network`)** · other / guessable · vm network · `command.ps1:121`
*For* — Shorter way to type the same combined network view.
*Note* — Pure abbreviation alias. **Five spellings reach essentially one subsystem:** `network`,
`net`, `nic`, `ip`, `net stats`.

**`pmx vm network adapters` (`pmx vm nic`)** · noun-verb / obvious · vm network ·
`network-read.ps1:276`
*For* — See the virtual NICs Proxmox has configured for a VM — bridge, MAC, VLAN, firewall flag,
model — which works even when the VM is off or is a template.
*Note* — Correctly **refuses** address filters (`--ipv4`/`--ipv6`/`--all`) that make no sense for
this view instead of silently ignoring them. Good model for the whole tree.

**`pmx vm nic` (`pmx vm network adapters`)** · other / guessable · vm network · `command.ps1:122`
*For* — Shortest way to ask what virtual network cards a VM has.
*Note* — Three-letter jargon noun; a new user is more likely to reach for "nic" than for
"adapters", so the alias is arguably the better name and the long form is the ceremony.

**`pmx vm network addresses` (`pmx vm ip`)** · noun-verb / guessable · ip ·
`network-read.ps1:277`
*For* — Find out what IP a VM actually has right now so I can ssh to it, with the primary
candidate clearly labelled as inferred rather than authoritative.
*Note* — Nobody types "addresses" when they want an IP — the alias is the real name. Three words
for the single most-reached-for question in the family.

**`pmx vm ip` (`pmx vm network addresses`)** · other / obvious · ip · `command.ps1:123`
*For* — Get the address of a VM so I can connect to it.
*Note* — **The best-named command in the domain** and the one the help examples lead with. Feeds
straight into the `srv` noun: you get an IP here and save it with `srv add`, e.g.
`srv add box you@192.168.1.50`.

**`pmx vm network stats` (`pmx vm net stats`)** · noun-verb / obvious · vm network ·
`network-read.ps1:278`
*For* — Read a running VM's rx/tx bytes, packets, errors and drops without touching or changing
the VM, and see "unavailable" rather than a fake zero when a counter is missing.
*Note* — Only reachable three words deep — no short alias of its own, unlike its siblings `nic`
and `ip`.

**`pmx vm network list` (`pmx vm net list`)** · noun-verb / obvious · vm network ·
`network-read.ps1:279`
*For* — One table of the whole fleet's adapters, primary IPv4 and agent state, where one VM with
a broken agent does not kill the whole report.
*Note* — Also what bare `pmx vm net` resolves to. `list` appears as a verb under five different
nouns in this domain (vm, storage, snapshot, disk, vm network) — the family's most consistent
verb, and a good argument for `list` as the canonical table word tree-wide.

**`pmx vm clone`** · noun-verb / obvious · vm · `vm-change.ps1:116`
*For* — Turn a template into a real, independently owned VM by naming the template and the
hostname I want; the VMID picks itself and every source-to-target storage mapping is shown before
I agree.
*Note* — **The in-file comment records the exact lesson this audit is about:** the old form was
"four flags, three flag names to remember, and the magic value auto", rewritten to two positional
words because `pmx disk grow 101 50G` already read that way. The best in-tree precedent for §5
(§6). Vestigial `--full` is still accepted but has never done anything (`Full` is hardcoded
true); `--source-vmid` is a compatibility alias of `--source`.

**`pmx vm start`** · noun-verb / obvious · vm · `vm-change.ps1:434`
*For* — Turn a stopped VM on, after seeing a preview and confirming, and be told plainly if it
was already running.
*Note* — Same verb word as `dkr start`/`dkr up` — cross-family consistency already exists here.

**`pmx vm shutdown`** · noun-verb / obvious · vm · `vm-change.ps1:435`
*For* — Ask a VM to close down cleanly rather than pulling its power, and never accidentally
force-stop it.
*Note* — Deliberately never passes `forceStop`, so there is no `pmx vm stop` and no force verb at
all — a gap a user may reach for. Also collides in word with the tree-wide `shutdown` command
(host power-off): `shutdown` powers off **your** machine, `pmx vm shutdown` powers off a guest.

**`pmx vm cpu` (`pmx vm cpu set`, `pmx vm set-cpu`)** · noun-verb / obvious · vm ·
`command.ps1:132`
*For* — Give a VM more or fewer cores, and be told what that actually means in total vCPUs against
the host's real logical CPU count before agreeing to it.
*Note* — **Three spellings for one action.** `set` is optional (`pmx vm cpu 101 4` works) and the
value may be positional or `--cores`. `pmx vm set-cpu` is verb-noun-hyphenated and directly
contradicts the noun-verb shape it sits beside **in the same switch block**; it is kept only for
compatibility and is the clear retire candidate.

**`pmx vm set-cpu` (`pmx vm cpu`)** · hyphen-abbreviated / guessable · vm · `command.ps1:127`
*For* — Legacy spelling of changing a VM's core count.
*Note* — Verb-first hyphenated leftover — the anti-pattern relative to the reference, living in
the same switch as its own noun-verb replacement.

**`pmx vm memory` (`pmx vm memory set`, `pmx vm set-memory`)** · noun-verb / obvious · vm ·
`command.ps1:133`
*For* — Resize a VM's RAM using a human unit like `8G`, see the MiB value Proxmox will actually
receive, and be warned if I am about to hand the guest most of the host's memory.
*Note* — Three spellings, same as `cpu`. `set` optional, value positional or `--size`.

**`pmx vm set-memory` (`pmx vm memory`)** · hyphen-abbreviated / guessable · vm ·
`command.ps1:128`
*For* — Legacy spelling of resizing a VM's RAM.
*Note* — Same verb-first hyphenated anti-pattern as `set-cpu`; retire together or keep together.

**`pmx snapshot list` (`pmx snapshot`)** · noun-verb / obvious · snapshot · `snapshots.ps1:61`
*For* — See the restore points that exist for a VM, with when each was taken and whether the VM
was running at the time — and without the synthetic "current" row pretending to be one.
*Note* — Bare `pmx snapshot` routes to list but then **fails** with "--vm is required" instead of
opening the VM picker that `pmx vm show` and `pmx disk` both open. The one place in `pmx` where
the bare command refuses rather than picks.

**`pmx snapshot create`** · noun-verb / obvious · snapshot · `snapshots.ps1:90`
*For* — Take a labelled restore point before I change something meaningful, with reserved and
duplicate names refused up front rather than at the hypervisor.
*Note* — Accepts both `--vm X --name Y` and positional `X Y`, but mixing the two forms is an
explicit error. **No delete or rollback verb exists yet**, so the noun is half-built — a user who
can create a snapshot will look for `pmx snapshot rollback` and find nothing. Same shape of gap
as `git-stash` (§5.6).

**`pmx disk`** · other / guessable · disk · `command.ps1:215`
*For* — Pick a physical drive out of a list when I cannot remember its device name, then open it.
*Note* — **The worst overloading in the tree.** The same word is (a) a physical-drive picker,
(b) the router for `disk list` and `disk grow`, which are about a VM's **virtual** disks, and
(c) the prefix for a destructive F3 gate. Its own help topic admits it: "Physical host drives and
guest virtual disks share a noun but never an execution path." Falling through to `Show-PmxDisks`
when nothing is picked is good, but two unrelated objects under one noun is the structural
problem.

**`pmx disk <device|serial>` (`pmx disk <dev> smart`)** · other / obvious · disk ·
`command.ps1:58`
*For* — Look at one physical drive properly — model, serial, its stable by-id identity,
partitions, whether Proxmox is using it, SMART health, temperature, power-on hours, error counters
— and be told whether a destructive capacity test would even be permitted.
*Note* — `smart` is an optional no-op word (identical switch branch to no action). `-Full` is a
**single-dash** PowerShell-style flag and `--full` is **rejected outright**, while everything else
in `pmx` takes `--dry-run`/`--json`/`--table` — two flag dialects inside one command. Worse,
`-Full` **chooses what runs** (summary view vs raw smartctl dump), which the reference forbids.

**`pmx disk <device> test`** · noun-verb / obvious · disk · `command.ps1:60`
*For* — Ask a drive's own firmware to test itself (short or long) so I can read the verdict
later, without writing anything to it.
*Note* — **Dangerous near-neighbour:** `pmx disk sda test` is a safe read, `pmx disk sda
capacity-test` destroys all data. The distance between them is one hyphenated prefix on the same
verb. `extended` is accepted as an alias of `long`.

**`pmx disk <device> report` (`pmx disk <dev> evidence`)** · noun-verb / obvious · disk ·
`evidence.ps1:17`
*For* — Collect everything I would need at 2am to argue a drive is faulty or counterfeit — SMART,
authenticity signals, recent kernel storage errors — and optionally drop it into a dated folder I
can attach to an RMA claim.
*Note* — Two spellings for one handler. `-Write` is single-dash and is what turns a screen view
into files written to my home directory — again a flag **selecting** behaviour rather than
modifying it; under the reference rule this should be a word.

**`pmx disk <device> capacity-test`** · hyphen-abbreviated / guessable · disk ·
`physical-disks.ps1:169`
*For* — Prove a new or suspicious drive really has the capacity printed on it — which means
writing over the whole thing, so by default it only explains itself and refuses.
*Note* — **The single most dangerous path in the tree, and its arming mechanism is a flag**
(`-Destroy`, single-dash) that selects between "explain" and "destroy everything". This is the
sharpest contradiction with the reference, and the sharpest argument against a letter-flag
convention: a letter is the wrong shape for choosing an irreversible action (§2.1). It does still
demand a typed `DESTROY <by-id-leaf>` phrase, an interactive terminal, and a provably empty and
idle stable device.

**`pmx disk list`** · noun-verb / cryptic · vm disk · `vm-read.ps1:258`
*For* — See the virtual disks attached to one VM — slot names, sizes, backing storage and boot
role — so I know which one to grow.
*Note* — **The worst collision in the domain:** `pmx disk list` (virtual disks of one VM) and
`pmx disks` (physical drives in the host) are one letter apart and answer completely different
questions about completely different hardware. Anyone reaching for "list the disks" will get the
wrong one roughly half the time.

**`pmx disk grow`** · noun-verb / obvious · vm disk · `disk-grow.ps1:120`
*For* — Make a VM's disk bigger by stating the final size I want, and have the tool compute the
delta, check the pool actually has room, refuse to shrink, and refuse to guess when the VM has
more than one eligible disk.
*Note* — **The exemplary command in the domain** and the acknowledged model for the clone
rewrite: noun-verb, positional values (`pmx disk grow 101 100GiB`), `--dry-run` as a true
modifier, and an explicit disk table shown when the choice is genuinely ambiguous. Mixing named
(`--vm`/`--disk`/`--to`) and positional forms is refused rather than half-honoured.

**`pmx disks`** · other / obvious · disk · `physical-disks.ps1:55`
*For* — See every physical drive in the host at once with size, HDD/SSD, model, serial and what is
currently using it (partitions, mounts, holders, Proxmox use).
*Note* — One letter from `pmx disk`, and answers a different question from `pmx disk list`. Bare
plural noun, no arguments. Also collides in intent with three commands outside this domain —
`listdisks`, `disk-big`, `diskfree` — so the word "disk" is spread across at least six names
tree-wide.

**`pmx guests`** · other / obvious · guest · `command.ps1:235`
*For* — See everything running on this box — VMs and containers together — with state, CPU and
memory.
*Note* — Overlaps `pmx vm list`, which deliberately **excludes** LXC rows. So "what is on this
box" has two answers depending on which word you pick, and neither name says which. No arguments.

**`pmx guest`** · other / obvious · guest · `command.ps1:239`
*For* — Open one guest and read its node, power state, CPU, memory, disk and uptime; with nothing
named it just lists them all.
*Note* — One letter from `pmx guests`, and with no argument it **is** `pmx guests` — the
singular/plural pair is a naming coin-flip with no consequence, unlike `disk`/`disks` where the
same pair is genuinely dangerous. Uses a positional selector where `pmx vm show` would open a
picker.

**`pmx updates`** · other / obvious · updates · `command.ps1:245`
*For* — Find out what Proxmox packages are waiting to be upgraded, knowing the tool will never
install anything and will never run `apt update` behind my back.
*Note* — Bare plural noun, no verb, no arguments, read-only by design. Word-collides with the
tree-wide `powerflow-update`, which **does** install things — same verb stem, opposite safety.

---

### Docker — `components/docker/` *(untracked, in-flight)*

**`dkr`** · noun-verb / guessable · docker · `dkr.ps1:389`
*For* — "Show me what containers are on this box and let me act on a few of them at once" — one
table of every container (running **and** stopped, greyed not hidden) grouped by compose stack,
then with fzf let me Tab-mark several and choose one action for all of them, replacing a
hand-typed `sudo docker stop qbittorrent radarr sonarr jellyfin`.
*Note* — **The reference.** Every flag is a true modifier (`-a`/`--all`, `-f`/`--follow`,
`-y`/`--yes`, `--show-native`) and every choice-of-behaviour is a word. Deliberately has **no
`param()` block** so PowerShell cannot steal `-a` and `-f` as parameter names; `$args` is
hand-parsed and the header warns not to "fix" this (`:24-27`). Two undocumented behaviours worth
knowing: an unknown first word is treated as a container-name **filter** (`dkr sonarr` prints a
filtered table), which appears in no registration and not in `Show-DkrHelp`; and after a
multi-select, choosing `logs` or `shell` silently acts on only `$picked[0]` while
`stop`/`start`/`restart` act on all marked. §2.

**`dkr logs`** · noun-verb / obvious · docker · `dkr.ps1:494`
*For* — "Why is this container misbehaving — show me what it has been printing", without having to
know whether the container is called `sonarr`, `media-sonarr-1`, or a compose service.
*Note* — Registered as a registry **row named with a space** (`:543`) — it is not a function, so
`pwsh-h` can show the verb. That mechanism is what every consolidation in §5 relies on. Name
resolution is container → compose service → project → substring, and a miss prints near-matches
instead of docker's bare error. Tail is **hardcoded at 200 lines** — there is no `-n`/`--tail`, so
the one thing a user routinely wants to change cannot be changed. `-f`/`--follow` is the paired
short/long form the rule calls for.

**`dkr shell` (`dkr sh`)** · noun-verb / obvious · docker · `dkr.ps1:510`
*For* — "Get me a prompt inside that container so I can poke at its filesystem" — picks bash if
the image has it, else sh, so the user never has to remember which images are Alpine.
*Note* — Registration at `:546` declares `dkr sh` as an alias and the body accepts both spellings
(`$verb -in @('shell','sh')`). Refuses on a stopped container and prints the exact
`dkr start <name>` to run first — a good example of the creed, and the pattern §5.1 borrows for
its failure hint.

**`dkr restart`** · noun-verb / obvious · docker · `dkr.ps1:473`
*For* — "I edited the compose file / this service is wedged — bounce it" from any directory.
*Note* — Registered at `:547`. The synopsis "compose-correct from any directory" is **true** —
verified in `Invoke-DockerLifecycle` (`platform/*/adapters/docker.ps1:142`), which groups by
`Project|ConfigFile` and only falls back to plain `docker restart <names>` for standalone
containers, so the edited file is actually picked up. No names opens the running-container picker.

**`dkr stop`** · noun-verb / obvious · docker · `dkr.ps1:473`
*For* — "Shut these down" — with no names it opens a multi-select of running containers so four
services stop in four keystrokes.
*Note* — Registered at `:549`. Shares one handler with `start`/`restart`. Ambiguity → picker,
exactly as the rule requires.

**`dkr start`** · noun-verb / obvious · docker · `dkr.ps1:473`
*For* — "Bring these back up" — with no names it deliberately offers the **not**-running
containers, because those are the only ones you can start.
*Note* — Registered at `:551`. The pool inversion at `:482` is the detail worth copying: `start`
sees stopped containers, `stop` sees running ones. A picker that offers impossible choices is
worse than no picker.

**`dkr up`** · noun-verb / obvious · docker · `dkr.ps1:451`
*For* — "Start the whole stack" — including a stack that is entirely down and therefore invisible
to `docker ps`; with no name it uses whatever compose file is in the current directory.
*Note* — Registered at `:553`. Looks in `docker compose ls --all` **first** precisely so a down
stack is findable, and the failure path lists the projects on the host instead of just erroring.
The `-a` flag has no meaning for this verb but is silently accepted.

**`dkr down`** · noun-verb / obvious · docker · `dkr.ps1:451`
*For* — "Take the stack down but do not lose my data" — removes containers and networks, and says
**in words** that named volumes survive before asking y/N.
*Note* — Registered at `:555`. The only destructive verb in the domain that both confirms **and**
states what is not destroyed; `-y`/`--yes` is the modifier that skips it. This is the pattern
§5.2's `git-discard` confirm, §5.13's `powerflow fix` reset, and `pwsh-recovery` option 5 should
all be copying.

---

### Help and core — `components/help/`, `components/core/`

**`pwsh-h` (`pwsh-help`)** · prefixed-family / guessable · help · `menu.ps1:41`
*For* — "What can this thing do?" and "what does this one command do?" — bare, it prints the whole
generated manual grouped into chapters; given a word it tries, in order, an exact command or
alias, a Linux lesson, a lesson topic, a section keyword, then a substring search over names and
synopses.
*Note* — **The one flag-as-selector in this slice:** `-a`/`-advanced` choose which program runs
(the fzf browser instead of the printed manual), which the reference forbids — it should be a word
(`pwsh-h search`). A third switch, `-all`, is declared in `param()` and then **never read** (`:42`
vs `:46`), so `pwsh-h -all` silently prints the manual. That triple is also the concrete example
`storage.ps1:32-33` cites when rejecting `-D` (§2.1). Falls back to the manual when stdout is
redirected or fzf is missing, so it can never hang in CI. The `pwsh-help` alias rescues the
guessability of the one-letter name.

**`powerflow-version`** · prefixed-family / obvious · powerflow · `version.ps1:259`
*For* — "What version of PowerFlow am I on?" — three lines: version, repo, profile path.
*Note* — A strict **subset** of `Get-PowerFlowVersion` (the same first three facts). Two
registered commands answer the identical question — the clearest merge candidate in the tree.
§5.13.

**`Get-PowerFlowVersion`** · other / cryptic · powerflow · `version.ps1:223`
*For* — "Is my install actually healthy?" — version, repo and profile path plus whether `$PROFILE`
exists, how many of the five dependencies resolve, and how many bookmarks are configured, drawn
in a box.
*Note* — **The odd one out: the only Verb-Noun name in the entire command registry**
(hand-registered at `version.ps1:309`). `CLAUDE.md` says Verb-Noun helpers go in `COMPONENTS.md`
and **not** the registry, because `pwsh-h` is a command reference and not a function index — and
the CI drift gate is case-sensitive, so it could never have caught this. A user typing kebab
commands all day will never guess it. Also reaches across domains into bookmarks
(`$script:BookmarkFile` / `Get-Bookmarks`). Overlaps `powerflow-version` almost entirely. §5.13.

**`powerflow-update`** · prefixed-family / obvious · powerflow · `version.ps1:152`
*For* — "Get me the newest PowerFlow" — reads the latest tag from the releases redirect (cheap, no
API quota), prints current versus latest, asks y/n, then downloads `install.ps1` and runs the real
installer in a child `pwsh -NoProfile` so it is not replacing files under its own feet.
*Note* — **Near-collision that matters:** shares the prefix `powerflow-u` with
`powerflow-uninstall`, so tab completion needs eleven characters before the **upgrade** and the
**delete** separate. `-Yes` is a legitimate modifier and the startup prompt uses it
(`version.ps1:102`), so no rename may drop it. Running a dev version above the latest tag prints a
note and exits. §5.13.

**`pwsh-reminders`** · prefixed-family / guessable · powerflow · `version.ps1:265`
*For* — "Stop nagging me about updates every time I open a shell" (and later, turn it back on) —
shows ON/OFF then toggles `$script:CHECK_PROFILE_UPDATES` by regex-rewriting
`config/PowerFlow.settings.ps1`; enabling also deletes the snooze marker so the check fires on the
next load.
*Note* — Near-collides with `pwsh-recovery` on the `pwsh-re` prefix — one silences a notification,
the other offers to delete your profile. **Live bug:** the settings path is built as
`Join-Path $PowerFlowRoot "config\PowerFlow.settings.ps1"` with a hardcoded **backslash**
(`:266`, and the same line at `:106` inside `Check-PowerFlowUpdates`). On Linux that is a single
literal filename, `Test-Path` fails, the file is never rewritten — yet the in-memory flag is set
and the success message still prints, so the setting silently reverts on the next shell. Its logic
is duplicated verbatim in the update prompt's option 4. §5.12, §5.13.

**`pwsh-recovery`** · prefixed-family / guessable · powerflow · `recovery.ps1:19`
*For* — "PowerFlow is broken — get me out of it" — prints a numbered 1-9 menu and `Read-Host`s a
digit: reload the profile, check the five tools, reinstall them, re-run the installer, delete
`$PROFILE`, open the profile in an editor, show version, run `powerflow-update`, or open `pwsh-h`.
*Note* — **The anti-reference shape:** the user must read and memorise a numbered menu, and
options 7/8/9 are merely other commands, so half of it is a launcher. Option 5 deletes `$PROFILE`
behind a bare y/n **with no backup** — unlike `powerflow-uninstall` twelve lines below, which does
back up. Prefix-collides with `pwsh-reminders`. Option 2 hardcodes the tool list instead of calling
`Get-RequiredTools` like option 3 does, so the two can drift (there is a third copy at
`version.ps1:233`). §5.13.

**`powerflow-uninstall`** · prefixed-family / obvious · powerflow · `recovery.ps1:97`
*For* — "Take PowerFlow off this machine but leave the tools I already had" — lists exactly what it
will delete, requires typing the full word "yes", backs up `$PROFILE` with a timestamp, removes
the bootloader plus `config/` and `components/`, then separately offers to uninstall
starship/fzf/zoxide/lsd (never git, never the package manager).
*Note* — **The best-behaved destructive command in the tree:** names the targets, demands "yes"
not "y", backs up first, and treats shared tools as not-ours. Two gaps: it removes only `config/`
and `components/`, so on a v3+ tree `platform/` (the whole adapter layer) and `windows-only/` are
left on disk; and its screen still says `components\ (all functions)` with a Windows backslash.
Prefix-collides with `powerflow-update`. Note the name is printed by `install.ps1:441` and baked
into generated release notes by `release-generate-scripts.yml:119`, so it can never be retired.
§5.13.

---

### Terminal — `components/terminal/`

**`open-nt`** · hyphen-abbreviated / cryptic · tab · `tabs.ps1:22`
*For* — "Give me another terminal here" — opens a new tab or tmux window already sitting in the
current directory; an optional first word picks the shell.
*Note* — "nt" = new tab; unguessable. **One edit from `open-t`, which does something else
entirely** (switches to tab N), so a typo silently teleports you instead of giving you a new
shell. The `-Shell` argument is documented nowhere in the registry, which hides that
`open-nt ubuntu` is a **third** way to open a WSL tab. Registered `-Platform 'Windows'` even
though `platform/linux/adapters/terminal.ps1:56` implements `New-TerminalTab` via tmux, so Linux
users have it but never see it in `pwsh-h`. `docs/migration/v3-upgrade.md:12` is a published
promise that this name still works. §5.9.

**`open-t`** · hyphen-abbreviated / cryptic · tab · `tabs.ps1:41`
*For* — "Jump to tab 3" — Alt+N via SendKeys on Windows, `tmux select-window -t N` on Linux; only
1-9 accepted.
*Note* — One edit from `open-nt`, different outcome. The Windows adapter's `Switch-TerminalTab`
returns `$true` **unconditionally** (`platform/windows/adapters/terminal.ps1:117`), so "Switched
to tab 7" prints happily when there is no tab 7. Registered Windows-only despite a working tmux
implementation. §5.9.

**`close-t`** · hyphen-abbreviated / cryptic · tab · `tabs.ps1:54`
*For* — "Close tab 3" without leaving the tab you are in — though the Windows implementation
actually switches to it first (Alt+N, 100 ms sleep, Ctrl+Shift+W).
*Note* — One edit from `close-ct`, which kills the **shell** instead of a numbered tab. The
Windows path is a timing-dependent SendKeys pair: if the Alt+N does not land within 100 ms it
closes whatever tab has focus — a destructive command with no confirmation and no verification,
reporting success either way. The Linux path (`tmux kill-window -t N`) does check
`$LASTEXITCODE`. §5.9.

**`close-ct`** · hyphen-abbreviated / cryptic · tab · `tabs.ps1:27`
*For* — "Close this tab" — the body is literally `exit`; it ends the shell, and the tab closes only
because the tab **is** the shell.
*Note* — "ct" = current tab. Adds nothing over typing `exit`, and one edit from `close-t` (close
tab N). Registered `-Platform 'Windows'` although `exit` is platform-neutral — and on Linux this
is the exact footgun `pwsh-exit` (`login.ps1:104`) exists to prevent, since PowerFlow can be the
SSH login shell there. Three commands now overlap on "end this session": `close-ct`, `pwsh-exit`,
plain `exit`. **The one name in the tab family with a behavioural reason to die.** §5.9.

**`next-t`** · hyphen-abbreviated / cryptic · tab · `tabs.ps1:29`
*For* — "Flip to the next tab" — Ctrl+Tab via SendKeys on Windows, `tmux next-window` on Linux.
*Note* — Registry oddity, verified by reading `tabs.ps1:70`: registers `-Aliases @('prev-t')`, but
`prev-t` is a **separate function** at `:35`, not an alias. So `pwsh-h` renders "next-t (prev-t)"
and `pwsh-h prev-t` shows the next-t row with the next-t synopsis — **the registry is lying to
satisfy the CI alias-coverage gate.** Windows path always reports success. §5.9.

**`prev-t`** · hyphen-abbreviated / cryptic · tab · `tabs.ps1:35`
*For* — "Flip back to the tab I was just on" — Ctrl+Shift+Tab on Windows, `tmux previous-window`
on Linux.
*Note* — Has **no registration of its own** — it is only listed as an alias of `next-t` (`:70`),
so it has no synopsis and no detail view in `pwsh-h`. A real function wearing a fake alias. §5.9.

**`send-keys`** · other / guessable · tab · `tabs.ps1:17`
*For* — "Type this for me" — injects a raw keystroke string into whatever currently has focus
(`System.Windows.Forms.SendKeys` on Windows, `tmux send-keys` into the current pane on Linux).
*Note* — The name is literally tmux's own subcommand, and the shape is a lowercased Verb-Noun,
unlike every sibling in the file. Its registered synopsis says "send keystrokes to **another
tab**" (`:73`) but the function takes **no target** — there is no way to name a tab, so keys go
wherever focus already is. The synopsis is marketing that drifted from behaviour. Also the one
command here that can type arbitrary input into an unknown window, with no confirmation.
Registered Windows-only though the Linux adapter implements it (`terminal.ps1:49`). §5.9 argues
for deleting the wrapper rather than renaming it.

---

### Windows-only — `windows-only/`

**`open-ubuntu`** · other / guessable · wsl · `wsl.ps1:12`
*For* — "Give me a Linux shell sitting in this same folder" — opens a Windows Terminal tab on an
Ubuntu profile and copies a ready-made `cd /mnt/<drive>/...` line to the clipboard so you can
paste your way to the current directory.
*Note* — **The profile GUID is the author's own machine** ("Use the exact GUID from your Windows
Terminal settings", `:15`) — on anyone else's box it opens the wrong profile or nothing, and
because `Start-Process` succeeds regardless the function still prints "Ubuntu-20.04 tab opened!".
Duplicates `open-nt ubuntu` (which runs the same GUID logic in the adapter) and
`open-wsl-simple` — **three commands for one goal.** Uses `Set-Clipboard` and `$env:LOCALAPPDATA`
directly, legal only because the file lives under `windows-only/`. This file also defines an
unregistered, user-facing-looking diagnostic, `Get-WindowsTerminalProfiles`, which prints every WT
profile and its GUID and is invisible in `pwsh-h`.

**`open-wsl-simple`** · other / cryptic · wsl · `wsl.ps1:81`
*For* — The same goal as `open-ubuntu` — open a WSL tab and hand me the cd line — but resolved by
profile **name** (default `Ubuntu-20.04`) instead of by GUID.
*Note* — "simple" names the **implementation** (no GUID lookup), not anything a user wants — from
the outside it is indistinguishable from `open-ubuntu`, so a user cannot tell which to type or
why. `$currentPath.Substring(3)` assumes a drive-letter path and mangles UNC paths. Its registered
synopsis, "open WSL without Terminal profiles", is backwards: it works **exclusively** through a
Terminal profile name.

---

*End of inventory — 201 surfaces.*
