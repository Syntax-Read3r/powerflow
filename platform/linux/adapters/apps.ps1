# ==============================================================================
# PowerFlow — Installed Applications Adapter (Linux)
# ==============================================================================
# Domain   : Platform / Linux
# File     : platform/linux/adapters/apps.ps1
# Purpose  : Enumerate installed packages with their on-disk size, uninstall them
#            properly, and delete paths to the trash
# Contract : Get-InstalledApplication, Uninstall-Application,
#            Move-ToTrash, Remove-PathPermanently, Test-TrashSupport, Test-ProtectedPath
# Depends  : Get-PackageManagerName (packages.ps1)
# ==============================================================================

# ──────────────────────────────────────────────────────────────────────────────
# Paths that must NEVER be deleted. Removing /usr or /etc bricks the system, so
# this is checked before any destructive action and cannot be overridden.
# ──────────────────────────────────────────────────────────────────────────────
function Get-ProtectedPaths {
    return @(
        '/', '/usr', '/bin', '/sbin', '/lib', '/lib64', '/etc', '/boot',
        '/var', '/opt', '/root', '/home', '/proc', '/sys', '/dev', '/run',
        '/opt/microsoft', '/opt/microsoft/powershell',
        $HOME
    )
}

function Test-ProtectedPath {
    param([Parameter(Mandatory)][string]$Path)

    $resolved = $Path.TrimEnd('/')
    if (-not $resolved) { return $true }        # '/' collapses to empty

    foreach ($p in (Get-ProtectedPaths)) {
        if ($resolved -eq $p.TrimEnd('/')) { return $true }
    }
    return $false
}

function Measure-FolderSize {
    param([string]$Path)

    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return 0 }
    try {
        return ((Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
                 Measure-Object -Property Length -Sum).Sum)
    } catch { return 0 }
}

# ──────────────────────────────────────────────────────────────────────────────
# Disk hot spots — where bulk actually accumulates.
#
# Scanning / from the root is slow and pointless (most of it is protected). These
# are the roots where multi-GB folders really live. /var/lib/docker is the Linux
# equivalent of the Docker VHDX on Windows and is very often the biggest thing
# on the machine.
# ──────────────────────────────────────────────────────────────────────────────
function Get-DiskHotspot {
    $roots = @(
        "$HOME/.cache"
        "$HOME/.local/share"
        "$HOME/.config"
        "$HOME/Downloads"
        "$HOME/.nvm"
        "$HOME/.cargo"
        "$HOME/.m2"
        "$HOME/.gradle"
        "$HOME/.docker"
        '/var/lib/docker'          # images, containers, volumes
        '/var/lib/containers'      # podman
        '/var/log'
        '/var/cache'
        '/snap'
        '/opt'
        '/tmp'
    )

    return @($roots | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)
}

