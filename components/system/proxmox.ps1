# ==============================================================================
# PowerFlow — Proxmox VE
# ==============================================================================
# Domain   : System
# File     : components/system/proxmox.ps1
# Purpose  : Compact Proxmox node, disk, pool, guest, update, and SMART workflows
# Functions: pmx, Show-PmxDashboard, Show-PmxDisks, Show-PmxDisk, Show-PmxPools,
#            Show-PmxGuests, Show-PmxUpdates, Resolve-PmxDisk,
#            Invoke-PmxSmartTest, Invoke-PmxCapacityTest
# Depends  : Proxmox adapter contract (platform/<os>/adapters/proxmox.ps1)
# ==============================================================================

function Format-PmxBytes {
    param([long]$Bytes)
    if ($Bytes -ge 1TB) { return ('{0:N1} TB' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:N1} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N0} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

function Format-PmxUptime {
    param([long]$Seconds)
    $span = [TimeSpan]::FromSeconds([math]::Max(0, $Seconds))
    if ($span.Days -gt 0) { return "$($span.Days)d $($span.Hours)h" }
    if ($span.Hours -gt 0) { return "$($span.Hours)h $($span.Minutes)m" }
    return "$($span.Minutes)m"
}

function Write-PmxField {
    param([string]$Label, [string]$Value, [ConsoleColor]$Color = 'White')
    # The trailing space is load-bearing. `{0,-13}` is a MINIMUM width — .NET never
    # truncates — so a label at or over the width emitted no padding and no separator, and
    # 'Capacity test' (13) rendered as "Capacity testblocked — mounted at /" on every
    # `pmx disk` view. An explicit space keeps a longer label readable instead of merged.
    Write-Host ('  {0,-13} ' -f $Label) -NoNewline -ForegroundColor DarkGray
    Write-Host $Value -ForegroundColor $Color
}

function Test-PmxReady {
    if (Test-ProxmoxSupport) { return $true }
    Write-Host '❌ pmx only runs inside a Proxmox VE host.' -ForegroundColor Red
    Write-Host '   Connect first (for example: srv proxmox), then run pmx in that PowerFlow session.' -ForegroundColor DarkGray
    return $false
}

function Resolve-PmxDisk {
    param([string]$Selector, [switch]$Interactive)
    $disks = @(Get-ProxmoxDisks)
    if (-not $disks.Count) {
        Write-Host '❌ No physical disks were returned by the host.' -ForegroundColor Red
        return $null
    }

    if (-not $Selector) {
        if (-not $Interactive -or [Console]::IsOutputRedirected -or -not (Get-Command fzf -ErrorAction SilentlyContinue)) {
            return $null
        }
        $tab = [char]9
        $rows = for ($i = 0; $i -lt $disks.Count; $i++) {
            $d = $disks[$i]
            $media = if ($d.Rotational) { 'HDD' } else { 'SSD' }
            "$i$tab$($d.Name)$tab$(Format-PmxBytes $d.SizeBytes)$tab$media$tab$($d.Model)$tab$($d.Serial)"
        }
        $picked = $rows | fzf --height=60% --layout=reverse --border --delimiter="$tab" --with-nth=2.. --header='disk  size  type  model  serial'
        if (-not $picked) { return $null }
        $index = [int]("$picked" -split "$tab", 2)[0]
        return $disks[$index]
    }

    $needle = $Selector.Trim()
    # NOT $matches: that is a PowerShell AUTOMATIC variable, rewritten by every -match in
    # scope. Using it as a local here is a latent bug that would surface the moment any
    # regex ran between assignment and use.
    $hits = @($disks | Where-Object {
        $_.Name -ieq $needle -or $_.Path -ieq $needle -or $_.Serial -ieq $needle -or
        $_.StableId -ieq $needle -or [IO.Path]::GetFileName($_.StableId) -ieq $needle -or
        @($_.StableIds | Where-Object { $_ -ieq $needle -or [IO.Path]::GetFileName($_) -ieq $needle }).Count -gt 0
    })
    if ($hits.Count -eq 1) { return $hits[0] }
    if ($hits.Count -gt 1) {
        Write-Host "❌ '$Selector' matches more than one disk. Use the device name or full stable ID:" -ForegroundColor Red
        $hits | ForEach-Object { Write-Host "   $($_.Name)  $($_.StableId)" -ForegroundColor DarkGray }
    } else {
        Write-Host "❌ No physical disk matches '$Selector'. Run: pmx disks" -ForegroundColor Red
    }
    return $null
}

function Show-PmxDisks {
    $disks = @(Get-ProxmoxDisks)
    Write-Host ''
    Write-Host "💾 PHYSICAL DISKS — $($disks.Count)" -ForegroundColor Cyan
    Write-Host '────────────────────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
    if (-not $disks.Count) {
        Write-Host '  No physical disks found.' -ForegroundColor DarkGray
        return
    }
    Write-Host ('  {0,-9} {1,10}  {2,-5} {3,-25} {4,-18} {5}' -f 'DEVICE', 'SIZE', 'TYPE', 'MODEL', 'SERIAL', 'USE') -ForegroundColor DarkGray
    foreach ($d in $disks) {
        $media = if ($d.Rotational) { 'HDD' } else { 'SSD' }
        $use = @()
        if ($d.ProxmoxUse) { $use += $d.ProxmoxUse }
        if (@($d.Partitions).Count) { $use += "$(@($d.Partitions).Count) part" }
        if (@($d.Mountpoints).Count) { $use += 'mounted' }
        if (@($d.Holders).Count) { $use += "held:$(@($d.Holders) -join ',')" }
        if (-not $use.Count) { $use = @('raw') }
        $model = if ($d.Model) { $d.Model } else { 'unknown' }
        if ($model.Length -gt 25) { $model = $model.Substring(0, 24) + '…' }
        $serial = if ($d.Serial) { $d.Serial } else { 'unknown' }
        if ($serial.Length -gt 18) { $serial = $serial.Substring(0, 17) + '…' }
        Write-Host ('  {0,-9} {1,10}  {2,-5} {3,-25} {4,-18} {5}' -f $d.Name, (Format-PmxBytes $d.SizeBytes), $media, $model, $serial, ($use -join ' · ')) -ForegroundColor White
    }
    Write-Host ''
    Write-Host '  Open one:  pmx disk <device|serial>   ·   picker:  pmx disk' -ForegroundColor DarkGray
}

function Show-PmxSmart {
    param($Smart)
    if (-not $Smart -or -not $Smart.Available) {
        $why = if ($Smart -and $Smart.Error) { $Smart.Error } else { 'SMART data unavailable.' }
        Write-PmxField 'SMART' $why Yellow
        return
    }

    $health = if ($null -eq $Smart.OverallPassed) { 'UNKNOWN' } elseif ($Smart.OverallPassed) { 'PASSED' } else { 'FAILED' }
    $healthColor = if ($null -eq $Smart.OverallPassed) { 'Yellow' } elseif ($Smart.OverallPassed) { 'Green' } else { 'Red' }
    $detail = @($health)
    if ($null -ne $Smart.TemperatureC) { $detail += "$($Smart.TemperatureC)°C" }
    if ($null -ne $Smart.PowerOnHours) { $detail += "$($Smart.PowerOnHours) power-on hours" }
    if ($null -ne $Smart.PowerCycles) { $detail += "$($Smart.PowerCycles) cycles" }
    Write-PmxField 'SMART' ($detail -join ' · ') $healthColor

    $signals = @()
    if ($null -ne $Smart.ReallocatedSectors) { $signals += "reallocated $($Smart.ReallocatedSectors)" }
    if ($null -ne $Smart.PendingSectors) { $signals += "pending $($Smart.PendingSectors)" }
    if ($null -ne $Smart.OfflineUncorrectable) { $signals += "uncorrectable $($Smart.OfflineUncorrectable)" }
    if ($null -ne $Smart.CrcErrors) { $signals += "CRC $($Smart.CrcErrors)" }
    if ($null -ne $Smart.MediaErrors) { $signals += "media errors $($Smart.MediaErrors)" }
    if ($null -ne $Smart.PercentageUsed) { $signals += "endurance used $($Smart.PercentageUsed)%" }
    if ($signals.Count) { Write-PmxField 'Signals' ($signals -join ' · ') }
    if ($Smart.SelfTestStatus) { Write-PmxField 'Self-test' $Smart.SelfTestStatus }
}

function Show-PmxDisk {
    param($Disk, [switch]$Full)
    if (-not $Disk) { return }
    $device = if ($Disk.StableId) { $Disk.StableId } else { $Disk.Path }

    if ($Full) {
        Write-Host ''
        Write-Host "🧾 SMART REPORT — $($Disk.Name) · $($Disk.Model) · $($Disk.Serial)" -ForegroundColor Cyan
        Get-ProxmoxSmartReport -DevicePath $device | ForEach-Object { Write-Host $_ }
        return
    }

    Write-Host ''
    Write-Host "💾 DISK $($Disk.Name)" -ForegroundColor Cyan
    Write-Host '──────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
    Write-PmxField 'Model' $(if ($Disk.Model) { $Disk.Model } else { 'unknown' })
    Write-PmxField 'Serial' $(if ($Disk.Serial) { $Disk.Serial } else { 'unknown' })
    Write-PmxField 'Stable ID' $(if ($Disk.StableId) { $Disk.StableId } else { 'none — destructive actions disabled' }) $(if ($Disk.StableId) { 'White' } else { 'Yellow' })
    $media = if ($Disk.Rotational) { 'HDD' } else { 'SSD' }
    $transport = if ($Disk.Transport) { $Disk.Transport.ToUpper() } else { 'unknown bus' }
    Write-PmxField 'Capacity' "$(Format-PmxBytes $Disk.SizeBytes) · $media · $transport"

    if (@($Disk.Partitions).Count) {
        $partText = @($Disk.Partitions | ForEach-Object {
            "$($_.Name) $(Format-PmxBytes $_.SizeBytes)$(if ($_.FileSystem) { " $($_.FileSystem)" })"
        }) -join ' · '
        Write-PmxField 'Partitions' $partText Yellow
    } else { Write-PmxField 'Partitions' 'none' Green }
    if (@($Disk.Mountpoints).Count) { Write-PmxField 'Mounted' (@($Disk.Mountpoints) -join ', ') Yellow }
    if (@($Disk.Holders).Count) { Write-PmxField 'Holders' (@($Disk.Holders) -join ', ') Yellow }
    if ($Disk.ProxmoxUse) { Write-PmxField 'Proxmox use' $Disk.ProxmoxUse Yellow }

    Show-PmxSmart (Get-ProxmoxSmartInfo -DevicePath $device)

    $safety = Get-ProxmoxDiskSafety -StablePath $device
    if ($safety.Safe) {
        Write-PmxField 'Capacity test' 'eligible after -Destroy and a typed DESTROY <by-id> confirmation' Yellow
    } else {
        Write-PmxField 'Capacity test' ('blocked — ' + (@($safety.Reasons) -join '; ')) DarkGray
    }
    Write-Host ''
    Write-Host "  Full SMART:  pmx disk $($Disk.Name) -Full" -ForegroundColor DarkGray
    Write-Host "  SMART test:  pmx disk $($Disk.Name) test short|long" -ForegroundColor DarkGray
}

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

function Invoke-PmxSmartTest {
    param($Disk, [string]$Kind)
    if ($Kind -eq 'extended') { $Kind = 'long' }
    if ($Kind -notin @('short', 'long')) {
        Write-Host '❌ Use: pmx disk <device> test short|long' -ForegroundColor Red
        return
    }
    $device = if ($Disk.StableId) { $Disk.StableId } else { $Disk.Path }
    $result = Start-ProxmoxSmartTest -DevicePath $device -Kind $Kind
    foreach ($line in @($result.Output)) { Write-Host "  $line" -ForegroundColor DarkGray }
    Write-Host $(if ($result.Success) { "✅ $($result.Message)" } else { "❌ $($result.Message)" }) -ForegroundColor $(if ($result.Success) { 'Green' } else { 'Red' })
}

function Invoke-PmxCapacityTest {
    param($Disk, [switch]$Destroy)
    if (-not $Destroy) {
        Write-Host '⛔ No action taken. An F3 capacity test writes raw sectors and destroys data.' -ForegroundColor Red
        Write-Host "   If this is a new, completely empty disk: pmx disk $($Disk.Name) capacity-test -Destroy" -ForegroundColor Yellow
        return
    }
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        Write-Host '❌ Destructive capacity tests require an interactive terminal.' -ForegroundColor Red
        return
    }
    $device = $Disk.StableId
    if (-not $device) {
        Write-Host '❌ Refused: the disk has no stable /dev/disk/by-id identity.' -ForegroundColor Red
        return
    }
    $safety = Get-ProxmoxDiskSafety -StablePath $device
    if (-not $safety.Safe) {
        Write-Host '❌ Refused — this disk is not provably empty and idle:' -ForegroundColor Red
        @($safety.Reasons) | ForEach-Object { Write-Host "   • $_" -ForegroundColor Yellow }
        return
    }

    # The phrase MUST be the one the adapter checks. These disagreed until v2: the prompt
    # asked for the serial while Invoke-ProxmoxCapacityProbe required "DESTROY <by-id leaf>",
    # so no answer could ever satisfy it and the feature was dead (fail-closed, but dead).
    # The by-id leaf is kept as the phrase because it names THIS device — a serial names a
    # product, and is easy to paste from the wrong row of a disk list.
    $leaf = [IO.Path]::GetFileName($device)
    $phrase = "DESTROY $leaf"

    Write-Host ''
    Write-Host '⛔ DESTRUCTIVE CAPACITY TEST' -ForegroundColor Red
    Write-Host "   Device : $device" -ForegroundColor White
    Write-Host "   Model  : $($safety.Disk.Model)" -ForegroundColor White
    Write-Host "   Serial : $($safety.Disk.Serial)" -ForegroundColor Yellow
    Write-Host "   Size   : $(Format-PmxBytes $safety.Disk.SizeBytes)" -ForegroundColor White
    Write-Host '   F3 will write directly to this disk. Existing data will not be restored.' -ForegroundColor Red
    $confirmation = Read-Host "Type exactly: $phrase"
    # Pressing Enter is the most likely way a person backs out here, and Read-Host returns
    # ''. $Confirmation on the adapter is [Parameter(Mandatory)][string], which REFUSES an
    # empty string — so the abort path threw a raw ParameterBindingValidationException
    # instead of the designed "Refused" line. Fail-closed, but it reads as a malfunction
    # mid-destructive-flow, and the reflex when a tool looks broken is to run it again.
    if (-not $confirmation) {
        Write-Host '⛔ Nothing typed — cancelled. No data was written to the disk.' -ForegroundColor Yellow
        return
    }

    # The adapter repeats every safety and identity check after this prompt, immediately
    # before starting f3probe. The displayed snapshot is never trusted for execution.
    # -ExpectedWwn is passed explicitly: the adapter compares it, so omitting it left
    # $ExpectedWwn empty and made "identity changed" fire for every disk that has a WWN.
    $result = Invoke-ProxmoxCapacityProbe -StablePath $device `
        -ExpectedSerial $safety.Disk.Serial -ExpectedSizeBytes $safety.Disk.SizeBytes `
        -ExpectedMajorMinor $safety.Disk.MajorMinor -ExpectedDiskSeq $safety.Disk.DiskSeq `
        -ExpectedWwn "$($safety.Disk.Wwn)" -Confirmation $confirmation
    Write-Host $(if ($result.Success) { "✅ $($result.Message)" } else { "❌ $($result.Message)" }) -ForegroundColor $(if ($result.Success) { 'Green' } else { 'Red' })
}

# ── evidence report ───────────────────────────────────────────────────────────
# docs/proxmox.md records what this replaces: after a drive had already dropped off the bus
# twice and corrupted a filesystem, the owner spent half an hour hand-assembling SMART
# output, kernel errors, f3 logs and a written summary into a tarball to claim a refund.
# Every input to that bundle is machine-readable. None of it should be typed by hand at
# 2 a.m. after a disk failure.
function Show-PmxEvidence {
    param($Disk, [switch]$Write, [int]$Hours = 24)

    $ev = Get-ProxmoxDiskEvidence -Disk $Disk -KernelHours $Hours
    if (-not $ev) {
        Write-Host '❌ Disk evidence collection is Linux-only.' -ForegroundColor Red
        return
    }

    Write-Host ''
    Write-Host "🧪 DISK EVIDENCE — $($Disk.Name)" -ForegroundColor Cyan
    Write-Host '──────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
    Write-PmxField 'Model' $(if ($Disk.Model) { $Disk.Model } else { 'unknown' })
    Write-PmxField 'Serial' $(if ($Disk.Serial) { $Disk.Serial } else { 'unknown' })
    Write-PmxField 'WWN' $(if ($Disk.Wwn) { $Disk.Wwn } else { 'none reported' }) $(if ($Disk.Wwn) { 'White' } else { 'Yellow' })
    Write-PmxField 'Capacity' (Format-PmxBytes $Disk.SizeBytes)
    Write-PmxField 'Stable ID' $(if ($Disk.StableId) { $Disk.StableId } else { 'none' })

    Write-Host ''
    $flags = @($ev.Flags)
    if ($flags.Count) {
        $high = @($flags | Where-Object Severity -eq 'high')
        Write-Host "  ⚠️  AUTHENTICITY SIGNALS — $($flags.Count) ($($high.Count) high)" -ForegroundColor Yellow
        foreach ($f in $flags) {
            $c = switch ($f.Severity) { 'high' { 'Red' } 'medium' { 'Yellow' } default { 'DarkGray' } }
            Write-Host ("     [{0,-6}] {1,-22} {2}" -f $f.Severity, $f.Id, $f.Detail) -ForegroundColor $c
        }
        Write-Host ''
        # This wording is deliberate and is the line docs/proxmox.md itself drew.
        Write-Host '     These are observations, not a verdict. They describe how the drive presents' -ForegroundColor DarkGray
        Write-Host '     itself; only a capacity test can speak to whether the flash is real.' -ForegroundColor DarkGray
    } else {
        Write-Host '  ✅ No authenticity signals — identity looks like a genuine vendor drive.' -ForegroundColor Green
    }

    Write-Host ''
    Show-PmxSmart $ev.Smart

    Write-Host ''
    $k = $ev.Kernel
    if (-not $k.Available) {
        Write-PmxField 'Kernel log' $k.Error Yellow
    } elseif (@($k.Matches).Count) {
        Write-PmxField 'Kernel log' "$(@($k.Matches).Count) decisive error(s) in the last $($k.Hours)h" Red
        foreach ($line in @($k.Matches | Select-Object -First 8)) {
            Write-Host "     $line" -ForegroundColor DarkGray
        }
        if (@($k.Matches).Count -gt 8) { Write-Host "     …and $(@($k.Matches).Count - 8) more" -ForegroundColor DarkGray }
    } else {
        Write-PmxField 'Kernel log' "clean for $($Disk.Name) over the last $($k.Hours)h" Green
    }

    if (-not $Write) {
        Write-Host ''
        Write-Host "  Write a bundle to disk:  pmx disk $($Disk.Name) report -Write" -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    Write-PmxEvidenceBundle -Evidence $ev
}

# The bundle is plain files in a dated folder — readable by a seller, attachable to a claim,
# and independent of PowerFlow. Nothing here is written to the disk under test.
function Write-PmxEvidenceBundle {
    param($Evidence)

    $disk = $Evidence.Disk
    $slug = ($disk.Serial -replace '[^A-Za-z0-9._-]', '_')
    if (-not $slug) { $slug = $disk.Name }
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $dir = Join-Path (Join-Path (Get-HomePath) 'pmx-reports') "$slug-$stamp"

    try { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null }
    catch { Write-Host "❌ Could not create $dir : $($_.Exception.Message)" -ForegroundColor Red; return }

    $flags = @($Evidence.Flags)
    $k = $Evidence.Kernel
    $s = $Evidence.Smart

    $md = @()
    $md += "# Disk acceptance evidence — $($disk.Model) / $($disk.Serial)"
    $md += ''
    $md += "Collected $($Evidence.CollectedAt) on host ``$($Evidence.Host)`` by PowerFlow pmx."
    $md += ''
    $md += '## Device identity'
    $md += ''
    $md += '| Field | Value |'
    $md += '|---|---|'
    $md += "| Model | $($disk.Model) |"
    $md += "| Serial | $($disk.Serial) |"
    $md += "| WWN | $(if ($disk.Wwn) { $disk.Wwn } else { '**none reported**' }) |"
    $md += "| Firmware | $(if ($s.Available) { $s.Firmware } else { 'unavailable' }) |"
    $md += "| Advertised capacity | $($disk.SizeBytes) bytes ($(Format-PmxBytes $disk.SizeBytes)) |"
    $md += "| Transport | $($disk.Transport) |"
    $md += "| Stable ID | $($disk.StableId) |"
    $md += ''
    $md += '## Authenticity signals'
    $md += ''
    if ($flags.Count) {
        $md += '| Severity | Signal | Observation |'
        $md += '|---|---|---|'
        foreach ($f in $flags) { $md += "| $($f.Severity) | ``$($f.Id)`` | $($f.Detail) |" }
        $md += ''
        $md += 'These are observations about how the device presents itself, not a proof of'
        $md += 'counterfeit capacity. A capacity test is required to speak to the flash itself.'
    } else {
        $md += 'None. The device identity is consistent with a genuine vendor drive.'
    }
    $md += ''
    $md += '## SMART'
    $md += ''
    if ($s.Available) {
        $md += "- Overall health: **$(if ($null -eq $s.OverallPassed) { 'UNKNOWN' } elseif ($s.OverallPassed) { 'PASSED' } else { 'FAILED' })**"
        if ($null -ne $s.TemperatureC)  { $md += "- Temperature: $($s.TemperatureC) °C" }
        if ($null -ne $s.PowerOnHours)  { $md += "- Power-on hours: $($s.PowerOnHours)" }
        if ($null -ne $s.PowerCycles)   { $md += "- Power cycles: $($s.PowerCycles)" }
        foreach ($p in @(
            @{ L = 'Reallocated sectors';   V = $s.ReallocatedSectors },
            @{ L = 'Pending sectors';       V = $s.PendingSectors },
            @{ L = 'Offline uncorrectable'; V = $s.OfflineUncorrectable },
            @{ L = 'Media errors';          V = $s.MediaErrors },
            @{ L = 'Endurance used %';      V = $s.PercentageUsed })) {
            if ($null -ne $p.V) { $md += "- $($p.L): $($p.V)" }
        }
    } else { $md += "SMART was unavailable: $($s.Error)" }
    $md += ''
    $md += '## Kernel evidence'
    $md += ''
    if (-not $k.Available) {
        $md += "The kernel log could not be read: $($k.Error)"
    } elseif (@($k.Matches).Count) {
        $md += "$(@($k.Matches).Count) decisive kernel error(s) referencing ``$($disk.Name)`` in the last $($k.Hours) hours:"
        $md += ''
        $md += '```'
        $md += @($k.Matches | Select-Object -First 60)
        $md += '```'
    } else {
        $md += "No I/O errors referencing ``$($disk.Name)`` in the last $($k.Hours) hours."
    }
    $md += ''
    $md += '## Files in this bundle'
    $md += ''
    $md += '| File | Contents |'
    $md += '|---|---|'
    $md += '| `report.md` | this summary |'
    $md += '| `smart.txt` | full `smartctl -x` output |'
    $md += '| `kernel.txt` | every kernel line referencing this device |'
    $md += '| `identity.json` | the structured device record |'

    $files = @{
        'report.md'     = ($md -join "`n") + "`n"
        'smart.txt'     = ((@($Evidence.SmartReport)) -join "`n") + "`n"
        'kernel.txt'    = ((@($k.Lines)) -join "`n") + "`n"
        'identity.json' = (($disk | ConvertTo-Json -Depth 6) + "`n")
    }
    foreach ($name in $files.Keys) {
        try { [IO.File]::WriteAllText((Join-Path $dir $name), $files[$name]) }
        catch { Write-Host "   could not write $name : $($_.Exception.Message)" -ForegroundColor DarkGray }
    }

    # A single attachable artefact. tar is present on every Proxmox host; if it is not,
    # the folder is still complete and is reported as such rather than silently skipped.
    $tar = Join-Path $dir 'evidence.tar.gz'
    $tarOk = $false
    if (Get-Command tar -CommandType Application -ErrorAction SilentlyContinue) {
        & tar '-czf' $tar '-C' $dir 'report.md' 'smart.txt' 'kernel.txt' 'identity.json' 2>$null
        $tarOk = ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $tar))
    }

    Write-Host ''
    Write-Host '  📦 Evidence bundle written' -ForegroundColor Green
    Write-Host "     $dir" -ForegroundColor White
    foreach ($n in @('report.md', 'smart.txt', 'kernel.txt', 'identity.json')) {
        Write-Host "       $n" -ForegroundColor DarkGray
    }
    if ($tarOk) { Write-Host "       evidence.tar.gz   ← attach this to a refund claim" -ForegroundColor DarkGray }
    else        { Write-Host '       (tar unavailable — the folder above is complete)' -ForegroundColor DarkGray }
    Write-Host ''
    Write-Host "     Copy it to your computer:  scp -r root@<host>:$dir ." -ForegroundColor DarkGray
    Write-Host ''
}

