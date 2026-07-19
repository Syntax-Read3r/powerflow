# Changelog

All notable changes to PowerFlow will be documented in this file.

## [Unreleased]

### Planning
- Additional database providers
- Testing framework integration
- Enhanced Docker optimizations

## [3.6.0] - 2026-07-19

### Fixed

- 🚨 **The documented Windows install was broken.** `irm …/install.ps1 | iex` died with
  *"Cannot bind argument to parameter 'Path' because it is an empty string"* right after
  printing the install location. Under `iex` there is **no script file**, so
  `$PSScriptRoot` is empty, and the local-checkout probe fed that emptiness to
  `Join-Path`. Guarded — a no-file context now falls through to the download path, which
  is what the one-liner always meant. Reproduced against the published v3.5.0 asset in a
  sandboxed `$PROFILE`; verified fixed the same way (download → full tree → manifest).
  The release checklist gains the Windows twin of the `curl | bash` item: the piped form
  of an installer is the *documented* form, and must be exercised as such.

### Added

- 🌐 **The `srv` picker is now a manager, not just a launcher.**

  ```
  Enter    connect          ctrl-d   delete (confirms first)
  ctrl-r   rename           Esc      close
  ```

  After a delete or rename the picker reopens with fresh statuses. And
  **`srv rename <old> <new>`** exists as a command too — the record travels intact
  (host, port, added date, **last seen**), which is the whole reason rename beats
  `rm` + `add`: re-adding would re-probe and lose the history that tells you when an
  offline server was last alive.

---

## [3.5.0] - 2026-07-19

> 📖 **pwsh-h is no longer a hand-drawn wall — it is generated, browsable, and cannot
> drift from the code.** Plus: 🌐 **`srv` — named SSH connections with live status.**

### Added

