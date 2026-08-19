# Storage allocation — where PowerFlow puts what grows

**Status:** design, not built. Nothing here ships until the open questions at the end are
answered.
**Written against:** working tree at `f7373c1` plus the uncommitted Scoop-path fix (see §2.0).
Every claim carries a `file:line` or a measured figure. Where a measurement was taken on the
author's own machine it says so; where something was **not** verified it says that too.

---

## 1. The problem, in the owner's framing

> "I have manually installed and set up this D drive. In the future installs of powerflow, I
> want an auto recognition of another drive aside from C drive if on Windows, and respectfully
> on Linux we would need to allocate a similar behaviour. If there isn't another drive, it
> still doesn't matter, the installs are to be properly allocated and managed, instead of the
> default install location that leads to memory growing in unknown location, making it harder
> to manage."

Three requirements, and they are not the same requirement:

1. **Recognise a second drive** and use it, on Windows and on Linux.
2. **Allocate properly even without one** — a single-drive machine must end up managed, not
   merely unchanged.
3. **Stop the growth happening in a place nobody named.**

The third is the load-bearing complaint, and measuring it changes what the design should move.
On this machine, right now:

| Thing | Measured size | Where |
|---|---|---|
| The PowerFlow install tree | **1.67 MB** | `C:\Users\<user>\Documents\PowerShell` |
| The Scoop root PowerFlow created | **570 MB** | `C:\Users\<user>\scoop` (apps 466.8, cache 93.7, buckets 7.8, shims 1.8) |

A ratio of about **1 : 341**. The "memory growing in unknown location" is Scoop's, not
PowerFlow's. A design that relocates the component tree spends its entire risk budget on 0.3% of
the problem. This design therefore moves **what grows**, and deliberately leaves the tree where
the OS puts it.

---

## 2. Constraints that are now proven

Each was checked against the tree or measured on a real machine. Several were believed true
going in and turned out to be false; those are marked **REFUTED**, and the design is built on
the correction rather than the hope.

### 2.0 The Scoop-path clobber is already fixed — do not "fix" it again

An earlier reading of this codebase said `config/paths.windows.ps1` overwrites `$env:SCOOP` on
every profile load. **That is stale.** The file now reads:

- `config/paths.windows.ps1:14` — `# READ $env:SCOOP. NEVER WRITE IT.`
- `config/paths.windows.ps1:45-60` — `Initialize-PFScoopPath` resolves `$env:SCOOP` else
  `~\scoop`, returns early when the shims directory does not exist, and matches PATH entries
  **exactly** instead of the old `-like "*scoop*"` substring scan.
- `tests/windows/scoop-root-resolution.ps1` (untracked, wired in at `tests/windows/run.ps1:3`)
  pins six cases, including *"a relocated Scoop root is never reassigned"* and *"an unset SCOOP
  is left unset, never invented"*. It passes today.

That file's own header also states the constraint this work inherits
(`config/paths.windows.ps1:39-43`):

> This resolution is deliberately inline rather than a shared adapter call. `config/` is scanned
> by the adapter-parity gate exactly like `components/`, so calling a Windows-only adapter
> function from here would make that name part of the cross-platform contract and fail the
> release for want of a Linux twin. **A shared root contract belongs with the install-time
> placement work, where Linux has something real to say.**

This document *is* that work. §5 and §6 pay the parity price openly rather than pretending it is
not there.

### 2.1 REFUTED — "the install tree can be relocated with a stub at `$PROFILE`"

The *mechanism* works. Verified by execution on this host, on both pwsh 7.6.5 and Windows
PowerShell 5.1: a stub that dot-sources a relocated profile leaves
`$MyInvocation.MyCommand.Path` pointing at the **real** file, so
`Microsoft.PowerShell_profile.ps1:23`'s
`$script:PowerFlowRoot = Split-Path -Parent $MyInvocation.MyCommand.Path` resolves to the
relocated directory with no code change. A directory junction also works, but reports the
*junction* path unresolved.

Everything around the mechanism is broken, and the repo supports none of it:

- **No destination parameter exists.** `install.ps1:30-36` is `-Yes -Force -NoDeps -Prefix
  -Platform`. The destination is hardcoded at `install.ps1:66-67`. `-Prefix` is documented at
  `install.ps1:19-21` as *"Directory holding the PowerFlow **source** to install from"* and is
  consumed as `$source` at `install.ps1:160-162`.
- **`powerflow-update` would silently undo it.** `components/core/version.ps1:193` runs
  `& pwsh -NoProfile -File $installer -Yes -NoDeps`; that child computes the stock `$PROFILE`
  and would lay a second copy at the default location.
- **Uninstall would strand it.** `uninstall.ps1:43-44` finds the manifest only at
  `Split-Path $PROFILE -Parent`; failing that it takes the conservative branch at
  `uninstall.ps1:60-66`, deleting `config/ components/ platform/ windows-only/ docs/` and
  `$PROFILE` at the **default** location — the exact failure `install.ps1:386-387` records as
  *"how the old Ubuntu port ended up deleting people's `~/.bashrc` outright."*
- **Both Windows tests would break, live.** `tests/windows/uninstall-scoop-safety.ps1:75` runs
  the real `uninstall.ps1 -Yes` isolated by nothing but `$PROFILE = '<sandbox>'` in a child
  pwsh. If manifest discovery ever stops following `$PROFILE`, running `tests/windows/run.ps1`
  uninstalls the developer's own PowerFlow.
- **Windows PowerShell 5.1 is not a target anyway.** `install.ps1:1` is `#Requires -Version
  7.0`, and `$PROFILE` differs per host (`…\Documents\PowerShell` vs
  `…\Documents\WindowsPowerShell`; the latter does not exist on this machine).

**Design consequence: the component tree does not move.** Manifest discovery stays on
`$PROFILE`, and a comment saying why belongs at `uninstall.ps1:43`.

Recorded so nobody re-litigates it: the stub is the *proven* relocation mechanism and a symlink
is the unproven one. If tree relocation is ever revisited, start from the stub.

### 2.2 REFUTED — "setting `$env:SCOOP` is how the root gets persisted"

`Install-PackageManager` (`platform/windows/adapters/packages.ps1:46-60`) pipes
`Invoke-RestMethod https://get.scoop.sh | Invoke-Expression`, which cannot take a parameter. I
downloaded the live upstream installer (722 lines) and read it rather than assume:

| Fact | Line in `get.scoop.sh` |
|---|---|
| `$SCOOP_DIR = $ScoopDir, $env:SCOOP, "$env:USERPROFILE\scoop" \| … Select-Object -First 1` | 690 |
| `$SCOOP_CACHE_DIR = $ScoopCacheDir, $env:SCOOP_CACHE, "$SCOOP_DIR\cache"` — **the 93.7 MB cache follows the root for free** | 694 |
| `Add-DefaultConfig`: `if (!(Get-Env 'SCOOP')) { if ($SCOOP_DIR -ne "$env:USERPROFILE\scoop") { Add-Config -Name 'root_path' -Value $SCOOP_DIR } }` | 527-534 |
| `Get-Env` reads **`HKCU:`** — the persisted User-scope variable, not `$env:` | 384-398 |
| `[String] $ScoopDir` is a real parameter, usable via the scriptblock form | 59 |
| `Deny-Install "Scoop is already installed…" -ErrorCode 0` | 175 |
| `Exit-Install` under `irm \| iex` uses `break`, not `exit` | 91-104, 684 |

So a **process-scope** `$env:SCOOP` chooses the root, and Scoop then records that choice itself
as `root_path` in `%USERPROFILE%\.config\scoop\config.json`. PowerFlow needs no new
env-persistence adapter, and **must never persist a User-scope `SCOOP`** — doing so suppresses
the `root_path` write and creates a second source of truth that only PowerFlow knows about.

Two hazards that fall out of the same reading. First, `Deny-Install` on an existing Scoop exits
with code **0** — a success — so an installer that tries to re-bootstrap gets no error. Second,
under `irm | iex` it exits via a bare `break`, which is **not** caught by the `try/catch` at
`packages.ps1:49-59` and terminates the enclosing script. Neither is reachable in the design
below, because relocation is proposed only when `Test-PackageManager` is false, but both must
stay unreachable.

### 2.3 The corollary nobody caught: PowerFlow is blind to `root_path`

