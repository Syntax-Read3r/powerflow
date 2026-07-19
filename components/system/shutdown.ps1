# ==============================================================================
# PowerFlow — Shutdown Scheduler
# ==============================================================================
# Domain   : System
# File     : components/system/shutdown.ps1
# Purpose  : Schedule or cancel a system shutdown with time-based syntax (e.g. "shutdown 1h 30m")
# Functions: shutdown, s
# Depends  : Invoke-Shutdown, Stop-Shutdown (platform/<os>/adapters/power.ps1)
# ==============================================================================

function shutdown {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Args
    )

    try {
        if (-not $Args -or $Args.Count -eq 0) {
            Write-Host "❌ Usage: shutdown 1h [30m]  OR  shutdown cancel" -ForegroundColor Red
            return
        }

        # Cancel: ONLY "shutdown cancel"
        if ($Args.Count -eq 1 -and $Args[0] -eq 'cancel') {
            if (Stop-Shutdown) {
                Write-Host "✅ Shutdown cancelled" -ForegroundColor Green
            } else {
                Write-Host "❌ Failed to cancel shutdown (is one scheduled?)" -ForegroundColor Red
            }
            return
        }

        # Otherwise: schedule with time tokens
        $totalMinutes = 0

        foreach ($arg in $Args) {
            if ($arg -match '^(\d+)(h|m)$') {
                $value = [int]$matches[1]
                $unit  = $matches[2]
                if ($unit -eq 'h') { $totalMinutes += $value * 60 }
                else { $totalMinutes += $value }
            }
            else {
                Write-Host "❌ Invalid token: $arg (use Nh or Nm, or 'shutdown cancel')" -ForegroundColor Red
                return
            }
        }

        if ($totalMinutes -lt 10) {
            Write-Host "❌ Minimum shutdown delay is 10 minutes" -ForegroundColor Red
            return
        }
        if ($totalMinutes -gt 360) {
            Write-Host "❌ Maximum shutdown delay is 6 hours" -ForegroundColor Red
            return
        }

        if (-not (Invoke-Shutdown -Minutes $totalMinutes)) {
            Write-Host "❌ Failed to schedule shutdown" -ForegroundColor Red
            return
        }

        Write-Host "🕒 Shutdown scheduled in $totalMinutes minutes" -ForegroundColor Green
        Write-Host "💡 Cancel with: shutdown cancel  OR  s c" -ForegroundColor Yellow
    }
    catch {
        Write-Host "❌ Shutdown failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function s {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Args
    )

    # Cancel: ONLY "s c"
    if ($Args.Count -eq 1 -and $Args[0] -eq 'c') {
        if (Stop-Shutdown) {
            Write-Host "✅ Shutdown cancelled" -ForegroundColor Green
        } else {
            Write-Host "❌ Failed to cancel shutdown (is one scheduled?)" -ForegroundColor Red
        }
        return
    }

    # For scheduling, forward to shutdown (full function)
    shutdown @Args
}

# ── pwsh-h registration ───────────────────────────────────────────────────────
Register-PFCommand -Name 'shutdown' -Aliases @('s') -Section '⚙️ CONFIGURATION & SETTINGS' -Synopsis 'schedule a shutdown (10 min - 6 h); cancel with s c' -Example 'shutdown 1h 30m · s c'
