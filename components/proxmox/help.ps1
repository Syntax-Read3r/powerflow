# ==============================================================================
# PowerFlow — Proxmox Help
# ==============================================================================
# Domain   : Proxmox
# File     : components/proxmox/help.ps1
# Purpose  : Table-driven overview and educational topic help for pmx
# Functions: Get-PmxHelpTopics, Get-PmxHelpOverview, Show-PmxHelp,
#            Show-PmxTopicHelp
# Depends  : ConvertTo-PmxDisplayText (components/proxmox/shared.ps1)
# ==============================================================================

function Get-PmxHelpTopics {
    $topics = [ordered]@{}
    $topics['config'] = [pscustomobject]@{
        Purpose = 'Configure PMX transport and educational defaults without storing credentials.'
        Syntax = @('pmx config show', 'pmx config set <setting> <value>', 'pmx config reset <setting|all>', 'pmx config validate', 'pmx config discover')
        Example = @('pmx config set host proxmox', 'pmx config set transport ssh', 'pmx config validate')
        Native = @('No native command for show/set/reset; validate/discover use allow-listed pvesh queries.')
        Safety = 'Green. Configuration stores an srv alias and policy values only.'
        Story = 'Save the remote-control settings, not the SSH key or password.'
    }
    $topics['config show'] = $topics['config']
    $topics['config set'] = $topics['config']
    $topics['config reset'] = $topics['config']
    $topics['config validate'] = $topics['config']
    $topics['discover'] = [pscustomobject]@{
        Purpose = 'Discover real nodes, VM storage, bridges, VMIDs, templates, and the next free ID.'
        Syntax = @('pmx discover [--json|--table]', 'pmx config discover [--json|--table]')
        Example = @('pmx discover', 'pmx discover --json')
        Native = @('pvesh get /version', 'pvesh get /nodes', 'pvesh get /nodes/<node>/storage', 'pvesh get /nodes/<node>/network --type any_bridge', 'pvesh get /cluster/resources --type vm', 'pvesh get /cluster/nextid')
        Safety = 'Green. Structured read-only queries.'
        Story = 'Ask the hotel what rooms and facilities actually exist before making a plan.'
    }
    $topics['config discover'] = $topics['discover']
    $topics['node status'] = [pscustomobject]@{
        Purpose = 'Show the selected Proxmox node status.'
        Syntax = @('pmx node status [--json|--table]')
        Example = @('pmx node status')
        Native = @('pvesh get /nodes/<node>/status')
        Safety = 'Green. Read only.'
        Story = 'Read the host dashboard without opening the web interface.'
    }
    $topics['storage list'] = [pscustomobject]@{
        Purpose = 'List active VM-image storage and available capacity.'
        Syntax = @('pmx storage list [--json|--table]')
        Example = @('pmx storage list')
        Native = @('pvesh get /nodes/<node>/storage --content images --enabled 1')
        Safety = 'Green. Read only.'
        Story = 'See which storerooms can hold a VM before copying one.'
    }
    $topics['vm list'] = [pscustomobject]@{
        Purpose = 'List QEMU virtual machines and templates.'
        Syntax = @('pmx vm list [--json|--table]')
        Example = @('pmx vm list')
        Native = @('pvesh get /cluster/resources --type vm')
        Safety = 'Green. Read only; LXC rows are excluded from this view.'
        Story = 'VMID is the room number; name is the sign on the door.'
    }
    $topics['vm show'] = [pscustomobject]@{
        Purpose = 'Show configuration and current status for one VM.'
        Syntax = @('pmx vm show <vmid|name> [--json|--table]')
        Example = @('pmx vm show 101', 'pmx vm show docker-host')
        Native = @('pvesh get /nodes/<node>/qemu/<vmid>/config --current 1', 'pvesh get /nodes/<node>/qemu/<vmid>/status/current')
        Safety = 'Green. Read only.'
        Story = 'Resolve the friendly sign to its authoritative room number, then inspect it.'
    }
    $topics['vm status'] = [pscustomobject]@{
        Purpose = 'Show current power and runtime status for one VM.'
        Syntax = @('pmx vm status <vmid|name> [--json|--table]')
        Example = @('pmx vm status debian13-lab', 'pmx vm status 101')
        Native = @('pvesh get /nodes/<node>/qemu/<vmid>/status/current')
        Safety = 'Green. Read only.'
        Story = 'Check whether the room is occupied and running.'
    }
    $topics['vm next-id'] = [pscustomobject]@{
        Purpose = 'Ask Proxmox for the next available VMID.'
        Syntax = @('pmx vm next-id [--json|--table]')
        Example = @('pmx vm next-id')
        Native = @('pvesh get /cluster/nextid')
        Safety = 'Green. The returned ID is not reserved until clone succeeds.'
        Story = 'Ask reception for an available room number instead of guessing.'
    }
    $topics['vm clone'] = [pscustomobject]@{
        Purpose = 'Create an independent VM from an existing template.'
        Syntax = @(
            'pmx vm clone --source <vmid|name> --new-vmid <number|auto> --name <dns-name> [--full] [--dry-run]',
            'pmx vm clone <source> <new-vmid|auto> <dns-name> [--full] [--dry-run]',
            'Compatibility: --source-vmid is accepted as an alias of --source.'
        )
        Example = @('pmx vm clone --source debian-base --new-vmid auto --name docker-host --full --dry-run')
        Native = @('qm clone <source-vmid> <new-vmid> --name <name> --full 1')
        Safety = 'Amber. Validates template/state/storage, previews, confirms, revalidates, executes, and verifies.'
        Story = 'Copy one hotel room into a new, independently owned room number.'
    }
    $topics['vm cpu set'] = [pscustomobject]@{
        Purpose = 'Set cores per socket for one VM.'
        Syntax = @(
            'pmx vm cpu set <vmid|name> --cores <number> [--dry-run]',
            'pmx vm cpu set <vmid|name> <number> [--dry-run]',
            'Compatibility: pmx vm set-cpu accepts the same arguments.'
        )
        Example = @('pmx vm cpu set 102 --cores 4 --dry-run')
        Native = @('qm set <vmid> --cores <number> --digest <sha1>')
        Safety = 'Amber. Shows sockets × cores, confirms, revalidates the digest, and verifies desired config.'
        Story = 'Cores are workers on each CPU socket; total vCPUs are sockets multiplied by cores.'
    }
    $topics['vm memory set'] = [pscustomobject]@{
        Purpose = 'Set VM memory with a friendly binary unit.'
        Syntax = @(
            'pmx vm memory set <vmid|name> --size <MiB|GiB|TiB> [--dry-run]',
            'pmx vm memory set <vmid|name> <size> [--dry-run]',
            'Compatibility: pmx vm set-memory accepts the same arguments.'
        )
        Example = @('pmx vm memory set 102 --size 8GiB --dry-run')
        Native = @('qm set <vmid> --memory <MiB> --digest <sha1>')
        Safety = 'Amber. Displays the friendly and native units, confirms, revalidates, and verifies.'
        Story = 'PowerFlow translates 8 GiB into the 8192 MiB value Proxmox expects.'
    }
    $topics['vm set-cpu'] = $topics['vm cpu set']
    $topics['vm set-memory'] = $topics['vm memory set']
    $topics['vm cpu'] = $topics['vm cpu set']
    $topics['vm memory'] = $topics['vm memory set']
    $topics['disk list'] = [pscustomobject]@{
        Purpose = 'List virtual disks attached to a VM.'
        Syntax = @('pmx disk list --vm <vmid|name> [--json|--table]', 'pmx disk list <vmid|name> [--json|--table]')
        Example = @('pmx disk list --vm 102')
        Native = @('pvesh get /nodes/<node>/qemu/<vmid>/config --current 1')
        Safety = 'Green. Read only. This is separate from pmx disk <physical-selector>.'
        Story = "These are a guest room's virtual disks, not physical drives in the host."
    }
    $topics['disk grow'] = [pscustomobject]@{
        Purpose = 'Grow a VM disk to a requested final size.'
        Syntax = @('pmx disk grow --vm <vmid|name> --disk <slot> --to <size> [--dry-run]')
        Example = @('pmx disk grow --vm 102 --disk scsi0 --to 100GiB --dry-run')
        Native = @('qm disk resize <vmid> <slot> +<calculated-delta> --digest <sha1>')
        Safety = 'Amber. Never shrinks. Growing the guest partition/filesystem remains a separate in-guest step.'
        Story = 'State the destination size; PowerFlow calculates the safe positive growth.'
    }
    $topics['vm start'] = [pscustomobject]@{
        Purpose = 'Start a stopped VM.'
        Syntax = @('pmx vm start <vmid|name> [--dry-run]')
        Example = @('pmx vm start debian13-lab', 'pmx vm start 101 --dry-run')
        Native = @('qm start <vmid>')
        Safety = 'Amber. Running is a no-op; state is revalidated and verified.'
        Story = 'Wake the room only after confirming the authoritative VMID.'
    }
    $topics['vm shutdown'] = [pscustomobject]@{
        Purpose = 'Request a graceful ACPI shutdown.'
        Syntax = @('pmx vm shutdown <vmid|name> [--dry-run]')
        Example = @('pmx vm shutdown debian13-lab', 'pmx vm shutdown 101 --dry-run')
        Native = @('qm shutdown <vmid>')
        Safety = 'Amber. Never adds forceStop; stopped is a no-op.'
        Story = 'Ask the guest to close cleanly instead of pulling its power cable.'
    }
    $topics['snapshot list'] = [pscustomobject]@{
        Purpose = 'List real snapshots for one VM.'
        Syntax = @('pmx snapshot list --vm <vmid|name> [--json|--table]', 'pmx snapshot list <vmid|name> [--json|--table]')
        Example = @('pmx snapshot list --vm 102')
        Native = @('pvesh get /nodes/<node>/qemu/<vmid>/snapshot')
        Safety = 'Green. The synthetic current row is omitted.'
        Story = 'See the saved restore points without confusing current state for a snapshot.'
    }
    $topics['snapshot create'] = [pscustomobject]@{
        Purpose = 'Create a named snapshot for one VM.'
        Syntax = @('pmx snapshot create --vm <vmid|name> --name <snapshot> [--dry-run]', 'pmx snapshot create <vmid|name> <snapshot> [--dry-run]')
        Example = @('pmx snapshot create --vm 102 --name pre-docker --dry-run')
        Native = @('qm snapshot <vmid> <snapshot>')
        Safety = 'Amber. Refuses reserved/duplicate names, confirms, revalidates, and verifies.'
        Story = 'Take a labelled photograph of the VM before a meaningful change.'
    }
    $topics['vm'] = [pscustomobject]@{
        Purpose = 'Inspect and safely manage QEMU virtual machines and templates.'
        Syntax = @(
            'pmx vm [list] [--json|--table]',
            'pmx vm show|status <vmid|name> [--json|--table]',
            'pmx vm next-id [--json|--table]',
            'pmx vm clone --source <template> --new-vmid <number|auto> --name <dns-name> [--dry-run]',
            'pmx vm cpu set <vm> --cores <number> [--dry-run]',
            'pmx vm memory set <vm> --size <size> [--dry-run]',
            'pmx vm start|shutdown <vm> [--dry-run]'
        )
        Example = @('pmx vm list', 'pmx vm start debian13-lab', 'pmx help vm clone')
        Native = @('Read operations use allow-listed pvesh queries; changes use fixed qm operations.')
        Safety = 'Reads are green. Clone, sizing, and lifecycle changes are amber and revalidated.'
        Story = 'Use a name or authoritative VMID; PowerFlow resolves identity before acting.'
    }
    $topics['snapshot'] = [pscustomobject]@{
        Purpose = 'List or create named VM snapshots.'
        Syntax = @('pmx snapshot list --vm <vmid|name> [--json|--table]', 'pmx snapshot create --vm <vmid|name> --name <snapshot> [--dry-run]')
        Example = @('pmx snapshot list --vm 101', 'pmx snapshot create --vm 101 --name before_upgrade --dry-run')
        Native = @('pvesh get /nodes/<node>/qemu/<vmid>/snapshot', 'qm snapshot <vmid> <snapshot>')
        Safety = 'Listing is green. Creation is amber, confirmed, revalidated, and verified.'
        Story = 'Inspect restore points or take a labelled one before a meaningful change.'
    }
    $topics['disk'] = [pscustomobject]@{
        Purpose = 'Inspect physical host disks or list/grow a VM virtual disk.'
        Syntax = @(
            'pmx disk                              physical-disk picker',
            'pmx disk <device|serial> [smart]      physical disk and SMART summary',
            'pmx disk <device> test short|long     SMART self-test',
            'pmx disk <device> report [-Write]     evidence report/bundle',
            'pmx disk <device> capacity-test [-Destroy]',
            'pmx disk list --vm <vmid|name> [--json|--table]',
            'pmx disk grow --vm <vm> --disk <slot> --to <size> [--dry-run]'
        )
        Example = @('pmx disk sda', 'pmx disk list --vm 101', 'pmx help disk grow')
        Native = @('Physical operations use lsblk/smartctl/f3probe locally; virtual operations use pvesh/qm.')
        Safety = 'Physical reads are green; F3 is destructive and separately gated. Virtual growth is amber and never shrinks.'
        Story = 'Physical host drives and guest virtual disks share a noun but never an execution path.'
    }
    $topics['disk test'] = [pscustomobject]@{
        Purpose = 'Launch a short or long SMART self-test on one physical disk.'
        Syntax = @('pmx disk <device|serial> test short|long', 'Compatibility: extended is accepted as an alias of long.')
        Example = @('pmx disk sda test short')
        Native = @('smartctl -t short|long <stable-device>')
        Safety = 'Amber read/diagnostic operation; does not overwrite disk data.'
        Story = 'Ask the drive firmware to test itself, then inspect its SMART result later.'
    }
    $topics['disk report'] = [pscustomobject]@{
        Purpose = 'Display disk authenticity/health evidence or write a portable bundle.'
        Syntax = @('pmx disk <device|serial> report [-Write]', 'Compatibility: evidence is accepted as an alias of report.')
        Example = @('pmx disk sda report', 'pmx disk sda report -Write')
        Native = @('smartctl plus filtered kernel/storage evidence collected by the Linux adapter.')
        Safety = 'Green. -Write creates an evidence folder; it does not write to the selected disk.'
        Story = 'Collect the facts needed to diagnose a drive or support an RMA claim.'
    }
    $topics['disk evidence'] = $topics['disk report']
    $topics['disk smart'] = $topics['disk']
    $topics['disks'] = $topics['disk']
    $topics['disk capacity-test'] = [pscustomobject]@{
        Purpose = 'Explain or, with explicit destruction gates, run an F3 raw-capacity test.'
        Syntax = @('pmx disk <device|serial> capacity-test', 'pmx disk <device|serial> capacity-test -Destroy')
        Example = @('pmx disk sdz capacity-test')
        Native = @('f3probe --destructive --time-ops <stable-device>')
        Safety = 'Red. -Destroy still requires an empty/idle stable device and an exact typed confirmation.'
        Story = 'Prove whether new media has its advertised capacity only when all existing data is disposable.'
    }
    $topics['local'] = [pscustomobject]@{
        Purpose = 'Inspect the local Proxmox node, guests, storage pools, updates, and physical disks.'
        Syntax = @('pmx', 'pmx disks', 'pmx pools', 'pmx guests', 'pmx guest [vmid|name]', 'pmx updates')
        Example = @('pmx', 'pmx guest 101', 'pmx disks')
        Native = @('Local allow-listed pvesh, lsblk, smartctl, zpool, and package queries.')
        Safety = 'Green unless an explicitly destructive physical-disk action is selected.'
        Story = 'Use the concise host dashboard, then open only the view you need.'
    }
    $topics['pools'] = $topics['local']
    $topics['guests'] = $topics['local']
    $topics['guest'] = $topics['local']
    $topics['updates'] = $topics['local']
    $topics['node'] = $topics['node status']
    $topics['storage'] = [pscustomobject]@{
        Purpose = 'List configured VM-image storage, or show local host pools through the legacy no-argument alias.'
        Syntax = @('pmx storage list [--json|--table]', 'pmx storage   (local Proxmox: same pool view as pmx pools)')
        Example = @('pmx storage list', 'pmx pools')
        Native = @('pvesh get /nodes/<node>/storage --content images --enabled 1', 'Local alias uses the existing storage/pool host view.')
        Safety = 'Green. Read only.'
        Story = 'Use storage list for VM-image capacity; use pools for the concise local host view.'
    }
    return $topics
}

