. (Join-Path $PSScriptRoot 'test-helpers.ps1')
. (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' 'shared.ps1')
. (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' 'vm-read.ps1')
. (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' 'disk-model.ps1')
. (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' 'clone-plan.ps1')
. (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' 'vm-change.ps1')
. (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' 'disk-grow.ps1')

$script:storageRows = @(
    [pscustomobject]@{ storage = 'local-zfs'; enabled = 1; active = 1; avail = 1TB },
    [pscustomobject]@{ storage = 'bulk-zfs'; enabled = 1; active = 1; avail = 4TB }
)
function Invoke-ProxmoxManagementQuery {
    param([string]$Operation, $Connection, [hashtable]$Parameters)
    if ($Operation -eq 'storage-list') { return [pscustomobject]@{ Success = $true; Data = $script:storageRows; Error = '' } }
    throw "Unexpected fixture query: $Operation"
}

$session = [pscustomobject]@{ Connection = [pscustomobject]@{}; Node = 'pve' }
$vm = [pscustomobject]@{ VmId = 100; Name = 'debian13-base'; Node = 'pve'; Template = $true }
$config = [pscustomobject]@{
    digest = ('a' * 40); boot = 'order=scsi0;net0'
    scsi0 = 'local-zfs:vm-100-disk-0,size=32G'
    scsi1 = 'bulk-zfs:vm-100-disk-1,size=100G'
}
$details = [pscustomobject]@{ Vm = $vm; Disks = @(Get-PmxVirtualDisksFromConfig $config) }
$diskJson = $details.Disks | ConvertTo-Json -Depth 8 -Compress
Assert-PmxTest ($diskJson -match '"Disk":"scsi0"' -and $diskJson -match '"SizeBytes":34359738368' -and
    $diskJson -match '"Roles":\["boot"\]' -and $diskJson -match '"BootOrder":1' -and
    $diskJson -match '"SizeDisplay":"32 GiB"') 'Additive virtual-disk JSON fields drifted or replaced existing properties.'
$clone = New-PmxClonePlan -Session $session -SourceDetails $details -TargetVmId 102 -TargetName 'docker-host'
Assert-PmxTest ($clone.Success -and $clone.Plan.Disks.Count -eq 2) 'Multi-storage clone plan was not built.'
Assert-PmxTest ($clone.Plan.PlacementPolicy -ceq 'same-as-source' -and $clone.Plan.ProvisionedBytes -eq 132GB) `
    'Clone placement policy or provisioned capacity is incorrect.'
Assert-PmxTest ($clone.Plan.Disks[1].TargetStorage -ceq 'bulk-zfs' -and $clone.Plan.Disks[0].Roles[0] -ceq 'boot') `
    'Clone per-disk storage or role was lost.'
$changedPlan = $clone.Plan.PSObject.Copy()
$changedPlan.Disks = @($clone.Plan.Disks | ForEach-Object { $_.PSObject.Copy() })
$changedPlan.Disks[0].AvailableBytes--
Assert-PmxTest (-not (Test-PmxClonePlanIdentity -Expected $clone.Plan -Actual $changedPlan)) `
    'Clone plan identity ignored changed storage capacity.'

$dryMutation = [pscustomobject]@{ Success = $true; Executed = $false; DryRun = $true }
$contract = ConvertTo-PmxCloneContract -Plan $clone.Plan -Mutation $dryMutation
$json = $contract | ConvertTo-Json -Depth 12 -Compress
Assert-PmxTest ($json -match '"operation":"clone"' -and $json -match '"dry_run":true' -and $json -match '"result":null') `
    'Clone dry-run JSON did not separate plan and result.'
Assert-PmxTest ($json -match '"size_bytes":34359738368' -and $json -match '"target_storage":"bulk-zfs"') `
    'Clone JSON omitted exact bytes or per-disk target storage.'
$verifiedMutation = [pscustomobject]@{ Success = $true; Executed = $true; DryRun = $false }
$verifiedContract = ConvertTo-PmxCloneContract -Plan $clone.Plan -Mutation $verifiedMutation `
    -VerifiedTarget ([pscustomobject]@{ VmId = 102; Name = 'docker-host'; Node = 'pve' })
$verifiedJson = $verifiedContract | ConvertTo-Json -Depth 12 -Compress
Assert-PmxTest ($verifiedJson -match '"verified":true' -and $verifiedJson -match '"result":\{"vmid":102') `
    'Verified clone JSON did not preserve the plan and add a separate result.'

$disk = $details.Disks[0]
$target = ConvertFrom-PmxSize -Value '100GiB' -Kind disk
$growth = New-PmxDiskGrowthPlan -Session $session -Vm ([pscustomobject]@{ VmId=102; Name='docker-host'; Node='pve' }) `
    -Config $config -Disk $disk -Target $target
Assert-PmxTest ($growth.Success -and $growth.Plan.CurrentBytes -eq 32GB -and $growth.Plan.DeltaBytes -eq 68GB) `
    'Disk growth did not calculate current and delta from exact bytes.'
Assert-PmxTest ($growth.Plan.NativeDelta -ceq '+68G' -and $growth.Plan.TargetDisplay -ceq '100 GiB') `
    'Disk growth native delta or IEC target display is wrong.'
$same = New-PmxDiskGrowthPlan -Session $session -Vm ([pscustomobject]@{ VmId=102; Name='docker-host'; Node='pve' }) `
    -Config $config -Disk $disk -Target (ConvertFrom-PmxSize -Value '32GiB')
Assert-PmxTest ($same.Success -and $same.NoOp) 'Equal disk target is not an idempotent no-op.'
$shrink = New-PmxDiskGrowthPlan -Session $session -Vm ([pscustomobject]@{ VmId=102; Name='docker-host'; Node='pve' }) `
    -Config $config -Disk $disk -Target (ConvertFrom-PmxSize -Value '16GiB')
Assert-PmxTest (-not $shrink.Success -and $shrink.Error -match 'cannot be shrunk') 'Disk shrink was not rejected.'

$rendered = (@(& { Show-PmxClonePlacement -Plan $clone.Plan } 6>&1 | ForEach-Object { "$_" }) -join "`n")
Assert-PmxTest ($rendered -match 'SOURCE DISK\s+ROLE\s+SOURCE STORAGE\s+TARGET STORAGE\s+PROVISIONED\s+AVAILABLE') `
    'Clone placement table headings drifted.'
Assert-PmxTest ($rendered -match 'scsi0\s+boot\s+local-zfs\s+local-zfs\s+32 GiB') `
    'Clone placement table omitted boot role, placement, or IEC size.'
$diskTable = (@(& { Show-PmxVirtualDiskTable -Disks $details.Disks } 6>&1 | ForEach-Object { "$_" }) -join "`n")
Assert-PmxTest ($diskTable -match 'DISK\s+ROLE\s+SIZE\s+STORAGE\s+BACKING' -and
    $diskTable -match 'scsi0\s+boot\s+32 GiB\s+local-zfs') 'Virtual-disk table contract drifted.'
$ambiguous = (@(& { Show-PmxGrowableDiskChoices -Vm ([pscustomobject]@{ VmId = 102 }) -Disks $details.Disks -Target '3TiB' } 6>&1 | ForEach-Object { "$_" }) -join "`n")
Assert-PmxTest ($ambiguous -match 'more than one eligible growable disk' -and
    $ambiguous -match 'pmx disk grow 102 <disk> 3TiB' -and
    $ambiguous -match 'pmx disk grow --vm 102 --disk <disk> --to 3TiB') `
    'Ambiguous automatic disk selection did not fail with both explicit retry forms.'
Write-PmxTestPass 'exact disk units, growth planning, clone placement, and JSON contracts'
