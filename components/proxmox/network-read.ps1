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
            '-a' { '--all' }
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
        'no-probe' = 'NoProbe'
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
    if (-not $resolved.Success) { Write-PmxResolveFailure -Resolved $resolved; return }
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
    $fleet = Get-PmxFleetNetworkModels -Session $session -Options $parsed.Options
    if (-not $fleet.Success) { Write-Host "❌ $($fleet.Error)" -ForegroundColor Red; return }
    $listModel = [pscustomobject][ordered]@{
        GeneratedAt = [DateTime]::UtcNow.ToString('o'); Node = $session.Node
        Vms = @($fleet.Models); Warnings = @($fleet.Warnings)
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

# ══════════════════════════════════════════════════════════════════════════════
#  PF-FEAT-008 — the fleet network + SSH status view
# ══════════════════════════════════════════════════════════════════════════════
# One question, asked constantly on a Proxmox box:
#
#   which VMs are running, what addresses do their agents report, and which of those
#   can I actually SSH into right now?
#
# Answering it by hand is `qm list`, then `qm guest cmd <vmid> network-get-interfaces`
# once per VM, then an ssh attempt per address.

<#
.SYNOPSIS
    Build the per-VM network model for every VM in the inventory. One data path.
.DESCRIPTION
    Both the list view and the status view need exactly this, and a second implementation
    of guest-interface parsing is precisely what a fleet view tends to grow. A VM whose
    config could not be read STAYS in the result as an explicitly-unavailable model — a
    fleet view that silently drops rows is worse than one that admits a gap.
#>
function Get-PmxFleetNetworkModels {
    param([Parameter(Mandatory)]$Session, [hashtable]$Options = @{})

    $inventory = Get-PmxManagedVmRows -Session $Session
    if (-not $inventory.Success) {
        return [pscustomobject]@{ Success = $false; Models = @(); Warnings = @(); Error = $inventory.Error }
    }
    $models = @()
    $warnings = @()
    foreach ($vm in @($inventory.Vms)) {
        $result = Get-PmxVmNetworkModel -Session $Session -Vm $vm -View combined -Options $Options
        if ($result.Success) { $models += $result.Model }
        else {
            $reason = "VM $($vm.VmId) network configuration could not be read."
            $models += New-PmxUnavailableVmNetworkModel -Vm $vm -Reason $reason
            $warnings += $reason
        }
    }
    return [pscustomobject]@{
        Success = $true; Error = ''
        Models = @($models | Sort-Object { $_.Vm.VmId })
        Warnings = @($warnings)
    }
}

<#
.SYNOPSIS
    The SSH port to try for one address: 22, unless a saved srv target names it.
.DESCRIPTION
    Correlation is by ADDRESS, never by name. A saved server called "web-prod" and a VM
    called "web-prod" are not evidence of anything — the same name gets reused across
    rebuilds, and probing the wrong port would report a healthy VM as closed. An exact
    host match is the only correlation confident enough to act on.
#>
function Get-PmxSshPortForAddress {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Address)

    if (-not $Address) { return 22 }
    if (-not (Get-Command Get-PFServers -ErrorAction SilentlyContinue)) { return 22 }
    try {
        foreach ($entry in (Get-PFServers).GetEnumerator()) {
            if ("$($entry.Value.host)" -ceq $Address) {
                $port = [int]$entry.Value.port
                if ($port -gt 0) { return $port }
            }
        }
    } catch {}
    return 22
}

<#
.SYNOPSIS
    Why a VM has no SSH answer, when it has none — or $null if it is worth probing.
.DESCRIPTION
    Three states that a lesser view would flatten into "failed", each with a different fix:

      stopped            start the VM
      agent-unavailable  install/start qemu-guest-agent, or enable agent=1
      no-address         the agent answered but reported nothing usable

    Flattening them is the failure the backlog called out by name, and it is the difference
    between a view that tells you what to do and one that tells you it did not work.
#>
function Get-PmxVmSshBlockedState {
    param([Parameter(Mandatory)]$Model)

    if ($Model.Vm.Template) { return 'stopped' }
    if ("$($Model.Vm.Status)" -ne 'running') { return 'stopped' }
    if (-not $Model.Agent.Available) { return 'agent-unavailable' }
    if (-not @($Model.AddressSelection.Candidates).Count) { return 'no-address' }
    return $null
}

