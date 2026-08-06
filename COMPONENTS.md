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
| `adapters/packages.ps1` | Shared: `Get-PackageManagerName`, `Test-PackageManager`, `Install-PackageManager`, `Test-Dependency`, `Install-Dependency`, `Uninstall-Dependency`, `Get-DependencyInstallHint`; Windows internal: `Add-ScoopShimToCurrentPath`, `Get-PackageManagerRemovalWarning`, `Confirm-PackageManagerRemoval`, `Uninstall-PackageManager` | required Scoop prerequisite; current-process shim activation; separately confirmed removal | apt / dnf / pacman / zypper / apk |
| `adapters/openers.ps1` | `Open-Path`, `Open-Editor`, `Open-Url`, `Get-FileManagerName` | `explorer.exe`, `code` | `xdg-open`, `$EDITOR` |
| `adapters/terminal.ps1` | `New-TerminalTab`, `Switch-TerminalTab`, `Close-TerminalTabAt`, `Send-TerminalKeys`, `Test-TerminalSupport` | Windows Terminal (`wt`) + SendKeys | tmux windows |
| `adapters/power.ps1` | `Invoke-Shutdown`, `Stop-Shutdown` | `shutdown.exe /s /t` | `shutdown -h +N` |
| `adapters/env.ps1` | `Get-PersistentPath`, `Add-PersistentPathEntry`, `Test-PersistentPathEntry`, `Get-PathScopeLabel` | Registry (`SetEnvironmentVariable`) | PowerFlow-managed rc fragment |
| `adapters/locations.ps1` | `Get-StarshipConfigPath`, `Get-TerminalSettingsPath`, `Get-TempPath`, `Get-HomePath`, `Get-PowerFlowDataPath`, `Get-PowerFlowConfigPath` | `%LOCALAPPDATA%`, `%TEMP%` | XDG (`~/.config`, `~/.local/share`), `$TMPDIR` |
| `adapters/pwsh-update.ps1` | `Invoke-PowerShellUpdate` | winget / MSI / Store | apt / snap / dotnet-tool |
| `adapters/apps.ps1` | `Get-InstalledApplication`, `Uninstall-Application`, `Get-DiskHotspot`, `Measure-FolderSize`, `Move-ToTrash`, `Remove-PathPermanently`, `Test-TrashSupport`, `Test-ProtectedPath` | registry + Scoop; Recycle Bin | dpkg / rpm / pacman; `gio trash` |
| `adapters/perms.ps1` | `Get-FileMode`, `Test-PermsSupported`, `Get-Umask`, `Set-Umask` | **returns `$null`** — Windows has ACLs, not POSIX mode bits, and inventing a fake `755` would teach something false | `stat(1)` for the mode; **libc `umask(2)` via P/Invoke** for the umask³ |
| `adapters/fonts.ps1` | `Get-NerdFontName`, `Test-NerdFont`, `Install-NerdFont`, `Uninstall-NerdFont`, `Get-NerdFontInstructions`, `Get-NerdFontInstallHint` | Scoop nerd-fonts bucket; font registry read for detection | download → `~/.local/share/fonts/PowerFlow-NerdFont` → `fc-cache`; `fc-list` for detection |
| `adapters/login.ps1` | `Get-LoginLaunchState`, `Enable-LoginLaunch`, `Disable-LoginLaunch` | **`'always'` / no-op** — pwsh always sources `$PROFILE`, so there is no login hook to manage | the guarded `~/.bashrc` block (byte-identical to `install.sh --auto-login`) |
| `adapters/sysconfig.ps1` | `Test-SysConfigSupported`, `Get-SysConfigOptions`, `Get-SysConfigChoices`, `Set-SysConfig` | `Set-TimeZone` / `Set-Culture` / `Rename-Computer` / W32Time, each applied for the user — machine-wide ones via a single UAC prompt (`Invoke-ElevatedCommand`). Four settings: keyboard is omitted because a Windows layout is an input-language tip, not a keymap. Validates a value against its own choices first (`Set-Culture` will otherwise write a bogus culture) | `localectl` / `timedatectl` / `hostnamectl`; a domain model (keyboard/timezone/locale/hostname/ntp) so new settings are one row. Keyboard detects vconsole vs X11 (`Get-KeyboardMode`) so Debian/Ubuntu work too |
| `adapters/startup.ps1` | `Get-StartupEntry`, `Set-StartupEntryState`, `Remove-StartupEntry`, `Add-StartupEntry`, `Get-StartupFolderPath` | both Startup folders **and** the HKCU/HKLM `Run` keys, joined against `Explorer\StartupApproved` for each entry's REAL state (Task Manager disables by flag, not deletion). Disable writes the same flag; folder deletes go to the Recycle Bin | XDG autostart `.desktop` files (`~/.config/autostart`, `/etc/xdg/autostart`). `Hidden=true` is the analogue of StartupApproved. A system entry is shadow-copied into the user dir rather than edited — the package owns the original |
| `adapters/health.ps1` | `Get-MachineInfo`, `Get-PowerSnapshot`, `Get-StabilityEvents`, `Get-FirmwareInfo`, `Set-CpuMaxState`, `Export-StabilityReport` — plus internal `Get-GpuInfo`, `Get-MemoryInfo`, `Get-DiskInfo`, `Get-SlotInfo`, `Format-HwVendor` (both platforms), plus contract `Get-ProcessMemoryUsage` (RAM by program, with system-critical + self flags) | `powercfg` (hex decoded, stock plans by GUID), WHEA/WER via `Get-WinEvent`, CIM, minidumps. **GPU:** `Win32_VideoController` filtered of virtual/streaming adapters, VRAM from the display-class registry (`AdapterRAM` is uint32 and wraps >4 GB; on an iGPU it reports shared memory, so only dedicated counts). **RAM:** `Win32_PhysicalMemory` using `SMBIOSMemoryType` (`MemoryType` is 0 on modern boards) + configured vs rated speed | cpufreq governor + `scaling_max_freq`, kernel MCE via `journalctl`, `/sys/class/dmi/id` (no root needed), `/var/crash`. **GPU:** `nvidia-smi` then `lspci -mm` (bracketed product name preferred); integrated vs discrete by PCI bus, not vendor — AMD ships APUs *and* cards; VRAM keyed by PCI slot via `Get-DrmVramBySlot`. **RAM:** `dmidecode -t 17` as root or `sudo -n` (never prompts), else size only with a reason |
| `adapters/proxmox.ps1` | `Test-ProxmoxSupport`, `Get-ProxmoxNodeSummary`, `Get-ProxmoxDisks`, `Get-ProxmoxStorage`, `Get-ProxmoxZfsPools`, `Get-ProxmoxGuests`, `Get-ProxmoxUpdates`, `Get-ProxmoxSmartInfo`, `Get-ProxmoxSmartReport`, `Start-ProxmoxSmartTest`, `Get-ProxmoxDiskSafety`, `Get-ProxmoxDiskEvidence`, `Invoke-ProxmoxCapacityProbe` | **every function returns empty/`$null`** — Proxmox VE is a Debian-based hypervisor and does not exist on Windows. The stubs exist so the component loads and `pmx help` still works⁸ | `pvesh` for the node/guest/storage API, `lsblk -J` + `/dev/disk/by-id` for stable identity, `smartctl -j`, `zpool`, `journalctl -k`, `f3probe` for the capacity probe |
| `adapters/proxmox-management.ps1` | `Test-ProxmoxManagementTransport`, `Invoke-ProxmoxManagementQuery`, `Invoke-ProxmoxManagementChange` plus private allow-list/token builders | SSH only: validates a saved target and maps documented operations to fixed `pvesh`/`qm` token arrays | local `pvesh`/`qm` on Proxmox or the same fixed operations over SSH elsewhere; structured results have `Success`, `Data`, `Error`, `ExitCode`, `NativeCommand` |
| `adapters/team-room.ps1` | `Get-TeamRoomState`, `Set-TeamRoomArm`, `Set-TeamRoomTask`, `Stop-TeamRoomWatcher` — plus internal `Get-TeamRoomBootInstant`, `Get-TeamRoomArmState`, `Get-TeamRoomWatchers`, `Get-TeamRoomTasks`, `Get-TeamRoomStateRoots` | Scheduled Tasks (`TeamChat-<agent>-<repo>`) for the wake connector; `Win32_Process` command lines to find live `node teamchat-wait.js` watchers; `LastBootUpTime` for the boot instant | `/proc/<pid>/cmdline` for watchers (matched on the **script** name — they are all plain `node`), `/proc/uptime` for the boot instant. `Set-TeamRoomTask` **reports it cannot act**: the wake connector registers a Windows Scheduled Task and team-room ships no Linux equivalent — no cron job, no systemd timer⁹ |

