. (Join-Path $PSScriptRoot 'test-helpers.ps1')
. (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' 'shared.ps1')

$switches = Get-PmxGlobalSwitchMap
$parsed = ConvertFrom-PmxArguments -Arguments @('--json', '--vm=101') `
    -ValueOptions @{ vm = 'Vm' } -SwitchOptions $switches
Assert-PmxTest $parsed.Success 'Reordered and equals-form options should parse.'
Assert-PmxTest ($parsed.Options.Json -and $parsed.Options.Vm -ceq '101') 'Parsed option values are incorrect.'

foreach ($case in @(
    @{ Args = @('--vm'); Text = 'missing value' },
    @{ Args = @('--vm', '101', '--vm', '102'); Text = 'duplicate option' },
    @{ Args = @('--v', '101'); Text = 'abbreviated option' },
    @{ Args = @('--VM', '101'); Text = 'case-changed option' },
    @{ Args = @('--vm', '-x'); Text = 'short-option-shaped separated value' },
    @{ Args = @('--vm=-x'); Text = 'short-option-shaped inline value' },
    @{ Args = @("--vm=10`n1"); Text = 'control character' }
)) {
    $bad = ConvertFrom-PmxArguments -Arguments $case.Args -ValueOptions @{ vm = 'Vm' } -SwitchOptions $switches
    Assert-PmxTest (-not $bad.Success) "PMX parser accepted $($case.Text)."
}

$literal = ConvertFrom-PmxArguments -Arguments @('--', '-literal') -MaxPositionals 1
Assert-PmxTest ($literal.Success -and $literal.Positionals[0] -ceq '-literal') `
    'The explicit end-of-options marker should permit a literal positional value.'

$memory = ConvertFrom-PmxSize -Value '2GiB' -Kind memory
Assert-PmxTest ($memory.Success -and $memory.MiB -eq 2048 -and $memory.Canonical -ceq '2 GiB') `
    'Memory size conversion returned the wrong canonical value.'
Assert-PmxTest (-not (ConvertFrom-PmxSize -Value '0GiB').Success) 'Zero disk growth size must be rejected.'
Assert-PmxTest (-not (Test-PmxVmId '0101')) 'VMIDs with leading zeros must be rejected like the adapter rejects them.'
Assert-PmxTest (Test-PmxVmId '101') 'A valid VMID was rejected.'

$hostileText = "safe$([char]27)[31mred$([char]27)[0m$([char]7)"
Assert-PmxTest ((ConvertTo-PmxDisplayText $hostileText) -ceq 'safered') `
    'Terminal-control sanitization did not remove CSI/control bytes.'
Write-PmxTestPass 'strict parser, identifiers, sizes, and display sanitization'

function Register-PFCommand {}
$script:routed = ''
$script:routedArguments = @()
function Show-PmxHelp { param([object[]]$TopicParts); $script:routed = 'help'; $script:routedArguments = @($TopicParts) }
function Invoke-PmxVmCpuSet { param([object[]]$Arguments); $script:routed = 'vm-cpu-set'; $script:routedArguments = @($Arguments) }
function Invoke-PmxVmMemorySet { param([object[]]$Arguments); $script:routed = 'vm-memory-set'; $script:routedArguments = @($Arguments) }
function Invoke-PmxVmStart { param([object[]]$Arguments); $script:routed = 'vm-start'; $script:routedArguments = @($Arguments) }
function Show-PmxManagedVm { param([object[]]$Arguments, [switch]$StatusOnly); $script:routed = $(if ($StatusOnly) { 'vm-status' } else { 'vm-show' }); $script:routedArguments = @($Arguments) }
function Invoke-PmxVmDiskGrow { param([object[]]$Arguments); $script:routed = 'vm-disk-grow'; $script:routedArguments = @($Arguments) }
function Invoke-PmxSnapshotCreate { param([object[]]$Arguments); $script:routed = 'snapshot-create'; $script:routedArguments = @($Arguments) }
. (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' 'command.ps1')

$one = Get-PmxCommandTail -Arguments @('cpu', 'set') -Start 1
Assert-PmxTest ($one -is [array] -and $one.Count -eq 1 -and $one[0] -ceq 'set') `
    'A one-token router tail was enumerated into a scalar.'

pmx vm cpu set
Assert-PmxTest ($script:routed -ceq 'vm-cpu-set') 'Nested vm cpu set route did not reach its handler.'
pmx vm set-memory 101 --size 2GiB
Assert-PmxTest ($script:routed -ceq 'vm-memory-set') 'Compatibility set-memory route did not reach its handler.'
Assert-PmxEqual @('101', '--size', '2GiB') $script:routedArguments `
    'Router changed VM memory handler arguments.'
pmx vm start debian13-lab
Assert-PmxTest ($script:routed -ceq 'vm-start') 'VM-first lifecycle route did not reach its handler.'
Assert-PmxEqual @('debian13-lab') $script:routedArguments 'Router changed the positional lifecycle selector.'
pmx vm status 101
Assert-PmxTest ($script:routed -ceq 'vm-status') 'VM-first status route did not reach its handler.'
Assert-PmxEqual @('101') $script:routedArguments 'Router changed the positional status selector.'
pmx disk grow --vm 101 --disk scsi0 --to 80GiB
Assert-PmxTest ($script:routed -ceq 'vm-disk-grow') 'Virtual disk grow collided with the physical disk route.'
pmx snapshot create
Assert-PmxTest ($script:routed -ceq 'snapshot-create') 'Snapshot create route did not reach its handler.'
pmx help vm clone
Assert-PmxTest ($script:routed -ceq 'help') 'Help route did not work without a Proxmox connection.'
Assert-PmxEqual @('vm', 'clone') $script:routedArguments 'Help topic tokens changed during routing.'
Write-PmxTestPass 'thin, collision-aware command routing'