function Show-PmxHelp {
    Write-Host ''
    Write-Host '⚡ pmx — PowerFlow for Proxmox VE' -ForegroundColor Cyan
    Write-Host '  pmx                              node dashboard' -ForegroundColor White
    Write-Host '  pmx disks                        physical disk inventory' -ForegroundColor White
    Write-Host '  pmx disk [device|serial]         disk + compact SMART summary (picker if omitted)' -ForegroundColor White
    Write-Host '  pmx disk <device> -Full          full smartctl report' -ForegroundColor White
    Write-Host '  pmx disk <device> test short     launch a SMART self-test (short|long)' -ForegroundColor White
    Write-Host '  pmx disk <device> report         authenticity signals, SMART and kernel errors' -ForegroundColor White
    Write-Host '  pmx disk <device> report -Write  ...and write an evidence bundle for a refund claim' -ForegroundColor White
    Write-Host '  pmx disk <device> capacity-test  explain the destructive F3 gate; writes nothing' -ForegroundColor White
    Write-Host '  pmx pools                        Proxmox storage and ZFS pools' -ForegroundColor White
    Write-Host '  pmx guests                       VMs and containers together' -ForegroundColor White
    Write-Host '  pmx guest <id|name>              one guest in detail' -ForegroundColor White
    Write-Host '  pmx updates                      cached pending updates (read-only)' -ForegroundColor White
    Write-Host ''
}

