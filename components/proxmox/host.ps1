# ==============================================================================
# PowerFlow — Proxmox Host Views
# ==============================================================================
# Domain   : Proxmox
# File     : components/proxmox/host.ps1
# Purpose  : Proxmox node, storage, guest, and update views
# Functions: Show-PmxPools, Show-PmxGuests, Show-PmxUpdates, Show-PmxDashboard,
#            Show-PmxManagedNodeStatus, Show-PmxManagedStorage, Show-PmxDiscovery
# Depends  : shared.ps1, config.ps1, vm-read.ps1, Proxmox adapter contracts
# ==============================================================================

function Show-PmxPools {
    $storage = @(Get-ProxmoxStorage)
    $zpools = @(Get-ProxmoxZfsPools)
    Write-Host ''
    Write-Host '🗄️ PROXMOX STORAGE' -ForegroundColor Cyan
    Write-Host '────────────────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
    if ($storage.Count) {
        Write-Host ('  {0,-18} {1,-10} {2,10} {3,10}  {4}' -f 'NAME', 'TYPE', 'USED', 'TOTAL', 'STATE') -ForegroundColor DarkGray
        foreach ($s in $storage) {
            $state = if (-not $s.Enabled) { 'disabled' } elseif (-not $s.Active) { 'inactive' } else { 'active' }
            $color = if ($s.Active -and $s.Enabled) { 'White' } else { 'Yellow' }
            Write-Host ('  {0,-18} {1,-10} {2,10} {3,10}  {4}' -f $s.Name, $s.Type, (Format-PmxBytes $s.UsedBytes), (Format-PmxBytes $s.TotalBytes), $state) -ForegroundColor $color
        }
    } else { Write-Host '  No Proxmox storage data returned.' -ForegroundColor DarkGray }

    Write-Host ''
    Write-Host '🌊 ZFS POOLS' -ForegroundColor Cyan
    if ($zpools.Count) {
        foreach ($p in $zpools) {
            $color = if ($p.Health -eq 'ONLINE') { 'Green' } else { 'Red' }
            Write-Host ('  {0,-18} {1,-10} {2,10} used · {3,10} free · {4} full · {5} frag' -f $p.Name, $p.Health, (Format-PmxBytes $p.AllocatedBytes), (Format-PmxBytes $p.FreeBytes), $p.Capacity, $p.Fragmentation) -ForegroundColor $color
        }
    } else { Write-Host '  No ZFS pools present.' -ForegroundColor DarkGray }
    Write-Host ''
}

function Show-PmxGuests {
    param([string]$Selector)
    $guests = @(Get-ProxmoxGuests)
    if ($Selector) {
        # $hits, not $matches (an automatic variable — see Resolve-PmxDisk).
        $hits = @($guests | Where-Object { "$($_.Id)" -eq $Selector -or $_.Name -ieq $Selector })
        if ($hits.Count -ne 1) {
            Write-Host "❌ Guest '$Selector' was not found uniquely." -ForegroundColor Red
            return
        }
        $g = $hits[0]
        Write-Host ''
        Write-Host "🧱 $($g.Kind) $($g.Id) — $($g.Name)" -ForegroundColor Cyan
        Write-PmxField 'Node' $g.Node
        Write-PmxField 'Status' $g.Status $(if ($g.Status -eq 'running') { 'Green' } else { 'Yellow' })
        Write-PmxField 'CPU' ('{0:N1}% of {1}' -f ($g.CpuUsage * 100), $g.CpuCount)
        Write-PmxField 'Memory' "$(Format-PmxBytes $g.MemoryBytes) of $(Format-PmxBytes $g.MaxMemory)"
        Write-PmxField 'Disk' "$(Format-PmxBytes $g.DiskBytes) of $(Format-PmxBytes $g.MaxDisk)"
        Write-PmxField 'Uptime' (Format-PmxUptime $g.Uptime)
        Write-Host ''
        return
    }

    Write-Host ''
    Write-Host "🧱 GUESTS — $(@($guests | Where-Object Status -eq 'running').Count) running of $($guests.Count)" -ForegroundColor Cyan
    Write-Host '────────────────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
    Write-Host ('  {0,-7} {1,-4} {2,-25} {3,-10} {4,9} {5,10}' -f 'ID', 'KIND', 'NAME', 'STATUS', 'CPU', 'MEMORY') -ForegroundColor DarkGray
    foreach ($g in $guests) {
        $color = if ($g.Status -eq 'running') { 'White' } else { 'DarkGray' }
        Write-Host ('  {0,-7} {1,-4} {2,-25} {3,-10} {4,8:N1}% {5,10}' -f $g.Id, $g.Kind, $g.Name, $g.Status, ($g.CpuUsage * 100), (Format-PmxBytes $g.MemoryBytes)) -ForegroundColor $color
    }
    Write-Host ''
}