function Get-PmxHelpOverview {
    return @(
        [pscustomobject]@{ Title = 'CONFIGURATION & DISCOVERY'; Commands = @(
            [pscustomobject]@{ Syntax = 'pmx config show [--json|--table]'; Description = 'show target and policy settings' },
            [pscustomobject]@{ Syntax = 'pmx config set <setting> <value>'; Description = 'change host, transport, node, output, confirmation, audit, or clone mode' },
            [pscustomobject]@{ Syntax = 'pmx config reset <setting|all>'; Description = 'restore one or all defaults' },
            [pscustomobject]@{ Syntax = 'pmx config validate'; Description = 'verify transport and selected node' },
            [pscustomobject]@{ Syntax = 'pmx discover [--json|--table]'; Description = 'nodes, storage, bridges, VMIDs, templates; alias: pmx config discover' },
            [pscustomobject]@{ Syntax = 'pmx node status [--json|--table]'; Description = 'selected node status; pmx node is equivalent' },
            [pscustomobject]@{ Syntax = 'pmx storage list [--json|--table]'; Description = 'active VM-image storage and capacity' }
        ) },
        [pscustomobject]@{ Title = 'VM READS'; Commands = @(
            [pscustomobject]@{ Syntax = 'pmx vm [list] [--json|--table]'; Description = 'VM/template inventory; bare pmx vm lists' },
            [pscustomobject]@{ Syntax = 'pmx vm show <name|vmid> [--json|--table]'; Description = 'configuration, disks, and current status' },
            [pscustomobject]@{ Syntax = 'pmx vm status <name|vmid> [--json|--table]'; Description = 'power and runtime status' },
            [pscustomobject]@{ Syntax = 'pmx vm next-id [--json|--table]'; Description = 'next authoritative available VMID' },
            [pscustomobject]@{ Syntax = 'pmx disk list --vm <name|vmid> [--json|--table]'; Description = 'virtual disks attached to one VM' }
        ) },
        [pscustomobject]@{ Title = 'GUARDED VM CHANGES'; Commands = @(
            [pscustomobject]@{ Syntax = 'pmx vm clone --source <template> --new-vmid <number|auto> --name <dns-name> [--full] [--dry-run]'; Description = 'independent full clone' },
            [pscustomobject]@{ Syntax = 'pmx vm cpu set <name|vmid> --cores <number> [--dry-run]'; Description = 'cores per socket; alias: pmx vm set-cpu' },
            [pscustomobject]@{ Syntax = 'pmx vm memory set <name|vmid> --size <size> [--dry-run]'; Description = 'memory in MiB/GiB/TiB; alias: pmx vm set-memory' },
            [pscustomobject]@{ Syntax = 'pmx disk grow --vm <name|vmid> --disk <slot> --to <size> [--dry-run]'; Description = 'grow virtual disk to a final size; never shrink' },
            [pscustomobject]@{ Syntax = 'pmx vm start <name|vmid> [--dry-run]'; Description = 'start a stopped VM' },
            [pscustomobject]@{ Syntax = 'pmx vm shutdown <name|vmid> [--dry-run]'; Description = 'request graceful ACPI shutdown' },
            [pscustomobject]@{ Syntax = 'pmx snapshot list --vm <name|vmid> [--json|--table]'; Description = 'list real snapshots' },
            [pscustomobject]@{ Syntax = 'pmx snapshot create --vm <name|vmid> --name <snapshot> [--dry-run]'; Description = 'create a guarded named snapshot' }
        ) },
        [pscustomobject]@{ Title = 'LOCAL HOST & PHYSICAL DISKS'; Commands = @(
            [pscustomobject]@{ Syntax = 'pmx'; Description = 'local node dashboard' },
            [pscustomobject]@{ Syntax = 'pmx disks'; Description = 'physical disk inventory' },
            [pscustomobject]@{ Syntax = 'pmx disk'; Description = 'physical-disk picker' },
            [pscustomobject]@{ Syntax = 'pmx disk <device|serial> [smart] [-Full]'; Description = 'SMART summary or full report' },
            [pscustomobject]@{ Syntax = 'pmx disk <device|serial> test short|long'; Description = 'launch a SMART self-test' },
            [pscustomobject]@{ Syntax = 'pmx disk <device|serial> report [-Write]'; Description = 'show or write an evidence bundle; alias: evidence' },
            [pscustomobject]@{ Syntax = 'pmx disk <device|serial> capacity-test [-Destroy]'; Description = 'explain or enter the destructive F3 gate' },
            [pscustomobject]@{ Syntax = 'pmx pools'; Description = 'local storage/ZFS pools; pmx storage is a local alias' },
            [pscustomobject]@{ Syntax = 'pmx guests'; Description = 'local guest inventory' },
            [pscustomobject]@{ Syntax = 'pmx guest [vmid|name]'; Description = 'open one local guest or list all' },
            [pscustomobject]@{ Syntax = 'pmx updates'; Description = 'available Proxmox updates' }
        ) }
    )
}

