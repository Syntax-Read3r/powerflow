. (Join-Path $PSScriptRoot 'test-helpers.ps1')
. (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' 'shared.ps1')
. (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' 'vm-read.ps1')

$script:inventory = @(
    [pscustomobject]@{ type = 'qemu'; vmid = 101; name = "app$([char]27)[31m-one"; node = 'pve1'; status = 'running'; template = 0 },
    [pscustomobject]@{ type = 'qemu'; vmid = 102; name = 'duplicate'; node = 'pve1'; status = 'stopped'; template = 0 },
    [pscustomobject]@{ type = 'qemu'; vmid = 103; name = 'DUPLICATE'; node = 'pve2'; status = 'stopped'; template = 0 },
    [pscustomobject]@{ type = 'lxc'; vmid = 200; name = 'container'; node = 'pve1'; status = 'running'; template = 0 }
)
function Invoke-ProxmoxManagementQuery {
    return [pscustomobject]@{ Success = $true; Data = $script:inventory; Error = ''; ExitCode = 0; NativeCommand = 'fixture' }
}
$session = [pscustomobject]@{ Connection = [pscustomobject]@{} }
$rows = Get-PmxManagedVmRows -Session $session
Assert-PmxTest ($rows.Success -and $rows.Vms.Count -eq 3) 'VM inventory did not filter non-QEMU resources.'
Assert-PmxTest ($rows.Vms[0].Name -ceq 'app-one') 'VM display text was not sanitized.'
Assert-PmxTest ((Resolve-PmxManagedVm -Selector '101' -Session $session).Vm.VmId -eq 101) `
    'Authoritative VMID resolution failed.'
$ambiguous = Resolve-PmxManagedVm -Selector 'duplicate' -Session $session
Assert-PmxTest (-not $ambiguous.Success -and $ambiguous.Error -match 'ambiguous') `
    'Ambiguous friendly VM names must require a VMID.'

$config = [pscustomobject]@{
    scsi0 = 'local-lvm:vm-101-disk-0,size=32G'
    ide2 = 'local:cloudinit,media=cdrom'
    net0 = 'virtio=AA:BB:CC:DD:EE:FF,bridge=vmbr0'
}
$disks = @(Get-PmxVirtualDisksFromConfig $config)
Assert-PmxTest ($disks.Count -eq 1 -and $disks[0].Disk -ceq 'scsi0' -and $disks[0].SizeBytes -eq 32GB) `
    'VM disk parser did not isolate a sized data disk.'
Write-PmxTestPass 'VM inventory, unique resolution, and virtual-disk parsing'
