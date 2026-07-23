# Log 3 — July 14, 2026 — v3.3.0: Linux shell parity, the teaching layer, and four release blockers

**Work performed:**

- **Fixed `nav`, which was completely non-functional on Linux.** It built its search root as
  the string `"$HOME\Code"`, which on Linux interpolates to `/home/you\Code` — a backslash
  is a legal *filename* character there, not a separator, so this was never an error, just a
  request for a directory that has never existed. Every default bookmark (`~\Documents`,
  `~\Pictures`, …) was built the same way and was equally dead. Underneath sat a silent second
  bug: bookmark-context matching used `TrimEnd('\')` and `StartsWith($bmPath + '\')`, so "am I
  inside a bookmark?" was permanently false on Linux. All path handling now goes through
  `Join-Path` and `[IO.Path]::DirectorySeparatorChar`; comparison is case-insensitive on
  Windows and case-sensitive on Linux.

- **Added `nav roots`** (`components/navigation/roots.ps1`) — configurable, persisted search
  roots (`~/.nav_roots.json`). Defaults: `~/Code` on Windows (unchanged), `~` on Linux.
  Sub-commands: `add`, `rm`, `reset`. With more than one root the picker labels each entry by
  its real root (`~/linux-lab` vs `/srv/media`) so same-named directories are unambiguous.
  Bookmark context still wins over a global scan.

- **Fixed `grep` being shadowed by a PowerShell function.** The new `-lesson` layer wrapped the
  real command names by defining a function for each — including `grep`. That fails the Linux
  CI's coreutils assertion, but the real problem is worse: a PowerShell function does not
  forward stdin to the binary it calls, so `cat access.log | grep ERROR` would have started
  native grep with no input and **hung on the console**. `grep` is now never wrapped; the
  commands that are wrapped forward stdin via `$MyInvocation.ExpectingInput`; and
  `platform/linux/bindings.ps1` strips a stray `grep` function as a backstop.

- **Fixed re-install → uninstall leaving a dead profile.** `install.ps1` backed up *any*
  existing profile, including PowerFlow's own. On a second install the "backup" was a copy of
  PowerFlow, and `uninstall.ps1` — which restores the backup — put PowerFlow back **after**
  deleting `components/` and `platform/`. The user was left with a profile that errored on
  every shell start. Install now backs up only what it did not write and keeps pointing at the
  genuine pre-PowerFlow backup across re-installs.

- **Fixed `install.sh` being un-re-runnable.** It copied the source tree with `cp -r`,
  including `.git/`. Git's loose objects are mode `444`, so the second run could not overwrite
  them, `cp` failed, and `set -euo pipefail` killed the installer with a wall of *Permission
  denied*. Re-running the installer from a clone — the normal way to change your mind about
  `--login-shell` — was impossible.

- **Cut the Linux install from 60 MB to 1.3 MB** by excluding `assets/` (58 MB of README
  screenshots nothing reads at runtime). The Windows installer never shipped it; now the two
  match.

- **Fixed shellcheck SC2086 in `install-gui.sh`** — arguments were assembled by string
  word-splitting (`--yes $NO_DEPS_FLAG $LOGIN_FLAG`); now an array.

**Files modified:**
- Added: `components/navigation/roots.ps1`, this log
- Modified: `components/navigation/{nav,bookmarks,projects}.ps1`, `components/shell/brothers.ps1`,
  `platform/linux/bindings.ps1`, `Microsoft.PowerShell_profile.ps1`, `install.ps1`, `install.sh`,
  `install-gui.sh`, `components/help/menu.ps1`, `COMPONENTS.md`, `CHANGELOG.md`

**Decisions:**

- **`nav`'s Linux default is `~`, not `/`.** Measured, not assumed: on a bare Debian container
  `/` holds 1,593 directories to `$HOME`'s 5 — and a real server is far worse. It also walks
  `/proc`, `/sys`, `/dev` and `/run`, which are kernel-backed pseudo-filesystems, and throws
  permission errors across most of the rest. `$HOME` is where work actually lives. Those paths
  are now skipped outright even if a user does add `/`.

- **`grep -lesson` was dropped rather than made to work.** Keeping it would mean keeping a
  function named `grep`, and no amount of stdin plumbing makes that as safe as the real binary.
  The lesson is still reachable via `findtext -lesson` and `pwsh-h grep`. Correctness of a
  daily-driver command beats reach of a teaching feature.

- **A `$script:PF_NeverWrap` list now guards the coreutils** rather than relying on reviewers
  remembering the rule. `brothers.ps1` refuses to wrap them and `bindings.ps1` strips them
  afterwards — two independent layers, because this exact mistake shipped once already.

- **3.2.0 is folded into 3.3.0.** It was tagged and pushed but its release workflow failed, so
  no release was ever published. The tag points at code that cannot pass CI; rather than
  re-cutting it, its content ships in 3.3.0 and the CHANGELOG says so plainly.

