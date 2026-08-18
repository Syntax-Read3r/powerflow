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
| `adapters/locations.ps1` | `Get-StarshipConfigPath`, `Get-TerminalSettingsPath`, `Get-TempPath`, `Get-HomePath`, `Get-PowerFlowDataPath`, `Get-PowerFlowConfigPath`, `Get-UserFolderPath` | `%LOCALAPPDATA%`, `%TEMP%`; **`Get-UserFolderPath` reads the Known Folder registry** — `Join-Path $HOME 'Documents'` is WRONG once OneDrive Known Folder Move redirects Documents/Pictures/Desktop to `~\OneDrive\…`, leaving the local path an empty stub or absent (measured: `~\Pictures` did not exist at all). Takes `-Prefer auto\|local\|known` so someone who keeps files off OneDrive can say so | XDG (`~/.config`, `~/.local/share`), `$TMPDIR`; **`Get-UserFolderPath`** faces the same trap in another shape — XDG user dirs can be relocated or localised (`~/Documentos`) — so it uses `xdg-user-dir(1)`, then parses `~/.config/user-dirs.dirs`, then falls back to `~/<Name>` |
| `adapters/pwsh-update.ps1` | `Invoke-PowerShellUpdate` | winget / MSI / Store | apt / snap / dotnet-tool |
| `adapters/apps.ps1` | `Get-InstalledApplication`, `Uninstall-Application`, `Get-DiskHotspot`, `Measure-FolderSize`, `Move-ToTrash`, `Remove-PathPermanently`, `Test-TrashSupport`, `Test-ProtectedPath` | registry + Scoop; Recycle Bin | dpkg / rpm / pacman; `gio trash` | **Storage additions:** `Get-StorageVolume`, `Resolve-StorageVolume`, `Get-StorageNativeCommand`. Windows enumerates via `Get-Volume` (falling back to `Get-PSDrive`), keeping only Fixed/Removable — a network drive is someone else's disk and walking one looks like a hang. Linux uses `findmnt -J -l`, and the **pseudo-filesystem filter is the load-bearing part**: an unfiltered mount list on a modern desktop is mostly noise (one squashfs loop per snap, a tmpfs per session, plus proc/sysfs/cgroup), which would bury the two mounts anyone cares about. Selector resolution is per-platform on purpose — `D`/`d`/`D:`/`D:\`/label on Windows, mount path/device/trailing directory name on Linux — because "what a volume is called" is exactly the knowledge a component must not hold. |
| `adapters/perms.ps1` | `Get-FileMode`, `Test-PermsSupported`, `Get-Umask`, `Set-Umask` | **returns `$null`** — Windows has ACLs, not POSIX mode bits, and inventing a fake `755` would teach something false | `stat(1)` for the mode; **libc `umask(2)` via P/Invoke** for the umask³ |
| `adapters/fonts.ps1` | `Get-NerdFontName`, `Test-NerdFont`, `Install-NerdFont`, `Uninstall-NerdFont`, `Get-NerdFontInstructions`, `Get-NerdFontInstallHint` | Scoop nerd-fonts bucket; font registry read for detection | download → `~/.local/share/fonts/PowerFlow-NerdFont` → `fc-cache`; `fc-list` for detection |
| `adapters/login.ps1` | `Get-LoginLaunchState`, `Enable-LoginLaunch`, `Disable-LoginLaunch` | **`'always'` / no-op** — pwsh always sources `$PROFILE`, so there is no login hook to manage | the guarded `~/.bashrc` block (byte-identical to `install.sh --auto-login`) |
| `adapters/sysconfig.ps1` | `Test-SysConfigSupported`, `Get-SysConfigOptions`, `Get-SysConfigChoices`, `Set-SysConfig` | `Set-TimeZone` / `Set-Culture` / `Rename-Computer` / W32Time, each applied for the user — machine-wide ones via a single UAC prompt (`Invoke-ElevatedCommand`). Four settings: keyboard is omitted because a Windows layout is an input-language tip, not a keymap. Validates a value against its own choices first (`Set-Culture` will otherwise write a bogus culture) | `localectl` / `timedatectl` / `hostnamectl`; a domain model (keyboard/timezone/locale/hostname/ntp) so new settings are one row. Keyboard detects vconsole vs X11 (`Get-KeyboardMode`) so Debian/Ubuntu work too |
| `adapters/startup.ps1` | `Get-StartupEntry`, `Set-StartupEntryState`, `Remove-StartupEntry`, `Add-StartupEntry`, `Get-StartupFolderPath` | both Startup folders **and** the HKCU/HKLM `Run` keys, joined against `Explorer\StartupApproved` for each entry's REAL state (Task Manager disables by flag, not deletion). Disable writes the same flag; folder deletes go to the Recycle Bin | XDG autostart `.desktop` files (`~/.config/autostart`, `/etc/xdg/autostart`). `Hidden=true` is the analogue of StartupApproved. A system entry is shadow-copied into the user dir rather than edited — the package owns the original |
| `adapters/health.ps1` | `Get-MachineInfo`, `Get-PowerSnapshot`, `Get-StabilityEvents`, `Get-FirmwareInfo`, `Set-CpuMaxState`, `Export-StabilityReport` — plus internal `Get-GpuInfo`, `Get-MemoryInfo`, `Get-DiskInfo`, `Get-SlotInfo`, `Format-HwVendor` (both platforms), plus contract `Get-ProcessMemoryUsage` (RAM by program, with system-critical + self flags) | `powercfg` (hex decoded, stock plans by GUID), WHEA/WER via `Get-WinEvent`, CIM, minidumps. **GPU:** `Win32_VideoController` filtered of virtual/streaming adapters, VRAM from the display-class registry (`AdapterRAM` is uint32 and wraps >4 GB; on an iGPU it reports shared memory, so only dedicated counts). **RAM:** `Win32_PhysicalMemory` using `SMBIOSMemoryType` (`MemoryType` is 0 on modern boards) + configured vs rated speed | cpufreq governor + `scaling_max_freq`, kernel MCE via `journalctl`, `/sys/class/dmi/id` (no root needed), `/var/crash`. **GPU:** `nvidia-smi` then `lspci -mm` (bracketed product name preferred); integrated vs discrete by PCI bus, not vendor — AMD ships APUs *and* cards; VRAM keyed by PCI slot via `Get-DrmVramBySlot`. **RAM:** `dmidecode -t 17` as root or `sudo -n` (never prompts), else size only with a reason |
| `adapters/proxmox.ps1` | `Test-ProxmoxSupport`, `Get-ProxmoxNodeSummary`, `Get-ProxmoxDisks`, `Get-ProxmoxStorage`, `Get-ProxmoxZfsPools`, `Get-ProxmoxGuests`, `Get-ProxmoxUpdates`, `Get-ProxmoxSmartInfo`, `Get-ProxmoxSmartReport`, `Start-ProxmoxSmartTest`, `Get-ProxmoxDiskSafety`, `Get-ProxmoxDiskEvidence`, `Invoke-ProxmoxCapacityProbe` | **every function returns empty/`$null`** — Proxmox VE is a Debian-based hypervisor and does not exist on Windows. The stubs exist so the component loads and `pmx help` still works⁸ | `pvesh` for the node/guest/storage API, `lsblk -J` + `/dev/disk/by-id` for stable identity, `smartctl -j`, `zpool`, `journalctl -k`, `f3probe` for the capacity probe |
| `adapters/proxmox-management.ps1` | `Test-ProxmoxManagementTransport`, `Invoke-ProxmoxManagementQuery`, `Invoke-ProxmoxManagementChange` plus private allow-list/token builders | SSH only: validates a saved target and maps documented operations to fixed `pvesh`/`qm` token arrays | local `pvesh`/`qm` on Proxmox or the same fixed operations over SSH elsewhere; structured results have `Success`, `Data`, `Error`, `ExitCode`, `NativeCommand`, `FailureKind`; remote errors/previews are alias-only |
| `adapters/container.ps1` | `Get-ContainerEngineNames`, `Get-ContainerEngineInfo`, `Get-ContainerEngineIdentity`, `Get-ContainerList`, `Invoke-ContainerLifecycle`, `Get-ContainerLogCommand`, `Get-ContainerShellCommand`, `Invoke-ContainerInteractive`, `Get-ContainerComposeProjects`, `Invoke-ContainerCompose` | **Serves BOTH docker and podman** from one body, parameterised by an engine descriptor — podman is a deliberate drop-in and the whole go-template surface was measured byte-identical on podman 6.0.2 and Docker Desktop. Docker Desktop over the `npipe://./pipe/docker_engine` named pipe; podman over a WSL machine. **Never elevates on Windows** for either engine. `Get-ContainerEngineIdentity` records which engine ACTUALLY answered: podman can register itself on the standard docker pipe, so the `docker` CLI's default context may resolve to podman — measured on the author's own host, where `docker version` reported Server 6.0.2 on `fedora-44`. Without it `dkr` would print "docker 6.0.2" and act on podman's containers. | Same contract, same body. Elevation differs: only **docker** may retry under `sudo -n`, because podman is rootless and `sudo podman ps` queries **root's separate container store** — a different set of containers, not the same ones with more rights, so elevating would show the wrong set and report success. `Clear-PFComposeNoise` strips podman's ANSI-wrapped external-provider banner, which otherwise makes compose JSON unparseable *silently* (the leading byte stops being `[`). The version probe gates on **`$LASTEXITCODE`, read before any pipeline**: podman prints its CLIENT version to stdout and exits 125 when unreachable, and `\| Select-Object -First 1` short-circuits the pipeline and leaves `$LASTEXITCODE` at 0 — both measured. |
| `adapters/ssh-session.ps1` | `Invoke-PFPrivateSshSession`, `Get-PFPrivateSshSessionResult` plus private askpass preparation | Compiles/caches the shipped console helper; the helper reads `CONIN$`, masks input, and writes only to OpenSSH's askpass pipe | Copies/chmods the shipped `/dev/tty` helper; hidden input goes only to OpenSSH's askpass pipe |
| `adapters/team-room.ps1` | `Get-TeamRoomState`, `Set-TeamRoomArm`, `Set-TeamRoomTask`, `Stop-TeamRoomWatcher` — plus internal `Get-TeamRoomBootInstant`, `Get-TeamRoomArmState`, `Get-TeamRoomWatchers`, `Get-TeamRoomTasks`, `Get-TeamRoomStateRoots` | Scheduled Tasks (`TeamChat-<agent>-<repo>`) for the wake connector; `Win32_Process` command lines to find live `node teamchat-wait.js` watchers; `LastBootUpTime` for the boot instant | `/proc/<pid>/cmdline` for watchers (matched on the **script** name — they are all plain `node`), `/proc/uptime` for the boot instant. `Set-TeamRoomTask` **reports it cannot act**: the wake connector registers a Windows Scheduled Task and team-room ships no Linux equivalent — no cron job, no systemd timer⁹ |