- 🌐 **`srv` — servers by name, not by memorised IP.**

  ```
  srv add proxmox munya@192.168.8.247    tested before saving
  srv proxmox                            connect by name
  srv                                    fzf picker, online servers first
  srv list · srv rm <name>
  ```

  **The status check probes the SSH port, not just ping** — because the question is
  "can I ssh in?", not "is it on?". That yields *three* states, and the middle one is
  the one ping cannot see:

  | | |
  |---|---|
  | `✅ online` | the port accepts — connect |
  | `🟡 host up, ssh not answering` | machine on, **sshd down or blocked** — restart the service |
  | `⛔ offline · last seen Jul 17` | nothing answers — **go turn it on** (or the IP is mistyped) |

  `srv add` runs the same probe before saving, so a typo'd address is caught at entry;
  a genuinely powered-off server can still be saved after confirming. All prompts are
  pipe-safe (piped stdin refuses with an explanation rather than hanging — the
  installer's old bug class). Offline entries show **last seen**, the picker sorts
  online-first, ports are per-server (`user@host:2222`), and the server list survives
  uninstall like bookmarks do (`-Purge` removes it). `ssh` itself is never wrapped or
  shadowed — the coreutils principle.

### Changed

- 📖 **`pwsh-h` rewritten around a command registry.** The old menu was a 350-line wall
  of hand-padded box characters in a file far from the commands it documented. An audit
  found 4 commands missing and one row **actively false** (`ls -t` documented as "tree
  view" a full version after 3.3.0 made `-t` the GNU time-sort), and 11 rows had drifted
  off the 80-char grid from emoji-width bugs.

  Now every component declares its own commands beside their definitions:

  ```powershell
  Register-PFCommand -Name 'nav' -Aliases @('z') -Section '🧭 SMART NAVIGATION & BOOKMARKS' `
      -Synopsis 'fuzzy-find and jump to a project (4 levels deep)' -Example 'nav chess-guru'
  ```

  and `pwsh-h` renders from that data — alignment is arithmetic, sections are generated,
  and platform filtering is automatic (`del`/`mvf` appear on Linux, terminal tabs only on
  Windows, empty sections vanish).

- 🔎 **Bare `pwsh-h` opens an fzf browser** — type to filter all ~130 entries, preview
  pane shows synopsis + example + platform, Enter prints the detail view. Piped output,
  scripts, and fzf-less machines get the generated print automatically; `pwsh-h -all`
  forces it. Filtering got sharper too: `pwsh-h git` (section), `pwsh-h pc-cap` (command
  detail), `pwsh-h chmod` (routes to the lesson), `pwsh-h clipboard` (substring search
  over names *and* synopses).

- 🚧 **CI now fails a release if a user-facing command has no registration** — the
  "missing from pwsh-h" class is extinct the same way shadowed coreutils are. The gate is
  case-sensitive on purpose: PowerShell regex is case-insensitive by default, and a bare
  `[a-z]` would have swallowed every internal Verb-Noun helper into the requirement.

### Fixed

- 📝 Four commands that had quietly fallen out of the old menu (`clr`, `git-aa`,
  `removefile`, `unalias`) are documented again — by construction, this time.

---

## [3.4.0] - 2026-07-17

> 🖥️ **`pc-whoami` — the machine's vital signs on one screen.** Born from a real
> diagnosis session (CPU throttling + WHEA crashes) that took seven hand-typed
> incantations and an AI to decode. It is one command now.

### Added

- 🖥️ **`pc-whoami`** — power plan, CPU cap, hardware errors, crash dumps, BIOS age. One
  screen, triage-first: **green stays silent, every ⚠️ names the flag that drills in.**
  No hex (`0x55` renders as `85%`), no GUID aliases, no event-provider names.

  ```
  🔌 POWER
     Plan     GameTurbo (High Performance)   ⚠️ custom/OEM plan — not a system default
     CPU cap  85%                            ⚠️ full speed is being withheld
  💥 STABILITY (last 7 days)
     HW errors 4   ⚠️ the hardware itself reported faults
  ```

  - `pc-whoami -power` — every plan (custom/OEM ones flagged — stock plans are matched by
    **GUID**, because names are localised), caps decoded, AC/DC split shown only on
    machines that actually have a battery.
  - `pc-whoami -crashes` — WHEA/hardware errors, bugchecks, dump inventory.
    `-export` writes the raw evidence bundle (WHEA XML, bugcheck text, dump list) to a
    folder you can hand to whoever is helping you. `-days N` widens the window.
  - `pc-whoami -bios` — firmware version, **computed age**, board model, and the exact
    search string for updates. Deliberately no vendor-site scraping: a diagnostic tool
    should not depend on ASUS's HTML.
  - Honest degradation everywhere: an unelevated session says the minidump folder
    *"needs an elevated session to list — 0 here does not mean 0 exist"*; a container
    with no cpufreq says so instead of inventing a governor; an unreadable journal is
    *"unknown, not zero"*.

- 🔒 **`pc-cap`** — cap the CPU's maximum speed, with **guaranteed restoration**:

  ```
  pc-cap 85          cap at 85% — records the prior state to disk FIRST
  pc-cap restore     put back exactly what was recorded, verify, then forget
  ```

  Born from a real incident: a script capped a CPU at 85% "temporarily", its cleanup never
  ran, and the machine stayed throttled with no record of the original values. So:

  - The prior plan + values are written to `~/.powerflow-power-state.json` **before**
    anything changes — if the process dies mid-way, the truth is already on disk.
  - A second `pc-cap` **refuses** while a record exists: 100→85→70 must never make
    "restore" mean 85.
  - Restore **verifies by re-querying** (`powercfg` exit codes lie by omission) and only
    then deletes the record. A failed restore keeps it.
  - `pc-whoami` shows a banner for as long as the record exists — an abandoned cap
    cannot go unnoticed.

- 🐧 **Both platforms, per the architecture.** Windows: `powercfg` / WHEA / CIM /
  minidumps. Linux: cpufreq governor + `scaling_max_freq`, kernel MCE via `journalctl`,
  `/sys/class/dmi/id` for firmware (readable without root), `/var/crash`. Six new adapter
  contract functions, parity-checked by CI.

### Fixed

- 🚨 **The startup updater's "Install now" would have BROKEN the install.** It was a
  pre-2.0 relic: it downloaded **only** `Microsoft.PowerShell_profile.ps1` and overwrote
  `$PROFILE` — on the component layout that means a *new bootloader loading old
  components*, and since the version lives in `config/` (never touched), the "updated"
  install still reported the old version and **re-prompted every day, forever**.
  `powerflow-update` now runs the real installer in a child `pwsh` — full tree, manifest
  respected, ownership preserved (`-NoDeps` no longer erases the dependency records).

- 🔕 **The startup prompt can no longer hang or spam a piped shell.** With redirected
  stdin (scripts, tooling that forgot `-NoProfile`) `Read-Host` read EOF, fell through,
  and — because the fall-through branch never wrote the daily marker — the check re-ran
  on *every* load. Non-interactive loads now get one quiet line and a one-day snooze.

- 🌐 **Update checks no longer spend GitHub API quota.** The `releases/latest` redirect
  on github.com resolves the newest tag without touching `api.github.com` — the same
  anonymous API call that killed the v3.3.2 release. The API remains only as a fallback,
  with the existing 3-day cooldown on 403.

### Added (update flow)

- 😴 **Defer options that actually defer.** The prompt now offers **Install now · Remind
  me tomorrow · Snooze for a week · Turn off reminders** — the snooze marker holds a real
  date instead of only ever meaning "until midnight".

### Fixed (installer)

- 🌐 **The installer no longer dies to GitHub API rate limits.** The tarball path asked
  `api.github.com` for the latest PowerShell release; anonymous calls from shared CI
  runner IPs get 403'd, and that exact 403 silently killed the v3.3.2 release for three
  days. Three layers now: the `releases/latest` **redirect** on github.com (the website,
  not the API — resolves the tag with no rate limit), then the API **authenticated** when
  `GITHUB_TOKEN` is present (CI passes it), then a pinned known-good version, loudly, so
  an outage degrades instead of aborting. Verified on Arch — the leg that failed.

### Changed

- 🚧 **The architecture gate got stricter.** `powercfg`, `Get-CimInstance`, `Get-WinEvent`
  and `$env:SystemRoot` are now forbidden in `components/` alongside the existing list —
  the health feature routes all of them through adapters, and CI now keeps it that way.

---

## [3.3.2] - 2026-07-14 · published 2026-07-17

> Tagged Jul 14; its release run failed on a transient GitHub API rate-limit (the Arch
> leg's anonymous `api.github.com` call got a 403) and sat unnoticed for three days.
> Re-run and published Jul 17. The 3.4.0 installer no longer depends on that API call.

> 🚨 **Upgrading via `curl … | bash` was impossible.** If you already had PowerFlow, the
> installer asked a question nobody could answer, then cancelled.

### Fixed

- 💥 **`curl … | bash` could not upgrade an existing install.**

  ```
  ⚠️  A PowerShell profile already exists.
  Overwrite it? (y/n):
  ❌ Installation cancelled
  ```

  Two bugs, stacked:

  1. **It was asking about its own profile.** The check was `Test-Path $profilePath` — any
     profile at all. But if PowerFlow is already installed, that profile *is PowerFlow's*.
     This is an **upgrade**, and asking "overwrite it?" is asking whether you would like to
     install the thing you just asked to install. It now recognises its own manifest and
     simply says `🔄 PowerFlow v3.3.1 is already installed — upgrading it.`

  2. **`Read-Host` cannot be answered through a pipe.** In `curl … | bash`, stdin is the
     pipe curl already drained, so `Read-Host` reads EOF and returns `""`. `"" -ne 'y'`, so
     the install cancelled — **it could never have succeeded that way**, and it never said
     why. When there is no terminal, it no longer pretends to ask: it explains, and gives
     you the exact command (`| bash -s -- --yes`).

- 💥 **The installer exited 1 after succeeding.** With no `--yes`, `install.sh` prompted for
  the login-shell choice. Piped, `read` hits EOF and returns non-zero — and under
  `set -euo pipefail` that killed the installer **after** it had already printed
  `🎉 PowerFlow installed!`. A successful install that reports failure is a good way to make
  someone distrust an installer that worked. It now skips the question when there is no
  terminal (`[[ ! -t 0 ]]`), leaves your login shell untouched, and tells you how to enable
  it (`--login-shell auto`).

- 📖 **The uninstall instructions were wrong.** They were Windows-only, told you to
  `Remove-Item $PROFILE` by hand — which bypasses the manifest, orphans the component tree
  and the dependencies, and destroys the only record of which tools were *yours* — and had
  no Linux section at all. Rewritten. The installer now also prints the uninstall command
  when it finishes.

  Note that **`bash install.sh --uninstall` only works if `install.sh` is on disk**, and the
  documented install (`curl … | bash`) leaves no file behind, so it fails with
  `No such file or directory`. Use `powerflow-uninstall`, or
  `pwsh -NoProfile -File ~/.config/powershell/uninstall.ps1`.

---

## [3.3.1] - 2026-07-14

> The last member of the family that produced 3.3.0's `touch` / `rm -rf` / `mkdir` bugs.

### Fixed

- 💥 **`mv a.txt b.txt` silently did nothing on Windows.** The most basic operation in any
  shell. PowerFlow's `mv` is a cut/paste workflow (`mv <file>` holds it, `mv-t` pastes),
  so with two arguments it joined them into the single filename `"a.txt b.txt"`, found no
  such file, and gave up without a word. `mv report.pdf ~/Documents/` did nothing either.

  **One argument still cuts. Two or more is now a real move.**

  ```
  mv old.txt new.txt          rename
  mv report.pdf ~/Documents/  move into a folder
  mv a.txt b.txt dest/        move several into a directory
  mv -f src dst               overwrite without asking
  mv -n src dst               never overwrite

  mv belief-index             ✂️  still cuts — then navigate, then mv-t
  ```

  Overwriting **prompts unless `-f`**, which follows PowerFlow's `rm` rather than GNU
  (GNU clobbers silently). Consistency inside PowerFlow beats strict parity, and safety is
  the right direction in which to differ.

  Guarded against the obvious ways this goes wrong: `mv same.txt same.txt` refuses instead
  of deleting the file; `mv f.txt notadir/` refuses rather than creating a stray *file*
  called `notadir`; and `mv my report.txt` — an unquoted name with a space — still **cuts**
  `my report.txt`, because that reading is only chosen when it is the unambiguous one (the
  joined name exists and the first word does not). `mv a.txt b.txt` is unaffected.

  *(Windows only — on Linux `mv` has always been the GNU binary. PowerFlow's version, which
  is exposed there as `mvf`, gains the same move form.)*

---

## [3.3.0] - 2026-07-14

> 🐧 **PowerFlow now behaves like a real shell on Linux — and teaches you Linux while you
> use it.**
>
> **Includes everything from 3.2.0**, which was tagged but never published — its release
> workflow failed and the fixes for that failure are in this release. Upgrading from 3.1.x
> gets you both.

### Fixed

- 🚨 **`touch` DESTROYED existing files on Windows.** Read that again.

  ```powershell
  function touch { param($f); New-Item -ItemType File -Path $f -Force }
  ```

  `New-Item -Force` on a file that **already exists** truncates it to zero bytes. So
  `touch README.md` — a completely ordinary thing to type — silently emptied README.md.
  Verified: a 42-byte file, `touch`ed, came back 0 bytes with its contents gone.

  GNU `touch` never does this. It updates the *timestamp*; creating the file is what it
  does only when the file is **absent**. That is now what PowerFlow's does, and an
  existing file is never rewritten. `-c` (never create) is supported.

  *(Windows only — on Linux `touch` has always resolved to the GNU binary.)*

- 💥 **`rm -rf <dir>` HUNG THE SHELL on Windows.** `rm` declared `param([switch]$f)`, so
  `-rf` matched nothing, fell through into the *filename* list, and `-f` was never seen.
  The confirmation prompt then fired and `Read-Host` blocked — forever, in any
  non-interactive context. `mkdir -p a/b/c` threw outright (*"the parameter name 'p' is
  ambiguous"*). Both are the same root cause as the `ls` bug below: **a `param()` block
  makes PowerShell bind `-r`/`-p`/`-f` as parameter names.**

  `rm`, `mkdir`, `touch` and `rmdir` now hand-parse `$args`, so GNU flags work as written:

  | | |
  |---|---|
  | `rm -rf node_modules` | recursive + force, no prompt |
  | `rm <dir>` (no `-r`) | **refuses**, exactly like GNU — a typo'd path should not take a tree with it |
  | `mkdir -p src/components/ui` | creates the whole chain |
  | `touch -c maybe.txt` | bump the timestamp, but never create |
  | `rm -- -rf` | delete a file genuinely *named* `-rf` |

  Bundled shorts (`-rf`), long flags (`--recursive`), and `--` all work.

- 💥 **`mkdir` rejected digits and slashes.** Its validation was `^[a-zA-Z ._-]+$`, so
  `mkdir v2` **threw** (a digit), and `mkdir src/app` **threw** (a slash). It also joined
  its arguments with spaces, so `mkdir a b` produced a single directory named `a b`. Now:
  one directory per argument, and only characters the *filesystem* actually forbids are
  rejected.

- 💥 **`rmdir` mangled any path containing "rmdir".** It read `$MyInvocation.Line` and did
  a string `.Replace("rmdir", "")` on it — so `rmdir ./rmdir-tests` tried to remove
  `./-tests`. It also could not see flags at all. Rewritten to parse `$args`.

- 💥 **`ls` silently listed the WRONG DIRECTORY.** Same root cause as the two above.

  ```
  ls -ld ward-a
    GNU:        drwxr-xr-x 2 munya media 4096 ... ward-a
    PowerFlow:  <listed the current directory instead>
  ```

  `ls` declared a `param()` block (`$path`, `$t`, `$d`) and **no `[CmdletBinding()]`**.
  PowerShell therefore tried to bind `-l` as a *parameter name*, failed, and **silently
  dumped it — and the path — into `$args`, where they were discarded**. No error.

  Worse, two flags actively **contradicted** GNU:

  | Flag | GNU means | PowerFlow meant |
  |---|---|---|
  | `ls -t` | sort by **time** | tree view |
  | `ls -d` | the **directory itself**, not its contents | tree depth |

  So `ls -t` on Linux quietly produced a *tree* instead of a time-sorted list.

  **The rule now: single dash belongs to Linux; long dash belongs to PowerFlow.**
  `ls -l -a -d -h -R -t -S -r -i` all mean exactly what they mean on Linux.
  PowerFlow's extras moved to `--tree` and `--depth`, which GNU `ls` does not have and so
  can never collide. (Not `--t` — in Linux `--` introduces a *long* flag, so `--t` would
  teach the wrong convention.)

- 💥 **`nav` was completely non-functional on Linux.**

  ```
  ❯ nav linux lab
  ❌ No directories found in /home/munya\Code
                                          ↑ a literal backslash
  ```

  `nav` built its search root as the string `"$HOME\Code"`. On Windows that is a path.
  On Linux it interpolates to `/home/munya\Code` — and because a backslash is a perfectly
  legal **filename character** on Linux, not a separator, this is not an error. It is a
  request for a directory that has never existed. `nav` dutifully searched it, found
  nothing, and said so. Every default bookmark (`~\Documents`, `~\Pictures`, …) was built
  the same way, so **every one of them was dead on Linux too**.

  Underneath sat a second bug: the bookmark-context logic compared paths with
  `TrimEnd('\')` and `StartsWith($bmPath + '\')`. On Linux that separator never appears,
  so "am I inside a bookmark?" was permanently false — silently, with no symptom.

  All path handling now goes through `Join-Path` and
  `[IO.Path]::DirectorySeparatorChar`. Path comparison is case-insensitive on Windows and
  **case-sensitive on Linux**, where `/home/Foo` and `/home/foo` are genuinely different
  directories.

- 🔖 **Default bookmarks no longer point at directories that do not exist.** A headless
  server has no `~/Pictures` and no `~/Code`; PowerFlow bookmarked them anyway. Defaults
  are now filtered by `Test-Path` at first run, and `~` is always among them.

- 💥 **`defaultmode` (umask) never worked at all.** It printed *"'umask' is not available
  on this system"* every single time — because `umask` is a **shell builtin, not a
  binary**. There is no `/usr/bin/umask` to execute, and `sh -c 'umask 022'` sets the umask
  of a subshell that immediately exits, changing nothing. It has to be done in-process, so
  the perms adapter now calls libc's `umask(2)` directly (verified on glibc *and* musl).

  `defaultmode` also now shows what the mask actually *produces*, since a umask is
  **subtractive** and that is the part everyone gets wrong:

  ```
  ❯ defaultmode 027
    umask 0022 → 0027   new files 640, new dirs 750
    🐧 real linux command: umask 027
  ```

  (A trap worth knowing: `umask(2)` has **no getter**. It always *sets*, returning the
  previous value — so reading it means setting `0` and restoring immediately. Skip the
  restore and every file the shell creates from then on is world-writable.)

- 💥 **Re-running the installer permanently disabled its own cleanup.** The manifest
  recorded `installedByPowerFlow = (-not $preExisting)` — but on a *second* install every
  tool is present **precisely because the first install put it there**. So each re-install
  quietly flipped `starship`, `fzf`, `zoxide` and `lsd` to "the user already had this", and
  `uninstall` then correctly honoured a manifest that had become a lie, leaving all of them
  behind forever.

  Ownership is now carried forward from the previous manifest. The safety guarantee is
  unchanged and still verified in CI in **both** directions: a tool PowerFlow installed is
  removed; a tool that was already on the machine (`git`, on the runner) is never touched.

- 💥 **Re-installing then uninstalling left a dead profile behind.** `install.ps1` backed
  up *any* existing profile — including PowerFlow's own. So on a second install the
  "backup" was a copy of PowerFlow, and `uninstall.ps1`, which restores the backup,
  put PowerFlow back **after** deleting `components/` and `platform/`. The result was a
  profile that errored on every single shell start. Install now backs up only what it did
  not write, and keeps pointing at your genuine pre-PowerFlow backup across re-installs.

- 🐧 **`install.sh` could not be run twice.** It copied the whole source tree into
  `~/.local/share/powerflow` with `cp -r`, **including `.git/`**. Git's loose objects are
  mode `444`, so the second run could not overwrite them; `cp` failed, `set -euo pipefail`
  aborted, and the installer died in a wall of *Permission denied*. Re-running the
  installer from a clone — the normal way to change your mind about `--login-shell` — was
  therefore impossible. `.git`, `.github`, `node_modules` and `assets/` are now excluded.

- 📦 **A Linux install was 60 MB; it is now 1.3 MB.** `assets/` — 58 MB of README
  screenshots that nothing reads at runtime — was being copied into every install. The
  Windows installer never shipped it; now neither does the Linux one.

- 🧰 **`install-gui.sh` built its arguments by string-splitting** (`--yes $NO_DEPS_FLAG
  $LOGIN_FLAG`), so a flag whose value contained a space depended on word-splitting to
  land correctly. Now an array (`"${INSTALL_ARGS[@]}"`), which passes exactly the
  arguments intended and nothing else. (shellcheck SC2086 — it was right.)

### Added

- 📍 **`nav roots` — configurable search roots.** `nav` no longer assumes your work lives
  in `~/Code`.

  ```
  nav roots              # show where nav looks
  nav roots add /srv     # also search /srv  (or /opt, /mnt/data, …)
  nav roots rm  /srv
  nav roots reset
  ```

  Defaults: **`~/Code` on Windows** (unchanged), **`~` on Linux** — which already contains
  `~/Code`, `~/linux-lab` and anything else you actually work in.

  **The default is deliberately not `/`.** Scanning `/` walks `/proc`, `/sys`, `/dev` and
  `/run` — kernel-backed pseudo-filesystems, not directories in any useful sense — and
  hits permission errors across most of the rest. On a bare Debian container `/` holds
  ~1,600 directories to `$HOME`'s 5, and a real server is far worse; you would wait
  seconds to fuzzy-match against mostly noise. Those paths are now skipped outright even
  if you do add `/`. Add the roots you actually want instead.

  With more than one root, the picker shows each entry under its real root
  (`~/linux-lab`, `/srv/media`) so two same-named directories are never ambiguous.
  If your current directory is inside a bookmark, that bookmark still wins — it is a
  better guess at what you meant than any global scan.

- 🎓 **A Linux teaching layer.** `perms <path>` explains a file's permissions — including
  **which column is which**, the thing that is genuinely hard to remember:

  ```
    d : rwx : rwx : r-x   2   munya   media   4.0K   Jul 14 12:05   ward-a
    ╷    ╷     ╷     ╷    ╷     ╷       ╷
    │    │     │     │    │     │       └── GROUP  · members of 'media'
    │    │     │     │    │     └── OWNER  · the user who owns it
    │    │     │     │    └── hard links
    │    │     │     └── others · r-x = read + enter
    │    │     └── group  · rwx = read + write + enter
    │    └── owner  · rwx = read + write + enter
    └── type · d = directory

    🔢 numeric : 775          chmod 775 ward-a
    🐧 real linux command : ls -ld ward-a
    💡 On a DIRECTORY, x means 'may enter', not 'may run'.
  ```

  Colon-separated (`d:rwx:rwx:r-x`) because the three triads are the whole point and
  `drwxr-xr-x` runs them together.

- 🎚️ **`linux-lessons full | hint | off`** — teaching is a phase, not a permanent state.
  `off` produces byte-identical GNU output. Persisted to settings; defaults to `full` on
  Linux and `off` on Windows (nobody on Windows is learning `chmod`).

- 👬 **Brother commands.** Full-word twins of cryptic Linux names — **same flags, same
  result** — that always print the real command, so you build muscle memory for `chmod`
  while typing `changemode`:

  | | | | |
  |---|---|---|---|
  | `changemode`→`chmod` | `changeowner`→`chown` | `changegroup`→`chgrp` | `defaultmode`→`umask` |
  | `whoamifull`→`id` | `mygroups`→`groups` | `lookupentry`→`getent` | `findtext`→`grep` |
  | `findfile`→`find` | `listprocs`→`ps` | `stopproc`→`kill` | `service`→`systemctl` |
  | `fileinfo`→`stat` | `makelink`→`ln` | `firstlines`→`head` | `lastlines`→`tail` |
  | `dirsize`→`du` | `diskfree`→`df` | `listdisks`→`lsblk` | `listports`→`ss` |
  | `systemlogs`→`journalctl` | `archive`→`tar` | `removefile`→`rm` | `listfiles`→`ls` |

- 📖 **24 lessons across 7 topics** — `permissions`, `files`, `text`, `disk`, `network`,
  `processes`, `archives`. The nine added here are the ones you reach for when something
  is actually broken at 3am:

  | | |
  |---|---|
  | `lesson df` | *"No space left on device" but `df` shows free space? Check `df -i` — you are out of **inodes**.* |
  | `lesson ss` | *Connection refused from another machine but fine locally? The service is bound to `127.0.0.1`, not `0.0.0.0`. Nothing to do with the firewall.* |
  | `lesson journalctl` | *`systemctl status` shows the last ten lines and everyone stops there. The answer is nearly always further back: `journalctl -u X -e`.* |
  | `lesson ln` | *Target FIRST, link second — backwards is the classic mistake, and it will happily create a link pointing at nothing.* |
  | `lesson tail` | *`-F` over `-f` on anything logrotate touches, or you follow a deleted file forever.* |
  | `lesson du` · `lesson lsblk` · `lesson head` · `lesson stat` | |

- 📚 **`lesson <command>`** — learn any Linux command. It **runs nothing**, so it is always
  safe, even for `rm`. Shorthand `l`, and it tab-completes:

  ```
  lesson chmod          # the real command
  l grep                # shorthand
  lesson changemode     # the brother name finds the same lesson
  lesson permissions    # every lesson in a topic
  lesson                # the full index
  ```

  **Why a verb and not `chmod -lesson`.** `chmod -lesson` would require PowerFlow to define
  a *function* named `chmod` — PowerShell gives no other way to see a native command's
  arguments. That was built, and then removed, because a function is not a transparent
  stand-in for a binary: **it does not forward stdin**, so a wrapped `grep` would make
  `cat access.log | grep ERROR` start the real grep with no input and **hang on the
  console**. Defending against that meant denylisting `grep`, `rm`, `cp`, `cat` — which
  left the commands a beginner most needs as exactly the ones that could not have a lesson.

  `lesson <command>` shadows nothing. So it covers **every** command, `grep` and `rm`
  included, and there is no failure mode to defend against. Brothers keep `-lesson`
  (`changemode -lesson`), since a brother name is not a real command.

  One data file backs `lesson`, `pwsh-h <topic>` and the inline hints, so they cannot drift.

- 🔍 **One menu, with topics.** No separate `linux-h`. `pwsh-h` already renders 16k
  characters, so it now takes a topic: `pwsh-h permissions`, `pwsh-h files`, `pwsh-h linux`,
  or a command name (`pwsh-h chmod`).

- 🐚 **The bash builtins PowerShell lacks**, so you never have to leave PowerFlow:

  | | |
  |---|---|
  | `export VAR=value` | bash-style env vars |
  | **`alias ll='ls -lh'`** | **an alias WITH ARGUMENTS** — `Set-Alias` fundamentally cannot do this |
  | `unset` · `source` | remove a var · load `KEY=value` lines from a file |
  | `jobs` · `fg` · `bg` | job control, mapped onto PowerShell jobs |
  | `history` · **`!!`** · **`!$`** | `sudo !!` is muscle memory. Implemented as PSReadLine handlers that rewrite the line **in place**, so you see what will run before pressing Enter — arguably better than bash, where `!!` expands invisibly. |

  (`&&`, `\|\|`, pipes, redirection, `$()` and globbing already worked in PowerShell 7.)

- 🪟 **Windows tells the truth.** `perms` on Windows does **not** invent a fake `755` —
  Windows has ACLs, not POSIX mode bits, and there is no honest mapping. It says so and
  points at `icacls`. The **lessons still work** on Windows; only the *action* does not.

## [3.2.0] - 2026-07-14 · tagged, never published

> ⚠️ **This version was tagged but no release was ever published — its release workflow
> failed** (shellcheck SC2086 in `install-gui.sh`, and `install.sh` could not run twice
> because it copied read-only `.git` objects). Both are fixed in **3.3.0**, which contains
> everything below. There is nothing to install here; go to 3.3.0.

> 🌍 **`git-rl` now works in any project — not just PowerFlow's.**
>
> It reads *your* project's version file (`package.json`, `pyproject.toml`, `Cargo.toml`,
> `*.csproj`, `build.gradle`, `VERSION`), bumps it, and keeps multiple version files in
> sync. No more asking a Node developer to keep a PowerShell file in their repo.

### Added

- 🌍 **Project version-file detection (`components/git/version-files.ps1`).**
  `git-rl` previously read **one hardcoded location** — `config/PowerFlow.settings.ps1`,
  matching `$script:POWERFLOW_VERSION`. In any other project it silently fell back to the
  latest git tag and **rewrote nothing**, so a Node project's `package.json` was never
  bumped. It now detects and rewrites the project's own version file:

  | Project | File | Pattern |
  |---|---|---|
  | Node | `package.json` | `"version": "X.Y.Z"` |
  | Python | `pyproject.toml` | `version = "X.Y.Z"` (`[project]` / `[tool.poetry]`) |
  | Rust | `Cargo.toml` | `version = "X.Y.Z"` (`[package]` only) |
  | .NET | `*.csproj` | `<Version>X.Y.Z</Version>` |
  | Gradle | `build.gradle(.kts)` | `version = "X.Y.Z"` |
  | Any | `VERSION` | plain text |
  | PowerShell | `config/PowerFlow.settings.ps1` | `$script:POWERFLOW_VERSION` |

  Falls back to the latest git tag when a project has none.

- 🔗 **Multiple version files are updated together, and drift is caught before the bump.**
  If a project has both `package.json` and a `VERSION` file, `git-rl` shows both, warns if
  they currently **disagree**, and — on confirmation — brings all of them to the same new
  version. Version drift is now handled at the source rather than policed by a CI check
  after the fact. If any file fails to update, the release **aborts before** anything is
  committed, tagged or pushed.

- 🛡️ **Formatting is preserved, and nested versions are never touched.**
  The rewrite is a targeted regex anchored to the *current* version, not a
  parse-and-reserialise — round-tripping `package.json` through a JSON serialiser would
  reorder keys and reindent the file, an unacceptable diff for a version bump. Verified
  against fixtures for all seven project types: a `version` under `[dependencies]` in
  `Cargo.toml`, a nested `"version"` key in `package.json`, and a `[tool.other]` version
  in `pyproject.toml` are all left alone, while only the project's own version moves.

- 🐚 **`install.sh --login-shell` — PowerFlow can now start on login.**

  PowerFlow is a PowerShell *profile*: it only loads when `pwsh` runs. On a server the
  login shell is bash, so users installed it successfully, rebooted, landed in bash, and
  found no PowerFlow — while the installer cheerfully told them to *"restart your shell"*,
  which on Linux does **nothing**. Reported from a real headless Proxmox box.

  ```bash
  install.sh --login-shell auto    # launch pwsh from ~/.bashrc  (recommended)
  install.sh --login-shell login   # chsh — make pwsh the login shell
  install.sh --login-shell none    # do nothing; run `pwsh` by hand
  ```

  With no flag it **asks**. With `--yes` and no flag it does **nothing** — CI and
  `curl … | bash` must never rewrite someone's shell config unasked.

  `auto` is recommended because it **cannot lock you out**. The `~/.bashrc` block is
  guarded three ways: `$- == *i*` (interactive only — never scp/rsync/cron), a
  `PWSH_STARTED` flag (no login loop), and `command -v pwsh` (if pwsh disappears you still
  get bash). Verified by deleting `pwsh` and confirming the shell still comes up. It is
  idempotent, and `--uninstall` strips it back out.

### Changed

- 📖 **`git-rl -h` setup docs rewritten for real projects.** The prompt previously told
  Node and Python developers to create a PowerShell file (`config/PowerFlow.settings.ps1`)
  in their repo, and then add a CI step to stop it drifting from `package.json`. That was
  a workaround for a limitation, not a design. The prompt now says: *if your project
  already has a version file, you are done* — and explicitly warns against creating a
  PowerShell file in a non-PowerShell project.

- 🐧 **The post-install message no longer misleads on Linux.** It said "Restart your shell
  to activate PowerFlow". Restarting bash does nothing — it now says
  *"PowerFlow is a PowerShell profile — start it with: `pwsh`"*.

### Fixed

- 🔐 **`chsh` failed silently, and could have left you with no shell.** Plain `chsh`
  prompts for a password, so it fails when piped or non-interactive — the login shell was
  never changed and **nothing was reported**. It now elevates via `sudo`, and verifies the
  result in `/etc/passwd` rather than trusting the exit code. The same bug hit *uninstall*:
  it printed "reverting to bash" while leaving `pwsh` as the login shell — meaning it would
  remove pwsh and leave the user's next login pointing at a shell that no longer exists.
  Uninstall now reverts the shell **before** removing pwsh, verifies it, and **aborts
  loudly** if it cannot.

## [3.1.0] - Unreleased

> 🗄️ **New: find what is actually eating your disk** — `installed-apps` and `disk-big`.
>
> 🐧 **Plus: the Linux installer now works on every distro it claims to support.**
> v3.0.0 and v3.0.1 were only ever tested on Ubuntu; the `dnf`, `pacman`, `zypper` and
> `apk` paths were written but **never executed once**. Every package manager is now
> exercised on a real container of that distro, on every release.

### Added

- 🗄️ **`installed-apps` — find installed applications by size, then act on them.**

  ```powershell
  installed-apps -o          # 📊 overview of every band, then drill into one
  installed-apps             # pick a size band, then browse it
  installed-apps 2gb-4gb     # apps in a range
  ```

  `installed-apps -o` scans once and reports where the space actually is:

  ```
  BAND           APPS          TOTAL
  1 - 5 GB          9       22.41 GB
  5 - 20 GB         2       11.33 GB
  20 - 50 GB        0           0 KB
  50 GB +           5      502.12 GB
  TOTAL            16      535.86 GB
  ```

  Pick a band in fzf to drill straight into it — no rescan, because the overview and the
  drill-in share the same pass. Each row shows **size *and* age**, since "big *and* old"
  is the strongest signal that something is safe to remove. Age comes from the registry's
  `InstallDate` on Windows (falling back to folder creation time), `rpm INSTALLTIME` and
  pacman's Install Date on Linux, and — because dpkg records none — the mtime of
  `/var/lib/dpkg/info/<pkg>.list`.

- 📁 **`disk-big` — find large FOLDERS and FILES, not just apps.**
  A registry enumeration will never surface a 169 GB `docker_data.vhdx`, a bloated
  `node_modules`, or a Downloads folder full of ISOs — none of those are "installed
  apps". `disk-big` scans the places where bulk actually accumulates (`%LOCALAPPDATA%`,
  `ProgramData`, `scoop`, `.gradle`/`.cargo`/`.m2`, Downloads … and on Linux
  `/var/lib/docker`, `/var/cache`, `~/.cache`, `/snap`) rather than walking all of `C:\`,
  which is slow and spends most of its time in directories that are protected anyway.

- 🛡️ **Safety model.** These commands delete things, so:
  - **Nothing below 1 GB is ever listed.** If the disk is full, a 50 MB utility is not
    the cause.
  - **A query cannot span two size bands.** `2gb-4gb` is fine; `1gb-100gb` is refused.
    An unreviewable list in front of a delete action is how people destroy things.
  - **Protected paths are refused outright** and cannot be overridden — `C:\Windows`,
    `System32`, `Program Files`, `C:\`, `$HOME`; `/`, `/usr`, `/etc`, `/boot`, `/opt/microsoft`.
  - **Apps are uninstalled, never `rm -rf`'d.** Deleting an app's folder leaves its
    uninstaller, registry keys and PATH shims behind — the tool says so and offers the
    real uninstaller first.
  - **Recycle Bin / trash by default; permanent delete requires typing the name.**
  - **Virtual disks are special-cased.** Deleting a `.vhdx`/`.vmdk` destroys every image,
    container and volume inside it — and would not even reclaim the space, because a
    VHDX grows but never shrinks. It recommends `docker system prune` *then* compacting.

- 🧰 **`git-rl -h` — set up `git-rl` in another project.**
  `git-rl` only works in a repository that satisfies its contract (a version source, a
  CHANGELOG it can parse, and a `v*`-tag-triggered pipeline). That knowledge previously
  lived nowhere.

  Run `git-rl -h` from inside the project you want to set up. It asks — via fzf — whether
  you are in the right folder. If yes it creates `docs/` if needed, writes
  **`docs/git-release-help.md`** into the project, and copies an **AI setup prompt** to
  your clipboard. If no, it tells you to navigate there and exits **without printing
  anything** — dumping a 13,000-character prompt into the scrollback of the wrong
  directory helps nobody.

  The generated file is self-contained: the **AI prompt** (paste it into any assistant and
  it builds the version file, CHANGELOG and all six workflows, then verifies them) *and*
  the **manual** — how to cut a release by hand, how to abort a bad one, and post-release
  verification. So the project keeps everything even if PowerFlow is never installed on
  that machine again.

  Source docs: `docs/git-rl/SETUP-PROMPT.md` and `docs/git-rl/README.md`.

- 🧪 **CI distro matrix.** `release-validate-linux.yml` now installs PowerFlow on **Debian
  12/13, Ubuntu 22.04/24.04, Fedora, Arch, openSUSE and Alpine** — all five package
  managers — and asserts on each that pwsh *runs*, all five dependencies install, the
  profile loads, and the GNU coreutils are not shadowed. A release can no longer ship a
  distro that was never executed.

### Fixed

- 📦 **`docs/git-rl/` did not survive installation.** `install.ps1` copied only `config/`,
  `components/`, `platform/` and `windows-only/`. But `git-rl -h` **reads** those docs at
  runtime to write the guide into a user's project — they are a dependency, not
  documentation. On a real install they were absent, so `git-rl -h` silently fell back to
  fetching from GitHub and simply failed offline. The installer now ships them, the
  uninstaller removes them, and CI asserts they survive an install.

- 🩹 **A failed install left the machine permanently broken.** If an earlier attempt
  installed the wrong Microsoft repo (e.g. a *bookworm* source on a *trixie* box), its
  SHA1-signed key poisons **every** subsequent `apt-get update`. Because `install.sh` runs
  `set -e`, the script then aborted on its very first apt call — *before* reaching the
  fixed repo logic — so re-running even a corrected installer could never recover. The
  installer now detects a stale Microsoft source, **purges** it (`dpkg --purge`, not `-r`,
  which would leave the conffile registered and trigger an interactive
  `"end of file on stdin at conffile prompt"` failure), and treats third-party repo errors
  as non-fatal.
- 💥 **PowerShell "installed" but could not run on Fedora / Arch / openSUSE / Alpine.**
  The release-archive fallback installs no runtime libraries, so pwsh died on first use
  with `"Couldn't find a valid ICU package"` — and the installer reported
  `✅ PowerShell installed ()` and carried on, because it only checked
  `command -v pwsh`. It now installs `libicu`/`icu-libs` first and verifies pwsh **runs**
  (`pwsh --version`) rather than merely existing on PATH.
- 📦 **`dnf` / `zypper` never added the Microsoft repository** — they imported the signing
  key and then ran `dnf install powershell`, which cannot work because the package does
  not exist without the repo config. Both now install
  `config/<distro>/<version>/packages-microsoft-prod.rpm` first.
- 🏔️ **Alpine could never work** — it is musl, not glibc, so the standard archive is the
  wrong binary. `apk` was also missing from package-manager detection entirely. Alpine now
  gets the `linux-musl` archive and is a supported target.
- 🏹 **Arch no longer dead-ends.** It previously printed "PowerShell is in the AUR" and
  exited; it now installs from the official archive, which needs no AUR helper.

## [3.0.1] - 2026-07-14

### Fixed

- 🐧 **PowerShell could not install on Debian.** `install.sh` built an *Ubuntu* repo URL
  from the distro's `VERSION_ID` without ever reading `ID`, so on Debian it 404'd and fell
  back to a hardcoded `debian/12` repo. That places a *bookworm* source on a *trixie*
  machine, and the bookworm signing key carries a **SHA1** binding signature that Debian
  13's apt rejects: `"SHA1 is not considered secure"` → `"The repository is not signed."`
  The installer now reads the real `ID`/`VERSION_ID` and requests the correct repo.
  Added a universal fallback that installs PowerShell from Microsoft's official release
  archive (no repo, no GPG key), so repo-signing problems cannot block installation.

## [3.0.0] - 2026-07-14

> 🐧 **Linux is back — rebuilt from scratch on a shared codebase.**
>
> The old Ubuntu port was a 4,160-line parallel re-implementation in bash/zsh/fish.
> Every feature existed twice and the two halves drifted until the Linux one rotted.
> It has been **deleted and replaced** by a Linux platform layer that shares one
> codebase with Windows, so it cannot drift again.
>
> - **Windows users — nothing to do.** Every command behaves exactly as before.
> - **Linux users — a real port, for the first time.** `curl … install.sh | bash`,
>   or a graphical installer. Your GNU coreutils are left alone.
> - **WSL users — unaffected.** `open-ubuntu` / `open-nt u` still open a WSL tab.
>
> ⚠️ **Breaking:** the old bash `.bashrc` port and its `ubuntu-install.sh` are gone.
> 📖 **[Upgrade guide → docs/migration/v3-upgrade.md](https://github.com/Syntax-Read3r/powerflow/blob/main/docs/migration/v3-upgrade.md)**

### Added

- 🐧 **Linux support (PowerShell 7).** PowerFlow now runs natively on Linux from the
  same codebase as Windows — not a second implementation. `nav`, the whole `git-*`
  suite, `gh-l`, bookmarks, fuzzy pickers, `set-path`, `shutdown` and `pwsh-h` all work.
- 🧩 **Platform adapter layer (`platform/<os>/adapters/`).** `components/` is now
  entirely OS-agnostic and calls adapters (`Copy-ToClipboard`, never `Set-Clipboard`).
  Nine adapters implement the same 32-function contract on each OS:

  | Adapter | Windows | Linux |
  |---|---|---|
  | clipboard | `Set-Clipboard` | `wl-copy` → `xclip` → `xsel` |
  | packages | Scoop | apt / dnf / pacman / zypper / apk |
  | elevation | `WindowsPrincipal` | `id -u` / sudo |
  | openers | `explorer.exe` | `xdg-open` |
  | terminal | Windows Terminal + SendKeys | tmux windows |
  | power | `shutdown.exe` | `shutdown -h +N` |
  | env | registry PATH | managed rc fragment |
  | locations | `%LOCALAPPDATA%` / `%TEMP%` | XDG dirs / `$TMPDIR` |
  | pwsh-update | winget / MSI / Store | apt / snap |

- 📦 **Two Linux installers, one installer.** `install.sh` (terminal) and
  `install-gui.sh` (zenity → kdialog → yad → terminal fallback) are thin front-ends;
  both delegate to the same `install.ps1` that Windows uses. Writing a second bash
  installer is the exact duplication that killed the old port.
- 🗑️ **Manifest-based uninstall.** The installer records what it placed and which tools
  it installed. **A dependency you already had is never removed** — the old uninstaller
  ripped out shared Scoop tools regardless, and the old bash one deleted `~/.bashrc`
  outright. Reachable three ways: `powerflow-uninstall`, `install.sh --uninstall`, or
  the GUI.
- 🚧 **CI enforces the architecture.** `release-validate.yml` fails the release if any
  file under `components/` calls an OS API directly, or if an adapter exists on only one
  platform. A new `release-validate-linux.yml` job proves **install → load → use →
  uninstall** on a real `ubuntu-latest` box and **blocks publish** if Linux is broken.
  The old port had no such check, which is why it rotted silently.
- 🛡️ **Shared elevation helpers (`Test-Admin`, `Assert-Admin`)** — one consistent
  Administrator/root check for every admin-gated command.

### Changed

- ⏰ **`shutdown` maximum delay raised to 6 hours** (was 3). `shutdown 6h` now works.
  The 10-minute minimum and `shutdown cancel` / `s c` are unchanged.
- 🐧 **Linux keeps its GNU coreutils.** PowerShell resolves
  `Alias → Function → Cmdlet → native binary`, so PowerFlow's `rm`/`mv` functions and
  `cat`/`cp` aliases would have **shadowed the real tools**. They no longer do:

  | On Linux | Behaviour |
  |---|---|
  | `rm` `mv` `cp` `cat` `mkdir` `touch` `rmdir` `which` `grep` | the **real GNU tools**, untouched |
  | **`del`** | PowerFlow's smart removal (what `rm` is on Windows) |
  | **`mvf`** | PowerFlow's cut-and-paste move (what `mv` is on Windows) |
  | `ls` `la` `ll` | PowerFlow's pretty listing (deliberately overridden) |

  This matters: PowerFlow's `rm somedir` recursively deletes a tree after one prompt,
  while GNU `rm somedir` **refuses** without `-r`. Shadowing it would have silently
  removed a seatbelt Linux users rely on. **Windows behaviour is unchanged.**
- 📦 **`install.ps1` now installs the whole component tree.** It previously downloaded
  only the bootloader, leaving `config/` and `components/` missing — the profile could
  not actually load from a fresh install.
- ⚙️ **Release scripts are shipped, not generated.** The CI used to rebuild `install.ps1`
  from a here-string embedded in YAML, which could silently drift from the real file.

### Fixed

- 🗑️ **`rm` now supports wildcards and multiple targets**: `rm *.log` and
  `rm a.txt b.txt` previously matched nothing and silently deleted nothing —
  every argument was joined into a single literal path (`"a.txt b.txt"`), which
  never resolved. Each argument is now resolved as its own path pattern.
  Multi-target deletes list every match and take one confirmation; `-f` still
  skips it. Unquoted filenames with spaces (`rm my report.txt`) still work, and
  names with wildcard characters (`rm build[1].log`) now resolve too.
- 🖥️ **`$IsWindows` does not exist on PowerShell 5.1** — it is `$null`, which is falsy.
  Platform detection checks `PSEdition -eq 'Desktop'` first, so a 5.1 box is correctly
  identified as Windows. A naive check would have failed to load the profile entirely
  for every 5.1 user.
- 🐧 **`$env:TEMP` / `$env:USERPROFILE` are unset on Linux** — state files (update
  markers, bookmarks) would have been written to bogus paths. Components now go through
  `Get-TempPath` / `Get-HomePath` adapters.
- 📦 **Dependency install failed for *every* tool on a clean Linux box** — `apt-get install`
  was called without ever running `apt-get update`, so on a fresh machine (or container)
  the package lists are empty and even `git` fails with "Unable to locate package".
  The index is now refreshed once per session.
- 📦 **`starship` and `lsd` are not in Ubuntu's repos at all** — apt could never install
  them, so `ls` had no `lsd` and the prompt had no `starship`. They are now fetched from
  their GitHub releases, using PowerShell's own web cmdlets rather than `curl` (a slim
  image often has neither `curl` nor `wget`, which made the old fallback fail silently).
- 🗑️ **Uninstall claimed to remove tools it did not remove** — removals were batched
  (`apt-get remove starship zoxide lsd`), and apt aborts the *entire* command if one name
  is not an apt package. A single unpackaged tool silently left every other tool installed.
  Removal is now one package at a time, and binaries installed to `/usr/local/bin` are
  deleted directly since the package manager cannot see them.
- ⛔ **The startup update check could block a non-interactive shell** — it ran during
  profile load and called `Read-Host`, so in CI, a script, or `curl … | bash` it would wait
  for input that never comes. It now skips prompting when stdin is redirected.
- 🧪 **`install.sh` ignored a local checkout and always downloaded `main`** — which meant
  the Linux CI job checked out the tag being released and then validated *different* code.
  It now installs from the checkout when run inside one.
- 🐧 **PowerShell could not install on Debian** — `install.sh` always built an *Ubuntu*
  repo URL from the distro's `VERSION_ID` (it never read `ID`), so on Debian it 404'd and
  fell back to a **hardcoded `debian/12`** repo. That put a *bookworm* source on a
  *trixie* box, and the bookworm signing key carries a **SHA1** binding signature that
  Debian 13's apt rejects outright:
  `"OpenPGP signature verification failed … SHA1 is not considered secure"` →
  `"The repository … is not signed."` The installer now reads the real `ID`/`VERSION_ID`
  and requests the correct repo (`config/debian/13/…`, which exists and works). Added a
  universal fallback that installs PowerShell from Microsoft's official release archive —
  no repo, no GPG key, so repo-signing problems cannot block installation on any distro.
  Verified end-to-end on Debian 13 (trixie).
- 💥 **Dependency install crashed for every non-root user** — `"The term 's' is not
  recognized"`. PowerShell **unrolls a single-element array into a scalar**, so
  `$sudo = if (root) { @() } else { @('sudo') }` produced the *string* `'sudo'`, making
  `$sudo + $cmd` a string concatenation rather than an array one. `$full[0]` then indexed
  the first **character** — `s`. It only broke when *not* root (as root the empty array
  concatenates correctly), so it passed in a root container and failed on every real user.
  All elevated calls now go through a single `Invoke-Elevated` builder.

### Removed

- 🐧 **The old Ubuntu/bash port is gone** — `ubuntu/` deleted (`.bashrc`, a 2,105-line
  `.zshrc`, `install.sh`, `uninstall.sh`, `install-essentials.sh`, `nav.fish` and its
  READMEs — 4,160 lines), along with `ubuntu-install.sh` / `ubuntu-uninstall.sh` from
  the release pipeline.

  It was a parallel re-implementation, which is why it rotted. **Linux is not gone —
  it is rebuilt** on the shared codebase above. If you installed the old port, see the
  [upgrade guide](https://github.com/Syntax-Read3r/powerflow/blob/main/docs/migration/v3-upgrade.md)
  to restore your `.bashrc` backup.
- ℹ️ Windows-side WSL support is **unaffected**: `open-ubuntu`, `open-wsl-simple` and
  `open-nt u` still launch a WSL tab from Windows Terminal with path bridging.

## [2.2.1] - 2026-05-25

### Fixed
- 🏢 **`gh-l-org` organisation selection parsing**: fixed a bug where selecting
  an organisation from the fzf picker could fail with
  `Could not parse organisation name from selection.` The picker now stores the
  organisation login in a stable hidden field instead of parsing it from the
  emoji-decorated display text.

## [2.2.0] - 2026-05-24

### Added
- 🔔 **Version display on startup**: profile load line now shows the running version
  (`✅ PowerFlow v2.2.0 loaded`) so the current version is always visible without
  running a command.
- 📋 **3-option update prompt**: when a new version is available the bare `y/n/s` prompt
  is replaced with a numbered menu — `1) Install now`, `2) Skip today`,
  `3) Turn off update reminders`.
- 🔕 **Persistent reminder toggle (option 3)**: choosing option 3 permanently writes
  `$script:CHECK_PROFILE_UPDATES = $false` to `config/PowerFlow.settings.ps1` so
  the setting survives profile reloads without manual editing.
- 🔔 **`pwsh-reminders` command**: interactive toggle for update reminder notifications.
  Shows current ON/OFF status and flips it by rewriting the settings file. Re-enabling
  clears the daily check marker so the update check fires on the very next load.

### Fixed
- 📦 **README install URL**: changed from `releases/latest/download/install.ps1` to
  `raw.githubusercontent.com/main/install.ps1` — the old URL resolved to v1.0.5 because
  newer releases were never confirmed to have created GitHub Release objects.

### Documentation
- 📋 **`docs/instructions.md`**: added mandatory post-release verification rule to §9
  and a CHANGELOG ordering convention so release drift cannot recur silently.

## [2.1.0] - 2026-05-24

### Added
- 🏢 **GitHub Organisation Browser** (`gh-l-org`): Browse and bulk-clone GitHub
  organisation repositories from the terminal.
  - **Org picker**: fzf list of all organisations the authenticated user belongs to
  - **Repo picker**: identical column layout to `gh-l` — privacy, name, last push date,
    24h commits, 1w commits, language
  - **Action menu**: clone selected repo, clone ALL repos into `.\<orgName>\` folder,
    open in browser, copy HTTPS or SSH URL
  - **Bulk clone**: uses `Push-Location`/`Pop-Location` to restore CWD; reports per-repo
    success/failure counts on completion
  - **Token scope fallback**: automatically retries with `type=public` and warns user if
    token lacks `read:org` scope
  - **Direct org argument**: `gh-l-org mycompany` skips the org picker
  - **Shared token helpers**: `_GhL-SetToken`, `_GhL-GetToken`, `_GhL-CommitCount`
    extracted to module level — shared by `gh-l` and `gh-l-org`, compiled once per session

## [2.0.1] - 2026-05-21

### Fixed
- 🐛 **`nav` multi-word query truncation**: `nav source code` previously only searched for `"source"` — every word after the first was silently dropped. Extra positional arguments are now joined into a single query string before being passed to fzf (or the BFS fallback), so `nav source code` correctly searches for `"source code"`.

## [2.0.0] - 2026-05-19

### Breaking Change — Modular Architecture
The profile is no longer a single monolithic file. `Microsoft.PowerShell_profile.ps1` is now a thin bootloader (~109 lines) that dot-sources 28 component files organized by domain. **Installation must use the `powerflow-v2.0.0.zip` archive** — downloading only the profile file will produce a broken install.

### Architecture
- **Component-based layout** inspired by React feature-folder conventions
- **28 component files** split across 10 domain folders under `components/`
- **`config/`** folder for settings (`PowerFlow.settings.ps1`) and environment init (`PowerFlow.paths.ps1`)
- **`_pf_source` bootloader helper** — warns on missing components instead of hard-failing, portable via `$script:PowerFlowRoot`
- **`COMPONENTS.md`** — registry table of every file, domain, and exported function
- **`IMPORT_ORDER.md`** — documented rationale for load order at each stage
- **`docs/`** and **`tests/`** scaffold directories for future growth

### Changed
- `$script:POWERFLOW_VERSION` moved from main profile to `config/PowerFlow.settings.ps1`
- Release workflow updated: version validation now checks `config/PowerFlow.settings.ps1`; releases now ship a `powerflow-v2.0.0.zip` archive containing the full component tree
- Install script updated to download and extract the zip archive into the profile directory

## [1.0.5] - 2025-01-23

### Added
- 🚀 **Automatic GitHub Repository Creation**: `git-a` now creates remote repositories on-the-fly
  - **Smart Remote Detection**: Automatically detects when no remote repository exists
  - **GitHub CLI Integration**: Checks for `gh` installation and authentication before offering to create
  - **Interactive Repository Setup**: Beautiful fzf interface for repository configuration
  - **Naming Convention Options**: Choose from kebab-case, snake_case, PascalCase, camelCase, or custom
  - **Visibility Selection**: Interactive private/public repository selection with clear descriptions
  - **Seamless Workflow**: Creates remote, sets origin, and pushes in one smooth operation
  - **Error Recovery**: Handles deleted remotes and offers to recreate them
  - **Authentication Status**: Shows current GitHub user during repository creation
- 🖥️ **Cross-Platform Terminal Integration**: Enhanced `open-nt` function with shell switching
  - **PowerShell from Ubuntu**: `open-nt pwsh` or `open-nt p` to launch PowerShell tabs from Ubuntu
  - **Ubuntu from PowerShell**: `open-nt ubuntu` or `open-nt u` to launch Ubuntu tabs from PowerShell
  - **Smart Path Conversion**: Automatically converts WSL paths ↔ Windows paths when switching shells
  - **Command Prompt Support**: `open-nt cmd` to open Command Prompt tabs from either environment
  - **Fallback Handling**: Graceful degradation when Windows Terminal is unavailable
- 🐧 **Ubuntu `open-nt` Function**: Complete implementation for Ubuntu/WSL environments
  - **Cross-shell navigation**: Launch any shell from Ubuntu terminal
  - **Windows Terminal integration**: Seamless tab management across environments
  - **Path translation**: Intelligent handling of /mnt/ paths to Windows drive letters

### Enhanced
- **`git-a` Workflow**: Now handles the complete git lifecycle from init to push
  - **Repository initialization**: Offers to init git if not in a repository
  - **Remote status display**: Shows if repository is local-only or has remote
  - **Upstream handling**: Automatically sets upstream on first push to new branches
  - **Complete automation**: From local changes to live GitHub repository in one command
- **PowerShell `open-nt`**: Extended existing function with cross-platform shell selection
- **Ubuntu Help System**: Updated `wsl_help` to include `open-nt` cross-platform usage
- **Documentation**: Comprehensive coverage of cross-platform terminal features

### Fixed
- 🐛 **`git-a` Syntax Errors**: Resolved critical issues in the git-a function
  - **Incomplete regex pattern**: Fixed unclosed regex replacement for repository name sanitization
  - **Duplicate code removal**: Eliminated ~140 lines of duplicated code in `Create-RemoteRepository` function
- 🔤 **Naming Convention Functions**: Improved word boundary detection in case conversion
  - **Smart word detection**: Now properly handles camelCase, PascalCase, snake_case, and kebab-case
  - **Single word preservation**: Fixed issue where single words like "back" were split into "b-a-c-k"
  - **Enhanced patterns**: Better regex patterns for detecting transitions between words and acronyms
  - **Examples**: "MyProject" → "my-project", "XMLParser" → "xml-parser", "back" → "back" (not "b-a-c-k")

## [1.0.4] - 10-07-2025

### Added
- 🚀 **Professional Next.js Project Creator**: `create-next` / `create-n` command
  - **Database Selection**: Choose from PostgreSQL+Prisma, Supabase, MongoDB, MySQL+Prisma, or SQLite+Prisma
  - **Complete CI/CD Pipeline**: 3 GitHub Actions workflows (ci.yml, docker-build.yml, deploy.yml)
  - **Docker Integration**: Development and production Docker configurations with database services
  - **Enterprise Structure**: Professional folder organization with all necessary directories
  - **Comprehensive Documentation**: API docs, development guide, and deployment guide auto-generated
  - **Database-Specific Configurations**: Tailored setup for each database type with proper connection strings
  - **TypeScript Ready**: Full TypeScript support with database-specific type definitions
  - **Beautiful Interface**: Same fzf-powered interface as `git-a` with database selection
- 🏷️ **Version release workflow**: `git-a -VersionRelease` / `git-a -vr` 
- 🤖 **GitHub Actions integration**: Automatic release creation when version tags are pushed
- 🎯 **One-command releases**: Update version → `git-a -vr` → Automatic release generation
- ✅ **Smart release validation**: Ensures profile version matches git tag
- 📦 **Auto-generated release assets**: install.ps1, uninstall.ps1, and release notes

### Enhanced
- `git-a` function now supports version release workflow
- Help documentation updated with new release commands and `create-next` functionality
- Release process streamlined from manual to automated
- `pwsh-h` help system expanded with comprehensive Next.js project creation documentation

### Technical Details
- **`create-next`**: Creates production-ready Next.js applications with:
  - Latest Next.js 15+ with App Router, TypeScript, Tailwind CSS, ESLint
  - Database integration: Prisma schemas, Supabase client, or Mongoose models
  - Docker Compose configurations for development and production
  - GitHub Container Registry integration
  - Automated dependency installation based on database choice
  - Environment variable templates for each database type
  - Professional npm scripts for database operations and Docker management
