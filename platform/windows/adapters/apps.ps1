# ==============================================================================
# PowerFlow — Installed Applications Adapter (Windows)
# ==============================================================================
# Domain   : Platform / Windows
# File     : platform/windows/adapters/apps.ps1
# Purpose  : Enumerate installed applications with their real on-disk size,
#            uninstall them properly, and delete paths to the Recycle Bin
# Contract : Get-InstalledApplication, Uninstall-Application,
#            Move-ToTrash, Test-TrashSupport, Test-ProtectedPath,
#            Get-StorageVolume, Resolve-StorageVolume, Get-StorageNativeCommand
# Depends  : none
# ==============================================================================

Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue

# ──────────────────────────────────────────────────────────────────────────────
# Paths that must NEVER be deleted, no matter what the user picks.
#
# An app's *folder* is not the app. Deleting C:\Windows or Program Files because
# it showed up as "large" would destroy the machine, so the denylist is checked
# before any destructive action and cannot be overridden by a flag.
# ──────────────────────────────────────────────────────────────────────────────
function Get-ProtectedPaths {
    return @(
        $env:SystemRoot                                    # C:\Windows
        (Join-Path $env:SystemRoot 'System32')
        $env:ProgramFiles                                  # C:\Program Files (the root itself)
        ${env:ProgramFiles(x86)}
        (Join-Path $env:ProgramFiles 'WindowsApps')
        $env:ProgramData
        $env:SystemDrive + '\'                             # C:\
        $HOME
        (Split-Path $PROFILE -Parent)                      # PowerFlow's own install root
    ) | Where-Object { $_ }
}