If Scoop records the root in `root_path` and PowerFlow only ever reads `$env:SCOOP`, then in
every ordinary shell `$env:SCOOP` is empty and PowerFlow computes a `~\scoop` that does not
exist. Four sites do this today:

| Site | Expression |
|---|---|
| `config/paths.windows.ps1:46` | `if ($env:SCOOP) { $env:SCOOP } else { Join-Path $HOME 'scoop' }` |
| `platform/windows/adapters/packages.ps1:22-26` | same, via `GetFolderPath('UserProfile')` |
| `platform/windows/adapters/apps.ps1:175` | same |
| `platform/windows/adapters/apps.ps1:75` | **hardcoded** `(Join-Path $HOME 'scoop')` — no `$env:SCOOP` read at all |

Scoop itself resolves `$env:SCOOP, (get_config ROOT_PATH), "$PSScriptRoot\..\..\..\..",
~\scoop` (verified in the installed copy at `scoop/apps/scoop/current/lib/core.ps1:1291`), so
Scoop keeps working while PowerFlow silently reports zero Scoop apps and adds no shims.

**Design consequence: one resolver — `Get-PackageManagerRoot` — reading `$env:SCOOP` → Scoop's
own `root_path` → `~\scoop`.** `apps.ps1:75` is already wrong today on any machine with a
relocated Scoop, so that fix ships whether or not anything ever relocates.

### 2.4 REFUTED — "`DriveType` distinguishes internal from external"

Measured on this machine with the **real** adapters, not fixtures:

```
Get-StorageVolume  (platform/windows/adapters/apps.ps1:308)
  C:  sys=True   type=Fixed      free=862.9 GB  label='OS & Programs'
  D:  sys=False  type=Fixed      free=844.2 GB  label='Games'
  E:  sys=False  type=Fixed      free=481.3 GB  label='My Passport'   <-- USB
  F:  sys=False  type=Removable  free= 14.5 GB  label='16 GB'

Get-DiskInfo  (platform/windows/adapters/health.ps1:176)
  id=0 bus=NVMe  ext=False sys=True   letters='C:'   932 GB
  id=1 bus=NVMe  ext=False sys=False  letters='D:'   932 GB
  id=2 bus=USB   ext=True  sys=False  letters='E:'  1863 GB
  id=3 bus=USB   ext=True  sys=False  letters='F:'    15 GB
```

`Get-Volume` reports a **USB-attached WD My Passport as `Fixed`**. The obvious rule —
`DriveType -eq 'Fixed' -and -not IsSystem`, sorted by free space — is the same shape already
used at `components/system/storage.ps1:239`, and it puts a detachable 2 TB backup disk in the
candidate set. It picks D: here only by luck; the moment the Passport is emptier than D:, it
wins.

`Get-DiskInfo.External` (`platform/windows/adapters/health.ps1:240`,
`External = ("$($d.BusType)" -in @('USB','1394','Fibre Channel'))`) is the only signal in the
tree that tells them apart, and it already has a parity-matched Linux twin
(`platform/linux/adapters/health.ps1`, `External = ($bus -eq 'USB')`). **The join is not
optional.**

Two implementation details that will bite, both verified in the source: `Letters` is a
**space-joined string** (`health.ps1:237`, `-join ' '`), not an array; and the free/letter maps
are keyed by `$p.DiskNumber` (`health.ps1:192`) then read back by `$d.DeviceId`
(`health.ps1:236`). The join needs a split, and the key alignment needs asserting in a test.

### 2.5 The Windows `Get-PSDrive` fallback is not safe to auto-select from

`platform/windows/adapters/apps.ps1:329-345` runs only when `Get-Volume` throws. It:

- applies **no** drive-type or network filter and stamps everything `DriveType = 'Fixed'`
  (`:343`), contradicting the function's own rule at `:305-306` that *"Network drives are
  someone else's disk"*;