> ⁸ **A stub that lies is worse than a stub that is empty.** The Windows Proxmox adapter
> returns `$false`/`@()`/`$null` and never guesses. `pmx` checks `Test-ProxmoxSupport`
> *after* handling `help`, so the help text — the one thing that is useful on a laptop
> while you are reading about the host — still prints, and every other verb says plainly
> that this is not a Proxmox node rather than rendering an empty dashboard.
>
> ⁹ **A cross-platform contract may not fake the half it cannot do.** Both `team-room`
> adapters expose `Set-TeamRoomTask`, because CI's parity check requires it; the Linux one
> prints *why* and returns `$false`. Returning `$true` would have made `team-room start`
> report success for a wake connector that was never installed — the exact class of
> silent lie this command exists to eliminate.

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
| `components/system/health.ps1` | System | `pc-whoami` (+ `-power`, `-crashes [-export]`, `-bios`, `-ram [level|<name>|-min N]`, `-days N`), `Show-RamIndex` (the level map), `Show-RamDetail` (one level, read-only), `Show-RamProcesses` (drill-in with command lines), `Stop-RamProcess` (one PID), `Stop-RamGroup` (whole program, harder warning), `Format-DriveSize`, `pc-cap`⁷ — machine vitals + a CPU cap with guaranteed restoration. Design: [docs/plan/pc-whoami/](docs/plan/pc-whoami/README.md) |
| `components/proxmox/*.ps1` | Both (physical host/disk actions Linux-only) | Ordered domain: `shared`, `config`, `host`, `physical-disks`, `evidence`, `vm-read`, `vm-change`, `snapshots`, `help`, `command`. `pmx` supports local host/disk inspection plus local/SSH VM discovery, clone, CPU/memory, grow-only virtual disks, start/shutdown, and snapshots. Mutations preview, confirm, revalidate, execute an allow-listed adapter operation, verify, and audit. The router only routes; `Get-PmxHelpOverview` and `Get-PmxHelpTopics` provide the complete executable command catalog. | Design: [VM-management plan](docs/plan/proxmox/pmx-vm-management.md); user syntax: `pmx help` |
| `components/system/team-room.ps1` | Both | `team-room` (+ `start <name>`, `stop <name>`, `list`, `help`, `-All`), `Show-TeamRoomList`, `Show-TeamRoomDetail`, `Invoke-TeamRoomAction`, `Format-TeamRoomAge` — **see and stop the agent watchers you started.** Reports all three independent states separately (wake connector · boot-scoped arm stamp · live watcher process) because any one of them alone does nothing¹⁰ |
| `components/system/fonts.ps1` | System | `pwsh-font` — install the Nerd Font the prompt and `ls` need, then print the one manual terminal-config step. All OS work is in the fonts adapter |
| `components/system/login.ps1` | System | `pwsh-autologin` (Linux) — toggle "start PowerFlow on login" without re-running the installer; writes the same guarded hook as `install.sh --auto-login`. `pwsh-exit` (Linux) — drop to bash without closing the SSH session (`exec pwsh` login shell has no bash to fall back to) |
| `components/system/sysconfig.ps1` | Both | `pwsh-config`, `Complete-SysConfigChange` — one fzf-driven menu that **applies** OS settings (timezone/locale/hostname/time-sync, plus keyboard on Linux): systemd on Linux, native cmdlets on Windows. Replaces the Debian-only `dpkg-reconfigure`. Extensible: new settings are a row in the adapter |
| `components/system/startup.ps1` | Both | `start-folder` (alias `startup`), `Show-StartupList`, `Invoke-StartupAction` — one list of everything that runs at login. Picker-as-manager: Enter **toggles** (reversible), ctrl-d deletes (confirmed, name typed back), ctrl-o opens the folder. `start-folder add <path>` / `list` / `open` |
| `components/network/server-privacy.ps1` | Network | `Get-PFServerTarget`, `Format-PFServerPublicRow`, `Invoke-PFServerSsh`, `Test-PFServerInteractiveAuth`, `Show-PFServerAuthenticatedInfo` — the saved-endpoint privacy boundary. Ordinary UI gets alias/status rows; native SSH gets the target tokens; `srv <name> info` reveals details only after successful authentication. Passwords remain entirely with OpenSSH. |
| `components/network/servers.ps1` | Network | `srv` (private alias/status picker: Enter connect · ctrl-d delete · ctrl-r rename), `srv <name> info`, `srv add`, `srv rm`, `srv rename`, `srv list`, `Show-PFServerPicker`, `Test-ServerOnline`, `Get-PFServers`, `Save-PFServers` — named SSH connections in `~/.powerflow-servers.json`. Status = TCP probe of the ssh port with ICMP tiebreaker: `online` / `no-ssh` / `offline`. `ssh` itself is never shadowed. |
| `components/help/registry.ps1` | Help | `Register-PFCommand`, `Get-PFCommandRegistry`, `Get-PFHelpSections`, `Get-PFHelpChapters` — the **one source of truth** for the command surface. Loads FIRST; every component registers its commands beside their definitions; sections fold into chapters (`$PF_HelpChapters`) for the printed manual; CI fails the release on an unregistered command |
| `components/help/menu.ps1` | Help | `pwsh-h` (alias `pwsh-help`) — rendered entirely from the registry. Default is `Show-PFManual`: a grouped, printed manual folded into a few chapters (`$PF_HelpChapters`); `pwsh-h -a` / `pwsh-help -advanced` is the `Show-PFHelpBrowser` fzf finder; `pwsh-h <topic>` filters a section/command/lesson via `Show-PFHelpSections` / `Show-PFCommandDetail` |

