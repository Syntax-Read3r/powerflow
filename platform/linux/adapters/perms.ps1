# ==============================================================================
# PowerFlow — Permissions Adapter (Linux)
# ==============================================================================
# Domain   : Platform / Linux
# File     : platform/linux/adapters/perms.ps1
# Purpose  : Read POSIX mode bits, owner and group; read and set the process umask
# Contract : Get-FileMode, Test-PermsSupported, Get-Umask, Set-Umask
# Depends  : none
# ==============================================================================

function Test-PermsSupported { return $true }

<#
.SYNOPSIS
    The POSIX mode, owner and group of a path.
.DESCRIPTION
    Uses stat(1), which reports the values the kernel actually holds — no parsing of
    `ls -l` output, which is localised and reformatted between distros.
#>
function Get-FileMode {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }

    # %A symbolic (drwxr-xr-x) · %a numeric (755) · %U user · %G group
    # %h links · %s size · %Y mtime epoch · %F type
    $raw = stat -c '%A|%a|%U|%G|%h|%s|%Y|%F' -- "$Path" 2>/dev/null
    if (-not $raw) { return $null }

    $p = $raw -split '\|'
    if ($p.Count -lt 8) { return $null }

    $symbolic = $p[0]      # e.g. drwxr-xr-x

    return [pscustomobject]@{
        Path      = $Path
        Name      = Split-Path $Path -Leaf
        Symbolic  = $symbolic
        Type      = $symbolic.Substring(0, 1)      # d - l c b s p
        Owner     = $symbolic.Substring(1, 3)      # rwx
        Group     = $symbolic.Substring(4, 3)      # r-x
        Others    = $symbolic.Substring(7, 3)      # r-x
        Numeric   = $p[1]                          # 755
        User      = $p[2]
        GroupName = $p[3]
        Links     = [int]$p[4]
        Size      = [int64]$p[5]
        Modified  = [datetimeoffset]::FromUnixTimeSeconds([int64]$p[6]).LocalDateTime
        Kind      = $p[7]                          # "directory" / "regular file" / ...
    }
}

# ── umask ─────────────────────────────────────────────────────────────────────
#
# umask is a SHELL BUILTIN, not a binary — there is no /usr/bin/umask to run. Shelling
# out to `sh -c 'umask'` can *read* it (the subshell inherits ours), but a subshell's
# `umask 022` dies with the subshell, so it cannot SET anything. It must be done in
# process, via libc.
#
# Verified working on both glibc (Debian) and musl (Alpine).
if (-not ('PF.Native' -as [type])) {
    Add-Type -Name Native -Namespace PF -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("libc", SetLastError = true)]
public static extern uint umask(uint mask);
'@ -ErrorAction SilentlyContinue
}

<#
.SYNOPSIS
    The current process umask, as an octal string ("0022").
.DESCRIPTION
    THE TRAP: umask(2) has no getter. It always SETS, and returns the PREVIOUS value.
    So reading it means setting it to 0 and immediately putting it back. Skip the restore
    and you have silently set the umask to 0000 — every file the shell creates from then
    on would be world-writable.
#>
function Get-Umask {
    if (-not ('PF.Native' -as [type])) { return $null }
    try {
        $old = [PF.Native]::umask(0)
        [PF.Native]::umask($old) | Out-Null      # put it back IMMEDIATELY
        return ([Convert]::ToString($old, 8)).PadLeft(4, '0')
    } catch { return $null }
}

<#
.SYNOPSIS
    Set the process umask. Takes octal ("022"). Returns the previous value, or $null.
#>
function Set-Umask {
    param([Parameter(Mandatory)][string]$Mask)

    if (-not ('PF.Native' -as [type])) { return $null }
    if ($Mask -notmatch '^[0-7]{3,4}$') { return $null }

    try {
        $old = [PF.Native]::umask([Convert]::ToUInt32($Mask, 8))
        return ([Convert]::ToString($old, 8)).PadLeft(4, '0')
    } catch { return $null }
}
