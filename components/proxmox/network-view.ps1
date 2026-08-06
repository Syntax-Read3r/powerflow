# ==============================================================================
# PowerFlow — Proxmox VM Network Views
# ==============================================================================
# Domain   : Proxmox
# File     : components/proxmox/network-view.ps1
# Purpose  : Build stable JSON contracts and render VM network tables
# Functions: ConvertTo-PmxVmNetworkContract, ConvertTo-PmxVmNetworkListContract,
#            Show-PmxVmNetworkResult, Show-PmxVmNetworkListResult
# Depends  : shared.ps1
# ==============================================================================

function ConvertTo-PmxNetworkAdapterContract {
    param($Adapter)
    return [pscustomobject][ordered]@{
        adapter            = $Adapter.Adapter
        model              = $Adapter.Model
        bridge             = $Adapter.Bridge
        mac_address        = $Adapter.MacAddress
        firewall           = $Adapter.Firewall
        vlan               = $Adapter.Vlan
        link               = $Adapter.Link
        rate_limit_mbps    = $Adapter.RateLimitMbps
        mtu                = $Adapter.Mtu
        matched_interfaces = @($Adapter.MatchedInterfaces)
    }
}

function ConvertTo-PmxNetworkStatsContract {
    param($Stats)
    if ($null -eq $Stats) { return $null }
    return [pscustomobject][ordered]@{
        rx_bytes   = $Stats.RxBytes
        rx_packets = $Stats.RxPackets
        rx_errors  = $Stats.RxErrors
        rx_dropped = $Stats.RxDropped
        tx_bytes   = $Stats.TxBytes
        tx_packets = $Stats.TxPackets
        tx_errors  = $Stats.TxErrors
        tx_dropped = $Stats.TxDropped
    }
}

function ConvertTo-PmxNetworkInterfaceContract {
    param($Interface, [ValidateSet('combined', 'addresses', 'stats')][string]$View)

    $addresses = if ($View -eq 'stats') { @() } else { @($Interface.Addresses | ForEach-Object {
        [pscustomobject][ordered]@{
            address = $_.Address; prefix = $_.Prefix; cidr = $_.Cidr; type = $_.Type
            scope = $_.Scope; valid = $_.Valid
        }
    }) }
    return [pscustomobject][ordered]@{
        name            = $Interface.Name
        mac_address     = $Interface.MacAddress
        matched_adapter = $Interface.MatchedAdapter
        addresses       = $addresses
        stats           = if ($View -eq 'stats') { ConvertTo-PmxNetworkStatsContract $Interface.Stats } else { $null }
    }
}

function ConvertTo-PmxVmNetworkContract {
    param(
        [Parameter(Mandatory)]$Model,
        [ValidateSet('combined', 'adapters', 'addresses', 'stats')][string]$View,
        [switch]$ShowNative,
        [switch]$Explain
    )

    $includeAdapters = $View -in @('combined', 'adapters')
    $includeInterfaces = $View -in @('combined', 'addresses', 'stats')
    return [pscustomobject][ordered]@{
        schema_version    = '1.0'
        command           = "pmx vm network$(if ($View -ne 'combined') { " $View" })"
        generated_at      = $Model.GeneratedAt
        node              = $Model.Vm.Node
        vm                = [pscustomobject][ordered]@{
            vmid = $Model.Vm.VmId; name = $Model.Vm.Name; status = $Model.Vm.Status
            template = [bool]$Model.Vm.Template
        }
        agent             = [pscustomobject][ordered]@{
            configured = [bool]$Model.Agent.Configured
            available  = [bool]$Model.Agent.Available
            status     = $Model.Agent.Status
            reason     = $Model.Agent.Reason
        }
        adapters          = if ($includeAdapters) { @($Model.Adapters | ForEach-Object { ConvertTo-PmxNetworkAdapterContract $_ }) } else { @() }
        interfaces        = if ($includeInterfaces) { @($Model.Interfaces | ForEach-Object { ConvertTo-PmxNetworkInterfaceContract $_ $View }) } else { @() }
        address_selection = if ($View -in @('combined', 'addresses')) {
            [pscustomobject][ordered]@{
                primary_candidate = $Model.AddressSelection.PrimaryCandidate
                candidates        = @($Model.AddressSelection.Candidates)
                inferred          = [bool]$Model.AddressSelection.Inferred
                reason            = $Model.AddressSelection.Reason
            }
        } else { $null }
        sources           = [pscustomobject][ordered]@{
            configured = [pscustomobject][ordered]@{
                available = [bool]$Model.Sources.Configured.Available
                native_command = if ($ShowNative) { $Model.Sources.Configured.NativeCommand } else { $null }
            }
            vm_reported = [pscustomobject][ordered]@{
                available = [bool]$Model.Sources.VmReported.Available
                native_command = if ($ShowNative) { $Model.Sources.VmReported.NativeCommand } else { $null }
            }
        }
        warnings          = @($Model.Warnings)
        explanations      = if ($Explain) { @($Model.Explanations) } else { @() }
    }
}

