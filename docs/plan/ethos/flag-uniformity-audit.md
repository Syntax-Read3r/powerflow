# Flag Uniformity — Findings Log

**Status:** Evidence only. No convention has been chosen. This document exists so that one
can be chosen with the full cost in view.
**Date:** 2026-08-08
**Scope:** Every user-facing command surface in `components/`, `windows-only/`, `platform/`.
**Method:** Every conflict below was written as a claim, then attacked — the parser or the
function was executed in `pwsh` and the claim was corrected or dropped where it did not
survive. Line numbers are the corrected ones. Where a claim was refuted it is recorded as
refuted rather than deleted, because "this is not a defect" is also evidence.

---

## 1 · What the owner asked

> Log the non-uniformity. Do not fix it.

That is the whole brief, and the reason for it is that the owner intends to choose the
convention themselves, from the evidence. So nothing in this document picks a winner.
Section 4 lays out what exists and what each inconsistency costs a user; section 5 records
the non-uniformities that were already decided on purpose and must not be swept up by a fix;
section 6 prices the candidate conventions; section 7 lists the decisions only the owner can
make.

---

## 2 · The count

**45 flags in PowerFlow are single-dash words** — `-power`, `-status`, `-recurse`, `-full`,
`-lesson`, `-detailed`, `-anchor`. That is the number that matters, because a single-dash
word is the one token shape whose meaning depends entirely on which half of the codebase
receives it. Handed to a `param()` block it binds as a parameter name, which is correct and
idiomatic PowerShell. Handed to `Split-GnuArgs` it is shredded into individual letters,
which is why `rm -force node_modules` is exactly `rm -rf node_modules` (§4.1).

| Surface | Count |
|---|---|
| Command surfaces surveyed | 167 |
| Registered commands (`Register-PFCommand`) | 138 |
| Accepted tokens catalogued | 598 |
| — `--long` (two-dash word) | 169 |
| — bare word (subcommand / positional keyword) | 167 |
| — value (positional argument) | 130 |
| — **param-derived** (exists only because PowerShell derives it) | **54** |
| — `-long` (one-dash word) | 45 |
| — `-short` (one-dash letter) | 33 |

Two secondary numbers are worth stating outright:

**54 of the 301 dashed tokens — 18% — were never authored.** They exist because PowerShell
binds any unambiguous prefix of a parameter name. `git-a-plus -a` amends the last commit;
`git-a-plus -q` and `-d` work too. Nobody wrote them, no help text lists them, and they
cannot be removed without renaming the parameters they abbreviate.

**Five commands share one parser.** `rm`, `mv`, `rmdir`, `touch` and `mkdir` all call
`Split-GnuArgs` (`components/files/operations.ps1:73, 309, 689, 751, 810`), which validates
long flags and does not validate short ones at all. Every hazard in §4.1 is a property of
those two lines, not of five separate bugs.

---

## 3 · Why this is harder than "pick one"

The tension is structural, not stylistic, and it cannot be argued away.