function Show-PmxTopicHelp {
    param([Parameter(Mandatory)][string]$Topic)
    Show-PmxHelp -TopicParts @($Topic -split '\s+')
}

function Show-PmxHelp {
    param([string[]]$TopicParts = @())

    $topic = (@($TopicParts | Where-Object { $_ } | ForEach-Object { "$_".ToLowerInvariant() }) -join ' ').Trim()
    $topics = Get-PmxHelpTopics
    if ($topic) {
        if (-not $topics.Contains($topic)) {
            Write-Host "❌ Unknown pmx help topic '$topic'." -ForegroundColor Red
            Write-Host '   Run: pmx help' -ForegroundColor DarkGray
            return
        }
        $entry = $topics[$topic]
        Write-Host ''
        Write-Host "⚡ PMX HELP — $($topic.ToUpperInvariant())" -ForegroundColor Cyan
        foreach ($section in @('Purpose', 'Story', 'Syntax', 'Example', 'Native', 'Safety')) {
            Write-Host ''
            Write-Host $section.ToUpperInvariant() -ForegroundColor Yellow
            foreach ($line in @($entry.$section)) { Write-Host "  $((ConvertTo-PmxDisplayText $line))" -ForegroundColor White }
        }
        Write-Host ''
        return
    }

    Write-Host ''
    Write-Host '⚡ pmx — PowerFlow for Proxmox VE' -ForegroundColor Cyan
    Write-Host ''
    foreach ($section in @(Get-PmxHelpOverview)) {
        Write-Host "  $($section.Title)" -ForegroundColor Yellow
        foreach ($command in @($section.Commands)) {
            Write-Host "  $($command.Syntax)" -ForegroundColor White
            Write-Host "      $($command.Description)" -ForegroundColor DarkGray
        }
        Write-Host ''
    }
    Write-Host ''
    Write-Host '  Detailed help: pmx help vm · pmx help vm start · pmx help disk · pmx help snapshot' -ForegroundColor DarkGray
    Write-Host '  Educational options: --explain · --dry-run · --show-native · --json · --table' -ForegroundColor DarkGray
    Write-Host ''
}
