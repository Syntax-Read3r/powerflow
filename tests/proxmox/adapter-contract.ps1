. (Join-Path $PSScriptRoot 'test-helpers.ps1')

function Get-PmxAdapterTokenFixture {
    param([Parameter(Mandatory)][string]$AdapterPath)

    . $AdapterPath
    $digest = 'a' * 40
    $fixture = [ordered]@{}
    $fixture['version'] = @(New-PmxManagementQueryTokens version @{}).Tokens
    $fixture['node-status'] = @(New-PmxManagementQueryTokens node-status @{ Node = 'pve1' }).Tokens
    $fixture['vm-config'] = @(New-PmxManagementQueryTokens vm-config @{ Vmid = 101; Node = 'pve1'; Current = $false }).Tokens
    $fixture['snapshot-list'] = @(New-PmxManagementQueryTokens snapshot-list @{ Vmid = 101; Node = 'pve1' }).Tokens
    $fixture['clone'] = @(New-PmxManagementChangeTokens vm-clone @{ SourceVmid = 9000; NewVmid = 101; Name = 'app-01'; Full = $true }).Tokens
    $fixture['cpu'] = @(New-PmxManagementChangeTokens vm-set-cpu @{ Vmid = 101; Cores = 4; Digest = $digest }).Tokens
    $fixture['memory'] = @(New-PmxManagementChangeTokens vm-set-memory @{ Vmid = 101; MemoryMiB = 4096; Digest = $digest }).Tokens
    $fixture['disk'] = @(New-PmxManagementChangeTokens vm-disk-grow @{ Vmid = 101; Disk = 'scsi0'; Size = '+16G'; Digest = $digest }).Tokens
    $fixture['start'] = @(New-PmxManagementChangeTokens vm-start @{ Vmid = 101 }).Tokens
    $fixture['shutdown'] = @(New-PmxManagementChangeTokens vm-shutdown @{ Vmid = 101 }).Tokens
    $fixture['snapshot'] = @(New-PmxManagementChangeTokens snapshot-create @{ Vmid = 101; Name = 'before_upgrade' }).Tokens
    return $fixture
}

$windowsPath = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'platform' 'windows' 'adapters' 'proxmox-management.ps1')).Path
$linuxPath = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'platform' 'linux' 'adapters' 'proxmox-management.ps1')).Path
$windows = Get-PmxAdapterTokenFixture $windowsPath
$linux = Get-PmxAdapterTokenFixture $linuxPath

Assert-PmxEqual $windows $linux 'Windows and Linux Proxmox management adapters produce different allow-listed tokens.'
Assert-PmxEqual @('qm', 'clone', '9000', '101', '--name', 'app-01', '--full', '1') $linux['clone'] `
    'Clone token sequence is incorrect.'
Assert-PmxEqual @('qm', 'disk', 'resize', '101', 'scsi0', '+16G', '--digest', ('a' * 40)) $linux['disk'] `
    'Disk-growth token sequence is incorrect.'
Assert-PmxEqual @('pvesh', 'get', '/nodes/pve1/qemu/101/config', '--output-format', 'json') $linux['vm-config'] `
    'Desired VM config query should not include --current.'

. $linuxPath
foreach ($bad in @(
    (New-PmxManagementQueryTokens node-status @{ Node = 'pve1;id' }),
    (New-PmxManagementQueryTokens vm-list @{ Command = 'id' }),
    (New-PmxManagementChangeTokens vm-clone @{ SourceVmid = 9000; NewVmid = 101; Name = 'app;id'; Full = $true }),
    (New-PmxManagementChangeTokens vm-disk-grow @{ Vmid = 101; Disk = 'scsi0;id'; Size = '+1G' }),
    (New-PmxManagementChangeTokens snapshot-create @{ Vmid = 101; Name = "snap`nname" }),
    (New-PmxManagementChangeTokens exec @{ Command = 'id' })
)) {
    Assert-PmxTest (-not $bad.Success) 'Management adapter accepted an unexpected or hostile operation/value.'
}
Write-PmxTestPass 'allow-listed local/SSH adapter token contract and hostile-input rejection'
