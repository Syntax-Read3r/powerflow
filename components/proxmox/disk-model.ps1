# ==============================================================================
# PowerFlow — Proxmox Virtual Disk Model
# ==============================================================================
# Domain   : Proxmox
# File     : components/proxmox/disk-model.ps1
# Purpose  : Parse exact virtual-disk identity, size, storage, and boot roles
# Functions: Get-PmxConfiguredBootOrder, Get-PmxVirtualDisksFromConfig,
#            Get-PmxGrowableVirtualDisks, Format-PmxVirtualDiskRole,
#            Show-PmxVirtualDiskTable
# Depends  : shared.ps1
# ==============================================================================

function Get-PmxConfiguredBootOrder {
    param([Parameter(Mandatory)]$Config)

    $boot = "$(Get-PmxObjectProperty $Config 'boot' '')"
    if ($boot -match '(?:^|,)order=([^,]+)') {
        return @($matches[1] -split ';' | Where-Object { $_ -match '^(ide|sata|scsi|virtio)\d+$' })
    }

    $legacy = "$(Get-PmxObjectProperty $Config 'bootdisk' '')"
    if ($legacy -match '^(ide|sata|scsi|virtio)\d+$') { return @($legacy) }
    return @()
}

function Format-PmxVirtualDiskRole {
    param([string[]]$Roles = @())
    if (@($Roles) -ccontains 'boot') { return 'boot' }
    return 'data'
}

function Get-PmxVirtualDisksFromConfig {
    param([Parameter(Mandatory)]$Config)

    $bootOrder = @(Get-PmxConfiguredBootOrder -Config $Config)
    $disks = @()
    foreach ($property in $Config.PSObject.Properties) {
        if ($property.Name -notmatch '^(ide|sata|scsi|virtio)\d+$') { continue }
        $raw = "$($property.Value)"
        if ($raw -match '(^|,)media=cdrom(,|$)' -or $raw -match '(^|,)cloudinit(,|$)') { continue }

        $sizeText = ''
        $sizeBytes = 0L
        if ($raw -match '(?:^|,)size=([^,]+)') {
            $sizeText = $matches[1]
            $parsedSize = ConvertFrom-PmxProxmoxSize $sizeText
            if ($parsedSize.Success) { $sizeBytes = $parsedSize.Bytes }
        }

        $backing = ($raw -split ',')[0]
        $storage = if ($backing -match '^([^:]+):') { $matches[1] } else { '' }
        $bootIndex = [array]::IndexOf($bootOrder, $property.Name)
        $roles = if ($bootIndex -ge 0) { @('boot') } else { @('data') }
        $disks += [pscustomobject]@{
            Disk        = $property.Name
            Storage     = ConvertTo-PmxDisplayText $storage
            Backing     = ConvertTo-PmxDisplayText $backing
            Size        = ConvertTo-PmxDisplayText $sizeText
            SizeBytes   = $sizeBytes
            Raw         = ConvertTo-PmxDisplayText $raw
            Roles       = [string[]]$roles
            BootOrder   = if ($bootIndex -ge 0) { $bootIndex + 1 } else { $null }
            SizeMiB     = if ($sizeBytes -gt 0) { [decimal]$sizeBytes / [decimal]1MB } else { [decimal]0 }
            SizeGiB     = if ($sizeBytes -gt 0) { [decimal]$sizeBytes / [decimal]1GB } else { [decimal]0 }
            SizeDisplay = if ($sizeBytes -gt 0) { Format-PmxBytes $sizeBytes } else { ConvertTo-PmxDisplayText $sizeText }
        }
    }
    return @($disks | Sort-Object Disk)
}

function Get-PmxGrowableVirtualDisks {
    param([Parameter(Mandatory)]$Config)
    return @(Get-PmxVirtualDisksFromConfig -Config $Config | Where-Object {
        $_.SizeBytes -gt 0 -and $_.Storage -and $_.Backing -and $_.Backing -notmatch '^(none|unused)'
    })
}

function Show-PmxVirtualDiskTable {
    param([Parameter(Mandatory)][object[]]$Disks)
    Write-Host ('  {0,-9} {1,-6} {2,10}  {3,-14} {4}' -f 'DISK', 'ROLE', 'SIZE', 'STORAGE', 'BACKING') -ForegroundColor DarkGray
    foreach ($disk in @($Disks)) {
        Write-Host ('  {0,-9} {1,-6} {2,10}  {3,-14} {4}' -f $disk.Disk,
            (Format-PmxVirtualDiskRole $disk.Roles), $disk.SizeDisplay, $disk.Storage, $disk.Backing) -ForegroundColor White
    }
}
