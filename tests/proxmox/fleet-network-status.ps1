# ==============================================================================
# PF-FEAT-008 (b2) — the fleet network + SSH status view
# ==============================================================================
# One question, asked constantly on a Proxmox box: which VMs are running, what addresses
# do their agents report, and which of those can I actually SSH into right now?
#
# Two requirements in this item carry real weight, and both are about what the view must
# NOT do:
#
#   1. Do not flatten `agent-unavailable`, `no-address` and `closed` into one failure.
#      Each has a different fix — start the agent, look at the guest, look at sshd — and a
#      generic "failed" sends someone to debug the wrong layer.
#
#   2. Do not scan. No ARP, no DNS guessing, no DHCP leases, no ping sweep, no port scan
#      across the subnet. If PMX does not know the address, the answer is "no-address" and
#      that is the end of it. A network tool that quietly probes a /24 is a different and
#      much less welcome kind of tool.
#
# And one about what `ready` MEANS: the TCP port answered. Not that a login would succeed.
# ==============================================================================

. (Join-Path $PSScriptRoot 'test-helpers.ps1')

$root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

function Register-PFCommand { }
. (Join-Path $root 'components/proxmox/shared.ps1')

# Extract just the status layer. Loading network-read.ps1 whole would pull in the session,
# the adapter and the router.
$text = Get-Content -LiteralPath (Join-Path $root 'components/proxmox/network-read.ps1') -Raw
$ast  = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$null)
foreach ($name in @('Get-PmxVmSshBlockedState', 'Get-PmxNetworkStatusRows', 'Get-PmxSshPortForAddress',
                    'Get-PmxSshStateColour', 'ConvertTo-PmxNetworkStatusContract')) {
    $fn = $ast.FindAll({
        $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $args[0].Name -eq $name }, $true)
    Assert-PmxTest ($fn.Count -eq 1) "could not extract $name"
    Invoke-Expression $fn[0].Extent.Text
}

# ── the probe, recorded rather than performed ────────────────────────────────
# Standing in for Get-PFHostReachability lets this assert WHAT was probed, which is the
# only way to prove the no-scanning rule rather than assert it in a comment.
$script:Probed = @()
$script:ProbeResults = @{}
function Get-PFHostReachability {
    param([object[]]$Targets = @(), [int]$TimeoutMs = 1200, [int]$PingTimeoutMs = 800, [int]$ThrottleLimit = 8)
    foreach ($t in @($Targets)) { $script:Probed += "$($t.TargetHost):$($t.Port)" }
    $map = @{}
    foreach ($t in @($Targets)) {
        $map["$($t.Key)"] = if ($script:ProbeResults.ContainsKey("$($t.TargetHost)")) {
            $script:ProbeResults["$($t.TargetHost)"]
        } else { 'offline' }
    }
    return $map
}

function New-Model {
    param(
        [int]$VmId, [string]$Name, [string]$Status = 'running', [bool]$Template = $false,
        [string]$AgentStatus = 'available', [bool]$AgentAvailable = $true,
        [string[]]$Addresses = @(), [string]$Primary = ''
    )
    $addressRows = @($Addresses | ForEach-Object {
        [pscustomobject]@{ Address = $_; Cidr = "$_/24"; Type = 'IPv4'; Scope = 'private'; Valid = $true }
    })
    $candidates = @()
    if ($Primary) { $candidates = @([pscustomobject]@{ address = $Primary; type = 'IPv4'; scope = 'private' }) }
    elseif ($Addresses.Count) { $candidates = @($Addresses | ForEach-Object { [pscustomobject]@{ address = $_; type = 'IPv4'; scope = 'private' } }) }

    return [pscustomobject]@{
        Vm = [pscustomobject]@{ VmId = $VmId; Name = $Name; Status = $Status; Template = $Template; Node = 'pve' }
        Agent = [pscustomobject]@{ Configured = $true; Available = $AgentAvailable; Status = $AgentStatus; Reason = $null }
        Interfaces = @([pscustomobject]@{ Name = 'eth0'; MatchedAdapter = 'net0'; Addresses = $addressRows })
        AddressSelection = [pscustomobject]@{
            PrimaryCandidate = $(if ($Primary) { $Primary } else { $null })
            Candidates = $candidates; Inferred = $true; Reason = ''
        }
        Warnings = @()
    }
}

