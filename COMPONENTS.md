# PowerFlow Component Registry

Every file in the architecture, its domain, the platforms it runs on, and the functions it exports.

## Architecture in one line

`components/` holds **platform-agnostic** domain logic and never calls an OS API directly.
It calls **adapters**. `platform/<os>/adapters/` implements the same contracts per OS.
This is why one codebase runs on both Windows and Linux — see
[docs/plan/linux/architecture.md](docs/plan/linux/architecture.md).

---

## Bootloader & Config

| File | Platform | Exports / Purpose |
|------|----------|-------------------|
| `Microsoft.PowerShell_profile.ps1` | Both | Platform-aware bootloader. Detects the OS, loads adapters → components → bindings. Also `$PROFILE` on Linux. |
| `config/PowerFlow.settings.ps1` | Both | `$script:POWERFLOW_VERSION`, `$script:POWERFLOW_REPO`, `$script:CHECK_*` flags, DB creds |
| `config/paths.windows.ps1` | Windows | Scoop PATH, Starship, Zoxide, auto-navigate |
| `config/paths.linux.ps1` | Linux | `~/.local/bin`, XDG dirs, PowerFlow PATH fragment, Starship, Zoxide, auto-navigate |

---

## Platform adapters — the OS boundary

Both platforms implement the **same contract**. Components call these names and never
know which OS they are on. CI enforces parity (`release-validate.yml`).

| Adapter | Contract | Windows backend | Linux backend |
|---------|----------|-----------------|---------------|
| `adapters/elevation.ps1` | `Test-Admin`, `Assert-Admin` | `WindowsPrincipal` | `id -u` / `sudo` |
| `adapters/clipboard.ps1` | `Copy-ToClipboard`, `Get-FromClipboard`, `Test-ClipboardSupport` | `Set-Clipboard` | `wl-copy` → `xclip` → `xsel` |
| `adapters/packages.ps1` | `Get-PackageManagerName`, `Test-PackageManager`, `Install-PackageManager`, `Test-Dependency`, `Install-Dependency`, `Uninstall-Dependency`, `Get-DependencyInstallHint` | Scoop | apt / dnf / pacman / zypper / apk |
| `adapters/openers.ps1` | `Open-Path`, `Open-Editor`, `Open-Url`, `Get-FileManagerName` | `explorer.exe`, `code` | `xdg-open`, `$EDITOR` |
| `adapters/terminal.ps1` | `New-TerminalTab`, `Switch-TerminalTab`, `Close-TerminalTabAt`, `Send-TerminalKeys`, `Test-TerminalSupport` | Windows Terminal (`wt`) + SendKeys | tmux windows |
| `adapters/power.ps1` | `Invoke-Shutdown`, `Stop-Shutdown` | `shutdown.exe /s /t` | `shutdown -h +N` |
| `adapters/env.ps1` | `Get-PersistentPath`, `Add-PersistentPathEntry`, `Test-PersistentPathEntry`, `Get-PathScopeLabel` | Registry (`SetEnvironmentVariable`) | PowerFlow-managed rc fragment |
| `adapters/locations.ps1` | `Get-StarshipConfigPath`, `Get-TerminalSettingsPath`, `Get-TempPath`, `Get-HomePath`, `Get-PowerFlowDataPath`, `Get-PowerFlowConfigPath` | `%LOCALAPPDATA%`, `%TEMP%` | XDG (`~/.config`, `~/.local/share`), `$TMPDIR` |
| `adapters/pwsh-update.ps1` | `Invoke-PowerShellUpdate` | winget / MSI / Store | apt / snap / dotnet-tool |
| `adapters/apps.ps1` | `Get-InstalledApplication`, `Uninstall-Application`, `Get-DiskHotspot`, `Measure-FolderSize`, `Move-ToTrash`, `Remove-PathPermanently`, `Test-TrashSupport`, `Test-ProtectedPath` | registry + Scoop; Recycle Bin | dpkg / rpm / pacman; `gio trash` |
| `adapters/perms.ps1` | `Get-FileMode`, `Test-PermsSupported`, `Get-Umask`, `Set-Umask` | **returns `$null`** — Windows has ACLs, not POSIX mode bits, and inventing a fake `755` would teach something false | `stat(1)` for the mode; **libc `umask(2)` via P/Invoke** for the umask³ |
| `adapters/health.ps1` | `Get-MachineInfo`, `Get-PowerSnapshot`, `Get-StabilityEvents`, `Get-FirmwareInfo`, `Set-CpuMaxState`, `Export-StabilityReport` | `powercfg` (hex decoded, stock plans by GUID), WHEA/WER via `Get-WinEvent`, CIM, minidumps | cpufreq governor + `scaling_max_freq`, kernel MCE via `journalctl`, `/sys/class/dmi/id` (no root needed), `/var/crash` |