<#
.SYNOPSIS
    One fleet row per VM: state, agent, primary address, extra count, SSH state.
#>
function Get-PmxNetworkStatusRows {
    param([object[]]$Models = @(), [switch]$NoProbe)

    $rows = @()
    $targets = @()
    foreach ($model in @($Models)) {
        $blocked = Get-PmxVmSshBlockedState -Model $model

        # The candidate list is what the PMX network layer already chose; this view does not
        # re-rank it. PrimaryCandidate is $null when several addresses tie, so the first
        # candidate is shown and the tie is visible in the +N count rather than hidden.
        $candidates = @($model.AddressSelection.Candidates)
        $primary = if ($model.AddressSelection.PrimaryCandidate) { "$($model.AddressSelection.PrimaryCandidate)" }
                   elseif ($candidates.Count) { "$($candidates[0].address)" }
                   else { '' }
        # Every reported address, not just the tied-best ones, so "+2" means what a reader
        # assumes it means.
        $allAddresses = @($model.Interfaces | ForEach-Object Addresses |
            Where-Object { $_.Valid -and $_.Scope -notin @('loopback', 'unspecified', 'multicast', 'invalid') } |
            ForEach-Object { "$($_.Address)" } | Select-Object -Unique)
        $extra = [Math]::Max(0, @($allAddresses).Count - 1)

        $ssh = if ($blocked) { $blocked } elseif ($NoProbe) { 'not-tested' } else { 'pending' }
        $port = if ($ssh -eq 'pending') { Get-PmxSshPortForAddress -Address $primary } else { 0 }

        $row = [pscustomobject][ordered]@{
            VmId = [int]$model.Vm.VmId; Name = "$($model.Vm.Name)"
            State = $(if ($model.Vm.Template) { 'template' } else { "$($model.Vm.Status)" })
            Agent = "$($model.Agent.Status)"
            Address = $primary; ExtraAddresses = $extra; Addresses = $allAddresses
            SshPort = $port; Ssh = $ssh
        }
        $rows += $row
        # Probed ONLY against an address the agent reported. No ARP, no DNS guessing, no
        # sweep of the subnet: if PMX does not know the address, the answer is "no-address",
        # not a scan for one.
        if ($ssh -eq 'pending') {
            $targets += [pscustomobject]@{ Key = "$($row.VmId)"; TargetHost = $primary; Port = $port }
        }
    }

    if ($targets.Count) {
        $reach = if (Get-Command Get-PFHostReachability -ErrorAction SilentlyContinue) {
            Get-PFHostReachability -Targets $targets
        } else { @{} }
        foreach ($row in $rows) {
            if ($row.Ssh -ne 'pending') { continue }
            # 'ready' means the TCP connection to the port succeeded. It does NOT mean the
            # host key was trusted, credentials were accepted, or a login succeeded, and the
            # help text says so in those words.
            $row.Ssh = switch ("$($reach["$($row.VmId)"])") {
                'online'  { 'ready' }
                'no-ssh'  { 'closed' }
                'offline' { 'unreachable' }
                default   { 'not-tested' }
            }
        }
    }
    return @($rows)
}

function Get-PmxSshStateColour {
    param([string]$State)
    switch ($State) {
        'ready'             { 'Green' }
        'closed'            { 'Yellow' }
        'unreachable'       { 'Red' }
        'no-address'        { 'Yellow' }
        'agent-unavailable' { 'Yellow' }
        'stopped'           { 'DarkGray' }
        default             { 'DarkGray' }
    }
}

