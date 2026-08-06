. (Join-Path $PSScriptRoot 'test-helpers.ps1')

$script:pmxTestRoot = Join-Path ([IO.Path]::GetTempPath()) "powerflow-pmx-test-$([Guid]::NewGuid().ToString('N'))"
function Get-PowerFlowConfigPath { return (Join-Path $script:pmxTestRoot 'config') }
function Get-PowerFlowDataPath { return (Join-Path $script:pmxTestRoot 'data') }
function Test-ProxmoxSupport { return $false }
$script:servers = @{
    proxmox = [pscustomobject]@{ user = 'root'; host = 'pve.example.test'; port = 22 }
}
function Get-PFServers { return $script:servers }

. (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' 'shared.ps1')
. (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' 'config.ps1')

try {
    $defaults = Get-PmxConfig
    Assert-PmxTest (-not $defaults.LoadError -and $defaults.Transport -ceq 'auto') `
        'PMX defaults did not load from an empty configuration directory.'
    Assert-PmxTest (-not (ConvertTo-PmxConfigValue Host 'root@host').Success) `
        'Host configuration accepted a target instead of a saved srv alias.'
    Assert-PmxTest (-not (ConvertTo-PmxConfigValue TimeoutSeconds '4').Success) `
        'Timeout below the documented safety floor was accepted.'

    Assert-PmxTest (Set-PmxConfigSetting transport ssh).Success 'Could not persist SSH transport.'
    Assert-PmxTest (Set-PmxConfigSetting host proxmox).Success 'Could not persist saved host alias.'
    $saved = Get-PmxConfig
    Assert-PmxTest ($saved.Transport -ceq 'ssh' -and $saved.Host -ceq 'proxmox') `
        'PMX configuration did not survive a JSON round trip.'

    $connection = Resolve-PmxManagementConnection -Config $saved
    Assert-PmxTest ($connection.Success -and $connection.Connection.Target -ceq 'root@pve.example.test' -and
        $connection.Connection.Port -eq 22) 'Saved srv alias did not resolve to the expected SSH connection.'

    $script:servers.proxmox = [pscustomobject]@{ user = 'root'; host = 'pve.example.test;id'; port = 22 }
    Assert-PmxTest (-not (Resolve-PmxManagementConnection -Config $saved).Success) `
        'Hostile saved server data was accepted as an SSH target.'

    Write-PmxAuditRecord -Operation vm-start -Target proxmox -Outcome dry-run -Message "validated`npreview" `
        -VmId 101 -DryRun -Config $saved
    $record = Get-Content (Get-PmxAuditFile) -Raw | ConvertFrom-Json
    Assert-PmxTest ($record.operation -ceq 'vm-start' -and $record.target -ceq 'proxmox' -and
        $record.dryRun -and $record.message -ceq 'validated preview') `
        'Audit record was not valid, sanitized JSONL metadata.'
    Write-PmxTestPass 'non-secret config persistence, saved-SSH resolution, and audit records'
}
finally {
    if (Test-Path -LiteralPath $script:pmxTestRoot) {
        Remove-Item -LiteralPath $script:pmxTestRoot -Recurse -Force
    }
}