### Command bindings — loaded **after** components

| File | Platform | Purpose |
|------|----------|---------|
| `platform/windows/bindings.ps1` | Windows | Provides `grep`, `less`, `pwd`, `which` (Windows lacks them). PowerFlow's `rm`/`mv`/`ls` keep their natural names — there is no GNU tool to shadow. |
| `platform/linux/bindings.ps1` | Linux | **Stops PowerFlow shadowing the GNU coreutils.** Frees `rm`/`mv`/`cp`/`cat`/`mkdir`/`touch`/`rmdir`/`which`; re-exposes PowerFlow's versions as **`del`** and **`mvf`**. Exports: `del`, `mvf` |

---

## Components — shared domain logic (both platforms)

| File | Domain | Functions |
|------|--------|-----------|
| `components/core/version.ps1` | Core | `Check-PowerFlowUpdates`, `powerflow-update`, `Get-PowerFlowVersion`, `powerflow-version`, `pwsh-reminders` |
| `components/core/dependencies.ps1` | Core | `Get-RequiredTools`, `Initialize-Dependencies`, `Check-PowerShellUpdates` |
| `components/core/recovery.ps1` | Core | `pwsh-recovery`, `powerflow-uninstall` |
| `components/shared/strings.ps1` | Shared | `Convert-ToKebabCase`, `Convert-ToSnakeCase`, `Convert-ToPascalCase`, `Convert-ToCamelCase` |
| `components/shell/bash-compat.ps1` | Shell | `export`, `unset`, `source`, `alias`¹, `unalias`, `jobs`, `fg`, `bg` — the bash builtins PowerShell lacks |
| `components/shell/history.ps1` | Shell | `history`, `Get-LastCommand`, `Get-LastArg` + PSReadLine handlers for **`!!`** and **`!$`** |
| `components/shell/lessons.ps1` | Shell | **`lesson`**, **`l`** (alias), `Show-LessonIndex`, `Get-LinuxLesson`, `Show-Lesson`, `Get-LessonTopics` — the **one source of truth** for every lesson. Tab-completes commands, brothers and topics. |
| `components/shell/teach.ps1` | Shell | `perms`, `linux-lessons`, `Show-PermissionBreakdown`, `Format-ModeColons`, `Get-LessonMode` |
| `components/shell/brothers.ps1` | Shell | `changemode`, `changeowner`, `changegroup`, `defaultmode`⁴, `whoamifull`, `mygroups`, `lookupentry`, `findfile`, `findtext`, `removefile`, `archive`, `listprocs`, `stopproc`, `service`, `systemlogs`, `listfiles`, `makelink`, `fileinfo`, `firstlines`, `lastlines`, `dirsize`, `diskfree`, `listdisks`, `listports`, `Get-UmaskResult` — each supports `-lesson` |

