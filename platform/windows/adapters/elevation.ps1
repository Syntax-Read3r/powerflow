# ==============================================================================
# PowerFlow — Elevation Adapter (Windows)
# ==============================================================================
# Domain   : Platform / Windows
# File     : platform/windows/adapters/elevation.ps1
# Purpose  : Detect and assert an elevated (Administrator) session
# Contract : Test-Admin, Assert-Admin
# Depends  : none
# ==============================================================================

# Returns $true when the current session is elevated (Administrator). Silent.
function Test-Admin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Gate a command on elevation. Returns $true if already elevated; otherwise prints
# the standard PowerFlow message and returns $false.
#
#     if (-not (Assert-Admin 'System PATH')) { return }
function Assert-Admin {
    param([string]$Action = 'This operation')

    if (Test-Admin) { return $true }

    Write-Host "❌ $Action requires an elevated (Administrator) session." -ForegroundColor Red
    return $false
}
