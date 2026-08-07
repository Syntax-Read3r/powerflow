# ==============================================================================
# PowerFlow — Proxmox VM Changes
# ==============================================================================
# Domain   : Proxmox
# File     : components/proxmox/vm-change.ps1
# Purpose  : Preview, confirm, revalidate, execute, and verify approved VM changes
# Functions: Invoke-PmxVmClone, Invoke-PmxVmCpuSet, Invoke-PmxVmMemorySet,
#            Invoke-PmxVmStart, Invoke-PmxVmShutdown
# Depends  : shared.ps1, config.ps1, vm-read.ps1, clone-plan.ps1, management adapter
# ==============================================================================

function Get-PmxDesiredVmConfig {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)]$Vm
    )
    $result = Invoke-ProxmoxManagementQuery -Operation 'vm-config' -Connection $Session.Connection `
        -Parameters @{ Vmid = [int]$Vm.VmId; Node = "$($Vm.Node)"; Current = $false }
    if (-not $result.Success) {
        return [pscustomobject]@{ Success = $false; Config = $null; Error = $result.Error; Result = $result }
    }
    return [pscustomobject]@{ Success = $true; Config = $result.Data; Error = ''; Result = $result }
}

function Get-PmxConfigDigest {
    param($Config)
    $digest = "$(Get-PmxObjectProperty $Config 'digest' '')"
    if ($digest -notmatch '^[a-fA-F0-9]{40}$') { return '' }
    return $digest.ToLowerInvariant()
}

function Test-PmxVmSnapshotIdentity {
    param($Expected, $Actual)
    if (-not $Expected -or -not $Actual) { return $false }
    return (
        $Expected.VmId -eq $Actual.VmId -and
        [string]::Equals("$($Expected.Name)", "$($Actual.Name)", [StringComparison]::Ordinal) -and
        [string]::Equals("$($Expected.Node)", "$($Actual.Node)", [StringComparison]::Ordinal) -and
        $Expected.Template -eq $Actual.Template
    )
}

function Invoke-PmxAmberMutation {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$Operation,
        [Parameter(Mandatory)][hashtable]$Parameters,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Fields,
        [string[]]$Warnings = @(),
        [hashtable]$Options = @{},
        [Parameter(Mandatory)][scriptblock]$Revalidate,
        [Parameter(Mandatory)][scriptblock]$Verify,
        [string]$VmId = ''
    )

    $preview = Invoke-ProxmoxManagementChange -Operation $Operation -Connection $Session.Connection `
        -Parameters $Parameters -Preview
    if (-not $preview.Success) {
        Write-Host "❌ Could not build the change plan: $($preview.Error)" -ForegroundColor Red
        return [pscustomobject]@{ Success = $false; Executed = $false; Error = $preview.Error }
    }

    $showNative = $Session.Config.ShowNative -or $Options.ContainsKey('ShowNative')
    $native = if ($showNative) { "$($preview.NativeCommand)" } else { '' }
    $dryRun = $Options.ContainsKey('DryRun')
    $confirmed = Confirm-PmxAmberPlan -Title $Title -Fields $Fields -NativeCommand $native `
        -Warnings $Warnings -DryRun:$dryRun
    if ($dryRun) {
        Write-PmxAuditRecord -Operation $Operation -Target $Session.Connection.Label -Outcome 'dry-run' `
            -Message 'validated preview only' -VmId $VmId -DryRun -Config $Session.Config
        return [pscustomobject]@{ Success = $true; Executed = $false; DryRun = $true; Error = ''; Verification = $null }
    }
    if (-not $confirmed) {
        Write-Host '  ⛔ Cancelled — no Proxmox state was changed.' -ForegroundColor Yellow
        Write-PmxAuditRecord -Operation $Operation -Target $Session.Connection.Label -Outcome 'cancelled' `
            -Message 'confirmation declined or unavailable' -VmId $VmId -Config $Session.Config
        return [pscustomobject]@{ Success = $false; Executed = $false; Error = 'cancelled' }
    }

    $fresh = & $Revalidate
    if (-not $fresh.Success) {
        Write-Host "❌ Refused after revalidation: $($fresh.Error)" -ForegroundColor Red
        Write-PmxAuditRecord -Operation $Operation -Target $Session.Connection.Label -Outcome 'refused' `
            -Message $fresh.Error -VmId $VmId -Config $Session.Config
        return [pscustomobject]@{ Success = $false; Executed = $false; Error = $fresh.Error }
    }
    $executionParameters = if ($fresh.PSObject.Properties.Name -contains 'Parameters' -and $fresh.Parameters) {
        $fresh.Parameters
    } else { $Parameters }

    $result = Invoke-ProxmoxManagementChange -Operation $Operation -Connection $Session.Connection `
        -Parameters $executionParameters
    if (-not $result.Success) {
        Write-Host "❌ Proxmox rejected the change: $($result.Error)" -ForegroundColor Red
        Write-PmxAuditRecord -Operation $Operation -Target $Session.Connection.Label -Outcome 'failed' `
            -Message $result.Error -VmId $VmId -Config $Session.Config
        return [pscustomobject]@{ Success = $false; Executed = $true; Error = $result.Error; Result = $result }
    }

    $verified = & $Verify
    if (-not $verified.Success) {
        $message = "Proxmox accepted the change, but verification failed: $($verified.Error)"
        Write-Host "⚠️  $message" -ForegroundColor Yellow
        Write-PmxAuditRecord -Operation $Operation -Target $Session.Connection.Label -Outcome 'unverified' `
            -Message $message -VmId $VmId -Config $Session.Config
        return [pscustomobject]@{ Success = $false; Executed = $true; Error = $message; Result = $result }
    }

    Write-Host "✅ $($verified.Message)" -ForegroundColor Green
    Write-PmxAuditRecord -Operation $Operation -Target $Session.Connection.Label -Outcome 'verified' `
        -Message $verified.Message -VmId $VmId -Config $Session.Config
    return [pscustomobject]@{ Success = $true; Executed = $true; Error = ''; Result = $result; Verification = $verified }
}