Write-Host 'PF-FEAT-008 fleet network status'

# ── 1. the five non-probe states, each distinct ──────────────────────────────
$cases = @(
    @{ Model = (New-Model -VmId 100 -Name 'base' -Status 'stopped' -AgentStatus 'stopped' -AgentAvailable $false)
       Expect = 'stopped'; Why = 'a stopped VM' }
    @{ Model = (New-Model -VmId 199 -Name 'tmpl' -Status 'stopped' -Template $true -AgentStatus 'template' -AgentAvailable $false)
       Expect = 'stopped'; Why = 'a template has no running OS' }
    @{ Model = (New-Model -VmId 101 -Name 'noagent' -AgentStatus 'not-responding' -AgentAvailable $false)
       Expect = 'agent-unavailable'; Why = 'running, agent silent' }
    @{ Model = (New-Model -VmId 102 -Name 'notconf' -AgentStatus 'not-configured' -AgentAvailable $false)
       Expect = 'agent-unavailable'; Why = 'agent channel never enabled' }
    @{ Model = (New-Model -VmId 103 -Name 'noaddr' -AgentStatus 'available' -AgentAvailable $true -Addresses @())
       Expect = 'no-address'; Why = 'agent answered but reported nothing usable' }
)
foreach ($case in $cases) {
    $got = Get-PmxVmSshBlockedState -Model $case.Model
    Assert-PmxTest ($got -ceq $case.Expect) "$($case.Why): expected '$($case.Expect)', got '$got'"
}
$reachable = New-Model -VmId 104 -Name 'ok' -Addresses @('10.0.0.5') -Primary '10.0.0.5'
Assert-PmxTest ($null -eq (Get-PmxVmSshBlockedState -Model $reachable)) 'a reachable VM is not blocked, so it gets probed'
Write-PmxTestPass 'stopped / agent-unavailable / no-address stay three different answers'

# They must be three DIFFERENT strings, not three labels for one value.
$distinct = @($cases | ForEach-Object { $_.Expect } | Sort-Object -Unique)
Assert-PmxTest ($distinct.Count -eq 3) 'the blocked states must not collapse into one'
Write-PmxTestPass 'the states are not flattened'

# ── 2. the probe outcomes ────────────────────────────────────────────────────
$script:Probed = @()
$script:ProbeResults = @{ '10.0.0.5' = 'online'; '10.0.0.6' = 'no-ssh'; '10.0.0.7' = 'offline' }
$models = @(
    (New-Model -VmId 104 -Name 'ready-vm'  -Addresses @('10.0.0.5') -Primary '10.0.0.5')
    (New-Model -VmId 105 -Name 'closed-vm' -Addresses @('10.0.0.6') -Primary '10.0.0.6')
    (New-Model -VmId 106 -Name 'gone-vm'   -Addresses @('10.0.0.7') -Primary '10.0.0.7')
)
$rows = @(Get-PmxNetworkStatusRows -Models $models)
Assert-PmxTest ((@($rows | Where-Object VmId -eq 104).Ssh) -ceq 'ready') 'a TCP connect that succeeds is ready'
Assert-PmxTest ((@($rows | Where-Object VmId -eq 105).Ssh) -ceq 'closed') 'host answers, port does not = closed'
Assert-PmxTest ((@($rows | Where-Object VmId -eq 106).Ssh) -ceq 'unreachable') 'nothing answers = unreachable'
Write-PmxTestPass 'ready / closed / unreachable are told apart'

