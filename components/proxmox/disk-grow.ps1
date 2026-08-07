# ==============================================================================
# PowerFlow — Proxmox Virtual Disk Growth
# ==============================================================================
# Domain   : Proxmox
# File     : components/proxmox/disk-grow.ps1
# Purpose  : Parse, plan, preview, revalidate, execute, and verify disk growth
# Functions: Get-PmxDiskGrowInvocation, New-PmxDiskGrowthPlan,
#            Test-PmxDiskGrowthPlanIdentity, Show-PmxGrowableDiskChoices,
#            Invoke-PmxVmDiskGrow
# Depends  : shared.ps1, disk-model.ps1, vm-read.ps1, vm-change.ps1, adapter
# ==============================================================================

function Get-PmxDiskGrowInvocation {
    param([object[]]$Arguments = @())

    $parsed = ConvertFrom-PmxArguments -Arguments $Arguments `
        -ValueOptions @{ 'vm' = 'Vm'; 'disk' = 'Disk'; 'to' = 'Target' } `
        -SwitchOptions (Get-PmxGlobalSwitchMap) -MaxPositionals 3
    if (-not $parsed.Success) { return $parsed }

    $namedCount = @(@('Vm', 'Disk', 'Target') | Where-Object { $parsed.Options.ContainsKey($_) }).Count
    if ($namedCount -gt 0) {
        if ($namedCount -ne 3 -or $parsed.Positionals.Count -ne 0) {
            return [pscustomobject]@{ Success = $false; Options = $parsed.Options; Positionals = $parsed.Positionals; Error = 'use all of --vm, --disk, and --to together; do not mix named and positional selectors' }
        }
        $parsed.Options['AutoSelect'] = $false
        return $parsed
    }
    if ($parsed.Positionals.Count -eq 2) {
        $parsed.Options['Vm'] = $parsed.Positionals[0]
        $parsed.Options['Target'] = $parsed.Positionals[1]
        $parsed.Options['AutoSelect'] = $true
        return $parsed
    }
    if ($parsed.Positionals.Count -eq 3) {
        $parsed.Options['Vm'] = $parsed.Positionals[0]
        $parsed.Options['Disk'] = $parsed.Positionals[1]
        $parsed.Options['Target'] = $parsed.Positionals[2]
        $parsed.Options['AutoSelect'] = $false
        return $parsed
    }
    return [pscustomobject]@{ Success = $false; Options = $parsed.Options; Positionals = $parsed.Positionals; Error = 'use: pmx disk grow <vm> <size>, pmx disk grow <vm> <disk> <size>, or the complete --vm/--disk/--to form' }
}

function Get-PmxDiskStorageCapacity {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$Node,
        [Parameter(Mandatory)][string]$Storage
    )
    $result = Invoke-ProxmoxManagementQuery -Operation 'storage-list' -Connection $Session.Connection -Parameters @{ Node = $Node }
    if (-not $result.Success) { return [pscustomobject]@{ Success = $false; AvailableBytes = 0L; Error = "could not verify storage capacity: $($result.Error)" } }
    $row = @($result.Data | Where-Object { "$(Get-PmxObjectProperty $_ 'storage' '')" -ceq $Storage }) | Select-Object -First 1
    if (-not $row -or (Get-PmxObjectProperty $row 'enabled' 1) -ne 1 -or (Get-PmxObjectProperty $row 'active' 1) -ne 1) {
        return [pscustomobject]@{ Success = $false; AvailableBytes = 0L; Error = "storage '$Storage' is not active for VM images" }
    }
    return [pscustomobject]@{ Success = $true; AvailableBytes = [long](Get-PmxObjectProperty $row 'avail' 0); Error = '' }
}