- emits a bogus `Temp:` row (PowerShell 7's built-in PSDrive) with `Root = 'Temp:\'`;
- **appends** to the same `$volumes` array the `try` block was filling (`:309` `$volumes = @()`,
  `+=` at both `:318` and `:335`, never reset), so a partial failure yields duplicates;
- is the one path in the storage area with **zero** test coverage — every assertion in
  `tests/storage/volume-contracts.ps1` injects a `-Volumes` fixture.

**Design consequence: when the fallback was used, bus type is unknowable, so there are zero auto
candidates.** Fail closed, and reject any candidate whose `Root` does not match `^[A-Za-z]:\\$`.

### 2.6 Letterless volumes are invisible

`platform/windows/adapters/apps.ps1:316-317` discards any volume with no drive letter — despite
the doc comment at `:301-303` claiming that seeing letterless volumes is *why* `Get-Volume` was
chosen. A data volume mounted as a **folder** (`C:\Data` backed by a second disk) is reported as
not existing. Pre-existing defect; the feature inherits it and must say so rather than telling
such a machine it has no second drive.

### 2.7 REFUTED — "Linux can already tell a real data mount from noise"

`Get-StorageVolume` on Linux (`platform/linux/adapters/apps.ps1:281-337`) applies exactly one
filter: `if ($fsType -in $script:PF_PseudoFilesystems) { continue }` (`:288`). Running the
repo's own parser and filter against a findmnt-shaped fixture, **9 of 10 rows survived** — only
`squashfs` was dropped:

| What survives as a "volume" today | Why |
|---|---|
| `/boot` (ext4), `/boot/efi` (vfat) | `IsSystem` is only `Target -eq '/'` (`:309`), and `tests/storage/volume-contracts.ps1:133-138` explicitly asserts ext4/vfat must **not** be filtered |
| `nfs`, `nfs4`, `cifs`, `smb3`, `fuse.sshfs`, `9p`, `drvfs` | none are in the 28-name list at `:246-251` — only `nfsd`, the server-side pseudo-fs, is |
| removable media at `/media/*`, `/run/media/*` | `DriveType` is the literal string `'Fixed'` at both `:310` and `:330` — on Linux it carries no information at all |
| a loop-backed ext4 image | `Source` is captured (`:265`) but never inspected |
| a read-only mount | the column list is `TARGET,SOURCE,FSTYPE,SIZE,AVAIL` (`:275`) — **`OPTIONS` is never requested**, so `ro` never reaches the adapter |
| file bind-mounts | nothing tests that the target is a directory; inside every Docker container `/etc/hosts` and `/etc/resolv.conf` are exactly that, carrying the host's ext4 fstype |

Two further defects found while checking. The dedup at `:289-291` keys on **Target**, not
Source, so its own comment (*"A bind mount reports the same device twice"*) describes behaviour
the code does not have. And the doc comment at `:243-244` promises a `df` fallback that exists
nowhere in the file — the real fallback is `[System.IO.DriveInfo]::GetDrives()` (`:315-333`),
which exposes none of the missing signals.

The repo already concedes the gap: `components/navigation/roots.ps1` calls `Get-StorageVolume`
and then re-filters with a hardcoded `^/(boot|snap|var|run|sys|proc|dev)(/|$)` regex — platform
path knowledge sitting in `components/`, which is the shape the architecture rule exists to
prevent.

**Design consequence: Linux needs a classifier, and it must read `/proc/self/mountinfo`
directly rather than add columns to `findmnt`.** The distro CI matrix installs only
`bash sudo curl ca-certificates git` into its containers
(`.github/workflows/release-validate-linux.yml:55-59`), so `findmnt` and `lsblk` are **not**
present on the Alpine/musl and Arch legs. `/proc/self/mountinfo` is kernel-provided, works
identically under musl, and yields mount options (`ro`), the `MAJ:MIN` device identity (st_dev),
the fs-root (bind detection) and the source device in one read. This follows the repo's own
stated doctrine at `platform/linux/adapters/apps.ps1:403-407` — `/proc/meminfo` is read instead
of `free` precisely because procps is absent from minimal images — and reuses the parse already
shipping at `platform/linux/adapters/proxmox.ps1:762-766`.

Honest limit: `MAJ:MIN` answers *"a different filesystem"*, not *"a different spindle"* — two
partitions of one disk have different st_dev. `lsblk`'s `PKNAME`/`TRAN` answers the harder
question and is an **optional refinement**; when it is absent the candidate is `unknown` and is
never auto-selected. Note that `Get-DiskInfo` on Linux skips `^(loop|ram|sr|dm-|zram)`
(`platform/linux/adapters/health.ps1:273`), and LVM/LUKS are `dm-` devices — the default layout
on Debian, RHEL/Fedora and openSUSE server installs — so it must fail closed to `unknown`, never
to `yes`.

**Not verified:** none of the Linux behaviour above was executed on a Linux host. The parser and
filter were exercised by dot-sourcing the real adapter on Windows against a fixture; the
mountinfo classifier is a design, not a measurement.

### 2.8 There is no writability primitive anywhere in the repo

`grep -rE "Test-Writ|writable|W_OK" components/ platform/ install.ps1` finds only a cosmetic
world-writable warning at `components/files/listing.ps1:89` and prose in the shell lessons.
`platform/linux/adapters/perms.ps1` reads POSIX mode bits and deliberately stops at reporting
them — it never infers capability.

This must be a **create-a-file-then-delete-it probe**, not mode-bit arithmetic: POSIX ACLs, a
root-squashed NFS export, an SELinux denial, a BitLocker-locked volume, a read-only remount and
a full filesystem all pass a mode check and then fail the write. It must run **before** any
placement: `install.sh:21` is `set -euo pipefail` and `install.sh:552` is a bare
`mkdir -p "$PREFIX"` that would die mid-run *after* pwsh may already be in `/opt`; `install.ps1`
runs `New-Item -ItemType Directory -Force` under `$ErrorActionPreference = "Stop"`.

### 2.9 `--prefix` is not an install root, and never was

`install.sh:27` sets `PREFIX="${HOME}/.local/share/powerflow"` and the help text at
`install.sh:62` calls it *"Install root"* — but `install.sh:578` copies the tree there and
`install.sh:588` hands the same directory to `install.ps1` as `-Prefix`, which
`install.ps1:160-162` consumes as the **source**. The real install still lands at
`Split-Path $PROFILE -Parent`. So `--prefix /mnt/data` today produces a **second dead copy** on
`/mnt/data` and relocates nothing. The new option must not be called `--prefix`, and the help
text should be corrected in the same change.

### 2.10 The CI gates that constrain the shape

| Gate | Scope | Constraint |
|---|---|---|
| Platform separation (`release-validate.yml:151-158`) | `components/` **only** | `\bscoop\b`, `Get-CimInstance`, `SetEnvironmentVariable`, `$env:(TEMP\|USERPROFILE\|LOCALAPPDATA\|APPDATA\|SystemRoot)` banned there. All drive logic must live in `platform/*/adapters/`, `config/`, or `install.ps1`. |
| Adapter parity (`release-validate.yml:391-435`) | calls collected from `components/` **and** `config/` | Any adapter-defined Verb-Noun name called from either **must exist on both platforms**, recognised only by `^function Name` at **column zero** (`:396-398`). |
| Flag spelling (`release-validate.yml:231-268`) | `components`, `windows-only`, `platform` | Any 3+ character token with one dash inside a `Register-PFCommand` call fails the release. |
| Coreutil shadowing (`release-validate.yml:185-196`) | `components/` | 57 banned names including `mount`, `df`, `du`, `stat`, `find`, `realpath`, `readlink`, `free`. Only `ls`/`la`/`ll` allow-listed. |
| Help registry (`release-validate.yml:322-333`) | `components`, `windows-only` | A kebab-named function or alias with no `Register-PFCommand` fails the release. |
| Linux leftover check (`release-validate-linux.yml:447-454`) | literal `$HOME/.config/powershell` | Tests for **absence** at a fixed path — it would go **vacuously green** for anything stranded at a declared root. |

Two holes worth naming: **`install.ps1` is scanned by no gate at all**
(`grep -n "install.ps1" .github/workflows/release-validate.yml` returns nothing), and
`tests/storage/volume-contracts.ps1:17`'s hand-maintained contract array is **already two names
stale** (`Get-StorageMemory` and `Get-StorageLayout` are defined in both adapters and listed
nowhere). A helper reached only from the installer, added to one platform, passes everything and
explodes at install time on the other OS.

### 2.11 The docs have no CI backstop, and are already drifting

No workflow validates `COMPONENTS.md`, `README.md` or `docs/installation.md` against reality.
`README.md:389` still claims the bootloader dot-sources 28 component files; there are 66. The
release-checklist item about a README documenting behaviour a release reversed
(`docs/release-checklist.md:72-74`) applies directly to the hardcoded Scoop paths in
`docs/troubleshooting.md:193, 241, 244`.

---

## 3. Inventory — every location PowerFlow creates or grows today

This is the evidence that motivates the change. Sizes marked *(measured)* were taken on the
author's Windows machine on the day of writing.

### 3.1 The install root (both platforms)

| Path | Contents | Growth |
|---|---|---|
| `Split-Path $PROFILE -Parent` — Windows `~\Documents\PowerShell`, Linux `~/.config/powershell` | the profile, `config/ components/ platform/ windows-only/ docs/git-rl/`, `uninstall.ps1`, `.powerflow-manifest.json` | **fixed, 1.67 MB** *(measured)* |
| `…\Microsoft.PowerShell_profile.ps1.powerflow-backup.<stamp>` | one-time backup of a pre-existing foreign profile (`install.ps1:151-154`); never listed in `manifest.files`, never removed by uninstall | fixed |

Every one of `config/ components/ platform/ windows-only/` is `Remove-Item -Recurse -Force`'d
before being re-copied on **every** install (`install.ps1:201-211`, deletion at `:206`) — which
is exactly how `CHECK_PROFILE_UPDATES` (`components/core/version.ps1:106`) and
`LINUX_LESSON_MODE` (`components/shell/teach.ps1:57`), both persisted by regex-rewriting the
installed settings file, get destroyed on upgrade. **Nothing this feature persists may live
under those four directories.**

The Windows install root also doubles as PowerShell's own user module store — `Modules\` sits
beside `components\` on this machine, and it is the first entry on `$env:PSModulePath`.

### 3.2 Windows

| Path | What | Growth |
|---|---|---|
| `$env:SCOOP` else `~\scoop` | **the whole story.** `apps/ cache/ buckets/ shims/ persist/` | **unbounded — 570 MB** *(measured: apps 466.8, cache 93.7, buckets 7.8, shims 1.8)* |
| `<scoop>\apps\{starship,fzf,zoxide,lsd,git}` | the five managed dependencies (`install.ps1:299`) | unbounded |
| `<scoop>\apps\FiraCode-NF-Mono` + `HKCU\…\Windows NT\CurrentVersion\Fonts` | the Nerd Font; bytes on disk, registration in the registry (`platform/windows/adapters/fonts.ps1:24, 78, 84`) | bounded |
| `<scoop>\cache` | Scoop's download cache. **Referenced nowhere in the tree** — no pruning, no sizing, no location control | unbounded, 93.7 MB *(measured)* |
| `%LOCALAPPDATA%\PowerFlow` (`Get-PowerFlowDataPath`, `locations.ps1:22-24`) | `helpers/powerflow-ssh-askpass.exe`, `pmx-audit.jsonl` | unbounded |
| `%APPDATA%\PowerFlow` (`Get-PowerFlowConfigPath`, `locations.ps1:26-28`) | `pmx.json`, `folder-preference.json` | bounded |
| `%TEMP%` markers | `.powerflow_update_check`, `.powerflow_rate_limit`, `.pwsh_update_check`, `powerflow-help/`, `powerflow-update-<rand>/`, `update_powershell.bat` | bounded |

Neither `%LOCALAPPDATA%\PowerFlow` nor `%APPDATA%\PowerFlow` exists on this machine — no feature
that writes them has run yet. That is what makes migration cheap here (§8).

### 3.3 Linux

| Path | What | Growth |
|---|---|---|
| `$XDG_DATA_HOME/powerflow` (default `~/.local/share/powerflow`) | `Get-PowerFlowDataPath` — `pmx-audit.jsonl`, `helpers/powerflow-ssh-askpass` | unbounded |
| **the same directory**, as `install.sh`'s `PREFIX` (`install.sh:27`) | a **second full copy of the tree**, staged and then copied again into `~/.config/powershell`. Never removed by uninstall, never checked by CI | bounded, duplicated |
| `$XDG_CONFIG_HOME/powerflow` | `pmx.json`, `folder-preference.json`, `path.ps1` (dot-sourced at every profile load, `config/paths.linux.ps1:71`) | bounded |
| `/opt/microsoft/powershell/7` + `/usr/local/bin/pwsh` | pwsh itself, root-owned (`install.sh:200-203`) — **the single largest item the Linux bootstrap places** | fixed, ~150-200 MB (not measured here) |
| `/usr/local/bin/<tool>` | starship/lsd/zoxide from the GitHub-tarball fallback (`platform/linux/adapters/packages.ps1:221`) | fixed |
| distro package prefixes and caches | apt/dnf/pacman/zypper/apk (`platform/linux/adapters/packages.ps1:126-142`) — **PowerFlow cannot redirect any of it** | unknown |
| `~/.local/share/fonts/PowerFlow-NerdFont/` | hardcoded to `$HOME`; does **not** honour `XDG_DATA_HOME` (`platform/linux/adapters/fonts.ps1:35`) | bounded |
| `/etc/profile.d/powerflow-path.sh`, `/etc/shells`, `~/.bashrc` | integration points, root- or shell-owned | fixed |

### 3.4 Both platforms, outside every managed root

| Path | Written by | Growth |
|---|---|---|
| `$HOME/.nav_bookmarks.json` | `components/navigation/bookmarks.ps1:11` | bounded |
| `$HOME/.nav_roots.json`, `.nav_anchors.json` | `components/navigation/roots.ps1:30, 403` | bounded |
| `$HOME/.powerflow-servers.json` | `components/network/servers.ps1:29` | bounded |
| `$HOME/.powerflow-power-state.json` | `components/system/health.ps1:24` — **safety-critical**, the only record enabling `pc-cap restore` | fixed |
| `<data>/pmx-audit.jsonl` | `components/proxmox/config.ps1:59`, appended per operation via `[IO.File]::AppendAllText` at `:488`, on by default at `:35` | **unbounded — the one genuinely unbounded file PowerFlow itself writes.** No rotation, cap or retention exists anywhere in the tree |
| `$HOME/pmx-reports/<slug>-<stamp>/` | `components/proxmox/evidence.ps1:88` — a new directory per run, never pruned | unbounded |
| `$HOME/Desktop/pc-crash-report` | `components/system/health.ps1:469` — overwritten per export | bounded |

`uninstall.ps1:200-204` lists only **three** of those `$HOME` dotfiles and never references
`Get-PowerFlowDataPath` or `Get-PowerFlowConfigPath` at all — so `.nav_anchors.json`,
`.powerflow-power-state.json`, `pmx.json`, `folder-preference.json`, `pmx-audit.jsonl` and the
compiled askpass helper all survive `-Purge` today.

---

## 4. Recommended design — a declared storage root

**One sentence.** PowerFlow declares, per machine, one directory that owns everything it causes
to grow — the Scoop root and PowerFlow's own data — chosen at first install from the emptiest
**internal, non-system, writable** volume when one exists and from the platform-native place
when one does not; the component tree, the manifest and the uninstaller never move.

### 4.1 The five decisions, and why each is that way

1. **The tree stays beside `$PROFILE`.** 1.67 MB against 570 MB (§1), and moving it breaks
   uninstall discovery, the two Windows test sandboxes, and `powerflow-update` (§2.1).
2. **The root governs `<root>\scoop` and `<root>\data` only.** `Get-PowerFlowConfigPath` stays
   at `%APPDATA%\PowerFlow` / `$XDG_CONFIG_HOME/powerflow` — small preference files must never
   live on a drive that can vanish. `Get-TempPath` stays too: four files under it are behaviour
   state, not scratch (`components/core/version.ps1:44, 61`,
   `components/core/dependencies.ps1:74`, `components/help/menu.ps1:226`), and relocating them
   resets the update snooze and the GitHub 403 cooldown on every drive-absent session.
3. **Scoop is relocated by process-scope `$env:SCOOP` before the bootstrap, and Scoop persists
   its own choice** (§2.2). PowerFlow writes no registry value and needs no new env adapter.
4. **The root proves its identity with a marker file, not with `Test-Path`.** Drive letters get
   reassigned, so `D:\PowerFlow` existing is not proof it is *our* D:; and on Linux an unmounted
   mountpoint has an empty directory underneath, so a path test succeeds while writes land on
   the root filesystem inside a hidden directory.
5. **Auto-selection fails closed.** No confirmed internal disk, no auto candidate. An explicit
   user choice may still proceed, after being told what could not be confirmed.

### 4.2 The two files that make it work

**The policy** — `<installRoot>\.powerflow-storage.json`, at the install root, **never** under
`config/` (§3.1):

```json
{ "schema": 1,
  "id": "3f9c...",
  "root": "D:\\DevTools\\PowerFlow",
  "chosenBy": "auto",
  "chosenAt": "2026-...Z",
  "volume": "D:", "reason": "internal NVMe, 844 GB free" }
```

`chosenBy` is `auto | user | inherited`. It is what lets an upgrade distinguish *"this machine
never chose"* from *"this machine chose the default"*, and it makes the legacy rule — no policy
means inherited, never re-decide — expressible rather than implicit. The policy is also mirrored
into the manifest (`install.ps1:395-404` gains one `storageRoot` object) so `uninstall.ps1` needs
no second file to parse.

**The marker** — `<root>\.powerflow-root`, one line holding the same GUID.

**Resolution** (`Get-PowerFlowStorageRoot`, memoised into a script-scoped variable; at most
three file operations, once per session):

| Condition | Result | State |
|---|---|---|
| no policy file | `''` | `none` — **byte-identical to today** |
| `policy.root` does not exist | `''` | `missing` |
| `<root>\.powerflow-root` absent | `''` | `missing` |
| marker GUID ≠ `policy.id` | `''` | `foreign` |
| otherwise | `policy.root` | `active` |

Any result but `active` falls back to the platform default and warns **once per session**.

### 4.3 Windows, second drive present

Layout: `<root>\scoop\`, `<root>\data\`, `<root>\.powerflow-root`.

1. `install.ps1` runs unchanged through platform detection, destination (`:66-68`), the
   profile-conflict/backup block (`:86-155`) and source resolution (`:158-186`). **No
   reordering** — the destination is not what is being chosen, so the ordering hazard that would
   push a GitHub download ahead of the overwrite prompt never arises.
2. After the tree copy (`:198-234`) and before the existing packages dot-source at `:265`, two
   more adapters are dot-sourced **from the just-copied tree**:
   `platform/windows/adapters/apps.ps1` and `.../health.ps1`. Both are safe standalone — I
   verified their only top-level statements are `Add-Type -AssemblyName Microsoft.VisualBasic
   -ErrorAction SilentlyContinue` (`apps.ps1:14`) and `$script:` array assignments, and
   `tests/storage/volume-contracts.ps1:37,77` already dot-sources both platforms' copies in one
   session on `windows-latest`.
3. `Get-StorageCandidate` joins `Get-StorageVolume` (name, root, free, `IsSystem`) with
   `Get-DiskInfo` (parent disk `External`), keyed on drive letter — **splitting `Letters` on
   space** (§2.4). Rejections, each carrying a `Reason` string:
   - `IsSystem`;
   - `DriveType -eq 'Removable'`;
   - parent disk `External` (USB / 1394 / Fibre Channel);
   - **parent disk not identifiable at all** → not eligible for auto (`Get-DiskInfo` returns
     `@()` when both `Get-PhysicalDisk` and the CIM fallback fail, `health.ps1:177-184`);
   - `Root` not matching `^[A-Za-z]:\\$`, or the `Get-PSDrive` fallback was used (§2.5);
   - filesystem not NTFS/ReFS — Scoop needs junction and hardlink support, and an exFAT data
     drive also breaks the SSH askpass helper's permissions;
   - free space below the floor (proposed 20 GB — OQ 4);
   - `Test-StorageWritable` fails (create-and-delete probe, §2.8).

   On this machine the eligible set is exactly `{ D: }`.
4. **Auto fires only when exactly one candidate passes.** Two or more → a picker, never a guess.
   Zero → §4.4.
5. Preview, one confirmation. Under `-Yes` or `[Console]::IsInputRedirected` — which is
   `irm | iex` and CI — a single unambiguous candidate proceeds and prints the choice; anything
   ambiguous falls back to the system-drive layout and prints the exact re-run line. That is a
   real gap between the promise and the piped path, stated rather than hidden (OQ 5).
6. `$env:SCOOP = '<root>\scoop'` is set **in the installer process only**, then the existing
   `Install-PackageManager` runs unchanged. Scoop writes `root_path` itself; the 93.7 MB cache
   follows for free; `Add-ShimsDirToPath` writes the shims directory into the user PATH, so
   cmd.exe and `pwsh -NoProfile` resolve tools with no PowerFlow involvement.
   **After the bootstrap, verify `(Get-Command scoop).Source` resolves under the declared root
   and fail closed with a message if it does not** — the mechanism is verified against today's
   bootstrap, not guaranteed forever. The bootstrap's own `-ScoopDir` parameter
   (`get.scoop.sh:59`), reachable via the scriptblock form, is the documented fallback if the
   env route ever stops working.
7. `Get-PowerFlowDataPath` returns `<root>\data`. Policy and marker are written. The manifest
   gains `storageRoot`.

**An existing Scoop is never moved by the installer.** The proposal is made only when
`Test-PackageManager` is false — a genuinely fresh box. On any machine that already has Scoop
the installer prints one advisory line and does nothing. That single guard is also what stops
`powerflow-update` (`components/core/version.ps1:193`, a `pwsh -NoProfile` child with
`-Yes -NoDeps`) from ever re-deciding placement, and it keeps `Deny-Install`'s exit-0/`break`
behaviour (§2.2) unreachable. Belt and braces: the installer reads an existing policy and carries
it forward rather than re-detecting — the same *"trust what we wrote last time"* rule already
applied to the profile backup (`install.ps1:138-149`) and dependency ownership
(`install.ps1:252-263`) — and `version.ps1` passes the recorded root explicitly.

Moving an **existing** Scoop is a separate, explicitly-invoked operation (§4.7).

### 4.4 Windows, no second drive

**Nothing relocates, and that is deliberate.** `Get-StorageCandidate` returns an empty eligible
set, no policy is written, `Get-PowerFlowDataPath` returns exactly what it returns today, and
Scoop lands at its own default `~\scoop`. **Zero behavioural delta from the current release.**
Same outcome when the only other volume is USB, removable, a network drive, non-NTFS, or
unwritable.

I deliberately do **not** move Scoop into `%LOCALAPPDATA%` on a single-drive box. It is
tempting — `~\scoop` in the top level of the home directory really is "an unknown location" —
but it is Scoop's own documented default that every Scoop answer on the internet names, moving
it frees no capacity, and gratuitous churn is the opposite of minimum blast radius.

What a single-drive machine gets instead is real:

1. **Accounting.** Bare `storage root` names and sizes every location PowerFlow causes to exist,
   in one screen, with a growth class per row — install tree, Scoop broken into
   apps/cache/buckets/shims, PowerFlow data, config, temp markers, and the out-of-scope growers
   (`pmx-reports/`, the Desktop crash bundle) so the accounting is honest about where the space
   actually went. Sizes come from `Measure-FolderSize`, which already exists on both platforms
   (`platform/windows/adapters/apps.ps1:100`, `platform/linux/adapters/apps.ps1:38`). "Growing
   in an unknown location" stops being unknown even when nothing moves.
2. **Reclaim.** `storage root prune` — previewed and confirmed — clears the Scoop download cache
   (93.7 MB here, referenced nowhere in the tree today) and the stale help-preview cache under
   `Get-TempPath`. It **reports** the audit log's size but does not delete it; silently deleting
   audit records is not something a prune verb should do.
3. **Two fixes that land regardless.** `Get-DiskHotspot`'s hardcoded `~\scoop`
   (`platform/windows/adapters/apps.ps1:75`) becomes `Get-PackageManagerRoot`, so `storage big`
   stops being blind to the 570 MB it exists to surface; and all four Scoop-root sites become
   one resolver that also reads `root_path` (§2.3).
4. **A named reality.** The report states when the install root is inside a OneDrive-redirected
   Documents folder — `platform/windows/adapters/locations.ps1:44-57` documents that Known
   Folder Move is *"the default on many setups"*, which means a large share of installs are
   already relocated and cloud-synced without anyone choosing it. The tree still does not move;
   the user is simply told.

### 4.5 Linux, separate data mount present

Layout: `<root>/data/` and `<root>/.powerflow-root`. **There is no `<root>/scoop`.**

`Get-PackageManagerRoot` returns `$null` on Linux and the design says why: dependencies come
from apt/dnf/pacman/zypper/apk into distro-owned prefixes
(`platform/linux/adapters/packages.ps1:126-142`), the tarball fallback hardcodes
`/usr/local/bin` (`:221`), pwsh goes to `/opt/microsoft/powershell/7` (`install.sh:200-203`), and
`/etc/profile.d`, `/etc/shells` and the font directory are all outside a per-user choice.
Returning `$null` is the established shape here — `Get-TerminalSettingsPath` does exactly that
(`platform/linux/adapters/locations.ps1:26-29`), and `Get-StorageLayout` returns
`Supported=$false; Reason='lsblk is not installed'` with the rationale *"a partial disk layout
presented as complete is worse than saying nothing"* (`platform/linux/adapters/apps.ps1:468-475`).

`Get-StorageCandidate` reads `/proc/self/mountinfo` and rejects, each with a `Reason`:

| Rejection | Why it is needed |
|---|---|
| st_dev equal to `/`'s | not another filesystem at all |
| fstype in the existing 28-name pseudo list, **plus a new network list**: `nfs nfs4 cifs smbfs smb3 fuse.sshfs 9p drvfs afs ceph glusterfs iso9660 udf erofs fuseblk` | §2.7 — a network share is a first-class "Fixed" volume today, and under WSL2 the Windows host drives appear as 9p/drvfs |
| mount options contain `ro` | invisible today; mountinfo gives it free |
| target is `/`, `/boot`, `/boot/efi`, `/efi`, `/snap`, `/var/lib/docker`, or under `/proc\|/sys\|/dev\|/run\|/media` | `ext4` and `vfat` are contractually un-filterable as *types* (`tests/storage/volume-contracts.ps1:133-138`), so a 512 MB ESP can only be excluded by mount point |
| target is not a directory | `findmnt -l` and mountinfo both list file bind-mounts; the distro matrix runs entirely in containers |
| duplicate `(Source, fs-root)` | fixes the Target-only dedup bug at `apps.ps1:289-291` for this feature without touching the shipped function |
| mount point or source absent from `/etc/fstab` | a mount that will not survive a reboot is offerable, never auto-selected |
| `Test-StorageWritable` fails | a second mount is very often `root:root 0755` |
| free space below the floor | as Windows |

Optional refinement when `lsblk` exists: `lsblk -b -P -o NAME,TYPE,ROTA,TRAN,MOUNTPOINT,PKNAME`
marks `TRAN=usb` external and excludes it from auto. Following `Invoke-PmxLsblkJson`
(`platform/linux/adapters/proxmox.ps1:94-98`), the query must retry with `MOUNTPOINT` when
`MOUNTPOINTS` fails — the column name varies by util-linux version. Without `lsblk` the candidate
is `unknown` and is never auto-selected.

**The Linux default is detect-and-advise, not relocate.** XDG already answers *"where does user
data go"* correctly, and overriding `$XDG_DATA_HOME` unasked would *be* the sprawl rather than
the cure. Windows has no equivalent convention for `~\scoop`, which is exactly why the Windows
default acts and the Linux default advises. A Linux install prints one line:

```
🗄️  /mnt/data  1.4 TB free (internal, ext4, rw, in fstab)
    PowerFlow's data is at ~/.local/share/powerflow. To move it:  storage root /mnt/data
```

Relocation is opt-in: `install.sh --storage-root /mnt/data`, or `storage root /mnt/data` later.
This asymmetry is a real gap against *"respectfully on Linux we would need to allocate a similar
behaviour"* and is put to the owner as OQ 3.

### 4.6 Linux, no separate mount

Identical to §4.4: nothing relocates, no policy is written, behaviour is byte-identical to
today, and `storage root` reports and prunes. The one thing worth fixing anyway is the **second
full copy of the tree** at `~/.local/share/powerflow` (§3.3) — `install.sh`'s `PREFIX` should
become a `mktemp -d` removed on exit, which also resolves its accidental collision with
`Get-PowerFlowDataPath` (both resolve to the same directory, and one of them holds the audit
log). See OQ 6.

### 4.7 Moving an existing Scoop — the one genuinely dangerous operation

Scoop shims embed absolute paths, and the manifest records only a tool's **name** and manager
(`install.ps1:322-331`) — no path. So this is never automatic, never part of an install or
update, and always its own confirmation:

```
storage root --adopt-packages

FROM  C:\Users\<you>\scoop            570 MB   (apps 467 · cache 94 · buckets 8 · shims 2)
TO    D:\DevTools\PowerFlow\scoop     844 GB free

WILL RUN   scoop config root_path D:\DevTools\PowerFlow\scoop
           scoop reset *                  (rewrites every shim and persist junction)

⚠  This touches launchers for EVERY tool Scoop manages, including ones unrelated
   to PowerFlow. If D: is ever absent at login, those tools will not resolve
   until it returns. PowerFlow itself still loads.

Proceed? (y/n)
```

Order: **copy** (never move) → `scoop config root_path` → `scoop reset *` → **verify** all five
managed tools resolve under the new root via `Get-Command` → only then a **second** confirmation
before reclaiming the old tree. Rollback is `scoop config root_path <old>` + `scoop reset *`,
possible at every stage because the source is still on disk, and it must be **printed in the
failure message**, not merely documented.

Two hard refusals. If a User-scope `SCOOP` registry value exists
(`[Environment]::GetEnvironmentVariable('SCOOP','User')`), refuse by name — it outranks
`root_path` in Scoop's own resolver (`core.ps1:1291`) and would create two sources of truth. Same
for `SCOOP_GLOBAL`, which appears **nowhere** in the PowerFlow tree today, so machine-wide Scoop
installs are entirely unmodelled: detect and refuse rather than half-support.

`scoop reset` has never been exercised by this repo and there is no dry-run for it. This
increment must be rehearsed on a throwaway box before it ships (§9, increment 8).

---

## 5. User-facing surface

### 5.1 Runtime command

`storage` already means *"where did my space go"*, already dispatches five sub-verbs
(`components/system/storage.ps1:454-463`), and is where a user hunting disk space already goes.
Adding a second top-level noun would re-create the command spread that `storage` was built to
eliminate. So this is a sub-verb.

```
storage root                      where PowerFlow keeps what grows, sized. READ-ONLY.
storage root auto                 pick the best candidate, preview, confirm
storage root D:                   a TARGET is positional — never -D
storage root D:\DevTools\PowerFlow   a full path is accepted; nested is preferred (§5.4)
storage root /mnt/data            the same word on Linux — a mount, not a letter
storage root off                  revert to the platform defaults (previewed)
storage root prune                reclaim the package download cache and stale previews
storage root --adopt-packages     Windows only: relocate an EXISTING Scoop (§4.7)
storage root --dry-run            print the plan and stop
storage root --show-native        print the real commands it would run
storage root --educate            already free — `storage` strips --educate first
```

The `root` case goes **inside** the switch at `components/system/storage.ps1:416`, **above** the
`Resolve-StorageVolume` fallthrough at `:442` — `tests/storage/storage-behaviour.ps1:128-134`
asserts verb dispatch precedes volume resolution, so a verb added below would be swallowed as a
volume name.

**Flag ethos.** A verb is a word (`auto`, `off`, `prune`); a target is positional — the rule
`storage`'s own help already states at `components/system/storage.ps1:249` (*"The volume is a
TARGET, not a flag"*); long options are `--kebab-case`; there are no short forms. `storage root`
hand-parses `$args` with no `param()` block, exactly as `storage` does and for the documented
reason: a `param()` would bind `-D` as a parameter name.

**Convenience creed.** The bare command does the useful thing — the report. Ambiguity gets an fzf
picker over the classified candidates, each row showing free space, disk type and why it
qualified, with a numbered `Read-Host` fallback when fzf is absent
(`components/files/operations.ps1:186-192`). Naming an excluded volume is **not** a usage error;
it is accepted with the rejection reason leading the preview, because refusing outright is
paternalistic and hiding the reason is dishonest:

```
⚠  E: is a USB-attached disk (WD My Passport). If it is unplugged, PowerFlow falls
   back to C: and says so, and the tools Scoop installed will not resolve.
   Eligible here: D:  (844 GB free, internal NVMe)
   Continue with E: anyway? (y/n)     or:  storage root D:
```

### 5.2 The literal registration

Section string copied character-for-character from `$script:PF_HelpSections`
(`components/help/registry.ps1:32-48`). Space-separated sub-verbs as separate entries is the
existing precedent at `components/system/storage.ps1:454-463`. No `Set-Alias`.

```powershell
Register-PFCommand -Name 'storage root' -Section '🗄️ DISK RECLAIM' `
    -Synopsis 'where PowerFlow keeps what grows, and on which drive' `
    -Example 'storage root · storage root auto · storage root D:'

Register-PFCommand -Name 'storage root prune' -Section '🗄️ DISK RECLAIM' `
    -Synopsis 'reclaim the package download cache and stale previews' `
    -Example 'storage root prune'
```

Neither example contains a single-dash word, so the flag-spelling gate
(`release-validate.yml:231-268`) is satisfied. `--adopt-packages`, `--dry-run`, `--show-native`
and `--educate` are two-dash kebab words. `Get-StorageCandidate`, `Test-StorageWritable`,
`Get-PowerFlowStorageRoot`, `Set-PowerFlowStorageRoot` and `Get-PackageManagerRoot` are Verb-Noun
internals and go in `COMPONENTS.md`, **not** the registry — CLAUDE.md's Help Registration Rule is
explicit that `pwsh-h` is a command reference, not a function index.

### 5.3 Installer flags

Script parameters, not PowerFlow commands, so they keep the native spelling each entry point
already uses:

```
install.ps1   -StorageRoot auto | <path> | off        default: auto
install.sh    --storage-root auto | <path> | off      default: auto
install-gui.sh                                        gains the same choice as a dialog
```

`--storage-root` mirrors the existing `--login-shell auto|login|none` three-value shape
(`install.sh:85-95`) — this repo's own precedent for *a choice with a sensible default and an
explicit off*.

**It is not `--prefix`.** `--prefix` already means the staging source tree (§2.9), and its help
text at `install.sh:62` is corrected from *"Install root"* to *"source tree to install from"* in
the same change. `install-gui.sh` builds a fixed `INSTALL_ARGS=(--yes)` at `:78` and forwards
`"$@"` only when no dialog toolkit is found (`:32`), so the choice must be added there
**explicitly** or graphical installs — the ones most likely to be run by someone who has never
heard of `--prefix` — silently keep the default. Its consent text at `:65` must name the chosen
root.

### 5.4 Preview before any mutation

```
storage root D:\DevTools\PowerFlow

WILL CREATE   D:\DevTools\PowerFlow\{scoop, data}  and  .powerflow-root
WILL MOVE     (nothing — Scoop is already on C:; see --adopt-packages)
STAYS PUT     the profile, components/, platform/, the manifest, the uninstaller
              PowerFlow's settings (%APPDATA%\PowerFlow) — they record where the root went

⚠  If D: is absent at shell start, PowerFlow falls back to C: defaults and says so once.
   PowerFlow itself still loads.

UNDO          storage root off
Proceed? (y/n)
```

**Prefer a nested path.** `platform/windows/adapters/apps.ps1:50-56` returns `$true` from
`Test-ProtectedPath` for any path of two or fewer segments outside `Users\` and `Temp\`, so
`D:\PowerFlow` is protected by construction and `disk-big`'s delete flows would refuse to act on
it. `D:\DevTools\PowerFlow` is three segments and is not. Either way the declared root is added
to `Get-ProtectedPaths` **explicitly on both platforms** — Windows already protects
`(Split-Path $PROFILE -Parent)` at `apps.ps1:32`, while the Linux list
(`platform/linux/adapters/apps.ps1:18-25`) does **not** protect the install root at all, a
pre-existing asymmetry this change closes.

---

## 6. Files to change or create

### Adapters — every new name at column zero, on **both** platforms, in the same commit

| File | Change |
|---|---|
| `platform/windows/adapters/packages.ps1` | **new** `Get-PackageManagerRoot`: `$env:SCOOP` → Scoop's own `root_path` from `<UserProfile>\.config\scoop\config.json` → `~\scoop`. `Install-PackageManager` gains `-Root`, which sets **process-scope** `$env:SCOOP` before the bootstrap and verifies `(Get-Command scoop).Source` afterwards. Never writes a persistent variable. |
| `platform/linux/adapters/packages.ps1` | **new** `Get-PackageManagerRoot` returning `$null`, with the reason in the doc comment. `Install-PackageManager -Root` accepts, ignores, and says so. |
| `platform/windows/adapters/apps.ps1` | **new** `Get-StorageCandidate` (Get-StorageVolume ⋈ Get-DiskInfo, the rejections in §4.3, each with a `Reason`), **new** `Test-StorageWritable`. `Get-DiskHotspot:75` consults `Get-PackageManagerRoot` **only when defined**, falling back to its current expression so the file still dot-sources standalone. `Get-ProtectedPaths:23-35` gains the declared root. |
| `platform/linux/adapters/apps.ps1` | Linux twins of both, reading `/proc/self/mountinfo`. `Get-ProtectedPaths` gains the declared root **and** the install root. Add the missing network fstypes to `$PF_PseudoFilesystems`. Fix the stale `df` comment at `:243-244` and the Target-only dedup comment at `:289`. Add the three storage functions to the header, which omits them. |
| `platform/windows/adapters/locations.ps1` | **new** `Get-PowerFlowStorageRoot` (memoised; the five-state table in §4.2) and `Set-PowerFlowStorageRoot`. `Get-PowerFlowDataPath` derives from it; `Get-PowerFlowConfigPath` deliberately does not. Fix the header, which declares four functions while the file defines seven. |
| `platform/linux/adapters/locations.ps1` | same, plus the same header fix. |

### Component and config

| File | Change |
|---|---|
| `components/system/storage.ps1` | `root` case inside the verb switch above `Resolve-StorageVolume`; report / auto / target / off / prune / `--adopt-packages` / `--dry-run`; two `Register-PFCommand` calls; `storage`'s footer gains a pointer. |
| `config/paths.windows.ps1` | `Initialize-PFScoopPath` resolves through `Get-PackageManagerRoot` **when defined** (adapters load at bootloader step 2, this file at step 3), falling back to its current inline expression. **The never-write rule and all six existing assertions stand unchanged.** This is the one place the parity tax is paid deliberately: the call pulls `Get-PackageManagerRoot` into the cross-platform contract, and the Linux twin returning `$null` is the honest answer, precedented by `Get-TerminalSettingsPath`. Keeping the resolution inline is a defensible alternative that avoids the tax at the cost of a duplicated resolver. |

### Installers and uninstaller

| File | Change |
|---|---|
| `install.ps1` | new `-StorageRoot auto\|<path>\|off`; dot-source `apps.ps1` + `health.ps1` from the copied tree before the Scoop block; propose **only** when `Test-PackageManager` is false; read and carry forward an existing policy; set process `$env:SCOOP`; write policy + marker; add `storageRoot` to the manifest at `:395-404`. |
| `install.sh` | new `--storage-root`; correct the `--prefix` help text; make `PREFIX` a `mktemp -d` removed on exit; stop `--uninstall` hard-requiring `${PREFIX}/uninstall.ps1` (`:504-505`) and exec'ing out of it (`:547`) — ask pwsh for `$PROFILE`, read the manifest beside it, run the copy sitting there; add `readlink -f` to the same-directory guard at `:577`, since comparing `cd … && pwd` strings makes a symlinked or bind-mounted prefix compare unequal to itself and `copy_tree` then tars a directory into itself. |
| `install-gui.sh` | forward the choice explicitly (`:78`, `:124`) and name the root in the consent text (`:65`). |
| `uninstall.ps1` | a comment at `:43` explaining why manifest discovery must stay on `$PROFILE`; read `manifest.storageRoot`; verify the marker before touching anything; remove `<root>/data` and the marker; remove `<root>` only if empty afterwards; report a kept relocated Scoop **by path and size**; teach the no-manifest branch to read the policy before deleting by guesswork; extend `-Purge` to `.nav_anchors.json`, `.powerflow-power-state.json` and the data/config directories — **keeping the power-state file, with the reason printed, if a CPU cap is currently active** (`components/system/health.ps1:945-956`, *"THE ORDER IS THE FEATURE"*). |
| `components/core/version.ps1` | `Invoke-PFSelfUpdate` passes the recorded root explicitly to the child installer at `:193`. |

### Tests and CI

| File | Change |
|---|---|
| `tests/storage/volume-contracts.ps1` | extend the contract array at `:17` — already two names stale. |
| `tests/storage/root-policy.ps1` | **new**: the five-state resolution table; marker mismatch → `foreign`; candidate classification against fixtures including a USB-`Fixed` row, a letterless row, a `Temp:` row, an nfs mount, `/boot/efi`, a `ro` mount and a file bind-mount; the `Letters` split and the `DiskNumber`/`DeviceId` key alignment (§2.4). |
| `tests/windows/scoop-root-resolution.ps1` | one more case: a root recorded only as `root_path`, with `$env:SCOOP` unset, still resolves. The never-write assertions stay. |
| `tests/linux/storage-root.ps1` | **new**: mountinfo parsing against a recorded fixture; the write probe; degradation with no `lsblk` and no `findmnt`. |
| `.github/workflows/release-validate-linux.yml` | rewrite the leftover gate at `:447-454` to read the root **from the manifest** rather than a literal path (§2.10); add an install-with-root → assert-data-lands-there → uninstall → assert-root-gone round trip. Write it as `run: \|` with **no** `${{ }}`, or `tests/gates.ps1` will neither collect it (`:57`) nor run it (`:97`). |

### Docs

`COMPONENTS.md` (new functions with the Platform column, plus the three storage functions
missing from the Linux header), `README.md` (state where Scoop goes; fix the stale "28 component
files" at `:389`), `docs/installation.md` (`:195-196`, `:325`, `:330`),
`docs/troubleshooting.md` (`:193`, `:241`, `:244`), `CHANGELOG.md` (dated, no leftover
`[Unreleased]` — `release-validate.yml:95-131` hard-fails otherwise),
`docs/release-checklist.md` (two new items: an install whose root differs from the default, and
cleaning the Linux staging root), `docs/feature-fix-and-improvements/README.md` (a tracked row —
there is none today).

Also while here: `Microsoft.PowerShell_profile.ps1:32` cites *"install.ps1's `#Requires -Version
5.1`"*; `install.ps1:1` says 7.0.

The owner's own placeholder, `docs/file system upgrade/scoop installation path.md`, stays empty.

---

## 7. Failure modes, answered

| Failure | What happens |
|---|---|
| **Declared root missing at shell start** | `Get-PowerFlowStorageRoot` returns `''` with state `missing`, `Get-PowerFlowDataPath` falls back to the platform default, and PowerFlow warns **once per session**. PowerFlow itself loads normally — that is the whole reason the tree does not move. Tools Scoop installed do not resolve until the drive returns; inherent to relocating a package root, which is why the move confirmation says so in plain words and why auto-selection never picks an external or removable volume. |
| **A different disk takes the same drive letter, or a mountpoint is not mounted** | The `.powerflow-root` GUID does not match `policy.id` → state `foreign` → fall back and warn. Without this check, Windows would write into a stranger's directory and Linux would write into the empty directory *under* the mountpoint, on the root filesystem, invisibly. |
| **Full disk** | The free-space floor is checked at selection time and `Test-StorageWritable` runs before any placement. Neither prevents the disk filling *later*: `storage root` reports headroom, and `pmx-audit.jsonl`'s catch (`components/proxmox/config.ps1:490`) downgrades a write failure to a `Write-Warning`, so auditing would stop **silently**. That is a real hole and is why OQ 2 exists. |
| **Removable or external drive** | Rejected from auto by `Get-DiskInfo.External` (Windows) or `lsblk TRAN=usb` (Linux). If the bus cannot be determined at all the candidate is `unknown` and never auto-selected. An explicit user choice is accepted after being told what could not be confirmed. |
| **Root-owned or read-only mount** | The create-and-delete probe fails, the candidate is rejected with a `Reason`, and — critically — the probe runs **before** any directory is created, so nothing dies mid-install after pwsh has already been placed in `/opt`. |
| **Partial migration of an existing Scoop** | Copy → repoint → `scoop reset *` → verify all five tools → **separately confirmed** reclaim. The source is never deleted before verification, so every stage is reversible, and the rollback command is printed in the failure message. |
| **Upgrading an existing install** | No policy file → nothing is proposed, nothing changes, `Get-PowerFlowDataPath` returns byte-for-byte what it returns today. A policy present → it is read and carried forward, never re-decided. `powerflow-update` is doubly guarded: the installer proposes only on a fresh box, and `version.ps1` passes the recorded root explicitly. |
| **Uninstall afterwards** | Manifest discovery is unchanged (`Split-Path $PROFILE -Parent`), so the conservative branch is never wrongly entered and both Windows test sandboxes keep working. `manifest.storageRoot` is read, the marker verified, `<root>/data` and the marker removed, `<root>` removed only if empty. Scoop is still **kept by default**, including under `-Yes` (`uninstall.ps1:121-133`) — but the summary now names the directory being left behind and its size, so *"PowerFlow is gone but 570 MB is still there"* is never a surprise. |
| **Uninstall when the root volume is absent** | Remove what is reachable, print the exact stranded path and the retry line, do **not** guess. Dependencies are left alone when the adapters needed to remove them live on the unreachable volume. |

---

## 8. This machine specifically

Measured today:

- The repo lives at `D:\Projects\Utils\powerflow`; the owner's hand-built D: layout is
  `DevTools\{ClaudeCode, CLI, Codex, Data, Runtimes}`, `Projects\`, `SteamLibrary\`.
- The **live PowerFlow install is entirely on C:** — `C:\Users\<user>\Documents\PowerShell`,
  1.67 MB, manifest v5.0.2 with `installRoot` recording the same path. Nothing of PowerFlow is on
  D:. Whatever "manually installed and set up this D drive" refers to, it is not a relocated
  PowerFlow.
- **Scoop is at `C:\Users\<user>\scoop`, 570 MB.** `SCOOP` and `SCOOP_GLOBAL` are empty at
  process, User **and** Machine scope. `~/.config/scoop/config.json` contains only `last_update`
  — no `root_path`. The C: root survives purely on Scoop's self-location fallback.
- `%LOCALAPPDATA%\PowerFlow` and `%APPDATA%\PowerFlow` **do not exist**. No feature that writes
  them has run.
- `D:` is Disk 1, internal NVMe, 844 GB free. `E:` is a USB WD My Passport that `Get-Volume`
  reports as `Fixed`.

**What the design does here: adopts, never overrides.**

The target is **positional** precisely so a hand-made layout wins. `storage root
D:\DevTools\PowerFlow` sits beside `ClaudeCode`, `CLI`, `Codex`, `Data` and `Runtimes` — the
owner's own convention, and three segments deep so `Test-ProtectedPath`'s depth rule does not
refuse it (§5.4). Nothing else on D: is read, moved or touched. The design must **not** impose
`D:\PowerFlow`.

Upgrading to the release carrying this feature changes nothing on disk. The machine gets
`Get-DiskHotspot` fixed to follow the real Scoop root, one Scoop resolver that also reads
`root_path`, and the `storage root` command. **Nothing moves.** `storage root` reports today's
reality and names the one command that would act.

Because PowerFlow's own data directories have never been created, declaring a root here moves
**zero bytes** of PowerFlow data — `<root>\data` is simply created empty. The 570 MB of Scoop is a
separate, explicitly-invoked `--adopt-packages` (§4.7), and the `scoop-backup-2026-08-19.json`
the owner already placed on `D:\` stays valid as their own belt and braces.

One adjacent thing, deliberately **out of scope**: `platform/windows/adapters/team-room.ps1`
already hardcodes a `D:\CodexData\teamchat-heartbeat` preference — the only drive preference in
the tree today. It is read-only and unrelated, and folding it in would widen the blast radius for
no gain.

---

## 9. Build order

Each increment is shippable on its own and leaves the tree correct. **Increments 0 and 4 are
decisions for the owner, not work.**

| # | Increment | Ships | Tests / gates it needs |
|---|---|---|---|
| **0** | **DECISION** — answer OQ 1-3 (naming, audit-log scope, Linux default). | nothing | — |
| 1 | **Commit the Scoop-path fix already in the working tree.** `config/paths.windows.ps1` + `tests/windows/scoop-root-resolution.ps1` + the `run.ps1` wiring. Nothing below should be built on an uncommitted base. | patch | `tests/windows/run.ps1`; a full gate run via `tests/gates.ps1` |
| 2 | **One Scoop resolver.** `Get-PackageManagerRoot` on both platforms (Linux `$null`), reading `root_path`. Rewire `packages.ps1:22-26`, `apps.ps1:175`, `apps.ps1:75` (guarded) and `config/paths.windows.ps1`. **Fixes a live bug** — `storage big` is blind to a relocated Scoop today. | patch | adapter parity gate; extend `tests/windows/scoop-root-resolution.ps1`; add the names to `tests/storage/volume-contracts.ps1:17` |
| 3 | **Candidate classification, read-only.** `Get-StorageCandidate` + `Test-StorageWritable` on both platforms. `storage root` **report only** — no policy, no writes, no relocation. This is the increment that proves the detection is right on real hardware before anything depends on it. | minor | new `tests/storage/root-policy.ps1`; new `tests/linux/storage-root.ps1`; flag-spelling and help-registry gates |
| **4** | **DECISION** — review increment 3's output on the owner's machine and on a Linux box. Does it pick D:? Does it reject E:? Only then proceed. | nothing | — |
| 5 | **Policy, marker and resolution.** `Get-PowerFlowStorageRoot`, `Set-PowerFlowStorageRoot`, the `Get-PowerFlowDataPath` derivation, `storage root <target>` / `off` / `--dry-run`, `Get-ProtectedPaths`. Still no installer change. | minor | resolution-table tests; a round trip that declares, reads back, and reverts |
| 6 | **Installer placement.** `-StorageRoot` / `--storage-root`, the adapter dot-source, the fresh-box-only guard, the manifest field, `version.ps1` passing the root through. | **major** — the install destination for new installs changes | new Linux CI round trip; rewrite the leftover gate to read the manifest; `tests/windows/install-prerequisite-roundtrip.ps1` must stay non-interactive under `-Yes` |
| 7 | **Uninstall and `-Purge`.** Marker verification, root removal, the missing user-data files, the power-state guard, the no-manifest branch reading the policy. | minor | Linux install → declare root → uninstall → assert **both** locations clean |
| 8 | **`--adopt-packages`.** Moving an existing Scoop. **Rehearse on a throwaway box first** — `scoop reset *` has never been exercised by this repo and has no dry-run. | minor | manual rehearsal; automated coverage is not realistic here and the docs should say so |
| 9 | **`prune`, `install-gui.sh`, the `install.sh` prefix cleanup, docs.** | patch | doc review; the release checklist's private-data grep |

Versioning: increment 6 changes the install destination for new installs, which is a **major**
bump under CLAUDE.md's rule, with `CHANGELOG.md` dated in the same commit.

**Privacy, before any of it lands.** `docs/release-checklist.md:85-91` records that v3.5.0
shipped the author's real username and server address across examples, CHANGELOG, README and the
commit message. A feature documented from one person's D: layout is exactly that class of
content. Every shipped example must use placeholders, and the staged diff and the release
description must both be grepped before the tag.

---

## 10. Open questions

Each needs one sentence from the owner.

1. **The command name.** `storage root` is recommended, but `Root` is already a property on
   `Get-StorageVolume` (the mount point) and on Linux `root` also means the superuser and `/`.
   Is `storage root` acceptable, or would `storage home` or `storage where` read better?

2. **Audit-log retention.** `pmx-audit.jsonl` is the one genuinely unbounded file PowerFlow
   writes and it is on by default; relocating it moves the problem rather than bounding it.
   Should size-capped rotation ship **inside** this release, or as its own item straight after?

3. **The Linux asymmetry.** Windows relocates by default on a fresh install; Linux detects and
   advises, because XDG already answers the question and there is no relocatable package root. Is
   advise-by-default acceptable on Linux, or should `--storage-root auto` relocate the data path
   there too?

4. **The free-space floor.** Proposed: 20 GB on Windows, 5 GB on Linux, with no percentage rule.
   Right numbers, or should it be a percentage of the volume?

5. **The piped install.** Under `irm | iex`, `-Yes` and CI there is no way to show a picker, so a
   machine with **two** eligible internal drives falls back to the system-drive layout and prints
   the re-run line rather than guessing. Is that the right call, or should the piped path pick the
   emptiest and say so?

6. **The Linux staging copy.** `install.sh`'s `PREFIX` is a permanent second full copy of the tree
   that uninstall never removes and CI never checks, and it collides with
   `Get-PowerFlowDataPath`. Should it become a `mktemp -d` in this release, or be tracked
   separately?

7. **`D:\DevTools\PowerFlow`, or somewhere else?** The design proposes adopting the existing
   `DevTools\` convention on this machine. Is that the right home, or should it be
   `D:\DevTools\Data\PowerFlow`, or somewhere else entirely?
