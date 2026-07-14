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