function Show-PmxUpdates {
    $updates = @(Get-ProxmoxUpdates)
    Write-Host ''
    Write-Host "📦 PENDING UPDATES — $($updates.Count)" -ForegroundColor Cyan
    Write-Host '────────────────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
    if (-not $updates.Count) {
        Write-Host '  No cached updates returned. This view does not run apt update.' -ForegroundColor DarkGray
    } else {
        foreach ($u in $updates) {
            Write-Host "  $($u.Package)" -NoNewline -ForegroundColor White
            Write-Host "  $($u.Current) → $($u.Available)" -ForegroundColor DarkGray
        }
    }
    Write-Host ''
    Write-Host '  Read-only: pmx never installs upgrades.' -ForegroundColor DarkGray
}

function Show-PmxDashboard {
    $node = Get-ProxmoxNodeSummary
    if (-not $node) {
        Write-Host '❌ Proxmox returned no node status.' -ForegroundColor Red
        return
    }
    $guests = @(Get-ProxmoxGuests)
    $storage = @(Get-ProxmoxStorage)
    $zpools = @(Get-ProxmoxZfsPools)
    $running = @($guests | Where-Object Status -eq 'running').Count

    Write-Host ''
    Write-Host "⚡ PROXMOX VE — $($node.Node)" -ForegroundColor Cyan
    Write-Host '──────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
    Write-PmxField 'Version' $(if ($node.Version) { $node.Version } else { 'unknown' })
    Write-PmxField 'Uptime' (Format-PmxUptime $node.UptimeSeconds)
    Write-PmxField 'CPU' ('{0:N1}% · {1} logical CPUs · load {2}' -f ($node.CpuUsage * 100), $node.CpuCount, (@($node.LoadAverage) -join ' '))
    Write-PmxField 'Memory' "$(Format-PmxBytes $node.MemoryUsedBytes) of $(Format-PmxBytes $node.MemoryTotalBytes)"
    Write-PmxField 'Root disk' "$(Format-PmxBytes $node.RootUsedBytes) of $(Format-PmxBytes $node.RootTotalBytes)"
    Write-PmxField 'Guests' "$running running of $($guests.Count)"
    Write-PmxField 'Storage' "$(@($storage | Where-Object { $_.Active -and $_.Enabled }).Count) active of $($storage.Count)"
    if ($zpools.Count) {
        $bad = @($zpools | Where-Object Health -ne 'ONLINE')
        Write-PmxField 'ZFS' $(if ($bad.Count) { "$($bad.Count) pool(s) need attention" } else { "$($zpools.Count) pool(s) online" }) $(if ($bad.Count) { 'Red' } else { 'Green' })
    }
    if ($node.Cluster) {
        $q = if ($null -eq $node.Quorate) { 'quorum unknown' } elseif ($node.Quorate) { 'quorate' } else { 'NO QUORUM' }
        Write-PmxField 'Cluster' "$($node.Cluster) · $q" $(if ($node.Quorate -eq $false) { 'Red' } else { 'White' })
    }
    Write-Host ''
    Write-Host '  pmx disks  ·  pmx pools  ·  pmx guests  ·  pmx updates' -ForegroundColor DarkGray
    Write-Host ''
}

function Get-PmxManagementReadOptions {
    param([object[]]$Arguments = @())
    return (ConvertFrom-PmxArguments -Arguments $Arguments -SwitchOptions (Get-PmxGlobalSwitchMap) -MaxPositionals 0)
}

