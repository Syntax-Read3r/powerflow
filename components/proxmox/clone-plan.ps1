# ==============================================================================
# PowerFlow — Proxmox Clone Planning
# ==============================================================================
# Domain   : Proxmox
# File     : components/proxmox/clone-plan.ps1
# Purpose  : Build, compare, and render full-clone storage placement plans
# Functions: New-PmxClonePlan, Test-PmxClonePlanIdentity, Show-PmxClonePlacement,
#            ConvertTo-PmxCloneContract
# Depends  : shared.ps1, disk-model.ps1, vm-read.ps1, management adapter
# ==============================================================================

function New-PmxClonePlan {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)]$SourceDetails,
        [Parameter(Mandatory)][int]$TargetVmId,
        [Parameter(Mandatory)][string]$TargetName
    )

    if (-not $SourceDetails.Disks.Count) {
        return [pscustomobject]@{ Success = $false; Plan = $null; Error = 'the source has no sized VM disk to clone' }
    }
    $node = if ($SourceDetails.Vm.Node) { "$($SourceDetails.Vm.Node)" } else { "$($Session.Node)" }
    $storageResult = Invoke-ProxmoxManagementQuery -Operation 'storage-list' -Connection $Session.Connection `
        -Parameters @{ Node = $node }
    if (-not $storageResult.Success) {
        return [pscustomobject]@{ Success = $false; Plan = $null; Error = "could not verify target storage: $($storageResult.Error)" }
    }

    $storageAvailable = @{}
    foreach ($group in @($SourceDetails.Disks | Group-Object Storage)) {
        if (-not $group.Name -or @($group.Group | Where-Object SizeBytes -le 0).Count) {
            return [pscustomobject]@{ Success = $false; Plan = $null; Error = 'could not determine every source disk size and storage' }
        }
        $row = @($storageResult.Data | Where-Object { "$(Get-PmxObjectProperty $_ 'storage' '')" -ceq "$($group.Name)" }) | Select-Object -First 1
        if (-not $row) {
            return [pscustomobject]@{ Success = $false; Plan = $null; Error = "source storage '$($group.Name)' is not active for VM images" }
        }
        if ((Get-PmxObjectProperty $row 'enabled' 1) -ne 1 -or (Get-PmxObjectProperty $row 'active' 1) -ne 1) {
            return [pscustomobject]@{ Success = $false; Plan = $null; Error = "source storage '$($group.Name)' is not active" }
        }
        $available = [long](Get-PmxObjectProperty $row 'avail' 0)
        $needed = [long](($group.Group | Measure-Object SizeBytes -Sum).Sum)
        if ($available -lt $needed) {
            return [pscustomobject]@{ Success = $false; Plan = $null; Error = "storage '$($group.Name)' has $(Format-PmxBytes $available) available; a full clone needs at least $(Format-PmxBytes $needed) provisioned capacity" }
        }
        $storageAvailable[$group.Name] = $available
    }

    $diskPlans = @($SourceDetails.Disks | ForEach-Object {
        [pscustomobject]@{
            Slot             = $_.Disk
            Roles            = [string[]]$_.Roles
            SourceStorage    = $_.Storage
            TargetStorage    = $_.Storage
            Backing          = $_.Backing
            SizeBytes        = [long]$_.SizeBytes
            SizeDisplay      = $_.SizeDisplay
            AvailableBytes   = [long]$storageAvailable[$_.Storage]
            AvailableDisplay = Format-PmxBytes ([long]$storageAvailable[$_.Storage])
        }
    })
    $provisioned = [long](($diskPlans | Measure-Object SizeBytes -Sum).Sum)
    return [pscustomobject]@{
        Success = $true
        Error   = ''
        Plan    = [pscustomobject]@{
            Source             = [pscustomobject]@{ VmId = [int]$SourceDetails.Vm.VmId; Name = $SourceDetails.Vm.Name; Node = $node }
            Target             = [pscustomobject]@{ VmId = $TargetVmId; Name = $TargetName; Node = $node }
            CloneType          = 'full'
            PlacementPolicy    = 'same-as-source'
            ProvisionedBytes   = $provisioned
            ProvisionedDisplay = Format-PmxBytes $provisioned
            Disks              = $diskPlans
        }
    }
}

function Test-PmxClonePlanIdentity {
    param([Parameter(Mandatory)]$Expected, [Parameter(Mandatory)]$Actual)
    if (-not $Expected -or -not $Actual) { return $false }
    if ($Expected.Source.VmId -ne $Actual.Source.VmId -or $Expected.Source.Node -cne $Actual.Source.Node -or
        $Expected.Target.VmId -ne $Actual.Target.VmId -or $Expected.Target.Name -cne $Actual.Target.Name -or
        $Expected.PlacementPolicy -cne $Actual.PlacementPolicy -or $Expected.Disks.Count -ne $Actual.Disks.Count) { return $false }
    for ($i = 0; $i -lt $Expected.Disks.Count; $i++) {
        $left = $Expected.Disks[$i]; $right = $Actual.Disks[$i]
        if ($left.Slot -cne $right.Slot -or $left.Backing -cne $right.Backing -or
            $left.SourceStorage -cne $right.SourceStorage -or $left.TargetStorage -cne $right.TargetStorage -or
            $left.SizeBytes -ne $right.SizeBytes -or $left.AvailableBytes -ne $right.AvailableBytes) { return $false }
    }
    return $true
}

function Show-PmxClonePlacement {
    param([Parameter(Mandatory)]$Plan)
    Write-Host ''
    Write-Host '  SOURCE DISK  ROLE   SOURCE STORAGE  TARGET STORAGE  PROVISIONED  AVAILABLE' -ForegroundColor DarkGray
    foreach ($disk in @($Plan.Disks)) {
        Write-Host ('  {0,-12} {1,-6} {2,-15} {3,-15} {4,11}  {5,11}' -f $disk.Slot,
            (Format-PmxVirtualDiskRole $disk.Roles), $disk.SourceStorage, $disk.TargetStorage,
            $disk.SizeDisplay, $disk.AvailableDisplay) -ForegroundColor White
    }
    Write-Host ''
}

function ConvertTo-PmxCloneContract {
    param(
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)]$Mutation,
        $VerifiedTarget = $null
    )
    $publicDisks = @($Plan.Disks | ForEach-Object {
        [ordered]@{
            slot = $_.Slot; roles = @($_.Roles); source_storage = $_.SourceStorage
            target_storage = $_.TargetStorage; backing = $_.Backing; size_bytes = [long]$_.SizeBytes
            size_display = $_.SizeDisplay; available_bytes = [long]$_.AvailableBytes
        }
    })
    return [ordered]@{
        operation = 'clone'
        dry_run   = [bool]$Mutation.DryRun
        executed  = [bool]$Mutation.Executed
        verified  = [bool]($Mutation.Success -and $Mutation.Executed -and $VerifiedTarget)
        plan      = [ordered]@{
            source = [ordered]@{ vmid = $Plan.Source.VmId; name = $Plan.Source.Name; node = $Plan.Source.Node }
            target = [ordered]@{ vmid = $Plan.Target.VmId; name = $Plan.Target.Name; node = $Plan.Target.Node }
            clone_type = $Plan.CloneType; placement_policy = $Plan.PlacementPolicy
            provisioned_bytes = [long]$Plan.ProvisionedBytes; provisioned_display = $Plan.ProvisionedDisplay
            disks = $publicDisks
        }
        result    = if ($Mutation.Success -and $Mutation.Executed -and $VerifiedTarget) {
            [ordered]@{ vmid = [int]$VerifiedTarget.VmId; name = $VerifiedTarget.Name; node = $VerifiedTarget.Node; verified = $true }
        } else { $null }
    }
}
