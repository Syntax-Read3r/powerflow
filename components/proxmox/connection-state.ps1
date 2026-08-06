# ============================================================================== 
# PowerFlow — Proxmox Connection State
# ============================================================================== 
# Domain   : Proxmox
# File     : components/proxmox/connection-state.ps1
# Purpose  : Convert transport failures into alias-only PMX state and guidance
# Functions: ConvertTo-PmxSessionFailure, Write-PmxDisconnectedState
# Depends  : shared.ps1 formatting helpers
# ============================================================================== 

function ConvertTo-PmxSessionFailure {
    param(
        $Connection,
        [string]$ErrorMessage,
        [string]$FailureKind = ''
    )

    if ($Connection -and "$($Connection.Transport)" -eq 'ssh' -and $FailureKind) {
        $alias = ConvertTo-PmxDisplayText $Connection.Label
        if ($alias -notmatch '^[a-z0-9][a-z0-9_-]{0,63}$') { $alias = 'saved server' }
        return [pscustomobject]@{
            Message     = "Not connected to Proxmox server '$alias'."
            FailureKind = $FailureKind
            Alias       = $alias
        }
    }

    return [pscustomobject]@{
        Message     = if ($ErrorMessage) { $ErrorMessage } else { 'Proxmox management is unavailable.' }
        FailureKind = $FailureKind
        Alias       = ''
    }
}

function Write-PmxDisconnectedState {
    param([Parameter(Mandatory)]$Session)

    Write-Host ''
    Write-Host '⚡ PROXMOX' -ForegroundColor Cyan
    Write-Host '──────────────────────────────────────────────────────────────' -ForegroundColor DarkGray

    if ($Session.Connection -and "$($Session.Connection.Transport)" -eq 'ssh' -and $Session.FailureKind) {
        $alias = ConvertTo-PmxDisplayText $Session.Connection.Label
        if ($alias -notmatch '^[a-z0-9][a-z0-9_-]{0,63}$') { $alias = 'saved server' }
        Write-Host "  🟡 Not connected to Proxmox server '$alias'." -ForegroundColor Yellow
        Write-Host "     Sign in first:  srv $alias" -ForegroundColor White
        Write-Host '     Then run pmx inside that Proxmox session.' -ForegroundColor DarkGray
    }
    elseif (-not $Session.Connection) {
        Write-Host '  🟡 No Proxmox server is connected.' -ForegroundColor Yellow
        Write-Host '     Save a server with srv, then select it with: pmx config set host <name>' -ForegroundColor DarkGray
    }
    else {
        Write-Host "  ❌ $($Session.Error)" -ForegroundColor Red
    }
    Write-Host ''
}
