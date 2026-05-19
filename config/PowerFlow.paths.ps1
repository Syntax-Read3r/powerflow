# ==============================================================================
# PowerFlow — Paths
# ==============================================================================
# Domain   : Core
# File     : config/PowerFlow.paths.ps1
# Purpose  : Configures PATH, initializes Starship and Zoxide, auto-navigates to Code
# Functions: (none — initialization statements only)
# Depends  : components/navigation/nav.ps1 (provides nav function used by Zoxide alias)
# ==============================================================================

<#
.SYNOPSIS
    Configure Scoop package manager PATH if not already present
.DESCRIPTION
    Ensures Scoop's shims directory is in the PATH for access to installed packages.
    Only adds to PATH if not already present to avoid duplicates.
#>
if (-not ($env:PATH -like "*scoop*")) {
    $env:SCOOP = "$env:USERPROFILE\\scoop"
    $env:PATH += ";$env:SCOOP\\shims"
    Write-Verbose "🛠 Scoop PATH configured: $env:SCOOP\\shims"
}

<#
.SYNOPSIS
    Initialize Starship cross-shell prompt
.DESCRIPTION
    Starship provides a fast, customizable prompt with Git integration,
    language detection, and beautiful theming capabilities.
#>
Invoke-Expression (&starship init powershell)

<#
.SYNOPSIS
    Initialize Zoxide smart directory navigation with fuzzy search support
.DESCRIPTION
    Zoxide learns your directory usage patterns and provides intelligent
    navigation. Includes custom 'nav' function with interactive fuzzy search.
#>
$zoxideInit = &zoxide init --hook prompt powershell
Invoke-Expression ($zoxideInit -join "`n")

# Remove default 'z' alias to use our enhanced version
if (Test-Path Alias:\\z) { Remove-Item Alias:\\z -Force }

<#
.SYNOPSIS
    Auto-navigate to Code directory when starting from HOME
.DESCRIPTION
    Productivity enhancement: automatically moves to ~/Code directory
    when PowerShell starts from the user's home directory.
#>
if ((Get-Location).Path -eq $HOME) {
    Set-Location "$HOME\\Code"
    Write-Host "🏠 Auto-navigated to ~/Code" -ForegroundColor DarkGray
}