function Invoke-PmxVmClone {
    param([object[]]$Arguments = @())

    $switches = Get-PmxGlobalSwitchMap
    # --full is accepted so nobody's existing command breaks, but it has never DONE anything:
    # Options.Full is read nowhere, and the clone parameters below hardcode Full = $true. It is
    # gone from the help text rather than advertised as a choice the user does not have.
    $switches['full'] = 'Full'
    $parsed = ConvertFrom-PmxArguments -Arguments $Arguments `
        -ValueOptions @{ 'source' = 'Source'; 'source-vmid' = 'Source'; 'new-vmid' = 'NewVmid'; 'name' = 'Name' } `
        -SwitchOptions $switches -MaxPositionals 3
    if (-not $parsed.Success) {
        # The shared parser's message is accurate but generic ("expected at most 3 positional
        # value(s)"). Append what to type instead — an error that only says what was wrong
        # leaves the user to guess the shape.
        Write-Host "❌ $($parsed.Error)" -ForegroundColor Red
        Write-Host '   Use: pmx vm clone <template> <name>' -ForegroundColor DarkGray
        return
    }
    if ($parsed.Options.Help) { Show-PmxTopicHelp 'vm clone'; return }

    # `pmx vm clone debian-base docker-host` — the everyday form.
    #
    # Cloning a template is the most common Proxmox task, and it had the worst ergonomics in
    # pmx: four flags, three flag names to remember, and the magic value `auto` — which is the
    # ONLY value the system accepts anyway (config.ps1 rejects any other vmid-policy). Two
    # positionals now mean source and name, with the VMID resolved automatically; the amber
    # preview prints the resolved VMID before you confirm, so nothing becomes invisible.
    #
    # `pmx disk grow 101 50G` in the same file already reads this way. Clone was the outlier.
    if ($parsed.Positionals.Count) {
        $named = $parsed.Options.ContainsKey('Source') -or $parsed.Options.ContainsKey('NewVmid') -or $parsed.Options.ContainsKey('Name')
        if ($named -or $parsed.Positionals.Count -notin @(2, 3)) {
            Write-Host '❌ Use: pmx vm clone <template> <name>' -ForegroundColor Red
            Write-Host '       pmx vm clone <template> <new-vmid> <name>      (to choose the VMID)' -ForegroundColor DarkGray
            Write-Host '       pmx vm clone --source <t> --name <n>           (script-friendly)' -ForegroundColor DarkGray
            return
        }
        $parsed.Options.Source = $parsed.Positionals[0]
        if ($parsed.Positionals.Count -eq 3) {
            $parsed.Options.NewVmid = $parsed.Positionals[1]
            $parsed.Options.Name    = $parsed.Positionals[2]
        }
        else {
            $parsed.Options.NewVmid = 'auto'
            $parsed.Options.Name    = $parsed.Positionals[1]
        }
    }
    # NewVmid is no longer required: 'auto' is the only policy the tool supports, so demanding
    # the user type it was ceremony. Source and Name genuinely cannot be guessed.
    if (-not $parsed.Options.ContainsKey('NewVmid')) { $parsed.Options.NewVmid = 'auto' }
    foreach ($required in @('Source', 'Name')) {
        if (-not $parsed.Options.ContainsKey($required)) {
            Write-Host "❌ Missing required clone option: $required." -ForegroundColor Red
            Write-Host '   Use: pmx vm clone <template> <name>' -ForegroundColor DarkGray
            return
        }
    }
    if (-not (Test-PmxGuestName $parsed.Options.Name)) {
        Write-Host '❌ VM names must be lowercase DNS-style names without spaces.' -ForegroundColor Red
        return
    }

    $session = Get-PmxManagementSession
    if (-not $session.Success) { Write-PmxDisconnectedState -Session $session; return }
    $mode = Get-PmxOutputMode -Options $parsed.Options -Config $session.Config
    if (-not $mode.Success) { Write-Host "❌ $($mode.Error)" -ForegroundColor Red; return }
    $jsonMode = $mode.Mode -eq 'json'
    $source = Resolve-PmxManagedVm -Selector "$($parsed.Options.Source)" -Session $session
    if (-not $source.Success) { Write-Host "❌ $($source.Error)" -ForegroundColor Red; return }
    if (-not $source.Vm.Template) { Write-Host '❌ Clone source must be a Proxmox template.' -ForegroundColor Red; return }
    if ($source.Vm.Status -eq 'running') { Write-Host '❌ Clone source must be stopped.' -ForegroundColor Red; return }

    $newVmid = 0
    if ("$($parsed.Options.NewVmid)" -eq 'auto') {
        $next = Invoke-ProxmoxManagementQuery -Operation 'next-id' -Connection $session.Connection
        if (-not $next.Success -or -not (Test-PmxVmId $next.Data)) { Write-Host "❌ Could not obtain the next VMID: $($next.Error)" -ForegroundColor Red; return }
        $newVmid = [int]$next.Data
    }
    elseif (Test-PmxVmId $parsed.Options.NewVmid) {
        $newVmid = [int]$parsed.Options.NewVmid
        $free = Invoke-ProxmoxManagementQuery -Operation 'next-id' -Connection $session.Connection -Parameters @{ Vmid = $newVmid }
        if (-not $free.Success) { Write-Host "❌ VMID $newVmid is not available: $($free.Error)" -ForegroundColor Red; return }
    }
    else { Write-Host '❌ --new-vmid must be auto or an integer from 100 to 999999999.' -ForegroundColor Red; return }

    $inventory = Get-PmxManagedVmRows -Session $session
    if (-not $inventory.Success) { Write-Host "❌ $($inventory.Error)" -ForegroundColor Red; return }
    if (@($inventory.Vms | Where-Object VmId -eq $newVmid).Count) { Write-Host "❌ VMID $newVmid is already in use." -ForegroundColor Red; return }
    if (@($inventory.Vms | Where-Object { [string]::Equals($_.Name, "$($parsed.Options.Name)", [StringComparison]::OrdinalIgnoreCase) }).Count) {
        Write-Host "❌ A VM already uses the name '$($parsed.Options.Name)'." -ForegroundColor Red; return
    }

    $sourceDetails = Get-PmxManagedVmDetails -Session $session -Vm $source.Vm
    if (-not $sourceDetails.Success) { Write-Host "❌ $($sourceDetails.Error)" -ForegroundColor Red; return }
    $planned = New-PmxClonePlan -Session $session -SourceDetails $sourceDetails -TargetVmId $newVmid -TargetName "$($parsed.Options.Name)"
    if (-not $planned.Success) { Write-Host "❌ $($planned.Error)" -ForegroundColor Red; return }
    $clonePlan = $planned.Plan

    $parameters = @{ SourceVmid = $source.Vm.VmId; NewVmid = $newVmid; Name = "$($parsed.Options.Name)"; Full = $true }
    $sourceSnapshot = $source.Vm
    $revalidate = {
        $freshSource = Resolve-PmxManagedVm -Selector "$($sourceSnapshot.VmId)" -Session $session
        if (-not $freshSource.Success -or -not (Test-PmxVmSnapshotIdentity $sourceSnapshot $freshSource.Vm) -or
            -not $freshSource.Vm.Template -or $freshSource.Vm.Status -eq 'running') {
            return [pscustomobject]@{ Success = $false; Error = 'source identity, template state, or power state changed after confirmation' }
        }
        $freshInventory = Get-PmxManagedVmRows -Session $session
        if (-not $freshInventory.Success) { return [pscustomobject]@{ Success = $false; Error = $freshInventory.Error } }
        if (@($freshInventory.Vms | Where-Object { $_.VmId -eq $newVmid -or [string]::Equals($_.Name, "$($parsed.Options.Name)", [StringComparison]::OrdinalIgnoreCase) }).Count) {
            return [pscustomobject]@{ Success = $false; Error = 'the target VMID or name became occupied after confirmation' }
        }
        $stillFree = Invoke-ProxmoxManagementQuery -Operation 'next-id' -Connection $session.Connection -Parameters @{ Vmid = $newVmid }
        if (-not $stillFree.Success) { return [pscustomobject]@{ Success = $false; Error = 'the target VMID became unavailable after confirmation' } }
        $freshDetails = Get-PmxManagedVmDetails -Session $session -Vm $freshSource.Vm
        if (-not $freshDetails.Success) { return [pscustomobject]@{ Success = $false; Error = $freshDetails.Error } }
        $freshPlanResult = New-PmxClonePlan -Session $session -SourceDetails $freshDetails -TargetVmId $newVmid -TargetName "$($parsed.Options.Name)"
        if (-not $freshPlanResult.Success) { return $freshPlanResult }
        if (-not (Test-PmxClonePlanIdentity -Expected $clonePlan -Actual $freshPlanResult.Plan)) {
            return [pscustomobject]@{ Success = $false; Error = 'clone disk placement, size, or storage capacity changed after confirmation' }
        }
        return [pscustomobject]@{ Success = $true; Error = ''; Parameters = $parameters }
    }.GetNewClosure()
    $verify = {
        $target = Resolve-PmxManagedVm -Selector "$newVmid" -Session $session
        if (-not $target.Success -or -not [string]::Equals($target.Vm.Name, "$($parsed.Options.Name)", [StringComparison]::Ordinal)) {
            return [pscustomobject]@{ Success = $false; Error = "VMID $newVmid was not returned with the expected name" }
        }
        return [pscustomobject]@{ Success = $true; Error = ''; Message = "Cloned template $($sourceSnapshot.VmId) to VM $newVmid ($($parsed.Options.Name))."; Data = $target.Vm }
    }.GetNewClosure()
    $fields = [ordered]@{
        'Source VMID' = $source.Vm.VmId
        'Source name' = $source.Vm.Name
        'Source type' = 'Template'
        'New VMID'    = $newVmid
        'New name'    = $parsed.Options.Name
        'Clone type'  = 'Full, independent copy'
        'Placement'   = $clonePlan.PlacementPolicy
        'Provisioned capacity' = $clonePlan.ProvisionedDisplay
    }
    $warnings = @()
    if ($session.Config.Explain -or $parsed.Options.ContainsKey('Explain')) {
        $warnings += 'Placement is same-as-source for every disk; no target-storage override is requested.'
        $warnings += 'Provisioned capacity is configured virtual capacity, not allocated thin-pool blocks.'
    }
    if (-not $jsonMode) { Show-PmxClonePlacement -Plan $clonePlan }
    $mutation = Invoke-PmxAmberMutation -Session $session -Operation 'vm-clone' -Parameters $parameters `
        -Title 'CLONE VM' -Fields $fields -Warnings $warnings -Options $parsed.Options -Revalidate $revalidate -Verify $verify -VmId "$newVmid"
    if ($jsonMode -and $mutation) {
        $verifiedTarget = if ($mutation.Verification -and $mutation.Verification.Data) { $mutation.Verification.Data } else { $null }
        Write-PmxJson (ConvertTo-PmxCloneContract -Plan $clonePlan -Mutation $mutation -VerifiedTarget $verifiedTarget)
    }
}

function Get-PmxSetInvocation {
    param(
        [object[]]$Arguments,
        [Parameter(Mandatory)][string]$ValueOption,
        [Parameter(Mandatory)][string]$ValueProperty,
        # Named so the usage error is self-contained. Without it the message read
        # "use: <vmid|name> --size <value>, ..." with no clue which command it belonged to.
        [string]$CommandName = "pmx vm"
    )

    $valueOptions = @{ $ValueOption = $ValueProperty }
    $parsed = ConvertFrom-PmxArguments -Arguments $Arguments -ValueOptions $valueOptions `
        -SwitchOptions (Get-PmxGlobalSwitchMap) -MaxPositionals 2
    if (-not $parsed.Success) { return $parsed }

    if ($parsed.Positionals.Count -eq 1 -and $parsed.Options.ContainsKey($ValueProperty)) {
        $parsed.Options.Vm = $parsed.Positionals[0]
    }
    elseif ($parsed.Positionals.Count -eq 2 -and -not $parsed.Options.ContainsKey($ValueProperty)) {
        $parsed.Options.Vm = $parsed.Positionals[0]
        $parsed.Options[$ValueProperty] = $parsed.Positionals[1]
    }
    else {
        return [pscustomobject]@{ Success = $false; Options = $parsed.Options; Positionals = $parsed.Positionals; Error = "use: $CommandName <vmid|name> <value>   (or: $CommandName <vmid|name> --$ValueOption <value>)" }
    }
    return $parsed
}

