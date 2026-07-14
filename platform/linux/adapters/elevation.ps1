# ==============================================================================
# PowerFlow — Elevation Adapter (Linux)
# ==============================================================================
# Domain   : Platform / Linux
# File     : platform/linux/adapters/elevation.ps1
# Purpose  : Detect root, and assert privileges for commands that need them
# Contract : Test-Admin, Assert-Admin
# Depends  : none
# ==============================================================================
#
# NOTE: the Linux model differs from Windows. You do not run the whole shell as
# root — you elevate individual commands with sudo. So Assert-Admin passes when
# EITHER the session is root OR sudo is available to elevate the specific action.
# Adapters that need root (power, env) call sudo themselves.
# ==============================================================================

# $true when the session is running as root (uid 0). Silent.
function Test-Admin {
    return ((id -u) -eq '0')
}

# $true when sudo exists and can be used to elevate a single command.
function Test-SudoAvailable {
    return [bool](Get-Command sudo -ErrorAction SilentlyContinue)
}

# Gate a command on privileges. Passes when already root, or when sudo can
# elevate the action. Prints the standard PowerFlow message otherwise.
function Assert-Admin {
    param([string]$Action = 'This operation')

    if (Test-Admin)         { return $true }
    if (Test-SudoAvailable) { return $true }   # the caller will invoke sudo

    Write-Host "❌ $Action requires root, and sudo is not available." -ForegroundColor Red
    Write-Host "💡 Re-run as root, or install sudo." -ForegroundColor DarkGray
    return $false
}
