# ==============================================================================
# PowerFlow — Proxmox VM Network Read Orchestration
# ==============================================================================
# Domain   : Proxmox
# File     : components/proxmox/network-read.ps1
# Purpose  : Parse, query, model, and display read-only VM network information
# Functions: Get-PmxNetworkInvocation, Get-PmxVmNetworkModel,
#            Show-PmxVmNetwork, Show-PmxVmNetworkList,
#            Invoke-PmxVmNetworkCommand
# Depends  : config.ps1, vm-read.ps1, network-config-model.ps1,
#            guest-network-model.ps1, network-view.ps1, management adapter
# ==============================================================================

function ConvertFrom-PmxNetworkShortOptions {
    param([object[]]$Arguments = @())

    $mapped = @()
    foreach ($argument in @($Arguments)) {
        $token = "$argument"
        $mapped += switch -CaseSensitive ($token) {
            '-t' { '--table' }
            '-j' { '--json' }
            '-4' { '--ipv4' }
            '-6' { '--ipv6' }
            default { $token }
        }
    }
    return ,$mapped
}

function Get-PmxNetworkInvocation {
    param(
        [object[]]$Arguments = @(),
        [ValidateSet('combined', 'adapters', 'addresses', 'stats', 'list')][string]$View
    )

    $switches = @{
        'help' = 'Help'; 'explain' = 'Explain'; 'show-native' = 'ShowNative'
        'json' = 'Json'; 'table' = 'Table'; 'all' = 'All'; 'ipv4' = 'IPv4'
        'ipv6' = 'IPv6'; 'include-loopback' = 'IncludeLoopback'
    }
    $mapped = ConvertFrom-PmxNetworkShortOptions $Arguments
    $parsed = ConvertFrom-PmxArguments -Arguments $mapped -SwitchOptions $switches -MinPositionals 0 `
        -MaxPositionals $(if ($View -eq 'list') { 0 } else { 1 })
    if (-not $parsed.Success) { return $parsed }
    if ($parsed.Options.Help) { return $parsed }
    if ($View -ne 'list' -and $parsed.Positionals.Count -ne 1) {
        return [pscustomobject]@{ Success = $false; Options = $parsed.Options; Positionals = $parsed.Positionals; Error = 'supply one VM name or VMID after the network command' }
    }
    if ($View -ne 'list') { $parsed.Options['Selector'] = "$($parsed.Positionals[0])" }
    if ($View -in @('adapters', 'stats') -and
        @('All', 'IPv4', 'IPv6', 'IncludeLoopback' | Where-Object { $parsed.Options.ContainsKey($_) }).Count) {
        return [pscustomobject]@{ Success = $false; Options = $parsed.Options; Positionals = $parsed.Positionals; Error = "address filters do not apply to the $View view" }
    }
    return $parsed
}

function New-PmxNetworkAgentState {
    param([bool]$Configured, [bool]$Available, [string]$Status, $Reason = $null)
    return [pscustomobject][ordered]@{
        Configured = $Configured; Available = $Available; Status = $Status; Reason = $Reason
    }
}

function New-PmxUnavailableVmNetworkModel {
    param([Parameter(Mandatory)]$Vm, [Parameter(Mandatory)][string]$Reason)
    return [pscustomobject][ordered]@{
        GeneratedAt = [DateTime]::UtcNow.ToString('o')
        Vm = [pscustomobject][ordered]@{
            VmId = [int]$Vm.VmId; Name = $Vm.Name; Node = $Vm.Node
            Status = $Vm.Status; Template = [bool]$Vm.Template
        }
        # 'unknown', not 'unavailable'. This model is built when the VM CONFIG could not be
        # read, which tells us nothing whatsoever about the agent — claiming the agent is
        # unavailable is an assertion we have no evidence for.
        Agent = New-PmxNetworkAgentState $false $false 'unknown' $Reason
        Adapters = @(); Interfaces = @()
        AddressSelection = [pscustomobject][ordered]@{
            PrimaryCandidate = $null; Candidates = @(); Inferred = $true; Reason = 'network configuration was unavailable'
        }
        Sources = [pscustomobject][ordered]@{
            Configured = [pscustomobject][ordered]@{ Available = $false; NativeCommand = $null }
            VmReported = [pscustomobject][ordered]@{ Available = $false; NativeCommand = $null }
        }
        Warnings = @($Reason)
        Explanations = @('This VM remains in the inventory even though one read failed.')
    }
}

<#
.SYNOPSIS
    Turn an agent query failure into a state that names its cause.
.DESCRIPTION
    'unavailable' previously meant any of five materially different things, so
    `pmx vm ip` was a dead end: the message told you it had not worked without telling you
    what to do. The states are now distinct, and each carries a Reason the view prints.
      not-responding  the channel is configured and the VM is running, but nothing answered
                      inside it — usually qemu-guest-agent not installed or not started
      query-failed    the query itself failed for another reason (transport, parse)
      timed-out       it answered too slowly
      unsupported     this agent does not report network information
    One of the original five — "skipped because runtime status could not be read" — no longer
    exists: PF-BUG-004 removed the branch that refused to ask.
#>
function Get-PmxVmAgentFailureState {
    param($Result)

    $kind = "$(Get-PmxObjectProperty $Result 'FailureKind' '')".ToLowerInvariant()
    switch ($kind) {
        'timeout' { New-PmxNetworkAgentState $true $false 'timed-out' 'VM agent did not respond before the timeout.' }
        'unsupported' { New-PmxNetworkAgentState $true $false 'unsupported' 'VM agent network reporting is unsupported.' }
        'agent-unavailable' {
            New-PmxNetworkAgentState $true $false 'not-responding' `
                'The agent channel is configured, but nothing answered inside the VM. Is qemu-guest-agent installed and running?'
        }
        default {
            New-PmxNetworkAgentState $true $false 'query-failed' `
                'The VM agent query failed. Re-run with --explain for the transport and parser evidence.'
        }
    }
}

function Get-PmxVmNetworkModel {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)]$Vm,
        [ValidateSet('combined', 'adapters', 'addresses', 'stats')][string]$View = 'combined',
        [hashtable]$Options = @{}
    )

    $parameters = @{ Vmid = [int]$Vm.VmId; Node = "$($Vm.Node)" }
    $configResult = Invoke-ProxmoxManagementQuery -Operation 'vm-config' -Connection $Session.Connection -Parameters $parameters
    if (-not $configResult.Success) {
        # Diagnostics is carried up, not dropped. Re-wrapping a result without it is how
        # "malformed JSON" reached the user with nothing to act on — the same information leak
        # Get-PmxManagedVmDetails had.
        return [pscustomobject]@{ Success = $false; Model = $null; Error = $configResult.Error
            Diagnostics = $configResult.Diagnostics }
    }
    $adapters = @(Get-PmxConfiguredNetworkAdapters -Config $configResult.Data)
    $agentConfig = Get-PmxVmAgentConfiguration -Config $configResult.Data
    $warnings = @()

    # TWO STATUS SOURCES, KEPT APART ON PURPOSE (PF-BUG-004).
    #
    # These were previously collapsed into one $status field, which let a single view state
    # "Status running" AND "Current VM status could not be read" at the same time — because
    # the inventory value survived the failed runtime read while the warning was also emitted.
    #
    #   inventory  what `pmx vm` and `qm list` report. Already fetched; always present.
    #   runtime    what `qm status <vmid>` reports. Richer, but a separate query that can fail.
    #
    # Falling back to inventory is not a guess: it is the same field from the same host, just
    # read earlier. So the fallback is stated plainly rather than reported as "unknown".
    $inventoryStatus = "$($Vm.Status)"
    $status = $inventoryStatus
    $statusSource = 'inventory'
    $statusNative = $null
    $statusAvailable = ($View -eq 'adapters')
    if ($View -ne 'adapters') {
        $statusResult = Invoke-ProxmoxManagementQuery -Operation 'vm-status' -Connection $Session.Connection -Parameters $parameters
        if ($statusResult.Success) {
            $status = "$(ConvertTo-PmxDisplayText (Get-PmxObjectProperty $statusResult.Data 'status' $status))"
            $statusSource = 'runtime'
            $statusNative = $statusResult.NativeCommand
            $statusAvailable = $true
        }
        elseif ($inventoryStatus) {
            $warnings += "Runtime status could not be read; showing the inventory status ($inventoryStatus)."
        }
        else {
            $warnings += 'VM status could not be determined from the inventory or the runtime query.'
        }
    }

    $vmModel = [pscustomobject][ordered]@{
        VmId = [int]$Vm.VmId; Name = $Vm.Name; Node = $Vm.Node; Status = $status
        StatusSource = $statusSource; Template = [bool]$Vm.Template
    }
    $agent = New-PmxNetworkAgentState ([bool]$agentConfig.Configured) $false 'not-queried' $null
    $interfaces = @()
    $runtimeNative = $null
    # $statusNative is DELIBERATELY absent from this condition. It is the --show-native display
    # string for the status query, and gating behaviour on it meant a failed runtime read
    # silently disabled the guest-agent query — so `pmx vm ip 102` found no addresses on a VM
    # that both `pmx vm` and `qm list` showed as running. A display value must never decide
    # whether work happens.
    #
    # The agent is now queried whenever the VM is running per EITHER status source and the
    # agent channel is configured. If the agent is genuinely unreachable, the query says so
    # with its own precise reason via Get-PmxVmAgentFailureState — which is a better answer
    # than refusing to ask.
    $shouldReadRuntime = $View -ne 'adapters' -and -not $Vm.Template -and $status -eq 'running' -and $agentConfig.Configured
    if ($View -eq 'adapters') {
        $agent = New-PmxNetworkAgentState ([bool]$agentConfig.Configured) $false 'not-requested' 'Adapter configuration does not require the VM agent.'
    }
    elseif ($Vm.Template) {
        $agent = New-PmxNetworkAgentState ([bool]$agentConfig.Configured) $false 'template' 'Templates have no running operating system to report addresses.'
    }
    elseif (-not $status) {
        # Neither source produced a status. This is the ONLY case that genuinely cannot be
        # resolved, and it is checked before the "not running" branch so an unknown status is
        # never reported as stopped.
        $agent = New-PmxNetworkAgentState ([bool]$agentConfig.Configured) $false 'unavailable' `
            'VM status could not be determined from the inventory or the runtime query.'
    }
    elseif ($status -ne 'running') {
        $agent = New-PmxNetworkAgentState ([bool]$agentConfig.Configured) $false 'stopped' 'Start the VM before requesting VM-reported addresses or stats.'
    }
    elseif (-not $agentConfig.Configured) {
        # 'not-configured', not 'disabled': nothing was turned off, the channel was never
        # enabled. The distinction matters because the fix differs — you add agent=1 to the VM
        # config, you do not re-enable something.
        $agent = New-PmxNetworkAgentState $false $false 'not-configured' 'The VM agent channel is not enabled in this VM configuration. Add agent=1 to the VM config.'
    }
    # The former `-not $statusAvailable` branch is GONE. It reported the AGENT as unavailable
    # because the STATUS query had failed — two unrelated facts — and it short-circuited ahead
    # of the query below, so the agent was never actually asked. That is PF-BUG-004: the view
    # showed "Status running" and "Agent unavailable" together, and `pmx vm ip` returned nothing.
    elseif ($shouldReadRuntime) {
        $runtimeResult = Invoke-ProxmoxManagementQuery -Operation 'vm-guest-network' -Connection $Session.Connection -Parameters $parameters
        $runtimeNative = "qm guest cmd $($Vm.VmId) network-get-interfaces"
        if ($runtimeResult.Success) {
            $interfaces = @(Get-PmxVmReportedNetworkInterfaces -Data $runtimeResult.Data)
            $agent = New-PmxNetworkAgentState $true $true 'available' $null
        }
        else {
            $agent = Get-PmxVmAgentFailureState $runtimeResult
            $warnings += $agent.Reason
        }
    }

    $joined = Join-PmxNetworkAdapters -Adapters $adapters -Interfaces $interfaces
    $warnings += @($joined.Warnings)
    $filteredInterfaces = @(Select-PmxNetworkAddresses -Interfaces $joined.Interfaces `
        -IPv4:$Options.ContainsKey('IPv4') -IPv6:$Options.ContainsKey('IPv6') `
        -IncludeLoopback:$Options.ContainsKey('IncludeLoopback') -All:$Options.ContainsKey('All'))
    if ($View -in @('combined', 'addresses')) {
        $before = @($joined.Interfaces | ForEach-Object Addresses).Count
        $after = @($filteredInterfaces | ForEach-Object Addresses).Count
        if ($before -gt $after) { $warnings += "$($before - $after) address row(s) were hidden by the selected filters." }
    }
    if ($View -eq 'stats' -and $agent.Available -and -not @($filteredInterfaces | Where-Object { $null -ne $_.Stats }).Count) {
        $warnings += 'The VM agent returned no traffic counters.'
    }
    $selection = Get-PmxPrimaryAddressSelection -Interfaces $filteredInterfaces `
        -IPv4:$Options.ContainsKey('IPv4') -IPv6:$Options.ContainsKey('IPv6')
    $nativeConfig = if ($statusNative) { @($configResult.NativeCommand, $statusNative) -join ' · ' } else { $configResult.NativeCommand }
    $model = [pscustomobject][ordered]@{
        GeneratedAt      = [DateTime]::UtcNow.ToString('o')
        Vm               = $vmModel
        Agent            = $agent
        Adapters         = @($joined.Adapters)
        Interfaces       = $filteredInterfaces
        AddressSelection = $selection
        Sources          = [pscustomobject][ordered]@{
            Configured = [pscustomobject][ordered]@{ Available = $true; NativeCommand = $nativeConfig }
            VmReported = [pscustomobject][ordered]@{ Available = [bool]$agent.Available; NativeCommand = $runtimeNative }
        }
        Warnings          = @($warnings | Where-Object { $_ } | Select-Object -Unique)
        Explanations      = @(
            'Adapters come from the Proxmox VM configuration; addresses and stats are reported from inside the VM.'
            'Configured adapters and VM interfaces are matched only when both report the same valid MAC address.'
            'The primary candidate is inferred from address family, scope, and adapter matching; reachability is not tested.'
        )
    }
    return [pscustomobject]@{ Success = $true; Model = $model; Error = '' }
}

function Show-PmxVmNetwork {
    param(
        # Not Mandatory: `pmx vm net` with no VM threw "Cannot bind argument to parameter
        # 'Arguments' because it is an empty array" — a raw binding exception, before any
        # parsing. With a default, an empty tail flows through to the VM picker instead.
        [object[]]$Arguments = @(),
        [ValidateSet('combined', 'adapters', 'addresses', 'stats')][string]$View = 'combined'
    )

    $parsed = Get-PmxNetworkInvocation -Arguments $Arguments -View $View
    if (-not $parsed.Success) { Write-Host "❌ $($parsed.Error)" -ForegroundColor Red; return }
    if ($parsed.Options.Help) { Show-PmxTopicHelp "vm network$(if ($View -ne 'combined') { " $View" })"; return }
    $session = Get-PmxManagementSession
    if (-not $session.Success) { Write-PmxDisconnectedState -Session $session; return }
    $mode = Get-PmxOutputMode -Options $parsed.Options -Config $session.Config
    if (-not $mode.Success) { Write-Host "❌ $($mode.Error)" -ForegroundColor Red; return }
    $resolved = Resolve-PmxManagedVm -Selector $parsed.Options.Selector -Session $session
    if (-not $resolved.Success) { Write-Host "❌ $($resolved.Error)" -ForegroundColor Red; return }
    $result = Get-PmxVmNetworkModel -Session $session -Vm $resolved.Vm -View $View -Options $parsed.Options
    if (-not $result.Success) { Write-PmxQueryFailure -Message $result.Error -Diagnostics $result.Diagnostics -Options $parsed.Options; return }
    if ($mode.Mode -eq 'json') {
        Write-PmxJson (ConvertTo-PmxVmNetworkContract -Model $result.Model -View $View `
            -ShowNative:$parsed.Options.ContainsKey('ShowNative') -Explain:$parsed.Options.ContainsKey('Explain'))
        return
    }
    Show-PmxVmNetworkResult -Model $result.Model -View $View `
        -ShowNative:$parsed.Options.ContainsKey('ShowNative') -Explain:$parsed.Options.ContainsKey('Explain')
}

function Show-PmxVmNetworkList {
    param([object[]]$Arguments = @())

    $parsed = Get-PmxNetworkInvocation -Arguments $Arguments -View list
    if (-not $parsed.Success) { Write-Host "❌ $($parsed.Error)" -ForegroundColor Red; return }
    if ($parsed.Options.Help) { Show-PmxTopicHelp 'vm network list'; return }
    $session = Get-PmxManagementSession
    if (-not $session.Success) { Write-PmxDisconnectedState -Session $session; return }
    $mode = Get-PmxOutputMode -Options $parsed.Options -Config $session.Config
    if (-not $mode.Success) { Write-Host "❌ $($mode.Error)" -ForegroundColor Red; return }
    $inventory = Get-PmxManagedVmRows -Session $session
    if (-not $inventory.Success) { Write-Host "❌ $($inventory.Error)" -ForegroundColor Red; return }
    $models = @()
    $warnings = @()
    foreach ($vm in @($inventory.Vms)) {
        $result = Get-PmxVmNetworkModel -Session $session -Vm $vm -View combined -Options $parsed.Options
        if ($result.Success) { $models += $result.Model }
        else {
            $reason = "VM $($vm.VmId) network configuration could not be read."
            $models += New-PmxUnavailableVmNetworkModel -Vm $vm -Reason $reason
            $warnings += $reason
        }
    }
    $listModel = [pscustomobject][ordered]@{
        GeneratedAt = [DateTime]::UtcNow.ToString('o'); Node = $session.Node
        Vms = @($models | Sort-Object { $_.Vm.VmId }); Warnings = @($warnings)
    }
    if ($mode.Mode -eq 'json') {
        Write-PmxJson (ConvertTo-PmxVmNetworkListContract -Model $listModel `
            -ShowNative:$parsed.Options.ContainsKey('ShowNative') -Explain:$parsed.Options.ContainsKey('Explain'))
        return
    }
    Show-PmxVmNetworkListResult -Model $listModel `
        -ShowNative:$parsed.Options.ContainsKey('ShowNative') -Explain:$parsed.Options.ContainsKey('Explain') `
        -IPv6Only:($parsed.Options.ContainsKey('IPv6') -and -not $parsed.Options.ContainsKey('IPv4'))
}

function Invoke-PmxVmNetworkCommand {
    param([object[]]$Arguments = @())

    # Bare `pmx vm net` lists the fleet, mirroring bare `pmx vm`. The user just learned that
    # pattern one level up, so erroring here taught the opposite of what the level above does.
    if (-not $Arguments.Count) { Show-PmxVmNetworkList -Arguments @(); return }

    $action = if ($Arguments.Count) { "$($Arguments[0])".ToLowerInvariant() } else { '' }
    $tail = Get-PmxCommandTail -Arguments $Arguments -Start 1
    switch ($action) {
        'adapters'  { Show-PmxVmNetwork -Arguments $tail -View adapters }
        'addresses' { Show-PmxVmNetwork -Arguments $tail -View addresses }
        'stats'     { Show-PmxVmNetwork -Arguments $tail -View stats }
        'list'      { Show-PmxVmNetworkList -Arguments $tail }
        default     { Show-PmxVmNetwork -Arguments $Arguments -View combined }
    }
}