<#
.SYNOPSIS
    Modern, compact Proxmox VE operations.
.DESCRIPTION
    Readable node, disk, pool, guest, update, and SMART views built from structured
    Proxmox/Linux data. Destructive capacity testing is isolated behind -Destroy,
    fail-closed device-use checks, and an exact typed "DESTROY <by-id>" confirmation
    naming the specific device — not its serial, which names a product, not a disk.
#>
function pmx {
    param(
        [Parameter(Position = 0)][string]$Command,
        [Parameter(Position = 1)][string]$Target,
        [Parameter(Position = 2)][string]$Action,
        [Parameter(Position = 3)][string]$Option,
        [switch]$Full,
        [switch]$Write,
        [switch]$Destroy,
        # A real switch, because the '-h' case in the routing table below can only ever be
        # reached as a QUOTED string: bare `pmx -h` is parameter binding, and PowerShell
        # fails it before the function body runs. Declaring it makes the obvious spelling work.
        [switch]$h
    )
    # Help must work EVERYWHERE. Gating it behind the Proxmox check meant `pmx help` on a
    # Windows workstation answered "this only runs on a Proxmox host" — refusing to explain
    # itself is the one thing a help command must never do, and it is exactly where someone
    # planning work from their desk would ask.
    if ($h -or $Command -in @('help', '-h', '--help', '/?')) { Show-PmxHelp; return }
    if (-not (Test-PmxReady)) { return }

    switch ($Command.ToLower()) {
        ''        { Show-PmxDashboard }
        'help'    { Show-PmxHelp }
        '-h'      { Show-PmxHelp }
        '--help'  { Show-PmxHelp }
        'disks'   { Show-PmxDisks }
        'disk'    {
            $disk = Resolve-PmxDisk -Selector $Target -Interactive
            if (-not $disk) { if (-not $Target) { Show-PmxDisks }; return }
            switch ($Action.ToLower()) {
                ''              { Show-PmxDisk -Disk $disk -Full:$Full }
                'smart'         { Show-PmxDisk -Disk $disk -Full:$Full }
                'test'          { Invoke-PmxSmartTest -Disk $disk -Kind $Option }
                'report'        { Show-PmxEvidence -Disk $disk -Write:$Write }
                'evidence'      { Show-PmxEvidence -Disk $disk -Write:$Write }
                'capacity-test' { Invoke-PmxCapacityTest -Disk $disk -Destroy:$Destroy }
                default         { Write-Host "❌ Unknown disk action '$Action'. Run: pmx help" -ForegroundColor Red }
            }
        }
        'pools'   { Show-PmxPools }
        'storage' { Show-PmxPools }
        'guests'  { Show-PmxGuests }
        'guest'   { if ($Target) { Show-PmxGuests -Selector $Target } else { Show-PmxGuests } }
        'updates' { Show-PmxUpdates }
        default   { Write-Host "❌ Unknown pmx command '$Command'. Run: pmx help" -ForegroundColor Red }
    }
}

Register-PFCommand -Name 'pmx' -Section '⚡ PROXMOX VE' -Platform 'Linux' -Synopsis 'compact Proxmox node, disk, pool, guest and SMART tools' -Example 'pmx · pmx disks · pmx disk sdg · pmx guests'

