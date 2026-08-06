. (Join-Path $PSScriptRoot 'test-helpers.ps1')
function Register-PFCommand {}
. (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' 'shared.ps1')
. (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' 'help.ps1')
. (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' 'vm-read.ps1')
. (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' 'vm-change.ps1')
. (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' 'disk-grow.ps1')
. (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' 'network-read.ps1')

$overview = @(Get-PmxHelpOverview)
$syntax = @($overview | ForEach-Object Commands | ForEach-Object Syntax)
$requiredSyntax = @(
    'pmx config show [--json|--table]',
    'pmx config set <setting> <value>',
    'pmx config reset <setting|all>',
    'pmx config validate',
    'pmx discover [--json|--table]',
    'pmx node status [--json|--table]',
    'pmx storage list [--json|--table]',
    'pmx vm [list] [--json|--table]',
    'pmx vm show <name|vmid> [--json|--table]',
    'pmx vm status <name|vmid> [--json|--table]',
    'pmx vm next-id [--json|--table]',
    'pmx vm network <name|vmid> [--json|--table]',
    'pmx vm network adapters <name|vmid> [--json|--table]',
    'pmx vm network addresses <name|vmid> [--json|--table]',
    'pmx vm network stats <name|vmid> [--json|--table]',
    'pmx vm network list [--json|--table]',
    'pmx disk list --vm <name|vmid> [--json|--table]',
    'pmx vm clone --source <template> --new-vmid <number|auto> --name <dns-name> [--full] [--dry-run]',
    'pmx vm cpu set <name|vmid> --cores <number> [--dry-run]',
    'pmx vm memory set <name|vmid> --size <size> [--dry-run]',
    'pmx disk grow <name|vmid> <size> [--dry-run]',
    'pmx disk grow <name|vmid> <slot> <size> [--dry-run]',
    'pmx disk grow --vm <name|vmid> --disk <slot> --to <size> [--dry-run]',
    'pmx vm start <name|vmid> [--dry-run]',
    'pmx vm shutdown <name|vmid> [--dry-run]',
    'pmx snapshot list --vm <name|vmid> [--json|--table]',
    'pmx snapshot create --vm <name|vmid> --name <snapshot> [--dry-run]',
    'pmx',
    'pmx disks',
    'pmx disk',
    'pmx disk <device|serial> [smart] [-Full]',
    'pmx disk <device|serial> test short|long',
    'pmx disk <device|serial> report [-Write]',
    'pmx disk <device|serial> capacity-test [-Destroy]',
    'pmx pools',
    'pmx guests',
    'pmx guest [vmid|name]',
    'pmx updates'
)
foreach ($required in $requiredSyntax) {
    Assert-PmxTest ($syntax -ccontains $required) "PMX overview omitted routed syntax: $required"
}

$rendered = (@(& { Show-PmxHelp } 6>&1 | ForEach-Object { "$_" }) -join "`n")
foreach ($required in $requiredSyntax) {
    Assert-PmxTest $rendered.Contains($required, [StringComparison]::Ordinal) "Rendered pmx help omitted: $required"
}

$topics = Get-PmxHelpTopics
foreach ($topic in @(
    'config', 'config discover', 'discover', 'node', 'node status', 'storage', 'storage list',
    'vm', 'vm list', 'vm show', 'vm status', 'vm next-id', 'vm network', 'vm network adapters',
    'vm network addresses', 'vm network stats', 'vm network list', 'vm net', 'vm nic', 'vm ip',
    'vm net stats', 'vm net list', 'vm clone', 'vm cpu', 'vm cpu set',
    'vm memory', 'vm memory set', 'vm set-cpu', 'vm set-memory', 'vm start', 'vm shutdown', 'disk', 'disks',
    'disk list', 'disk grow', 'disk smart', 'disk test', 'disk report', 'disk evidence',
    'disk capacity-test', 'snapshot',
    'snapshot list', 'snapshot create', 'local', 'pools', 'guests', 'guest', 'updates'
)) {
    Assert-PmxTest $topics.Contains($topic) "PMX detailed help topic is missing: $topic"
}

$vmTopicSyntax = @($topics['vm'].Syntax) -join "`n"
Assert-PmxTest ($vmTopicSyntax -notmatch '(?m)^pmx vm .+--vm\b') `
    'The VM help family still advertises redundant --vm syntax.'
$overviewVmSyntax = @($syntax | Where-Object { $_ -match '^pmx vm ' }) -join "`n"
Assert-PmxTest ($overviewVmSyntax -notmatch '--vm\b') `
    'The top-level VM overview still advertises redundant --vm syntax.'

$read = Get-PmxReadInvocation -Arguments @('debian13-lab') -RequireSelector -PositionalSelectorOnly
Assert-PmxTest ($read.Success -and $read.Options.Selector -ceq 'debian13-lab') `
    'VM positional selector did not parse.'
$badRead = Get-PmxReadInvocation -Arguments @('--vm', '101') -RequireSelector -PositionalSelectorOnly
Assert-PmxTest (-not $badRead.Success) 'A pmx vm read still accepted redundant --vm.'

$networkRead = Get-PmxNetworkInvocation -Arguments @('debian13-lab', '-j') -View addresses
Assert-PmxTest ($networkRead.Success -and $networkRead.Options.Selector -ceq 'debian13-lab' -and $networkRead.Options.Json) `
    'VM network positional selector or -j convenience did not parse.'

$cpu = Get-PmxSetInvocation -Arguments @('debian13-lab', '--cores', '4') -ValueOption cores -ValueProperty Cores
Assert-PmxTest ($cpu.Success -and $cpu.Options.Vm -ceq 'debian13-lab' -and $cpu.Options.Cores -ceq '4') `
    'VM-first CPU syntax did not parse.'
$memory = Get-PmxSetInvocation -Arguments @('101', '8GiB') -ValueOption size -ValueProperty Size
Assert-PmxTest ($memory.Success -and $memory.Options.Vm -ceq '101' -and $memory.Options.Size -ceq '8GiB') `
    'Two-positional compatibility syntax did not parse.'
$badSet = Get-PmxSetInvocation -Arguments @('--vm', '101', '--cores', '4') -ValueOption cores -ValueProperty Cores
Assert-PmxTest (-not $badSet.Success) 'A pmx vm mutation still accepted redundant --vm.'

$autoGrow = Get-PmxDiskGrowInvocation -Arguments @('docker-host', '100GiB', '--dry-run')
Assert-PmxTest ($autoGrow.Success -and $autoGrow.Options.AutoSelect -and $autoGrow.Options.Vm -ceq 'docker-host') `
    'Concise automatic disk-growth syntax did not parse.'
$positionalGrow = Get-PmxDiskGrowInvocation -Arguments @('102', 'scsi1', '3TiB')
Assert-PmxTest ($positionalGrow.Success -and -not $positionalGrow.Options.AutoSelect -and $positionalGrow.Options.Disk -ceq 'scsi1') `
    'Explicit positional disk-growth syntax did not parse.'
$namedGrow = Get-PmxDiskGrowInvocation -Arguments @('--to', '100GiB', '--vm', '102', '--disk', 'scsi0')
Assert-PmxTest ($namedGrow.Success -and $namedGrow.Options.Disk -ceq 'scsi0') `
    'Explicit named disk-growth syntax did not parse.'
foreach ($badArgs in @(
    @('102', '100GiB', '--disk', 'scsi0'),
    @('--vm', '102', '--disk', 'scsi0'),
    @('102'),
    @('102', 'scsi0', '100GiB', 'extra')
)) {
    Assert-PmxTest (-not (Get-PmxDiskGrowInvocation -Arguments $badArgs).Success) `
        "Disk-growth parser accepted invalid or hybrid syntax: $($badArgs -join ' ')"
}

Write-PmxTestPass 'complete executable help and VM-first selector syntax'
