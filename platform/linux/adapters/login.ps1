# ==============================================================================
# PowerFlow — Login-Launch Adapter (Linux)
# ==============================================================================
# Domain   : Platform / Linux
# File     : platform/linux/adapters/login.ps1
# Purpose  : Manage the ~/.bashrc hook that launches pwsh on interactive login,
#            so `pwsh-autologin` can toggle it without re-running the installer
# Contract : Get-LoginLaunchState, Enable-LoginLaunch, Disable-LoginLaunch
# Depends  : none
# ==============================================================================
#
# PowerFlow is a PowerShell profile — it loads only when `pwsh` runs. Your login
# shell is bash, so without a hook you land in bash after every login and PowerFlow
# is simply not there. install.sh --auto-login writes a guarded block to ~/.bashrc;
# this adapter writes the SAME block, so the runtime command and the installer stay
# identical (the CI lockout test greps for this exact marker + terminator).
#
# THE GUARD IS THE SAFETY: the block only exec's pwsh for interactive shells, only
# once (PWSH_STARTED), and only if pwsh is actually on PATH. Remove pwsh and you
# still get bash — you cannot be locked out of your own machine.
# ==============================================================================

$script:PF_BashrcMarker = 'PowerFlow: launch pwsh on interactive login'
$script:PF_Bashrc       = Join-Path $HOME '.bashrc'

# The block is written with LF only. The .ps1 source is CRLF on a Windows checkout,
# so a here-string literal here would carry \r into ~/.bashrc — and a stray \r turns
# `fi` into `fi\r`, which bash mis-parses. Build with explicit `n and strip any \r.
function Get-PFLoginBlock {
    $lines = @(
        ''
        "# ── $script:PF_BashrcMarker ──"
        '# Guards, in order:'
        '#   $- == *i*      only interactive shells — never scp/rsync/cron/scripts'
        '#   PWSH_STARTED   prevents a login loop'
        '#   command -v     if pwsh is ever removed you still get bash — no lockout'
        '#   pwsh --version pwsh must RUN, not merely exist — a broken pwsh (e.g. missing'
        '#                  ICU) falls through to bash instead of exec-crash-looping login'
        'if [[ $- == *i* ]] && [[ -z "$PWSH_STARTED" ]] && command -v pwsh >/dev/null 2>&1 && pwsh --version >/dev/null 2>&1; then'
        '    export PWSH_STARTED=1'
        '    exec pwsh'
        'fi'
        ''
    )
    return (($lines -join "`n") -replace "`r", '')
}

# Find the hook block: the first marker line whose range down to the next bare `fi`
# actually CONTAINS `exec pwsh`. That `exec pwsh` requirement is the safety net — a
# user's own comment that merely mentions the marker phrase (or a user `if…fi` block
# after it) has no `exec pwsh`, so it is NOT mistaken for the hook and never deleted.
# Returns @{ Start; End } (0-based inclusive line indices) or $null.
function Find-PFHookRange {
    param([string[]]$Lines)
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match [regex]::Escape($script:PF_BashrcMarker)) {
            $hasExec = $false; $end = -1
            for ($j = $i; $j -lt $Lines.Count; $j++) {
                if ($Lines[$j] -match '(^|\s)exec\s+pwsh(\s|$)') { $hasExec = $true }
                if ($Lines[$j].Trim() -eq 'fi') { $end = $j; break }
            }
            if ($hasExec -and $end -ge 0) { return @{ Start = $i; End = $end } }
        }
    }
    return $null
}

function Get-LoginLaunchState {
    if (-not (Test-Path $script:PF_Bashrc)) { return 'off' }
    $lines = [System.IO.File]::ReadAllLines($script:PF_Bashrc)
    if (Find-PFHookRange -Lines $lines) { return 'on' }
    return 'off'
}

function Enable-LoginLaunch {
    if ((Get-LoginLaunchState) -eq 'on') { return $true }
    # AppendAllText writes exactly these bytes — no PowerShell newline translation,
    # so the LF-only block stays LF-only.
    [System.IO.File]::AppendAllText($script:PF_Bashrc, (Get-PFLoginBlock))
    return ((Get-LoginLaunchState) -eq 'on')
}

function Disable-LoginLaunch {
    if ((Get-LoginLaunchState) -eq 'off') { return $true }

    # Remove every real hook block (marker → fi that contains exec pwsh). Loops so a
    # pre-existing duplicate is cleared too; leaves all other lines — including a user
    # comment that happens to name the marker — untouched.
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.AddRange([string[]]([System.IO.File]::ReadAllLines($script:PF_Bashrc)))
    while ($true) {
        $r = Find-PFHookRange -Lines $lines.ToArray()
        if (-not $r) { break }
        $lines.RemoveRange($r.Start, ($r.End - $r.Start + 1))
    }
    [System.IO.File]::WriteAllText($script:PF_Bashrc, (($lines -join "`n") -replace "`r", '') + "`n")
    return ((Get-LoginLaunchState) -eq 'off')
}