> ¹ **Rebound on Linux.** `platform/linux/bindings.ps1` removes these so the GNU
> coreutils stay reachable. `rm` → **`del`**, `mv` → **`mvf`**; `cp`/`cat`/`mkdir`/
> `touch`/`rmdir` defer entirely to the native tools.
>
> ¹⁰ **A team room is three separate things, and `team-room` refuses to merge them.** A
> wake connector (a Scheduled Task) can be Ready while nothing is armed; an arm stamp can
> be present but belong to a *previous boot*; a watcher process can be running with neither.
> Collapsing these into one "on/off" is what made a room impossible to reason about — the
> owner could not tell whether anything would actually happen, and so could not tell
> whether stopping it had worked. The list shows all three per room and derives **Live**
> from them; `Live` is the honest answer to "will an agent wake up?".
>
> The arm stamp is deliberately **boot-scoped**: it records the boot instant (now minus
> uptime, so a clock change moves both together) and anything outside a 3-minute tolerance
> reads as *disarmed*. Unreadable, malformed and previous-boot stamps all **fail closed**,
> each with its own reason string. And `Stop-TeamRoomWatcher` re-verifies the process is
> still a `teamchat-wait` before signalling — a PID confirmed by a human seconds ago can be
> a different program by the time they answer.

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