# $true when the path IS a protected root (deleting it would be catastrophic).
# Deleting something *inside* Program Files is allowed; deleting Program Files is not.
function Test-ProtectedPath {
    param([Parameter(Mandatory)][string]$Path)

    $resolved = try { (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path.TrimEnd('\') }
                catch { $Path.TrimEnd('\') }

    foreach ($p in (Get-ProtectedPaths)) {
        if ($resolved -ieq $p.TrimEnd('\')) { return $true }
    }

    # Anything only 1 level below the drive root is too close to the bone.
    if ($resolved -match '^[A-Za-z]:\\[^\\]*$' -and $resolved -inotmatch '^[A-Za-z]:\\(Users|Temp)\\') {
        # e.g. C:\Windows, C:\PerfLogs — but allow C:\Users\... and deeper paths
        if (($resolved -split '\\').Count -le 2) { return $true }
    }

    return $false
}

# ──────────────────────────────────────────────────────────────────────────────
# Disk hot spots — where bulk actually accumulates.
#
# A full C:\ walk takes minutes and spends most of it inside C:\Windows, which is
# protected anyway. These are the roots where multi-GB folders and files really
# live. Note %LOCALAPPDATA%: Docker Desktop's WSL disk (docker_data.vhdx) sits
# there and can reach hundreds of GB — it is not an "installed app" and no
# registry enumeration will ever surface it.
# ──────────────────────────────────────────────────────────────────────────────
function Get-DiskHotspot {
    $roots = @(
        $env:LOCALAPPDATA                              # Docker/WSL vhdx, browser caches, app data
        $env:APPDATA
        $env:ProgramData
        $env:ProgramFiles
        ${env:ProgramFiles(x86)}
        $env:TEMP
        # Resolved, not assumed: a relocated Scoop is usually the single biggest
        # reclaimable directory on the machine, and hardcoding ~\scoop hid it entirely.
        (Get-PackageManagerRoot)
        (Join-Path $HOME 'Downloads')
        (Join-Path $HOME 'Videos')
        (Join-Path $HOME 'Documents')
        (Join-Path $HOME '.nuget')
        (Join-Path $HOME '.gradle')
        (Join-Path $HOME '.cargo')
        (Join-Path $HOME '.m2')
        (Join-Path $HOME '.docker')
        (Join-Path $HOME 'AppData\Local\Packages')     # Store apps / WSL distros
    )

    return @($roots | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)
}

# ──────────────────────────────────────────────────────────────────────────────
# Enumeration
# ──────────────────────────────────────────────────────────────────────────────
$script:PF_UninstallKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

# Measure a folder on disk. Slow, so only called when the registry has no size.
function Measure-FolderSize {
    param([string]$Path)

    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return 0 }
    try {
        return ((Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
                 Measure-Object -Property Length -Sum).Sum)
    } catch { return 0 }
}

# Return every installed application PowerFlow can see.
#
# -Measure walks each install folder for a true size. Without it we trust the
# registry's EstimatedSize, which is fast but frequently missing or wrong — so
# entries with no EstimatedSize are always measured regardless.
function Get-InstalledApplication {
    param([switch]$Measure)

    $apps = [System.Collections.Generic.List[object]]::new()

    # Collect first so we know the total and can report real progress. Measuring a
    # folder on disk is slow, so a scan of a machine with many apps takes a while and
    # must not look frozen.
    $entries = @()
    foreach ($key in $script:PF_UninstallKeys) {
        $entries += @(Get-ItemProperty $key -ErrorAction SilentlyContinue)
    }

    $total = [math]::Max($entries.Count, 1)
    $i     = 0

    foreach ($entry in $entries) {
        $i++
        Write-Progress -Activity "🔍 Scanning installed applications" `
                       -Status  "$i of $total — $($entry.DisplayName)" `
                       -PercentComplete ([math]::Min(($i / $total) * 100, 100))

        $name = $entry.DisplayName
        if (-not $name)                  { continue }
        if ($entry.SystemComponent -eq 1) { continue }   # hidden OS components
        if ($entry.ParentKeyName)         { continue }   # updates/patches of a parent app

        $location = $entry.InstallLocation
        $bytes    = 0

        if ($entry.EstimatedSize) { $bytes = [int64]$entry.EstimatedSize * 1KB }
        if ($Measure -or $bytes -eq 0) {
            $measured = Measure-FolderSize $location
            if ($measured -gt 0) { $bytes = $measured }
        }

        # The registry's InstallDate is a YYYYMMDD string and is frequently missing,
        # so fall back to the install folder's creation time.
        $installed = $null
        if ($entry.InstallDate -and "$($entry.InstallDate)" -match '^(\d{4})(\d{2})(\d{2})$') {
            try { $installed = [datetime]::new([int]$matches[1], [int]$matches[2], [int]$matches[3]) } catch { }
        }
        if (-not $installed -and $location -and (Test-Path -LiteralPath $location)) {
            try { $installed = (Get-Item -LiteralPath $location -Force).CreationTime } catch { }
        }

        $apps.Add([pscustomobject]@{
            Name            = $name
            Version         = $entry.DisplayVersion
            Publisher       = $entry.Publisher
            SizeBytes       = [int64]$bytes
            InstallDate     = $installed
            InstallLocation = $location
            UninstallString = if ($entry.QuietUninstallString) { $entry.QuietUninstallString } else { $entry.UninstallString }
            Source          = 'registry'
            Id              = $entry.PSChildName
        })
    }

    # Scoop apps live outside the registry entirely — invisible to Add/Remove Programs.
    # Through the resolver, never $env:SCOOP directly: a Scoop relocated with -ScoopDir
    # records root_path and sets no variable, and this listing went blank because of it.
    $scoopApps = Join-Path (Get-PackageManagerRoot) 'apps'
    if (Test-Path $scoopApps) {
        $scoopDirs = @(Get-ChildItem $scoopApps -Directory -ErrorAction SilentlyContinue)
        $j = 0
        foreach ($d in $scoopDirs) {
            $j++
            Write-Progress -Activity "🔍 Scanning installed applications" `
                           -Status  "scoop: $($d.Name)" `
                           -PercentComplete ([math]::Min(($j / [math]::Max($scoopDirs.Count,1)) * 100, 100))

            $apps.Add([pscustomobject]@{
                Name            = $d.Name
                Version         = 'scoop'
                Publisher       = 'Scoop'
                SizeBytes       = [int64](Measure-FolderSize $d.FullName)
                InstallDate     = $d.CreationTime
                InstallLocation = $d.FullName
                UninstallString = $null
                Source          = 'scoop'
                Id              = $d.Name
            })
        }
    }

    Write-Progress -Activity "🔍 Scanning installed applications" -Completed
    return $apps
}

# ──────────────────────────────────────────────────────────────────────────────
# Uninstall — always via the app's own uninstaller, never by deleting its folder
# ──────────────────────────────────────────────────────────────────────────────
function Uninstall-Application {
    param([Parameter(Mandatory)]$App)

    switch ($App.Source) {
        'scoop' {
            if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) { return $false }
            scoop uninstall $App.Id
            return (-not (Test-Path $App.InstallLocation))
        }
        default {
            if (-not $App.UninstallString) {
                Write-Host "❌ No uninstaller registered for '$($App.Name)'." -ForegroundColor Red
                return $false
            }

            # UninstallString is a raw command line: either "path\to.exe" /args, or
            # MsiExec.exe /X{GUID}. Split the executable from its arguments.
            $cmd = $App.UninstallString.Trim()
            if ($cmd -match '^"([^"]+)"\s*(.*)$') {
                $exe = $matches[1]; $argline = $matches[2]
            } elseif ($cmd -match '^(\S+)\s*(.*)$') {
                $exe = $matches[1]; $argline = $matches[2]
            } else {
                return $false
            }

            try {
                if ($argline) { Start-Process -FilePath $exe -ArgumentList $argline -Wait }
                else          { Start-Process -FilePath $exe -Wait }
                return $true
            } catch {
                Write-Host "❌ Uninstaller failed: $($_.Exception.Message)" -ForegroundColor Red
                return $false
            }
        }
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# Deletion
# ──────────────────────────────────────────────────────────────────────────────
function Test-TrashSupport { return $true }

# Send to the Recycle Bin so a mistake is recoverable.
function Move-ToTrash {
    param([Parameter(Mandatory)][string]$Path)

    if (Test-ProtectedPath $Path) {
        Write-Host "🛑 Refusing to delete a protected system path: $Path" -ForegroundColor Red
        return $false
    }

    try {
        if (Test-Path -LiteralPath $Path -PathType Container) {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
                $Path, 'OnlyErrorDialogs', 'SendToRecycleBin')
        } else {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                $Path, 'OnlyErrorDialogs', 'SendToRecycleBin')
        }
        return (-not (Test-Path -LiteralPath $Path))
    } catch {
        Write-Host "❌ Could not send to Recycle Bin: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Permanent, unrecoverable delete. The caller must have confirmed.
function Remove-PathPermanently {
    param([Parameter(Mandatory)][string]$Path)

    if (Test-ProtectedPath $Path) {
        Write-Host "🛑 Refusing to delete a protected system path: $Path" -ForegroundColor Red
        return $false
    }

    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        return $true
    } catch {
        Write-Host "❌ Delete failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

<#
.SYNOPSIS
    Every real storage volume on this machine, with size and free space.
.DESCRIPTION
    This is the piece that was missing. Get-DiskHotspot only ever returned locations on the
    SYSTEM drive ($env:LOCALAPPDATA, $env:ProgramFiles, $HOME\...), so on a machine with data
    drives the bare command was blind to them — it could not answer "which drive is full",
    which is the first question anyone asks.

    Get-Volume is preferred because it sees volumes that have no drive letter (a mounted
    folder, a recovery partition), which Get-PSDrive cannot. Get-PSDrive is the fallback for
    hosts where the Storage module is unavailable.

    Only FIXED and REMOVABLE volumes are returned. Network drives are someone else's disk and
    walking one is slow enough to look like a hang; CD-ROMs are not actionable.
#>
function Get-StorageVolume {
    $volumes = @()

    try {
        foreach ($vol in (Get-Volume -ErrorAction Stop)) {
            if ($vol.DriveType -notin @('Fixed', 'Removable')) { continue }
            # A volume with no letter and no access path cannot be walked, so it is not
            # actionable and would only pad the table.
            $root = if ($vol.DriveLetter) { "$($vol.DriveLetter):\" } else { '' }
            if (-not $root) { continue }
            $volumes += [pscustomobject]@{
                Name       = "$($vol.DriveLetter):"
                Root       = $root
                Label      = "$($vol.FileSystemLabel)"
                FileSystem = "$($vol.FileSystem)"
                SizeBytes  = [int64]$vol.Size
                FreeBytes  = [int64]$vol.SizeRemaining
                IsSystem   = ($root -eq "$($env:SystemDrive)\")
                DriveType  = "$($vol.DriveType)"
            }
        }
    } catch {
        # Fallback: Get-PSDrive is always present but only sees lettered filesystem drives.
        foreach ($drive in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
            if ($null -eq $drive.Used -and $null -eq $drive.Free) { continue }
            $size = [int64]($drive.Used) + [int64]($drive.Free)
            if ($size -le 0) { continue }
            $volumes += [pscustomobject]@{
                Name       = "$($drive.Name):"
                Root       = "$($drive.Name):\"
                Label      = ''
                FileSystem = ''
                SizeBytes  = $size
                FreeBytes  = [int64]$drive.Free
                IsSystem   = ("$($drive.Name):\" -eq "$($env:SystemDrive)\")
                DriveType  = 'Fixed'
            }
        }
    }

    return @($volumes | Sort-Object -Property @{ Expression = 'IsSystem'; Descending = $true }, Name)
}

<#
.SYNOPSIS
    Resolve a user-typed volume selector to a volume, or $null.
.DESCRIPTION
    Accepts what a Windows user would actually type for the D: drive: "D", "d", "D:", "D:\",
    and the filesystem label. Kept in the adapter because "what a volume is called" is exactly
    the platform-specific knowledge a component must not hold — the Linux adapter resolves
    mount points through the same contract.
#>
function Resolve-StorageVolume {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Selector, [object[]]$Volumes)

    if (-not $Selector) { return $null }
    if (-not $Volumes) { $Volumes = @(Get-StorageVolume) }

    $wanted = $Selector.Trim().TrimEnd('\', '/')
    # ${} is load-bearing: "$wanted:" parses as a SCOPE qualifier (the $env:PATH form), not
    # as the variable followed by a colon, and fails to parse at all.
    if (-not $wanted.EndsWith(':') -and $wanted.Length -eq 1) { $wanted = "${wanted}:" }

    $hit = @($Volumes | Where-Object { $_.Name -ieq $wanted })
    if (-not $hit.Count) { $hit = @($Volumes | Where-Object { $_.Root -ieq $Selector }) }
    if (-not $hit.Count) { $hit = @($Volumes | Where-Object { $_.Label -and $_.Label -ieq $Selector }) }
    if ($hit.Count) { return $hit[0] }
    return $null
}

<#
.SYNOPSIS
    The real OS command behind a storage operation, for --show-native.
.DESCRIPTION
    The component must not know which OS it is on, so it cannot hold these strings itself —
    that is the whole point of the adapter layer. `dkr` solves the same problem by returning a
    .Native field from its adapter; this is the same idea for storage.
#>
<#
.SYNOPSIS
    Development directories sitting on the SYSTEM drive, and what would move each one.
.DESCRIPTION
    The knowledge here is irreducibly per-OS — %APPDATA%, %LOCALAPPDATA% and the dot-folder
    conventions have no Linux counterpart — which is the whole reason this lives in an
    adapter rather than in a component.

    A JUNCTIONED PATH IS NOT A STRAGGLER. Relocating an editor's data and leaving a junction
    behind is a legitimate and often the only workable answer: the flags an application
    offers usually cover only the launches you control, while a junction is resolved by the
    filesystem for every launch route. Such a path still EXISTS on the system drive and
    still measures the same size through the link, so a naive scan reports it as unmoved
    when it is exactly the opposite. Each row therefore carries Redirected, and the caller
    is expected to say so rather than nag about work already done.

    Size is measured through Measure-FolderSize rather than a second walk of its own, so a
    row here and a row in the disk-hotspot view can never disagree about how big something is.
#>
function Get-StorageStraggler {
    $systemRoot = "$env:SystemDrive\"

    $known = @(
        @{ Name = 'VS Code extensions'; Path = (Join-Path $HOME '.vscode\extensions');              Var = '' }
        @{ Name = 'VS Code user data';  Path = (Join-Path $env:APPDATA 'Code');                     Var = '' }
        @{ Name = 'Scoop';              Path = (Join-Path $HOME 'scoop');                           Var = 'SCOOP' }
        @{ Name = 'npm global prefix';  Path = (Join-Path $env:APPDATA 'npm');                      Var = 'NPM_CONFIG_PREFIX' }
        @{ Name = 'npm cache';          Path = (Join-Path $HOME '.npm');                            Var = 'NPM_CONFIG_CACHE' }
        @{ Name = 'pnpm';               Path = (Join-Path $env:LOCALAPPDATA 'pnpm');                Var = 'PNPM_HOME' }
        @{ Name = 'Yarn cache';         Path = (Join-Path $env:LOCALAPPDATA 'Yarn\Cache');          Var = 'YARN_CACHE_FOLDER' }
        @{ Name = 'NuGet packages';     Path = (Join-Path $HOME '.nuget');                          Var = 'NUGET_PACKAGES' }
        @{ Name = 'Gradle';             Path = (Join-Path $HOME '.gradle');                         Var = 'GRADLE_USER_HOME' }
        @{ Name = 'Maven';              Path = (Join-Path $HOME '.m2');                             Var = '' }
        @{ Name = 'Cargo';              Path = (Join-Path $HOME '.cargo');                          Var = 'CARGO_HOME' }
        @{ Name = 'Rustup';             Path = (Join-Path $HOME '.rustup');                         Var = 'RUSTUP_HOME' }
        @{ Name = 'Go workspace';       Path = (Join-Path $HOME 'go');                              Var = 'GOPATH' }
        @{ Name = 'pip cache';          Path = (Join-Path $env:LOCALAPPDATA 'pip\Cache');           Var = 'PIP_CACHE_DIR' }
        @{ Name = 'Android SDK';        Path = (Join-Path $env:LOCALAPPDATA 'Android\Sdk');         Var = 'ANDROID_SDK_ROOT' }
        @{ Name = 'Android user data';  Path = (Join-Path $HOME '.android');                        Var = 'ANDROID_USER_HOME' }
        @{ Name = 'container store';    Path = (Join-Path $HOME '.local\share\containers');         Var = '' }
        @{ Name = 'Docker config';      Path = (Join-Path $HOME '.docker');                         Var = 'DOCKER_CONFIG' }
        @{ Name = 'temp';               Path = (Join-Path $env:LOCALAPPDATA 'Temp');                Var = 'TEMP' }
    )

    $out = @()
    foreach ($entry in $known) {
        $path = "$($entry.Path)"
        if (-not $path -or -not (Test-Path -LiteralPath $path)) { continue }
        # Only report what is actually ON the system drive. A machine whose profile already
        # lives elsewhere has nothing to answer for.
        if (-not $path.StartsWith($systemRoot, [StringComparison]::OrdinalIgnoreCase)) { continue }

        $redirected = $false
        try { $redirected = [bool]((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) } catch { }

        $target = ''
        if ($entry.Var) { $target = "$([Environment]::GetEnvironmentVariable($entry.Var, 'User'))" }

        $out += [pscustomobject]@{
            Name       = $entry.Name
            Path       = $path
            SizeBytes  = [int64](Measure-FolderSize $path)
            Variable   = "$($entry.Var)"
            Redirect   = $target
            Redirected = $redirected
        }
    }
    return @($out | Sort-Object -Property @{ Expression = 'Redirected' }, @{ Expression = 'SizeBytes'; Descending = $true })
}

function Get-StorageNativeCommand {
    param(
        [Parameter(Mandatory)][ValidateSet('list', 'measure')][string]$Operation,
        [string]$Root = ''
    )
    switch ($Operation) {
        'list'    { return 'Get-Volume | Where-Object DriveType -in Fixed,Removable' }
        'measure' { return "Get-ChildItem -LiteralPath '$Root' -Force | ForEach-Object { measure its size }" }
    }
    return ''
}

# ── PF-FEAT-006: memory, swap, and the partition layout ───────────────────────
# The Linux sibling answers "how is this box laid out, and is it under pressure?" from
# /proc. Windows has no /proc, so the same two questions are answered through CIM — and
# the shapes returned here are IDENTICAL, because the renderer in components/ must not
# know which platform produced them.
#
# Read-only throughout, and no elevation: a diagnostic that prompts for admin is one people
# stop running.

<#
.SYNOPSIS
    Memory and the pagefile — the Windows answer to `free` and `swapon --show`.
.DESCRIPTION
    Windows reports FreePhysicalMemory but has no direct MemAvailable equivalent, so
    "available" is reported as free plus the standby/cache set where that is obtainable, and
    falls back to free otherwise. Labelled "pagefile" rather than "swap" because that is what
    a Windows user will search for, while the field names stay shared.
#>
function Get-StorageMemory {
    $total = 0; $free = 0; $cache = 0
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $total = [int64]$os.TotalVisibleMemorySize * 1KB
        $free  = [int64]$os.FreePhysicalMemory * 1KB
    } catch { }

    try {
        $perf = Get-CimInstance Win32_PerfRawData_PerfOS_Memory -ErrorAction Stop
        if ($perf.StandbyCacheNormalPriorityBytes) {
            $cache = [int64]$perf.StandbyCacheNormalPriorityBytes +
                     [int64]$perf.StandbyCacheReserveBytes +
                     [int64]$perf.StandbyCacheCoreBytes
        }
    } catch { }

    $areas = @()
    $swapTotal = 0; $swapUsed = 0
    try {
        foreach ($pf in @(Get-CimInstance Win32_PageFileUsage -ErrorAction Stop)) {
            $size = [int64]$pf.AllocatedBaseSize * 1MB
            $used = [int64]$pf.CurrentUsage * 1MB
            $swapTotal += $size
            $swapUsed  += $used
            $areas += [pscustomobject]@{
                Name      = $pf.Name
                Type      = 'file'
                SizeBytes = $size
                UsedBytes = $used
                Priority  = ''
            }
        }
    } catch { }

    return [pscustomobject]@{
        Supported      = ($total -gt 0)
        TotalBytes     = $total
        FreeBytes      = $free
        AvailableBytes = ($free + $cache)
        CacheBytes     = $cache
        UsedBytes      = ($total - $free - $cache)
        SwapTotalBytes = $swapTotal
        SwapUsedBytes  = $swapUsed
        SwapAreas      = $areas
        SwapLabel      = 'pagefile'
    }
}

<#
.SYNOPSIS
    The disk and partition tree — the Windows answer to `lsblk`.
.DESCRIPTION
    Get-Disk/Get-Partition come from the Storage module, which is present on every supported
    Windows but can be absent in a stripped image; an unsupported result says so rather than
    returning a half-built tree, matching how the Linux side handles a missing lsblk.
#>
function Get-StorageLayout {
    if (-not (Get-Command Get-Disk -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ Supported = $false; Devices = @(); Reason = 'the Storage module is not available' }
    }

    $devices = @()
    try {
        foreach ($disk in @(Get-Disk -ErrorAction Stop | Sort-Object Number)) {
            $children = @()
            # Same @($null) guard as the Linux sibling: a disk with no partitions must render
            # no child rows, not one blank one.
            foreach ($part in @(Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue | Where-Object { $_ })) {
                $vol = $null
                try { $vol = Get-Volume -Partition $part -ErrorAction SilentlyContinue } catch { }
                $children += [pscustomobject]@{
                    Name       = "Partition $($part.PartitionNumber)"
                    SizeBytes  = [int64]$part.Size
                    Type       = 'part'
                    FsType     = if ($vol) { $vol.FileSystemType } else { '' }
                    MountPoint = if ($part.DriveLetter) { "$($part.DriveLetter):" } else { '' }
                }
            }
            $devices += [pscustomobject]@{
                Name       = if ($disk.FriendlyName) { $disk.FriendlyName } else { "Disk $($disk.Number)" }
                SizeBytes  = [int64]$disk.Size
                Type       = 'disk'
                FsType     = ''
                MountPoint = ''
                Partitions = $children
            }
        }
    }
    catch {
        return [pscustomobject]@{ Supported = $false; Devices = @(); Reason = 'the disk layout could not be read' }
    }

    return [pscustomobject]@{ Supported = $true; Devices = $devices; Reason = '' }
}
