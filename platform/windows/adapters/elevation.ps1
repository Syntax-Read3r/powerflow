# ==============================================================================
# PowerFlow — Elevation Adapter (Windows)
# ==============================================================================
# Domain   : Platform / Windows
# File     : platform/windows/adapters/elevation.ps1
# Purpose  : Detect and assert an elevated (Administrator) session, and run a single
#            command elevated on demand
# Contract : Test-Admin, Assert-Admin  (+ Invoke-ElevatedCommand, adapter-internal)
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

# Run ONE command elevated and report whether it succeeded.
#
# Used by adapters whose settings are machine-wide (timezone, hostname, time sync,
# HKLM startup entries). Rather than refusing when PowerFlow is running unelevated, we
# re-run just that command in a child pwsh via Start-Process -Verb RunAs — the standard
# UAC prompt. The user consents visibly, once, per change.
#
# Notes on the details, each of which is load-bearing:
#   * -NoProfile — the child must not reload PowerFlow (slow, and pointless for a
#     one-shot cmdlet).
#   * this process's own pwsh path, not bare 'pwsh' — the elevated PATH may differ.
#   * the command is wrapped in try/exit so a THROWING cmdlet becomes a non-zero exit
#     code; without it the child exits 0 and a failure looks like success.
#   * a declined UAC prompt throws in the parent, which we translate to $false.
function Invoke-ElevatedCommand {
    param([Parameter(Mandatory)][string]$Command)

    $exe = try { (Get-Process -Id $PID).Path } catch { $null }
    if (-not $exe) { $exe = 'pwsh.exe' }

    $wrapped = "try { $Command } catch { exit 1 }; exit 0"
    try {
        $p = Start-Process -FilePath $exe `
                           -ArgumentList '-NoProfile', '-NonInteractive', '-Command', $wrapped `
                           -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ErrorAction Stop
        return ($p.ExitCode -eq 0)
    } catch {
        Write-Host "   (elevation declined or unavailable)" -ForegroundColor DarkGray
        return $false
    }
}
