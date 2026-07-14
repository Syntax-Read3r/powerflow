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
| `components/navigation/bookmarks.ps1` | Navigation | `Initialize-DefaultBookmarks`, `Get-Bookmarks`, `Save-Bookmarks`, `Add-Bookmark`, `Remove-Bookmark`, `Rename-Bookmark`, `Show-BookmarkList` |
| `components/navigation/projects.ps1` | Navigation | `Search-Projects` |
| `components/navigation/nav.ps1` | Navigation | `nav`, `Test-NavFunction`, `z` (alias) |
| `components/navigation/directory.ps1` | Navigation | `here`, `..`, `...`, `....`, `.....`, `~`, `back`, `cd-` (alias), `copy-pwd` |
| `components/files/listing.ps1` | Files | `ls`, `la`, `ll`, `clr` (alias), `cat` (alias)¹, `cp` (alias)¹ |
| `components/files/operations.ps1` | Files | `rm`¹, `mv`¹, `mv-t`, `mv-c`, `rmdir`¹, `touch`¹, `mkdir`¹ |
| `components/files/rename.ps1` | Files | `rn` |
| `components/files/clipboard.ps1` | Files | `open-pwd`, `op`, `paste-file`, `copy-file`, `cf`, `pf` |
| `components/git/remote.ps1` | Git | `Create-RemoteRepository` |
| `components/git/commit.ps1` | Git | `git-a`, `git-a-plus`, `git-aa`, `git-aq`, `git-ad`, `git-am` |
| `components/git/branches.ps1` | Git | `git-branch`, `Invoke-DeleteBranch`, `git-b`, `git-cm`, `git-bd`, `git-bD`, `git-c.sb` |
| `components/git/rollback.ps1` | Git | `git-rba`, `grba` (alias), `git-rb` |
| `components/git/interactive.ps1` | Git | `git-l`, `git-log`, `git-s`, `git-st`, `git-pick`, `git-p`, `git-stash`, `git-remote`, `git-sh`, `git-r` |
| `components/git/release.ps1` | Git | `git-release`, `git-rl` |
| `components/git/reset.ps1` | Git | `git-f`, `git-next` |
| `components/github/browser.ps1` | GitHub | `gh-l`, `gh-l-reset`, `gh-l-status`, `gh-l-org` |
| `components/terminal/tabs.ps1` | Terminal | `send-keys`, `open-nt`, `close-ct`, `next-t`, `prev-t`, `open-t`, `close-t` |
| `components/projects/create-next.ps1` | Projects | `create-next`, `create-n` |
| `components/system/config-files.ps1` | System | `pwsh-profile`, `pwsh-starship`, `pwsh-settings` |
| `components/system/shutdown.ps1` | System | `shutdown`, `s` |
| `components/system/path.ps1` | System | `set-path` |
| `components/help/menu.ps1` | Help | `pwsh-h` |

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