> ¹ **`alias` is a function, not `Set-Alias`.** PowerShell's `Set-Alias` maps a name to a
> single command and **cannot carry arguments**, so `alias ll='ls -la'` — the most common
> thing anyone does with an alias in bash — is impossible with it. PowerFlow compiles
> bash-style aliases into functions instead, which can.
>
> ⁷ **`pc-cap` records before it changes — the order is the feature.** The prior plan and
> cap are written to `~/.powerflow-power-state.json` *before* anything is modified; a second
> `pc-cap` refuses while a record exists (100→85→70 must not make "restore" mean 85);
> restore verifies by re-querying and only then deletes the record; and `pc-whoami` banners
> for as long as the record exists, so an abandoned cap cannot go unnoticed. Born from a
> real incident where a "temporary" 85% cap was left behind with no record of the original.
> The gate now also forbids `powercfg`/`Get-CimInstance`/`Get-WinEvent` in `components/`.
>
> ⁶ **`mv` is overloaded by argument count, deliberately.** One argument **cuts** (the
> PowerFlow cut/paste workflow: `mv <file>` … `mv-t`). Two or more is a **real move**, because
> `mv a.txt b.txt` used to join its arguments into the filename `"a.txt b.txt"`, find nothing,
> and silently do nothing at all. The one ambiguous case — `mv my report.txt`, an unquoted name
> containing a space — still cuts, but only when that reading is unambiguous (the joined name
> exists *and* the first word does not). Overwriting prompts unless `-f`, matching PowerFlow's
> `rm` rather than GNU, which clobbers silently.
>
> ⁵ **`Split-GnuArgs` is why `rm -rf` works on Windows.** These functions take **no
> `param()` block**, deliberately. A `param()` block makes PowerShell try to bind `-r`,
> `-p` and `-f` as *parameter names* — it then either throws (*"the parameter name 'p' is
> ambiguous"*) or silently drops the flag into `$args`, where it is mistaken for a
> filename. That is the identical bug that made `ls -ld dir` list the wrong directory.
> Hand-parsing `$args` is the only way a PowerShell function can accept `rm -rf x`.
> It handles bundled shorts (`-rf`), long flags (`--recursive`), and `--` (so you can
> delete a file genuinely named `-rf`). None of it runs on Linux — bindings hands those
> names back to the GNU coreutils.
>
> ³ **`umask` is a shell builtin, not a binary.** There is no `/usr/bin/umask` to run, and
> `sh -c 'umask 022'` sets the umask of a subshell that then exits — changing nothing. It
> must be done in-process, so the Linux adapter P/Invokes libc's `umask(2)` (verified on
> both glibc and musl). Note that `umask(2)` has **no getter**: it always *sets*, returning
> the previous value, so `Get-Umask` sets `0`, captures the old value, and restores it
> immediately. Skip that restore and you have silently made every new file world-writable.
>
> ⁴ **`defaultmode` does not go through `Invoke-Brother`** for exactly that reason — there
> is no binary to exec. It calls the adapter, and prints what the mask actually *produces*
> (`022` → files `644`, dirs `755`), because a umask is **subtractive** and that is the
> part people get wrong.
>
> **PowerFlow does not wrap the real command names.** An earlier design defined a function
> per command so `chmod -lesson` would work; it was removed. A PowerShell function does not
> forward stdin, so a wrapped `grep` would make `cat f | grep x` **hang** — which meant
> `grep`/`rm`/`cp`/`cat` had to be denylisted, i.e. the commands a beginner most needs were
> the ones that could not have a lesson. `lesson <command>` shadows nothing, so it covers
> every command instead. See [components/shell/lessons.ps1](components/shell/lessons.ps1).
>
> ² **`nav` used to hardcode `~/Code`** — as the literal string `"$HOME\Code"`, which on
> Linux interpolates to `/home/you\Code` (a backslash is a legal *filename* character
> there, not a separator) and therefore matches nothing, ever. Roots are now a
> configurable list: `~/Code` on Windows, `~` on Linux, plus whatever you add.
> **The default is deliberately not `/`** — that walks `/proc`, `/sys`, `/dev` and `/run`,
> which are kernel-backed pseudo-filesystems, and throws permission errors across most of
> the rest. Add the real ones you want instead: `nav roots add /srv`.
| `components/navigation/roots.ps1` | Navigation | `Get-NavSearchRoots`, `Get-NavDefaultRoots`, `Add-NavSearchRoot`, `Remove-NavSearchRoot`, `Reset-NavSearchRoots`, `Show-NavSearchRoots`, `Format-NavPath` — **where `nav` looks**, persisted to `~/.nav_roots.json`² |
| `components/navigation/bookmarks.ps1` | Navigation | `Initialize-DefaultBookmarks`, `Get-Bookmarks`, `Save-Bookmarks`, `Add-Bookmark`, `Remove-Bookmark`, `Rename-Bookmark`, `Show-BookmarkList` |
| `components/navigation/projects.ps1` | Navigation | `Search-Projects` |
| `components/navigation/nav.ps1` | Navigation | `nav`, `nav roots`, `Test-NavFunction`, `z` (alias) |
| `components/navigation/directory.ps1` | Navigation | `here`, `..`, `...`, `....`, `.....`, `~`, `back`, `cd-` (alias), `copy-pwd` |
| `components/files/listing.ps1` | Files | `ls`, `la`, `ll`, `clr` (alias), `cat` (alias)¹, `cp` (alias)¹ |
| `components/files/operations.ps1` | Files | `rm`¹, `mv`¹ ⁶, `Invoke-GnuMove`, `mv-t`, `mv-c`, `rmdir`¹, `touch`¹, `mkdir`¹, `Split-GnuArgs`⁵ |
| `components/files/rename.ps1` | Files | `rn` |
| `components/files/clipboard.ps1` | Files | `open-pwd`, `op`, `paste-file`, `copy-file`, `cf`, `pf` |
| `components/git/remote.ps1` | Git | `Create-RemoteRepository` |
| `components/git/commit.ps1` | Git | `git-a`, `git-a-plus`, `git-aa`, `git-aq`, `git-ad`, `git-am` |
| `components/git/branches.ps1` | Git | `git-branch`, `Invoke-DeleteBranch`, `git-b`, `git-cm`, `git-bd`, `git-bD`, `git-c.sb` |
| `components/git/rollback.ps1` | Git | `git-rba`, `grba` (alias), `git-rb` |
| `components/git/interactive.ps1` | Git | `git-l`, `git-log`, `git-s`, `git-st`, `git-pick`, `git-p`, `git-stash`, `git-remote`, `git-sh`, `git-r` |
| `components/git/version-files.ps1` | Git | `Get-ProjectVersionSource`, `Get-ProjectVersion`, `Set-ProjectVersion`, `Update-ProjectVersion`, `Test-VersionDrift`, `Get-VersionFileDefinition`, `Read-TomlSectionVersion` — detects and rewrites `package.json` / `pyproject.toml` / `Cargo.toml` / `*.csproj` / `build.gradle` / `VERSION` / PowerFlow settings |
| `components/git/release.ps1` | Git | `git-release`, `git-rl`, `git-rl -h` (setup a new project), `Show-GitReleaseSetupPrompt`, `Write-GitReleaseGuide`, `Get-GitReleaseDocs` |
| `components/git/reset.ps1` | Git | `git-f`, `git-next` |
| `components/github/browser.ps1` | GitHub | `gh-l`, `gh-l-reset`, `gh-l-status`, `gh-l-org` |
| `components/terminal/tabs.ps1` | Terminal | `send-keys`, `open-nt`, `close-ct`, `next-t`, `prev-t`, `open-t`, `close-t` |
| `components/projects/create-next.ps1` | Projects | `create-next`, `create-n` |
| `components/system/config-files.ps1` | System | `pwsh-profile`, `pwsh-starship`, `pwsh-settings` |
| `components/system/shutdown.ps1` | System | `shutdown`, `s` |
| `components/system/path.ps1` | System | `set-path` |
| `components/system/apps.ps1` | System | `installed-apps`, `i-a` (alias), `disk-big`, `d-b` (alias), `Get-SizeBands`, `Convert-ToBytes`, `Format-Size`, `Format-Age`, `Resolve-SizeRange`, `Show-SizeBandMenu`, `Show-AppPicker`, `Show-BandOverview`, `Invoke-AppAction` |
| `components/system/health.ps1` | System | `pc-whoami` (+ `-power`, `-crashes [-export]`, `-bios`, `-days N`), `pc-cap`⁷ — machine vitals + a CPU cap with guaranteed restoration. Design: [docs/plan/pc-whoami/](docs/plan/pc-whoami/README.md) |
| `components/network/servers.ps1` | Network | `srv` (picker: Enter connect · ctrl-d delete · ctrl-r rename), `srv add`, `srv rm`, `srv rename`, `srv list`, `Show-PFServerPicker`, `Test-ServerOnline`, `Get-PFServers`, `Save-PFServers` — named SSH connections in `~/.powerflow-servers.json`. Status = TCP probe of the ssh port with ICMP tiebreaker: `online` / `no-ssh` / `offline`. `ssh` itself is never shadowed |
| `components/help/registry.ps1` | Help | `Register-PFCommand`, `Get-PFCommandRegistry`, `Get-PFHelpSections` — the **one source of truth** for the command surface. Loads FIRST; every component registers its commands beside their definitions; CI fails the release on an unregistered command |
| `components/help/menu.ps1` | Help | `pwsh-h`, `Show-PFCommandDetail` — rendered entirely from the registry: fzf browser when interactive, generated print otherwise, section/command/lesson filtering |