function Show-PmxManagedNodeStatus {
    param([object[]]$Arguments = @())

    $parsed = Get-PmxManagementReadOptions -Arguments $Arguments
    if (-not $parsed.Success) { Write-Host "❌ $($parsed.Error)" -ForegroundColor Red; return }
    if ($parsed.Options.Help) { Show-PmxTopicHelp 'node status'; return }
    $session = Get-PmxManagementSession
    if (-not $session.Success) { Write-PmxDisconnectedState -Session $session; return }
    $result = Invoke-ProxmoxManagementQuery -Operation 'node-status' -Connection $session.Connection -Parameters @{ Node = $session.Node }
    if (-not $result.Success) { Write-Host "❌ $($result.Error)" -ForegroundColor Red; return }
    $mode = Get-PmxOutputMode -Options $parsed.Options -Config $session.Config
    if (-not $mode.Success) { Write-Host "❌ $($mode.Error)" -ForegroundColor Red; return }
    if ($mode.Mode -eq 'json') { Write-PmxJson $result.Data; return }

    $node = $result.Data
    $cpuInfo = Get-PmxObjectProperty $node 'cpuinfo' $null
    $memory = Get-PmxObjectProperty $node 'memory' $null
    $rootfs = Get-PmxObjectProperty $node 'rootfs' $null
    Write-Host ''
    Write-Host "⚡ PROXMOX NODE — $((ConvertTo-PmxDisplayText $session.Node))" -ForegroundColor Cyan
    Write-Host '──────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
    Write-PmxField 'Version' (ConvertTo-PmxDisplayText (Get-PmxObjectProperty $node 'pveversion' 'unknown'))
    Write-PmxField 'Kernel' (ConvertTo-PmxDisplayText (Get-PmxObjectProperty $node 'kversion' 'unknown'))
    Write-PmxField 'Uptime' (Format-PmxUptime ([long](Get-PmxObjectProperty $node 'uptime' 0)))
    $cpuCount = if ($cpuInfo) { [int](Get-PmxObjectProperty $cpuInfo 'cpus' 0) } else { [int](Get-PmxObjectProperty $node 'maxcpu' 0) }
    Write-PmxField 'CPU' ('{0:N1}% · {1} logical CPUs' -f ([double](Get-PmxObjectProperty $node 'cpu' 0) * 100), $cpuCount)
    if ($memory) { Write-PmxField 'Memory' "$(Format-PmxBytes ([long](Get-PmxObjectProperty $memory 'used' 0))) of $(Format-PmxBytes ([long](Get-PmxObjectProperty $memory 'total' 0)))" }
    if ($rootfs) { Write-PmxField 'Root disk' "$(Format-PmxBytes ([long](Get-PmxObjectProperty $rootfs 'used' 0))) of $(Format-PmxBytes ([long](Get-PmxObjectProperty $rootfs 'total' 0)))" }
    Write-Host ''
}