# ──────────────────────────────────────────────────────────────────────────────
# Enumeration — the package manager already knows every package's installed size,
# so no filesystem walk is needed (unlike Windows).
# ──────────────────────────────────────────────────────────────────────────────
function Get-InstalledApplication {
    param([switch]$Measure)

    $apps = [System.Collections.Generic.List[object]]::new()

    switch (Get-PackageManagerName) {
        'apt' {
            # dpkg records no install date anywhere. The mtime of the package's file
            # manifest (/var/lib/dpkg/info/<pkg>.list) is written when the package is
            # unpacked, which makes it a reliable proxy.
            $lines = dpkg-query -W -f='${Package}\t${Version}\t${Installed-Size}\t${Maintainer}\n' 2>/dev/null
            foreach ($l in $lines) {
                $p = $l -split "`t"
                if ($p.Count -lt 3) { continue }

                $installed = $null
                foreach ($cand in @("/var/lib/dpkg/info/$($p[0]).list",
                                    "/var/lib/dpkg/info/$($p[0]):amd64.list",
                                    "/var/lib/dpkg/info/$($p[0]):arm64.list")) {
                    if (Test-Path -LiteralPath $cand) {
                        try { $installed = (Get-Item -LiteralPath $cand).LastWriteTime } catch { }
                        break
                    }
                }

                $apps.Add([pscustomobject]@{
                    Name            = $p[0]
                    Version         = $p[1]
                    Publisher       = if ($p.Count -ge 4) { $p[3] } else { '' }
                    SizeBytes       = [int64]($p[2] -as [int64]) * 1KB
                    InstallDate     = $installed
                    InstallLocation = $null
                    UninstallString = $null
                    Source          = 'apt'
                    Id              = $p[0]
                })
            }
        }
        { $_ -in 'dnf', 'zypper' } {
            # rpm knows exactly when it installed something: SIZE in bytes, INSTALLTIME
            # as a unix epoch.
            $lines = rpm -qa --queryformat '%{NAME}\t%{VERSION}\t%{SIZE}\t%{INSTALLTIME}\t%{VENDOR}\n' 2>/dev/null
            foreach ($l in $lines) {
                $p = $l -split "`t"
                if ($p.Count -lt 3) { continue }

                $installed = $null
                if ($p.Count -ge 4 -and ($p[3] -as [int64])) {
                    try { $installed = [datetimeoffset]::FromUnixTimeSeconds([int64]$p[3]).LocalDateTime } catch { }
                }

                $apps.Add([pscustomobject]@{
                    Name            = $p[0]
                    Version         = $p[1]
                    Publisher       = if ($p.Count -ge 5) { $p[4] } else { '' }
                    SizeBytes       = [int64]($p[2] -as [int64])
                    InstallDate     = $installed
                    InstallLocation = $null
                    UninstallString = $null
                    Source          = (Get-PackageManagerName)
                    Id              = $p[0]
                })
            }
        }
        'pacman' {
            # "Installed Size : 12.34 MiB" / "Install Date : Mon 01 Jan 2024 ..."
            $current = $null
            foreach ($l in (pacman -Qi 2>/dev/null)) {
                if     ($l -match '^Name\s+:\s+(.+)$')                     { $current = @{ Name = $matches[1].Trim() } }
                elseif ($l -match '^Version\s+:\s+(.+)$' -and $current)     { $current.Version = $matches[1].Trim() }
                elseif ($l -match '^Install Date\s+:\s+(.+)$' -and $current) {
                    try { $current.Installed = [datetime]::Parse($matches[1].Trim()) } catch { }
                }
                elseif ($l -match '^Installed Size\s+:\s+([\d.]+)\s+(\w+)' -and $current) {
                    $val  = [double]$matches[1]
                    $unit = $matches[2]
                    $mult = switch -Regex ($unit) {
                        '^B'   { 1 }; '^KiB' { 1KB }; '^MiB' { 1MB }; '^GiB' { 1GB }; default { 1 }
                    }
                    $apps.Add([pscustomobject]@{
                        Name            = $current.Name
                        Version         = $current.Version
                        Publisher       = 'pacman'
                        SizeBytes       = [int64]($val * $mult)
                        InstallDate     = $current.Installed
                        InstallLocation = $null
                        UninstallString = $null
                        Source          = 'pacman'
                        Id              = $current.Name
                    })
                    $current = $null
                }
            }
        }
    }

    return $apps
}

function Uninstall-Application {
    param([Parameter(Mandatory)]$App)

    # Remove-SinglePackage lives in packages.ps1 and already handles sudo correctly.
    return (Remove-SinglePackage $App.Id)
}

# ──────────────────────────────────────────────────────────────────────────────
# Deletion
# ──────────────────────────────────────────────────────────────────────────────
function Test-TrashSupport {
    return [bool](Get-Command gio -ErrorAction SilentlyContinue)
}

function Move-ToTrash {
    param([Parameter(Mandatory)][string]$Path)

    if (Test-ProtectedPath $Path) {
        Write-Host "🛑 Refusing to delete a protected system path: $Path" -ForegroundColor Red
        return $false
    }

    if (-not (Test-TrashSupport)) {
        Write-Host "⚠️  No trash support (gio not found) — use a permanent delete instead." -ForegroundColor Yellow
        return $false
    }

    gio trash "$Path" 2>$null
    return (-not (Test-Path -LiteralPath $Path))
}

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
    Every real storage mount on this machine, with size and free space.
.DESCRIPTION
    This is the piece that was missing. Get-DiskHotspot only ever returned paths on the root
    filesystem (/var/lib/docker, /snap, /var/log), so a data mount under /mnt or /srv was
    invisible to the bare command — it could not answer "which mount is full".

    The filter is the whole job here. An unfiltered mount list on a modern Linux desktop is
    almost entirely noise: one squashfs loop per installed snap (often dozens), a tmpfs per
    user session, plus proc/sysfs/cgroup/devtmpfs pseudo-filesystems. Reporting those as
    "storage" would bury the two mounts anyone cares about.

    findmnt is preferred because it reports the filesystem type and target directly as JSON.
    df is the fallback: present everywhere, but its output has to be parsed positionally.
#>
$script:PF_PseudoFilesystems = @(
    'proc', 'sysfs', 'devtmpfs', 'devpts', 'tmpfs', 'ramfs', 'securityfs', 'cgroup', 'cgroup2',
    'pstore', 'efivarfs', 'bpf', 'debugfs', 'tracefs', 'hugetlbfs', 'mqueue', 'configfs',
    'fusectl', 'squashfs', 'overlay', 'autofs', 'binfmt_misc', 'rpc_pipefs', 'nsfs', 'fuse.gvfsd-fuse',
    'fuse.portal', 'nfsd', 'selinuxfs'
)

