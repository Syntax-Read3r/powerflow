# ==============================================================================
# PowerFlow — Power Adapter (Windows)
# ==============================================================================
# Domain   : Platform / Windows
# File     : platform/windows/adapters/power.ps1
# Purpose  : Schedule and cancel a system shutdown
# Contract : Invoke-Shutdown, Stop-Shutdown
# Depends  : none
# ==============================================================================

# Schedule a shutdown $Minutes from now. Returns $true on success.
function Invoke-Shutdown {
    param([Parameter(Mandatory)][int]$Minutes)

    $seconds = $Minutes * 60
    shutdown.exe /s /t $seconds | Out-Null
    return ($LASTEXITCODE -eq 0)
}

# Cancel a pending shutdown. Returns $true on success.
function Stop-Shutdown {
    shutdown.exe /a 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}