function ConvertTo-PmxVmNetworkListContract {
    param([Parameter(Mandatory)]$Model, [switch]$ShowNative, [switch]$Explain)
    return [pscustomobject][ordered]@{
        schema_version = '1.0'
        command        = 'pmx vm network list'
        generated_at   = $Model.GeneratedAt
        node           = $Model.Node
        vms            = @($Model.Vms | ForEach-Object {
            ConvertTo-PmxVmNetworkContract -Model $_ -View combined -ShowNative:$ShowNative -Explain:$Explain
        })
        warnings       = @($Model.Warnings)
    }
}

function Write-PmxVmNetworkIdentity {
    param($Model, [string]$Title)
    Write-Host ''
    Write-Host "🌐 $Title — $($Model.Vm.VmId) $((ConvertTo-PmxDisplayText $Model.Vm.Name))" -ForegroundColor Cyan
    Write-Host '────────────────────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
    Write-PmxField 'Status' (ConvertTo-PmxDisplayText $Model.Vm.Status) $(if ($Model.Vm.Status -eq 'running') { 'Green' } else { 'Yellow' })
    Write-PmxField 'Agent' (ConvertTo-PmxDisplayText $Model.Agent.Status) $(if ($Model.Agent.Available) { 'Green' } else { 'Yellow' })
}

function Show-PmxNetworkAdapterTable {
    param([object[]]$Adapters = @())
    Write-Host ''
    Write-Host '  VIRTUAL ADAPTERS' -ForegroundColor Yellow
    Write-Host ('  {0,-8} {1,-9} {2,-10} {3,-17} {4,-9} {5,-6} {6}' -f 'ADAPTER', 'MODEL', 'BRIDGE', 'MAC ADDRESS', 'FIREWALL', 'VLAN', 'LINK') -ForegroundColor DarkGray
    if (-not $Adapters.Count) { Write-Host '  No configured virtual adapters.' -ForegroundColor DarkGray; return }
    foreach ($adapter in $Adapters) {
        $firewall = if ($null -eq $adapter.Firewall) { '—' } elseif ($adapter.Firewall) { 'on' } else { 'off' }
        Write-Host ('  {0,-8} {1,-9} {2,-10} {3,-17} {4,-9} {5,-6} {6}' -f
            $adapter.Adapter, $(if ($adapter.Model) { $adapter.Model } else { '—' }),
            $(if ($adapter.Bridge) { $adapter.Bridge } else { '—' }),
            $(if ($adapter.MacAddress) { $adapter.MacAddress } else { '—' }), $firewall,
            $(if ($null -ne $adapter.Vlan) { $adapter.Vlan } else { '—' }), $adapter.Link) -ForegroundColor White
    }
}

function Show-PmxNetworkAddressTable {
    param([object[]]$Interfaces = @())
    Write-Host ''
    Write-Host '  VM ADDRESSES' -ForegroundColor Yellow
    Write-Host ('  {0,-13} {1,-41} {2,-7} {3,-13} {4}' -f 'INTERFACE', 'ADDRESS', 'TYPE', 'SCOPE', 'ADAPTER') -ForegroundColor DarkGray
    $count = 0
    foreach ($interface in $Interfaces) {
        foreach ($address in @($interface.Addresses)) {
            $count++
            Write-Host ('  {0,-13} {1,-41} {2,-7} {3,-13} {4}' -f $interface.Name, $address.Cidr,
                $address.Type, $address.Scope, $(if ($interface.MatchedAdapter) { $interface.MatchedAdapter } else { '—' })) -ForegroundColor White
        }
    }
    if (-not $count) { Write-Host '  No addresses match the selected filters.' -ForegroundColor DarkGray }
}

function Format-PmxNetworkCounter {
    param($Value, [switch]$Bytes)
    if ($null -eq $Value) { return '—' }
    if ($Bytes) { return Format-PmxBytes ([long]$Value) }
    return ([long]$Value).ToString('N0')
}

function Get-PmxNetworkCounterSum {
    param($First, $Second)
    if ($null -eq $First -and $null -eq $Second) { return $null }
    return [long]$(if ($null -ne $First) { $First } else { 0 }) + [long]$(if ($null -ne $Second) { $Second } else { 0 })
}

function Show-PmxNetworkStatsTable {
    param([object[]]$Interfaces = @())
    Write-Host ''
    Write-Host '  NETWORK STATS' -ForegroundColor Yellow
    Write-Host ('  {0,-13} {1,11} {2,12} {3,11} {4,12} {5,9} {6,9}' -f
        'INTERFACE', 'RX BYTES', 'RX PACKETS', 'TX BYTES', 'TX PACKETS', 'ERRORS', 'DROPPED') -ForegroundColor DarkGray
    $count = 0
    foreach ($interface in $Interfaces) {
        if ($null -eq $interface.Stats) { continue }
        $count++
        $errors = Get-PmxNetworkCounterSum $interface.Stats.RxErrors $interface.Stats.TxErrors
        $dropped = Get-PmxNetworkCounterSum $interface.Stats.RxDropped $interface.Stats.TxDropped
        Write-Host ('  {0,-13} {1,11} {2,12} {3,11} {4,12} {5,9} {6,9}' -f $interface.Name,
            (Format-PmxNetworkCounter $interface.Stats.RxBytes -Bytes),
            (Format-PmxNetworkCounter $interface.Stats.RxPackets),
            (Format-PmxNetworkCounter $interface.Stats.TxBytes -Bytes),
            (Format-PmxNetworkCounter $interface.Stats.TxPackets),
            (Format-PmxNetworkCounter $errors), (Format-PmxNetworkCounter $dropped)) -ForegroundColor White
    }
    if (-not $count) { Write-Host '  Traffic counters are unavailable.' -ForegroundColor DarkGray }
}

