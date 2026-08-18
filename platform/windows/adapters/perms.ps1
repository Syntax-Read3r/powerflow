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

# ── PF-FEAT-001: set a POSIX mode ─────────────────────────────────────────────

<#
.SYNOPSIS
    Not supported on Windows, and says so rather than pretending.
.DESCRIPTION
    A numeric chmod mode is POSIX semantics: three permission bits for exactly three
    principals. NTFS ACLs are a different model — an ordered list of allow/deny entries
    per identity, with inheritance. There is no faithful mapping, and the plausible ones
    are dangerous in the direction that matters: "600" translated as "remove Users" leaves
    Administrators and SYSTEM with full control, so a user who ran `--chmod 600` on a
    private key would believe it was locked down when it is readable by anything elevated.

    So this refuses. The refusal names what Windows would actually use, because "not
    supported" without a next step is only half an answer.
#>
function Set-FileMode {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Mode
    )

    return [pscustomobject]@{
        Supported = $false
        Success   = $false
        Numeric   = ''
        Symbolic  = ''
        Error     = 'POSIX modes do not exist on Windows — NTFS uses ACLs, and translating a numeric mode would misreport who can read the file. Use icacls, or Get-Acl/Set-Acl, if you need to restrict it.'
    }
}