# Parsing is kept SEPARATE from detection on purpose. `Get-Command -CommandType Application`
# is the right guard in production — it must find the real binary, not some function that
# happens to share the name — but it also means the detection cannot be shimmed, which would
# leave this parser untestable on any host without findmnt. Splitting it lets the real parsing
# body be exercised against a recorded fixture.
function ConvertFrom-PFFindmntJson {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Json)

    $raw = "$Json".Trim()
    if (-not $raw -or $raw[0] -ne '{') { return @() }
    try { $parsed = $raw | ConvertFrom-Json } catch { return @() }
    return @($parsed.filesystems | ForEach-Object {
        [pscustomobject]@{ Target = "$($_.target)"; Source = "$($_.source)"
            FsType = "$($_.fstype)"; SizeText = "$($_.size)"; AvailText = "$($_.avail)" }
    })
}

function Get-StorageMountCandidate {
    # findmnt -J gives type and target without positional parsing, and -l flattens the tree
    # so nothing is missed inside a nested mount.
    if (Get-Command findmnt -CommandType Application -ErrorAction SilentlyContinue) {
        try {
            return @(ConvertFrom-PFFindmntJson ((& findmnt -J -l -o TARGET,SOURCE,FSTYPE,SIZE,AVAIL 2>$null | Out-String)))
        } catch { }
    }
    return @()
}

function Get-StorageVolume {
    $out = @()
    $seen = @{}

    foreach ($cand in (Get-StorageMountCandidate)) {
        if (-not $cand.Target) { continue }
        $fsType = "$($cand.FsType)".ToLowerInvariant()
        if ($fsType -in $script:PF_PseudoFilesystems) { continue }
        # A bind mount reports the same device twice; the first (shortest) target is the real one.
        if ($seen.ContainsKey($cand.Target)) { continue }
        $seen[$cand.Target] = $true

        # findmnt renders sizes human-readable ("1.8T"); PowerShell needs the bytes. Getting
        # them from .NET avoids a second parse of a localised suffix.
        $size = 0; $free = 0
        try {
            $info = [System.IO.DriveInfo]::new($cand.Target)
            $size = [int64]$info.TotalSize; $free = [int64]$info.AvailableFreeSpace
        } catch { }
        if ($size -le 0) { continue }

        $out += [pscustomobject]@{
            Name       = "$($cand.Target)"
            Root       = "$($cand.Target)"
            Label      = "$($cand.Source)"
            FileSystem = $fsType
            SizeBytes  = $size
            FreeBytes  = $free
            IsSystem   = ("$($cand.Target)" -eq '/')
            DriveType  = 'Fixed'
        }
    }

    if (-not $out.Count) {
        # Last resort: .NET enumerates ready drives without needing findmnt at all.
        foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
            try {
                if (-not $drive.IsReady) { continue }
                $fsType = "$($drive.DriveFormat)".ToLowerInvariant()
                if ($fsType -in $script:PF_PseudoFilesystems) { continue }
                if ([int64]$drive.TotalSize -le 0) { continue }
                $out += [pscustomobject]@{
                    Name       = "$($drive.Name)"
                    Root       = "$($drive.Name)"
                    Label      = "$($drive.VolumeLabel)"
                    FileSystem = $fsType
                    SizeBytes  = [int64]$drive.TotalSize
                    FreeBytes  = [int64]$drive.AvailableFreeSpace
                    IsSystem   = ("$($drive.Name)" -eq '/')
                    DriveType  = 'Fixed'
                }
            } catch { }
        }
    }

    return @($out | Sort-Object -Property @{ Expression = 'IsSystem'; Descending = $true }, Name)
}

<#
.SYNOPSIS
    Resolve a user-typed mount selector to a volume, or $null.
.DESCRIPTION
    Accepts a mount point ("/srv", "/mnt/data/"), a device ("/dev/sdb1"), or the trailing
    directory name ("data" for /mnt/data) — that last one matters because it is what someone
    types when they cannot remember the full path. Kept in the adapter because "what a volume
    is called" is the platform-specific knowledge a component must not hold.
#>
function Resolve-StorageVolume {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Selector, [object[]]$Volumes)

    if (-not $Selector) { return $null }
    if (-not $Volumes) { $Volumes = @(Get-StorageVolume) }

    $wanted = $Selector.Trim()
    if ($wanted.Length -gt 1) { $wanted = $wanted.TrimEnd('/') }

    $hit = @($Volumes | Where-Object { $_.Name -ceq $wanted })
    if (-not $hit.Count) { $hit = @($Volumes | Where-Object { $_.Name -ieq $wanted }) }
    if (-not $hit.Count) { $hit = @($Volumes | Where-Object { $_.Label -and $_.Label -ieq $wanted }) }
    if (-not $hit.Count) { $hit = @($Volumes | Where-Object { (Split-Path $_.Name -Leaf) -ieq $wanted }) }
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
function Get-StorageNativeCommand {
    param(
        [Parameter(Mandatory)][ValidateSet('list', 'measure')][string]$Operation,
        [string]$Root = ''
    )
    switch ($Operation) {
        'list'    { return 'findmnt -J -l -o TARGET,SOURCE,FSTYPE,SIZE,AVAIL' }
        'measure' { return "du -sh '$Root'/* 2>/dev/null | sort -h" }
    }
    return ''
}