**Late change — `lesson <command>` replaces `<command> -lesson` (user's call, and it was right):**

I had built `-lesson` on the real command names, which required defining a PowerShell function
per command (`chmod`, `grep`, `tar`, …) — the only way PowerShell lets you see a native
command's arguments. Making that survivable took three separate safety mechanisms: a denylist
(`$PF_NeverWrap`), stdin forwarding via `$MyInvocation.ExpectingInput`, and a CI backstop in
`bindings.ps1`.

The user proposed `lesson grep` / `l grep` instead. That is strictly better and the workaround
was deleted (~50 lines):

| | `chmod -lesson` | `lesson chmod` |
|---|---|---|
| functions shadowing real binaries | 12 | **0** |
| can teach `grep` / `rm` / `cat` / `cp` | ❌ denylisted | ✅ |
| stdin in pipes | needs plumbing | not a question |
| failure mode when wrong | silent **hang** | none available |

The damning row is the second: the wrapper could not teach `grep`, `rm` or `cat` *precisely
because they are too dangerous to shadow* — so the commands a beginner most needs were the ones
excluded. `lesson` shadows nothing and therefore covers everything. Added: `lesson`, `l` alias,
topic lookup (`lesson permissions`), an index, typo suggestions, and tab-completion over
commands + brothers + topics. Brothers keep `-lesson` (a brother name shadows nothing).

**And that change exposed a feature that had never worked:**

Removing the wrapper made the test assert every real command resolves to `Application` — and
`umask` came back empty. Not shadowing: **`umask` is a shell builtin, not a binary.** There is
no `/usr/bin/umask`. So `defaultmode` had been printing *"'umask' is not available on this
system"* every single time it was ever run, and would have shipped that way.

`sh -c 'umask 022'` cannot fix it — that sets the umask of a subshell which then exits. It must
be in-process, so `platform/*/adapters/perms.ps1` gained `Get-Umask` / `Set-Umask`, P/Invoking
libc's `umask(2)`. Verified working on **glibc and musl** (Alpine is in the CI matrix, so this
mattered). Windows returns `$null` — it has ACLs and no umask, and a fabricated `0022` would be
a lie the user might act on.

Two traps in that code, both commented in place:
- **`umask(2)` has no getter.** It always *sets*, returning the previous value. Reading it means
  setting `0` and restoring immediately — skip the restore and every file the shell creates from
  then on is world-writable.
- **`Get-UmaskResult $mask 666`** would pass 666 *decimal*. The base must be an octal string, or
  the arithmetic is quietly, plausibly wrong. Caught while writing it.

`defaultmode` now also prints what the mask *produces* (`022` → files `644`, dirs `755`), because
a umask is subtractive and that is the part everyone gets wrong.

**Finished the COMMAND-MAP backlog — and it turned up a data-loss bug:**

Added the last nine lessons (`du`, `df`, `lsblk`, `head`, `tail`, `ln`, `stat`, `ss`,
`journalctl`) with brothers for each, bringing it to **24 lessons across 7 topics**
(`permissions`, `files`, `text`, `disk`, `network`, `processes`, `archives`). Two new topics.

Then the "harmless on Windows" item — GNU flags for `rm`/`mv`/`mkdir`/`touch`. It was not
harmless. Reproducing it first, as always, produced three findings:

1. 🚨 **`touch` DESTROYED existing files.** `New-Item -ItemType File -Path $f -Force` on a
   file that already exists **truncates it to zero bytes**. `touch README.md` silently
   emptied README.md. Measured: 42-byte file → 0 bytes, contents gone. This has been
   shipping. GNU touch only moves the timestamp; creating is what it does when the file is
   *absent*. Rewritten so an existing file is never rewritten.

2. 💥 **`rm -rf <dir>` HUNG THE SHELL.** `param([switch]$f)` meant `-rf` matched nothing,
   fell through into the *filename* list, `-f` was never seen, the confirm prompt fired and
   `Read-Host` blocked forever. My test harness timed out at two minutes, which is how I
   found it.

3. 💥 **`mkdir` rejected digits and slashes** (`^[a-zA-Z ._-]+$`), so `mkdir v2` threw and
   `mkdir src/app` threw; and it joined args with spaces, so `mkdir a b` made one directory
   called `a b`. `rmdir` did `$MyInvocation.Line.Replace("rmdir","")`, so `rmdir ./rmdir-tests`
   tried to remove `./-tests`.

All four now hand-parse `$args` through a shared `Split-GnuArgs` (bundled shorts `-rf`, long
flags `--recursive`, and `--` to name a file literally `-rf`). `rm` also adopts GNU's refusal
to delete a directory without `-r` — that is a real safety feature, not pedantry.

**The through-line:** items 2 and 3 are the *same root cause* as the `ls -ld` bug from this
morning. **A `param()` block makes PowerShell bind `-r`/`-p`/`-f`/`-l` as parameter names**,
and it then either throws "ambiguous" or silently drops the flag into `$args` where it is
mistaken for a filename. Three separate features, one mistake, made three times. It is now
written down in `COMPONENTS.md` footnote 5 rather than left for the next person to rediscover.

**A mistake worth recording:**

While fixing the `nav` array-unrolling trap (`return @($path)` unrolls to a bare string, so
`$roots[0]` is the character `'C'`), I reached for `Write-Output -NoEnumerate`. That is worse
than the bug: it emits the array *wrapped*, the caller's own `@()` nests it into a `List`, and a
later `[string[]]` cast stringifies that List to its **type name**. It wrote
`"System.Collections.Generic.List\`1[System.Object]"` into `.nav_roots.json` as a search root,
destroying the user's `Code` entry on the first `nav roots add`. The boring idiom — plain
`return`, `@(...)` at the call site — is correct. Caught by a test before it shipped; the
lesson is that a clever fix to a PowerShell semantics quirk deserves more suspicion than the
quirk itself.
