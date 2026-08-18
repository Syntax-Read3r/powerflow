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

# ── PF-FEAT-001: set a POSIX mode ─────────────────────────────────────────────

<#
.SYNOPSIS
    Apply a numeric POSIX mode to a path, and VERIFY it took.
.DESCRIPTION
    chmod's exit code is necessary but not sufficient. It can succeed while the resulting
    mode differs from the one asked for — most commonly on a filesystem mounted with fixed
    permissions (vfat, ntfs-3g, many network mounts), where chmod returns 0 and the mode is
    whatever the mount options dictate. Reporting success there would tell someone their key
    file is 600 when it is world-readable, which is the one direction a permissions command
    must never be wrong in.

    So the mode is read back and compared, and a mismatch is a FAILURE carrying both numbers.
.PARAMETER Mode
    Numeric only — 600, 0644. Symbolic forms (u+x, go-rwx) are deliberately not accepted:
    they are relative to the current mode, so "verify it took" has no single expected value
    to compare against, and a half-supported syntax is worse than a clearly limited one.
#>
function Set-FileMode {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Mode
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            Supported = $true; Success = $false; Numeric = ''; Symbolic = ''
            Error = "no such path: $Path"
        }
    }

    if ($Mode -notmatch '^[0-7]{3,4}$') {
        return [pscustomobject]@{
            Supported = $true; Success = $false; Numeric = ''; Symbolic = ''
            Error = "'$Mode' is not a numeric mode — use three or four octal digits, such as 600 or 0644"
        }
    }

    # `--` before the path so a filename beginning with a dash is not read as an option.
    $stderr = & chmod $Mode -- "$Path" 2>&1
    $code = $LASTEXITCODE

    $after = Get-FileMode -Path $Path
    if (-not $after) {
        return [pscustomobject]@{
            Supported = $true; Success = $false; Numeric = ''; Symbolic = ''
            Error = 'the mode could not be read back after chmod'
        }
    }

    if ($code -ne 0) {
        return [pscustomobject]@{
            Supported = $true; Success = $false
            Numeric = $after.Numeric; Symbolic = $after.Symbolic
            Error = "chmod failed: $(("$stderr" -split "`n" | Select-Object -First 1).Trim())"
        }
    }

    # Compare as NUMBERS, not strings: `chmod 644` yields "644" and `chmod 0644` also yields
    # "644", and a string compare would call the second a mismatch.
    $wanted = [Convert]::ToInt32($Mode, 8)
    $actual = [Convert]::ToInt32($after.Numeric, 8)
    if ($wanted -ne $actual) {
        return [pscustomobject]@{
            Supported = $true; Success = $false
            Numeric = $after.Numeric; Symbolic = $after.Symbolic
            Error = "chmod reported success but the mode is $($after.Numeric), not $Mode — this filesystem may be mounted with fixed permissions"
        }
    }

    return [pscustomobject]@{
        Supported = $true; Success = $true
        Numeric = $after.Numeric; Symbolic = $after.Symbolic; Error = ''
    }
}