function Show-PmxNetworkStatusFleet {
    param([object[]]$Rows = @(), [object[]]$Warnings = @(), [switch]$Explain)

    Write-Host ''
    Write-Host "🌐 VM NETWORK STATUS — $(@($Rows).Count) VMs" -ForegroundColor Cyan
    Write-Host '──────────────────────────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
    Write-Host ('  {0,-6} {1,-22} {2,-9} {3,-18} {4,-20} {5}' -f 'VMID', 'NAME', 'VM', 'AGENT', 'ADDRESS', 'SSH') -ForegroundColor DarkGray
    foreach ($row in @($Rows)) {
        $address = if ($row.Address) {
            if ($row.ExtraAddresses -gt 0) { "$($row.Address)  +$($row.ExtraAddresses)" } else { $row.Address }
        } else { '—' }
        Write-Host ('  {0,-6} {1,-22} {2,-9} {3,-18} {4,-20} ' -f $row.VmId,
            (ConvertTo-PmxDisplayText $row.Name), $row.State, $row.Agent, $address) -NoNewline -ForegroundColor White
        Write-Host $row.Ssh -ForegroundColor (Get-PmxSshStateColour $row.Ssh)
    }
    foreach ($warning in @($Warnings)) { Write-Host "  ⚠ $((ConvertTo-PmxDisplayText $warning))" -ForegroundColor Yellow }
    Write-Host ''
    Write-Host '  SSH "ready" means the TCP port answered — not that a login would succeed.' -ForegroundColor DarkGray
    if ($Explain) {
        Write-Host '  Addresses come from the VM agent only. No ARP, DNS, DHCP or subnet scanning is used,' -ForegroundColor DarkGray
        Write-Host '  so a VM with no agent data reads as agent-unavailable rather than being hunted for.' -ForegroundColor DarkGray
    }
    Write-Host ''
}

