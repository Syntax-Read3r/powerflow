# ==============================================================================
# PowerFlow — Packages Adapter (Windows)
# ==============================================================================
# Domain   : Platform / Windows
# File     : platform/windows/adapters/packages.ps1
# Purpose  : Enforce Scoop as PowerFlow's Windows prerequisite, then install and
#            query managed tool dependencies through it
# Contract : Get-PackageManagerName, Get-PackageManagerRoot, Test-PackageManager,
#            Install-PackageManager, Test-Dependency, Install-Dependency,
#            Uninstall-Dependency, Get-DependencyInstallHint
# Internal : Add-ScoopShimToCurrentPath, Get-PackageManagerRemovalWarning,
#            Confirm-PackageManagerRemoval, Uninstall-PackageManager
# Depends  : none
# ==============================================================================

function Get-PackageManagerName { return 'scoop' }

<#
.SYNOPSIS
    Scoop's root — the one place that answers "where is Scoop actually installed".
.DESCRIPTION
    THE VARIABLE IS NOT WHERE SCOOP KEEPS THE ANSWER. Scoop resolves its own root as
    $env:SCOOP, then `root_path` from its config file, then ~\scoop. Relocating with the
    installer's -ScoopDir writes root_path and sets NO environment variable — and the
    upstream installer writes root_path only when no User-scope SCOOP exists, so the two
    are alternatives rather than a pair.

    PowerFlow read only the variable, in four separate places. On any machine with a
    relocated Scoop that means an empty $env:SCOOP, a computed ~\scoop that does not
    exist, zero Scoop apps reported and no shims added — while Scoop itself works
    perfectly. This function is the single resolver those four sites now share.

    It deliberately does NOT require the path to exist. Agreeing with Scoop about where
    Scoop is matters more than reporting something reachable: if the root is on a drive
    that is currently unmounted, "there and unavailable" is the truth, and quietly
    answering ~\scoop instead would have PowerFlow acting on a different installation
    from the one the user has.
#>
function Get-PackageManagerRoot {
    if ($env:SCOOP) { return "$env:SCOOP" }

    # Get-HomePath, not [Environment]::GetFolderPath('UserProfile'): the adapter is the
    # house rule for "where is home", and GetFolderPath cannot be redirected — it ignores
    # $env:USERPROFILE entirely (measured), which makes this function untestable without
    # writing into the real profile.
    # $homeDir, never $home — $HOME is a read-only automatic variable, and assigning it
    # throws. There is a CI gate for exactly this class of mistake.
    #
    # RESOLVED DEFENSIVELY, because this file is dot-sourced ON ITS OWN. install.ps1 loads
    # packages.ps1 well before locations.ps1, so Get-HomePath does not exist yet when the
    # installer bootstraps the package manager. That shipped as a failed release: on a
    # machine that already HAS Scoop, Test-PackageManager returns at its `Get-Command scoop`
    # check and never reaches this function — so every local run passed, and the CI runner,
    # which has no Scoop, took the other branch and the installer died. An adapter the
    # installer sources standalone may not assume a sibling adapter is loaded.
    $homeDir = if (Get-Command Get-HomePath -ErrorAction SilentlyContinue) { Get-HomePath } else { $HOME }

    # Read defensively — a partial or corrupt config must degrade to the default, never
    # throw. This runs during profile load, where an exception is a broken shell.
    $config = Join-Path $homeDir '.config\scoop\config.json'
    if (Test-Path -LiteralPath $config) {
        try {
            $root = (Get-Content -LiteralPath $config -Raw -ErrorAction Stop | ConvertFrom-Json).root_path
            if ($root) { return "$root" }
        } catch { }
    }
    return (Join-Path $homeDir 'scoop')
}

# Scoop's bootstrap persists this directory in the USER PATH, but the current
# PowerShell process does not reliably receive that update. Make the prerequisite
# usable immediately so the same installer run can install tools and the Nerd Font.
function Add-ScoopShimToCurrentPath {
    $shimPath = Join-Path (Get-PackageManagerRoot) 'shims'
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
