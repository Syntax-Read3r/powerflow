# ==============================================================================
# PowerFlow — Packages Adapter (Windows)
# ==============================================================================
# Domain   : Platform / Windows
# File     : platform/windows/adapters/packages.ps1
# Purpose  : Install and query PowerFlow's tool dependencies via Scoop
# Contract : Get-PackageManagerName, Test-PackageManager, Install-PackageManager,
#            Test-Dependency, Install-Dependency, Uninstall-Dependency,
#            Get-DependencyInstallHint
# Depends  : none
# ==============================================================================

function Get-PackageManagerName { return 'scoop' }

function Test-PackageManager {
    return [bool](Get-Command scoop -ErrorAction SilentlyContinue)
}

# Bootstrap the package manager itself. Returns $true on success.
function Install-PackageManager {
    if (Test-PackageManager) { return $true }

    try {
        Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
        return [bool](Get-Command scoop -ErrorAction SilentlyContinue)
    }
    catch {
        Write-Host "❌ Failed to install Scoop: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Is a tool already available on this machine?
function Test-Dependency {
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

# Install one tool. Returns $true on success.
function Install-Dependency {
    param([Parameter(Mandatory)][string]$Name)

    if (-not (Test-PackageManager)) { return $false }

    scoop install $Name *>$null
    return (Test-Dependency $Name)
}

function Uninstall-Dependency {
    param([Parameter(Mandatory)][string[]]$Name)

    if (-not (Test-PackageManager)) { return $false }

    scoop uninstall @Name 2>$null
    return $true
}

# The copy/pasteable command shown to a user when a tool is missing.
function Get-DependencyInstallHint {
    param([Parameter(Mandatory)][string]$Name)
    return "scoop install $Name"
}