function Invoke-PmxVmCpuSet {
    param([object[]]$Arguments = @())

    if (@($Arguments | Where-Object { "$_" -eq '--help' }).Count) { Show-PmxTopicHelp 'vm cpu set'; return }
    $parsed = Get-PmxSetInvocation -Arguments $Arguments -ValueOption 'cores' -ValueProperty 'Cores' -CommandName 'pmx vm cpu'
    if (-not $parsed.Success) { Write-Host "❌ $($parsed.Error)" -ForegroundColor Red; return }
    $cores = 0
    if (-not [int]::TryParse("$($parsed.Options.Cores)", [ref]$cores) -or $cores -lt 1 -or $cores -gt 1024) {
        Write-Host '❌ --cores must be an integer from 1 to 1024.' -ForegroundColor Red; return
    }
    $session = Get-PmxManagementSession
    if (-not $session.Success) { Write-PmxDisconnectedState -Session $session; return }
    $resolved = Resolve-PmxManagedVm -Selector "$($parsed.Options.Vm)" -Session $session
    if (-not $resolved.Success) { Write-Host "❌ $($resolved.Error)" -ForegroundColor Red; return }
    if ($resolved.Vm.Template) { Write-Host '❌ Clone the template before changing its CPU allocation.' -ForegroundColor Red; return }
    $desired = Get-PmxDesiredVmConfig -Session $session -Vm $resolved.Vm
    if (-not $desired.Success) { Write-Host "❌ $($desired.Error)" -ForegroundColor Red; return }
    $current = [int](Get-PmxObjectProperty $desired.Config 'cores' 1)
    $sockets = [int](Get-PmxObjectProperty $desired.Config 'sockets' 1)
    if ($current -eq $cores) { Write-Host "✅ VM $($resolved.Vm.VmId) already has $cores core(s) per socket; nothing changed." -ForegroundColor Green; return }
    $digest = Get-PmxConfigDigest $desired.Config
    if (-not $digest) { Write-Host '❌ Proxmox did not return a configuration digest; refusing a race-prone update.' -ForegroundColor Red; return }
    $nodeStatus = Invoke-ProxmoxManagementQuery -Operation 'node-status' -Connection $session.Connection -Parameters @{ Node = $resolved.Vm.Node }
    $logical = if ($nodeStatus.Success) { [int](Get-PmxObjectProperty (Get-PmxObjectProperty $nodeStatus.Data 'cpuinfo' $null) 'cpus' 0) } else { 0 }
    $total = $cores * [math]::Max(1, $sockets)
    $warnings = @("Proxmox cores are per socket: $cores × $sockets socket(s) = $total vCPU(s).")
    if ($logical -gt 0 -and $total -ge [math]::Ceiling($logical * 0.8)) { $warnings += "This assigns $total of the node's $logical logical CPUs." }
    $parameters = @{ Vmid = $resolved.Vm.VmId; Cores = $cores; Digest = $digest }
    $snapshot = $resolved.Vm
    $revalidate = {
        $freshVm = Resolve-PmxManagedVm -Selector "$($snapshot.VmId)" -Session $session
        if (-not $freshVm.Success -or -not (Test-PmxVmSnapshotIdentity $snapshot $freshVm.Vm)) { return [pscustomobject]@{ Success = $false; Error = 'VM identity changed after confirmation' } }
        $freshConfig = Get-PmxDesiredVmConfig -Session $session -Vm $freshVm.Vm
        if (-not $freshConfig.Success) { return [pscustomobject]@{ Success = $false; Error = $freshConfig.Error } }
        $freshDigest = Get-PmxConfigDigest $freshConfig.Config
        if ($freshDigest -cne $digest -or [int](Get-PmxObjectProperty $freshConfig.Config 'cores' 1) -ne $current) { return [pscustomobject]@{ Success = $false; Error = 'VM CPU configuration changed after confirmation' } }
        return [pscustomobject]@{ Success = $true; Error = ''; Parameters = @{ Vmid = $snapshot.VmId; Cores = $cores; Digest = $freshDigest } }
    }.GetNewClosure()
    $verify = {
        $freshConfig = Get-PmxDesiredVmConfig -Session $session -Vm $snapshot
        if (-not $freshConfig.Success -or [int](Get-PmxObjectProperty $freshConfig.Config 'cores' 0) -ne $cores) { return [pscustomobject]@{ Success = $false; Error = 'desired core count was not returned' } }
        return [pscustomobject]@{ Success = $true; Error = ''; Message = "VM $($snapshot.VmId) now requests $cores core(s) per socket ($total vCPU total)." }
    }.GetNewClosure()
    $fields = [ordered]@{ VM = "$($snapshot.VmId) $($snapshot.Name)"; Current = "$current core(s) per socket"; Requested = "$cores core(s) per socket"; 'Total vCPUs' = $total }
    $null = Invoke-PmxAmberMutation -Session $session -Operation 'vm-set-cpu' -Parameters $parameters `
        -Title 'CHANGE VM CPU' -Fields $fields -Warnings $warnings -Options $parsed.Options -Revalidate $revalidate -Verify $verify -VmId "$($snapshot.VmId)"
}

function Invoke-PmxVmMemorySet {
    param([object[]]$Arguments = @())

    if (@($Arguments | Where-Object { "$_" -eq '--help' }).Count) { Show-PmxTopicHelp 'vm memory set'; return }
    $parsed = Get-PmxSetInvocation -Arguments $Arguments -ValueOption 'size' -ValueProperty 'Size' -CommandName 'pmx vm memory'
    if (-not $parsed.Success) { Write-Host "❌ $($parsed.Error)" -ForegroundColor Red; return }
    $size = ConvertFrom-PmxSize -Value "$($parsed.Options.Size)" -Kind memory
    if (-not $size.Success -or $size.MiB -gt [int]::MaxValue) { Write-Host "❌ $($size.Error)" -ForegroundColor Red; return }
    $session = Get-PmxManagementSession
    if (-not $session.Success) { Write-PmxDisconnectedState -Session $session; return }
    $resolved = Resolve-PmxManagedVm -Selector "$($parsed.Options.Vm)" -Session $session
    if (-not $resolved.Success) { Write-Host "❌ $($resolved.Error)" -ForegroundColor Red; return }
    if ($resolved.Vm.Template) { Write-Host '❌ Clone the template before changing its memory allocation.' -ForegroundColor Red; return }
    $desired = Get-PmxDesiredVmConfig -Session $session -Vm $resolved.Vm
    if (-not $desired.Success) { Write-Host "❌ $($desired.Error)" -ForegroundColor Red; return }
    $current = [long](Get-PmxObjectProperty $desired.Config 'memory' 0)
    if ($current -eq $size.MiB) { Write-Host "✅ VM $($resolved.Vm.VmId) already requests $($size.Canonical); nothing changed." -ForegroundColor Green; return }
    $digest = Get-PmxConfigDigest $desired.Config
    if (-not $digest) { Write-Host '❌ Proxmox did not return a configuration digest; refusing a race-prone update.' -ForegroundColor Red; return }
    $nodeStatus = Invoke-ProxmoxManagementQuery -Operation 'node-status' -Connection $session.Connection -Parameters @{ Node = $resolved.Vm.Node }
    $nodeMemory = if ($nodeStatus.Success) { [long](Get-PmxObjectProperty (Get-PmxObjectProperty $nodeStatus.Data 'memory' $null) 'total' 0) } else { 0L }
    $warnings = @("Requested memory: $($size.Canonical); Proxmox value: $($size.MiB) MiB.")
    if ($nodeMemory -gt 0 -and $size.Bytes -ge ($nodeMemory * 0.8)) { $warnings += "This assigns at least 80% of the node's $(Format-PmxBytes $nodeMemory) memory." }
    $parameters = @{ Vmid = $resolved.Vm.VmId; MemoryMiB = [int]$size.MiB; Digest = $digest }
    $snapshot = $resolved.Vm
    $revalidate = {
        $freshVm = Resolve-PmxManagedVm -Selector "$($snapshot.VmId)" -Session $session
        if (-not $freshVm.Success -or -not (Test-PmxVmSnapshotIdentity $snapshot $freshVm.Vm)) { return [pscustomobject]@{ Success = $false; Error = 'VM identity changed after confirmation' } }
        $freshConfig = Get-PmxDesiredVmConfig -Session $session -Vm $freshVm.Vm
        if (-not $freshConfig.Success) { return [pscustomobject]@{ Success = $false; Error = $freshConfig.Error } }
        $freshDigest = Get-PmxConfigDigest $freshConfig.Config
        if ($freshDigest -cne $digest -or [long](Get-PmxObjectProperty $freshConfig.Config 'memory' 0) -ne $current) { return [pscustomobject]@{ Success = $false; Error = 'VM memory configuration changed after confirmation' } }
        return [pscustomobject]@{ Success = $true; Error = ''; Parameters = @{ Vmid = $snapshot.VmId; MemoryMiB = [int]$size.MiB; Digest = $freshDigest } }
    }.GetNewClosure()
    $verify = {
        $freshConfig = Get-PmxDesiredVmConfig -Session $session -Vm $snapshot
        if (-not $freshConfig.Success -or [long](Get-PmxObjectProperty $freshConfig.Config 'memory' 0) -ne $size.MiB) { return [pscustomobject]@{ Success = $false; Error = 'desired memory value was not returned' } }
        return [pscustomobject]@{ Success = $true; Error = ''; Message = "VM $($snapshot.VmId) now requests $($size.Canonical)." }
    }.GetNewClosure()
    $fields = [ordered]@{ VM = "$($snapshot.VmId) $($snapshot.Name)"; Current = "$(Format-PmxBytes ($current * 1MB)) ($current MiB)"; Requested = "$($size.Canonical) ($($size.MiB) MiB)" }
    $null = Invoke-PmxAmberMutation -Session $session -Operation 'vm-set-memory' -Parameters $parameters `
        -Title 'CHANGE VM MEMORY' -Fields $fields -Warnings $warnings -Options $parsed.Options -Revalidate $revalidate -Verify $verify -VmId "$($snapshot.VmId)"
}

