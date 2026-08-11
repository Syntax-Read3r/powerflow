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
    # pmx vm config is an alias for pmx vm show, added because qm config <vmid> is the native
    # habit. It gets its own help topic so someone reaching for the native spelling finds it in
    # the catalogue rather than concluding PowerFlow lacks it.
    $topics['vm config'] = [pscustomobject]@{
        Purpose = 'Show configuration and current status for one VM. Alias for pmx vm show.'
        Syntax = @('pmx vm config <vmid|name> [--json|--table]')
        Example = @('pmx vm config 103', 'pmx vm config docker-host')
        Native = @('qm config <vmid>', 'pvesh get /nodes/<node>/qemu/<vmid>/config --current 1')
        Safety = 'Green. Read only.'
        Story = 'The native spelling of a view PowerFlow already had.'
    }
    # `pmx vm disks` is a convenience route to the same function `pmx disk list --vm` uses.
    # It gets a topic because a route nobody can find is not a route.
    $topics['vm disks'] = [pscustomobject]@{
        Purpose = 'List one VM virtual disks. Convenience route for pmx disk list --vm.'
        Syntax = @('pmx vm disks [vmid|name]')
        Example = @('pmx vm disks 102', 'pmx vm disks')
        Native = @('qm config <vmid>')
        Safety = 'Green. Read only. A bare call opens the VM picker.'
        Story = 'Show VMs, choose one, show its disks - the third step of that walk.'
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
    $topics['vm network'] = [pscustomobject]@{
        Purpose = 'Show configured adapters, VM-reported addresses, agent status, and a primary address candidate.'
        Syntax = @(
            'pmx vm network <vmid|name> [--table|-t|--json|-j] [--ipv4|-4|--ipv6|-6] [--all|--include-loopback]',
            'Short alias: pmx vm net <vmid|name>'
        )
        Example = @('pmx vm network docker-host', 'pmx vm net 102 -4')
        Native = @('PowerFlow translates this into separate configured and VM-reported reads. Add --show-native to reveal those translations.')
        Safety = 'Green. Read only; unavailable VM-agent data never triggers a fallback scan or configuration change.'
        Story = 'See the virtual cable and the addresses inside the VM without pretending they are the same source.'
    }
    $topics['vm network adapters'] = [pscustomobject]@{
        Purpose = 'Show virtual network hardware configured for one VM.'
        Syntax = @('pmx vm network adapters <vmid|name> [--table|-t|--json|-j]', 'Short alias: pmx vm nic <vmid|name>')
        Example = @('pmx vm network adapters 102', 'pmx vm nic docker-host -j')
        Native = @('Add --show-native to reveal the translated Proxmox configuration read.')
        Safety = 'Green. Read only and available for stopped VMs and templates.'
        Story = 'Inspect the virtual network cards, bridges, MAC addresses, firewall flags, and VLANs Proxmox has configured.'
    }
    $topics['vm network addresses'] = [pscustomobject]@{
        Purpose = 'Show addresses currently reported from inside one running VM.'
        Syntax = @(
            'pmx vm network addresses <vmid|name> [--table|-t|--json|-j] [--ipv4|-4|--ipv6|-6] [--all|--include-loopback]',
            'Short alias: pmx vm ip <vmid|name>'
        )
        Example = @('pmx vm network addresses 102', 'pmx vm ip docker-host -4')
        Native = @('Add --show-native to reveal the translated VM-agent read.')
        Safety = 'Green. Read only; reports agent availability and never infers addresses from ARP, DNS, DHCP, or scans.'
        Story = 'Ask the running VM which addresses it owns, then clearly label the best primary candidate as inferred.'
    }
    $topics['vm network stats'] = [pscustomobject]@{
        Purpose = 'Show receive/transmit counters reported for a running VM network interface.'
        Syntax = @('pmx vm network stats <vmid|name> [--table|-t|--json|-j]', 'Short alias: pmx vm net stats <vmid|name>')
        Example = @('pmx vm network stats 102', 'pmx vm net stats docker-host -j')
        Native = @('Add --show-native to reveal the translated VM-agent read.')
        Safety = 'Green. Read only; missing counters remain unavailable rather than becoming zero.'
        Story = 'Read exact packet/error/drop counters and IEC byte totals without changing the VM.'
    }
    $topics['vm network list'] = [pscustomobject]@{
        Purpose = 'Summarize configured adapters, primary IPv4 addresses, and agent state across QEMU VMs.'
        Syntax = @('pmx vm network list [--table|-t|--json|-j] [--ipv4|-4|--ipv6|-6] [--all|--include-loopback]', 'Short alias: pmx vm net list')
        Example = @('pmx vm network list', 'pmx vm net list -j')
        Native = @('Add --show-native in JSON mode to reveal each allow-listed translated read.')
        Safety = 'Green. Read only; one unavailable VM agent does not abort the inventory.'
        Story = 'Scan the VM network estate while preserving a visible status for every unavailable source.'
    }
    $topics['vm net'] = $topics['vm network']
    $topics['vm nic'] = $topics['vm network adapters']
    $topics['vm ip'] = $topics['vm network addresses']
    $topics['vm net stats'] = $topics['vm network stats']
    $topics['vm net list'] = $topics['vm network list']
    $topics['vm clone'] = [pscustomobject]@{
        Purpose = 'Create an independent VM from an existing template.'
        Syntax = @(
            'pmx vm clone <template> <dns-name> [--dry-run]',
            'pmx vm clone <template> <new-vmid> <dns-name> [--dry-run]',
            'pmx vm clone --source <template> --name <dns-name> [--dry-run]'
            'Compatibility: --source-vmid is accepted as an alias of --source.'
        )
        Example = @('pmx vm clone debian-base docker-host', 'pmx vm clone debian-base docker-host --dry-run')
        Native = @('qm clone <source-vmid> <new-vmid> --name <name> --full 1')
        Safety = 'Amber. Shows every source-to-target storage mapping and provisioned capacity, then validates, confirms, revalidates, executes, and verifies.'
        Story = 'Copy one hotel room into a new, independently owned room number while showing which storage pool receives each disk.'
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
        Syntax = @(
            'pmx disk grow <vmid|name> <size> [--dry-run]',
            'pmx disk grow <vmid|name> <slot> <size> [--dry-run]',
            'pmx disk grow --vm <vmid|name> --disk <slot> --to <size> [--dry-run]'
        )
        Example = @('pmx disk grow 102 100GiB --dry-run', 'pmx disk grow docker-host scsi1 3TiB --dry-run')
        Native = @('qm disk resize <vmid> <slot> +<calculated-delta> --digest <sha1>')
        Safety = 'Amber. Automatic selection is allowed only when exactly one eligible disk exists; multiple disks require an explicit slot. Never shrinks. Growing the guest partition/filesystem remains a separate in-guest step.'
        Story = 'State the final IEC size. PowerFlow reads exact configured bytes, shows current storage availability, calculates the native positive delta, and refuses to guess between disks.'
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
            'pmx vm network <vm> [--json|--table]                       combined adapter/address view',
            'pmx vm network adapters|addresses|stats <vm> [--json|--table]',
            'pmx vm network list [--json|--table]',
            'Short aliases: pmx vm net <vm> · pmx vm nic <vm> · pmx vm ip <vm>',
            'pmx vm clone <template> <dns-name> [--dry-run]',
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
            'pmx disk grow <vm> <size> [--dry-run]',
            'pmx disk grow <vm> <slot> <size> [--dry-run]',
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
            [pscustomobject]@{ Syntax = 'pmx config set <setting> <value>'; Description = 'change host, transport, node, output, confirmation, or audit' },
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
            [pscustomobject]@{ Syntax = 'pmx vm network <name|vmid> [--json|--table]'; Description = 'combined adapters, VM addresses, agent state, and primary candidate; alias: pmx vm net' },
            [pscustomobject]@{ Syntax = 'pmx vm network adapters <name|vmid> [--json|--table]'; Description = 'configured virtual adapters; alias: pmx vm nic' },
            [pscustomobject]@{ Syntax = 'pmx vm network addresses <name|vmid> [--json|--table]'; Description = 'VM-reported addresses; alias: pmx vm ip' },
            [pscustomobject]@{ Syntax = 'pmx vm network stats <name|vmid> [--json|--table]'; Description = 'VM-reported traffic counters; alias: pmx vm net stats' },
            [pscustomobject]@{ Syntax = 'pmx vm network list [--json|--table]'; Description = 'network summary across QEMU VMs; alias: pmx vm net list' },
            [pscustomobject]@{ Syntax = 'pmx disk list --vm <name|vmid> [--json|--table]'; Description = 'virtual disks attached to one VM' }
        ) },
        [pscustomobject]@{ Title = 'GUARDED VM CHANGES'; Commands = @(
            [pscustomobject]@{ Syntax = 'pmx vm clone <template> <name> [--dry-run]'; Description = 'full clone; the VMID is chosen automatically' },
            [pscustomobject]@{ Syntax = 'pmx vm cpu set <name|vmid> --cores <number> [--dry-run]'; Description = 'cores per socket; alias: pmx vm set-cpu' },
            [pscustomobject]@{ Syntax = 'pmx vm memory set <name|vmid> --size <size> [--dry-run]'; Description = 'memory in MiB/GiB/TiB; alias: pmx vm set-memory' },
            [pscustomobject]@{ Syntax = 'pmx disk grow <name|vmid> <size> [--dry-run]'; Description = 'grow the only eligible virtual disk to a final IEC size' },
            [pscustomobject]@{ Syntax = 'pmx disk grow <name|vmid> <slot> <size> [--dry-run]'; Description = 'grow an explicitly selected virtual disk' },
            [pscustomobject]@{ Syntax = 'pmx disk grow --vm <name|vmid> --disk <slot> --to <size> [--dry-run]'; Description = 'script-friendly explicit virtual-disk growth' },
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
    Write-Host '  Detailed help: pmx help vm · pmx help vm network · pmx help disk grow · pmx help snapshot' -ForegroundColor DarkGray
    Write-Host '  Educational options: --explain · --dry-run · --show-native · --json/-j · --table/-t' -ForegroundColor DarkGray
    Write-Host ''
}
