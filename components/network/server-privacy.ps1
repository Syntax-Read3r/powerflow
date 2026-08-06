# ==============================================================================
# PowerFlow — SSH Server Privacy and Invocation
# ==============================================================================
# Domain   : Network
# File     : components/network/server-privacy.ps1
# Purpose  : Keep saved SSH endpoints out of ordinary UI, construct native SSH
#            tokens centrally, and reveal details only after authentication
# Functions: Get-PFServerTarget, Format-PFServerPublicRow, Invoke-PFServerSsh,
#            Test-PFServerInteractiveAuth, Show-PFServerAuthenticatedInfo
# Depends  : ssh (client); Format-PFServerStatus, Get-PFServers, Save-PFServers
#            are resolved at runtime from components/network/servers.ps1
# ==============================================================================

# Endpoint construction belongs in one deliberately narrow place. It feeds native
# argv and the authenticated info view only — never a list, picker, error, or banner.
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
        [Parameter(Mandatory)]$Server,
        [switch]$AuthenticationOnly
    )

    $sshArgs = @('-p', "$([int]$Server.port)")
    if ($AuthenticationOnly) {
        # A constant remote no-op proves SSH authentication without opening a shell
        # or changing server state. Capture connection diagnostics so a failed info
        # request does not disclose the saved endpoint through PowerFlow's output.
        $sshArgs += @('-o', 'LogLevel=ERROR', '-o', 'RequestTTY=no')
    }
    $sshArgs += (Get-PFServerTarget $Server)

    if ($AuthenticationOnly) {
        $sshArgs += 'exit 0'
        $null = @(& ssh @sshArgs 2>&1)
        return ($LASTEXITCODE -eq 0)
    }

    & ssh @sshArgs
    return $LASTEXITCODE
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

    if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
        Write-Host '❌ No ssh client on this machine.' -ForegroundColor Red
        return
    }
    if (-not (Test-PFServerInteractiveAuth)) {
        Write-Host "❌ '$Name' info requires interactive SSH authentication; endpoint kept private." -ForegroundColor Red
        return
    }

    Write-Host "🔐 Authenticate to view '$Name' connection details." -ForegroundColor Cyan
    if (-not (Invoke-PFServerSsh -Server $Server -AuthenticationOnly)) {
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