function Get-PmxLifecycleInvocation {
    param([object[]]$Arguments)
    return (Get-PmxReadInvocation -Arguments $Arguments -RequireSelector -PositionalSelectorOnly)
}

function Invoke-PmxVmLifecycleChange {
    param(
        [Parameter(Mandatory)][object[]]$Arguments,
        [Parameter(Mandatory)][ValidateSet('start', 'shutdown')][string]$Action
    )
    if (@($Arguments | Where-Object { "$_" -eq '--help' }).Count) { Show-PmxTopicHelp "vm $Action"; return }
    $parsed = Get-PmxLifecycleInvocation -Arguments $Arguments
    if (-not $parsed.Success) { Write-Host "❌ $($parsed.Error)" -ForegroundColor Red; return }
    $session = Get-PmxManagementSession
    if (-not $session.Success) { Write-PmxDisconnectedState -Session $session; return }
    $resolved = Resolve-PmxManagedVm -Selector "$($parsed.Options.Selector)" -Session $session
    if (-not $resolved.Success) { Write-Host "❌ $($resolved.Error)" -ForegroundColor Red; return }
    if ($resolved.Vm.Template) { Write-Host '❌ Templates cannot be started or shut down.' -ForegroundColor Red; return }
    $wanted = if ($Action -eq 'start') { 'running' } else { 'stopped' }
    if ($resolved.Vm.Status -eq $wanted) { Write-Host "✅ VM $($resolved.Vm.VmId) is already $wanted; nothing changed." -ForegroundColor Green; return }
    if ($Action -eq 'start' -and $resolved.Vm.Status -ne 'stopped') { Write-Host "❌ VM is '$($resolved.Vm.Status)', not stopped." -ForegroundColor Red; return }
    if ($Action -eq 'shutdown' -and $resolved.Vm.Status -ne 'running') { Write-Host "❌ VM is '$($resolved.Vm.Status)', not running." -ForegroundColor Red; return }
    $snapshot = $resolved.Vm
    $operation = if ($Action -eq 'start') { 'vm-start' } else { 'vm-shutdown' }
    $parameters = @{ Vmid = $snapshot.VmId }
    $revalidate = {
        $fresh = Resolve-PmxManagedVm -Selector "$($snapshot.VmId)" -Session $session
        if (-not $fresh.Success -or -not (Test-PmxVmSnapshotIdentity $snapshot $fresh.Vm) -or $fresh.Vm.Status -ne $snapshot.Status) {
            return [pscustomobject]@{ Success = $false; Error = 'VM identity or power state changed after confirmation' }
        }
        return [pscustomobject]@{ Success = $true; Error = ''; Parameters = $parameters }
    }.GetNewClosure()
    $verify = {
        $fresh = Resolve-PmxManagedVm -Selector "$($snapshot.VmId)" -Session $session
        if (-not $fresh.Success -or $fresh.Vm.Status -ne $wanted) { return [pscustomobject]@{ Success = $false; Error = "VM did not reach '$wanted'" } }
        return [pscustomobject]@{ Success = $true; Error = ''; Message = "VM $($snapshot.VmId) is $wanted." }
    }.GetNewClosure()
    $fields = [ordered]@{ VM = "$($snapshot.VmId) $($snapshot.Name)"; Current = $snapshot.Status; Requested = $wanted }
    $warnings = if ($Action -eq 'shutdown') { @('This requests a graceful guest shutdown; it does not force-stop the VM.') } else { @() }
    $null = Invoke-PmxAmberMutation -Session $session -Operation $operation -Parameters $parameters `
        -Title "$(if ($Action -eq 'start') { 'START VM' } else { 'SHUT DOWN VM' })" -Fields $fields `
        -Warnings $warnings -Options $parsed.Options -Revalidate $revalidate -Verify $verify -VmId "$($snapshot.VmId)"
}

function Invoke-PmxVmStart { param([object[]]$Arguments = @()); Invoke-PmxVmLifecycleChange -Arguments $Arguments -Action start }
function Invoke-PmxVmShutdown { param([object[]]$Arguments = @()); Invoke-PmxVmLifecycleChange -Arguments $Arguments -Action shutdown }
