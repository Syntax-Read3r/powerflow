# ==============================================================================
# PowerFlow — Packages Adapter (Linux)
# ==============================================================================
# Domain   : Platform / Linux
# File     : platform/linux/adapters/packages.ps1
# Purpose  : Install and query PowerFlow's tool dependencies via the distro's
#            native package manager (apt / dnf / pacman / zypper / apk)
# Contract : Get-PackageManagerName, Test-PackageManager, Install-PackageManager,
#            Test-Dependency, Install-Dependency, Uninstall-Dependency,
#            Get-DependencyInstallHint
# Depends  : none
# ==============================================================================

# Detect the distro's package manager once, then cache it.
function Get-PackageManagerName {
    if ($script:PF_PackageManager) { return $script:PF_PackageManager }

    $script:PF_PackageManager =
        if     (Get-Command apt-get -ErrorAction SilentlyContinue) { 'apt' }
        elseif (Get-Command dnf     -ErrorAction SilentlyContinue) { 'dnf' }
        elseif (Get-Command pacman  -ErrorAction SilentlyContinue) { 'pacman' }
        elseif (Get-Command zypper  -ErrorAction SilentlyContinue) { 'zypper' }
        elseif (Get-Command apk     -ErrorAction SilentlyContinue) { 'apk' }
        else                                                        { 'none' }

    return $script:PF_PackageManager
}

function Test-PackageManager {
    return ((Get-PackageManagerName) -ne 'none')
}

# The distro package manager always exists — nothing to bootstrap, unlike Scoop.
function Install-PackageManager {
    return (Test-PackageManager)
}

# PowerFlow tool name -> distro package name. Only exceptions are listed.
$script:PF_PackageNameMap = @{
    'apt'    = @{ 'bat' = 'bat' }
    'dnf'    = @{ }
    'pacman' = @{ }
    'zypper' = @{ }
    'apk'    = @{ }
}

# PowerFlow tool name -> the binary it actually installs as.
# Debian/Ubuntu ship bat as `batcat` to avoid a name clash.
$script:PF_BinaryNameMap = @{
    'apt' = @{ 'bat' = 'batcat' }
}

function Resolve-PackageName {
    param([Parameter(Mandatory)][string]$Name)
    $mgr = Get-PackageManagerName
    $map = $script:PF_PackageNameMap[$mgr]
    if ($map -and $map.ContainsKey($Name)) { return $map[$Name] }
    return $Name
}

# Is the tool available? Accounts for distros that rename the binary.
function Test-Dependency {
    param([Parameter(Mandatory)][string]$Name)

    if (Get-Command $Name -ErrorAction SilentlyContinue) { return $true }

    $mgr = Get-PackageManagerName
    $map = $script:PF_BinaryNameMap[$mgr]
    if ($map -and $map.ContainsKey($Name)) {
        return [bool](Get-Command $map[$Name] -ErrorAction SilentlyContinue)
    }
    return $false
}

