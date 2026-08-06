. (Join-Path $PSScriptRoot 'test-helpers.ps1')
. (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' 'shared.ps1')
. (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' 'vm-read.ps1')
. (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' 'disk-model.ps1')

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
    boot = 'order=scsi0;net0'
    scsi0 = 'local-lvm:vm-101-disk-0,size=32G'
    scsi1 = 'bulk-zfs:vm-101-disk-1,size=1.5T'
    scsi2 = 'bulk-zfs:vm-101-disk-2,size=unknown'
    ide2 = 'local:cloudinit,media=cdrom'
    sata0 = 'none,media=cdrom'
    efidisk0 = 'local-lvm:vm-101-disk-efi,size=4M'
    tpmstate0 = 'local-lvm:vm-101-disk-tpm,size=4M'
    unused0 = 'local-lvm:vm-101-disk-old'
    net0 = 'virtio=AA:BB:CC:DD:EE:FF,bridge=vmbr0'
}
$disks = @(Get-PmxVirtualDisksFromConfig $config)
Assert-PmxTest ($disks.Count -eq 3 -and $disks[0].Disk -ceq 'scsi0' -and $disks[0].SizeBytes -eq 32GB) `
    'VM disk parser did not isolate sized virtual disks.'
Assert-PmxTest ($disks[0].BootOrder -eq 1 -and $disks[0].Roles[0] -ceq 'boot' -and $disks[0].SizeDisplay -ceq '32 GiB') `
    'Modern boot order or exact size display was not modeled.'
Assert-PmxTest ($disks[1].Roles[0] -ceq 'data' -and $disks[1].SizeBytes -eq [long](1.5 * 1TB)) `
    'Fractional Proxmox size or data role was not modeled.'
$growable = @(Get-PmxGrowableVirtualDisks $config)
Assert-PmxTest ($growable.Count -eq 2 -and $growable.Disk -notcontains 'scsi2') `
    'Malformed, EFI, TPM, unused, cloud-init, or CD-ROM media entered automatic selection.'
$legacy = @(Get-PmxVirtualDisksFromConfig ([pscustomobject]@{ bootdisk = 'virtio0'; virtio0 = 'local:vm-9-disk-0,size=8G' }))
Assert-PmxTest ($legacy[0].BootOrder -eq 1 -and $legacy[0].Roles[0] -ceq 'boot') `
    'Legacy bootdisk configuration was not modeled.'
Write-PmxTestPass 'VM inventory, unique resolution, and virtual-disk parsing'