> ¹ **Rebound on Linux.** `platform/linux/bindings.ps1` removes these so the GNU
> coreutils stay reachable. `rm` → **`del`**, `mv` → **`mvf`**; `cp`/`cat`/`mkdir`/
> `touch`/`rmdir` defer entirely to the native tools.

---

## Windows-only

| File | Platform | Functions |
|------|----------|-----------|
| `windows-only/wsl.ps1` | Windows | `open-ubuntu`, `Get-WindowsTerminalProfiles`, `open-wsl-simple` — launch a WSL tab **from** Windows Terminal. WSL is a Windows concept; this never loads on Linux. |

---

## Installers

| File | Platform | Purpose |
|------|----------|---------|
| `install.ps1` | Both | **THE installer.** Copies the tree, installs deps via the packages adapter, writes `.powerflow-manifest.json`. |
| `uninstall.ps1` | Both | **Manifest-driven.** Removes only what PowerFlow placed. Never removes a dependency the user already had (`installedByPowerFlow: false`). |
| `install.sh` | Linux | Thin bootstrap: detect distro → install pwsh → hand off to `install.ps1`. Contains **no** install logic. |
| `install-gui.sh` | Linux | Graphical front-end (zenity → kdialog → yad → terminal fallback). Delegates to `install.sh`. |