# Run a root-requiring command, elevating with sudo when not already root.
#
# ⚠️  DO NOT rebuild this as `$sudo = if (root) { @() } else { @('sudo') }` followed
# by `$sudo + $cmd`. PowerShell UNROLLS a single-element array into a scalar, so
# `@('sudo')` becomes the STRING 'sudo', and `'sudo' + @('apt-get','install')` is
# string concatenation, not array concatenation. `$full[0]` then indexes the first
# CHARACTER — 's' — and the whole thing dies with "The term 's' is not recognized".
#
# It only breaks when NOT root (as root the empty array concatenates fine), which is
# why it passed in a root container and exploded on the non-root CI runner.
function Invoke-Elevated {
    param([Parameter(Mandatory)][string[]]$Command)

    $argv = [System.Collections.Generic.List[string]]::new()
    if ((id -u) -ne '0') { $argv.Add('sudo') }
    foreach ($c in $Command) { $argv.Add($c) }

    $exe  = $argv[0]
    $rest = @($argv | Select-Object -Skip 1)

    & $exe @rest 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

# Refresh the package index. Runs at most once per session.
#
# CRITICAL on apt: a fresh machine (or container) has EMPTY package lists, so
# `apt-get install git` fails with "Unable to locate package" — even for packages
# that obviously exist. Without this, dependency installation silently fails for
# every single tool on a clean box.
function Update-PackageIndex {
    if ($script:PF_IndexUpdated) { return $true }

    $cmd = switch (Get-PackageManagerName) {
        'apt'    { @('apt-get', 'update', '-qq') }
        'dnf'    { $null }                              # dnf refreshes on demand
        'pacman' { @('pacman', '-Sy', '--noconfirm') }
        'zypper' { @('zypper', '--non-interactive', 'refresh') }
        'apk'    { @('apk', 'update') }
        default  { $null }
    }

    if ($cmd) { Invoke-Elevated -Command $cmd | Out-Null }

    $script:PF_IndexUpdated = $true
    return $true
}

# Run a package-manager install, elevating with sudo when not already root.
function Invoke-PackageManager {
    param([Parameter(Mandatory)][string[]]$Arguments)

    Update-PackageIndex | Out-Null

    $cmd = switch (Get-PackageManagerName) {
        'apt'    { @('apt-get', 'install', '-y') }
        'dnf'    { @('dnf', 'install', '-y') }
        'pacman' { @('pacman', '-S', '--noconfirm') }
        'zypper' { @('zypper', '--non-interactive', 'install') }
        'apk'    { @('apk', 'add') }
        default  { $null }
    }
    if (-not $cmd) { return $false }

    return (Invoke-Elevated -Command ($cmd + $Arguments))
}

# Install a tool from its GitHub release, for distros that do not package it.
#
# starship and lsd are NOT in Ubuntu 22.04's repos at all, so apt can never install
# them. Uses PowerShell's own web cmdlets rather than curl: a minimal container (or a
# slim server image) often has neither curl nor wget, and an installer that silently
# needs one fails with no explanation. pwsh is guaranteed present — we are running in it.
function Install-FromGitHubRelease {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$AssetPattern
    )

    try {
        $release = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest" -TimeoutSec 20
        $asset   = $release.assets | Where-Object { $_.name -like $AssetPattern } | Select-Object -First 1
        if (-not $asset) { return $false }

        $tmp = Join-Path (Get-TempPath) $asset.name
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmp -TimeoutSec 180

        $sudo = if ((id -u) -eq '0') { '' } else { 'sudo ' }

        if ($asset.name -like '*.deb') {
            bash -c "$sudo dpkg -i '$tmp'" 2>&1 | Out-Null
        }
        elseif ($asset.name -like '*.tar.gz') {
            $dir = Join-Path (Get-TempPath) "pf-extract-$Name"
            Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            tar -xzf $tmp -C $dir 2>&1 | Out-Null

            $bin = Get-ChildItem $dir -Recurse -File | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
            if ($bin) { bash -c "$sudo install -m 755 '$($bin.FullName)' /usr/local/bin/$Name" 2>&1 | Out-Null }
            Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
        }

        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        return (Test-Dependency $Name)
    }
    catch { return $false }
}

# Fallback for tools the distro does not package.
function Install-ViaOfficialScript {
    param([Parameter(Mandatory)][string]$Name)

    $arch = (uname -m)
    $debArch = switch ($arch) { 'x86_64' { 'amd64' } 'aarch64' { 'arm64' } default { $null } }

    switch ($Name) {
        'starship' {
            return (Install-FromGitHubRelease -Name 'starship' -Repo 'starship/starship' `
                        -AssetPattern "starship-$arch-unknown-linux-gnu.tar.gz")
        }
        'zoxide' {
            if ($debArch) {
                return (Install-FromGitHubRelease -Name 'zoxide' -Repo 'ajeetdsouza/zoxide' `
                            -AssetPattern "zoxide_*_$debArch.deb")
            }
            return $false
        }
        'lsd' {
            if ($debArch -and (Get-PackageManagerName) -eq 'apt') {
                return (Install-FromGitHubRelease -Name 'lsd' -Repo 'lsd-rs/lsd' `
                            -AssetPattern "lsd_*_$debArch.deb")
            }
            return (Install-FromGitHubRelease -Name 'lsd' -Repo 'lsd-rs/lsd' `
                        -AssetPattern "lsd-*-$arch-unknown-linux-gnu.tar.gz")
        }
        default { return $false }
    }
}

