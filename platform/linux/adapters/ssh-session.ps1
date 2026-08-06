# ============================================================================== 
# PowerFlow — Private SSH Session Adapter (Linux)
# ============================================================================== 
# Domain   : Platform / Linux
# File     : platform/linux/adapters/ssh-session.ps1
# Purpose  : Run alias-private OpenSSH authentication and interactive sessions
# Contract : Invoke-PFPrivateSshSession, Get-PFPrivateSshSessionResult
# Depends  : OpenSSH client, chmod, locations adapter
# ============================================================================== 

function Get-PFPrivateSshAskPassPath {
    $source = Join-Path (Split-Path $PSScriptRoot -Parent) 'helpers/powerflow-ssh-askpass.sh'
    if (-not (Test-Path -LiteralPath $source)) { return $null }

    $cache = Join-Path (Get-PowerFlowDataPath) 'helpers'
    $helper = Join-Path $cache 'powerflow-ssh-askpass'
    try {
        if (-not (Test-Path -LiteralPath $cache)) {
            New-Item -ItemType Directory -Path $cache -Force | Out-Null
        }
        if (-not (Test-Path -LiteralPath $helper) -or
            (Get-Item -LiteralPath $source).LastWriteTimeUtc -gt (Get-Item -LiteralPath $helper).LastWriteTimeUtc) {
            Copy-Item -LiteralPath $source -Destination $helper -Force
        }
        # Askpass handles a live credential. Never inherit permissive archive/mount
        # modes that could let another local user replace or read the helper.
        & chmod 700 -- $helper
        if ($LASTEXITCODE -ne 0) { return $null }
        return $helper
    }
    catch { return $null }
}

function Get-PFPrivateSshSessionResult {
    if ($script:PFPrivateSshLastResult) { return $script:PFPrivateSshLastResult }
    return [pscustomobject]@{ Success = $false; FailureKind = 'not-run'; ExitCode = $null }
}

function Invoke-PFPrivateSshSession {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Server,
        [switch]$AuthenticationOnly
    )

    $ssh = Get-Command 'ssh' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $ssh) {
        $script:PFPrivateSshLastResult = [pscustomobject]@{ Success = $false; FailureKind = 'client-missing'; ExitCode = $null }
        return
    }
    $askPass = Get-PFPrivateSshAskPassPath
    if (-not $askPass) {
        $script:PFPrivateSshLastResult = [pscustomobject]@{ Success = $false; FailureKind = 'prompt-unavailable'; ExitCode = $null }
        return
    }

    $target = "$($Server.user)@$($Server.host)"
    $arguments = @(
        '-q', '-p', "$([int]$Server.port)",
        '-o', "HostKeyAlias=$Name",
        '-o', 'StrictHostKeyChecking=accept-new',
        '-o', 'NumberOfPasswordPrompts=3',
        $target
    )
    if ($AuthenticationOnly) {
        $arguments += @('-o', 'RequestTTY=no', 'exit 0')
    }

    $names = @('SSH_ASKPASS', 'SSH_ASKPASS_REQUIRE', 'DISPLAY', 'POWERFLOW_SRV_ALIAS')
    $previous = @{}
    foreach ($variable in $names) {
        $previous[$variable] = [Environment]::GetEnvironmentVariable($variable, 'Process')
    }
    try {
        [Environment]::SetEnvironmentVariable('SSH_ASKPASS', $askPass, 'Process')
        [Environment]::SetEnvironmentVariable('SSH_ASKPASS_REQUIRE', 'force', 'Process')
        [Environment]::SetEnvironmentVariable('DISPLAY', 'powerflow', 'Process')
        [Environment]::SetEnvironmentVariable('POWERFLOW_SRV_ALIAS', $Name, 'Process')
        & $ssh.Source @arguments
        $code = $LASTEXITCODE
    }
    catch { $code = $null }
    finally {
        foreach ($variable in $names) {
            [Environment]::SetEnvironmentVariable($variable, $previous[$variable], 'Process')
        }
    }

    $script:PFPrivateSshLastResult = [pscustomobject]@{
        Success     = ($code -eq 0)
        FailureKind = if ($code -eq 0) { '' } elseif ($null -eq $code) { 'launch-failed' } else { 'connection-failed' }
        ExitCode    = $code
    }
}