function Show-PmxManagedStorage {
    param([object[]]$Arguments = @())

    $parsed = Get-PmxManagementReadOptions -Arguments $Arguments
    if (-not $parsed.Success) { Write-Host "❌ $($parsed.Error)" -ForegroundColor Red; return }
    if ($parsed.Options.Help) { Show-PmxTopicHelp 'storage list'; return }
    $session = Get-PmxManagementSession
    if (-not $session.Success) { Write-PmxDisconnectedState -Session $session; return }
    $result = Invoke-ProxmoxManagementQuery -Operation 'storage-list' -Connection $session.Connection -Parameters @{ Node = $session.Node }
    if (-not $result.Success) { Write-Host "❌ $($result.Error)" -ForegroundColor Red; return }
    $storage = @($result.Data)
    $mode = Get-PmxOutputMode -Options $parsed.Options -Config $session.Config
    if (-not $mode.Success) { Write-Host "❌ $($mode.Error)" -ForegroundColor Red; return }
    if ($mode.Mode -eq 'json') { Write-PmxJson $storage; return }

    Write-Host ''
    Write-Host "🗄️ VM STORAGE — $((ConvertTo-PmxDisplayText $session.Node))" -ForegroundColor Cyan
    Write-Host '────────────────────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
    Write-Host ('  {0,-18} {1,-11} {2,11} {3,11} {4,11}  {5}' -f 'STORAGE', 'TYPE', 'USED', 'AVAILABLE', 'TOTAL', 'STATE') -ForegroundColor DarkGray
    foreach ($item in $storage) {
        $total = [long](Get-PmxObjectProperty $item 'total' (Get-PmxObjectProperty $item 'maxdisk' 0))
        $used = [long](Get-PmxObjectProperty $item 'used' (Get-PmxObjectProperty $item 'disk' 0))
        $available = [long](Get-PmxObjectProperty $item 'avail' ([math]::Max(0, $total - $used)))
        $active = (Get-PmxObjectProperty $item 'active' 1) -eq 1 -or (Get-PmxObjectProperty $item 'status' '') -eq 'available'
        $enabled = (Get-PmxObjectProperty $item 'enabled' 1) -eq 1
        $state = if (-not $enabled) { 'disabled' } elseif ($active) { 'active' } else { 'inactive' }
        Write-Host ('  {0,-18} {1,-11} {2,11} {3,11} {4,11}  {5}' -f
            (ConvertTo-PmxDisplayText (Get-PmxObjectProperty $item 'storage' 'unknown')),
            (ConvertTo-PmxDisplayText (Get-PmxObjectProperty $item 'type' 'unknown')),
            (Format-PmxBytes $used), (Format-PmxBytes $available), (Format-PmxBytes $total), $state) `
            -ForegroundColor $(if ($active -and $enabled) { 'White' } else { 'Yellow' })
    }
    Write-Host ''
}

function Show-PmxDiscovery {
    param([object[]]$Arguments = @())

    $parsed = Get-PmxManagementReadOptions -Arguments $Arguments
    if (-not $parsed.Success) { Write-Host "❌ $($parsed.Error)" -ForegroundColor Red; return }
    if ($parsed.Options.Help) { Show-PmxTopicHelp 'discover'; return }
    $session = Get-PmxManagementSession
    if (-not $session.Success) { Write-PmxDisconnectedState -Session $session; return }

    $version = Invoke-ProxmoxManagementQuery -Operation 'version' -Connection $session.Connection
    $storage = Invoke-ProxmoxManagementQuery -Operation 'storage-list' -Connection $session.Connection -Parameters @{ Node = $session.Node }
    $bridges = Invoke-ProxmoxManagementQuery -Operation 'bridge-list' -Connection $session.Connection -Parameters @{ Node = $session.Node }
    $vms = Get-PmxManagedVmRows -Session $session
    $next = Invoke-ProxmoxManagementQuery -Operation 'next-id' -Connection $session.Connection
    foreach ($check in @($version, $storage, $bridges, $next)) {
        if (-not $check.Success) { Write-Host "❌ Discovery failed: $($check.Error)" -ForegroundColor Red; return }
    }
    if (-not $vms.Success) { Write-Host "❌ Discovery failed: $($vms.Error)" -ForegroundColor Red; return }

    $templates = @($vms.Vms | Where-Object Template | ForEach-Object { [pscustomobject]@{ vmid = $_.VmId; name = $_.Name } })
    $bridgeNames = @($bridges.Data | ForEach-Object { ConvertTo-PmxDisplayText (Get-PmxObjectProperty $_ 'iface' (Get-PmxObjectProperty $_ 'name' '')) } | Where-Object { $_ })
    $storageNames = @($storage.Data | ForEach-Object { ConvertTo-PmxDisplayText (Get-PmxObjectProperty $_ 'storage' '') } | Where-Object { $_ })
    $discovery = [pscustomobject]@{
        Transport   = $session.Connection.Transport
        Target      = $session.Connection.Label
        Version     = Get-PmxObjectProperty $version.Data 'version' "$($version.Data)"
        Nodes       = @($session.Nodes | ForEach-Object { ConvertTo-PmxDisplayText (Get-PmxObjectProperty $_ 'node' '') })
        SelectedNode = $session.Node
        Storage     = $storageNames
        Bridges     = $bridgeNames
        VmIds       = @($vms.Vms.VmId)
        NextVmId    = [int]$next.Data
        Templates   = $templates
    }
    $mode = Get-PmxOutputMode -Options $parsed.Options -Config $session.Config
    if (-not $mode.Success) { Write-Host "❌ $($mode.Error)" -ForegroundColor Red; return }
    if ($mode.Mode -eq 'json') { Write-PmxJson $discovery; return }

    Write-Host ''
    Write-Host '🔎 PROXMOX DISCOVERY' -ForegroundColor Cyan
    Write-Host '──────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
    Write-PmxField 'Transport' "$($discovery.Transport) → $($discovery.Target)"
    Write-PmxField 'Version' (ConvertTo-PmxDisplayText $discovery.Version)
    Write-PmxField 'Nodes' (@($discovery.Nodes) -join ', ')
    Write-PmxField 'Selected node' (ConvertTo-PmxDisplayText $discovery.SelectedNode)
    Write-PmxField 'Storage' $(if ($storageNames.Count) { $storageNames -join ', ' } else { 'none' })
    Write-PmxField 'Bridges' $(if ($bridgeNames.Count) { $bridgeNames -join ', ' } else { 'none' })
    Write-PmxField 'VMs' "$($vms.Vms.Count) existing · next ID $($discovery.NextVmId)"
    Write-PmxField 'Templates' $(if ($templates.Count) { @($templates | ForEach-Object { "$($_.vmid) $($_.name)" }) -join ', ' } else { 'none' })
    Write-Host ''
}
