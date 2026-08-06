# ==============================================================================
# PowerFlow — Proxmox Help
# ==============================================================================
# Domain   : Proxmox
# File     : components/proxmox/help.ps1
# Purpose  : Table-driven overview and educational topic help for pmx
# Functions: Get-PmxHelpTopics, Show-PmxHelp, Show-PmxTopicHelp
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
        Syntax = @('pmx vm show <vmid|name> [--json|--table]', 'pmx vm show --vm <vmid|name>')
        Example = @('pmx vm show 101', 'pmx vm show docker-host')
        Native = @('pvesh get /nodes/<node>/qemu/<vmid>/config --current 1', 'pvesh get /nodes/<node>/qemu/<vmid>/status/current')
        Safety = 'Green. Read only.'
        Story = 'Resolve the friendly sign to its authoritative room number, then inspect it.'
    }
    $topics['vm status'] = [pscustomobject]@{
        Purpose = 'Show current power and runtime status for one VM.'
        Syntax = @('pmx vm status <vmid|name> [--json|--table]')
        Example = @('pmx vm status 101')
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
        Syntax = @('pmx vm clone --source <vmid|name> --new-vmid <number|auto> --name <dns-name> [--full] [--dry-run]')
        Example = @('pmx vm clone --source debian-base --new-vmid auto --name docker-host --full --dry-run')
        Native = @('qm clone <source-vmid> <new-vmid> --name <name> --full 1')
        Safety = 'Amber. Validates template/state/storage, previews, confirms, revalidates, executes, and verifies.'
        Story = 'Copy one hotel room into a new, independently owned room number.'
    }
    $topics['vm cpu set'] = [pscustomobject]@{
        Purpose = 'Set cores per socket for one VM.'
        Syntax = @('pmx vm cpu set --vm <vmid|name> --cores <number> [--dry-run]')
        Example = @('pmx vm cpu set --vm 102 --cores 4 --dry-run')
        Native = @('qm set <vmid> --cores <number> --digest <sha1>')
        Safety = 'Amber. Shows sockets × cores, confirms, revalidates the digest, and verifies desired config.'
        Story = 'Cores are workers on each CPU socket; total vCPUs are sockets multiplied by cores.'
    }
    $topics['vm memory set'] = [pscustomobject]@{
        Purpose = 'Set VM memory with a friendly binary unit.'
        Syntax = @('pmx vm memory set --vm <vmid|name> --size <MiB|GiB|TiB> [--dry-run]')
        Example = @('pmx vm memory set --vm 102 --size 8GiB --dry-run')
        Native = @('qm set <vmid> --memory <MiB> --digest <sha1>')
        Safety = 'Amber. Displays the friendly and native units, confirms, revalidates, and verifies.'
        Story = 'PowerFlow translates 8 GiB into the 8192 MiB value Proxmox expects.'
    }
    $topics['disk list'] = [pscustomobject]@{
        Purpose = 'List virtual disks attached to a VM.'
        Syntax = @('pmx disk list --vm <vmid|name> [--json|--table]')
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
        Example = @('pmx vm start 102 --dry-run')
        Native = @('qm start <vmid>')
        Safety = 'Amber. Running is a no-op; state is revalidated and verified.'
        Story = 'Wake the room only after confirming the authoritative VMID.'
    }
    $topics['vm shutdown'] = [pscustomobject]@{
        Purpose = 'Request a graceful ACPI shutdown.'
        Syntax = @('pmx vm shutdown <vmid|name> [--dry-run]')
        Example = @('pmx vm shutdown 102 --dry-run')
        Native = @('qm shutdown <vmid>')
        Safety = 'Amber. Never adds forceStop; stopped is a no-op.'
        Story = 'Ask the guest to close cleanly instead of pulling its power cable.'
    }
    $topics['snapshot list'] = [pscustomobject]@{
        Purpose = 'List real snapshots for one VM.'
        Syntax = @('pmx snapshot list --vm <vmid|name> [--json|--table]')
        Example = @('pmx snapshot list --vm 102')
        Native = @('pvesh get /nodes/<node>/qemu/<vmid>/snapshot')
        Safety = 'Green. The synthetic current row is omitted.'
        Story = 'See the saved restore points without confusing current state for a snapshot.'
    }
    $topics['snapshot create'] = [pscustomobject]@{
        Purpose = 'Create a named snapshot for one VM.'
        Syntax = @('pmx snapshot create --vm <vmid|name> --name <snapshot> [--dry-run]')
        Example = @('pmx snapshot create --vm 102 --name pre-docker --dry-run')
        Native = @('qm snapshot <vmid> <snapshot>')
        Safety = 'Amber. Refuses reserved/duplicate names, confirms, revalidates, and verifies.'
        Story = 'Take a labelled photograph of the VM before a meaningful change.'
    }
    return $topics
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
    Write-Host '  MANAGEMENT' -ForegroundColor Yellow
    Write-Host '  pmx config show|set|reset|validate   target and policy settings' -ForegroundColor White
    Write-Host '  pmx discover                         nodes, storage, bridges, IDs, templates' -ForegroundColor White
    Write-Host '  pmx node status                      selected node status' -ForegroundColor White
    Write-Host '  pmx storage list                     VM-image storage and capacity' -ForegroundColor White
    Write-Host '  pmx vm list|show|status|next-id       inspect VMs and templates' -ForegroundColor White
    Write-Host '  pmx vm clone                         guarded full clone' -ForegroundColor White
    Write-Host '  pmx vm cpu set | memory set           guarded resource changes' -ForegroundColor White
    Write-Host '  pmx disk list|grow --vm <vm>          virtual disks' -ForegroundColor White
    Write-Host '  pmx vm start|shutdown                 guarded lifecycle' -ForegroundColor White
    Write-Host '  pmx snapshot list|create              VM snapshots' -ForegroundColor White
    Write-Host ''
    Write-Host '  LOCAL HOST & PHYSICAL DISKS' -ForegroundColor Yellow
    Write-Host '  pmx                                    local node dashboard' -ForegroundColor White
    Write-Host '  pmx disks                              physical disk inventory' -ForegroundColor White
    Write-Host '  pmx disk [device|serial]               physical disk + SMART summary' -ForegroundColor White
    Write-Host '  pmx disk <device> -Full                full smartctl report' -ForegroundColor White
    Write-Host '  pmx disk <device> test short|long      launch SMART self-test' -ForegroundColor White
    Write-Host '  pmx disk <device> report [-Write]      evidence report/bundle' -ForegroundColor White
    Write-Host '  pmx disk <device> capacity-test        explain the destructive F3 gate' -ForegroundColor White
    Write-Host '  pmx pools | guests | updates           local Proxmox host views' -ForegroundColor White
    Write-Host ''
    Write-Host '  Detailed help: pmx help vm clone · pmx help disk grow' -ForegroundColor DarkGray
    Write-Host '  Educational options: --explain · --dry-run · --show-native · --json · --table' -ForegroundColor DarkGray
    Write-Host ''
}