function Show-PmxVmNetworkResult {
    param(
        [Parameter(Mandatory)]$Model,
        [ValidateSet('combined', 'adapters', 'addresses', 'stats')][string]$View,
        [switch]$ShowNative,
        [switch]$Explain
    )

    $title = switch ($View) { 'adapters' { 'VM ADAPTERS' }; 'addresses' { 'VM ADDRESSES' }; 'stats' { 'VM NETWORK STATS' }; default { 'VM NETWORK' } }
    Write-PmxVmNetworkIdentity -Model $Model -Title $title
    if ($View -in @('combined', 'adapters')) { Show-PmxNetworkAdapterTable $Model.Adapters }
    if ($View -in @('combined', 'addresses')) {
        Show-PmxNetworkAddressTable $Model.Interfaces
        Write-Host ''
        Write-PmxField 'Primary candidate' $(if ($Model.AddressSelection.PrimaryCandidate) { $Model.AddressSelection.PrimaryCandidate } else { '—' })
    }
    if ($View -eq 'stats') { Show-PmxNetworkStatsTable $Model.Interfaces }
    foreach ($warning in @($Model.Warnings)) { Write-Host "  ⚠ $((ConvertTo-PmxDisplayText $warning))" -ForegroundColor Yellow }
    if ($Explain) { foreach ($line in @($Model.Explanations)) { Write-Host "  ℹ $((ConvertTo-PmxDisplayText $line))" -ForegroundColor DarkGray } }
    if ($ShowNative) {
        if ($View -in @('combined', 'adapters') -and $Model.Sources.Configured.NativeCommand) { Write-PmxField 'Native read' $Model.Sources.Configured.NativeCommand DarkGray }
        if ($View -in @('combined', 'addresses', 'stats') -and $Model.Sources.VmReported.NativeCommand) { Write-PmxField 'Native read' $Model.Sources.VmReported.NativeCommand DarkGray }
    }
    Write-Host ''
}

function Show-PmxVmNetworkListResult {
    param([Parameter(Mandatory)]$Model, [switch]$ShowNative, [switch]$Explain, [switch]$IPv6Only)
    Write-Host ''
    Write-Host "🌐 VM NETWORKS — $($Model.Vms.Count) VMs" -ForegroundColor Cyan
    Write-Host '────────────────────────────────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
    Write-Host ('  {0,-7} {1,-23} {2,-10} {3,-8} {4,-10} {5,-15} {6}' -f
        'VMID', 'NAME', 'STATUS', 'ADAPTER', 'BRIDGE', $(if ($IPv6Only) { 'IPv6' } else { 'IPv4' }), 'AGENT') -ForegroundColor DarkGray
    foreach ($vmModel in @($Model.Vms)) {
        $adapterRows = @($vmModel.Adapters)
        if (-not $adapterRows.Count) { $adapterRows = @($null) }
        foreach ($adapter in $adapterRows) {
            $address = @($vmModel.Interfaces | Where-Object { -not $adapter -or $_.MatchedAdapter -ceq $adapter.Adapter } |
                ForEach-Object Addresses | Where-Object { $_.Type -eq $(if ($IPv6Only) { 'IPv6' } else { 'IPv4' }) -and $_.Scope -notin @('loopback', 'unspecified') } |
                Select-Object -First 1)
            Write-Host ('  {0,-7} {1,-23} {2,-10} {3,-8} {4,-10} {5,-15} {6}' -f $vmModel.Vm.VmId,
                $vmModel.Vm.Name, $(if ($vmModel.Vm.Template) { 'template' } else { $vmModel.Vm.Status }),
                $(if ($adapter) { $adapter.Adapter } else { '—' }),
                $(if ($adapter -and $adapter.Bridge) { $adapter.Bridge } else { '—' }),
                $(if ($address.Count) { $address[0].Address } else { '—' }), $vmModel.Agent.Status) -ForegroundColor White
        }
    }
    foreach ($warning in @($Model.Warnings)) { Write-Host "  ⚠ $((ConvertTo-PmxDisplayText $warning))" -ForegroundColor Yellow }
    if ($Explain) { Write-Host '  ℹ VM addresses are reported by the VM agent; blank addresses are not inferred from host tables.' -ForegroundColor DarkGray }
    if ($ShowNative) { Write-Host '  Native reads are included only in JSON for the multi-VM view; use a focused VM command for readable details.' -ForegroundColor DarkGray }
    Write-Host ''
}