function New-PmxDiskGrowthPlan {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)]$Vm,
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)]$Disk,
        [Parameter(Mandatory)]$Target
    )

    if ($Target.Bytes -lt $Disk.SizeBytes) {
        return [pscustomobject]@{ Success = $false; Plan = $null; NoOp = $false; Error = 'virtual disks cannot be shrunk; choose a target larger than the current size' }
    }
    if ($Target.Bytes -eq $Disk.SizeBytes) {
        return [pscustomobject]@{ Success = $true; Plan = $null; NoOp = $true; Error = '' }
    }
    $delta = [long]($Target.Bytes - $Disk.SizeBytes)
    if ($delta % 1MB -ne 0) {
        return [pscustomobject]@{ Success = $false; Plan = $null; NoOp = $false; Error = 'the requested growth cannot be represented exactly in MiB' }
    }
    $digest = Get-PmxConfigDigest $Config
    if (-not $digest) {
        return [pscustomobject]@{ Success = $false; Plan = $null; NoOp = $false; Error = 'Proxmox did not return a configuration digest; refusing a race-prone resize' }
    }
    $capacity = Get-PmxDiskStorageCapacity -Session $Session -Node "$($Vm.Node)" -Storage $Disk.Storage
    if (-not $capacity.Success) { return [pscustomobject]@{ Success = $false; Plan = $null; NoOp = $false; Error = $capacity.Error } }
    if ($capacity.AvailableBytes -lt $delta) {
        return [pscustomobject]@{ Success = $false; Plan = $null; NoOp = $false; Error = "storage '$($Disk.Storage)' has $(Format-PmxBytes $capacity.AvailableBytes) available; growth requires $(Format-PmxBytes $delta)" }
    }
    $nativeDelta = if ($delta % 1GB -eq 0) { "+$([long]($delta / 1GB))G" } else { "+$([long]($delta / 1MB))M" }
    return [pscustomobject]@{
        Success = $true; NoOp = $false; Error = ''
        Plan = [pscustomobject]@{
            VmId = [int]$Vm.VmId; VmName = $Vm.Name; Node = $Vm.Node; Disk = $Disk.Disk
            Roles = [string[]]$Disk.Roles; Backing = $Disk.Backing; Storage = $Disk.Storage
            CurrentBytes = [long]$Disk.SizeBytes; TargetBytes = [long]$Target.Bytes; DeltaBytes = $delta
            CurrentDisplay = $Disk.SizeDisplay; TargetDisplay = Format-PmxBytes $Target.Bytes
            DeltaDisplay = Format-PmxBytes $delta; AvailableBytes = [long]$capacity.AvailableBytes
            AvailableDisplay = Format-PmxBytes $capacity.AvailableBytes; NativeDelta = $nativeDelta; Digest = $digest
        }
    }
}

function Test-PmxDiskGrowthPlanIdentity {
    param([Parameter(Mandatory)]$Expected, [Parameter(Mandatory)]$Actual)
    foreach ($property in @('VmId','VmName','Node','Disk','Backing','Storage','CurrentBytes','TargetBytes','DeltaBytes','AvailableBytes','NativeDelta','Digest')) {
        if ("$($Expected.$property)" -cne "$($Actual.$property)") { return $false }
    }
    return $true
}

function Show-PmxGrowableDiskChoices {
    param([Parameter(Mandatory)]$Vm, [Parameter(Mandatory)][object[]]$Disks, [Parameter(Mandatory)][string]$Target)
    Write-Host "❌ VM $($Vm.VmId) has more than one eligible growable disk; choose one explicitly." -ForegroundColor Red
    Write-Host ''
    Show-PmxVirtualDiskTable -Disks $Disks
    Write-Host ''
    Write-Host "  Retry: pmx disk grow $($Vm.VmId) <disk> $Target" -ForegroundColor DarkGray
    Write-Host "         pmx disk grow --vm $($Vm.VmId) --disk <disk> --to $Target" -ForegroundColor DarkGray
}