**PowerShell makes `-word` native.** A `param([switch]$status)` block gives you
`-status` for free, and with it case-insensitivity (`-Status`, `-STATUS`) and prefix
matching (`-s`, `-st`, `-stat`) — all without a line of parsing code. This is what the host
shell does, what every PowerShell user's fingers already know, and what `Get-ChildItem
-Recurse` taught them. `components/files/listing.ps1:53-55` honours exactly that instinct
in writing:

```powershell
# -recurse / -Recurse: the spelling a PowerShell user already knows. Get-ChildItem
# habits should not be punished. NOT -r — that is GNU reverse-sort and lsd honours
# it; -R is GNU recursive and already works.
'^-{1,2}recurse$' { $pfTree = $true }
```

**But the commands are Unix-flavoured, where `-word` is a cluster.** PowerFlow reimplements
`rm`, `mv`, `ls`, `touch`, `mkdir`, `rmdir` and wraps twenty coreutils as "brothers". In
that world `-force` is not a word at all; it is `-f -o -r -c -e`. GNU getopt refuses it
(`invalid option -- 'e'`). PowerFlow's parser accepts every letter, which is how a word
that reads as a safety flag arms a recursive delete.

**A `param()` block cannot accept `--long` at all.** This is the fact that makes the choice
genuinely hard rather than merely expensive. PowerShell parses `--foo` as a positional
*value*, never as the parameter name `foo`. So on a `param()` command the GNU spelling
either vanishes into `$args`, binds silently as a string, or hard-errors — depending on the
function's shape. `pwsh-font --status` is the sharpest case: `-status` is a read-only query,
`--status` leaves the switch false and the command proceeds to *install* (§4.3).

The codebase has already reached the opposite conclusion twice, in writing, for two
different reasons:

```powershell
# components/files/listing.ps1:11
# THE RULE:  single dash belongs to Linux.  long dash belongs to PowerFlow.
```

```powershell
# components/system/storage.ps1:249-250
# NO param() block. A param() would bind -a and -D as parameter NAMES, and PowerShell's
# prefix matching would make -D ambiguous with any other D parameter. See the header.
```

So the stated rule is GNU-strict, and the mechanism chosen to achieve it is hand-parsing.
But 40 of the 125 user-facing commands have `param()` blocks, and the flags a `param()` block
produces are single-dash words with prefix matching — the exact shape the stated rule
forbids. **Whichever convention wins, one of the two instincts gets violated.** Adopt
GNU-strict and every `param()` command must be rewritten as a hand-parser, losing
case-insensitivity and prefix forgiveness that users currently rely on. Adopt
PowerShell-native and `rm`, `ls` and the brothers stop matching the tools they impersonate.

This document does not resolve that. It measures both bills.

---

## 4 · Findings

Twenty-one verified conflicts, ordered by severity and then by blast radius. Severity is
about consequence, not about how wrong the code looks: a flag that silently does the wrong
thing outranks a flag that errors, because an error is information.

### 4.1 · A single-dash word is shredded into letters, so `rm -force` is `rm -rf`

**Severity: high. Blast radius: `rm`, `mv`, `rmdir`, `touch`, `mkdir`, plus `del` on Linux.**

`Split-GnuArgs` splits any single-dash token into individual characters and sets a flag for
each one, with no length check and no membership test:

```powershell
# components/files/operations.ps1:60-63
# -rf  ->  r, f.  A lone "-" is a path (stdin convention), not a flag.
if ($s -match '^-(.+)$') {
    foreach ($c in $matches[1].ToCharArray()) { $flags["$c"] = $true }
    continue
}
```

The `$unknown` collector that feeds every command's "unknown option" warning is populated
only in the `^--(.+)$` branch above it (`components/files/operations.ps1:53-56`). So a
one-dash word can never produce a warning. `rm --recurse x` warns and refuses;
`rm -recurse x` recurses.

Verified by executing the real parser and the real `rm` against a real directory tree:

| Typed | Flags produced | Effect |
|---|---|---|
| `rm -force x` | `c,e,f,o,r` | `r` **and** `f`: directory guard skipped, `[y/N]` skipped, tree deleted with no prompt and no warning |
| `rm -Force x` | `c,e,F,o,r` | identical — the flag hashtable is case-insensitive, and `-Force` is the spelling a PowerShell user reaches for first |
| `rm -verbose x` | `b,e,o,r,s,v` | `r` set, `f` not: the "Is a directory" refusal is gone, but the prompt still fires |
| `rm -interactive x` | `a,c,e,i,n,r,t,v` | sets `i` **and** `r`: asks once, then recurses |
| `rm -recurse x` | `c,e,r,s,u` | works, by accident — the word happens to contain an `r` |
| `touch -recurse f` | `c,e,r,s,u` | sets `c` (no-create), so `touch` silently declines to create the file |
| `mkdir -parents d` | `a,e,n,p,r,s,t` | harmless — `mkdir` reads only `p` and `v`, which is why the hazard stays invisible until the same habit reaches `rm` |

The two flags that make `-force` lethal are read three lines apart:

```powershell
# components/files/operations.ps1:77-78
$force     = $parsed.Flags.ContainsKey('f')
$recurse   = $parsed.Flags.ContainsKey('r') -or $parsed.Flags.ContainsKey('R')
```

`$recurse` bypasses the directory refusal at `operations.ps1:139`, `$force` bypasses the
confirmation at `:152`, and the delete runs at `:174`.

**What makes this a uniformity finding and not a plain bug** is that the habit is taught
elsewhere in the same slice. `components/files/listing.ps1:56` grants `-recurse` /
`--recurse` / `-Recurse` on `ls` deliberately, with the comment quoted in section 3, and
`ls`'s registry entry advertises it:

```powershell
# components/files/listing.ps1:164
-Example 'ls -la · ls -recurse -depth 2 · ls -srv complete'
```

`components/navigation/nav.ps1:31` grants `-verbose` on `nav` the same way. A user who
learns one-dash words from `ls` and `nav` and carries them to `rm` loses a tree.

On Linux the hazard survives under a different name, because
`platform/linux/bindings.ps1:43` copies the function body wholesale:

```powershell
if (Test-Path Function:\rm) { ${function:global:del} = ${function:rm} }   # fzf picker + confirm + recursive delete
```

**The author already found this bug class and fixed one instance.** `mv` strips its own
one-dash word in a pre-pass before parsing, and the comment names the mechanism exactly:

```powershell
# components/files/operations.ps1:299-307, comment abridged
# -detailed is PowerFlow's own and must be pulled out BEFORE flag parsing:
# Split-GnuArgs would otherwise read '-detailed' as the bundled short flags
# -d -e -t -a -i -l -e -d. (Per PowerFlow's rule the long form --detailed is the
# correct spelling, but the single-dash one is accepted so nobody's habit breaks.)
if ("$a" -in @('-detailed', '--detailed')) { $detailed = $true } else { $argv += "$a" }
```

That fix went to one token in one command. The guard belongs at
`components/files/operations.ps1:61-62`, where short flags are still unvalidated. GNU getopt
rejects `-verbose` with `invalid option -- 'e'`; this parser accepts every letter.

---

### 4.2 · `git-bd` and `git-bD` are one function, and the survivor force-deletes

**Severity: high. Blast radius: one command, unbounded consequence — lost commits.**

Two `function` definitions differ only in the case of the final letter. PowerShell's function
table is case-insensitive, so the later definition replaces the earlier one's body while
keeping the earlier one's casing as the table key.

- `components/git/branches.ps1:265` — `function git-bd`, runs `git branch -d` at `:277`
  (safe, merged-only). Dead code.
- `components/git/branches.ps1:286` — `function git-bD`, runs `git branch -D` at `:299`
  (force). Defined 21 lines later, so this is what both names execute.

Verified in `pwsh -NoProfile` by dot-sourcing the real file with `git` shimmed:
`(Get-Command git-bd).Definition` contains `git branch -D`, and `git-bd somebranch` prints
`Force-deleted branch:`.

The unreachable branch advises escalating to the command the user is already running:

```powershell
# components/git/branches.ps1:281-282
Write-Host "❌ Could not delete branch: $branchName (not fully merged?)" -ForegroundColor Red
Write-Host "💡 Use git-bD to force delete unmerged branches" -ForegroundColor DarkGray
```

And the registry states a safety gradient the runtime cannot make, in the direction that
makes the dangerous command look safe:

```powershell
# components/git/branches.ps1:380
Register-PFCommand -Name 'git-bd'   -Aliases @('git-bD') -Section '🎯 ENHANCED GIT WORKFLOW' -Synopsis 'delete a branch (bD forces)'
```

Two further wrongs on that one line: `git-bD` is registered as an *alias* when it is a second
`function` (a repo-wide grep finds no `Set-Alias` for it), and `COMPONENTS.md:171` propagates
the same false two-function model.

**Consequence:** a user who deliberately types the lowercase form to avoid losing unmerged
work loses it, silently, because `git branch -D` succeeds. This is the one case in the audit
where the inconsistency is invisible in the source *and* at runtime — the surviving command
name is the safe-looking one.

---

### 4.3 · `--long` cannot bind on any `param()` command, and one such case performs a write

**Severity: high. Blast radius: all 40 `param()`-block commands.**

PowerShell parses `--foo` as a positional value, never as the parameter name `foo`. What
happens next depends on the function's shape, so one token has four outcomes:

| Function shape | `--flag` becomes |
|---|---|
| simple function, no positional parameter | silently dropped into `$args`, which is usually never read |
| positional string parameter present | silently bound as that parameter's value |
| typed positional (`[int]`) or a `ValidateSet` | a cast or validation error |
| `[CmdletBinding()]` with no positional slot | hard error: *A positional parameter cannot be found* |

The load-bearing instances are the ones where PowerFlow's **own documented** one-dash flag has
a GNU spelling that fails:

- **`pwsh-font --status` — the worst case.** `components/system/fonts.ps1:29` is
  `param([switch]$status)`, documented at `:24` and in the registration at `:68`. `--status`
  leaves `$status` false, skipping the read-only branch at `:33-44`, and on a machine where
  the font is absent it reaches `Install-NerdFont` at `:51`. A status query performs an install.
- **`git-rl --help` — the sharpest inconsistency.** `components/git/release.ps1:206` is
  `[CmdletBinding()]` over a switch-only `param()`, so `--help` throws *"A positional
  parameter cannot be found that accepts argument '--help'"* — including through the
  `function git-rl { git-release @args }` splat at `:472`. An AST scan of `components/`,
  `platform/`, `shared/` and `windows-only/` confirms this is the only user-facing command in
  the repo where `--help` crashes, while `pmx --help`, `dkr --help` and `srv --help` all work.
- **`git-a-plus --quick` / `--dry-run` / `--amend`** — `components/git/commit.ps1:246-248`.
  The registration at `:459` advertises `-Quick, -DryRun, -AmendLast`; all three long forms
  fall into `$args` and the command drops through to the default `git-a` path at `:449` with no
  error.
- **`pwsh-h --advanced`** — `components/help/menu.ps1:42`. `-advanced` is documented at `:36`
  and `:262`; `--advanced` binds into `$Topic` and prints `Nothing called '--advanced'`
  (`menu.ps1:84`).
- **`powerflow-update --yes`** — `components/core/version.ps1:153`. `-Yes` is documented in
  the `.EXAMPLE` at `:150`; `--yes` leaves it false and the confirmation at `:174-179` prompts
  anyway. Benign, same defect.

The contradiction is stated in the tree. `components/files/operations.ps1:301` says "Per
PowerFlow's rule the long form `--detailed` is the correct spelling", and the hand-parsed half
of the codebase honours that rule — `Split-GnuArgs` long flags, `--help` in `pmx`, `dkr` and
`srv`. The `param()` half physically cannot.

Illustrative but not uniformity conflicts, because the token is not a PowerFlow spelling of
anything: `linux-lessons -full` / `--full` (`components/shell/teach.ps1:37` — the documented
interface is the bare word `full`; one dash goes to `$args` and prints the current mode, two
dashes dies on the `ValidateSet`); `gh-l --count` (`components/github/browser.ps1:113` — a
`System.Int32` cast error, and `-Count` is a value parameter rather than a switch);
`rn -force` (`components/files/rename.ps1:26` — `ValueFromRemainingArguments` swallows it
into the filename); `perms -foo` (`components/shell/teach.ps1:174` — one dash errors, two
dashes binds silently as `$Path`).

---

### 4.4 · Prefix matching invents flags nobody designed, and one of them rewrites history

**Severity: high. Blast radius: all 40 `param()`-block commands; 54 catalogued tokens.**

Every `param()` command silently accepts unambiguous prefixes of its parameter names. Nothing
in the source declares them, so no help text can list them and no author chose them — users
find them by typo. Three failure classes follow, none of which a hand-parsed command can have.

Resolution rules that matter, and that make the surface unpredictable in both directions: the
function's own parameter beats a common parameter on a prefix tie, so `-d` and `-e` do not
collide with `-Debug` and `-ErrorAction`; ambiguity arises only when two of the function's own
parameters share a prefix, or when *only* common parameters match; and an exact match on a
built-in alias (`ov`, `ob`, `pv`, `db`, `ea`, `vb`) beats a prefix match on a real parameter.

**Silent absorption — the flag becomes a value, or does nothing.**

- `git-a-plus -a` binds `-AmendLast` (`components/git/commit.ps1:248`). The sharp one. The
  branch runs `git add .` then `git commit --amend`, and the only thing between the user and
  the rewrite is an fzf *message* box — escaping it leaves the message empty and falls straight
  into `git commit --amend --no-edit`. There is no abort path. `git push --force-with-lease`
  (`:330`) is then offered behind a y/n. A user reaching for git's own "stage everything"
  rewrites the last commit.
- `git-a-plus -q` binds `-Quick`, `-d` binds `-DryRun`. Three one-letter forms nobody declared.
- `srv -c lab` binds `$Command = 'lab'` (`components/network/servers.ps1:174`), which falls
  past every switch case to the connect-by-name block at `:344-378` and calls
  `Connect-PFServer`. It opens an SSH session.
- `.. -t foo` is identical to `.. foo` (`components/navigation/directory.ps1:66-68`; `-t` is a
  prefix of `$targetDirParts`). The same block repeats verbatim at `:104-107`, `:143-146` and
  `:181-184` — four separate functions, not one function with aliases, despite the registry at
  `:237` listing the deeper dots under `-Aliases`.
- `rn -f draft.md` is identical to `rn draft.md` (`components/files/rename.ps1:26`).
- `pc-whoami -de 3` binds `Debug=True, name=3`: `de` prefixes the common `-Debug` but not
  `-days`, so the number becomes a program name and the command drills into a process called "3".

**"Missing an argument" for what the user meant as a switch.**

- `history -c` errors with *Missing an argument for parameter 'Count'*
  (`components/shell/history.ps1:91`). bash's `history -c` clears history; here it demands a
  number. `-l`, `-p` and `-a` land in `$args` and are ignored.
- `pc-cap -v` errors the same way; `pc-cap -v 85` caps the CPU
  (`components/system/health.ps1:780`). The token that means verbose in `nav` and in `mv`,
  `touch` and `mkdir` is a required value here.
- `open-nt -s` errors on `Shell` (`components/terminal/tabs.ps1:23`). Compare `set-path -s`
  (`components/system/path.ps1:14`, a switch), `pwsh-font -s`
  (`components/system/fonts.ps1:29`, a switch) and `git-rl -s`
  (`components/git/release.ps1:209`, an undeclared prefix that prints the setup prompt).
- `pwsh-config -W` errors on `Which` (`components/system/sysconfig.ps1:46`); `-w tz` binds.
- `installed-apps -Ov` errors on `OutVariable` (`components/system/apps.ps1:272`). Narrow but
  instructive: `-o` is a declared `[Alias]` and works, `-Ove` works by prefix, and only the
  exact token `-Ov` misfires, because `ov` is PowerShell's built-in alias for `OutVariable`.

**Ambiguity errors naming parameters the user never typed.**

- `pc-whoami -p` → *"the parameter name 'p' is ambiguous. Possible matches include: -program
  -power -ProgressAction -PipelineVariable"* (`components/system/health.ps1:81`). `$program`
  exists only to catch the second word of a two-word program name, and it collides with the
  flag the user wants; `-po` is required.
- `pc-whoami -o` → *"ambiguous. Possible matches include: -OutVariable -OutBuffer"*. A single
  `[Parameter()]` attribute at `:81` silently makes the function advanced, so eleven common
  parameters join the namespace; none of pc-whoami's own start with `o`, so only PowerShell
  internals are named.
- `srv -P` → *"ambiguous. Possible matches include: -Param1 -Param2"*
  (`components/network/servers.ps1:175-176`).

**One command errors where the whole house swallows.** `perms -foo` →
*"A parameter cannot be found that matches parameter name 'foo'"*
(`components/shell/teach.ps1:174`). `[Parameter(Position = 0)]` alone makes the function
advanced, so unknown dash tokens crash — whereas every simple function in the codebase puts
them in `$args`.

**The two most instructive instances fail for opposite structural reasons.** `pc-cap`
(`components/system/health.ps1:779-780`) has no `[CmdletBinding()]`, so `-v` collides with
nothing except universal user expectation, and it succeeds silently. `installed-apps`
(`components/system/apps.ps1:269`) does have `[CmdletBinding()]`, and that is precisely why
`-Ov` breaks.

Finally, one hand-parse in this class is dead. `components/github/browser.ps1:118` comments
"Allow positional parameter for count: gh-l 15", but `gh-l 15` already binds `Count=15` with
`$args` empty. The block only fires on a third bare token: `gh-l 5 tok 20` yields
`Count=5, Token=tok, args=[20]`, and line `:119` then overrides `Count` to 20.

**The codebase has already decided against this once.** `components/system/storage.ps1:249-250`
refuses a `param()` block in so many words (quoted in section 3),
`tests/storage/storage-behaviour.ps1:71-80` enforces it as a regression test, and
`docs/plan/proxmox/pmx-vm-management.md:21` specifies "exact long option names, no
abbreviation" for `pmx`.

---

### 4.5 · "Show me help" has four spellings, and three commands declare one they cannot reach

**Severity: high. Blast radius: seven commands, including the one whose entire job is help.**

`-h` is the most-guessed flag there is, and it is the one token that must never surprise
anyone. Here is what each command actually accepts, all verified by execution:

| Command | `help` | `-h` | `--help` | `/?` |
|---|---|---|---|---|
| `pmx` | yes | yes | yes | yes |
| `dkr` | yes | yes | yes | no — becomes a verb |
| `storage` | no | yes | yes | no |
| `srv` | yes | **declared but dead** | yes | yes |
| `team-room` | yes | **declared but errors** | yes | read as a room name |
| `pwsh-h` | no | hard error | prints *Nothing called '--help'* | no |
| `nav` | no | — | prints *Unknown starting point* | no |

`pmx` is the widest and the model: `components/proxmox/command.ps1:171` accepts all four at
token zero, and `:184` re-scans the whole command line so a help token anywhere always beats
running the command:

```powershell
# components/proxmox/command.ps1:184
if (@($argv | Where-Object { "$_".ToLowerInvariant() -in @('--help', '-h', '/?') }).Count) {
```

`dkr` and `storage` accept `-h` / `--help` because they hand-parse `$args`
(`components/docker/dkr.ps1:404`, `components/system/storage.ps1:260`), and both files say in
comments that a `param()` block is forbidden for exactly this reason.

**The three failures are all caused by calling convention, not by intent.**

- **`srv -h` silently opens the SSH picker.** `components/network/servers.ps1:306` declares
  `{ $_ -in 'help', '-h', '--help', '/?' }`, but the `param()` block at `:173-178` has no
  `[Parameter()]` attribute, making `srv` a simple function. `-h` matches no parameter, lands
  in the automatic `$args`, `$Command` stays empty, every switch case misses, and control falls
  to the bare-`srv` path — the fzf picker whose Enter key calls `Connect-PFServer`. The comment
  at `:300-305` shows help was meant to work here ("`pmx help` and `team-room help` both work;
  srv now matches them").
- **`team-room -h` throws a raw binder error.** `components/system/team-room.ps1:265` declares
  the same set, but `[Parameter(Position = 0)]` at `:251` makes the function advanced, so `-h`
  is a parameter-name attempt with no match: *"A parameter cannot be found that matches
  parameter name 'h'"*. The `-h` cases at `:261` and `:265` are unreachable. `/?` binds to
  `$Command`, fails the verb list at `:261`, is reassigned to `$Name`, and answers
  *"No team room called '/?'"* — a token `srv` accepts and `team-room` does not.
- **`pwsh-h` accepts none of the four.** `components/help/menu.ps1:42` is
  `param([Parameter(Position = 0)][string]$Topic = '', [switch]$a, [switch]$advanced, [switch]$all)`.
  `-h` is a hard binder error; `--help` binds into `$Topic` and prints
  *"Nothing called '--help'. Try: pwsh-h"*.

Sharpened after refutation: these branches are not literally dead. `srv '-h'` and
`team-room '-h'` — quoted, or passed through a variable — do print help, because the token
arrives as a value rather than a parameter. They are unreachable only through the syntax a
user types, which is the syntax that matters.

**The `-h` crash is not confined to those two.** Fifteen user-facing kebab commands are
advanced functions with no `h`-prefixed parameter, so a literal `-h` throws on all of them:
`copy-file`, `disk-big`, `git-bd`, `git-rb`, `installed-apps`, `pc-whoami`, `perms`, `pwsh-h`,
`rn`, `s`, `set-path`, `shutdown`, `source`, `start-folder`, `team-room`. `team-room` is
distinctive only in declaring a handler the crash makes unreachable.

**`-h` also carries a non-help meaning.** On `git-release` / `git-rl`,
`components/git/release.ps1:206-209` is:

```powershell
[CmdletBinding()]
param(
    [Alias('h', 'help', '?')]
    [switch]$ShowSetupPrompt
)
```

That runs `Show-GitReleaseSetupPrompt` (`:132`) — an interactive new-project scaffolding wizard
that writes a setup guide into the repo and copies an AI prompt to the clipboard. It is
intentional and advertised (`release.ps1:475` registers `git-rl -h (set up a project)`), which
is exactly why it collides. `git-rl` has no help token at all. Two further defects sit on those
same lines and are worth fixing independently of any convention: `-h` and `-help` are one
declaration rather than two spellings (PowerShell prefix-matches the single `[Alias('help')]`),
and the `?` alias at `:208` is unreachable because the engine intercepts `-?` and prints
`Get-Help`'s SYNTAX block before binding — so `git-rl -?` answers with a block headed
`git-release`, a name the user never typed. Six further spellings work and are documented
nowhere: `-help`, `-he`, `-s`, `-sh`, `-show`, `-ShowSetupPrompt`.

Explicitly **not** part of this conflict: `-a` on `pwsh-h` selects the fzf browser over the
printed manual, a deliberate commented choice ("TWO VIEWS, ON PURPOSE",
`components/help/menu.ps1:22-29`); `-a` on `dkr` (`components/docker/dkr.ps1:402`) means
"include stopped containers". Neither is a help spelling. `pwsh-h`'s `[switch]$all` is declared
and never read anywhere in the file — a dead legacy parameter whose only effect is falling
through to the manual, documented as such at `menu.ps1:88-89`.

---

### 4.6 · `-f` has three parse categories: force, follow, and "here comes a value"

**Severity: high. Blast radius: seven commands.**

`-f` is the flag users type most reflexively, and it is not one concept in PowerFlow.

**Force — parsed on purpose.**
`rm -f` skips the `[y/N]` confirmation (`components/files/operations.ps1:77`, long form mapped
at `:74`). `mv -f` overwrites the destination (`:328`, long form at `:310-311`, documented in
`mv`'s own help at `:350`). `srv rm <name> -f` skips the delete confirm
(`components/network/servers.ps1:177`, consumed at `:257`, and at `:205` it overwrites an
existing name on `srv add`); documented at `:165` and in the registration at `:456`.

**Force — by accidental prefix match of `-Force`.**
`pf -f` and `pf -F` bind `[switch]$Force` (`components/files/clipboard.ps1:47`) — harmless,
since the target is a switch and the typed token means what the user intended.
`git-rb <hash> -f` binds `[switch]$Force` (`components/git/rollback.ps1:175`), which suppresses
**both** the rollback confirmation (`:206`) and the "branch already exists, delete and
recreate?" prompt (`:230`), then runs `git branch -D` unattended (`:238`). Verified that `-f`,
`-fo` and a trailing `-f` all bind. The registration at `:274` says "safely" and never mentions it.

**Follow — docker's meaning.**

```powershell
# components/docker/dkr.ps1:401
if ($token -in @('-f', '--follow')) { $follow = $true; continue }
```

This is deliberate and documented: `dkr.ps1:24-27` forbids a `param()` block so that "`-a` and
`-f` stay OURS", and `Show-DkrHelp:368` documents `-f` for logs. But `$follow` is read only by
`Invoke-DkrLogs` (`:443`, `:506`) and never by `Invoke-DkrCompose` (`:469`), so **`dkr down -f`
reads as "force it down" and is a silent no-op** — the confirmation at `:245` fires anyway.
`dkr`'s skip-confirm is `-y` (`:403`, documented at `:381`), and nothing anywhere says `-f` is
not force for `down`.

**Not a flag at all — a prefix match onto a value parameter.**
`cf -f <file>` — `-f` is an unambiguous prefix of `[string]$filePath`
(`components/files/clipboard.ps1:183`, `:209`), so it consumes the following token: `cf -f
notes.md` is identical to `cf notes.md`, and bare `cf -f` dies with *"Missing an argument for
parameter 'filePath'"* — a raw PowerShell message, not a PowerFlow one.
`rn -f <file>` — `-f` prefixes `[string[]]$fileNameParts`, which is
`[Parameter(ValueFromRemainingArguments)]` (`components/files/rename.ps1:26`), so `rn -f
draft.md` is a silent no-op. Spell it out and it gets worse: `rn -force x` searches for a file
literally named `-force x`, with no error.

Refuted and dropped: `ls -f` is **not** a fourth meaning. `lsd` has no `-f` short option
(`lsd -f .` returns *"error: unexpected argument '-f' found"*) and
`components/files/listing.ps1:131` routes to `lsd` whenever it is installed; GNU's "do not
sort" reading applies only on the lsd-missing fallback at `:141`, and the comment at `:128`
lists the flags lsd honours and omits `-f` deliberately.

---

### 4.7 · "Proceed without asking me" has six spellings, and two are silently ignored

**Severity: high. Blast radius: seven commands with destructive confirmations, plus five with
no escape hatch at all.**

The concept is identical everywhere — skip the destructive confirmation — and the spelling is
not:

| Spelling | Commands | Notes |
|---|---|---|
| `-f` / `--force` | `rm` (`operations.ps1:74`, `:77`), `mv` (`:310`, `:328`) | GNU-faithful, hand-parsed; unknown long flags are reported |
| `-f` only | `srv` (`servers.ps1:177`) | `--force` is not accepted |
| `-y` / `--yes` | `dkr down` (`dkr.ps1:403`, prompt at `:245`) | forced collision: `-f` is `--follow` |
| `-Force` | `paste-file` / `pf` (`clipboard.ps1:47`, documented `:200`) | PascalCase |
| `-Force` | `git-rb` (`rollback.ps1:175`, guards `:206` and `:230`) | documented in no channel |
| `-Yes` | `powerflow-update` (`version.ps1:153`, documented `.EXAMPLE` `:150`) | whole word, affirmative rather than forceful |

What actually bites: `-f` works on five of the seven — literally on `rm`, `mv` and `srv`, and
by unambiguous prefix onto `-Force` on `pf` and `git-rb`. It fails on exactly the two that
diverge, and **both fail silently rather than erroring**, because neither has a `param()` block
that would reject an unknown name:

- `dkr down -f` sets `$follow`, which `down` never reads. The prompt appears anyway.
- `powerflow-update -f` and `powerflow-update --yes` both land in `$args`, which the function
  never reads. The prompt at `:175` appears anyway. (`-y` does work, via prefix binding to
  `-Yes`.)

**Five commands stop and ask with no way to skip:** `rmdir` (`operations.ps1:715`), `mv-t`
overwrite (`:623`), `nav delete-b` / `db` (`components/navigation/bookmarks.ps1:113`),
`powerflow-uninstall` (`components/core/recovery.ps1:114`), `pwsh-reminders`
(`components/core/version.ps1:275`, `:288`). `rmdir` is the sharp edge, because `rmdir -f x` is
not rejected — it is swallowed by the unvalidated short-flag path of section 4.1, so no
"unknown option" prints and the prompt appears regardless. `pmx` has no skip-confirm flag at
all; its `confirmation` setting rejects everything but `risk-based`
(`components/proxmox/config.ps1:118-120`), though the error text reads "currently supports only
risk-based", which sounds like an unfinished setting rather than a declared policy.

One related note, verified but weaker than it looks: `srv`'s `[switch]$f` is not the only
lowercase single-letter switch in a `param()` block — `pwsh-h` has `[switch]$a` at
`components/help/menu.ps1:42` — but two file headers already name this exact pattern as a bug
class (`components/files/listing.ps1:18`, `components/system/storage.ps1:34`), so
`servers.ps1:177` is a survivor of something the codebase has elsewhere decided against.

---

### 4.8 · `-a` binds to whichever `A…` parameter a command happens to declare

**Severity: high. Blast radius: six commands; three of them agree, which is what makes the
other three surprising.**

`-a` is the most reflexive flag a Unix user owns, and the honest finding is narrower than "six
meanings" — the split is caused by prefix matching, not by six deliberate choices.

**Three commands agree that `-a` means "all", which is consistency, not collision.**
`ls` / `la` (`components/files/listing.ps1:152`) — GNU dotfiles, not a declared flag at all, it
falls through `$gnuArgs` to lsd. `dkr` (`components/docker/dkr.ps1:402`) — include stopped
containers, hand-parsed and documented in its own help at `:380`. `team-room`
(`components/system/team-room.ps1:253`) — a prefix of the documented `[switch]$All`; verified
that the room name still resolves, because `:259-261` reassigns a non-verb `$Command` to `$Name`.

**One genuinely different meaning, deliberately chosen and documented four times.**
`pwsh-h -a` (`components/help/menu.ps1:42`) opens the interactive fzf browser — "advanced", not
"all". Documented at `menu.ps1:23-28`, `:36`, `:123`, `:175`, and in the registry synopsis at
`:263`. `-a`, `-ad` and `-all` bind distinctly to `$a`, `$advanced` and `$all`, because
PowerShell's exact-match rule outranks prefix matching.

**The actual hazard — `-a` is declared nowhere in these two, and PowerShell derives it.**
`git-a-plus -a` binds `-AmendLast` (`components/git/commit.ps1:248`); see section 4.4 for the
full path to an unabortable amend. `start-folder -a add` binds `[string]$Action`
(`components/system/startup.ps1:49`) — same mechanism, harmless, it just does what bare `add`
does.

Two claimed instances were **refuted and dropped.** `shutdown -a` does not consume the next
word: explicitly naming a `ValueFromRemainingArguments` parameter disables its remaining-args
collection, so `shutdown -a 1h 30m` fails with *"A positional parameter cannot be found that
accepts argument '30m'"*. `-a` breaks the command rather than giving it another meaning
(`components/system/shutdown.ps1:15`, `:76`). And `nav roots a` (`components/navigation/nav.ps1:112`)
is a bare positional subcommand word for `add`, not a flag; a verb abbreviation in a subcommand
namespace does not belong in a flag table.

The guidance this finding supports is narrow: do not renumber `-a` across the codebase. The
rule worth writing down is that **no destructive parameter may be reachable by a one-letter
prefix.** `git-a-plus` should either rename `-AmendLast` so `-a` is not its unique prefix, or
declare an explicit `[switch]$a` that refuses with a pointer to `git-am`.

---

### 4.9 · `-v` is accepted by nine commands, means four things, and in two of them means nothing

**Severity: high. Blast radius: nine commands, four of them siblings in one file.**

| Command | `-v` / `-verbose` / `--verbose` does |
|---|---|
| `nav` (`nav.ps1:31`, printed `:97-99`) | live trace of the resolved root key and word list. Undocumented in nav's own help block (`:72-94`) and in all four registrations (`:364-367`) |
| `rm` (`operations.ps1:74`) | **nothing.** `'verbose'='v'` sits in the LongMap; the body's only reads are `f`, `r`/`R`, `i` at `:77-79` |
| `rmdir` (`operations.ps1:689`) | **nothing.** Nor does `-p`/`--parents`; the body at `:692-731` contains no flag read at all |
| `mv` (`operations.ps1:310`, forwarded `:330`) | live but conditional: read only at `:257` inside `if ($NoClobber)`, so `mv -v a b` prints nothing extra and only `mv -nv a b` does |
| `touch` (`operations.ps1:752`, read `:755`) | live: prints each bumped file at `:773` |
| `mkdir` (`operations.ps1:811`, read `:814`) | live: with `-p`, reports "already exists" at `:840` |
| `ls` (`listing.ps1:65`) | forwarded to lsd → `--versionsort`, GNU natural version sort. Nothing to do with verbosity |
| `git-release` / `git-rl` (`release.ps1:206`) | the `[CmdletBinding()]` common parameter, accepted and inert — no `Write-Verbose` exists in the file |
| `pc-cap` (`health.ps1:780`) | not a `-v` token at all — a prefix match onto `[string]$Value`, so `pc-cap -v 85` caps the CPU |

**The confusion:** `rm`, `rmdir`, `mkdir` and `touch` sit in one file and all accept `-v`; two
of the four do nothing with it. A user who confirms `mkdir -v` works will reasonably assume
`rm -v` does too — and `rm`'s one-dash long form is actively dangerous by section 4.1.

`ls -v` is a documented deliberate choice, not a defect: `components/files/listing.ps1:11-30`
sets the rule "single dash belongs to Linux… GNU semantics, exactly", and GNU's own `ls -v` is
version-sort. It is listed for completeness. `pc-cap` is a footnote for the same reason: any
parameter beginning with V in any function behaves this way, and `pc-cap` is
`param([string]$Value)` with no `[CmdletBinding()]`.

Related but separate, and belonging with section 4.15: `rm --dir` / `-d`
(`components/files/operations.ps1:74`) is dead the same way, so GNU's "remove empty directory"
is accepted and ignored and `rm -d emptydir` still fails with "Is a directory".

---

### 4.10 · `pmx` states the strictest option contract in the repo and then breaks it three ways

**Severity: high. Blast radius: one command family, roughly forty routes.**

`pmx` is the command that most looks like it has a doctrine, which makes its exceptions the
most surprising. The shared parser is `--long`-only and case-**sensitive**:

```powershell
# components/proxmox/shared.ps1:112
if (-not $name -or $name -cnotmatch '^[a-z][a-z0-9-]*$') {
    ... Error = "invalid option '$token'; long options are lowercase and exact"
```

```powershell
# components/proxmox/shared.ps1:162-163
if ($token.StartsWith('-', [StringComparison]::Ordinal) -and $token -cne '-') {
    ... Error = "unknown option '$token'; use the documented --long-name exactly"
```

**1 · The physical-disk route inverts the contract.**

```powershell
# components/proxmox/command.ps1:23
$allowedFlags = @('-full', '-write', '-destroy')
```

The token is lowercased first (`:29`), so `-Full`, `-FULL` and `-fUlL` all work, while the
documented two-dash spellings **fail**: `pmx disk sda --full`, `--json`, `--dry-run` and
`capacity-test --destroy` each answer *"Unknown physical-disk option"*. None of the six global
switches function on this route. A one-dash word arms the most destructive operation in `pmx`
(`components/proxmox/command.ps1:63`, `capacity-test -Destroy`), and every help surface spells
the trio **PascalCase** — `[-Full]` at `components/proxmox/help.ps1:363`, `[-Write]` at `:261`,
`:283`, `:284`, `:365`, `-Destroy` at `:262`, `:294`, `:297`, `:366` — plus runtime hints at
`components/proxmox/physical-disks.ps1:151`, `:173` and `components/proxmox/evidence.ps1:71`.
The router lowercases, so PascalCase is accepted; it is a documentation-casing wrinkle rather
than a fourth parser, but it teaches PascalCase single-dash inside a command whose stated rule
is lowercase double-dash. No comment anywhere defends the spelling, and
`git log -S allowedFlags` places it in v3.16.2, before the shared parser's doctrine existed.
The function's own name — `Invoke-PmxLegacyDiskCommand` — marks it as the preserved pre-parser
surface.

**2 · The network routes add case-sensitive single-character flags.**

```powershell
# components/proxmox/network-read.ps1:20-24
$mapped += switch -CaseSensitive ($token) { '-t' { '--table' } '-j' { '--json' } '-4' { '--ipv4' } '-6' { '--ipv6' } default { $token } }
```

`ConvertFrom-PmxNetworkShortOptions` is the only pre-map in `components/proxmox/`, and its one
caller is `network-read.ps1:42`. Case-**sensitive**, so `pmx vm net <vm> -J` errors while
`pmx disk sda -FULL` works. (`-4`/`-6` are additionally refused on the adapters and stats views
at `:51-54`; that part is deliberate and documented.)

**3 · Help tokens use a third case policy.** `-h`, `-H` and `/?` are accepted anywhere,
case-**in**sensitively (`components/proxmox/command.ps1:171`, `:184`), because the router
intercepts them before the parser's single-dash rejection can fire. Neither `-h` nor `/?` is
written down anywhere — not in `pmx help`, not in the registration at `command.ps1:259`, not in
any `.md`. `docs/feature-pmx.md:746` documents `--help` only.

Net effect, all verified by running the parsers: `pmx vm list -j` errors, `pmx vm list -H`
prints help, `pmx vm net <vm> -j` works, `pmx vm net <vm> -J` errors, `pmx disk sda -FULL`
works, `pmx disk sda --full` errors. Nothing on the surface signals which dialect a route
speaks.

Not counted, though it looks like a fourth grammar: `pmx vm clone --full`
(`components/proxmox/vm-change.ps1:123`) is accepted and dead, but the comment at `:120-122`
states this is deliberate — accepted so existing commands do not break, never read because
`Full = $true` is hardcoded at `:215`, and "gone from the help text rather than advertised as a
choice the user does not have". Undocumented back-compat, not a grammar the user is taught.

A project rule worth citing when this is decided: `CHANGELOG.md:1579` states it outright — **"The rule now: single dash belongs to Linux; long dash
belongs to PowerFlow."** — decided for `ls`. Under
that rule `pmx`'s `-full` / `-Write` / `-Destroy` are the outliers and the network
`-t/-j/-4/-6` are the conforming ones.

---

### 4.11 · `ls` accepts five dash styles in one twenty-line loop, and `-depth=N` is a silent gap

**Severity: high. Blast radius: `ls`, `la`, `ll` — the most-typed commands in the shell.**

The whole flag surface is one `switch -Regex` at `components/files/listing.ps1:49-68`, ordered
by fallthrough, where GNU shorts, one-dash PowerFlow words and two-dash PowerFlow words share a
namespace. The file states an absolute rule at line 11 and then breaks it three times in the
same function:

```powershell
'^--tree$'  { $pfTree = $true }
'^-{1,2}recurse$' { $pfTree = $true }
'^--depth$'       { $i++; $pfDepth = [int]$args[$i] }
'^--depth='       { $pfDepth = [int]($a -split '=', 2)[1] }
'^-depth$'        { $i++; $pfDepth = [int]$args[$i] }
default {
    $bare = $a -replace '^-{1,2}', ''
    if ($a.StartsWith('-') -and $namedRoots -contains $bare.ToLowerInvariant()) {
        $pfRoot = $bare.ToLowerInvariant()
    }
    else { $gnuArgs += $a }           # everything else is GNU's
}
```

Verified by execution:

- Tree view is `--tree` **or** `-recurse` **or** `--recurse`, all case-insensitive.
- `-recurse` sets **tree view, not recursion.** lsd's real `-R` recursion is a separate
  passthrough: `ls -recurse` gives tree=True with no flag to lsd; `ls -R` gives tree=False and
  hands lsd `-R`. With lsd absent they also diverge — `-recurse` warns and returns with no
  listing (`:108-111`) while `-R` degrades to native `ls` / `Get-ChildItem` (`:131-148`).
- Depth has three spellings and a silent fourth gap. `--depth N`, `--depth=N` and `-depth N`
  all work; **`-depth=3` matches nothing**, falls to the default branch, is not a named root,
  and is forwarded to lsd as a literal string, leaving depth at its default. `--depth=` is the
  only `=value` acceptance anywhere under `components/`, and its single-dash counterpart's
  absence is undocumented.
- Roots are dash-count agnostic and case-insensitive: `-docs` and `--docs` are identical.
- Everything unmatched is forwarded verbatim with GNU semantics, so `-l -a -A -h -d -R -t -S -r
  -1 -i` and bundles like `-la` mean what they mean on Linux.

**The help entry teaches each spelling exactly once, in the wrong half.**

```powershell
# components/files/listing.ps1:164
-Synopsis 'pretty listing; GNU flags, --tree/--depth, and -<root> starting points' -Example 'ls -la · ls -recurse -depth 2 · ls -srv complete'
# components/files/listing.ps1:166
-Synopsis 'ls -lh: permissions, owner, size, date - composes with --tree/--depth' -Example 'll · ll -recurse -depth 2'
```

The synopsis names only the two-dash forms; the example types only the one-dash forms.
`components/help/menu.ps1:198-201` (detail view) and `:227-228` (fzf preview) render the two
adjacently, so a user sees both conventions in one entry with nothing saying they are the same
flag. `COMPONENTS.md:165` documents only the one-dash forms, so the two manuals disagree about
which spelling is canonical. `--recurse` and `--depth=N` appear in no doc, changelog, comment or
registration at all.

Partly mitigating, and it matters for section 5: `listing.ps1:53-55` explicitly defends
`-recurse` as "the spelling a PowerShell user already knows" and explains why `-r`/`-R` are left
to GNU. That one break is a documented decision. `-depth`, the missing `-depth=`, and `-<root>`
carry no such explanation.

---

### 4.12 · `nav -<name>` and `ls -<name>` are the same token resolved by two different resolvers

**Severity: high. Blast radius: two commands, six documentation sites, every user anchor.**

`nav` accepts three kinds of starting point; `ls` / `la` / `ll` accept one.

`nav.ps1:36` calls `Resolve-PFRootAlias`, which strips leading dashes and then tries canonical
named roots (`components/navigation/roots.ps1:288`), the eleven aliases in `Get-PFRootAliases`
(`:289-293`; table at `:213-227` — `pics pic docs doc dl down vids vid desk conf cfg`), then
every user anchor (`:296`).

`ls` builds its accept-list from canonical keys only, and never calls the resolver:

```powershell
# components/files/listing.ps1:47
try { $namedRoots = @((Get-PFNamedRoots).Keys) } catch { }
# components/files/listing.ps1:62
if ($a.StartsWith('-') -and $namedRoots -contains $bare.ToLowerInvariant()) {
```

`Resolve-PFRootAlias`, `Get-PFRootAliases` and `Get-PFUserAnchors` are referenced nowhere under
`components/files/`. So every alias and every anchor sets `pfRoot=''` and is forwarded to lsd,
which bundles it as unknown shorts. Measured against the installed lsd:

```
ls -downloads complete   ->  works
ls -pics screenshots     ->  error: unexpected argument '-p' found
ls -docs x               ->  '-o'    ls -vids x -> '-s'    ls -desk x -> '-e'
ls -<anchor> x           ->  e.g. -mon -> error: unexpected argument '-m' found
ll -dl -recurse -depth 2 ->  NO error, and that is worse
```

The `-dl` case is the sharp one because it fails *quietly*: `-d` (directory-only) and `-l` are
both real lsd shorts, so the documented example silently tree-lists the **current** directory,
directories-only, instead of long-listing Downloads two deep.

The anchor case is structurally guaranteed to fail: `Add-PFAnchor`
(`components/navigation/roots.ps1:445`) refuses any anchor name colliding with a named root or
alias, so no anchor can ever be in `ls`'s set.

**Six places promise otherwise**, and one of them prints at the exact moment a user creates an
anchor:

```powershell
# components/navigation/roots.ps1:457
Write-Host "   Use it:  nav -$key <destination>   ·   ls -$key <destination>" -ForegroundColor DarkGray
# components/navigation/roots.ps1:488
Write-Host '⚓ ANCHORS — starting points for  nav -<name> <destination>  and  ls -<name>' -ForegroundColor Cyan
# components/navigation/nav.ps1:117
Write-Host '🎯 Named starting points   (nav -<name> · ls -<name>)' -ForegroundColor Cyan
```

plus `components/navigation/roots.ps1:190` ("the shared starting points behind `nav -<root>` and
`ls -<root>`"), `roots.ps1:197` (the worked example `ll -dl -recurse -depth 2`, where `dl` is an
alias per `:219`), `COMPONENTS.md:165` ("same resolver as `nav`", using the word "anchor", which
is precisely the case that fails), and `CHANGELOG.md:266`.

**This is drift, not design, and the tree says so.** The invariant is written down:

```powershell
# components/navigation/roots.ps1:209-210
# `nav` and `ls` MUST both resolve through Resolve-PFRootedDirectory, so the two can
# never disagree about which roots exist or how a name is matched.
```

`components/files/listing.ps1:70-71` repeats the same belief. `Resolve-PFRootedDirectory`
(`roots.ps1:347`, anchor-aware at `:354`) already resolves aliases and anchors; only `ls`'s
canonical-only gate blocks them.

The failure modes are also asymmetric in kind. `nav` rejects an unknown `-token` by name and
prints the available roots (`nav.ps1:38-43`); `ls` forwards it without comment, so **`nav` fails
as PowerFlow while `ls` fails as lsd** — the error message names lsd's shorts, not starting
points.

Fix scope for whoever takes this: switching `listing.ps1:62` to `Resolve-PFRootAlias` is
necessary but not sufficient, because the bare form at `:76` still indexes `Get-PFNamedRoots`
only, so `ls -<anchor>` with no needle would resolve to null.

---

### 4.13 · The same category of flag is declared lowercase in one command and PascalCase in the next

**Severity: high. Blast radius: the whole generated manual — this is the owner's original
complaint, mechanically located.**

PowerFlow's generated help prints optional mode-switch flags in two capitalisations, and a user
reading one `pwsh-h` screen sees both.

Lowercase one-dash words: `pc-whoami -ram · -power · -crashes · -bios`
(`components/system/health.ps1:871`, declared lowercase at `:83-89`, repeated in
`COMPONENTS.md:184` with `-export`, `-days N`, `-min N`); `pwsh-font -status`
(`components/system/fonts.ps1:68`, declared `:29`); `set-path (-system needs admin)`
(`components/system/path.ps1:42`).

PascalCase one-dash words: `git-a-plus with modes: -Quick, -DryRun, -AmendLast`
(`components/git/commit.ps1:459`, declared `:246-248`), plus undisplayed-but-typed `-Force` and
`-Path` (`components/files/clipboard.ps1:47-48`), `-Yes` (`components/core/version.ps1:153`),
`-All` (`components/system/team-room.ps1:253`), `-Overview` / `-Measure`
(`components/system/apps.ps1:272-273`), `-Force` (`components/git/rollback.ps1:175`).

**The sharpest single case is a disagreement inside one command.** `set-path` declares
`[switch]$System` at `components/system/path.ps1:14` and its own registered synopsis advertises
`-system` at `:42`.

Scope limits that matter, because they keep this from being bigger than it is. PowerShell binds
parameter names case-insensitively, so every one of these flags works whichever casing is typed:
**the inconsistency is in what the help prints, not in what the shell accepts.** It does not
extend to the camelCase parameter names (`-filePath`, `-branchName`, `-commitHash`, `-index`,
`-keys`), which are positional in practice and appear in no help string, synopsis, example or
`.md` — a contributor style matter only. It does not extend to the brothers' GNU flags
(`dirsize -sh`, `listports -tulpn`, `systemlogs -u … -e`, `lastlines -f`), which are the wrapped
tool's own flags, preserved on purpose and documented as such at
`components/shell/brothers.ps1:6-7` and `:16-17`. And it does not extend to `ls -recurse` /
`--recurse` / `-Recurse` (`components/files/listing.ps1:52-56`) or the brothers' `-lesson` /
`--lesson` (`brothers.ps1:33`), both of which deliberately accept every plausible spelling — a
documented superset, the opposite of an unpredictable flag.

The narrow rule this finding supports, if the owner wants one cheap fix before deciding
anything larger: a flag that will be printed in a `Register-PFCommand` synopsis or example
should be *declared* lowercase, so the declaration and the advertised spelling agree.

---

### 4.14 · `pc-whoami` intercepts one GNU spelling and traps three as program names

**Severity: high. Blast radius: one command, but it is the diagnostic entry point.**

`pc-whoami` has seven single-dash word switches (`components/system/health.ps1:83-89`), each
also reachable by prefix. A `param()` block cannot accept a double-dash spelling, so every
`--flag` binds to `[Parameter(Position = 0)][string]$name` at `:81` as a plain string. The
command then handles that one invalid-token case three different ways, none of which mentions
the dash count:

- `--ram` is intercepted at `:95` with a deprecation notice. Per the comment at `:92-94` this
  exists because `--ram` was the literal flag name in v3.14.0 and is retired — not because
  double dashes are supported.
- `--power`, `--crashes`, `--bios` and `--export` fall through `:107` (a bare name flips
  `$ram = $true`), miss `Get-RamLevel` at `:126`, and reach `Show-RamProcesses` at `:128`, which
  prints *"Nothing called '--power' is running."* (`:542`). **The flag is reported as a missing
  program.**
- `--days 3` and `--min 2` put the value in `$program` and hit the two-word guard at `:111`:
  *"Program names with a space need quoting: pc-whoami -ram \"--days 3\""*.

One flag out of seven teaches the user that double-dash spellings are understood here; the rest
answer as if the command were fine and the machine were not. That the code special-cases exactly
one of them proves the author already knew this failure mode.

The cross-file inconsistency is what makes it a uniformity finding rather than a missing guard:
`components/files/operations.ps1:301-302` calls `--detailed` "the correct spelling" and
`Split-GnuArgs` really does honour `--recursive`, so **`rm --recursive` works while
`pc-whoami --power` reports a missing program.**

Adjacent and verified but a separate defect: the registration at `health.ps1:871` shows
`-ram`/`-power`/`-crashes`/`-bios` in its example and omits `-export`, though the
`.DESCRIPTION` at `:61` and the runtime hint at `:378` both document it.

---

### 4.15 · Coreutils flags are accepted and then never read

**Severity: medium. Blast radius: `rm`, `mv`, `rmdir`, plus `cat` and `cp` on Windows.**

An accepted-and-ignored flag is the least honest outcome available: worse than an error, because
the user believes it worked.

Two are silently **wrong** behaviour:

- `rm --dir` / `-d` (`components/files/operations.ps1:74`) — mapped `'dir'='d'`, never read.
  GNU removes an empty directory; here the flag is ignored and the no-recurse guard at `:139`
  then prints *"rm: cannot remove 'x': Is a directory"* (`:143`). The user supplied GNU's
  correct flag for exactly this job and was told the job is impossible.
- `rmdir --parents` / `-p` (`components/files/operations.ps1:689`) — the only silently-wrong
  one. `rmdir -p a/b/c` removes the leaf, leaves `a` and `a/b`, and reports success. The file's
  only `ContainsKey('p')` is `mkdir`'s at `:813`.

Two are ignored but harmless and should not be filed with the above: `rm --verbose` and
`rmdir --verbose` are never read, but both commands already print every deletion (`:175`,
`:724`); `mv --interactive` / `-i` (`:310`) is never read, but `mv` already prompts on overwrite
when neither `-f` nor `-n` is given (`:260-266`).

Three are honoured but documented nowhere: `rm -i` (read `:79`, honoured `:85` — "`-i` beats
`-f`, exactly as in GNU"), `mkdir -v` (read `:814`, used `:840-841`), `touch -v` (read `:755`,
used `:773`).

**Inside one file, `mkdir` gets this right and `rmdir` does not.** `mkdir` (`:809-861`) reads
both `-p` and `-v` and honours GNU faithfully; `rmdir` maps the same `-p` and drops it.

`--` (end-of-flags, `operations.ps1:51`) reaches all five commands. It is the only way to delete
a file genuinely named `-rf`, it is documented solely in the helper's internal comment help
(`:34-36`), and it appears in no registration and nowhere under `docs/`.

PowerShell hashtable literals are case-insensitive, which has two consequences nobody chose:
`-I` is silently the same flag as `-i` (GNU treats them differently), and the
`-or $parsed.Flags.ContainsKey('R')` at `:78` is dead code.

**The stock PowerShell aliases give a second grammar on Windows.** `cat` → `Get-Content`
(`components/files/listing.ps1:159`) and `cp` → `Copy-Item` (`:161`) are re-registered as
PowerFlow commands (`:168-169`) with the synopsis "(the GNU cat on Linux)", while
`platform/linux/bindings.ps1` strips them so the coreutil wins there. Measured on Windows:
`cat -n` errors; `cp -a`, `cp -u` and `cp -n` error; `cp -f` errors as **ambiguous** (`-Force` vs
`-Filter`) so it never reaches `-Force`; `cp -v` **succeeds** by prefix-binding the common
`-Verbose`; `cp -r` works by prefix-matching `-Recurse`; and `cp -i src dst` is the worst
outcome of all — it exits clean, prints nothing, and copies nothing, because `-i` binds
`-Include` to the source and leaves the destination as a positional `-Path` with no
`-Destination`.

CLAUDE.md's own rule is that PowerFlow must not shadow coreutils on Linux, and
`platform/linux/bindings.ps1` enforces it — which means the **Windows** implementations are what
teach users their habits, and those habits then break in both directions.

---

### 4.16 · Flags the manual promises and the code lacks, and flags the code has and the manual omits

**Severity: medium. Blast radius: nine commands. The pattern matters more than any instance.**

`Register-PFCommand`'s schema (`components/help/registry.ps1:76-83`) has **no field for a
command's arguments at all.** Every flag PowerFlow has is documented only as hand-written prose
inside a `-Synopsis`, an `-Example`, or a `Write-Host` hint — which is why the two sides drift,
and why `pwsh-h` cannot be trusted as the source of truth for what a command accepts.

**A released feature whose flag is silently discarded.** `docs/features.md:25` still sells
"One-command releases - Update version and release with `git-a -vr` for instant GitHub
releases". `components/git/commit.ps1:11` is `function git-a {` with no `param()` block, and it
never reads `$args`, `$MyInvocation` or `$PSBoundParameters` anywhere in `:11-243`.
`-VersionRelease` exists in no `.ps1` file. Verified with `$ErrorActionPreference='Stop'`: no
error, the ordinary interactive add-commit-push runs. The user sees no version bump and no
release and has no error to search for. Releases are owned by `git-rl`
(`components/git/release.ps1:472`), consistent with CLAUDE.md; `docs/log/2026/May/21 Wed/log-3.md`
shows `README.md` was scrubbed of `git-a -vr` and `features.md` was missed.

**Help text describing behaviour that does not exist**, each promise written in the vocabulary
of a *different* command in this repo that does implement it:

- `copy-file` — `components/files/clipboard.ps1:224` promises "(fzf picker)". The body
  (`:180-205`) is `Test-Path` / `Resolve-Path` / `Copy-ToClipboard` / `Write-Host`; line `:224`
  is the only occurrence of "fzf" in the file. `$filePath` is `Mandatory` at `:182`, so bare
  `copy-file` shows PowerShell's raw "Supply values for the following parameters:" prompt. The
  phrase is lifted from `components/files/rename.ps1:210`, whose identical synopsis *is* honoured
  by a real picker at `rename.ps1:35-55`. The repo already contradicts itself:
  `clipboard.ps1:57` tells the user "Use 'cf <filename>' to copy a file first".
- `cf` — the advertised alias produces a *different* failure. `clipboard.ps1:208-211` forwards
  `''`, so `copy-file`'s binder rejects it before the prompt logic runs: *"Cannot bind argument
  to parameter 'filePath' because it is an empty string."* One synopsis, two non-picker outcomes.
- `here` — `components/navigation/directory.ps1:238` promises "with quick actions". The body
  (`:21-44`) is nine `Write-Host` lines and four `Test-Path` project sniffs. The file contains no
  `Read-Host`, no prompt, no menu.
- `nav list` — `components/navigation/nav.ps1:88` prints "(Enter go · ctrl-d delete)".
  `Show-BookmarkList` (`components/navigation/bookmarks.ps1:160`) is `while ($true) { Read-Host }`
  with no fzf; delete is the typed token `d <name>` (regex at `:212`, advertised on screen at
  `:183`). Ctrl-D at a `Read-Host` prompt does nothing, and "Enter go" is wrong in kind too —
  navigation requires typing an index first (`:193`). This vocabulary belongs to `srv`, where it
  is real: `components/network/servers.ps1:416` passes `--expect=ctrl-d,ctrl-r` to fzf and `:429`
  handles it, with the design explained at `:396-398`.
- `open-wsl-simple` — the synopsis "open WSL without Terminal profiles" (`windows-only/wsl.ps1:99`)
  contradicts its own body (`:82-85`), whose only parameter is `-ProfileName = "Ubuntu-20.04"`
  and which runs `wt -w 0 nt -p $ProfileName`. It means "without profile *discovery*" — the
  contrast with `open-ubuntu`, which parses `settings.json` — but it reads as denying the
  parameter it has.

**Flags that work and nothing mentions:**

- `git-rb -Force` (`components/git/rollback.ps1:175`) skips both confirmations (`:206`, `:230`)
  and force-deletes an existing `rollback-XXX` branch, while its registration at `:274` says
  "safely". No comment help, no README mention (`README.md:274`, `:478` list `git-rb` without
  it), no `COMPONENTS.md` entry. **"Safely" in the manual and a hidden `-Force` in the code is
  the worst possible split:** the flag that matters most for data loss is the one a user can only
  find by reading the source. The suggested minimum is
  `-Synopsis 'create a rollback branch from any commit (-Force skips both prompts)'` plus an
  `-Example`.
- `gh-l -Token` (`components/github/browser.ps1:114`) puts a GitHub PAT in plaintext on the
  command line and overrides `$env:GITHUB_TOKEN` and the credential store (`:125-128`). Absent
  from README, `docs/`, and the registration at `:642`. Sibling `gh-l-org` (`:395-398`) accepts
  no token at all, so the two disagree on whether a token can be supplied as an argument.
- `disk-big -Path` (`components/system/apps.ps1:348`) is mentioned only by an in-code hint at
  `:404` — not in the `.EXAMPLE` block (`:338-342`), not in the registration (`:571`).
- `dkr --follow` / `--all` / `--yes` / `-h` / `--help` (`components/docker/dkr.ps1:401-404`) all
  work and appear in no help text. `Show-DkrHelp` documents `-f` (`:368`), `--show-native`
  (`:379`), `-a` (`:380`) and `-y` (`:381`) — short spellings only — and none of the eight
  registrations at `:541-556` mention any flag except `-f` on `dkr logs`. The gap matters most
  on `dkr down`, registered at `:555` as "Take a compose stack down; confirms, keeps named
  volumes" without naming the `-y` that skips that confirmation — while `srv rm` at
  `servers.ps1:456` already documents its confirm-skip flag exactly that way.
- `installed-apps -Measure` (`components/system/apps.ps1:273`) is honoured at `:286` and `:312`
  and changes real behaviour (walks folder sizes instead of trusting the registry, and is slow).
  Missing from all four `.EXAMPLE` blocks (`:259-266`), the registration (`:570`), and
  `README.md:609-611`; mentioned only in the source comment at `:326`.
- `send-keys -keys` (`components/terminal/tabs.ps1:18`), `open-nt -Shell` (`:23`) and
  `close-t -index` (`:55`) are value parameters whose registrations (`:73`, `:68`, `:72`) carry
  no `-Example`, so `pwsh-h` renders them as commands that take nothing — while `open-t` (`:71`)
  with the identical shape does have one.

Deliberate choices in this space that must **not** be filed as drift: `pmx vm clone --full`
(`components/proxmox/vm-change.ps1:120-122`, inert and hidden by explicit written decision) and
`pwsh-h -all` (`components/help/menu.ps1:88`, "the legacy `-all`", intentionally landing on the
manual).

---

### 4.17 · `pmx help` advertises short options that five routes out of forty accept

**Severity: medium. Blast radius: one command's global help footer.**

```powershell
# components/proxmox/help.ps1:416
Write-Host '  Educational options: --explain · --dry-run · --show-native · --json/-j · --table/-t' -ForegroundColor DarkGray
```

That line sits in the no-topic overview, immediately after the loop listing all thirty-eight
commands (`:406-413`). It is the one place in `pmx` that presents `-j` / `-t` as generally
available. They exist only on the five `pmx vm network` views, via the one pre-map in section
4.10; every other route parses with `Get-PmxGlobalSwitchMap`
(`components/proxmox/shared.ps1:73-81`), which registers long `json` / `table` only, so `-j`
falls to the catch-all at `shared.ps1:162-163` and returns *"unknown option '-j'; use the
documented --long-name exactly"*.

**A user who reads `pmx help`, then types `pmx vm list -j`, is told to use the documented long
name — by the same program that just documented the short one.** Verified per route for
`pmx vm list` (`components/proxmox/vm-read.ps1:163` → `:134`), `pmx node status`
(`components/proxmox/host.ps1:131` → `:125`), `pmx storage list` (`:162` → `:125`),
`pmx discover` (`:197` → `:125`), `pmx config show` (`components/proxmox/config.ps1:389`) and
`pmx snapshot list` (`components/proxmox/snapshots.ps1:42`).

Four commands reject the documented `--json` outright, before any parser runs:
`components/proxmox/command.ps1:228` (`pmx disks takes no arguments.`), `:232` (`pools`), `:236`
(`guests`), `:246` (`updates`). Four more accept `--json` / `--table` and silently ignore them,
because `Invoke-PmxVmCpuSet` (`components/proxmox/vm-change.ps1:298`), `Invoke-PmxVmMemorySet`
(`:346`) and `Invoke-PmxVmLifecycleChange` (`:395`) never call `Get-PmxOutputMode` — so
`pmx vm start <name> --json` prints the human confirmation plan.

The drift is confined to that footer: every per-topic syntax line is accurate — long-only for
non-network topics (`help.ps1:28`, `:53`, `:213`, `:315`), `[--table|-t|--json|-j]` for network
topics (`:86`, `:96`, `:105`, `:115`, `:123`). Even the overview's own network entries
(`:233-235`) write long-only, which means `help.ps1` contradicts itself internally. Nothing in
the code marks the network-only scope as intentional, and
`docs/plan/proxmox/pmx-full-vm-view-and-output-overrides.md:34` and `:136` specify `-t` / `-j`
as exact aliases across **every** PMX read — so the footer documents an unfinished plan rather
than a mistake.

---

### 4.18 · Inside `nav` alone, one action has four spellings and a verb does not carry between siblings

**Severity: medium. Blast radius: the `nav` family; `srv` shows the same pattern.**

```powershell
# components/navigation/nav.ps1:33-34
# --start-repo is accepted because that is what the owner first reached for.
if ($token -in @('--anchor', '-anchor', '--start-repo')) { $anchorVerb = $true; continue }
```

Three spellings of one verb on one line; only `--anchor` is ever shown (`nav.ps1:367`,
`roots.ps1:428-429`, `:503`, `README.md:444`). The comment makes `--start-repo` deliberate
muscle-memory forgiveness rather than an oversight — but "repo" is git/GitHub vocabulary
(`components/github/browser.ps1:643`) and appears nowhere in the navigation or anchor surface;
an anchor is never called a repo where a user can see it. `-anchor` has no justification
anywhere.

**The load-bearing failure is a verb list that differs 52 lines apart inside the same
function.** `components/navigation/nav.ps1:61` accepts `rm`, `remove`, `d`, `delete` for
anchors; `:113` accepts only `rm`, `remove`, `d` for roots. So `nav anchors delete x` deletes,
and `nav roots delete /srv` falls into the `default` branch of the switch (`:115-126`) and
prints the roots listing — **the delete is discarded behind a success-looking screen.** Both
help texts advertise only `rm` (`roots.ps1:167`, `:504`).

Four spellings for "bookmark this": `create-b` and `cb` (`nav.ps1:103`), REPL `c <name>`
(`components/navigation/bookmarks.ps1:209`), and `nav b .` (`nav.ps1:135`). Same for delete
(`delete-b` / `db` at `:104`, REPL `d <name>` at `bookmarks.ps1:213`) and rename (`rename-b` /
`rb` at `:105`, REPL `r <old> <new>` at `bookmarks.ps1:215` — whose `^r\s+(\S+)\s+(\S+)$` makes
a bookmark name containing spaces unrenamable, and spaced names are creatable via
`nav cb "my name"`). One-letter forms follow no single convention: `roots` uses `a` and `d`
(`:112-113`), the bookmark router uses two-letter `cb`/`db`/`rb` but one-letter `l` for list
(`:103-106`), and the REPL uses `c`/`d`/`r`.

Dash count is not uniform product-wide, and both halves are intentional. For root tokens it is
meaningless by design — `roots.ps1:285` does `"$Token".TrimStart('-')`, stripping any number of
dashes, while `components/files/listing.ps1:61` caps at two, so `---pics` resolves in `nav` and
not in `ls`. Elsewhere it is strict: `--show-native` is matched by exact equality at
`components/docker/dkr.ps1:400` and `components/system/storage.ps1:259`, and `pmx` requires a
literal `--` at `components/proxmox/shared.ps1:106`.

The same pattern sits outside `nav`. `srv` accepts `list` / `ls` (`servers.ps1:324`),
`rm` / `remove` (`:251`), and `help` / `-h` / `--help` / `/?` (`:306`). All are reserved as
forbidden server names at `:190` and `:287` — the same "reserved therefore intended" evidence
the comment at `:300-305` used to justify adding `srv help` — yet `ls`, `remove`, `-h`,
`--help` and `/?` appear in neither the `.DESCRIPTION` (`:155-171`), the `srv help` block
(`:306-320`), nor any of the six registrations (`:453-458`).

Dropped after refutation: the `shutdown cancel` / `s c` pair. Both restrictions are stated
deliberately in comments ("Cancel: ONLY …") and the pairing is documented to users at
`components/system/shutdown.ps1:66` and in the registration synopsis.

---

### 4.19 · Bare subcommand words collide across routers, and two of them shadow a documented flag

**Severity: medium. Blast radius: `nav`, `pmx`, `pwsh-config`, and eight `list` implementations.**

Subcommands are the part of PowerFlow with no dashes at all, so they look like the safe,
uniform layer. They are not.

**`host` means two opposite things under two commands both called config.**
`pmx config set host <value>` (`components/proxmox/config.ps1:43`) sets which saved `srv` alias
to tunnel through — a *remote* endpoint, and the validator's own error says so:
`'host must be a saved srv alias using lowercase letters, digits, dashes, or underscores'`
(`:93`). `pwsh-config host` (`components/system/sysconfig.ps1:27`) is an abbreviation for
`hostname` and changes *this machine's* name. Note the asymmetry too: in `pwsh-config` `host`
is a documented shorthand for the canonical key; in `pmx` it is the canonical key.

**`list` means "print and return" in eight commands and "capture the terminal" in one.**
`nav list` (`components/navigation/nav.ps1:106`) calls `Show-BookmarkList`, which is
`while ($true) { Read-Host }` (`components/navigation/bookmarks.ps1:186`). Every other `list`
prints and returns: `pmx vm list` (`components/proxmox/command.ps1:116`), `pmx snapshot list`
(`:144`), `pmx storage list` (`:207`), `pmx disk list` (`:217`), `pmx vm net list`
(`components/proxmox/network-read.ps1:279`), `srv list` (`components/network/servers.ps1:324`),
`start-folder list` (`components/system/startup.ps1:81`), `team-room list`
(`components/system/team-room.ps1:261`). `start-folder` makes the convention explicit rather
than incidental — a bare `start-folder` *is* the picker and `list` is the documented way to opt
out: "Print mode: asked for explicitly, piped, or no fzf. Never launches a picker."
(`startup.ps1:79-81`). So `list` already means non-interactive by stated intent, and `nav` is
the sole violator.

**`pmx disk` splits the virtual/physical boundary inside one word.** `pmx disk list`
(`components/proxmox/command.ps1:217-218`) and `pmx disk grow` (`:222`) address a VM's *virtual*
disks; every other tail, including a bare `pmx disk`, falls through to the *physical* device
router at `:225`. `pmx disks` (`:227`) is the physical inventory. The reader cannot tell from
`disk` alone which subsystem they are addressing.

**Two bare words in `nav` shadow documented flags of the same name and win.**
`components/navigation/nav.ps1:194` (`home`), `:195` (`code`), `:206` (`projects`) and `:193`
(`~`) use hardcoded `Join-Path` targets and are matched **after** the `-<start>` anchor is
resolved (`:165-185`) but **before** the search runs. Verified by running nav's parser:
`nav -srv anything-else` searches `/srv`, but `nav -srv home`, `nav -srv ~`, `nav -srv code` and
`nav -srv projects` all ignore `-srv`. `-home` and `-code` are real root flags
(`components/navigation/roots.ps1:244-245`) advertised at `nav.ps1:83`, `:117` and
`roots.ps1:494`, making `nav ~` / `nav home` / `nav -home` three spellings of one destination.
None of the bare words appears in any help text or doc. **The user names a starting point, the
bare word wins, and they land in `~/Code` with a coloured success message and no hint the flag
was dropped.**

Verified and excluded: `pmx vm cpu set` (the parse layer at
`components/proxmox/vm-change.ps1:287-290` already accepts `<vm> <value>` positionally, and the
choice is documented at `command.ps1:129-131`); the three uses of `.` (all mean "the current
directory", with the `code .` convention cited by name at `nav.ps1:133` and `roots.ps1:433`);
`node`; `nic`/`ip` vs `net`; and `srv <name> info` (a positional-order fact documented at
`servers.ps1:311` and `:454`, matched by `pmx disk <device> <action>`). `team-room list` is also
excluded — the comment at `:259-260` shows `list` is deliberately in the verb whitelist.

---

### 4.20 · The confirmation prompt has six labels and four accepted-input grammars

**Severity: low — every divergence currently fails safe. Blast radius: fifteen prompts across
nine commands.**

Prompt labels in use: `[y/N]`, `(y/n)`, `(y/N)`, `Confirm (y/n)`, `(yes/n)`,
`(y/n/r=…)`. Because PowerShell's comparison operators are case-insensitive by default,
`-ne 'y'`, `-notin @('y','Y')` and `-eq 'y' -or -eq 'Y'` are one behaviour spelled three ways —
so capitalising an answer never changes its meaning anywhere in the tree. The real divergence is
the word `yes`.

**A — `y` only; `yes` cancels.** The majority. `rm` (prompts
`components/files/operations.ps1:154`, `:162`; gate `:165`), `cp` overwrite (`:261-262`),
`rmdir` (`:715-716`), `mv-t` (`:622-623`), `nav db` / `delete-b`
(`components/navigation/bookmarks.ps1:113`, `:115`), `powerflow-update`
(`components/core/version.ps1:175`), `powerflow-uninstall`'s *second* prompt
(`components/core/recovery.ps1:145-146`), `git-cmt`'s init offer
(`components/git/commit.ps1:19-20`), `git remote` replace
(`components/git/remote.ps1:180-181`).

**B — `y` or `yes`, behind the identical `[y/N]` label.** `dkr down`
(`components/docker/dkr.ps1:248-249`, `-notmatch '^(y|yes)$'`) and `nav`'s folder creation
(`components/navigation/roots.ps1:586-587`, the same gate).

**C — any `y`-prefixed word, so `yolo` is a yes.** `git-rl`'s project-folder check
(`components/git/release.ps1:165`, `-match '^y'`).

**D — the whole word `yes` only; `y` cancels.** `powerflow-uninstall`
(`components/core/recovery.ps1:114-115`, `-ne 'yes'`). Its own second prompt is grammar A, so
**one command asks two different ways**, and a user who habitually types `y` cancels an
uninstall.

Plus the only three-way prompts, spelled differently from each other:
`components/files/clipboard.ps1:90` (`(y/n/r=rename manually)`) and `:138`
(`(y/n/r=rename new file)`).

Two prompts render the identical string `[y/N]` and disagree on whether `yes` is a yes. No
comment anywhere in the tree justifies any divergence, and there is no shared confirmation
helper for components to call.

Refuted and dropped: the claim that `Y` cancels on `paste-file`. `-eq 'y'`
(`components/files/clipboard.ps1:100`) is case-insensitive. Also dropped:
`pmx capacity-test -destroy` is an arming/mode flag beside `-full`/`-write`, not a confirmation
skip.

---

### 4.21 · `mv` prints its own flag two ways in one session

**Severity: low. Blast radius: one flag, two hints.**

- `components/files/operations.ps1:355` — the bare-`mv` help block prints the long form:
  `mv <filename> --detailed   Show the search process`
- `components/files/operations.ps1:576` — the no-matches hint prints the short form:
  `💡 Use 'mv $fileName -detailed' for detailed search output`

Both spellings genuinely work (`:306`), and accepting both is authorised on purpose by the
comment at `:299-302` quoted in section 4.1. The only fault is that the same comment calls
`--detailed` "the correct spelling", and `:576` — the line most users will actually see, because
it fires when the search fails — teaches the other one. The `Register-PFCommand` entry at `:868`
mentions neither spelling, so these two hints are the only reference a user has, which is what
makes their disagreement matter.

---

## 5 · Deliberate exceptions already in the tree

These are non-uniformities that were *decided*, with the reasoning written down at the point of
decision. Any future rule must carve them out explicitly, because a mechanical sweep would
"fix" them back into bugs. They are listed with the exact text that authorises them so a future
reader does not have to re-litigate.

**`ls -r` is deliberately NOT aliased to recursion.** GNU uses `-r` for reverse-sort and lsd
honours it; `-R` is GNU recursive and already works.

```powershell
# components/files/listing.ps1:53-55
# -recurse / -Recurse: the spelling a PowerShell user already knows. Get-ChildItem
# habits should not be punished. NOT -r — that is GNU reverse-sort and lsd honours
# it; -R is GNU recursive and already works.
```

Restated in `COMPONENTS.md:165`: "**`-r` is NOT aliased** — that is GNU reverse-sort." Any rule
that says "every long flag gets a short form" breaks this.

**`ls -v` is version-sort, not verbose,** for the same reason: the file's stated rule is
"GNU semantics, exactly" for single dashes (`components/files/listing.ps1:11-13`), and GNU's own
`ls -v` is natural version sort. Section 4.9 lists it for completeness only.

**Coreutils are not shadowed on Linux.** `platform/linux/bindings.ps1:35-40` states the whole
policy as three named strategies:

```powershell
#   OVERRIDE  PowerFlow adds real value and the semantics don't conflict  (ls/la/ll)
#   RENAME    the feature is valuable but the semantics differ            (rm->del, mv->mvf)
#   DEFER     PowerFlow merely reimplements a tool Linux already has      (cp, cat,
#             mkdir, touch, rmdir, which, grep, less, pwd)
```

CI asserts that `rm`, `mv`, `cp`, `cat`, `mkdir`, `touch`, `rmdir`, `which` and `grep` all
resolve to a native binary on Linux. This is why the flag surfaces of `cat` and `cp` genuinely
differ per platform (section 4.15) and why that difference cannot simply be equalised.

**`--show-native` is deliberately long-only, with no short form.** Matched by exact equality at
`components/docker/dkr.ps1:400` and `components/system/storage.ps1:259`, and registered as a
long switch in `pmx` (`components/proxmox/shared.ps1:77`). `docs/plan/docker/dkr.md:68-72`
documents the reasoning. Any rule that mandates a short alias for every long flag breaks it.

**Neither `dkr` nor `storage` nor `nav` nor `ls` may gain a `param()` block.** Four file headers
say so, each naming a real bug that was undone:

```powershell
# components/docker/dkr.ps1:25-27
# NO param() BLOCK — DO NOT ADD ONE
# PowerShell would bind `-a` and `-f` as PARAMETER NAMES and reject everything else,
# which is exactly the bug that had to be undone in nav. $args is hand-parsed instead.
```

`components/system/storage.ps1:249-250` (quoted in section 3, and locked by
`tests/storage/storage-behaviour.ps1:71-80`), `components/files/listing.ps1:18-30` (with the
worked failure `ls -ld ward-a` → "silently swallowed into $args and DISCARDED"), and
`COMPONENTS.md:165` for `nav`.

**`-lesson` and `--lesson` are both accepted on all twenty brothers.** `components/shell/brothers.ps1:33`
matches `^--?lesson$`, and `:20` documents it: "Every brother supports `-lesson`". A deliberate
superset, chosen so no plausible spelling fails; no coreutil flag can collide with the word.

**The brothers' own flags are the wrapped tool's, preserved verbatim.** `dirsize -sh`,
`listports -tulpn`, `systemlogs -u <unit> -e`, `lastlines -f` are GNU clusters passed straight
through (`components/shell/brothers.ps1:47`), documented as such at `:6-7` and `:16-17`. They
must never be normalised to PowerFlow style — teaching the real flags is the point of the
command.

**`pmx vm clone --full` is accepted, inert, and hidden on purpose.**
`components/proxmox/vm-change.ps1:120-122`: accepted so existing commands do not break, never
read because `Full = $true` is hardcoded, and "gone from the help text rather than advertised as
a choice the user does not have." A dead-flag sweep would delete it and break someone's history.

**`pwsh-h -all` is an intentional accepted-and-ignored legacy spelling**
(`components/help/menu.ps1:88-89`), and `pwsh-h -a` means "advanced" rather than "all" by a
documented four-times-over choice (`menu.ps1:22-29`, `:36`, `:123`, `:175`, `:263`).

**`nav --start-repo` is deliberate muscle-memory forgiveness** — "accepted because that is what
the owner first reached for" (`components/navigation/nav.ps1:33`). Section 4.18 questions the
*vocabulary*, not the decision to forgive.

**`pmx` requires exact long option names by specification,** not by accident:
`docs/plan/proxmox/pmx-vm-management.md:21` says "exact long option names, no abbreviation".
That is a deliberate rejection of PowerShell prefix matching, and it is the reason `pmx` has no
`param()` block anywhere.

**`mv` accepts both `-detailed` and `--detailed` on purpose** (`components/files/operations.ps1:299-302`),
"so nobody's habit breaks". Section 4.21 is about which one the hints print, not about accepting
both.

**`srv <name> info` is positional-second by design** (`components/network/servers.ps1:311`,
`:454`), matching `pmx disk <device> <action>`. The verb-last shape is a chosen house pattern,
not an outlier.

---

## 6 · The options

Four candidate conventions. Each is stated as a one-sentence rule, then costed: how many
commands change, which cannot change without breaking a documented interface, and what the rule
buys. Migration counts come from the 40 `param()`-block commands, the 85 hand-parsed commands,
and the 45 one-dash-word tokens in section 2.

Two facts constrain all four, and are worth restating because they are not negotiable:

1. **A `param()` block can never accept `--long`.** Any rule that makes `--long` canonical
   requires converting `param()` commands to hand-parsers, or accepting that `--long` fails on
   40 commands.
2. **A hand-parser gets no case-insensitivity or prefix matching for free.** Any rule that makes
   hand-parsing universal must decide, per command, whether to reimplement those forgivenesses —
   and if it does not, users lose `-Status` and `-st` on commands where they work today.

### Option A — One letter per dash (GNU-strict)

> **Rule:** a single dash introduces exactly one letter; a word always takes two dashes; a
> single-dash token longer than one character is refused by name, with the `--long` spelling
> printed in the error.

**Cost.** All 45 one-dash-word tokens change, spread across 13 command families. Thirteen of
those spellings are *documented*, so changing them breaks a published interface and needs a
deprecation window rather than an edit:

| Command | Documented one-dash word | Where it is published |
|---|---|---|
| `pc-whoami` | `-ram -power -crashes -bios -export -days -min` | `health.ps1:871` registry example; `COMPONENTS.md:184` |
| `pwsh-font` | `-status` | `fonts.ps1:68` registry example |
| `set-path` | `-system` | `path.ps1:42` registry synopsis |
| `git-a-plus` | `-Quick -DryRun -AmendLast` | `commit.ps1:459` registry synopsis |
| `ls` / `ll` | `-recurse` `-depth N` | `listing.ps1:164`, `:166`; `COMPONENTS.md:165`; `CHANGELOG.md` |
| `srv` | `-f` (one letter — survives) | `servers.ps1:456` |
| `git-rl` | `-h` | `release.ps1:475`; `README.md:477`; `COMPONENTS.md:175`; `docs/git-rl/README.md:20` |
| `pmx disk` | `-Full -Write -Destroy` | `help.ps1:261-262`, `:283-297`, `:363-366`; runtime hints ×3 |
| `paste-file` / `pf` | `-Force` | `clipboard.ps1:200` runtime hint |
| brothers (×20) | `-lesson` | `brothers.ps1:20`, `:205` |
| `powerflow-update` | `-Yes` | `version.ps1:150` `.EXAMPLE` |
| `team-room` | `-All` | `team-room.ps1:243-244`, `:272` |
| `installed-apps` | `-Overview` (`-o` survives) | `apps.ps1:570` |

The deeper cost is structural: to accept the `--long` replacements, **each of those commands
must be converted from `param()` to a hand-parser** — including `pc-whoami`, which has seven
switches plus two positionals and a level-word vocabulary. That is where the bill actually
lands. `ls`, `nav`, `dkr` and `storage` are already hand-parsed, so they are cheap; `pc-whoami`,
`git-a-plus`, `installed-apps`, `team-room` and `pwsh-h` are not.

**Cannot change at all:** the brothers' pass-through flags (section 5), because they belong to
`chmod`, `ss`, `du` and friends, and `-lesson` itself, which is a documented superset accepting
both dash counts already.

**Wins.** Eliminates section 4.1 outright — the bundling hazard becomes structurally impossible
once a multi-character single-dash token is a refusal. Matches the rule already written at
`components/files/listing.ps1:11` and `CHANGELOG.md:1579`, and the specification at
`docs/plan/proxmox/pmx-vm-management.md:21`. Makes `rm`, `ls`, `mv` and the brothers honest about
impersonating GNU tools. Kills sections 4.3, 4.4, 4.13 and 4.14 as a side effect, because
hand-parsing removes prefix matching and makes casing explicit.

**Loses.** Every PowerShell forgiveness users currently rely on, unless each hand-parser
reimplements it: `-Status` stops working unless the parser lowercases, `-st` stops working
entirely. It also asks `pc-whoami` to become `pc-whoami --power`, which is the least
PowerShell-looking command in the shell.

### Option B — One dash, always a word (PowerShell-native)

> **Rule:** PowerFlow's own flags are single-dash lowercase words; `--long` is accepted as an
> alias wherever the command hand-parses; GNU short clusters exist only inside the commands that
> deliberately impersonate a native tool.

**Cost.** The 169 `--long` tokens do not all change — `pmx`'s entire surface is hand-parsed and
would keep `--long` as the accepted alias. What changes is smaller and sharper:

- The 45 one-dash words become the canonical, documented spelling everywhere. Thirteen already
  are; the rest get promoted from accident to policy.
- The PascalCase declarations in section 4.13 are renamed lowercase — 8 commands
  (`paste-file`/`pf`, `git-rb`, `git-a-plus`, `powerflow-update`, `team-room`,
  `installed-apps`, `set-path`, `pmx disk`'s help text). Runtime behaviour is unchanged because
  PowerShell is case-insensitive; only declarations and help strings move.
- **`Split-GnuArgs` must be taught to reject one-dash words** rather than bundling them
  (`components/files/operations.ps1:61-62`), which fixes section 4.1 without touching any
  command.

**Cannot change:** `pmx`'s doctrine, which is specified as long-only in
`docs/plan/proxmox/pmx-vm-management.md:21` and enforced case-sensitively at
`components/proxmox/shared.ps1:112` — a `pmx --long` surface with one-dash aliases would need
that specification revisited. `--show-native` (deliberately long-only, section 5). The brothers'
pass-through flags. `rm -rf`, which is the whole point of `rm`.

**Wins.** Cheapest of the four, because it ratifies what 40 `param()` commands already do rather
than rewriting them. Keeps case-insensitivity and prefix forgiveness. Makes the help text
consistent with the declarations for free. Fixes section 4.13 with a rename and section 4.1 with
a guard, and makes section 4.3 a non-issue because `--long` stops being canonical.

**Loses.** `rm`, `mv`, `ls`, `touch`, `mkdir` and the brothers now speak a different dialect
from the rest of the shell by design, which means the boundary itself has to be documented and
taught — the exact thing users find hardest. It also formally contradicts
`components/files/listing.ps1:11` and `CHANGELOG.md:1579`, so those decisions would need to be
rewritten rather than quietly overridden.

### Option C — The parser declares the dialect (status quo, formalised and enforced)

> **Rule:** every command declares in a header comment whether it is hand-parsed or
> `param()`-bound; hand-parsed commands take `--long` exactly and reject one-dash words;
> `param()` commands take `-Word` and never advertise a `--long` spelling; CI fails a release
> where a registered synopsis or example uses a spelling the command's own parser cannot accept.

**Cost.** Zero flag renames. The work is a CI gate plus the drift fixes it would then catch:
sections 4.3 (five commands advertising `--long` they cannot bind), 4.11 (`ls`'s synopsis and
example teaching opposite conventions), 4.13 (`set-path` declaring `-System` and advertising
`-system`), 4.16 (nine commands), 4.17 (`pmx`'s footer), 4.21 (`mv`'s two hints). Call it 20
one-line documentation fixes and one new gate in `release-validate.yml` — the cheapest option by
an order of magnitude.

**Cannot change:** nothing. That is both its strength and its limitation.

**Wins.** Affordable today. Kills every docs-versus-code finding (4.3 partially, 4.11, 4.13,
4.16, 4.17, 4.21) by making the manual mechanically true. Preserves every deliberate exception
in section 5 without special-casing.

**Loses.** It does **not** fix the hazards. `rm -force` still deletes a tree, `git-bd` still
force-deletes, `git-a-plus -a` still amends, `pwsh-font --status` still installs — because none
of those is a documentation defect. It also formalises the thing the owner objected to: a user
still cannot carry one habit across the shell, they can only trust the manual about where it
stops. Those four fixes (sections 4.1, 4.2, 4.3, 4.4) are independent of the convention and
should arguably ship regardless of which option wins.

### Option D — Refinements are words, not flags

> **Rule:** a refinement is a bare word — `rm force tree`, `dkr down yes`, `pmx disk sda full`,
> `pc-whoami power` — and dashes survive only where a wrapped native tool owns them or where GNU
> parity is the command's purpose.

This is the convenience creed extended to its conclusion. The creed already says: bare command
does the useful thing, refinement is a word, ambiguity gets a picker, native detail only behind
`--show-native`. Several commands already work this way — `pwsh-autologin on|off|status`
(`components/system/login.ps1:33`), `linux-lessons full|hint|off`
(`components/shell/teach.ps1:37`), `pmx config set <setting> <value>`, `start-folder open|add|list`.

**Cost.** The largest and the least mechanical. Every one of the 78 one-dash and short tokens
gains a word form, and the bare-word namespace grows — which collides head-on with section 4.19,
where bare words already shadow flags (`nav code`) and disagree across routers (`host`, `list`).
It would need a namespace rule of its own before it could be adopted: reserved words per router,
a stated precedence between a bare word and a flag, and a policy for the eight existing `list`
implementations.

**Cannot change:** `rm -rf` and the brothers, for the reasons in section 5. GNU parity is not a
style choice there; it is the feature.

**Wins.** No dash convention to remember at all, which is the only outcome that fully satisfies
"never make users memorise flags". Sidesteps the PowerShell-versus-Unix tension in section 3
entirely, because a bare word binds the same way under both parsers. Case-insensitivity is free
(`-in` and `-eq` are case-insensitive). It is also the only option that reads naturally aloud,
which is how the owner describes commands.

**Loses.** Scriptability and precision. `rm force tree` cannot be distinguished from a file
literally named `force` without a reserved-word list, and reserved words are exactly the
memorisation the creed forbids — just relocated. It also means PowerFlow's `rm` stops accepting
what every user's muscle memory produces.

---

## 7 · Open questions for the owner

These are the decisions the evidence cannot make.

**1 · Break existing spellings, or accept both with one documented?** The tree already does the
second thing four times deliberately — `-lesson`/`--lesson`, `-detailed`/`--detailed`,
`-recurse`/`--recurse`, `nav --start-repo`. Accepting both is cheap, forgiving and consistent
with the creed; it also means the manual has to nominate a canonical spelling and every hint has
to use it, which is precisely the discipline that failed at
`components/files/operations.ps1:576`. Choosing to accept both is choosing a documentation
obligation, not avoiding a decision.

**2 · Should subcommands ever gain a dashed form?** `srv list` and `pmx vm list` are bare words
today, and nothing in the tree lets `srv --list` work. If the answer is never, that should be
stated, because `nav --anchor` is already a dashed *verb* (`components/navigation/nav.ps1:34`) and
`pmx config set` is a bare one — the product currently does both without a rule.

**3 · Is the bare-word namespace governed at all?** Section 4.19 is only a defect if bare words
are supposed to mean one thing per product. If `host` is allowed to mean a remote alias in `pmx`
and the local machine name in `pwsh-config`, say so; if not, one of them has to be renamed. The
same question decides whether `nav code` may keep beating `nav -srv`.

**4 · Should `pmx` keep its own stricter dialect?** It is the only command with a written option
specification, and it is stricter than anything else in the shell — long-only, case-sensitive,
no abbreviation. That is defensible for a command that talks to a hypervisor. But it means "the
PowerFlow convention" will have an exception the size of forty routes, and the disk route
(section 4.10) is currently an exception *within* the exception.

**5 · Does PowerShell prefix matching stay?** It cannot be partially kept: it is a property of
`param()`, so the only way to remove it is hand-parsing. Keeping it means accepting that 54
undocumented flags exist and that `git-a-plus -a` amends a commit unless `-AmendLast` is renamed.
Removing it means 40 commands lose `-st` for `-status` and gain a parser each.

**6 · Do the four hazards ship before the convention is chosen?** Sections 4.1, 4.2, 4.3 and 4.4
cause data loss or silent wrong actions and are independent of which convention wins. The
minimal set is: reject one-dash words in `Split-GnuArgs`
(`components/files/operations.ps1:61-62`), rename one of `git-bd`/`git-bD`
(`components/git/branches.ps1:265`, `:286`), make `pwsh-font` refuse `--status` rather than
installing (`components/system/fonts.ps1:29`), and put `git-a-plus`'s amend behind something
`-a` cannot reach (`components/git/commit.ps1:248`). A CI gate that fails on two `function`
definitions differing only in case would catch the `git-bd` class permanently.

**7 · Should `Register-PFCommand` gain a flags field?** Section 4.16's root cause is that the
registry has no argument schema (`components/help/registry.ps1:76-83`), so every flag is prose.
A structured field would let CI check that every advertised spelling is one the command's parser
accepts — which is the enforcement mechanism Option C needs and the other three would benefit
from. This is the one question whose answer is useful under every option.

---

## 8 · Appendix: full inventory

Every accepted token on every user-facing command surface, with the file and line that accepts
it, what it does, the other spellings that also bind, and what the documentation says. This is
the audit trail behind the counts in section 2 and every citation in section 4. It is reproduced
in full and unedited; where a token is a hazard or a dead declaration, that is noted inline
rather than removed.

Reading the format: `token  (parse-category/style)  meaning  @file:line [also: other accepted
spellings] [docs say: what the help text claims]`.

### Navigation and files

```text
nav  [hand-parsed-args]  components/navigation/nav.ps1
    -verbose  (hand-parsed/-long)  echo the resolved root key, the word list and the chosen search roots  @components/navigation/nav.ps1:31 [also: -Verbose -VERBOSE (-in is case-insensitive)] [docs say: not documented anywhere (absent from nav's own help block, lines 72-94, and from all four Register-PFCommand calls)]
    -v  (hand-parsed/-short)  same as -verbose  @components/navigation/nav.ps1:31 [also: -V] [docs say: not documented]
    --anchor  (hand-parsed/--long)  verb: save <path> as a named starting point called <name>  @components/navigation/nav.ps1:34 [also: --Anchor --ANCHOR] [docs say: nav --anchor . mon (nav.ps1:367 -Example; roots.ps1:428,503)]
    -anchor  (hand-parsed/-long)  single-dash spelling of --anchor, accepted identically  @components/navigation/nav.ps1:34 [also: -Anchor] [docs say: never shown; only --anchor appears in help]
    --start-repo  (hand-parsed/--long)  third accepted spelling of --anchor ('because that is what the owner first reached for')  @components/navigation/nav.ps1:34 [also: --START-REPO] [docs say: undocumented; the word 'repo' appears nowhere in any help text or registration]
    -<root>  (hand-parsed/-long)  named starting point: scopes the search (or cd's straight there when no word follows)  @components/navigation/nav.ps1:35 [also: -home -code -documents -downloads -pictures -videos -music -desktop -config -tmp -srv (Linux) -opt (Linux) -www (Linux) -etc (Linux) -log (Linux) -mnt (Linux) -pics -pic -docs -doc -dl -down -vids -vid -desk -conf -cfg -<any user anchor name> --pics / --code / --srv (Resolve-PFRootAlias does TrimStart('-'), which strips ALL leading dashes, roots.ps1:285) -PICS / -Code (ToLowerInvariant, roots.ps1:285)] [docs say: nav -pics screenshots (nav.ps1:364); 'nav -<start> <name>' (nav.ps1:75-76)]
    anchors  (subcommand/bare)  list built-in and user starting points  @components/navigation/nav.ps1:60 [also: anchor ANCHORS / Anchors (-in is case-insensitive; true of every subcommand below)] [docs say: nav anchors (nav.ps1:367)]
    rm  (subcommand/bare)  under 'anchors': delete a user anchor  @components/navigation/nav.ps1:61 [also: remove d delete] [docs say: nav anchors rm mon (nav.ps1:367; roots.ps1:464,504)]
    roots  (subcommand/bare)  show/edit where a bare nav searches, and list every named starting point  @components/navigation/nav.ps1:110 [docs say: nav roots (nav.ps1:366)]
    add  (subcommand/bare)  under 'roots': add a search root  @components/navigation/nav.ps1:112 [also: a] [docs say: nav roots add /srv (nav.ps1:366); nav roots add <path> (nav.ps1:92, roots.ps1:93,166)]
    rm  (subcommand/bare)  under 'roots': remove a search root  @components/navigation/nav.ps1:113 [also: remove d] [docs say: nav roots rm <path> (roots.ps1:125,167) — note 'delete' works for anchors but NOT for roots]
    reset  (subcommand/bare)  under 'roots': forget the config, back to the platform default  @components/navigation/nav.ps1:114 [docs say: nav roots reset (roots.ps1:168)]
    b  (subcommand/bare)  jump to a bookmark  @components/navigation/nav.ps1:131 [docs say: nav b docs (nav.ps1:365,86)]
    .  (positional/value)  after 'b': bookmark the current directory instead of jumping  @components/navigation/nav.ps1:135 [also: ./ .\] [docs say: nav b . (nav.ps1:365,87)]
    create-b  (subcommand/bare)  create a bookmark for the current directory  @components/navigation/nav.ps1:103 [also: cb] [docs say: long form only in an error string (bookmarks.ps1:77); short form in nav's help (nav.ps1:89). Neither is a registered pwsh-h command.]
    delete-b  (subcommand/bare)  delete a bookmark (Read-Host y/n confirm)  @components/navigation/nav.ps1:104 [also: db] [docs say: bookmarks.ps1:99; nav.ps1:89,154]
    rename-b  (subcommand/bare)  rename a bookmark  @components/navigation/nav.ps1:105 [also: rb] [docs say: bookmarks.ps1:133; nav.ps1:89]
    list  (subcommand/bare)  open the interactive bookmark manager (Read-Host REPL, see 'nav list' row)  @components/navigation/nav.ps1:106 [also: l] [docs say: nav list — 'manage bookmarks (Enter go · ctrl-d delete)' (nav.ps1:88). The 'l' short form is undocumented, and the ctrl-d claim is false — Show-BookmarkList uses Read-Host, not fzf.]
    ~  (subcommand/bare)  cd to home  @components/navigation/nav.ps1:193 [docs say: not in nav's help; '~' is separately registered as its own command (directory.ps1:240)]
    home  (subcommand/bare)  cd to home — hardcoded, distinct from the -home root flag  @components/navigation/nav.ps1:194 [docs say: undocumented]
    code  (subcommand/bare)  cd to ~/Code (hardcoded Join-Path, not the -code root)  @components/navigation/nav.ps1:195 [docs say: undocumented as a bare word; only '-code' is advertised. It is matched BEFORE the anchor search, so `nav -srv code` silently ignores -srv and goes to ~/Code.]
    projects  (subcommand/bare)  cd to ~/Code/Projects (hardcoded)  @components/navigation/nav.ps1:206 [docs say: undocumented; same shadowing hazard as 'code']
    <dest>  (positional/value)  fuzzy-search target; several words are joined with spaces into one fzf query  @components/navigation/nav.ps1:264 [docs say: nav chess-guru (nav.ps1:364,74)]
    <path>  (positional/value)  a real existing directory path is cd'd into directly  @components/navigation/nav.ps1:220 [docs say: nav <path> (nav.ps1:77)]

z  (Set-Alias z nav — accepts every nav token above)  [hand-parsed-args]  components/navigation/nav.ps1
    z  (subcommand/bare)  alias to nav declared at nav.ps1:361; argument surface is identical  @components/navigation/nav.ps1:361 [docs say: -Aliases @('z') (nav.ps1:364)]

nav list  (the interactive bookmark REPL it opens)  [hand-parsed-args]  components/navigation/bookmarks.ps1
    q  (subcommand/bare)  quit the REPL  @components/navigation/bookmarks.ps1:188 [docs say: "'q' to quit" (bookmarks.ps1:183)]
    <number>  (positional/value)  cd to the Nth bookmark in the printed list  @components/navigation/bookmarks.ps1:193 [docs say: 'Enter number to navigate' (bookmarks.ps1:183)]
    c  (subcommand/bare)  c <name> — create a bookmark (regex ^c\s+(.+)$)  @components/navigation/bookmarks.ps1:209 [docs say: "'c <name>' to create" (bookmarks.ps1:183) — note nav's own verb for this is cb/create-b, so the same action has three spellings]
    d  (subcommand/bare)  d <name> — delete a bookmark (regex ^d\s+(.+)$)  @components/navigation/bookmarks.ps1:213 [docs say: "'d <name>' to delete" (bookmarks.ps1:183)]
    r  (subcommand/bare)  r <old> <new> — rename (regex ^r\s+(\S+)\s+(\S+)$; names with spaces cannot be typed)  @components/navigation/bookmarks.ps1:215 [docs say: "'r <old> <new>' to rename" (bookmarks.ps1:183)]
    y  (positional/value)  the delete confirmation prompt 'Confirm (y/n)' accepts only y or Y; 'yes' is treated as no  @components/navigation/bookmarks.ps1:115 [also: Y] [docs say: Confirm (y/n) (bookmarks.ps1:113) — every other confirm in the slice is spelled '[y/N]']

..  [param-block]  components/navigation/directory.ps1
    <dir>  (positional/value)  after going up one level, hand the remaining words (joined with spaces) to nav  @components/navigation/directory.ps1:68 [docs say: .. management / .. "Web Apps" (directory.ps1:62-63)]
    -t  (param-switch/param-derived)  unambiguous prefix of -targetDirParts; `.. -t foo` is identical to `.. foo` (verified in pwsh)  @components/navigation/directory.ps1:68 [also: -ta -tar -target -targetDirParts -TARGETDIRPARTS (case-insensitive)] [docs say: not documented; ValueFromRemainingArguments also lets any OTHER dash token (e.g. `.. -foo`) through into the array, which nav then rejects as an unknown starting point]

...  [param-block]  components/navigation/directory.ps1
    <dir>  (positional/value)  up two levels, then nav <dir>  @components/navigation/directory.ps1:107 [docs say: ... projects (directory.ps1:101)]
    -t  (param-switch/param-derived)  prefix of -targetDirParts  @components/navigation/directory.ps1:107 [also: -targetDirParts] [docs say: not documented]

....  [param-block]  components/navigation/directory.ps1
    <dir>  (positional/value)  up three levels, then nav <dir>  @components/navigation/directory.ps1:146 [docs say: .... code (directory.ps1:140)]
    -t  (param-switch/param-derived)  prefix of -targetDirParts  @components/navigation/directory.ps1:146 [also: -targetDirParts] [docs say: not documented]

.....  [param-block]  components/navigation/directory.ps1
    <dir>  (positional/value)  up four levels, then nav <dir>  @components/navigation/directory.ps1:184 [docs say: ..... documents (directory.ps1:179)]
    -t  (param-switch/param-derived)  prefix of -targetDirParts  @components/navigation/directory.ps1:184 [also: -targetDirParts] [docs say: not documented]

~  [none]  components/navigation/directory.ps1
    (none)  (positional/bare)  no param block and no $args read — arguments are silently discarded; always cd $HOME  @components/navigation/directory.ps1:209 [docs say: ~ — 'go home' (directory.ps1:240)]

back  [none]  components/navigation/directory.ps1
    (none)  (positional/bare)  no arguments accepted; walks $global:NAV_HISTORY[-2]  @components/navigation/directory.ps1:218 [docs say: back — 'return to the previous directory' (directory.ps1:239)]

cd-  [none]  components/navigation/directory.ps1
    cd-  (subcommand/bare)  Set-Alias cd- back; no arguments  @components/navigation/directory.ps1:228 [docs say: -Aliases @('cd-') (directory.ps1:239)]

copy-pwd  [none]  components/navigation/directory.ps1
    (none)  (positional/bare)  no arguments; copies $PWD via Copy-ToClipboard  @components/navigation/directory.ps1:230 [docs say: copy-pwd (directory.ps1:241)]

here  [none]  components/navigation/directory.ps1
    (none)  (positional/bare)  no param block, $args never read — anything typed is silently ignored  @components/navigation/directory.ps1:21 [docs say: here — 'show where you are, with quick actions' (directory.ps1:238). There are NO quick actions in the body; it only prints. Documented-vs-actual mismatch.]

ls  [hand-parsed-args]  components/files/listing.ps1
    --tree  (hand-parsed/--long)  lsd tree view; hard-requires lsd or it warns and returns  @components/files/listing.ps1:52 [also: --TREE --Tree (switch -Regex is case-insensitive)] [docs say: --tree (listing.ps1:164,166)]
    -recurse  (hand-parsed/-long)  same as --tree (NOT GNU -R recursion)  @components/files/listing.ps1:56 [also: --recurse -Recurse --Recurse -RECURSE] [docs say: ls -recurse -depth 2 (listing.ps1:164,166)]
    --depth  (hand-parsed/--long)  tree depth; value is the NEXT argv token  @components/files/listing.ps1:57 [also: --DEPTH] [docs say: --depth (listing.ps1:164,166); 'ls --depth 3' (listing.ps1:14)]
    --depth=  (hand-parsed/--long)  tree depth, =value form  @components/files/listing.ps1:58 [also: --DEPTH=3] [docs say: not documented]
    -depth  (hand-parsed/-long)  tree depth, single-dash form; value is the next token  @components/files/listing.ps1:59 [also: -Depth -DEPTH] [docs say: ls -recurse -depth 2 (listing.ps1:164). NOTE: `-depth=3` is NOT handled — no single-dash '=' case exists, so it falls through to lsd as a bogus argument.]
    -<root>  (hand-parsed/-long)  named starting point: resolve <needle> under that root, then list it  @components/files/listing.ps1:62 [also: -home -code -documents -downloads -pictures -videos -music -desktop -config -tmp -srv (Linux) -opt -www -etc -log -mnt --home / --srv (the regex strips one OR two dashes, listing.ps1:61) -SRV / -Home (ToLowerInvariant, listing.ps1:62-63)] [docs say: ls -srv complete (listing.ps1:164); roots.ps1:196,457,488 and nav.ps1:117 all promise 'ls -<name>' for ALIASES and USER ANCHORS too — but this list is @((Get-PFNamedRoots).Keys) only, so `ls -pics`, `ls -dl`, `ls -docs`, `ls -vids` and `ls -<your-anchor>` are NOT recognised and get passed to lsd as garbage.]
    -l  (hand-parsed/-short)  anything not matched above is forwarded verbatim to lsd / native ls with GNU meaning  @components/files/listing.ps1:65 [also: -a -A -h -d -R -t -S -r -1 -i -la -lh --help (goes to lsd) any bundled short combination] [docs say: 'ls -l -a -d -h -R -t -S -r  GNU semantics, exactly' (listing.ps1:13); ls -la (listing.ps1:164)]
    <needle>  (positional/value)  with a -<root> flag present: the LAST non-dash argv token is the directory to find; several matches open an fzf picker  @components/files/listing.ps1:73 [docs say: ls -srv complete (listing.ps1:164)]
    <path>  (positional/value)  without a root flag: forwarded to lsd/ls as the path to list  @components/files/listing.ps1:65 [docs say: implied]

la  [hand-parsed-args]  components/files/listing.ps1
    -a  (hand-parsed/-short)  injected before @args; every ls token above is then accepted too  @components/files/listing.ps1:152 [docs say: la — 'ls -a: everything, dotfiles included' (listing.ps1:165). No -Example is registered.]

ll  [hand-parsed-args]  components/files/listing.ps1
    -lh  (hand-parsed/-short)  injected bundled shorts before @args; every ls token above is then accepted too  @components/files/listing.ps1:153 [docs say: ll · ll -recurse -depth 2 (listing.ps1:166)]

clr  [none]  components/files/listing.ps1
    clr  (subcommand/bare)  Set-Alias clr clear; no PowerFlow tokens of its own  @components/files/listing.ps1:155 [docs say: clr — 'clear the screen' (listing.ps1:167)]

cat  [param-block]  components/files/listing.ps1
    -Raw  (param-switch/param-derived)  on Windows cat IS Get-Content, so only Get-Content's parameters bind (-Path, -LiteralPath, -Raw, -Tail, -TotalCount, -Encoding, -Wait, …), each with case-insensitive prefix matching  @components/files/listing.ps1:159 [also: -raw -Ra -Tail -TotalCount -Path -LiteralPath] [docs say: cat — 'print a file (the GNU cat on Linux)' (listing.ps1:168). Verified: `cat -n file` fails with "A parameter cannot be found that matches parameter name 'n'" on Windows while it works on Linux, where bindings.ps1 strips the alias. Same command name, two different flag surfaces.]

cp  [param-block]  components/files/listing.ps1
    -r  (param-switch/param-derived)  on Windows cp IS Copy-Item, so -r binds by prefix to -Recurse and happens to behave like GNU cp -r (verified)  @components/files/listing.ps1:161 [also: -R -rec -Recurse -f -> -Force -Destination -Path -LiteralPath -Container -PassThru] [docs say: cp — 'copy files (the GNU cp on Linux)' (listing.ps1:169). Verified: `cp -a` fails ("parameter name 'a'"); -v, -i, -u, -n also fail. Only the accidental -r/-f overlap works.]

rm  [hand-parsed-args]  components/files/operations.ps1
    -r  (hand-parsed/-short)  recurse into directories; without it rm refuses a named directory  @components/files/operations.ps1:78 [also: -R --recursive --RECURSIVE (the LongMap hashtable is case-insensitive) -rf / -fr / any bundle containing r] [docs say: rm -rf node_modules (operations.ps1:867); 'refuses a dir without -r' (867); 'Use -r to recurse' (146)]
    -f  (hand-parsed/-short)  skip the [y/N] confirmation  @components/files/operations.ps1:77 [also: -F --force --Force] [docs say: rm -rf node_modules (operations.ps1:867)]
    -i  (hand-parsed/-short)  always ask; overrides -f  @components/files/operations.ps1:79 [also: -I --interactive] [docs say: not documented in the registration; only in the comment at operations.ps1:84. Note -I and -i are the SAME flag here (Split-GnuArgs stores into a case-insensitive hashtable), whereas GNU treats them differently.]
    --verbose  (hand-parsed/--long)  mapped to 'v' at line 74 but the body NEVER reads 'v' — accepted and silently ignored  @components/files/operations.ps1:74 [also: -v -V] [docs say: not documented]
    --dir  (hand-parsed/--long)  mapped to 'd' at line 74 but the body NEVER reads 'd' — GNU's 'remove empty directory' is accepted and silently ignored, so `rm -d emptydir` still errors with 'Is a directory'  @components/files/operations.ps1:74 [also: -d -D] [docs say: not documented]
    --  (hand-parsed/--long)  end of flags; everything after is a path even if it starts with a dash  @components/files/operations.ps1:51 [docs say: operations.ps1:34-36 comment only]
    -  (positional/value)  a lone dash is a PATH, not a flag (stdin convention)  @components/files/operations.ps1:61 [docs say: operations.ps1:60 comment only]
    <path>...  (positional/value)  each argument is its own glob pattern; if none match, the whole list is retried joined with spaces as one literal name  @components/files/operations.ps1:89 [docs say: rm *.log (operations.ps1:867)]
    y  (positional/value)  the '[y/N]' confirmation accepts only y or Y — 'yes' cancels  @components/files/operations.ps1:165 [also: Y] [docs say: Delete '…'? [y/N] (operations.ps1:154,162)]
    -verbose  (hand-parsed/-long)  HAZARD, not a real flag: single-dash words are bundled character-by-character (operations.ps1:61-62), so `rm -verbose x` sets v,e,r,b,o,s — including r — and silently deletes recursively. Verified in pwsh. `rm -force x` likewise sets f AND r. No 'unknown option' warning is emitted because only --double-dash words reach $unknown.  @components/files/operations.ps1:62 [also: -force -recurse -Recursive any single-dash word containing r or R] [docs say: not documented; the '-recurse / -Recurse: the spelling a PowerShell user already knows' convenience that listing.ps1:53-56 grants ls does NOT exist here, it silently means something else]

mv  [mixed]  components/files/operations.ps1
    -detailed  (hand-parsed/-long)  trace the cut-mode search (exact/fuzzy/extension phases); stripped in a pre-pass before GNU parsing  @components/files/operations.ps1:306 [also: --detailed -Detailed --DETAILED] [docs say: mv <filename> --detailed (operations.ps1:355) and 'mv $fileName -detailed' (operations.ps1:576) — the two help lines disagree on the dash count; the comment at line 301 says --detailed is 'the correct spelling']
    -f  (hand-parsed/-short)  overwrite the destination without asking  @components/files/operations.ps1:328 [also: -F --force] [docs say: '-f  overwrite without asking' (operations.ps1:350,287)]
    -n  (hand-parsed/-short)  never overwrite  @components/files/operations.ps1:329 [also: -N --no-clobber] [docs say: '-n  never overwrite' (operations.ps1:350,288)]
    -v  (hand-parsed/-short)  report skipped-because-exists lines (only consulted alongside -n)  @components/files/operations.ps1:330 [also: -V --verbose] [docs say: not documented]
    --interactive  (hand-parsed/--long)  mapped to 'i' at line 310 but never read — accepted and silently ignored  @components/files/operations.ps1:310 [also: -i -I] [docs say: not documented]
    --  (hand-parsed/--long)  end of flags (inherited from Split-GnuArgs)  @components/files/operations.ps1:51 [docs say: not documented for mv]
    <src> <dst>  (positional/value)  2+ paths = a real GNU move; 1 path = PowerFlow's cut/hold  @components/files/operations.ps1:317 [docs say: mv old.txt new.txt (operations.ps1:868,348-349)]
    q  (positional/value)  the three ambiguity prompts ('Enter number to cut for moving (or q to quit)') take a 1-based index or q  @components/files/operations.ps1:440 [also: <number> q at lines 491 and 545] [docs say: operations.ps1:439,490,544 — a hand-rolled numbered menu, whereas ls and rm use fzf for the same ambiguity]

mv-t  [none]  components/files/operations.ps1
    (none)  (positional/bare)  no param block, $args never read; pastes $script:MoveInHand into $PWD  @components/files/operations.ps1:588 [also: y / Y at the 'Overwrite existing file? (y/n)' prompt, line 622-623] [docs say: mv-t — 'paste the cut file here' (operations.ps1:869)]

mv-c  [none]  components/files/operations.ps1
    (none)  (positional/bare)  no arguments; drops the held file  @components/files/operations.ps1:668 [docs say: mv-c — 'cancel the cut - drop the held file' (operations.ps1:870)]

rmdir  [hand-parsed-args]  components/files/operations.ps1
    --parents  (hand-parsed/--long)  mapped to 'p' at line 689 but the body NEVER reads it — accepted and silently ignored (GNU rmdir -p removes parent dirs too)  @components/files/operations.ps1:689 [also: -p -P] [docs say: not documented]
    --verbose  (hand-parsed/--long)  mapped to 'v' at line 689 but never read — accepted and silently ignored  @components/files/operations.ps1:689 [also: -v -V] [docs say: not documented]
    --  (hand-parsed/--long)  end of flags (inherited from Split-GnuArgs)  @components/files/operations.ps1:51 [docs say: not documented for rmdir]
    <dir>...  (positional/value)  each path removed in turn; a non-empty dir triggers a [y/N] prompt  @components/files/operations.ps1:699 [docs say: usage: rmdir <dir>... (operations.ps1:695); registration has NO -Example (operations.ps1:873)]
    y  (positional/value)  'Delete it and everything in it? [y/N]' accepts only y or Y  @components/files/operations.ps1:716 [also: Y] [docs say: operations.ps1:715]

touch  [hand-parsed-args]  components/files/operations.ps1
    -c  (hand-parsed/-short)  bump the timestamp only if the file exists; never create  @components/files/operations.ps1:754 [also: -C --no-create --NO-CREATE] [docs say: touch -c maybe.txt (operations.ps1:872,748,761)]
    -v  (hand-parsed/-short)  print the name of each existing file whose timestamp was bumped  @components/files/operations.ps1:755 [also: -V --verbose] [docs say: not documented]
    --  (hand-parsed/--long)  end of flags (inherited from Split-GnuArgs)  @components/files/operations.ps1:51 [docs say: not documented for touch]
    <file>...  (positional/value)  one file per argument  @components/files/operations.ps1:765 [docs say: touch a.txt b.txt (operations.ps1:747)]

mkdir  [hand-parsed-args]  components/files/operations.ps1
    -p  (hand-parsed/-short)  create missing parents, and succeed silently if the dir exists  @components/files/operations.ps1:813 [also: -P --parents --Parents] [docs say: mkdir -p src/app/ui (operations.ps1:871,806,820,852)]
    -v  (hand-parsed/-short)  with -p, report 'already exists'  @components/files/operations.ps1:814 [also: -V --verbose] [docs say: not documented]
    --  (hand-parsed/--long)  end of flags (inherited from Split-GnuArgs)  @components/files/operations.ps1:51 [docs say: not documented for mkdir]
    <dir>...  (positional/value)  one directory per argument  @components/files/operations.ps1:824 [docs say: mkdir a b c (operations.ps1:807)]

open-pwd  [none]  components/files/clipboard.ps1
    (none)  (positional/bare)  no param block, $args never read; Open-Path $PWD  @components/files/clipboard.ps1:21 [docs say: open-pwd (clipboard.ps1:223)]

op  [none]  components/files/clipboard.ps1
    (none)  (positional/bare)  a wrapper FUNCTION (not Set-Alias) that calls open-pwd and drops any argument  @components/files/clipboard.ps1:41 [docs say: -Aliases @('op') (clipboard.ps1:223)]

copy-file  [param-block]  components/files/clipboard.ps1
    -filePath  (param-switch/param-derived)  Mandatory; the file to put on the clipboard as 'FILE:<fullpath>'  @components/files/clipboard.ps1:183 [also: -f -file -FILEPATH -FilePath (case-insensitive, any unambiguous prefix)] [docs say: copy-file — 'copy a file to the clipboard (fzf picker)' (clipboard.ps1:224). There is NO fzf picker in the body; because -filePath is Mandatory, a bare `copy-file` drops into PowerShell's mandatory-parameter prompt instead. Documented-vs-actual mismatch.]
    <file>  (positional/value)  binds to -filePath positionally  @components/files/clipboard.ps1:183 [docs say: implied]

cf  [param-block]  components/files/clipboard.ps1
    -filePath  (param-switch/param-derived)  forwarded to copy-file; NOT mandatory here, so a bare `cf` reaches copy-file with '' and triggers ITS mandatory prompt  @components/files/clipboard.ps1:209 [also: -f -file -FilePath] [docs say: 'Use cf <filename> to copy a file first' (clipboard.ps1:57); -Aliases @('cf') (clipboard.ps1:224)]
    <file>  (positional/value)  binds to -filePath positionally  @components/files/clipboard.ps1:209 [docs say: cf <filename> (clipboard.ps1:57)]

paste-file  [param-block]  components/files/clipboard.ps1
    -Force  (param-switch/param-derived)  skip the overwrite/rename prompt and auto-generate a ' - Copy' name  @components/files/clipboard.ps1:47 [also: -force -F -Fo -FORCE] [docs say: 'pf -Force to overwrite without asking' (clipboard.ps1:200). PascalCase -Force here versus GNU -f in rm/mv — the only param-derived flag style in the whole slice.]
    -Path  (param-switch/param-derived)  destination directory; defaults to $PWD  @components/files/clipboard.ps1:48 [also: -path -P -Pa] [docs say: not documented]
    y  (positional/value)  the two overwrite prompts accept y, n, or r (r = type a new filename)  @components/files/clipboard.ps1:90 [also: n r the same triple at line 138] [docs say: 'Rename the copy? (y/n/r=rename manually)' (clipboard.ps1:90); 'Overwrite existing file? (y/n/r=rename new file)' (clipboard.ps1:138). Lowercase-only per the original claim — REFUTED: -eq 'y' is case-insensitive in PowerShell, so 'Y' does NOT cancel.]

pf  [param-block]  components/files/clipboard.ps1
    -Force  (param-switch/param-derived)  forwarded to paste-file -Force  @components/files/clipboard.ps1:214 [also: -force -F -Fo] [docs say: pf -Force (clipboard.ps1:200)]
    -Path  (param-switch/param-derived)  forwarded to paste-file -Path when non-empty  @components/files/clipboard.ps1:214 [also: -path -P] [docs say: not documented]

rn  [param-block]  components/files/rename.ps1
    <filename>  (positional/value)  file to rename; all remaining words are joined with spaces, then exact->fuzzy searched. Empty opens an fzf picker.  @components/files/rename.ps1:26 [docs say: rn draft.md (rename.ps1:210); rn / rn myfile.txt (rename.ps1:20-21)]
    -f  (param-switch/param-derived)  unambiguous prefix of -fileNameParts, so `rn -f draft.md` is identical to `rn draft.md`  @components/files/rename.ps1:26 [also: -file -fileName -fileNameParts -FILENAMEPARTS] [docs say: not documented. Any OTHER dash token (e.g. `rn -force`) is swallowed into the array by ValueFromRemainingArguments and searched for as part of the filename, with no error (verified in pwsh).]
```

### Proxmox (`pmx`)

```text
pmx  [hand-parsed-args]  components/proxmox/command.ps1
    help  (subcommand/bare)  opens the pmx help catalogue; remaining words become the topic path  @components/proxmox/command.ps1:171 [also: HELP Help --help -h /?] [docs say: pmx help]
    --help  (hand-parsed/--long)  honoured ANYWHERE in the command line and always wins over running the command  @components/proxmox/command.ps1:184 [also: --HELP --Help -h /?]
    -h  (hand-parsed/-short)  same as --help, accepted at token zero or anywhere in the tail  @components/proxmox/command.ps1:184 [also: -H]
    /?  (hand-parsed/bare)  Windows-style help token, accepted anywhere and stripped from the topic path  @components/proxmox/command.ps1:184
    config  (subcommand/bare)  routes to the PMX configuration sub-router  @components/proxmox/command.ps1:191 [also: CONFIG Config] [docs say: pmx config show]
    discover  (subcommand/bare)  one-shot read of nodes, storage, bridges, VMIDs and next free ID  @components/proxmox/command.ps1:192 [docs say: pmx discover [--json|--table]]
    node  (subcommand/bare)  node group; bare `pmx node` defaults to the status action  @components/proxmox/command.ps1:193 [docs say: pmx node status [--json|--table]]
    status  (subcommand/bare)  the ONLY accepted node action; any other word is a hard error  @components/proxmox/command.ps1:194 [docs say: pmx node status]
    storage  (subcommand/bare)  storage group; bare on a Proxmox host prints local pools, otherwise defaults to list  @components/proxmox/command.ps1:201 [docs say: pmx storage list [--json|--table]]
    list  (subcommand/bare)  the ONLY accepted storage action; any other word is a hard error  @components/proxmox/command.ps1:206 [docs say: pmx storage list]
    vm  (subcommand/bare)  routes to the VM sub-router  @components/proxmox/command.ps1:213 [also: VM Vm] [docs say: pmx vm list]
    snapshot  (subcommand/bare)  routes to the snapshot sub-router  @components/proxmox/command.ps1:214 [docs say: pmx snapshot list --vm <name|vmid>]
    disk  (subcommand/bare)  disk group: `list`/`grow` are virtual-disk routes, anything else falls through to the physical-disk router  @components/proxmox/command.ps1:215 [docs say: pmx disk <device|serial>]
    list  (subcommand/bare)  virtual disks of one VM (branches away from the physical-disk router)  @components/proxmox/command.ps1:217 [docs say: pmx disk list --vm <name|vmid>]
    grow  (subcommand/bare)  virtual-disk growth route  @components/proxmox/command.ps1:221 [docs say: pmx disk grow <name|vmid> <size>]
    disks  (subcommand/bare)  physical disk inventory; rejects every argument except the hoisted help tokens  @components/proxmox/command.ps1:227 [docs say: pmx disks]
    pools  (subcommand/bare)  local storage/ZFS pools; rejects every argument, including --json  @components/proxmox/command.ps1:231 [docs say: pmx pools]
    guests  (subcommand/bare)  local guest inventory; rejects every argument, including --json  @components/proxmox/command.ps1:235 [docs say: pmx guests]
    guest  (subcommand/bare)  one local guest; accepts at most one positional  @components/proxmox/command.ps1:239 [docs say: pmx guest [vmid|name]]
    101  (positional/value)  guest id or name, matched case-insensitively against id and name (host.ps1:43)  @components/proxmox/command.ps1:242 [also: docker-host DOCKER-HOST] [docs say: [vmid|name]]
    updates  (subcommand/bare)  pending Proxmox updates; rejects every argument, including --json  @components/proxmox/command.ps1:245 [docs say: pmx updates]

pmx vm  [hand-parsed-args]  components/proxmox/command.ps1
    list  (subcommand/bare)  VM inventory; also the default when no action word is given  @components/proxmox/command.ps1:116 [also: LIST List] [docs say: pmx vm [list]]
    show  (subcommand/bare)  full VM detail view  @components/proxmox/command.ps1:117 [docs say: pmx vm show <name|vmid>]
    status  (subcommand/bare)  power/runtime subset of show (-StatusOnly)  @components/proxmox/command.ps1:118 [docs say: pmx vm status <name|vmid>]
    next-id  (subcommand/bare)  next available VMID from Proxmox  @components/proxmox/command.ps1:119 [docs say: pmx vm next-id]
    network  (subcommand/bare)  network sub-router (combined view by default)  @components/proxmox/command.ps1:120 [docs say: pmx vm network <name|vmid>]
    net  (subcommand/bare)  exact synonym of `network`, same sub-router  @components/proxmox/command.ps1:121 [docs say: alias: pmx vm net]
    nic  (subcommand/bare)  jumps straight to the adapters view; does NOT accept the net sub-words  @components/proxmox/command.ps1:122 [docs say: alias: pmx vm nic]
    ip  (subcommand/bare)  jumps straight to the addresses view; does NOT accept the net sub-words  @components/proxmox/command.ps1:123 [docs say: pmx vm ip <name>]
    clone  (subcommand/bare)  template clone route  @components/proxmox/command.ps1:124 [docs say: pmx vm clone <template> <name>]
    start  (subcommand/bare)  start a stopped VM  @components/proxmox/command.ps1:125 [docs say: pmx vm start <name|vmid>]
    shutdown  (subcommand/bare)  graceful ACPI shutdown  @components/proxmox/command.ps1:126 [docs say: pmx vm shutdown <name|vmid>]
    set-cpu  (subcommand/bare)  compatibility spelling of `cpu set`; reaches the setter WITHOUT the optional-`set` normaliser  @components/proxmox/command.ps1:127 [docs say: alias: pmx vm set-cpu]
    set-memory  (subcommand/bare)  compatibility spelling of `memory set`; reaches the setter WITHOUT the optional-`set` normaliser  @components/proxmox/command.ps1:128 [docs say: alias: pmx vm set-memory]
    cpu  (subcommand/bare)  cores setter with optional `set` word and promotable positional value  @components/proxmox/command.ps1:132 [docs say: pmx vm cpu set <name|vmid> --cores <number>]
    memory  (subcommand/bare)  memory setter with optional `set` word and promotable positional value  @components/proxmox/command.ps1:133 [docs say: pmx vm memory set <name|vmid> --size <size>]
    set  (subcommand/bare)  OPTIONAL filler word stripped after `cpu`/`memory` only (not after set-cpu/set-memory)  @components/proxmox/command.ps1:86 [also: SET Set] [docs say: pmx vm cpu set <vmid|name>]

pmx disk <device|serial>  [hand-parsed-args]  components/proxmox/command.ps1
    sda  (positional/value)  physical-disk selector matched case-insensitively on name/path/serial/stable-id (physical-disks.ps1:40-44); empty opens an fzf picker  @components/proxmox/command.ps1:47 [also: /dev/sda SDA <serial> /dev/disk/by-id/<id>] [docs say: pmx disk <device|serial>]
    smart  (subcommand/bare)  SMART summary; identical to the empty action  @components/proxmox/command.ps1:59 [also: SMART Smart] [docs say: pmx disk <device|serial> [smart]]
    test  (subcommand/bare)  launch a SMART self-test, kind taken from the third positional  @components/proxmox/command.ps1:60 [docs say: pmx disk <device> test short|long]
    report  (subcommand/bare)  authenticity/health evidence view  @components/proxmox/command.ps1:61 [docs say: pmx disk <device|serial> report [-Write]]
    evidence  (subcommand/bare)  undocumented-in-overview synonym of `report` (named as an alias only in the help topic, help.ps1:283)  @components/proxmox/command.ps1:62 [docs say: alias: evidence]
    capacity-test  (subcommand/bare)  destructive F3 gate; explains itself unless -destroy is present  @components/proxmox/command.ps1:63 [docs say: pmx disk <device|serial> capacity-test [-Destroy]]
    -full  (hand-parsed/-long)  full smartctl -x dump instead of the summary; only read by the smart/empty actions  @components/proxmox/command.ps1:23 [also: -Full -FULL -fUlL] [docs say: -Full]
    -write  (hand-parsed/-long)  writes the evidence bundle to ~/pmx-reports; only read by report/evidence  @components/proxmox/command.ps1:23 [also: -Write -WRITE] [docs say: -Write]
    -destroy  (hand-parsed/-long)  arms the destructive capacity test; only read by capacity-test  @components/proxmox/command.ps1:23 [also: -Destroy -DESTROY] [docs say: -Destroy]

pmx disk <device> test  [hand-parsed-args]  components/proxmox/physical-disks.ps1
    short  (positional/value)  short SMART self-test  @components/proxmox/physical-disks.ps1:159 [also: SHORT Short] [docs say: short|long]
    long  (positional/value)  long SMART self-test  @components/proxmox/physical-disks.ps1:159 [also: LONG Long] [docs say: short|long]
    extended  (positional/value)  accepted alias normalised to `long`  @components/proxmox/physical-disks.ps1:158 [also: EXTENDED Extended] [docs say: Compatibility: extended is accepted as an alias of long.]

pmx snapshot  [hand-parsed-args]  components/proxmox/command.ps1
    list  (subcommand/bare)  list snapshots; also the default when no action word is given (but then errors for a missing --vm)  @components/proxmox/command.ps1:144 [also: LIST] [docs say: pmx snapshot list --vm <name|vmid>]
    create  (subcommand/bare)  create a named snapshot  @components/proxmox/command.ps1:145 [docs say: pmx snapshot create --vm <name|vmid> --name <snapshot>]

pmx config  [hand-parsed-args]  components/proxmox/config.ps1
    show  (subcommand/bare)  print the config table; also the default action  @components/proxmox/config.ps1:421 [also: SHOW] [docs say: pmx config show [--json|--table]]
    set  (subcommand/bare)  change one setting; takes EXACTLY two positionals and accepts only --help  @components/proxmox/config.ps1:422 [docs say: pmx config set <setting> <value>]
    reset  (subcommand/bare)  restore one setting or all; takes exactly one positional and accepts only --help  @components/proxmox/config.ps1:430 [docs say: pmx config reset <setting|all>]
    validate  (subcommand/bare)  probe the transport and node; accepts only --help  @components/proxmox/config.ps1:438 [docs say: pmx config validate]
    discover  (subcommand/bare)  same handler as top-level `pmx discover`  @components/proxmox/config.ps1:446 [docs say: pmx config discover [--json|--table]]
    --help  (hand-parsed/--long)  the ONLY option set/reset/validate accept (--json/--table/--dry-run are rejected as unknown here, unlike config show)  @components/proxmox/config.ps1:423
    host  (positional/value)  setting name: srv alias to connect through  @components/proxmox/config.ps1:43 [also: HOST  host ] [docs say: pmx config set host proxmox]
    node  (positional/value)  setting name: `auto` or a node name  @components/proxmox/config.ps1:44 [docs say: pmx config set node <name>]
    transport  (positional/value)  setting name: auto|local|ssh  @components/proxmox/config.ps1:45 [docs say: pmx config set transport ssh]
    output  (positional/value)  setting name: table|json default output mode  @components/proxmox/config.ps1:46 [docs say: pmx config set output <table|json>]
    show-native  (positional/value)  setting name: boolean, permanently enables native-command echo  @components/proxmox/config.ps1:47 [docs say: pmx config set show-native true]
    explain  (positional/value)  setting name: boolean, extra educational warnings  @components/proxmox/config.ps1:48
    confirmation  (positional/value)  setting name: accepts only `risk-based`  @components/proxmox/config.ps1:49
    audit-log  (positional/value)  setting name: boolean, JSONL audit writing  @components/proxmox/config.ps1:50
    timeout-seconds  (positional/value)  setting name: integer 5..600  @components/proxmox/config.ps1:51
    all  (positional/value)  reset-only sentinel restoring every default  @components/proxmox/config.ps1:240 [also: ALL All] [docs say: pmx config reset <setting|all>]
    true  (positional/value)  boolean value for show-native/explain/audit-log  @components/proxmox/config.ps1:71 [also: on yes 1 TRUE On YES]
    false  (positional/value)  boolean value for show-native/explain/audit-log  @components/proxmox/config.ps1:74 [also: off no 0 FALSE Off NO]

pmx (shared option parser)  [hand-parsed-args]  components/proxmox/shared.ps1
    --  (hand-parsed/--long)  end-of-options: every later token becomes a positional (case-sensitive -ceq)  @components/proxmox/shared.ps1:104
    -  (positional/value)  a bare single dash is the one dash-led token allowed through as a positional  @components/proxmox/shared.ps1:162
    --vm=101  (hand-parsed/--long)  inline `--name=value` form accepted for EVERY value option; switches reject `=` with 'does not take a value'  @components/proxmox/shared.ps1:108 [also: --cores=4 --size=8G --to=100G --name=web --source=debian-base]
    --help  (hand-parsed/--long)  global switch map entry; long options are lowercase-exact (-cnotmatch at line 112) so --Help is 'invalid option' when it reaches this parser  @components/proxmox/shared.ps1:74
    --explain  (hand-parsed/--long)  global switch map entry; only actually read by clone, disk grow and the network views  @components/proxmox/shared.ps1:75
    --dry-run  (hand-parsed/--long)  global switch map entry; only read by the amber mutation path, silently ignored by every read command  @components/proxmox/shared.ps1:76
    --show-native  (hand-parsed/--long)  global switch map entry; only read by the amber mutation path and the network views  @components/proxmox/shared.ps1:77
    --json  (hand-parsed/--long)  global switch map entry; read only where Get-PmxOutputMode is called, accepted-and-ignored elsewhere  @components/proxmox/shared.ps1:78 [docs say: --json/-j]
    --table  (hand-parsed/--long)  global switch map entry; mutually exclusive with --json (shared.ps1:262)  @components/proxmox/shared.ps1:79 [docs say: --table/-t]
    8G  (positional/value)  size grammar for --size/--to and their positional forms: whole number plus M/MB/MIB/G/GB/GIB/T/TB/TIB, case-insensitive  @components/proxmox/shared.ps1:195 [also: 8g 8GB 8GiB 8gib 512M 2T 2tb] [docs say: <MiB|GiB|TiB>]

pmx vm list  [hand-parsed-args]  components/proxmox/vm-read.ps1
    --json  (hand-parsed/--long)  emits the VM rows as JSON  @components/proxmox/vm-read.ps1:135 [docs say: pmx vm [list] [--json|--table]]
    --table  (hand-parsed/--long)  forces the table view over a saved json default  @components/proxmox/vm-read.ps1:135 [docs say: [--json|--table]]
    --help  (hand-parsed/--long)  shows the `vm list` topic (in practice intercepted by the router hoist first)  @components/proxmox/vm-read.ps1:135
    --explain  (hand-parsed/--long)  accepted, parsed, never read by this view  @components/proxmox/vm-read.ps1:135
    --dry-run  (hand-parsed/--long)  accepted, parsed, never read by this view  @components/proxmox/vm-read.ps1:135
    --show-native  (hand-parsed/--long)  accepted, parsed, never read by this view  @components/proxmox/vm-read.ps1:135
    --vm  (hand-parsed/--long)  accepted as a value option here (RequireSelector is off) but the value is never used — `pmx vm list --vm 101` silently ignores it  @components/proxmox/vm-read.ps1:133

pmx vm show  [hand-parsed-args]  components/proxmox/vm-read.ps1
    101  (positional/value)  the ONLY way to name the VM here: VMID matched case-sensitively, name matched OrdinalIgnoreCase; --vm is rejected as an unknown option because PositionalSelectorOnly empties the value map  @components/proxmox/vm-read.ps1:198 [also: docker-host DOCKER-HOST] [docs say: pmx vm show <vmid|name>]
    --json  (hand-parsed/--long)  JSON detail contract  @components/proxmox/vm-read.ps1:135 [docs say: [--json|--table]]
    --table  (hand-parsed/--long)  forces table output  @components/proxmox/vm-read.ps1:135 [docs say: [--json|--table]]
    --help  (hand-parsed/--long)  shows the `vm show`/`vm status` topic  @components/proxmox/vm-read.ps1:135
    --explain  (hand-parsed/--long)  accepted, never read by this view  @components/proxmox/vm-read.ps1:135
    --dry-run  (hand-parsed/--long)  accepted, never read by this view  @components/proxmox/vm-read.ps1:135
    --show-native  (hand-parsed/--long)  accepted, never read by this view  @components/proxmox/vm-read.ps1:135

pmx vm status  [hand-parsed-args]  components/proxmox/vm-read.ps1
    101  (positional/value)  positional-only VM selector; omitting it opens the fzf picker (vm-read.ps1:63)  @components/proxmox/vm-read.ps1:198 [also: debian13-lab] [docs say: pmx vm status <vmid|name>]
    --json  (hand-parsed/--long)  emits only the status object  @components/proxmox/vm-read.ps1:135 [docs say: [--json|--table]]
    --table  (hand-parsed/--long)  forces table output  @components/proxmox/vm-read.ps1:135
    --help  (hand-parsed/--long)  shows the `vm status` topic  @components/proxmox/vm-read.ps1:135
    --explain  (hand-parsed/--long)  accepted, never read  @components/proxmox/vm-read.ps1:135
    --dry-run  (hand-parsed/--long)  accepted, never read  @components/proxmox/vm-read.ps1:135
    --show-native  (hand-parsed/--long)  accepted, never read  @components/proxmox/vm-read.ps1:135

pmx vm next-id  [hand-parsed-args]  components/proxmox/vm-read.ps1
    --json  (hand-parsed/--long)  emits {vmid:<n>}  @components/proxmox/vm-read.ps1:135 [docs say: pmx vm next-id [--json|--table]]
    --table  (hand-parsed/--long)  forces the one-line text form  @components/proxmox/vm-read.ps1:135
    --help  (hand-parsed/--long)  shows the `vm next-id` topic  @components/proxmox/vm-read.ps1:135
    --explain  (hand-parsed/--long)  accepted, never read  @components/proxmox/vm-read.ps1:135
    --dry-run  (hand-parsed/--long)  accepted, never read  @components/proxmox/vm-read.ps1:135
    --show-native  (hand-parsed/--long)  accepted, never read  @components/proxmox/vm-read.ps1:135
    --vm  (hand-parsed/--long)  accepted as a value option and then ignored entirely  @components/proxmox/vm-read.ps1:133

pmx disk list  [hand-parsed-args]  components/proxmox/vm-read.ps1
    --vm  (hand-parsed/--long)  names the VM whose virtual disks are listed; supplying BOTH --vm and a positional is an error  @components/proxmox/vm-read.ps1:133 [also: --vm=101] [docs say: pmx disk list --vm <name|vmid>]
    101  (positional/value)  positional alternative to --vm; omitting both opens the VM picker  @components/proxmox/vm-read.ps1:145 [docs say: pmx disk list <vmid|name>]
    --json  (hand-parsed/--long)  emits the parsed disk rows  @components/proxmox/vm-read.ps1:135 [docs say: [--json|--table]]
    --table  (hand-parsed/--long)  forces the disk table  @components/proxmox/vm-read.ps1:135
    --help  (hand-parsed/--long)  shows the `disk list` topic  @components/proxmox/vm-read.ps1:135
    --explain  (hand-parsed/--long)  accepted, never read  @components/proxmox/vm-read.ps1:135
    --dry-run  (hand-parsed/--long)  accepted, never read  @components/proxmox/vm-read.ps1:135
    --show-native  (hand-parsed/--long)  accepted, never read  @components/proxmox/vm-read.ps1:135

pmx vm clone  [hand-parsed-args]  components/proxmox/vm-change.ps1
    debian-base  (positional/value)  positional 1 = source template; 2 positionals mean <template> <name>, 3 mean <template> <new-vmid> <name>  @components/proxmox/vm-change.ps1:154 [docs say: pmx vm clone <template> <dns-name>]
    docker-host  (positional/value)  new VM name, validated as a lowercase DNS-style label (Test-PmxGuestName, shared.ps1:283)  @components/proxmox/vm-change.ps1:161 [docs say: <dns-name>]
    --source  (hand-parsed/--long)  script-friendly source template; cannot be mixed with positionals  @components/proxmox/vm-change.ps1:125 [also: --source=debian-base --source-vmid] [docs say: pmx vm clone --source <template> --name <dns-name>]
    --source-vmid  (hand-parsed/--long)  compatibility alias writing the same Source slot; using both spellings errors as a duplicate  @components/proxmox/vm-change.ps1:125 [docs say: Compatibility: --source-vmid is accepted as an alias of --source.]
    --new-vmid  (hand-parsed/--long)  explicit target VMID or the literal `auto`; defaults to auto when absent  @components/proxmox/vm-change.ps1:125 [docs say: --new-vmid must be auto or an integer from 100 to 999999999]
    auto  (positional/value)  the only non-numeric value --new-vmid accepts  @components/proxmox/vm-change.ps1:190
    --name  (hand-parsed/--long)  new VM name in the flag form  @components/proxmox/vm-change.ps1:125 [docs say: --name <dns-name>]
    --full  (hand-parsed/--long)  accepted for backward compatibility and DEAD — Options.Full is never read and Full=$true is hardcoded; deliberately absent from all help text  @components/proxmox/vm-change.ps1:123
    --dry-run  (hand-parsed/--long)  prints the amber plan and the clone placement, then stops without changing state  @components/proxmox/vm-change.ps1:126 [docs say: [--dry-run]]
    --show-native  (hand-parsed/--long)  reveals the translated `qm clone ...` line in the plan  @components/proxmox/vm-change.ps1:126 [docs say: Add --show-native to reveal those translations.]
    --explain  (hand-parsed/--long)  adds placement/provisioning caveats to the plan warnings  @components/proxmox/vm-change.ps1:126
    --json  (hand-parsed/--long)  suppresses the placement table and emits the clone contract afterwards  @components/proxmox/vm-change.ps1:126
    --table  (hand-parsed/--long)  forces the human plan over a saved json default  @components/proxmox/vm-change.ps1:126
    --help  (hand-parsed/--long)  shows the `vm clone` topic  @components/proxmox/vm-change.ps1:126

pmx vm cpu set  [hand-parsed-args]  components/proxmox/vm-change.ps1
    --help  (hand-parsed/--long)  scanned by exact case-sensitive string compare BEFORE parsing, so `--HELP` would not match here (the router hoist catches it first)  @components/proxmox/vm-change.ps1:301
    --cores  (hand-parsed/--long)  cores per socket, integer 1..1024  @components/proxmox/vm-change.ps1:302 [also: --cores=4] [docs say: pmx vm cpu set <vmid|name> --cores <number>]
    101  (positional/value)  positional 1 = VM; with two positionals the second is promoted to --cores  @components/proxmox/vm-change.ps1:286 [docs say: pmx vm cpu set <vmid|name> <number>]
    4  (positional/value)  positional 2 = core count (promoted to --cores by the router at command.ps1:132 or accepted directly here)  @components/proxmox/vm-change.ps1:290 [docs say: <number>]
    --dry-run  (hand-parsed/--long)  plan-only, writes a dry-run audit record  @components/proxmox/vm-change.ps1:282 [docs say: [--dry-run]]
    --show-native  (hand-parsed/--long)  shows the `qm set <vmid> --cores <n> --digest <sha1>` translation  @components/proxmox/vm-change.ps1:282
    --explain  (hand-parsed/--long)  accepted; this command adds its socket-maths warning unconditionally  @components/proxmox/vm-change.ps1:282
    --json  (hand-parsed/--long)  accepted and completely ignored — Get-PmxOutputMode is never called on this path  @components/proxmox/vm-change.ps1:282
    --table  (hand-parsed/--long)  accepted and completely ignored on this path  @components/proxmox/vm-change.ps1:282

pmx vm memory set  [hand-parsed-args]  components/proxmox/vm-change.ps1
    --help  (hand-parsed/--long)  exact case-sensitive pre-parse scan for the `vm memory set` topic  @components/proxmox/vm-change.ps1:349
    --size  (hand-parsed/--long)  memory size, at least 16 MiB and a whole MiB multiple  @components/proxmox/vm-change.ps1:350 [also: --size=8G] [docs say: pmx vm memory set <vmid|name> --size <MiB|GiB|TiB>]
    101  (positional/value)  positional 1 = VM  @components/proxmox/vm-change.ps1:286 [docs say: pmx vm memory set <vmid|name> <size>]
    8G  (positional/value)  positional 2 = size, promoted to --size  @components/proxmox/vm-change.ps1:290 [also: 8GiB 8gb 8192M] [docs say: <size>]
    --dry-run  (hand-parsed/--long)  plan-only  @components/proxmox/vm-change.ps1:282 [docs say: [--dry-run]]
    --show-native  (hand-parsed/--long)  shows the `qm set <vmid> --memory <MiB> --digest <sha1>` translation  @components/proxmox/vm-change.ps1:282
    --explain  (hand-parsed/--long)  accepted; unit-translation warning is emitted unconditionally  @components/proxmox/vm-change.ps1:282
    --json  (hand-parsed/--long)  accepted and completely ignored on this path  @components/proxmox/vm-change.ps1:282
    --table  (hand-parsed/--long)  accepted and completely ignored on this path  @components/proxmox/vm-change.ps1:282

pmx vm start  [hand-parsed-args]  components/proxmox/vm-change.ps1
    --help  (hand-parsed/--long)  exact case-sensitive pre-parse scan for the `vm start` topic  @components/proxmox/vm-change.ps1:400
    debian13-lab  (positional/value)  positional-only VM selector (--vm is rejected here); omitting it opens the picker  @components/proxmox/vm-change.ps1:392 [docs say: pmx vm start <vmid|name>]
    --dry-run  (hand-parsed/--long)  plan-only  @components/proxmox/vm-change.ps1:135 [docs say: [--dry-run]]
    --show-native  (hand-parsed/--long)  shows the `qm start <vmid>` translation  @components/proxmox/vm-change.ps1:135
    --explain  (hand-parsed/--long)  accepted, never read on this path  @components/proxmox/vm-change.ps1:135
    --json  (hand-parsed/--long)  accepted and completely ignored on this path  @components/proxmox/vm-change.ps1:135
    --table  (hand-parsed/--long)  accepted and completely ignored on this path  @components/proxmox/vm-change.ps1:135

pmx vm shutdown  [hand-parsed-args]  components/proxmox/vm-change.ps1
    --help  (hand-parsed/--long)  exact case-sensitive pre-parse scan for the `vm shutdown` topic  @components/proxmox/vm-change.ps1:400
    debian13-lab  (positional/value)  positional-only VM selector; omitting it opens the picker  @components/proxmox/vm-change.ps1:392 [docs say: pmx vm shutdown <vmid|name>]
    --dry-run  (hand-parsed/--long)  plan-only  @components/proxmox/vm-change.ps1:135 [docs say: [--dry-run]]
    --show-native  (hand-parsed/--long)  shows the `qm shutdown <vmid>` translation  @components/proxmox/vm-change.ps1:135
    --explain  (hand-parsed/--long)  accepted, never read on this path  @components/proxmox/vm-change.ps1:135
    --json  (hand-parsed/--long)  accepted and completely ignored on this path  @components/proxmox/vm-change.ps1:135
    --table  (hand-parsed/--long)  accepted and completely ignored on this path  @components/proxmox/vm-change.ps1:135

pmx disk grow  [hand-parsed-args]  components/proxmox/disk-grow.ps1
    --help  (hand-parsed/--long)  exact case-sensitive pre-parse scan for the `disk grow` topic  @components/proxmox/disk-grow.ps1:123
    --vm  (hand-parsed/--long)  VM selector; the three named options must be used as a complete set and never mixed with positionals  @components/proxmox/disk-grow.ps1:17 [docs say: pmx disk grow --vm <name|vmid> --disk <slot> --to <size>]
    --disk  (hand-parsed/--long)  disk slot, must match ^(ide|sata|scsi|virtio)[0-9]+$ case-SENSITIVELY (so `SCSI0` is refused)  @components/proxmox/disk-grow.ps1:17 [docs say: --disk <slot>]
    --to  (hand-parsed/--long)  final size — a third name for 'the new value' alongside --size and --cores  @components/proxmox/disk-grow.ps1:17 [docs say: --to <size>]
    101  (positional/value)  positional 1 = VM; two positionals mean <vm> <size> with auto disk selection, three mean <vm> <disk> <size>  @components/proxmox/disk-grow.ps1:30 [docs say: pmx disk grow <name|vmid> <size>]
    scsi1  (positional/value)  positional 2 of 3 = explicit disk slot, lowercase only  @components/proxmox/disk-grow.ps1:37 [docs say: pmx disk grow <name|vmid> <slot> <size>]
    100G  (positional/value)  final target size, never a delta and never a shrink  @components/proxmox/disk-grow.ps1:38 [also: 100GiB 3TiB 100g] [docs say: <size>]
    --dry-run  (hand-parsed/--long)  plan-only  @components/proxmox/disk-grow.ps1:18 [docs say: [--dry-run]]
    --show-native  (hand-parsed/--long)  shows the `qm disk resize ... +<delta> --digest <sha1>` translation  @components/proxmox/disk-grow.ps1:18
    --explain  (hand-parsed/--long)  adds the delta-calculation and thin-pool caveats  @components/proxmox/disk-grow.ps1:18
    --json  (hand-parsed/--long)  accepted and completely ignored on this path  @components/proxmox/disk-grow.ps1:18
    --table  (hand-parsed/--long)  accepted and completely ignored on this path  @components/proxmox/disk-grow.ps1:18

pmx snapshot list  [hand-parsed-args]  components/proxmox/snapshots.ps1
    --help  (hand-parsed/--long)  exact case-sensitive pre-parse scan for the `snapshot list` topic  @components/proxmox/snapshots.ps1:64
    --vm  (hand-parsed/--long)  REQUIRED VM selector (named or positional) — there is no picker fallback here, unlike vm show/status/start/shutdown  @components/proxmox/snapshots.ps1:39 [docs say: pmx snapshot list --vm <name|vmid>]
    101  (positional/value)  positional alternative to --vm; mixing the two forms errors  @components/proxmox/snapshots.ps1:52 [docs say: pmx snapshot list <vmid|name>]
    --json  (hand-parsed/--long)  emits the snapshot rows  @components/proxmox/snapshots.ps1:43 [docs say: [--json|--table]]
    --table  (hand-parsed/--long)  forces the snapshot table  @components/proxmox/snapshots.ps1:43
    --explain  (hand-parsed/--long)  accepted, never read  @components/proxmox/snapshots.ps1:43
    --dry-run  (hand-parsed/--long)  accepted, never read  @components/proxmox/snapshots.ps1:43
    --show-native  (hand-parsed/--long)  accepted, never read  @components/proxmox/snapshots.ps1:43

pmx snapshot create  [hand-parsed-args]  components/proxmox/snapshots.ps1
    --help  (hand-parsed/--long)  exact case-sensitive pre-parse scan for the `snapshot create` topic  @components/proxmox/snapshots.ps1:93
    --vm  (hand-parsed/--long)  required VM selector  @components/proxmox/snapshots.ps1:39 [docs say: pmx snapshot create --vm <name|vmid> --name <snapshot>]
    --name  (hand-parsed/--long)  required snapshot name; letters/digits/_/-, max 40, not `current`/`pending`  @components/proxmox/snapshots.ps1:40 [docs say: --name <snapshot>]
    101  (positional/value)  positional 1 = VM; both positionals must be given together or neither  @components/proxmox/snapshots.ps1:52 [docs say: pmx snapshot create <vmid|name> <snapshot>]
    pre-docker  (positional/value)  positional 2 = snapshot name  @components/proxmox/snapshots.ps1:53 [docs say: <snapshot>]
    --dry-run  (hand-parsed/--long)  plan-only  @components/proxmox/snapshots.ps1:43 [docs say: [--dry-run]]
    --show-native  (hand-parsed/--long)  shows the `qm snapshot <vmid> <name>` translation  @components/proxmox/snapshots.ps1:43
    --explain  (hand-parsed/--long)  accepted, never read  @components/proxmox/snapshots.ps1:43
    --json  (hand-parsed/--long)  accepted and completely ignored on this path  @components/proxmox/snapshots.ps1:43
    --table  (hand-parsed/--long)  accepted and completely ignored on this path  @components/proxmox/snapshots.ps1:43

pmx vm network  [hand-parsed-args]  components/proxmox/network-read.ps1
    adapters  (subcommand/bare)  configured-NIC view; also reachable as `pmx vm nic`  @components/proxmox/network-read.ps1:276 [also: ADAPTERS] [docs say: pmx vm network adapters <name|vmid>]
    addresses  (subcommand/bare)  VM-reported address view; also reachable as `pmx vm ip`  @components/proxmox/network-read.ps1:277 [docs say: pmx vm network addresses <name|vmid>]
    stats  (subcommand/bare)  traffic-counter view  @components/proxmox/network-read.ps1:278 [docs say: pmx vm net stats <vmid|name>]
    list  (subcommand/bare)  fleet-wide network summary; also the behaviour of a bare `pmx vm net`  @components/proxmox/network-read.ps1:279 [docs say: pmx vm network list]
    101  (positional/value)  REQUIRED VM selector for every non-list view — omitting it errors instead of opening the picker the other VM commands use  @components/proxmox/network-read.ps1:50 [also: docker-host] [docs say: pmx vm network <vmid|name>]
    --table  (hand-parsed/--long)  forces the table view  @components/proxmox/network-read.ps1:39 [docs say: [--table|-t|--json|-j]]
    -t  (hand-parsed/-short)  case-SENSITIVE pre-map to --table; exists ONLY on the network routes  @components/proxmox/network-read.ps1:21
    --json  (hand-parsed/--long)  emits the network contract  @components/proxmox/network-read.ps1:39 [docs say: [--json|-j]]
    -j  (hand-parsed/-short)  case-SENSITIVE pre-map to --json; `-J` falls through as an unknown option  @components/proxmox/network-read.ps1:22
    --ipv4  (hand-parsed/--long)  restrict addresses to IPv4; rejected for the adapters/stats views  @components/proxmox/network-read.ps1:39 [docs say: [--ipv4|-4|--ipv6|-6]]
    -4  (hand-parsed/-short)  case-sensitive pre-map to --ipv4  @components/proxmox/network-read.ps1:23
    --ipv6  (hand-parsed/--long)  restrict addresses to IPv6; rejected for the adapters/stats views  @components/proxmox/network-read.ps1:40 [docs say: [--ipv6|-6]]
    -6  (hand-parsed/-short)  case-sensitive pre-map to --ipv6  @components/proxmox/network-read.ps1:24
    --all  (hand-parsed/--long)  disable scope filtering entirely; rejected for the adapters/stats views  @components/proxmox/network-read.ps1:39 [docs say: [--all|--include-loopback]]
    --include-loopback  (hand-parsed/--long)  keep loopback addresses; rejected for the adapters/stats views  @components/proxmox/network-read.ps1:40 [docs say: [--all|--include-loopback]]
    --explain  (hand-parsed/--long)  adds the source/inference explanations to the view and the JSON contract  @components/proxmox/network-read.ps1:38
    --show-native  (hand-parsed/--long)  reveals the translated configured/agent reads  @components/proxmox/network-read.ps1:38 [docs say: Add --show-native to reveal the translated VM-agent read.]
    --help  (hand-parsed/--long)  shows the matching `vm network …` topic  @components/proxmox/network-read.ps1:38

pmx node status  [hand-parsed-args]  components/proxmox/host.ps1
    --json  (hand-parsed/--long)  emits the raw node-status object  @components/proxmox/host.ps1:125 [docs say: pmx node status [--json|--table]]
    --table  (hand-parsed/--long)  forces the field view  @components/proxmox/host.ps1:125
    --help  (hand-parsed/--long)  shows the `node status` topic  @components/proxmox/host.ps1:125
    --explain  (hand-parsed/--long)  accepted, never read  @components/proxmox/host.ps1:125
    --dry-run  (hand-parsed/--long)  accepted, never read  @components/proxmox/host.ps1:125
    --show-native  (hand-parsed/--long)  accepted, never read  @components/proxmox/host.ps1:125

pmx storage list  [hand-parsed-args]  components/proxmox/host.ps1
    --json  (hand-parsed/--long)  emits the storage rows  @components/proxmox/host.ps1:125 [docs say: pmx storage list [--json|--table]]
    --table  (hand-parsed/--long)  forces the storage table  @components/proxmox/host.ps1:125
    --help  (hand-parsed/--long)  shows the `storage list` topic  @components/proxmox/host.ps1:125
    --explain  (hand-parsed/--long)  accepted, never read  @components/proxmox/host.ps1:125
    --dry-run  (hand-parsed/--long)  accepted, never read  @components/proxmox/host.ps1:125
    --show-native  (hand-parsed/--long)  accepted, never read  @components/proxmox/host.ps1:125

pmx discover  [hand-parsed-args]  components/proxmox/host.ps1
    --json  (hand-parsed/--long)  emits the discovery contract  @components/proxmox/host.ps1:125 [docs say: pmx discover --json]
    --table  (hand-parsed/--long)  forces the field view  @components/proxmox/host.ps1:125 [docs say: [--json|--table]]
    --help  (hand-parsed/--long)  shows the `discover` topic  @components/proxmox/host.ps1:125
    --explain  (hand-parsed/--long)  accepted, never read  @components/proxmox/host.ps1:125
    --dry-run  (hand-parsed/--long)  accepted, never read  @components/proxmox/host.ps1:125
    --show-native  (hand-parsed/--long)  accepted, never read  @components/proxmox/host.ps1:125

pmx config show  [hand-parsed-args]  components/proxmox/config.ps1
    --json  (hand-parsed/--long)  emits the settings map; works here but is REJECTED by config set/reset/validate  @components/proxmox/config.ps1:389 [docs say: pmx config show [--json|--table]]
    --table  (hand-parsed/--long)  forces the field view  @components/proxmox/config.ps1:389
    --help  (hand-parsed/--long)  shows the `config show` topic  @components/proxmox/config.ps1:389
    --explain  (hand-parsed/--long)  accepted, never read  @components/proxmox/config.ps1:389
    --dry-run  (hand-parsed/--long)  accepted, never read  @components/proxmox/config.ps1:389
    --show-native  (hand-parsed/--long)  accepted, never read  @components/proxmox/config.ps1:389
```

### System, network and git

```text
installed-apps  [param-block]  components/system/apps.ps1
    -o  (param-switch/-short)  band overview across everything installed, then drill into one band without rescanning  @components/system/apps.ps1:272 [also: -O]
    -Overview  (param-switch/param-derived)  same as -o; the real parameter name that -o is an [Alias] for  @components/system/apps.ps1:272 [also: -overview -OVERVIEW -Overvie any unambiguous prefix EXCEPT -Ov, which errors against -OutVariable]
    -Measure  (param-switch/param-derived)  passes -Measure to Get-InstalledApplication so folder sizes are walked rather than read from the registry  @components/system/apps.ps1:273 [also: -measure -M -m -Meas]
    <range>  (positional/value)  size band, e.g. 2gb-4gb; must fit entirely inside one band and sit at/above the 1 GB floor  @components/system/apps.ps1:271 [also: -Range 2gb-4gb -R 2gb-4gb -range 2gb-4gb] [docs say: i-a 2gb-4gb]

i-a  [param-block]  components/system/apps.ps1
    -o  (param-switch/-short)  Set-Alias to installed-apps, so every parameter forwards untouched  @components/system/apps.ps1:327 [also: -O -Overview -overview] [docs say: i-a -o]
    -Measure  (param-switch/param-derived)  forwarded to installed-apps  @components/system/apps.ps1:327 [also: -M -m -measure]
    <range>  (positional/value)  forwarded to installed-apps -Range  @components/system/apps.ps1:327 [docs say: i-a 2gb-4gb]

disk-big  [param-block]  components/system/apps.ps1
    <range>  (positional/value)  size band, e.g. 50gb-200gb; no range opens the interactive band menu  @components/system/apps.ps1:346 [also: -Range 50gb-200gb -R 50gb-200gb] [docs say: d-b 50gb-200gb]
    -Path  (param-switch/param-derived)  value param (not a switch): scan this one root instead of Get-DiskHotspot's list  @components/system/apps.ps1:347 [also: -path -p -Pa -PATH] [docs say: disk-big 1gb-5gb -Path D:\ (in-code hint at line 404 only; absent from Register-PFCommand)]

d-b  [param-block]  components/system/apps.ps1
    <range>  (positional/value)  Set-Alias to disk-big; parameters forward untouched  @components/system/apps.ps1:328 [docs say: d-b 50gb-200gb]
    -Path  (param-switch/param-derived)  forwarded to disk-big -Path  @components/system/apps.ps1:328 [also: -p -path -Pa]

pwsh-profile  [none]  components/system/config-files.ps1

pwsh-starship  [none]  components/system/config-files.ps1

pwsh-settings  [none]  components/system/config-files.ps1

pwsh-font  [param-block]  components/system/fonts.ps1
    -status  (param-switch/-long)  report whether the Nerd Font is installed and install nothing; declared lowercase so it renders as a one-dash word  @components/system/fonts.ps1:29 [also: -Status -STATUS -s -st -stat]

pc-whoami  [mixed]  components/system/health.ps1
    -power  (param-switch/-long)  every power plan with caps decoded  @components/system/health.ps1:83 [also: -Power -POWER -pow -po]
    -crashes  (param-switch/-long)  hardware errors + bugchecks + dumps  @components/system/health.ps1:84 [also: -Crashes -c -cr]
    -bios  (param-switch/-long)  firmware version, age, board model  @components/system/health.ps1:85 [also: -BIOS -b -bi]
    -ram  (param-switch/-long)  the memory map, a named level, or one program's processes  @components/system/health.ps1:86 [also: -RAM -Ram -r -ra]
    -export  (param-switch/-long)  with -crashes, write the raw evidence bundle to a folder  @components/system/health.ps1:87 [also: -Export -e -ex] [docs say: -export (DESCRIPTION line 61 and hint line 378; absent from the Register-PFCommand example)]
    -days  (param-switch/-long)  value param: widen the stability window, default 7  @components/system/health.ps1:88 [also: -Days -d -da] [docs say: -days N]
    -min  (param-switch/-long)  value param: custom RAM cut-off in GB instead of a level, default 0.5  @components/system/health.ps1:89 [also: -Min -m -mi] [docs say: -min N]
    <name>  (positional/value)  slot 0: a RAM level word or a program name; a bare name with no other flag implies -ram (line 107)  @components/system/health.ps1:81 [also: -name java -n java] [docs say: pc-whoami -ram huge / -ram java]
    <program>  (positional/value)  slot 1: exists only to catch the second word of `--ram java` and of an unquoted two-word program name (which then triggers the quoting hint at line 111)  @components/system/health.ps1:82 [also: -program x -pr x]
    huge  (subcommand/bare)  RAM level 1 GB and up; level words are reserved and beat a program of the same name (line 126)  @components/system/health.ps1:397 [docs say: pc-whoami -ram huge]
    large  (subcommand/bare)  RAM level 250 MB - 1 GB  @components/system/health.ps1:398 [docs say: huge | large | medium | small | tiny]
    medium  (subcommand/bare)  RAM level 50 - 250 MB  @components/system/health.ps1:399 [docs say: huge | large | medium | small | tiny]
    small  (subcommand/bare)  RAM level 10 - 50 MB  @components/system/health.ps1:400 [docs say: huge | large | medium | small | tiny]
    tiny  (subcommand/bare)  RAM level under 10 MB  @components/system/health.ps1:401 [docs say: huge | large | medium | small | tiny]
    --ram  (hand-parsed/--long)  retired GNU-style spelling; binds as the literal STRING into slot 0 and is intercepted to print a deprecation notice  @components/system/health.ps1:95
    --power  (positional/--long)  NOT a flag and NOT intercepted: binds as the literal string into slot 0, so line 107 flips -ram on and it is looked up as a program name -> 'Nothing called --power is running'  @components/system/health.ps1:81
    --crashes  (positional/--long)  same trap as --power: reported as a missing program name instead of a flag  @components/system/health.ps1:81
    --bios  (positional/--long)  same trap as --power: reported as a missing program name instead of a flag  @components/system/health.ps1:81

pc-cap  [mixed]  components/system/health.ps1
    <pct>  (positional/value)  cap the CPU at this percentage; 5-100, records the prior state to disk first  @components/system/health.ps1:780 [docs say: pc-cap 85]
    restore  (subcommand/bare)  put back exactly what was recorded, verify by re-query, then forget the record  @components/system/health.ps1:802 [also: RESTORE Restore (the -eq compare is case-insensitive)] [docs say: pc-cap restore]
    -Value  (param-switch/param-derived)  value param holding either the percentage or 'restore'  @components/system/health.ps1:780 [also: -value -v -val -Val]

pwsh-autologin  [param-block]  components/system/login.ps1
    on  (subcommand/bare)  enable the ~/.bashrc login hook; also what a bare `pwsh-autologin` with no argument does  @components/system/login.ps1:33 [also: ON On '' (empty / no argument)] [docs say: pwsh-autologin]
    off  (subcommand/bare)  remove the login hook so the next login lands in bash  @components/system/login.ps1:61 [also: OFF Off (ValidateSet is case-insensitive)] [docs say: pwsh-autologin off]
    status  (subcommand/bare)  show the current setting, change nothing  @components/system/login.ps1:48 [also: STATUS Status] [docs say: pwsh-autologin status]
    -Mode  (param-switch/param-derived)  value param the three bare words bind to; ValidateSet('', 'on', 'off', 'status')  @components/system/login.ps1:33 [also: -mode -m -Mo]

pwsh-exit  [none]  components/system/login.ps1

set-path  [param-block]  components/system/path.ps1
    -System  (param-switch/param-derived)  write to the System PATH instead of the User PATH (adapter owns the elevation check)  @components/system/path.ps1:14 [also: -system -SYSTEM -s -sys -Sy] [docs say: -system (the Register-PFCommand synopsis lowercases the PascalCase parameter)]
    <dir...>  (positional/value)  ValueFromRemainingArguments, re-joined with a space, so an unquoted path containing spaces still works  @components/system/path.ps1:16 [also: -PathParts C:\tools -P C:\tools] [docs say: set-path C:\tools]

shutdown  [mixed]  components/system/shutdown.ps1
    cancel  (subcommand/bare)  cancel a scheduled shutdown; accepted ONLY as the sole argument (line 25 requires $Args.Count -eq 1)  @components/system/shutdown.ps1:25 [also: CANCEL Cancel] [docs say: shutdown cancel]
    Nh  (positional/value)  hours, matched by ^(\d+)(h|m)$; multiple tokens are summed (10 min - 6 h enforced)  @components/system/shutdown.ps1:38 [docs say: shutdown 1h 30m]
    Nm  (positional/value)  minutes, matched by the same regex and added to the total  @components/system/shutdown.ps1:38 [docs say: shutdown 1h 30m]
    -Args  (param-switch/param-derived)  the ValueFromRemainingArguments string[] all the bare tokens land in; shadows the automatic $Args  @components/system/shutdown.ps1:15 [also: -args -a -ar -Ar]

s  [mixed]  components/system/shutdown.ps1
    c  (subcommand/bare)  cancel — a one-letter subcommand that exists only on `s`, not on `shutdown`; sole argument only  @components/system/shutdown.ps1:80 [also: C] [docs say: s c]
    cancel  (subcommand/bare)  also works: anything that is not exactly 'c' is splatted to shutdown, which has its own cancel case  @components/system/shutdown.ps1:84
    Nh  (positional/value)  forwarded to shutdown via splat  @components/system/shutdown.ps1:84
    Nm  (positional/value)  forwarded to shutdown via splat  @components/system/shutdown.ps1:84
    -Args  (param-switch/param-derived)  the ValueFromRemainingArguments collector  @components/system/shutdown.ps1:76 [also: -a -args]

start-folder  [param-block]  components/system/startup.ps1
    open  (subcommand/bare)  open the Startup folder in the file manager  @components/system/startup.ps1:52 [also: OPEN (switch is over $Action.ToLower())] [docs say: start-folder open]
    add  (subcommand/bare)  add the positional-1 path to the Startup folder  @components/system/startup.ps1:58 [also: ADD] [docs say: start-folder add C:\t.exe]
    list  (subcommand/bare)  print the list instead of launching the fzf manager (also forced when output is redirected or fzf is missing)  @components/system/startup.ps1:81 [also: LIST (case-insensitive -eq)] [docs say: start-folder list]
    <path>  (positional/value)  slot 1, only meaningful after `add`  @components/system/startup.ps1:49 [also: -Target C:\x.exe -t C:\x.exe] [docs say: start-folder add <path>]
    -Action  (param-switch/param-derived)  value param that the bare verb binds to; any unrecognised word is silently ignored and the picker opens  @components/system/startup.ps1:49 [also: -action -a -Ac]

startup  [param-block]  components/system/startup.ps1
    open  (subcommand/bare)  Set-Alias to start-folder; all subcommands and parameters forward  @components/system/startup.ps1:183
    add  (subcommand/bare)  forwarded to start-folder  @components/system/startup.ps1:183
    list  (subcommand/bare)  forwarded to start-folder  @components/system/startup.ps1:183
    <path>  (positional/value)  forwarded to start-folder slot 1  @components/system/startup.ps1:183

pwsh-config  [mixed]  components/system/sysconfig.ps1
    timezone  (subcommand/bare)  canonical setting key from the platform adapter (Get-SysConfigOptions); resolved by lowercased string match  @components/system/sysconfig.ps1:88
    locale  (subcommand/bare)  canonical setting key from the platform adapter  @components/system/sysconfig.ps1:88
    hostname  (subcommand/bare)  canonical setting key from the platform adapter  @components/system/sysconfig.ps1:88
    ntp  (subcommand/bare)  canonical setting key (time sync toggle); also its own entry in the alias map  @components/system/sysconfig.ps1:28
    keyboard  (subcommand/bare)  canonical setting key, Linux adapter only  @components/system/sysconfig.ps1:88 [docs say: plus keyboard on Linux]
    user-folders  (subcommand/bare)  PowerFlow's OWN preference injected beside the OS keys (auto | local | known); undocumented in the synopsis and has no short alias  @components/system/sysconfig.ps1:67
    kb  (hand-parsed/bare)  alias -> keyboard, via the $script:PF_ConfigAliases hashtable  @components/system/sysconfig.ps1:24 [also: KB (lookup is on $Which.ToLower())]
    keys  (hand-parsed/bare)  alias -> keyboard; undocumented  @components/system/sysconfig.ps1:24
    tz  (hand-parsed/bare)  alias -> timezone  @components/system/sysconfig.ps1:25
    time  (hand-parsed/bare)  alias -> timezone; undocumented  @components/system/sysconfig.ps1:25
    loc  (hand-parsed/bare)  alias -> locale  @components/system/sysconfig.ps1:26
    lang  (hand-parsed/bare)  alias -> locale; undocumented  @components/system/sysconfig.ps1:26
    host  (hand-parsed/bare)  alias -> hostname  @components/system/sysconfig.ps1:27
    name  (hand-parsed/bare)  alias -> hostname; undocumented  @components/system/sysconfig.ps1:27
    sync  (hand-parsed/bare)  alias -> ntp  @components/system/sysconfig.ps1:28
    -Which  (param-switch/param-derived)  value param the bare setting name binds to  @components/system/sysconfig.ps1:46 [also: -which -w -W -Wh]

team-room  [mixed]  components/system/team-room.ps1
    start  (subcommand/bare)  re-arm a room that is already set up  @components/system/team-room.ps1:277 [also: START (verb is $Command.ToLower())] [docs say: team-room start <room>]
    stop  (subcommand/bare)  disarm the room and stop its watchers  @components/system/team-room.ps1:277 [also: STOP] [docs say: team-room stop <room>]
    list  (subcommand/bare)  in the verb whitelist at line 261 with no branch of its own; falls through to Show-TeamRoomList at line 299 — deliberate per the comment at 259-260  @components/system/team-room.ps1:261
    help  (subcommand/bare)  print the usage block  @components/system/team-room.ps1:265 [also: HELP]
    --help  (hand-parsed/--long)  works: PowerShell has no double-dash syntax so it binds as the literal string into slot 0 and the -in test at line 265 catches it  @components/system/team-room.ps1:265
    -h  (hand-parsed/-short)  BROKEN: team-room is an advanced function (a [Parameter] attribute is present at :251), so -h is a parameter-name attempt with no match and the call dies with 'A parameter cannot be found that matches parameter name h'. The line 261/265 cases for it are unreachable through typed syntax  @components/system/team-room.ps1:265
    <name>  (positional/value)  a bare word that is not a verb is reassigned from $Command to $Name (line 262) and shows one room in detail; also slot 1 after start/stop  @components/system/team-room.ps1:252 [also: -Name <room> -N <room> -Command <room>] [docs say: team-room <name>]
    -All  (param-switch/param-derived)  also enable/disable the scheduled connector task, not just the arm stamp; honoured at :289  @components/system/team-room.ps1:253 [also: -all -ALL -a -Al] [docs say: .DESCRIPTION :243-244 and in-command help :272; absent from the registry example at :304]
    /?  (positional/bare)  NOT a help token here (unlike srv, which does accept it): binds to slot 0, fails the verb whitelist, and is treated as a room name -> "No team room called '/?'"  @components/system/team-room.ps1:261

srv  [mixed]  components/network/servers.ps1
    add  (subcommand/bare)  save a connection by name after probing its SSH port  @components/network/servers.ps1:183 [also: ADD (the switch statement is case-insensitive)] [docs say: srv add proxmox you@192.168.1.50]
    rm  (subcommand/bare)  forget a saved connection  @components/network/servers.ps1:251 [also: RM] [docs say: srv rm <name> [-f]]
    remove  (subcommand/bare)  same as rm; undocumented in both the .DESCRIPTION and the in-command help block, but reserved as a name at lines 190 and 287  @components/network/servers.ps1:251
    rename  (subcommand/bare)  re-key a server so host/port/addedAt/lastSeen travel with it  @components/network/servers.ps1:273 [docs say: srv rename lab proxmox]
    list  (subcommand/bare)  every saved server with live status  @components/network/servers.ps1:324 [docs say: srv list]
    ls  (subcommand/bare)  same as list; undocumented in the .DESCRIPTION, the help block, and Register-PFCommand, but reserved as a name at lines 190 and 287  @components/network/servers.ps1:324
    help  (subcommand/bare)  print the usage block  @components/network/servers.ps1:306 [also: HELP]
    --help  (hand-parsed/--long)  works: binds as the literal string to $Command and the -in test at line 306 catches it  @components/network/servers.ps1:306
    -h  (hand-parsed/-short)  BROKEN: srv is a simple function, so -h matches no parameter and falls into the automatic $args while $Command stays empty; the switch matches nothing and the bare fzf picker opens instead of the help. The line 306 case for -h is unreachable through typed syntax  @components/network/servers.ps1:306
    /?  (hand-parsed/bare)  works: binds positionally to $Command and is matched at line 306 (team-room does not accept this token)  @components/network/servers.ps1:306
    info  (subcommand/bare)  SECOND positional, not first: `srv <name> info` authenticates over SSH and then reveals the saved endpoint  @components/network/servers.ps1:353 [also: INFO (case-insensitive -eq)] [docs say: srv proxmox info]
    <name>  (positional/value)  slot 0 when it is not a subcommand: connect by name; slot 1 for add/rm/rename/start  @components/network/servers.ps1:174 [also: -Command proxmox -C proxmox -Param1 proxmox] [docs say: srv proxmox]
    <user@host[:port]>  (positional/value)  slot 2 for `add`, validated by ^([^@\s]+)@([^@:\s]+)(?::(\d+))?$  @components/network/servers.ps1:198 [also: -Param2 you@192.168.1.50] [docs say: srv add proxmox you@192.168.1.50]
    -f  (param-switch/-short)  force: skip the delete confirmation on rm, and overwrite an existing entry on add  @components/network/servers.ps1:177 [also: -F] [docs say: srv rm <name> [-f] / '-f skips the confirm']
    -Param1  (param-switch/param-derived)  value param for slot 1; note -P is AMBIGUOUS between -Param1 and -Param2 and errors  @components/network/servers.ps1:175 [also: -param1 -Par1]
    -Param2  (param-switch/param-derived)  value param for slot 2  @components/network/servers.ps1:176 [also: -param2 -Par2]

git-branch  [none]  components/git/branches.ps1

git-b  [none]  components/git/branches.ps1

git-cm  [none]  components/git/branches.ps1

git-bd  [param-block]  components/git/branches.ps1
    <branchName>  (positional/value)  branch to delete; Mandatory, so PowerShell prompts when omitted. CRITICAL: this function is UNREACHABLE — PowerShell's function table is case-insensitive, so `function git-bD` at branches.ps1:286 overwrites `git-bd` at :265. Verified: after both definitions, `git-bd <name>` runs the git-bD body (git branch -D, force delete). The safe `git branch -d` path at :277 is dead code.  @components/git/branches.ps1:266 [also: git-bD] [docs say: git-bd (branches.ps1:380, synopsis 'delete a branch (bD forces)' — implies bd is safe; it is not)]
    -branchName  (param-switch/param-derived)  named form of the same positional value (takes a value, not a switch)  @components/git/branches.ps1:266 [also: -branchname -BRANCHNAME -b -br -branch]

git-bD  [param-block]  components/git/branches.ps1
    <branchName>  (positional/value)  branch to force-delete (git branch -D at :299); Mandatory, prompts when omitted. This definition wins the case-insensitive name collision with git-bd.  @components/git/branches.ps1:287 [docs say: listed only as an -Aliases entry of git-bd (branches.ps1:380), though it is a separate function, not a Set-Alias]
    -branchName  (param-switch/param-derived)  named form of the same positional value  @components/git/branches.ps1:287 [also: -branchname -BRANCHNAME -b -br -branch]

git-c.sb  [param-block]  components/git/branches.ps1
    <label>  (positional/value)  branch name (or name stem); omitting it entirely switches the command into an fzf branch picker at :311  @components/git/branches.ps1:308 [docs say: no -Example given (branches.ps1:381)]
    <suffixOrCommit>  (positional/value)  second positional: appended as `label-suffix`, EXCEPT when it matches ^[a-f0-9]{6,40}$ (:365), in which case it is treated as a commit to branch from — one positional slot with two silently different meanings  @components/git/branches.ps1:308
    -label  (param-switch/param-derived)  named form of positional 1  @components/git/branches.ps1:308 [also: -l -la -LABEL]
    -suffixOrCommit  (param-switch/param-derived)  named form of positional 2  @components/git/branches.ps1:308 [also: -s -su -suffix -suffixorcommit]

git-a  [none]  components/git/commit.ps1
    -vr  (hand-parsed/-long)  PHANTOM FLAG — NOT accepted by any code path. docs/features.md:25 advertises 'One-command releases - Update version and release with `git-a -vr`', but git-a has no param() block and never reads $args, so `git-a -vr` silently discards the flag and runs the ordinary interactive add-commit-push. Verified: a param-less function swallows unmatched dash tokens into $args without error.  @components/git/commit.ps1:11 [docs say: git-a -vr (docs/features.md:25); Register-PFCommand at commit.ps1:458 documents no flags at all (-Example 'git-a')]

git-a-plus  [param-block]  components/git/commit.ps1
    -Quick  (param-switch/param-derived)  minimal-prompt add-commit-push via Read-Host instead of fzf (:392)  @components/git/commit.ps1:246 [also: -quick -QUICK -q -qu] [docs say: -Quick (commit.ps1:459 synopsis 'git-a with modes: -Quick, -DryRun, -AmendLast')]
    -DryRun  (param-switch/param-derived)  preview the files that would be committed, change nothing (:343)  @components/git/commit.ps1:247 [also: -dryrun -d -dry -DRYRUN] [docs say: -DryRun (commit.ps1:459)]
    -AmendLast  (param-switch/param-derived)  amend the previous commit, then optionally force-push with --force-with-lease (:257)  @components/git/commit.ps1:248 [also: -amendlast -a -am -amend] [docs say: -AmendLast (commit.ps1:459)]
    --quick  (hand-parsed/--long)  GNU-style spelling is NOT recognised — no CmdletBinding, so `--quick` (and `--dry-run`, `--amend`) fall into $args and are silently ignored; the command then falls through to the default git-a path at :449 with no error. Same for --dryrun/--amendlast.  @components/git/commit.ps1:245

git-aa  [none]  components/git/commit.ps1
    (any argument)  (hand-parsed/value)  body is a bare `git-a-plus -Quick` with no @args forwarding, so anything typed after git-aa is silently discarded (e.g. `git-aa -DryRun` still runs Quick mode)  @components/git/commit.ps1:452 [docs say: git-aa (commit.ps1:460), no flags documented]

git-aq  [none]  components/git/commit.ps1
    (any argument)  (hand-parsed/value)  duplicate of git-aa (`git-a-plus -Quick`), no @args forwarding; arguments silently discarded  @components/git/commit.ps1:453 [docs say: listed as an -Aliases entry of git-aa (commit.ps1:460) though it is a separate function]

git-ad  [none]  components/git/commit.ps1
    (any argument)  (hand-parsed/value)  `git-a-plus -DryRun`, no @args forwarding; arguments silently discarded  @components/git/commit.ps1:454 [docs say: git-ad (commit.ps1:461)]

git-am  [none]  components/git/commit.ps1
    (any argument)  (hand-parsed/value)  `git-a-plus -AmendLast`, no @args forwarding; arguments silently discarded  @components/git/commit.ps1:455 [docs say: git-am (commit.ps1:462)]

git-l  [none]  components/git/interactive.ps1

git-log  [none]  components/git/interactive.ps1

git-s  [none]  components/git/interactive.ps1

git-st  [none]  components/git/interactive.ps1

git-pick  [none]  components/git/interactive.ps1

git-p  [none]  components/git/interactive.ps1

git-stash  [none]  components/git/interactive.ps1

git-sh  [none]  components/git/interactive.ps1

git-remote  [none]  components/git/interactive.ps1

git-r  [none]  components/git/interactive.ps1

git-release  [param-block]  components/git/release.ps1
    -h  (param-switch/-short)  print the new-project setup prompt and exit (:213); declared as [Alias('h',...)] on the switch, so it looks GNU-short but is really param-derived  @components/git/release.ps1:208 [also: -H] [docs say: git-rl -h (release.ps1:475 -Example 'git-rl · git-rl -h (set up a project)'); also README.md:477, COMPONENTS.md:175]
    -help  (param-switch/-long)  same switch via prefix-matching the single [Alias('help')]; one dash, whole word  @components/git/release.ps1:208 [also: -HELP -he -hel]
    -?  (param-switch/-short)  DECLARED as an alias but UNREACHABLE — the PowerShell engine intercepts -? and prints Get-Help output instead of binding the parameter. Verified: `git-rl -?` prints the auto-generated help block (NAME/SYNTAX), not the setup prompt.  @components/git/release.ps1:208
    -ShowSetupPrompt  (param-switch/param-derived)  the real parameter name behind -h/-help; undocumented anywhere but fully typable  @components/git/release.ps1:209 [also: -showsetupprompt -s -sh -show -SHOWSETUPPROMPT]
    --help  (hand-parsed/--long)  GNU spelling is a hard ERROR here (unlike everywhere else in the slice) because [CmdletBinding()] over a switch-only param() leaves no positional slot: 'A positional parameter cannot be found that accepts argument --help'. Verified.  @components/git/release.ps1:206
    -Verbose  (param-switch/param-derived)  one of the common parameters injected by [CmdletBinding()] at :206 — accepted (and inert) on git-release/git-rl only; no other command in this slice is an advanced function  @components/git/release.ps1:206 [also: -Debug -ErrorAction -WarningAction -InformationAction -ProgressAction (7.4+) -ErrorVariable -WarningVariable -InformationVariable -OutVariable -OutBuffer -PipelineVariable]

git-rl  [param-block]  components/git/release.ps1
    -h  (param-switch/-short)  forwarded verbatim: body is `git-release @args` (:472), so every git-release token binds identically through the wrapper. Verified -h/-help/-s/-Show all reach the switch; -? is still intercepted by the engine and --help still errors.  @components/git/release.ps1:472 [also: -help -HELP -he -ShowSetupPrompt -s -sh -show] [docs say: git-rl -h (release.ps1:475)]

git-f  [none]  components/git/reset.ps1

git-next  [none]  components/git/reset.ps1

git-rba  [none]  components/git/rollback.ps1

grba  [none]  components/git/rollback.ps1
    grba  (subcommand/bare)  the only real Set-Alias in the slice (Set-Alias -Name grba -Value git-rba); takes no tokens, and being an alias it forwards nothing of its own  @components/git/rollback.ps1:169 [docs say: grba (rollback.ps1:275 -Aliases @('grba'))]

git-rb  [param-block]  components/git/rollback.ps1
    <commitHash>  (positional/value)  commit to roll back to; Mandatory, so PowerShell prompts for 'commitHash' when omitted rather than opening a picker  @components/git/rollback.ps1:174 [docs say: no -Example given (rollback.ps1:274)]
    -commitHash  (param-switch/param-derived)  named form of positional 1 (lowercase first letter, unlike -Force)  @components/git/rollback.ps1:174 [also: -commithash -c -co -commit -COMMITHASH]
    -Force  (param-switch/param-derived)  skip both confirmation prompts and silently recreate an existing rollback-XXX branch (:206, :230)  @components/git/rollback.ps1:175 [also: -force -f -fo -FORCE] [docs say: NOT documented — rollback.ps1:274 synopsis says 'create a rollback branch from any commit, safely' and never mentions the flag that removes the safety]

gh-l  [mixed]  components/github/browser.ps1
    <count>  (positional/value)  how many recently-pushed repos to list; binds positionally to [int]$Count. A non-numeric first argument is a hard cast ERROR ('Cannot convert value "abc" to type System.Int32'), not a friendly message. Verified.  @components/github/browser.ps1:113 [docs say: gh-l 20 (README.md:306); Register-PFCommand at browser.ps1:642 documents no argument at all]
    -Count  (param-switch/param-derived)  named form of the repo limit, default 10  @components/github/browser.ps1:113 [also: -count -c -co -COUNT]
    -Token  (param-switch/param-derived)  GitHub PAT passed in plaintext on the command line (positional slot 2), bypassing $env:GITHUB_TOKEN and the credential store  @components/github/browser.ps1:114 [also: -token -t -to -TOKEN] [docs say: NOT documented in the registry or README]
    <third bare number>  (hand-parsed/value)  the hand-parse at :118-120 is unreachable for its stated purpose — the comment says 'Allow positional parameter for count: gh-l 15', but 15 already binds to $Count positionally, leaving $args empty. $args[0] only exists from the THIRD argument on, where a bare number silently OVERRIDES an explicit -Count (verified: `gh-l 5 tok 20` yields Count=20).  @components/github/browser.ps1:118
    --count  (hand-parsed/--long)  GNU spelling fails loudly here, in a different way from the rest of the slice: `--count` is taken as the positional [int] and dies with a cast error rather than being ignored. Verified.  @components/github/browser.ps1:112

gh-l-reset  [none]  components/github/browser.ps1

gh-l-status  [none]  components/github/browser.ps1

gh-l-org  [param-block]  components/github/browser.ps1
    <org>  (positional/value)  organisation login; omitting it opens an fzf org picker (:436)  @components/github/browser.ps1:397 [docs say: gh-l-org my-team (browser.ps1:643 -Example)]
    <count>  (positional/value)  second positional: repo limit, default 100 — same concept as gh-l's <count> but a different default and a different position (slot 2 here, slot 1 there)  @components/github/browser.ps1:398
    -Org  (param-switch/param-derived)  named form of positional 1  @components/github/browser.ps1:397 [also: -org -o -or -ORG]
    -Count  (param-switch/param-derived)  named form of positional 2, default 100 (gh-l's identically-named flag defaults to 10)  @components/github/browser.ps1:398 [also: -count -c -co -COUNT]
    -Token  (param-switch/param-derived)  ABSENT here although gh-l accepts it — gh-l-org reads only $env:GITHUB_TOKEN / the credential store (:402-403), so the sibling commands disagree on whether a token can be supplied as an argument  @components/github/browser.ps1:396
```

### Help, core, shell, brothers, docker, terminal, projects

```text
pwsh-h  [param-block]  components/help/menu.ps1
    -a  (param-switch/-short)  open the interactive fzf help browser instead of the printed manual  @components/help/menu.ps1:42 [also: -A (case-insensitive; exact match wins over the -advanced/-all prefixes)] [docs say: pwsh-h -a]
    -advanced  (param-switch/param-derived)  exact synonym of -a, checked in the same -or at line 46  @components/help/menu.ps1:42 [also: -ad -adv -adva -ADVANCED -Advanced] [docs say: pwsh-help -advanced also works (docstring line 36 / comment line 261, NOT in the Register-PFCommand example)]
    -all  (param-switch/param-derived)  accepted but INERT - declared at line 42, never read anywhere in the body; bare pwsh-h behaviour  @components/help/menu.ps1:42 [also: -al -ALL -All]
    <command-or-alias>  (positional/value)  exact registry Name or alias match -> the single-command detail view  @components/help/menu.ps1:56 [also: -Topic <name> -t <name> -To <name> -Top <name>] [docs say: pwsh-h chmod (docstring line 38); Register example 'pwsh-h · pwsh-h -a · pwsh-h git']
    <section-keyword>  (positional/value)  regex-substring match against $PF_HelpSections; verified matches are nav git github file linux bash health docker proxmox ssh disk terminal project config wsl  @components/help/menu.ps1:68 [also: -Topic <keyword> -t <keyword> git matches BOTH 'ENHANCED GIT WORKFLOW' and 'GITHUB BROWSER' 'files' (as documented on line 37) matches NO section - only the singular 'file' does; 'files' silently falls through to the substring search at line 75] [docs say: pwsh-h git  one section (nav · git · github · files · linux · health …) - docstring line 37]
    <lesson-or-topic>  (positional/value)  a lessons.ps1 command/brother name, or one of the 7 lesson topics -> prints the lesson  @components/help/menu.ps1:60 [also: -Topic <topic> -t <topic>] [docs say: pwsh-h permissions  every lesson in a topic (docstring line 39)]
    <free text>  (positional/value)  anything else becomes a substring search over names + synopses (line 75), else the 'Nothing called' error at line 84  @components/help/menu.ps1:75
    --all  (positional/--long)  NOT a switch - PowerShell binds any --token positionally, so --all/--a/--advanced land in $Topic and produce "Nothing called '--all'"; the only GNU-shaped spelling in the file is a dead end  @components/help/menu.ps1:42

pwsh-help  [param-block]  components/help/menu.ps1
    pwsh-help  (subcommand/bare)  Set-Alias to pwsh-h - identical binding, so every pwsh-h token above applies unchanged  @components/help/menu.ps1:262 [docs say: -Aliases @('pwsh-help')]
    -a  (param-switch/-short)  fzf browser (same param block)  @components/help/menu.ps1:42 [docs say: pwsh-help -advanced == pwsh-h -a (comment line 261)]
    -advanced  (param-switch/param-derived)  fzf browser  @components/help/menu.ps1:42 [docs say: pwsh-help -advanced]
    -all  (param-switch/param-derived)  accepted, inert  @components/help/menu.ps1:42

pwsh-recovery  [none]  components/core/recovery.ps1
    (no arguments)  (positional/bare)  no param block and $args is never read, so any token typed after it is silently discarded; all choice is via a Read-Host menu (1-9, q) at line 40  @components/core/recovery.ps1:19 [docs say: pwsh-recovery     # Shows recovery options (line 17); Register has no -Example]

powerflow-uninstall  [none]  components/core/recovery.ps1
    (no arguments)  (positional/bare)  no param block, no $args read; confirmation is the literal word 'yes' typed at the Read-Host on line 114, and a second y/n at line 145  @components/core/recovery.ps1:97

powerflow-update  [param-block]  components/core/version.ps1
    -Yes  (param-switch/param-derived)  skip the y/n confirmation at line 175  @components/core/version.ps1:153 [also: -yes -YES -y -Y] [docs say: powerflow-update -Yes     # no questions (comment-based .EXAMPLE line 150; the Register-PFCommand at line 308 has NO -Example, so pwsh-h never shows this flag)]
    --yes  (positional/--long)  SILENTLY IGNORED - verified: a -- token cannot bind a switch and there is no positional param, so it lands in $args, which the function never reads; the command prompts anyway  @components/core/version.ps1:153

powerflow-version  [none]  components/core/version.ps1
    (no arguments)  (positional/bare)  no param block, no $args read; extra tokens silently ignored  @components/core/version.ps1:259 [docs say: powerflow-version     # Shows version info (line 257)]

Get-PowerFlowVersion  [none]  components/core/version.ps1
    (no arguments)  (positional/bare)  registered as a user-facing pwsh-h row (line 309) despite being Verb-Noun; takes nothing  @components/core/version.ps1:223 [docs say: Get-PowerFlowVersion     # Shows detailed version info (line 221)]

pwsh-reminders  [none]  components/core/version.ps1
    (no arguments)  (positional/bare)  pure toggle - state is read from $script:CHECK_PROFILE_UPDATES and flipped through a y/n Read-Host (lines 275, 288); no on/off word is accepted, unlike linux-lessons  @components/core/version.ps1:265

export  [hand-parsed-args]  components/shell/bash-compat.ps1
    (bare)  (positional/bare)  no args -> list every env var as 'declare -x NAME="value"'  @components/shell/bash-compat.ps1:36 [docs say: export                      # list all, like bash (line 33)]
    NAME=value  (positional/value)  regex ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ at line 47; one or more, each Set-Item on Env:  @components/shell/bash-compat.ps1:47 [also: quotes stripped from the value (line 54): export PATH="$PATH:/opt/bin" anything not matching the regex -> 'not a valid assignment' error, so bash's export -p / -n are rejected, not honoured] [docs say: export EDITOR=vim]

unset  [hand-parsed-args]  components/shell/bash-compat.ps1
    NAME  (positional/value)  removes Env:\NAME, else the global Variable:\NAME; loops over every arg  @components/shell/bash-compat.ps1:67 [also: multiple names in one call a name that exists as neither is silently skipped - no error at all] [docs say: unset EDITOR]

source  [param-block]  components/shell/bash-compat.ps1
    <file>  (positional/value)  mandatory path; .ps1 is dot-sourced, anything else is parsed for KEY=value lines  @components/shell/bash-compat.ps1:88 [also: -File <path> -file <path> -f <path> -Fi <path> omitting it prompts (Mandatory), it does not error] [docs say: source .env]

alias  [hand-parsed-args]  components/shell/bash-compat.ps1
    (bare)  (positional/bare)  no args -> list the bash-style aliases in $script:PF_BashAliases  @components/shell/bash-compat.ps1:139 [docs say: alias                       # list all (line 136)]
    name='command args'  (positional/value)  args are re-joined with spaces (line 153) then matched by ^([A-Za-z_][\w\-\.]*)=(.+)$ (line 155) and compiled into a global function  @components/shell/bash-compat.ps1:155 [also: quotes stripped (line 161) REFUSED for rm mv cp cat ls chmod chown sudo (line 163)] [docs say: alias ll='ls -lh']

unalias  [hand-parsed-args]  components/shell/bash-compat.ps1
    <name>  (positional/value)  removes the compiled function, else a real Alias: entry; loops over every arg  @components/shell/bash-compat.ps1:179 [also: bash's unalias -a is NOT implemented - '-a' is treated as a name and reports '-a not found'] [docs say: unalias ll]

jobs  [none]  components/shell/bash-compat.ps1
    (no arguments)  (positional/bare)  no param block and $args never read, so bash's jobs -l / -p / -r are silently swallowed and the plain table prints  @components/shell/bash-compat.ps1:200

fg  [param-block]  components/shell/bash-compat.ps1
    <id>  (positional/value)  [int]$Id; omitted -> the last Running job (line 229)  @components/shell/bash-compat.ps1:226 [also: -Id 3 -id 3 -i 3 fg -3 binds Id = -3 (a negative int, not a flag) and reports 'no such job'] [docs say: fg 3]

bg  [param-block]  components/shell/bash-compat.ps1
    <id>  (positional/value)  [int]$Id; omitted -> the last job of any state (line 245)  @components/shell/bash-compat.ps1:242 [also: -Id 3 -i 3] [docs say: bg [id] (comment-based .SYNOPSIS line 239; Register has no -Example)]

history  [param-block]  components/shell/history.ps1
    <n>  (positional/value)  [int]$Count = 25; prints the last n history entries numbered  @components/shell/history.ps1:91 [also: -Count 100 -count 100 -c 100 -C 100 bare 'history -c' (bash's clear) ERRORS with "Missing an argument for parameter 'Count'" because -c prefix-matches Count other bash flags (-l, -p, -a) land in $args and are silently ignored] [docs say: history 100      # last 100 (line 85); Register -Example is 'sudo !!']
    !!  (positional/bare)  not an argument at all - a PSReadLine '!' chord (line 45) rewrites the buffer in place with the previous command line  @components/shell/history.ps1:45 [docs say: sudo !!]
    !$  (positional/bare)  PSReadLine '$' chord (line 63) - substitutes the last argument of the previous command  @components/shell/history.ps1:63 [docs say: !! and !$ work at the prompt (synopsis line 102)]

lesson  [param-block]  components/shell/lessons.ps1
    (bare)  (positional/bare)  no arg -> the grouped lesson index (Show-LessonIndex)  @components/shell/lessons.ps1:671 [docs say: lesson                the full index (line 661)]
    <command>  (positional/value)  a real Linux command key: chmod chown chgrp umask ls id getent groups rm find grep tar ps kill systemctl du df lsblk head tail ln stat ss journalctl  @components/shell/lessons.ps1:686 [also: -Name grep -n grep case-insensitive (ToLower at line 673) the brother name too: lesson changemode == lesson chmod (line 606) tab-completion is registered for -Name over commands+brothers+topics (line 726)] [docs say: lesson grep · l chmod (Register -Example 'l grep · lesson permissions')]
    <topic>  (subcommand/bare)  one of the 7 topics - archives disk files network permissions processes text - prints every lesson under it  @components/shell/lessons.ps1:676 [also: -Name permissions case-insensitive] [docs say: lesson permissions    every lesson in that topic (line 660)]

l  [param-block]  components/shell/lessons.ps1
    l  (subcommand/bare)  Set-Alias to lesson - takes the identical positional token set  @components/shell/lessons.ps1:722 [docs say: -Aliases @('l'); example 'l grep']

linux-lessons  [param-block]  components/shell/teach.ps1
    (bare)  (positional/bare)  no arg -> print the current mode and the three choices  @components/shell/teach.ps1:39 [docs say: linux-lessons          # show the current mode (line 31)]
    full  (subcommand/bare)  ValidateSet value - column diagrams + numeric + real command + tips; persisted to config/PowerFlow.settings.ps1  @components/shell/teach.ps1:37 [also: FULL / Full (ValidateSet is case-insensitive) -Mode full -m full '-full' with one dash is SILENTLY IGNORED (simple function, so it lands in $args) and the command just prints the current mode '--full' binds positionally and dies on the ValidateSet] [docs say: linux-lessons full]
    hint  (subcommand/bare)  one-line 'real linux command' reminder only  @components/shell/teach.ps1:37 [also: HINT -Mode hint -m hint] [docs say: linux-lessons hint]
    off  (subcommand/bare)  no teaching output; byte-identical to GNU  @components/shell/teach.ps1:37 [also: OFF -Mode off -m off '-off' silently ignored - prints the mode instead of turning lessons off] [docs say: linux-lessons off (Register -Example)]

perms  [param-block]  components/shell/teach.ps1
    <path>  (positional/value)  path to explain, defaults to '.'; output shape then depends on the linux-lessons mode  @components/shell/teach.ps1:174 [also: -Path ward-a -path ward-a -Pa ward-a --anything binds positionally as a path because [Parameter()] makes this an ADVANCED function, an unknown single-dash flag (perms -foo) ERRORS instead of being ignored - the opposite of every other command in this slice] [docs say: perms ward-a]

changemode  [hand-parsed-args]  components/shell/brothers.ps1
    -lesson  (hand-parsed/-long)  print the chmod lesson and run nothing (matched anywhere in the arg list)  @components/shell/brothers.ps1:33 [also: --lesson -LESSON --Lesson (regex ^--?lesson$, -match is case-insensitive)] [docs say: Every brother supports -lesson (file comment line 20); NOT mentioned in any Register-PFCommand synopsis or example]
    <chmod args>  (positional/value)  everything else is forwarded verbatim to the real chmod (& $Real @Arguments, line 47)  @components/shell/brothers.ps1:62 [docs say: changemode 775 shared/]

changeowner  [hand-parsed-args]  components/shell/brothers.ps1
    -lesson  (hand-parsed/-long)  print the chown lesson, run nothing  @components/shell/brothers.ps1:33 [also: --lesson -LESSON]
    <chown args>  (positional/value)  forwarded verbatim to chown  @components/shell/brothers.ps1:63

changegroup  [hand-parsed-args]  components/shell/brothers.ps1
    -lesson  (hand-parsed/-long)  print the chgrp lesson, run nothing  @components/shell/brothers.ps1:33 [also: --lesson -LESSON]
    <chgrp args>  (positional/value)  forwarded verbatim to chgrp  @components/shell/brothers.ps1:64

defaultmode  [mixed]  components/shell/brothers.ps1
    -lesson  (hand-parsed/-long)  print the umask lesson; caught by $args -contains '-lesson' because a single-dash token cannot bind $Mask  @components/shell/brothers.ps1:82 [also: -LESSON (-contains is case-insensitive)]
    --lesson  (hand-parsed/--long)  same lesson, but reached by the OTHER branch - a -- token binds positionally into $Mask and is matched by $Mask -match '^--?lesson$'  @components/shell/brothers.ps1:82 [also: --LESSON '-lesson' quoted]
    (bare)  (positional/bare)  no mask -> report the current umask plus the file/dir modes it produces  @components/shell/brothers.ps1:96 [docs say: defaultmode          # show it (line 75)]
    <mask>  (positional/value)  3-4 octal digits (^[0-7]{3,4}$, line 107) set via the perms adapter; anything else is rejected  @components/shell/brothers.ps1:80 [also: -Mask 022 -m 022] [docs say: defaultmode 022]

whoamifull  [hand-parsed-args]  components/shell/brothers.ps1
    -lesson  (hand-parsed/-long)  print the id lesson, run nothing  @components/shell/brothers.ps1:33 [also: --lesson]
    <id args>  (positional/value)  forwarded verbatim to id  @components/shell/brothers.ps1:147

mygroups  [hand-parsed-args]  components/shell/brothers.ps1
    -lesson  (hand-parsed/-long)  print the groups lesson, run nothing  @components/shell/brothers.ps1:33 [also: --lesson]
    <groups args>  (positional/value)  forwarded verbatim to groups  @components/shell/brothers.ps1:148

lookupentry  [hand-parsed-args]  components/shell/brothers.ps1
    -lesson  (hand-parsed/-long)  print the getent lesson, run nothing  @components/shell/brothers.ps1:33 [also: --lesson]
    <getent args>  (positional/value)  forwarded verbatim to getent (its database name is a bare word: passwd, group…)  @components/shell/brothers.ps1:149

findfile  [hand-parsed-args]  components/shell/brothers.ps1
    -lesson  (hand-parsed/-long)  print the find lesson, run nothing  @components/shell/brothers.ps1:33 [also: --lesson]
    <find args>  (positional/value)  forwarded verbatim to find - note find's own single-dash long flags (-name, -type, -mtime) pass straight through  @components/shell/brothers.ps1:152

findtext  [hand-parsed-args]  components/shell/brothers.ps1
    -lesson  (hand-parsed/-long)  print the grep lesson, run nothing  @components/shell/brothers.ps1:33 [also: --lesson] [docs say: findtext -lesson (file comment line 205)]
    <grep args>  (positional/value)  forwarded verbatim to grep (-r, -i, --include=… all pass through)  @components/shell/brothers.ps1:153

removefile  [hand-parsed-args]  components/shell/brothers.ps1
    -lesson  (hand-parsed/-long)  print the rm lesson and run NOTHING - the safe path on a destructive command  @components/shell/brothers.ps1:33 [also: --lesson]
    <rm args>  (positional/value)  forwarded verbatim to rm  @components/shell/brothers.ps1:154

archive  [hand-parsed-args]  components/shell/brothers.ps1
    -lesson  (hand-parsed/-long)  print the tar lesson, run nothing  @components/shell/brothers.ps1:33 [also: --lesson]
    <tar args>  (positional/value)  forwarded verbatim to tar (including tar's bare-cluster form: archive czf out.tgz dir)  @components/shell/brothers.ps1:155

makelink  [hand-parsed-args]  components/shell/brothers.ps1
    -lesson  (hand-parsed/-long)  print the ln lesson, run nothing  @components/shell/brothers.ps1:33 [also: --lesson]
    <ln args>  (positional/value)  forwarded verbatim to ln (-s etc.)  @components/shell/brothers.ps1:157

fileinfo  [hand-parsed-args]  components/shell/brothers.ps1
    -lesson  (hand-parsed/-long)  print the stat lesson, run nothing  @components/shell/brothers.ps1:33 [also: --lesson]
    <stat args>  (positional/value)  forwarded verbatim to stat  @components/shell/brothers.ps1:158

firstlines  [hand-parsed-args]  components/shell/brothers.ps1
    -lesson  (hand-parsed/-long)  print the head lesson, run nothing  @components/shell/brothers.ps1:33 [also: --lesson]
    <head args>  (positional/value)  forwarded verbatim to head (-n 20 etc.)  @components/shell/brothers.ps1:161

lastlines  [hand-parsed-args]  components/shell/brothers.ps1
    -lesson  (hand-parsed/-long)  print the tail lesson, run nothing  @components/shell/brothers.ps1:33 [also: --lesson]
    <tail args>  (positional/value)  forwarded verbatim to tail  @components/shell/brothers.ps1:162 [docs say: synopsis advertises a native flag inside the prose: 'brother of tail - last lines; -f follows live']

dirsize  [hand-parsed-args]  components/shell/brothers.ps1
    -lesson  (hand-parsed/-long)  print the du lesson, run nothing  @components/shell/brothers.ps1:33 [also: --lesson]
    <du args>  (positional/value)  forwarded verbatim to du  @components/shell/brothers.ps1:165 [docs say: dirsize -sh * (a one-dash SHORT CLUSTER in PowerFlow's own help text)]

diskfree  [hand-parsed-args]  components/shell/brothers.ps1
    -lesson  (hand-parsed/-long)  print the df lesson, run nothing  @components/shell/brothers.ps1:33 [also: --lesson]
    <df args>  (positional/value)  forwarded verbatim to df (-h, -T…)  @components/shell/brothers.ps1:166

listdisks  [hand-parsed-args]  components/shell/brothers.ps1
    -lesson  (hand-parsed/-long)  print the lsblk lesson, run nothing  @components/shell/brothers.ps1:33 [also: --lesson]
    <lsblk args>  (positional/value)  forwarded verbatim to lsblk  @components/shell/brothers.ps1:167

listports  [hand-parsed-args]  components/shell/brothers.ps1
    -lesson  (hand-parsed/-long)  print the ss lesson, run nothing  @components/shell/brothers.ps1:33 [also: --lesson]
    <ss args>  (positional/value)  forwarded verbatim to ss  @components/shell/brothers.ps1:170 [docs say: listports -tulpn (one-dash short cluster in the Register example)]

listprocs  [hand-parsed-args]  components/shell/brothers.ps1
    -lesson  (hand-parsed/-long)  print the ps lesson, run nothing  @components/shell/brothers.ps1:33 [also: --lesson]
    <ps args>  (positional/value)  forwarded verbatim to ps (aux, -ef…)  @components/shell/brothers.ps1:173

stopproc  [hand-parsed-args]  components/shell/brothers.ps1
    -lesson  (hand-parsed/-long)  print the kill lesson, run nothing  @components/shell/brothers.ps1:33 [also: --lesson]
    <kill args>  (positional/value)  forwarded verbatim to kill; -9 survives because PowerShell parses it as the number -9 and it is stringified back by [string[]]$Arguments  @components/shell/brothers.ps1:174

service  [hand-parsed-args]  components/shell/brothers.ps1
    -lesson  (hand-parsed/-long)  print the systemctl lesson, run nothing  @components/shell/brothers.ps1:33 [also: --lesson]
    status|start|stop|restart|enable  (subcommand/bare)  NOT parsed by PowerFlow - a bare word forwarded verbatim to systemctl, but it reads as a PowerFlow subcommand in the help row  @components/shell/brothers.ps1:175 [docs say: service status jellyfin]
    <systemctl args>  (positional/value)  forwarded verbatim to systemctl  @components/shell/brothers.ps1:175

systemlogs  [hand-parsed-args]  components/shell/brothers.ps1
    -lesson  (hand-parsed/-long)  print the journalctl lesson, run nothing  @components/shell/brothers.ps1:33 [also: --lesson]
    <journalctl args>  (positional/value)  forwarded verbatim to journalctl  @components/shell/brothers.ps1:176 [docs say: systemlogs -u jellyfin -e (one-dash short flags with a value, in the Register example)]

listfiles  [hand-parsed-args]  components/shell/brothers.ps1
    -lesson  (hand-parsed/-long)  print the ls lesson, run nothing - checked in listfiles itself, not Invoke-Brother  @components/shell/brothers.ps1:182 [also: --lesson -LESSON --Lesson]
    <ls args>  (positional/value)  splatted to PowerFlow's own ls (ls @args, line 186), not to /bin/ls - the one brother that never shells out  @components/shell/brothers.ps1:186

dkr  [hand-parsed-args]  components/docker/dkr.ps1
    --show-native  (hand-parsed/--long)  echo the real docker/compose command before running it  @components/docker/dkr.ps1:400 [also: --Show-Native --SHOW-NATIVE any case variant ( -eq is case-insensitive )] [docs say: not in any Register-PFCommand synopsis/example; only in the built-in Show-DkrHelp text at line 379]
    -f  (hand-parsed/-short)  follow the log stream (only consulted by the logs path)  @components/docker/dkr.ps1:401 [also: -F --follow --Follow --FOLLOW]
    --follow  (hand-parsed/--long)  same as -f; follow the log stream  @components/docker/dkr.ps1:401 [also: -f -F --Follow] [docs say: undocumented — the registry and Show-DkrHelp only ever show -f]
    -a  (hand-parsed/-short)  include stopped containers in the fzf pick pool  @components/docker/dkr.ps1:402 [also: -A --all --All --ALL] [docs say: not in any Register-PFCommand synopsis/example; only in Show-DkrHelp at line 380]
    --all  (hand-parsed/--long)  same as -a; include stopped containers in pickers  @components/docker/dkr.ps1:402 [also: -a -A --All] [docs say: undocumented — Show-DkrHelp shows only -a]
    -y  (hand-parsed/-short)  skip the destructive confirmation prompt on dkr down  @components/docker/dkr.ps1:403 [also: -Y --yes --Yes --YES] [docs say: not in any Register-PFCommand synopsis/example; only in Show-DkrHelp at line 381]
    --yes  (hand-parsed/--long)  same as -y; skip the dkr down confirmation  @components/docker/dkr.ps1:403 [also: -y -Y --Yes] [docs say: undocumented — Show-DkrHelp shows only -y]
    -h  (hand-parsed/-short)  print Show-DkrHelp and return  @components/docker/dkr.ps1:404 [also: -H --help --Help --HELP the bare subcommand 'help' at line 409] [docs say: undocumented — Show-DkrHelp does not list -h/--help, and no Register-PFCommand mentions them]
    --help  (hand-parsed/--long)  same as -h; print Show-DkrHelp and return  @components/docker/dkr.ps1:404 [also: -h -H --Help help (bare word, line 409)] [docs say: undocumented]
    help  (subcommand/bare)  print Show-DkrHelp and return  @components/docker/dkr.ps1:409 [also: HELP Help (verb is lowercased at line 408) -h --help] [docs say: printed as a suggestion at line 538 ('dkr help'); no Register-PFCommand entry]
    up  (subcommand/bare)  bring a compose stack up; no name uses a compose file in the cwd  @components/docker/dkr.ps1:451 [also: UP Up (lowercased at line 408)] [docs say: dkr up]
    down  (subcommand/bare)  take a compose stack down; confirms unless -y  @components/docker/dkr.ps1:451 [also: DOWN Down] [docs say: dkr down]
    start  (subcommand/bare)  start containers; no name opens a picker of non-running containers  @components/docker/dkr.ps1:473 [also: START Start] [docs say: dkr start]
    stop  (subcommand/bare)  stop containers; no name opens a multi-select picker  @components/docker/dkr.ps1:473 [also: STOP Stop] [docs say: dkr stop]
    restart  (subcommand/bare)  restart containers; no name opens a picker  @components/docker/dkr.ps1:473 [also: RESTART Restart] [docs say: dkr restart]
    logs  (subcommand/bare)  tail one container's log (fixed 200 lines); -f follows  @components/docker/dkr.ps1:494 [also: LOGS Logs] [docs say: dkr logs]
    shell  (subcommand/bare)  open an interactive shell inside a running container  @components/docker/dkr.ps1:510 [also: sh SHELL Shell] [docs say: dkr shell]
    sh  (subcommand/bare)  abbreviation of shell  @components/docker/dkr.ps1:510 [also: SH Sh shell] [docs say: dkr sh (declared via -Aliases @('dkr sh') at line 546)]
    <stack>  (positional/bare)  compose project or service name for up/down; only the first word is used, extras silently ignored  @components/docker/dkr.ps1:453 [docs say: dkr up media / dkr down media]
    <names...>  (positional/bare)  one or more container/service/stack names for start/stop/restart; resolved name -> service -> project -> substring  @components/docker/dkr.ps1:476 [docs say: dkr restart sonarr radarr]
    <name>  (positional/bare)  single container name for logs; only $names[0] is used, extras silently ignored  @components/docker/dkr.ps1:497 [docs say: dkr logs jellyfin -f]
    <name>  (positional/bare)  single container name for shell/sh; only $names[0] is used, extras silently ignored  @components/docker/dkr.ps1:513 [docs say: dkr shell sonarr]
    <container>  (positional/bare)  fallback: an unrecognised first word is resolved as a container name and filters the table; unresolved words error out  @components/docker/dkr.ps1:532 [docs say: not documented as a form; Show-DkrHelp only lists it indirectly via the name-matching note at lines 376-377]

send-keys  [param-block]  components/terminal/tabs.ps1
    -keys  (param-switch/param-derived)  keystroke string forwarded verbatim to Send-TerminalKeys  @components/terminal/tabs.ps1:18 [also: -Keys -KEYS -k -ke -key (any unambiguous prefix; it is the only parameter) -keys:value] [docs say: not spelled at all — Register-PFCommand line 73 has synopsis 'send keystrokes to another tab' and no -Example]
    <keys>  (positional/bare)  same value bound positionally, e.g. send-keys 'ls\r'  @components/terminal/tabs.ps1:18 [docs say: not documented — no -Example on the registration]

open-nt  [param-block]  components/terminal/tabs.ps1
    -Shell  (param-switch/param-derived)  shell to launch in the new tab; defaults to pwsh  @components/terminal/tabs.ps1:23 [also: -shell -SHELL -s -sh -she -shel (any unambiguous prefix) -Shell:bash] [docs say: not spelled — Register-PFCommand line 68 has no -Example, so the shell argument is invisible in pwsh-h]
    <shell>  (positional/bare)  same value bound positionally, e.g. open-nt bash  @components/terminal/tabs.ps1:23 [docs say: not documented]

close-ct  [none]  components/terminal/tabs.ps1

next-t  [none]  components/terminal/tabs.ps1

prev-t  [none]  components/terminal/tabs.ps1

open-t  [param-block]  components/terminal/tabs.ps1
    -index  (param-switch/param-derived)  tab number to switch to; must be 1-9 or the command prints an error  @components/terminal/tabs.ps1:42 [also: -Index -INDEX -i -in -ind -inde (any unambiguous prefix) -index:3] [docs say: the -Example at line 71 is 'open-t 3' — positional only; the -index name never appears]
    <n>  (positional/bare)  tab number bound positionally; omitting it yields [int]$index = 0 and the 1-9 error, never a picker  @components/terminal/tabs.ps1:42 [docs say: open-t 3]

close-t  [param-block]  components/terminal/tabs.ps1
    -index  (param-switch/param-derived)  tab number to close; must be 1-9 or the command prints an error  @components/terminal/tabs.ps1:55 [also: -Index -INDEX -i -in -ind -inde (any unambiguous prefix) -index:3] [docs say: not spelled — Register-PFCommand line 72 has synopsis 'close tab N' and NO -Example (unlike open-t)]
    <n>  (positional/bare)  tab number bound positionally; omitting it yields 0 and the 1-9 error  @components/terminal/tabs.ps1:55 [docs say: N (only as the letter N inside the synopsis 'close tab N')]

open-ubuntu  [none]  windows-only/wsl.ps1

open-wsl-simple  [param-block]  windows-only/wsl.ps1
    -ProfileName  (param-switch/param-derived)  Windows Terminal profile name to open; defaults to the hardcoded 'Ubuntu-20.04'  @windows-only/wsl.ps1:82 [also: -profilename -PROFILENAME -p -pr -prof -profile (any unambiguous prefix) -ProfileName:Ubuntu] [docs say: not spelled — Register-PFCommand line 99 has synopsis 'open WSL without Terminal profiles' and no -Example; the synopsis actively contradicts the parameter's existence]
    <profile-name>  (positional/bare)  same value bound positionally, e.g. open-wsl-simple Ubuntu-22.04  @windows-only/wsl.ps1:82 [docs say: not documented]

create-next  [none]  components/projects/create-next.ps1

create-n  [none]  components/projects/create-next.ps1
```
