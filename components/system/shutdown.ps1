# ==============================================================================
# PowerFlow — Shutdown Scheduler
# ==============================================================================
# Domain   : System
# File     : components/system/shutdown.ps1
# Purpose  : Schedule or cancel Windows shutdown with time-based syntax (e.g. "shutdown 1h 30m")
# Functions: shutdown, s
# Depends  : none
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
            shutdown.exe /a | Out-Null
            Write-Host "✅ Shutdown cancelled" -ForegroundColor Green
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
        if ($totalMinutes -gt 180) {
            Write-Host "❌ Maximum shutdown delay is 3 hours" -ForegroundColor Red
            return
        }

        $seconds = $totalMinutes * 60
        shutdown.exe /s /t $seconds | Out-Null

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
        shutdown.exe /a | Out-Null
        Write-Host "✅ Shutdown cancelled" -ForegroundColor Green
        return
    }

    # For scheduling, forward to shutdown (full function)
    shutdown @Args
}