> ⁹ **A standard user folder is not `$HOME/<Name>`, on either platform.** Windows OneDrive
> Known Folder Move redirects Documents/Pictures/Desktop to `~\OneDrive\…` and leaves the local
> path an empty stub — or absent, as `~\Pictures` was on the machine this was found on. So
> `nav -pics` silently vanished and `nav -docs` would have landed in the *wrong* folder, which
> is worse than failing. Linux has the same problem wearing different clothes: XDG user dirs are
> relocatable and **localised** (`~/Documentos`). Both go through `Get-UserFolderPath`.
>
> The **preference** (`auto`/`local`/`known`) lives in PowerFlow config, not the adapter: the
> adapter answers *"where is Documents under policy P"*, the component decides P. Under `local`
> a missing folder returns empty rather than falling back to the redirect — silently falling
> back would ignore the preference the user just set — and `Repair-PFUserFolders` offers to
> create it. Creating is offered and confirmed, never automatic: it is a real directory on
> someone's disk.

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
| `platform/windows/bindings.ps1` | Windows | **Adds only.** Binds `rm` → `del` and `mv` → `mvf` (safe on Windows: there is no GNU tool underneath, and PowerShell's own `rm`/`mv` are thin Remove-Item/Move-Item aliases). Provides `grep`, `less`, `pwd`, `which`, which Windows lacks. |
| *(Linux has no bindings file)* | Linux | Deliberately absent. `components/` claims no coreutil name, so there is nothing left to unbind — see CLAUDE.md, "Command Shadowing on Linux". Two CI gates keep it that way. |

---

## Components — shared domain logic (both platforms)

| File | Domain | Functions |
|------|--------|-----------|
| `components/core/version.ps1` | Core | `Check-PowerFlowUpdates`, `powerflow-update`, `Get-PowerFlowVersion`, `powerflow-version`, `pwsh-reminders` |
| `components/core/dependencies.ps1` | Core | `Get-RequiredTools`, `Initialize-Dependencies`, `Check-PowerShellUpdates` |
| `components/core/recovery.ps1` | Core | `pwsh-recovery`, `powerflow-uninstall` |
| `components/shared/strings.ps1` | Shared | `Convert-ToKebabCase`, `Convert-ToSnakeCase`, `Convert-ToPascalCase`, `Convert-ToCamelCase` |
| `components/shared/educate.ps1` | Both | `Register-PFEducation`, `Write-PFEducation`, `Split-PFEducateFlag`, `Test-PFEducationTopic`, `Get-PFEducationTopics` — the `--educate` footer. Analogy first, then one line per element on screen. Prints **after** the output, opt-in only, and a topic is registered beside the view it explains so the two move together |
| `components/shared/flags.ps1` | Both | `Invoke-PFParamCommand`, `ConvertTo-PFCanonicalFlags`, `Write-PFFlagDeprecation`, `Get-PFFlagSuggestion`, `ConvertTo-PFKebab` — **the one place the flag convention is enforced**¹¹. Loads early; every command may route through it |
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
| `components/navigation/roots.ps1` | Navigation | `Get-NavSearchRoots`, `Get-NavDefaultRoots`, `Add-NavSearchRoot`, `Remove-NavSearchRoot`, `Reset-NavSearchRoots`, `Show-NavSearchRoots`, `Format-NavPath` — **where `nav` looks**, persisted to `~/.nav_roots.json`² · plus the **named-starting-point layer shared by `nav` and `ls`**: `Get-PFNamedRoots`, `Get-PFRootAliases`, `Resolve-PFRootAlias`, `Get-PFRootChoices`, `Resolve-PFRootedDirectory`, and user **anchors** `Get-PFUserAnchors`/`Save-PFUserAnchors`/`Add-PFAnchor`/`Remove-PFAnchor`/`Show-PFAnchors`, plus the OneDrive-vs-local folder preference `Get-PFFolderPreference`/`Set-PFFolderPreference`/`Repair-PFUserFolders`⁹ |
| `components/navigation/bookmarks.ps1` | Navigation | `Initialize-DefaultBookmarks`, `Get-Bookmarks`, `Save-Bookmarks`, `Add-Bookmark`, `Remove-Bookmark`, `Rename-Bookmark`, `Show-BookmarkList` |
| `components/navigation/projects.ps1` | Navigation | `Search-Projects` |
| `components/navigation/nav.ps1` | Navigation | `nav`, `nav roots`, `nav anchors`, `nav b .`, `z` (alias) — **hand-parses ``, no `param()` block**: a param block binds `-srv`/`-pics` as parameter NAMES, so `nav -srv complete` never reached the body (it just printed help). Same trap as `rm -rf`, footnote ⁵ |
| `components/navigation/directory.ps1` | Navigation | `here`, `..`, `...`, `....`, `.....`, `~`, `back`, `cd-` (alias), `copy-pwd` |
| `components/files/listing.ps1` | Files | `ls`, `la`, `ll`, `clr` (alias) — `ls -<anchor> <name>` lists a directory without typing its path (same resolver as `nav`); `-recurse`/`-depth N` accepted as the spellings PowerShell users already type. **`-r` is NOT aliased** — that is GNU reverse-sort |
| `components/files/operations.ps1` | Both | `del`¹, `mvf`¹ ⁶, `Invoke-GnuMove`, `mv-t`, `mv-c`, `Split-GnuArgs`⁵ — both report themselves as the name they were **invoked** as (`$MyInvocation.InvocationName`), so `rm -rf x` on Windows says `rm:` while `del -rf x` says `del:`. Neither is named after a coreutil, so neither needs unbinding anywhere |
| `components/files/rename.ps1` | Files | `rn` |
| `components/files/clipboard.ps1` | Files | `open-pwd`, `op`, `paste-file`¹¹, `pf`¹¹, `copy-file`, `cf`, `Invoke-PFPasteFile` — `pf` is the short name for the same implementation, not a forwarder to `paste-file` |
| `components/git/remote.ps1` | Git | `Create-RemoteRepository` |
| `components/git/commit.ps1` | Git | `git-a` — add, commit and push interactively. `git-a-plus` and its four one-line wrappers (`git-aa`, `git-aq`, `git-ad`, `git-am`) were **pruned** at the owner's request as unused; that also deleted DECISIONS 1.3's hazard rather than guarding it, since `git-a-plus -a` was the command whose `-a` bound to `-AmendLast` by prefix and rewrote the last commit |
| `components/git/branches.ps1` | Git | `git-branch`, `Invoke-DeleteBranch`, `git-b`, `git-cm`, `git-bd` (safe, `branch -d`), **`git-bd-force`** (`branch -D`), `git-c.sb` — the force variant is `git-bd-force` and NOT `git-bD`: PowerShell's function table is case-insensitive, so the two names were one function and the force-delete silently replaced the documented-safe one |
| `components/git/rollback.ps1` | Git | `git-rba`, `grba` (alias), `git-rb` |
| `components/git/interactive.ps1` | Git | `git-l`, `git-log`, `git-s`, `git-st`, `git-pick`, `git-p`, `git-stash`, `git-remote`, `git-sh`, `git-r` |
| `components/git/version-files.ps1` | Git | `Get-ProjectVersionSource`, `Get-ProjectVersion`, `Set-ProjectVersion`, `Update-ProjectVersion`, `Test-VersionDrift`, `Get-VersionFileDefinition`, `Read-TomlSectionVersion` — detects and rewrites `package.json` / `pyproject.toml` / `Cargo.toml` / `*.csproj` / `build.gradle` / `VERSION` / PowerFlow settings |
| `components/git/release.ps1` | Git | `git-rl` (alias `git-release`)¹¹, `Invoke-GitReleaseCommand`, `Show-GitReleaseSetupPrompt`, `Write-GitReleaseGuide`, `Get-GitReleaseDocs` — bump, commit, tag and push, for any project. **Two states are deliberately different:** in a project WITH a release pipeline it opens the fzf bump picker; in one without (no version source, no `v*` tag) it reports what is missing and points at `git-rl -h`, **writing nothing** — bare `git-rl` may be run in a clone or scratch checkout, so creating files there as the side effect of a status report would assume the wrong target. `git-rl -h` is the only path that writes the setup walkthrough, and it confirms the folder first. Tests in `tests/git/` |
| `components/git/reset.ps1` | Git | `git-f`, `git-next` |
| `components/github/browser.ps1` | GitHub | `gh-l`, `gh-l-reset`, `gh-l-status`, `gh-l-org` |
| `components/terminal/tabs.ps1` | Terminal | `send-keys`, `open-nt`, `close-ct`, `next-t`, `prev-t`, `open-t`, `close-t` |
| `components/projects/create-next.ps1` | Projects | `create-next`, `create-n` |
| `components/system/config-files.ps1` | System | `pwsh-profile`, `pwsh-starship`, `pwsh-settings` |
| `components/system/shutdown.ps1` | System | `shutdown`, `s` |
| `components/system/path.ps1` | System | `set-path` |
| `components/system/apps.ps1` | System | `installed-apps`, `i-a` (alias), `disk-big`, `d-b` (alias), `Get-SizeBands`, `Convert-ToBytes`, `Format-Size`, `Format-Age`, `Resolve-SizeRange`, `Show-SizeBandMenu`, `Show-AppPicker`, `Show-BandOverview`, `Invoke-AppAction` |
| `components/system/health.ps1` | System | `pc-whoami` (+ `--power`, `--crashes [--export]`, `--bios`, `-ram [level|<name>|-min N]`, `-days N`), `Show-RamIndex` (the level map), `Show-RamDetail` (one level, read-only), `Show-RamProcesses` (drill-in with command lines), `Stop-RamProcess` (one PID), `Stop-RamGroup` (whole program, harder warning), `Format-DriveSize`, `pc-cap`⁷ — machine vitals + a CPU cap with guaranteed restoration. Design: [docs/plan/pc-whoami/](docs/plan/pc-whoami/README.md) |
| `components/containers/containers.ps1` | Both | `dkr` (docker) and `pman` (podman), plus their `logs` / `shell` / `up` / `down` / `restart` / `stop` / `start` verbs. **One implementation, two entry points** — the command NAME is the engine selector, so there is no `--engine` flag to remember, the same reasoning as `storage <volume>` being a word rather than `-D`. A switchable alias was rejected because it would make `dkr` mean different things on different machines, so help text, docs and muscle memory would all become machine-dependent. **No `param()` block**: PowerShell would bind `-a`/`-f` as parameter *names*, and prefix matching would make single letters ambiguous. Names resolve container → compose service → project → substring, so `dkr restart sonarr` works from any directory. Stopped containers are listed, not hidden. `dkr restart` is compose-correct — plain `restart` ignores an edited compose file. `down` can never reach `-v`. When zero containers come back it **re-probes engine health before claiming "no containers"**, because podman can report a usable version while unreachable and a confident wrong answer is worse than a slow one. | Design: [dkr plan](docs/plan/docker/dkr.md); tests in `tests/containers/` |
| `components/system/storage.ps1` | Both | `storage` and its `apps` / `big` / `docker` verbs, plus `Format-StorageSize`, `Format-StorageBar`, `Get-StorageColour`. **One noun for "where did my space go", across every volume.** `installed-apps` and `disk-big` both answered that question under unrelated names, and neither could answer the one that comes first — *which drive is full* — because `Get-DiskHotspot` only ever returned system-drive locations. Measured on the author's box: four volumes, three unreachable, including a 1.8 TB external. The volume is a **positional target, never a flag**: a flag per drive letter is an unbounded set, drive letters do not exist on Linux, and PowerShell's parameter **prefix** matching would make `-D` ambiguous with `-Detailed`/`-Depth`. Verbs are dispatched before volume resolution so `storage apps` cannot be eaten by a volume labelled "apps". `storage docker` defers to `docker system df` because a directory walk of the docker root double-counts shared overlay2 layers. Nothing is renamed — `installed-apps`, `i-a`, `disk-big` and `d-b` keep working, and the verbs delegate to them. | Shape follows [dkr](docs/plan/docker/dkr.md); tests in `tests/storage/` |
| `components/proxmox/*.ps1` | Both (physical host/disk actions Linux-only) | Ordered domain: `shared`, `connection-state`, `config`, `host`, `physical-disks`, `evidence`, `disk-model`, `vm-read`, `network-config-model`, `guest-network-model`, `network-view`, `network-read`, `clone-plan`, `vm-change`, `disk-grow`, `snapshots`, `help`, `command`. The four network components separately own configured adapters, VM-reported interfaces/addresses/stats, stable tables/JSON, and read-only orchestration. They match only by valid unique MAC, infer a primary address without claiming reachability, and reveal the fixed native VM-agent read only with `--show-native`. `disk-model` owns exact bytes, IEC displays, boot roles, eligibility, and the shared disk table. `clone-plan` owns per-disk placement/capacity and plan-versus-result JSON. `disk-grow` owns the three strict grammars, single-disk inference, byte/delta/capacity planning, and guarded execution. Remote transport failures and previews are alias-only. Mutations preview, confirm, revalidate, execute an allow-listed adapter operation, verify, and audit. The router only routes; `Get-PmxHelpOverview` and `Get-PmxHelpTopics` provide the complete executable command catalog. | Design: [VM-management plan](docs/plan/proxmox/pmx-vm-management.md), [network inspection](docs/plan/proxmox/pmx-vm-network-inspection.md), [disk/clone contracts](docs/plan/proxmox/pmx-disk-and-clone-output-contracts.md); user syntax: `pmx help` |
| `components/system/team-room.ps1` | Both | `team-room` (+ `start <name>`, `stop <name>`, `list`, `help`, `-All`), `Show-TeamRoomList`, `Show-TeamRoomDetail`, `Invoke-TeamRoomAction`, `Format-TeamRoomAge` — **see and stop the agent watchers you started.** Reports all three independent states separately (wake connector · boot-scoped arm stamp · live watcher process) because any one of them alone does nothing¹⁰ |
| `components/system/fonts.ps1` | System | `pwsh-font` — install the Nerd Font the prompt and `ls` need, then print the one manual terminal-config step. All OS work is in the fonts adapter |
| `components/system/login.ps1` | System | `pwsh-autologin` (Linux) — toggle "start PowerFlow on login" without re-running the installer; writes the same guarded hook as `install.sh --auto-login`. `pwsh-exit` (Linux) — drop to bash without closing the SSH session (`exec pwsh` login shell has no bash to fall back to) |
| `components/system/sysconfig.ps1` | Both | `pwsh-config`, `Complete-SysConfigChange` — one fzf-driven menu that **applies** OS settings (timezone/locale/hostname/time-sync, plus keyboard on Linux): systemd on Linux, native cmdlets on Windows. Replaces the Debian-only `dpkg-reconfigure`. Extensible: new settings are a row in the adapter |
| `components/system/startup.ps1` | Both | `start-folder` (alias `startup`), `Show-StartupList`, `Invoke-StartupAction` — one list of everything that runs at login. Picker-as-manager: Enter **toggles** (reversible), ctrl-d deletes (confirmed, name typed back), ctrl-o opens the folder. `start-folder add <path>` / `list` / `open` |
| `components/network/server-privacy.ps1` | Network | `Get-PFServerTarget`, `Format-PFServerPublicRow`, `Invoke-PFServerSsh`, `Test-PFServerInteractiveAuth`, `Show-PFServerAuthenticatedInfo` — the saved-endpoint privacy boundary. Ordinary UI and credential prompts get aliases; platform adapters alone receive endpoint tokens; `srv <name> info` reveals details only after successful authentication. Passwords travel only through the helper-to-OpenSSH askpass pipe and are never persisted. |
| `components/network/servers.ps1` | Network | `srv` (private alias/status picker: Enter connect · ctrl-d delete · ctrl-r rename), `srv <name> info`, `srv add`, `srv rm`, `srv rename`, `srv list`, `Show-PFServerPicker`, `Test-ServerOnline`, `Get-PFServers`, `Save-PFServers` — named SSH connections in `~/.powerflow-servers.json`. Status = TCP probe of the ssh port with ICMP tiebreaker: `online` / `no-ssh` / `offline`. `ssh` itself is never shadowed. |
| `components/help/registry.ps1` | Help | `Register-PFCommand`, `Get-PFCommandRegistry`, `Get-PFHelpSections`, `Get-PFHelpChapters` — the **one source of truth** for the command surface. Loads FIRST; every component registers its commands beside their definitions; sections fold into chapters (`$PF_HelpChapters`) for the printed manual; CI fails the release on an unregistered command |
| `components/help/menu.ps1` | Help | `pwsh-h` (alias `pwsh-help`) — rendered entirely from the registry. Default is `Show-PFManual`: a grouped, printed manual folded into a few chapters (`$PF_HelpChapters`); `pwsh-h -a` / `pwsh-help --advanced` is the `Show-PFHelpBrowser` fzf finder; `pwsh-h <topic>` filters a section/command/lesson via `Show-PFHelpSections` / `Show-PFCommandDetail` |

> ¹¹ **Flags are `--word` and `-x`, and one file enforces it.** `Invoke-PFParamCommand` is what
> makes `--long` bind at all. A PowerShell `param()` block cannot bind a double-dash flag — it
> *misbinds* it, landing `--force` in whichever value parameter comes next and displacing the
> real value — so twelve commands are now a one-line shim (`pc-whoami`, `pwsh-h`, `pwsh-font`, `disk-big`,
> `installed-apps`, `paste-file`, `pf`, `set-path`, `team-room`, `git-rb`, `git-release`,
> `powerflow-update`) over an unchanged Verb-Noun implementation that keeps its `param()` block,
> its case-insensitivity and its prefix matching. Legacy single-dash words still work and say so
> once per session. An **unknown** flag is refused with a suggestion rather than dropped, which
> is what closes DECISIONS 1.4 generally: `pwsh-font --status` used to install a font because the
> unbindable token vanished into `$args`. See [ETHOS.md](docs/plan/ethos/ETHOS.md); asserted by
> `tests/flags/`.
>
> ¹ **Never named after a coreutil.** PowerFlow's delete and move are **`del`** and
> **`mvf`** on *every* platform — they are not clones, and borrowing `rm`/`mv` would mean a
> Linux user's reflexes silently getting different behaviour. Windows additionally binds
> `rm`/`mv` to them, because there is no GNU tool there to hide. `cp` and `cat` are gone
> entirely (PowerShell already ships both as built-in aliases on Windows, so they were
> adding nothing there while hiding the real tools on Linux); `mkdir`/`touch`/`rmdir` moved
> to `windows-only/coreutils.ps1`, since Windows ships none of the three.
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
| `windows-only/coreutils.ps1` | Windows | `mkdir` (`-p`), `touch`, `rmdir` — GNU clones for the one platform that ships none of them: Windows has no `touch` at all, its `mkdir` is a New-Item wrapper with no GNU flags, and its `rmdir` will not ask before taking a directory's contents with it. Never loads on Linux, where the real tools are better. |
| `windows-only/wsl.ps1` | Windows | `open-ubuntu`, `open-wsl-simple` — launch a WSL tab **from** Windows Terminal. WSL is a Windows concept; this never loads on Linux. |

---

## Installers

| File | Platform | Purpose |
|------|----------|---------|
| `install.ps1` | Both | **THE installer.** Copies the tree, installs deps via the packages adapter, writes `.powerflow-manifest.json`. |
| `uninstall.ps1` | Both | **Manifest-driven.** Removes only what PowerFlow placed. Never removes a dependency the user already had (`installedByPowerFlow: false`). |
| `install.sh` | Linux | Thin bootstrap: detect distro → install pwsh → hand off to `install.ps1`. Contains **no** install logic. |
| `install-gui.sh` | Linux | Graphical front-end (zenity → kdialog → yad → terminal fallback). Delegates to `install.sh`. |
