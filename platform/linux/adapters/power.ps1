# ==============================================================================
# PowerFlow — Power Adapter (Linux)
# ==============================================================================
# Domain   : Platform / Linux
# File     : platform/linux/adapters/power.ps1
# Purpose  : Schedule and cancel a system shutdown via shutdown(8)
# Contract : Invoke-Shutdown, Stop-Shutdown
# Depends  : Test-Admin (platform/linux/adapters/elevation.ps1)
# ==============================================================================
#
# `shutdown -h +N` schedules; `shutdown -c` cancels. Both need root, so elevate
# with sudo when the session is not already root.
# ==============================================================================

function Invoke-Shutdown {
    param([Parameter(Mandatory)][int]$Minutes)

    if (-not (Get-Command shutdown -ErrorAction SilentlyContinue)) {
        Write-Host "❌ shutdown(8) not found on this system." -ForegroundColor Red
        return $false
    }

    if (Test-Admin) { shutdown -h "+$Minutes" 2>&1 | Out-Null }
    else            { sudo shutdown -h "+$Minutes" 2>&1 | Out-Null }

    return ($LASTEXITCODE -eq 0)
}

function Stop-Shutdown {
    if (-not (Get-Command shutdown -ErrorAction SilentlyContinue)) { return $false }

    if (Test-Admin) { shutdown -c 2>&1 | Out-Null }
    else            { sudo shutdown -c 2>&1 | Out-Null }

    return ($LASTEXITCODE -eq 0)
}
