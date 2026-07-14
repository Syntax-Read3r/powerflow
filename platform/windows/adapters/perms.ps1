# ==============================================================================
# PowerFlow — Permissions Adapter (Windows)
# ==============================================================================
# Domain   : Platform / Windows
# File     : platform/windows/adapters/perms.ps1
# Purpose  : Declare, honestly, that Windows has no POSIX mode bits
# Contract : Get-FileMode, Test-PermsSupported, Get-Umask, Set-Umask
# Depends  : none
# ==============================================================================
#
# Windows does NOT have POSIX permissions. It has ACLs — a fundamentally richer and
# differently-shaped model. There is no faithful mapping from `rwxr-xr-x` to an ACL.
#
# So this adapter does not pretend. It returns $null, and the caller says so plainly
# and points at `icacls`. Inventing a fake `755` for a Windows file would teach the
# user something false, which is worse than teaching nothing.
#
# The LESSONS still work on Windows (`lesson chmod` explains chmod perfectly well).
# Only the ACTION is unavailable.
# ==============================================================================

function Test-PermsSupported { return $false }

function Get-FileMode {
    param([Parameter(Mandatory)][string]$Path)
    return $null
}

# umask is a POSIX concept — a mask of permission bits to withhold when creating a file.
# Windows has no equivalent: new files inherit their ACL from the parent directory, and
# there is no per-process mask to read or set. $null, for the same reason as above: a
# fabricated "0022" would be a lie the user might act on.
function Get-Umask { return $null }

function Set-Umask {
    param([Parameter(Mandatory)][string]$Mask)
    return $null
}