# Install one tool. Tries the distro package first, then the tool's own installer.
function Install-Dependency {
    param([Parameter(Mandatory)][string]$Name)

    if (Test-Dependency $Name) { return $true }

    if (Test-PackageManager) {
        if (Invoke-PackageManager -Arguments @((Resolve-PackageName $Name))) {
            if (Test-Dependency $Name) { return $true }
        }
    }

    # starship / zoxide are often missing from stable repos — use their installer.
    return (Install-ViaOfficialScript $Name)
}

# Remove ONE package via the distro package manager.
function Remove-SinglePackage {
    param([Parameter(Mandatory)][string]$Name)

    $pkg = Resolve-PackageName $Name

    $cmd = switch (Get-PackageManagerName) {
        'apt'    { @('apt-get', 'remove', '-y') }
        'dnf'    { @('dnf', 'remove', '-y') }
        'pacman' { @('pacman', '-R', '--noconfirm') }
        'zypper' { @('zypper', '--non-interactive', 'remove') }
        'apk'    { @('apk', 'del') }
        default  { $null }
    }
    if (-not $cmd) { return $false }

    return (Invoke-Elevated -Command ($cmd + @($pkg)))
}

# Remove the tools PowerFlow installed.
#
# Two traps this has to handle, both found on a real box:
#
#  1. NEVER batch the removals. `apt-get remove starship zoxide lsd` aborts the
#     WHOLE command if even one name is not an apt package — so a single unpackaged
#     tool silently leaves every other tool installed. Remove them one at a time.
#
#  2. Tools installed from a GitHub tarball live in /usr/local/bin and are invisible
#     to the package manager. apt can never remove them; the binary must be deleted.
function Uninstall-Dependency {
    param([Parameter(Mandatory)][string[]]$Name)

    $sudo   = if ((id -u) -eq '0') { '' } else { 'sudo ' }
    $allOk  = $true

    foreach ($n in $Name) {
        $cmd = Get-Command $n -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }   # already gone

        $path = $cmd.Source

        if ($path -and $path -like '/usr/local/*') {
            # Hand-installed binary — the package manager knows nothing about it.
            bash -c "$sudo rm -f '$path'" 2>&1 | Out-Null
        }
        else {
            Remove-SinglePackage $n | Out-Null
        }

        # Verify per tool rather than trusting an exit code.
        if (Test-Dependency $n) { $allOk = $false }
    }

    return $allOk
}

# Tools that most distros do NOT package. Telling an Ubuntu 22.04 user to
# `apt-get install lsd` is actively wrong advice — there is no such package.
$script:PF_UnpackagedTools = @{
    'starship' = 'https://starship.rs/guide/#step-1-install-starship'
    'lsd'      = 'https://github.com/lsd-rs/lsd#installation'
}

function Get-DependencyInstallHint {
    param([Parameter(Mandatory)][string]$Name)

    $mgr = Get-PackageManagerName

    # Only suggest the package manager when the package actually exists there.
    if ($script:PF_UnpackagedTools.ContainsKey($Name) -and $mgr -eq 'apt') {
        return "not in apt — see $($script:PF_UnpackagedTools[$Name]) (PowerFlow will fetch it from GitHub automatically)"
    }

    $pkg = Resolve-PackageName $Name
    switch ($mgr) {
        'apt'    { return "sudo apt-get install $pkg" }
        'dnf'    { return "sudo dnf install $pkg" }
        'pacman' { return "sudo pacman -S $pkg" }
        'zypper' { return "sudo zypper install $pkg" }
        'apk'    { return "sudo apk add $pkg" }
        default  { return "install '$pkg' with your package manager" }
    }
}
