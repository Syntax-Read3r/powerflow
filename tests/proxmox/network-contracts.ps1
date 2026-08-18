. (Join-Path $PSScriptRoot 'test-helpers.ps1')
function Register-PFCommand {}
. (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' 'shared.ps1')
. (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' 'network-config-model.ps1')
. (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' 'guest-network-model.ps1')
. (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' 'network-view.ps1')
. (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' 'network-read.ps1')

$config = [pscustomobject]@{
    agent = 'enabled=1,type=virtio'
    net10 = 'e1000=00-11-22-33-44-66,bridge=vmbr1,tag=20,link_down=1'
    net2 = "virtio=AA:BB:CC:DD:EE:FF,bridge=vmbr0,firewall=1,rate=100,mtu=1500$([char]27)[31m"
}
$adapters = @(Get-PmxConfiguredNetworkAdapters $config)
Assert-PmxTest ($adapters.Count -eq 2 -and $adapters[0].Adapter -ceq 'net2' -and $adapters[1].Adapter -ceq 'net10') `
    'Configured adapters were not sorted by numeric slot.'
Assert-PmxTest ($adapters[0].MacAddress -ceq 'AA:BB:CC:DD:EE:FF' -and $adapters[0].Firewall -eq $true -and
    $adapters[0].Mtu -eq 1500 -and $adapters[0].Raw -notmatch [regex]::Escape([char]27)) `
    'Configured adapter parsing, MAC normalization, or sanitization failed.'
Assert-PmxTest ($adapters[1].Link -ceq 'down' -and $adapters[1].Vlan -eq 20) `
    'Configured adapter VLAN or link state was not modeled.'
Assert-PmxTest (Get-PmxVmAgentConfiguration $config).Configured 'Enabled VM-agent configuration was not detected.'
Assert-PmxTest (-not (Get-PmxVmAgentConfiguration ([pscustomobject]@{ agent = '0' })).Configured) `
    'Disabled VM-agent configuration was treated as enabled.'

$reported = @(
    [pscustomobject]@{
        name = 'ens18'; 'hardware-address' = 'aa-bb-cc-dd-ee-ff'
        'ip-addresses' = @(
            [pscustomobject]@{ 'ip-address' = '192.168.1.50'; prefix = 24 },
            [pscustomobject]@{ 'ip-address' = 'fe80::1133:ba8a:e6dc:a5a2'; prefix = 64 },
            [pscustomobject]@{ 'ip-address' = '0.0.0.0'; prefix = 0 }
        )
        statistics = [pscustomobject]@{
            'rx-bytes' = 2048; 'rx-packets' = 20; 'rx-errs' = 1; 'rx-dropped' = 2
            'tx-bytes' = 4096; 'tx-packets' = 30; 'tx-errs' = 3; 'tx-dropped' = 4
        }
    },
    [pscustomobject]@{
        name = 'lo'; 'hardware-address' = '00:00:00:00:00:00'
        'ip-addresses' = @([pscustomobject]@{ 'ip-address' = '127.0.0.1'; prefix = 8 })
    }
)
$interfaces = @(Get-PmxVmReportedNetworkInterfaces $reported)
$joined = Join-PmxNetworkAdapters -Adapters $adapters -Interfaces $interfaces
Assert-PmxTest (@($joined.Interfaces | Where-Object Name -eq 'ens18' | Where-Object MatchedAdapter -eq 'net2').Count -eq 1) `
    'Valid equal MAC addresses did not join configured and VM-reported records.'
$filtered = @(Select-PmxNetworkAddresses $joined.Interfaces)
Assert-PmxTest (@($filtered | ForEach-Object Addresses).Count -eq 2) `
    'Default filtering did not hide loopback and unspecified addresses.'
$all = @(Select-PmxNetworkAddresses $joined.Interfaces -All)
Assert-PmxTest (@($all | ForEach-Object Addresses).Count -eq 4) '--all did not retain every valid reported address.'
$ipv6 = @(Select-PmxNetworkAddresses $joined.Interfaces -IPv6)
Assert-PmxTest (@($ipv6 | ForEach-Object Addresses).Count -eq 1 -and
    @($ipv6 | ForEach-Object Addresses)[0].Scope -ceq 'link-local') 'IPv6 filtering or link-local classification failed.'
$selection = Get-PmxPrimaryAddressSelection $filtered
Assert-PmxTest ($selection.PrimaryCandidate -ceq '192.168.1.50' -and $selection.Inferred) `
    'Primary address ranking did not prefer the matched private IPv4 address.'
Assert-PmxTest ((Get-PmxNetworkAddressRecord '10.0.0.1').Scope -ceq 'private') 'IPv4 private classification failed.'
Assert-PmxTest ((Get-PmxNetworkAddressRecord '169.254.1.1').Scope -ceq 'link-local') 'IPv4 link-local classification failed.'
Assert-PmxTest ((Get-PmxNetworkAddressRecord 'fc00::1').Scope -ceq 'unique-local') 'IPv6 unique-local classification failed.'
Assert-PmxTest ((Get-PmxNetworkAddressRecord 'ff02::1').Scope -ceq 'multicast') 'IPv6 multicast classification failed.'

$model = [pscustomobject][ordered]@{
    GeneratedAt = '2026-08-06T00:00:00.0000000Z'
    Vm = [pscustomobject]@{ VmId = 102; Name = 'docker-host'; Node = 'pve'; Status = 'running'; Template = $false }
    Agent = [pscustomobject]@{ Configured = $true; Available = $true; Status = 'available'; Reason = $null }
    Adapters = $joined.Adapters; Interfaces = $filtered; AddressSelection = $selection
    Sources = [pscustomobject]@{
        Configured = [pscustomobject]@{ Available = $true; NativeCommand = 'pvesh fixture' }
        VmReported = [pscustomobject]@{ Available = $true; NativeCommand = 'qm guest cmd 102 network-get-interfaces' }
    }
    Warnings = @(); Explanations = @('fixture')
}
$contract = ConvertTo-PmxVmNetworkContract -Model $model -View addresses
$json = $contract | ConvertTo-Json -Depth 12 -Compress
Assert-PmxTest ($json -match '"primary_candidate":"192.168.1.50"' -and $json -match '"native_command":null') `
    'Address JSON omitted the primary candidate or leaked native vocabulary by default.'
$nativeJson = ConvertTo-PmxVmNetworkContract -Model $model -View addresses -ShowNative | ConvertTo-Json -Depth 12 -Compress
Assert-PmxTest ($nativeJson -match [regex]::Escape('qm guest cmd 102 network-get-interfaces')) `
    '--show-native did not reveal the translated VM-agent read.'
$statsContract = ConvertTo-PmxVmNetworkContract -Model $model -View stats
$statsJson = $statsContract | ConvertTo-Json -Depth 12 -Compress
Assert-PmxTest ($statsJson -match '"rx_bytes":2048' -and $statsJson -match '"tx_dropped":4') `
    'Stats JSON lost exact integer counters.'
$rendered = (@(& { Show-PmxVmNetworkResult -Model $model -View combined } 6>&1 | ForEach-Object { "$_" }) -join "`n")
Assert-PmxTest ($rendered -match 'VIRTUAL ADAPTERS' -and $rendered -match 'VM ADDRESSES' -and
    $rendered -match 'Primary candidate\s+192\.168\.1\.50' -and $rendered -notmatch 'guest cmd') `
    'Combined table omitted its public contract or exposed internal command vocabulary.'

$short = Get-PmxNetworkInvocation -Arguments @('102', '-4', '-j') -View addresses
Assert-PmxTest ($short.Success -and $short.Options.IPv4 -and $short.Options.Json) `
    'Documented network short options did not parse.'
foreach ($bad in @(@('102', '-tj'), @('102', '-table'), @('102', '-j', '--json'))) {
    Assert-PmxTest (-not (Get-PmxNetworkInvocation -Arguments $bad -View addresses).Success) `
        "Network parser accepted invalid or duplicate short options: $($bad -join ' ')"
}
Assert-PmxTest (-not (Get-PmxNetworkInvocation -Arguments @('102', '-4') -View stats).Success) `
    'Stats view silently accepted an address-only filter.'

$script:networkQueryMode = 'running'
$script:runtimeQueryCount = 0
function Invoke-ProxmoxManagementQuery {
    param([string]$Operation, $Connection, [hashtable]$Parameters)
    switch ($Operation) {
        'vm-config' {
            $agentValue = if ($script:networkQueryMode -eq 'disabled') { '0' } else { '1' }
            return [pscustomobject]@{
                Success = $true; Data = [pscustomobject]@{ agent = $agentValue; net0 = 'virtio=AA:BB:CC:DD:EE:FF,bridge=vmbr0' }
                Error = ''; NativeCommand = 'pvesh fixture'; FailureKind = ''
            }
        }
        'vm-status' {
            $state = if ($script:networkQueryMode -eq 'stopped') { 'stopped' } else { 'running' }
            return [pscustomobject]@{ Success = $true; Data = [pscustomobject]@{ status = $state }; Error = ''; NativeCommand = 'status fixture'; FailureKind = '' }
        }
        'vm-guest-network' {
            $script:runtimeQueryCount++
            if ($script:networkQueryMode -eq 'timeout') {
                return [pscustomobject]@{ Success = $false; Data = $null; Error = 'safe failure'; NativeCommand = 'private fixture'; FailureKind = 'timeout' }
            }
            return [pscustomobject]@{ Success = $true; Data = $reported; Error = ''; NativeCommand = 'private fixture'; FailureKind = '' }
        }
        default { throw "Unexpected network fixture query: $Operation" }
    }
}
$session = [pscustomobject]@{ Connection = [pscustomobject]@{}; Node = 'pve' }
$runningVm = [pscustomobject]@{ VmId = 102; Name = 'docker-host'; Node = 'pve'; Status = 'running'; Template = $false }
$runtimeQueryCount = 0
$runningModel = Get-PmxVmNetworkModel -Session $session -Vm $runningVm -View combined
Assert-PmxTest ($runningModel.Success -and $runningModel.Model.Agent.Available -and $script:runtimeQueryCount -eq 1) `
    'Running, configured VM did not perform exactly one VM-agent network read.'
$script:networkQueryMode = 'stopped'; $script:runtimeQueryCount = 0
$stoppedModel = Get-PmxVmNetworkModel -Session $session -Vm $runningVm -View combined
Assert-PmxTest ($stoppedModel.Model.Agent.Status -ceq 'stopped' -and $script:runtimeQueryCount -eq 0) `
    'Stopped VM queried runtime data or lost its non-fatal agent state.'
$script:networkQueryMode = 'disabled'; $script:runtimeQueryCount = 0
$disabledModel = Get-PmxVmNetworkModel -Session $session -Vm $runningVm -View addresses
# 'not-configured', not 'disabled' (PF-UX-003): nothing was turned off, the channel was never
# enabled — and the fix differs, since you add agent=1 rather than re-enabling something.
Assert-PmxTest ($disabledModel.Model.Agent.Status -ceq 'not-configured' -and $script:runtimeQueryCount -eq 0) `
    'An unconfigured agent channel still triggered a runtime read.'
Assert-PmxTest ([bool]$disabledModel.Model.Agent.Reason) `
    'Every non-available agent state must carry a Reason - the state alone is what made this a dead end.'
$script:networkQueryMode = 'timeout'; $script:runtimeQueryCount = 0
$timeoutModel = Get-PmxVmNetworkModel -Session $session -Vm $runningVm -View addresses
Assert-PmxTest ($timeoutModel.Model.Agent.Status -ceq 'timed-out' -and
    ($timeoutModel.Model.Warnings -join ' ') -notmatch 'private fixture') `
    'VM-agent timeout was not safely categorized.'
function Get-PmxManagementSession {
    return [pscustomobject]@{ Success = $true; Connection = [pscustomobject]@{}; Node = 'pve'; Config = [pscustomobject]@{ Output = 'table' }; Error = '' }
}
function Resolve-PmxManagedVm {
    return [pscustomobject]@{ Success = $true; Vm = $runningVm; Error = '' }
}
$script:networkQueryMode = 'running'; $script:runtimeQueryCount = 0
$commandJson = @(Show-PmxVmNetwork -Arguments @('102', '--json') -View addresses) -join "`n"
$parsedCommandJson = $commandJson | ConvertFrom-Json
Assert-PmxTest ($parsedCommandJson.vm.vmid -eq 102 -and $parsedCommandJson.address_selection.primary_candidate -ceq '192.168.1.50' -and
    $commandJson -notmatch 'qm guest cmd') 'Successful --json command output was impure or leaked the native read.'
$nativeCommandJson = @(Show-PmxVmNetwork -Arguments @('102', '--json', '--show-native') -View addresses) -join "`n"
Assert-PmxTest ($nativeCommandJson -match [regex]::Escape('qm guest cmd 102 network-get-interfaces')) `
    'Command-level --show-native did not populate the JSON source contract.'
$unavailable = New-PmxUnavailableVmNetworkModel -Vm $runningVm -Reason 'configuration unavailable'
Assert-PmxTest ($unavailable.Vm.VmId -eq 102 -and -not $unavailable.Sources.Configured.Available) `
    'All-VM failure model dropped VM identity or fabricated an available source.'
$networkSource = @('network-config-model.ps1', 'guest-network-model.ps1', 'network-view.ps1', 'network-read.ps1') |
    ForEach-Object { Get-Content -Raw (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' $_) }
Assert-PmxTest (($networkSource -join "`n") -notmatch '\bInvoke-ProxmoxManagementChange\b') `
    'A read-only network component references the mutation adapter.'
Write-PmxTestPass 'VM network models, source separation, output contracts, and short options'
