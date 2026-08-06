# ==============================================================================
# PowerFlow — SSH Server Privacy and Invocation
# ==============================================================================
# Domain   : Network
# File     : components/network/server-privacy.ps1
# Purpose  : Keep saved SSH endpoints out of ordinary UI, delegate private SSH
#            sessions to platform adapters, and reveal details after authentication
# Functions: Get-PFServerTarget, Format-PFServerPublicRow, Invoke-PFServerSsh,
#            Test-PFServerInteractiveAuth, Show-PFServerAuthenticatedInfo
# Depends  : Private SSH session adapter; Format-PFServerStatus,
#            Get-PFServers and Save-PFServers resolve at runtime from servers.ps1
# ==============================================================================

# Endpoint display construction belongs in one deliberately narrow place. It feeds
# only the authenticated info view — never a list, picker, error, prompt, or banner.
function Get-PFServerTarget {
    param([Parameter(Mandatory)]$Server)
    return "$($Server.user)@$($Server.host)"
}

function Format-PFServerPublicRow {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$State,
        [Parameter(Mandatory)]$Server
    )
    return "$Name`t$(Format-PFServerStatus $State $Server)"
}

function Invoke-PFServerSsh {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Server,
        [switch]$AuthenticationOnly
    )

    # The adapter owns OpenSSH, askpass and endpoint-bearing argv. Components receive
    # only a categorized result, so neither native prompts nor diagnostics can leak the
    # saved target into PowerFlow output.
    # Do not capture this invocation: the normal native session must remain directly
    # attached to the terminal. Its adapter result is retrieved separately afterward.
    Invoke-PFPrivateSshSession -Name $Name -Server $Server -AuthenticationOnly:$AuthenticationOnly
}

function Test-PFServerInteractiveAuth {
    return (-not [Console]::IsInputRedirected)
}

function Show-PFServerAuthenticatedInfo {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Server,
        [Parameter(Mandatory)][string]$State
    )

    if (-not (Test-PFServerInteractiveAuth)) {
        Write-Host "❌ '$Name' info requires interactive SSH authentication; endpoint kept private." -ForegroundColor Red
        return
    }

    Write-Host "🔐 Authenticate to view '$Name' connection details." -ForegroundColor Cyan
    Invoke-PFServerSsh -Name $Name -Server $Server -AuthenticationOnly
    $authentication = Get-PFPrivateSshSessionResult
    if (-not $authentication.Success) {
        if ($authentication.FailureKind -eq 'client-missing') {
            Write-Host '❌ No SSH client is installed; connection details remain hidden.' -ForegroundColor Red
            return
        }
        if ($authentication.FailureKind -eq 'prompt-unavailable') {
            Write-Host '❌ The private password prompt is unavailable; connection details remain hidden.' -ForegroundColor Red
            return
        }
        Write-Host '❌ Authentication did not succeed; connection details remain hidden.' -ForegroundColor Yellow
        return
    }

    $servers = Get-PFServers
    if ($servers[$Name]) {
        $servers[$Name] | Add-Member -NotePropertyName lastSeen -NotePropertyValue (Get-Date).ToString('o') -Force
        Save-PFServers $servers
        $Server = $servers[$Name]
    }

    $portSuffix = if ([int]$Server.port -ne 22) { ":$([int]$Server.port)" } else { '' }
    Write-Host ''
    Write-Host "🔐 $Name — authenticated connection info" -ForegroundColor Cyan
    Write-Host "   Status : $(Format-PFServerStatus $State $Server)" -ForegroundColor White
    Write-Host "   SSH    : $(Get-PFServerTarget $Server)$portSuffix" -ForegroundColor White
    if ($Server.addedAt) {
        try { Write-Host "   Added  : $(([datetime]$Server.addedAt).ToString('yyyy-MM-dd HH:mm'))" -ForegroundColor DarkGray } catch {}
    }
    if ($Server.lastSeen) {
        try { Write-Host "   Seen   : $(([datetime]$Server.lastSeen).ToString('yyyy-MM-dd HH:mm'))" -ForegroundColor DarkGray } catch {}
    }
    Write-Host ''
}
