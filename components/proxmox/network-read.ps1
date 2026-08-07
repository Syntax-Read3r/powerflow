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
        Agent = New-PmxNetworkAgentState $false $false 'unavailable' $Reason
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

function Get-PmxVmAgentFailureState {
    param($Result)

    $kind = "$(Get-PmxObjectProperty $Result 'FailureKind' '')".ToLowerInvariant()
    switch ($kind) {
        'timeout' { New-PmxNetworkAgentState $true $false 'timed-out' 'VM agent did not respond before the timeout.' }
        'unsupported' { New-PmxNetworkAgentState $true $false 'unsupported' 'VM agent network reporting is unsupported.' }
        'agent-unavailable' { New-PmxNetworkAgentState $true $false 'unavailable' 'VM agent is not available inside the running VM.' }
        default { New-PmxNetworkAgentState $true $false 'unavailable' 'VM agent did not return network information.' }
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
        return [pscustomobject]@{ Success = $false; Model = $null; Error = $configResult.Error }
    }
    $adapters = @(Get-PmxConfiguredNetworkAdapters -Config $configResult.Data)
    $agentConfig = Get-PmxVmAgentConfiguration -Config $configResult.Data
    $warnings = @()
    $status = "$($Vm.Status)"
    $statusNative = $null
    $statusAvailable = ($View -eq 'adapters')
    if ($View -ne 'adapters') {
        $statusResult = Invoke-ProxmoxManagementQuery -Operation 'vm-status' -Connection $Session.Connection -Parameters $parameters
        if ($statusResult.Success) {
            $status = "$(ConvertTo-PmxDisplayText (Get-PmxObjectProperty $statusResult.Data 'status' $status))"
            $statusNative = $statusResult.NativeCommand
            $statusAvailable = $true
        }
        else { $warnings += 'Current VM status could not be read; VM-reported network data was not queried.' }
    }

    $vmModel = [pscustomobject][ordered]@{
        VmId = [int]$Vm.VmId; Name = $Vm.Name; Node = $Vm.Node; Status = $status; Template = [bool]$Vm.Template
    }
    $agent = New-PmxNetworkAgentState ([bool]$agentConfig.Configured) $false 'not-queried' $null
    $interfaces = @()
    $runtimeNative = $null
    $shouldReadRuntime = $View -ne 'adapters' -and -not $Vm.Template -and $status -eq 'running' -and $agentConfig.Configured -and $statusNative
    if ($View -eq 'adapters') {
        $agent = New-PmxNetworkAgentState ([bool]$agentConfig.Configured) $false 'not-requested' 'Adapter configuration does not require the VM agent.'
    }
    elseif ($Vm.Template) {
        $agent = New-PmxNetworkAgentState ([bool]$agentConfig.Configured) $false 'template' 'Templates have no running operating system to report addresses.'
    }
    elseif ($status -ne 'running') {
        $agent = New-PmxNetworkAgentState ([bool]$agentConfig.Configured) $false 'stopped' 'Start the VM before requesting VM-reported addresses or stats.'
    }
    elseif (-not $agentConfig.Configured) {
        $agent = New-PmxNetworkAgentState $false $false 'disabled' 'The VM agent channel is not enabled in this VM configuration.'
    }
    elseif (-not $statusAvailable) {
        $agent = New-PmxNetworkAgentState $true $false 'unavailable' 'Current VM status could not be verified.'
    }
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
    if (-not $result.Success) { Write-Host "❌ $($result.Error)" -ForegroundColor Red; return }
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

