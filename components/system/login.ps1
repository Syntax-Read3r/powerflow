# ==============================================================================
# PowerFlow — Login Launch
# ==============================================================================
# Domain   : System
# File     : components/system/login.ps1
# Purpose  : pwsh-autologin — turn "start PowerFlow on login" on or off, without
#            re-running the installer
# Functions: pwsh-autologin
# Depends  : login adapter — Get-LoginLaunchState, Enable-LoginLaunch,
#            Disable-LoginLaunch
# ==============================================================================
#
# The runtime twin of install.sh --auto-login. On Linux it toggles the guarded
# ~/.bashrc hook (the adapter writes the identical block the installer does). On
# Windows there is nothing to toggle — pwsh always loads $PROFILE — and the command
# says so. All ~/.bashrc work is in the adapter; this only renders.
# ==============================================================================

<#
.SYNOPSIS
    pwsh-autologin — start PowerFlow automatically when you log in (Linux).
.DESCRIPTION
    pwsh-autologin          turn it on (the common case)
    pwsh-autologin on       same
    pwsh-autologin off      turn it off — you'll land in bash; run `pwsh` by hand
    pwsh-autologin status   show the current setting, change nothing

    Guarded so it can never lock you out: if pwsh is ever removed you still get bash.
.EXAMPLE
    pwsh-autologin
#>
function pwsh-autologin {
    param([ValidateSet('', 'on', 'off', 'status')][string]$Mode = '')

    $state = Get-LoginLaunchState

    # Windows: no login-shell hook exists — PowerFlow loads on every pwsh start.
    if ($state -eq 'always') {
        Write-Host ""
        Write-Host "ℹ️  On Windows, PowerFlow loads automatically every time PowerShell 7 runs —" -ForegroundColor Cyan
        Write-Host "   there is no login hook to toggle." -ForegroundColor DarkGray
        Write-Host "   If a new terminal opens Windows PowerShell 5.1 or cmd instead, set" -ForegroundColor DarkGray
        Write-Host "   'PowerShell' (7+) as your terminal's default profile." -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    if ($Mode -eq 'status') {
        Write-Host ""
        if ($state -eq 'on') {
            Write-Host "✅ PowerFlow starts automatically on login." -ForegroundColor Green
            Write-Host "   Turn it off:  pwsh-autologin off" -ForegroundColor DarkGray
        } else {
            Write-Host "⭕ PowerFlow does NOT start on login — you land in bash." -ForegroundColor Yellow
            Write-Host "   Turn it on:  pwsh-autologin" -ForegroundColor DarkGray
        }
        Write-Host ""
        return
    }

    if ($Mode -eq 'off') {
        if ($state -eq 'off') {
            Write-Host "⭕ Already off — PowerFlow does not start on login." -ForegroundColor Yellow
            return
        }
        if (Disable-LoginLaunch) {
            Write-Host "✅ Off. Your next login lands in bash." -ForegroundColor Green
            Write-Host "   Start PowerFlow by hand with 'pwsh', or re-enable:  pwsh-autologin" -ForegroundColor DarkGray
        } else {
            Write-Host "❌ Could not update ~/.bashrc." -ForegroundColor Red
        }
        return
    }

    # default / 'on' → enable
    if ($state -eq 'on') {
        Write-Host "✅ PowerFlow already starts on login. (pwsh-autologin off to undo)" -ForegroundColor Green
        return
    }
    if (Enable-LoginLaunch) {
        Write-Host "✅ PowerFlow will now start automatically on login." -ForegroundColor Green
        Write-Host "   Test it WITHOUT logging out:  bash -l" -ForegroundColor Cyan
        Write-Host "   Undo any time:  pwsh-autologin off" -ForegroundColor DarkGray
    } else {
        Write-Host "❌ Could not write the login hook to ~/.bashrc." -ForegroundColor Red
    }
}

# ── pwsh-h registration ───────────────────────────────────────────────────────
Register-PFCommand -Name 'pwsh-autologin' -Platform 'Linux' -Section '⚙️ CONFIGURATION & SETTINGS' -Synopsis 'start PowerFlow on login (on/off) - no installer re-run' -Example 'pwsh-autologin · pwsh-autologin off'
