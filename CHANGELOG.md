# Changelog

All notable changes to PowerFlow will be documented in this file.

## [Unreleased]

### Planning
- Additional database providers
- Testing framework integration
- Enhanced Docker optimizations

## [3.0.0] - Unreleased

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
