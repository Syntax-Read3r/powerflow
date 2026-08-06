# ==============================================================================
# PowerFlow — Packages Adapter (Windows)
# ==============================================================================
# Domain   : Platform / Windows
# File     : platform/windows/adapters/packages.ps1
# Purpose  : Enforce Scoop as PowerFlow's Windows prerequisite, then install and
#            query managed tool dependencies through it
# Contract : Get-PackageManagerName, Test-PackageManager, Install-PackageManager,
#            Test-Dependency, Install-Dependency, Uninstall-Dependency,
#            Get-DependencyInstallHint
# Internal : Add-ScoopShimToCurrentPath, Get-PackageManagerRemovalWarning,
#            Confirm-PackageManagerRemoval, Uninstall-PackageManager
# Depends  : none
# ==============================================================================

function Get-PackageManagerName { return 'scoop' }

# Scoop's bootstrap persists this directory in the USER PATH, but the current
# PowerShell process does not reliably receive that update. Make the prerequisite
# usable immediately so the same installer run can install tools and the Nerd Font.
function Add-ScoopShimToCurrentPath {
    $scoopRoot = if ($env:SCOOP) {
        $env:SCOOP
    } else {
        Join-Path ([Environment]::GetFolderPath('UserProfile')) 'scoop'
    }
    $shimPath = Join-Path $scoopRoot 'shims'
    if (-not (Test-Path -LiteralPath $shimPath)) { return $false }

    $pathEntries = @($env:PATH -split ';' | Where-Object { $_ })
    if (-not @($pathEntries | Where-Object {
        [string]::Equals($_.TrimEnd('\\'), $shimPath.TrimEnd('\\'), [StringComparison]::OrdinalIgnoreCase)
    }).Count) {
        $env:PATH = "$shimPath;$env:PATH"
    }

    return [bool](Get-Command scoop -ErrorAction SilentlyContinue)
}

function Test-PackageManager {
    if (Get-Command scoop -ErrorAction SilentlyContinue) { return $true }
    return (Add-ScoopShimToCurrentPath)
}

# Bootstrap the package manager itself. Returns $true on success.
function Install-PackageManager {
    if (Test-PackageManager) { return $true }

    try {
        Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
        if (-not (Add-ScoopShimToCurrentPath)) {
            throw 'Scoop installed, but its shim directory could not be activated in this PowerShell process.'
        }
        return $true
    }
    catch {
        Write-Host "❌ Failed to install Scoop: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Scoop owns more than PowerFlow's dependencies. The shared uninstaller displays
# this only after the user opts in, then Scoop performs its own final confirmation.
function Get-PackageManagerRemovalWarning {
    return @(
        'Removing Scoop also uninstalls EVERY application managed by Scoop.'
        'Its buckets, shims, and non-persisted application files are removed as well.'
        'This can break unrelated commands and workflows that were never part of PowerFlow.'
        'Persisted application data is kept unless Scoop is explicitly purged.'
    )
}

function Confirm-PackageManagerRemoval {
    param(
        [scriptblock]$ReadResponse = { param($Prompt) Read-Host $Prompt }
    )

    $answer = & $ReadResponse 'Also remove the Scoop prerequisite? (y/n)'
    if ("$answer" -notmatch '^y(?:es)?$') { return $false }

    # The user asked to see the risks AFTER opting in. This is intentionally not
    # printed for the safe/default "no" path.
    Write-Host ""
    Write-Host "⚠️  Removing Scoop has system-wide consequences for your user account:" -ForegroundColor Red
    foreach ($warningLine in (Get-PackageManagerRemovalWarning)) {
        Write-Host "   • $warningLine" -ForegroundColor Yellow
    }
    Write-Host ""

    $confirmed = & $ReadResponse "Continue to Scoop's final removal confirmation? (y/n)"
    return ("$confirmed" -match '^y(?:es)?$')
}

function Uninstall-PackageManager {
    if (-not (Test-PackageManager)) { return $true }

    # Scoop's own uninstaller prints its warning and asks one final y/N question.
    & scoop uninstall scoop
    return (-not (Test-PackageManager))
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