# ── 3. NO SCANNING. The rule with the sharpest edge. ─────────────────────────
# Only addresses the agent actually reported may be probed, and nothing else at all.
$script:Probed = @()
$mixed = @(
    (New-Model -VmId 100 -Name 'stopped-vm' -Status 'stopped' -AgentAvailable $false)
    (New-Model -VmId 101 -Name 'no-agent'   -AgentStatus 'not-responding' -AgentAvailable $false)
    (New-Model -VmId 102 -Name 'no-address' -Addresses @())
    (New-Model -VmId 104 -Name 'ready-vm'   -Addresses @('10.0.0.5') -Primary '10.0.0.5')
)
$null = Get-PmxNetworkStatusRows -Models $mixed
Assert-PmxTest ($script:Probed.Count -eq 1) "only the one known address may be probed; probed: $($script:Probed -join ', ')"
Assert-PmxTest ($script:Probed[0] -ceq '10.0.0.5:22') "the probe must target the reported address on 22; got $($script:Probed[0])"
Write-PmxTestPass 'a VM with no known address is never hunted for'

# And nothing in the source may reach for a discovery mechanism.
# Comments are blanked IN PLACE before the scan. The function's own comment says "No ARP,
# no DNS guessing" — a naive substring search finds that and fails on the promise instead
# of on a breach of it. Blanking in place rather than rebuilding from tokens keeps every
# offset intact, so a match still points at the right line.
function Remove-PSComment {
    param([string]$Source)
    $tokens = $null
    $null = [System.Management.Automation.Language.Parser]::ParseInput($Source, [ref]$tokens, [ref]$null)
    $builder = [Text.StringBuilder]::new($Source)
    foreach ($token in @($tokens | Where-Object { $_.Kind -eq 'Comment' })) {
        $start = $token.Extent.StartOffset
        $length = $token.Extent.EndOffset - $start
        $null = $builder.Remove($start, $length).Insert($start, (' ' * $length))
    }
    return $builder.ToString()
}