function Invoke-PmxVmDiskGrow {
    param([object[]]$Arguments = @())

    if (@($Arguments | Where-Object { "$_" -eq '--help' }).Count) { Show-PmxTopicHelp 'disk grow'; return }
    $parsed = Get-PmxDiskGrowInvocation -Arguments $Arguments
    if (-not $parsed.Success) { Write-Host "❌ $($parsed.Error)" -ForegroundColor Red; return }
    if ($parsed.Options.Disk -and "$($parsed.Options.Disk)" -cnotmatch '^(ide|sata|scsi|virtio)[0-9]+$') {
        Write-Host '❌ Disk must be an exact Proxmox VM disk such as scsi0.' -ForegroundColor Red; return
    }
    $target = ConvertFrom-PmxSize -Value "$($parsed.Options.Target)" -Kind disk
    if (-not $target.Success) { Write-Host "❌ $($target.Error)" -ForegroundColor Red; return }
    $session = Get-PmxManagementSession
    if (-not $session.Success) { Write-PmxDisconnectedState -Session $session; return }
    $resolved = Resolve-PmxManagedVm -Selector "$($parsed.Options.Vm)" -Session $session
    if (-not $resolved.Success) { Write-Host "❌ $($resolved.Error)" -ForegroundColor Red; return }
    if ($resolved.Vm.Template) { Write-Host '❌ Clone the template before growing a virtual disk.' -ForegroundColor Red; return }
    $desired = Get-PmxDesiredVmConfig -Session $session -Vm $resolved.Vm
    if (-not $desired.Success) { Write-Host "❌ $($desired.Error)" -ForegroundColor Red; return }
    $disks = @(Get-PmxGrowableVirtualDisks -Config $desired.Config)
    if (-not $disks.Count) { Write-Host '❌ No growable VM disk has a trustworthy size, storage, and backing identity.' -ForegroundColor Red; return }

    if ($parsed.Options.AutoSelect) {
        if ($disks.Count -ne 1) { Show-PmxGrowableDiskChoices -Vm $resolved.Vm -Disks $disks -Target "$($parsed.Options.Target)"; return }
        $disk = $disks[0]
    }
    else {
        $selected = @($disks | Where-Object Disk -ceq "$($parsed.Options.Disk)")
        if ($selected.Count -ne 1) { Write-Host "❌ Disk '$($parsed.Options.Disk)' was not found with a trustworthy size, storage, and backing identity." -ForegroundColor Red; return }
        $disk = $selected[0]
    }

    $planned = New-PmxDiskGrowthPlan -Session $session -Vm $resolved.Vm -Config $desired.Config -Disk $disk -Target $target
    if (-not $planned.Success) { Write-Host "❌ $($planned.Error)" -ForegroundColor Red; return }
    if ($planned.NoOp) { Write-Host "✅ $($disk.Disk) is already $(Format-PmxBytes $target.Bytes); nothing changed." -ForegroundColor Green; return }
    $plan = $planned.Plan
    $parameters = @{ Vmid = $plan.VmId; Disk = $plan.Disk; Size = $plan.NativeDelta; Digest = $plan.Digest }
    $snapshot = $resolved.Vm
    $revalidate = {
        $freshVm = Resolve-PmxManagedVm -Selector "$($snapshot.VmId)" -Session $session
        if (-not $freshVm.Success -or -not (Test-PmxVmSnapshotIdentity $snapshot $freshVm.Vm)) { return [pscustomobject]@{ Success = $false; Error = 'VM identity changed after confirmation' } }
        $freshConfig = Get-PmxDesiredVmConfig -Session $session -Vm $freshVm.Vm
        if (-not $freshConfig.Success) { return [pscustomobject]@{ Success = $false; Error = $freshConfig.Error } }
        $freshDisk = @(Get-PmxGrowableVirtualDisks -Config $freshConfig.Config | Where-Object Disk -ceq $plan.Disk)
        if ($freshDisk.Count -ne 1) { return [pscustomobject]@{ Success = $false; Error = 'VM disk identity changed after confirmation' } }
        $freshPlan = New-PmxDiskGrowthPlan -Session $session -Vm $freshVm.Vm -Config $freshConfig.Config -Disk $freshDisk[0] -Target $target
        if (-not $freshPlan.Success -or $freshPlan.NoOp -or -not (Test-PmxDiskGrowthPlanIdentity -Expected $plan -Actual $freshPlan.Plan)) {
            return [pscustomobject]@{ Success = $false; Error = 'VM disk identity, size, configuration, or storage capacity changed after confirmation' }
        }
        return [pscustomobject]@{ Success = $true; Error = ''; Parameters = @{ Vmid = $plan.VmId; Disk = $plan.Disk; Size = $plan.NativeDelta; Digest = $freshPlan.Plan.Digest } }
    }.GetNewClosure()
    $verify = {
        $freshConfig = Get-PmxDesiredVmConfig -Session $session -Vm $snapshot
        $freshDisk = if ($freshConfig.Success) { @(Get-PmxVirtualDisksFromConfig -Config $freshConfig.Config | Where-Object Disk -ceq $plan.Disk) } else { @() }
        if ($freshDisk.Count -ne 1 -or $freshDisk[0].SizeBytes -lt $plan.TargetBytes) { return [pscustomobject]@{ Success = $false; Error = 'the target disk size was not returned' } }
        return [pscustomobject]@{ Success = $true; Error = ''; Message = "VM $($plan.VmId) disk $($plan.Disk) grew to $(Format-PmxBytes $freshDisk[0].SizeBytes)." }
    }.GetNewClosure()
    $fields = [ordered]@{
        VM = $plan.VmName; VMID = $plan.VmId; Disk = $plan.Disk; Role = Format-PmxVirtualDiskRole $plan.Roles
        Current = $plan.CurrentDisplay; Target = $plan.TargetDisplay; Growth = $plan.DeltaDisplay
        Storage = $plan.Storage; Backing = $plan.Backing; Available = $plan.AvailableDisplay
    }
    $warnings = @()
    if ($session.Config.Explain -or $parsed.Options.ContainsKey('Explain')) {
        $warnings += 'The target is the final virtual-disk size; PowerFlow computes the native positive delta from exact configured bytes.'
        $warnings += 'Available is the current Proxmox storage API value, not guaranteed thin-pool allocation.'
    }
    $warnings += 'This enlarges the virtual disk only; grow the partition and filesystem separately inside the guest.'
    $null = Invoke-PmxAmberMutation -Session $session -Operation 'vm-disk-grow' -Parameters $parameters `
        -Title 'GROW VM DISK' -Fields $fields -Warnings $warnings -Options $parsed.Options -Revalidate $revalidate -Verify $verify -VmId "$($plan.VmId)"
}