function Show-PmxNetworkStatusVm {
    param([Parameter(Mandatory)]$Model, [Parameter(Mandatory)]$Row, [switch]$Explain)

    Write-Host ''
    Write-Host "🌐 VM $($Row.VmId) — $((ConvertTo-PmxDisplayText $Row.Name))" -ForegroundColor Cyan
    Write-Host '────────────────────────────────────────────────' -ForegroundColor DarkGray
    Write-PmxField 'State' $Row.State
    Write-PmxField 'Agent' $Row.Agent
    Write-Host ('  {0,-13} ' -f 'SSH') -NoNewline -ForegroundColor White
    Write-Host "$($Row.Ssh)$(if ($Row.SshPort -and $Row.Ssh -in @('ready','closed','unreachable')) { "  (port $($Row.SshPort))" })" `
        -ForegroundColor (Get-PmxSshStateColour $Row.Ssh)
    if ($Model.Agent.Reason) { Write-Host "  $((ConvertTo-PmxDisplayText $Model.Agent.Reason))" -ForegroundColor DarkGray }

    Write-Host ''
    Write-Host '  INTERFACES' -ForegroundColor DarkGray
    $any = $false
    foreach ($interface in @($Model.Interfaces)) {
        foreach ($address in @($interface.Addresses)) {
            if (-not $address.Valid -or $address.Scope -in @('loopback', 'unspecified', 'multicast', 'invalid')) { continue }
            $any = $true
            $mark = if ("$($address.Address)" -ceq "$($Row.Address)") { '→' } else { ' ' }
            Write-Host ("  {0} {1,-16} {2,-20} {3,-9} {4}" -f $mark, (ConvertTo-PmxDisplayText $interface.Name),
                $address.Address, $address.Type, $address.Scope) -ForegroundColor White
        }
    }
    if (-not $any) { Write-Host '    — no usable address was reported' -ForegroundColor DarkGray }
    foreach ($warning in @($Model.Warnings)) { Write-Host "  ⚠ $((ConvertTo-PmxDisplayText $warning))" -ForegroundColor Yellow }
    Write-Host ''
    Write-Host '  SSH "ready" means the TCP port answered — not that a login would succeed.' -ForegroundColor DarkGray
    Write-Host ''
}

function ConvertTo-PmxNetworkStatusContract {
    param([object[]]$Rows = @(), [object[]]$Warnings = @())
    return [pscustomobject][ordered]@{
        generatedAt = [DateTime]::UtcNow.ToString('o')
        vms = @($Rows | ForEach-Object {
            [pscustomobject][ordered]@{
                vmid = $_.VmId; name = $_.Name; state = $_.State; agent = $_.Agent
                address = $(if ($_.Address) { $_.Address } else { $null })
                addresses = @($_.Addresses); sshPort = $(if ($_.SshPort) { $_.SshPort } else { $null })
                ssh = $_.Ssh
            }
        })
        warnings = @($Warnings)
        # Stated in the payload, not only in the human view: a consumer reading `ssh: ready`
        # must not take it for "a login would succeed".
        sshMeaning = 'ready = the TCP connection to the SSH port succeeded; it does not imply authentication would succeed'
    }
}

<#
.SYNOPSIS
    `pmx net status` (fleet) and `pmx net <vm> status` (one VM).
#>
function Show-PmxVmNetworkStatus {
    param([object[]]$Arguments = @())

    # `--all`/`-a` is accepted because the backlog specifies it, but bare `pmx net status`
    # already means the fleet — the same thing bare `pmx vm` and bare `pmx vm net` mean. A
    # user should not have to remember a flag to get the obvious answer.
    $parsed = Get-PmxNetworkInvocation -Arguments $Arguments -View list
    if (-not $parsed.Success) {
        # One positional is a VM selector, which the 'list' grammar rejects. Re-parse it as
        # the single-VM form rather than reporting the fleet grammar's complaint.
        $parsed = Get-PmxNetworkInvocation -Arguments $Arguments -View addresses
        if (-not $parsed.Success) { Write-Host "❌ $($parsed.Error)" -ForegroundColor Red; return }
    }
    if ($parsed.Options.Help) { Show-PmxTopicHelp 'vm network status'; return }

    $session = Get-PmxManagementSession
    if (-not $session.Success) { Write-PmxDisconnectedState -Session $session; return }
    $mode = Get-PmxOutputMode -Options $parsed.Options -Config $session.Config
    if (-not $mode.Success) { Write-Host "❌ $($mode.Error)" -ForegroundColor Red; return }
    $noProbe = $parsed.Options.ContainsKey('NoProbe')

    $selector = "$($parsed.Options.Selector)"
    if ($selector) {
        $resolved = Resolve-PmxManagedVm -Selector $selector -Session $session
        if (-not $resolved.Success) { Write-PmxResolveFailure -Resolved $resolved; return }
        $result = Get-PmxVmNetworkModel -Session $session -Vm $resolved.Vm -View combined -Options $parsed.Options
        $model = if ($result.Success) { $result.Model } else {
            New-PmxUnavailableVmNetworkModel -Vm $resolved.Vm -Reason "VM $($resolved.Vm.VmId) network configuration could not be read."
        }
        $rows = @(Get-PmxNetworkStatusRows -Models @($model) -NoProbe:$noProbe)
        if ($mode.Mode -eq 'json') { Write-PmxJson (ConvertTo-PmxNetworkStatusContract -Rows $rows -Warnings @($model.Warnings)); return }
        Show-PmxNetworkStatusVm -Model $model -Row $rows[0] -Explain:$parsed.Options.ContainsKey('Explain')
        return
    }

    $fleet = Get-PmxFleetNetworkModels -Session $session -Options $parsed.Options
    if (-not $fleet.Success) { Write-Host "❌ $($fleet.Error)" -ForegroundColor Red; return }
    $rows = @(Get-PmxNetworkStatusRows -Models $fleet.Models -NoProbe:$noProbe)
    if ($mode.Mode -eq 'json') { Write-PmxJson (ConvertTo-PmxNetworkStatusContract -Rows $rows -Warnings $fleet.Warnings); return }
    Show-PmxNetworkStatusFleet -Rows $rows -Warnings $fleet.Warnings -Explain:$parsed.Options.ContainsKey('Explain')
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
        'status'    { Show-PmxVmNetworkStatus -Arguments $tail }
        default     {
            # `pmx net 103 status` — selector first, action second, which is how the
            # backlog spells it and how a hand reaches for it. Only 'status' is accepted
            # in the trailing position; anything else stays the combined view, so this
            # cannot swallow an argument meant for something already working.
            if ($Arguments.Count -ge 2 -and "$($Arguments[-1])".ToLowerInvariant() -ceq 'status') {
                Show-PmxVmNetworkStatus -Arguments @($Arguments | Select-Object -SkipLast 1)
                return
            }
            Show-PmxVmNetwork -Arguments $Arguments -View combined
        }
    }
}