$statusSrc = [regex]::Match((Remove-PSComment $text), '(?s)function Get-PmxNetworkStatusRows \{.*?\n\}').Value
Assert-PmxTest ($statusSrc.Length -gt 0) 'could not read Get-PmxNetworkStatusRows'
Assert-PmxTest ($statusSrc -notmatch 'Probed ONLY against') 'precondition: comments really were blanked'
foreach ($forbidden in @('arp', 'Resolve-DnsName', 'nslookup', 'dhcp', 'Test-Connection', 'nmap', 'Get-NetNeighbor', 'ping')) {
    Assert-PmxTest ($statusSrc -notmatch "(?i)$forbidden") `
        "the status view must not use $forbidden — the item forbids discovery of any kind"
}
Write-PmxTestPass 'no ARP, DNS, DHCP or sweep anywhere in the status path'

# ── 4. --no-probe touches the network not at all ─────────────────────────────
$script:Probed = @()
$rows = @(Get-PmxNetworkStatusRows -Models $models -NoProbe)
Assert-PmxTest ($script:Probed.Count -eq 0) 'no-probe must make no connections'
Assert-PmxTest (@($rows | Where-Object { $_.Ssh -ceq 'not-tested' }).Count -eq 3) 'and every probeable row reads not-tested'
# A blocked VM still reports WHY it is blocked; --no-probe suppresses the probe, not the facts.
$rows = @(Get-PmxNetworkStatusRows -Models $mixed -NoProbe)
Assert-PmxTest ((@($rows | Where-Object VmId -eq 100).Ssh) -ceq 'stopped') 'no-probe still reports a stopped VM as stopped'
Assert-PmxTest ((@($rows | Where-Object VmId -eq 102).Ssh) -ceq 'no-address') 'and no-address as no-address'
Write-PmxTestPass 'no-probe suppresses the probe, not the diagnosis'

# ── 5. stopped VMs stay in the table ─────────────────────────────────────────
$rows = @(Get-PmxNetworkStatusRows -Models $mixed)
Assert-PmxTest ($rows.Count -eq $mixed.Count) 'every VM in the inventory gets a row'
Assert-PmxTest (@($rows | Where-Object VmId -eq 100).Count -eq 1) 'a stopped VM is not silently omitted'
Write-PmxTestPass 'stopped VMs are retained, not dropped'

# ── 6. the primary address plus a count ──────────────────────────────────────
$multi = @(New-Model -VmId 107 -Name 'multi' -Addresses @('10.0.0.8', '10.0.0.9', '172.17.0.1') -Primary '10.0.0.8')
$script:ProbeResults = @{ '10.0.0.8' = 'online' }
$row = @(Get-PmxNetworkStatusRows -Models $multi)[0]
Assert-PmxTest ($row.Address -ceq '10.0.0.8') 'the primary candidate chosen by the network layer is shown'
Assert-PmxTest ($row.ExtraAddresses -eq 2) "three addresses means '+2'; got +$($row.ExtraAddresses)"
Assert-PmxTest (@($row.Addresses).Count -eq 3) 'the drill-down keeps all of them'
Write-PmxTestPass 'the fleet row shows one address and an honest count of the rest'

# A single address shows no count at all.
$one = @(New-Model -VmId 108 -Name 'single' -Addresses @('10.0.0.5') -Primary '10.0.0.5')
Assert-PmxTest ((@(Get-PmxNetworkStatusRows -Models $one)[0]).ExtraAddresses -eq 0) 'one address means no +N'
Write-PmxTestPass 'one address shows no count'

# ── 7. the SSH port ──────────────────────────────────────────────────────────
Assert-PmxTest ((Get-PmxSshPortForAddress -Address '10.0.0.5') -eq 22) 'the default port is 22'
Assert-PmxTest ((Get-PmxSshPortForAddress -Address '') -eq 22) 'an empty address still yields a sane default'

# A saved srv entry is used only on an EXACT address match. Correlating by name would let a
# reused name point the probe at the wrong port and report a healthy VM as closed.
function Get-PFServers { return @{ 'other' = @{ host = '10.0.0.99'; port = 2222 }; 'here' = @{ host = '10.0.0.5'; port = 2200 } } }
Assert-PmxTest ((Get-PmxSshPortForAddress -Address '10.0.0.5') -eq 2200) 'a saved srv target on the same address supplies its port'
Assert-PmxTest ((Get-PmxSshPortForAddress -Address '10.0.0.6') -eq 22) 'an unrelated address still gets 22'
$portSrc = [regex]::Match($text, '(?s)function Get-PmxSshPortForAddress \{.*?\n\}').Value
Assert-PmxTest ($portSrc -notmatch '\.Name\b' -and $portSrc -notmatch '\$entry\.Key') `
    'the srv correlation must be by address, never by name'
Write-PmxTestPass 'the port comes from an exact srv address match, or 22'

# ── 8. `ready` does not overclaim ────────────────────────────────────────────
$script:ProbeResults = @{ '10.0.0.5' = 'online' }
$contract = ConvertTo-PmxNetworkStatusContract -Rows @(Get-PmxNetworkStatusRows -Models $one) -Warnings @()
Assert-PmxTest ($contract.sshMeaning -match 'TCP') 'the JSON says what ready means'
Assert-PmxTest ($contract.sshMeaning -match 'does not imply authentication') `
    'and says plainly that it does not mean a login would work'
Assert-PmxTest (@($contract.vms).Count -eq 1) 'the contract carries the rows'
Assert-PmxTest ($contract.vms[0].ssh -ceq 'ready') 'with the state as computed'
Write-PmxTestPass 'the payload states that ready is a TCP fact, not an auth fact'

# ── 9. the states are exactly the seven the item named ───────────────────────
$known = @('ready', 'closed', 'unreachable', 'no-address', 'agent-unavailable', 'stopped', 'not-tested')
foreach ($state in $known) {
    Assert-PmxTest ([bool](Get-PmxSshStateColour $state)) "'$state' must have a colour"
}
$script:ProbeResults = @{ '10.0.0.5' = 'online'; '10.0.0.6' = 'no-ssh'; '10.0.0.7' = 'offline' }
$allRows = @(Get-PmxNetworkStatusRows -Models ($models + $mixed))
foreach ($row in $allRows) {
    Assert-PmxTest ($row.Ssh -in $known) "'$($row.Ssh)' is not one of the seven documented states"
}
Assert-PmxTest (@($allRows | Where-Object { $_.Ssh -ceq 'pending' }).Count -eq 0) `
    'no row may escape with the internal pending marker'
Write-PmxTestPass 'every row lands on one of the seven documented states'

Write-Host 'PF-FEAT-008: the fleet view distinguishes seven states, probes only known addresses, and never scans.'
