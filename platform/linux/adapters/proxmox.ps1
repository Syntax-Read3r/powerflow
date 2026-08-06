# ==============================================================================
# PowerFlow — Proxmox Adapter (Linux)
# ==============================================================================
# Domain   : Platform / Linux
# File     : platform/linux/adapters/proxmox.ps1
# Purpose  : Structured Proxmox VE, disk, SMART, and destructive-test operations
# Functions: Test-ProxmoxSupport, Get-ProxmoxNodeSummary, Get-ProxmoxDisks,
#            Get-ProxmoxStorage, Get-ProxmoxZfsPools, Get-ProxmoxGuests,
#            Get-ProxmoxUpdates, Get-ProxmoxSmartInfo, Get-ProxmoxSmartReport,
#            Start-ProxmoxSmartTest, Get-ProxmoxDiskSafety,
#            Invoke-ProxmoxCapacityProbe
# Depends  : Test-Admin (platform/linux/adapters/elevation.ps1)
# ==============================================================================

function Test-ProxmoxSupport {
    return ((Test-Path -LiteralPath '/etc/pve') -and [bool](Get-Command pvesh -ErrorAction SilentlyContinue))
}

function Get-PmxNodeName {
    $local = @(Invoke-PmxPveshJson -Arguments @('get', '/cluster/status')) |
        Where-Object { $_.type -eq 'node' -and ($_.local -eq 1 -or $_.local -eq $true) } |
        Select-Object -First 1
    if ($local -and $local.name) { return "$($local.name)" }

    $name = @(& hostname '-s' 2>$null) -join ''
    if (-not $name) { $name = @(& hostname 2>$null) -join '' }
    return $name.Trim()
}

function Invoke-PmxPveshJson {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $result = Invoke-PmxPveshRequest -Arguments $Arguments
    if (-not $result.Success) { return $null }
    return $result.Data
}

function Invoke-PmxPveshRequest {
    param([Parameter(Mandatory)][string[]]$Arguments)

    if (-not (Test-ProxmoxSupport)) {
        return [pscustomobject]@{ Success = $false; Data = $null; Error = 'not a Proxmox VE host' }
    }
    $raw = @(& pvesh @Arguments '--output-format' 'json' 2>$null)
    $code = $LASTEXITCODE
    if ($code -ne 0 -or -not $raw) {
        return [pscustomobject]@{ Success = $false; Data = $null; Error = "pvesh exited $code" }
    }
    try {
        $data = (($raw -join [Environment]::NewLine) | ConvertFrom-Json)
        return [pscustomobject]@{ Success = $true; Data = $data; Error = '' }
    } catch {
        return [pscustomobject]@{ Success = $false; Data = $null; Error = 'pvesh returned malformed JSON' }
    }
}

function ConvertTo-PmxInt64 {
    param($Value)
    $n = 0L
    if ($null -ne $Value -and [int64]::TryParse("$Value", [ref]$n)) { return $n }
    return 0L
}

function Get-ProxmoxNodeSummary {
    if (-not (Test-ProxmoxSupport)) { return $null }

    $node = Get-PmxNodeName
    $s = Invoke-PmxPveshJson -Arguments @('get', '/nodes/localhost/status')
    if (-not $s) { return $null }

    $cluster = @(Invoke-PmxPveshJson -Arguments @('get', '/cluster/status')) |
        Where-Object { $_.type -eq 'cluster' } | Select-Object -First 1

    [pscustomobject]@{
        Node             = $node
        Version          = "$($s.pveversion)"
        Kernel           = "$($s.kversion)"
        UptimeSeconds    = ConvertTo-PmxInt64 $s.uptime
        CpuUsage         = if ($null -ne $s.cpu) { [double]$s.cpu } else { 0.0 }
        CpuCount         = if ($s.cpuinfo -and $s.cpuinfo.cpus) { [int]$s.cpuinfo.cpus } elseif ($s.maxcpu) { [int]$s.maxcpu } else { 0 }
        MemoryUsedBytes  = if ($s.memory) { ConvertTo-PmxInt64 $s.memory.used } else { 0L }
        MemoryTotalBytes = if ($s.memory) { ConvertTo-PmxInt64 $s.memory.total } else { 0L }
        RootUsedBytes    = if ($s.rootfs) { ConvertTo-PmxInt64 $s.rootfs.used } else { 0L }
        RootTotalBytes   = if ($s.rootfs) { ConvertTo-PmxInt64 $s.rootfs.total } else { 0L }
        LoadAverage      = @($s.loadavg)
        Cluster          = if ($cluster) { "$($cluster.name)" } else { '' }
        Quorate          = if ($cluster -and $null -ne $cluster.quorate) { [bool]$cluster.quorate } else { $null }
    }
}

function Invoke-PmxLsblkJson {
    if (-not (Get-Command lsblk -ErrorAction SilentlyContinue)) { return $null }

    $columns = 'NAME,KNAME,PATH,TYPE,SIZE,MODEL,SERIAL,WWN,TRAN,ROTA,RO,FSTYPE,MOUNTPOINTS,PKNAME,MAJ:MIN'
    $raw = @(& lsblk '--json' '--bytes' '--paths' '--output' $columns 2>$null)
    if (-not $raw -or $LASTEXITCODE -ne 0) {
        $columns = 'NAME,KNAME,PATH,TYPE,SIZE,MODEL,SERIAL,WWN,TRAN,ROTA,RO,FSTYPE,MOUNTPOINT,PKNAME,MAJ:MIN'
        $raw = @(& lsblk '--json' '--bytes' '--paths' '--output' $columns 2>$null)
    }
    if (-not $raw) { return $null }
    try { return (($raw -join "`n") | ConvertFrom-Json) } catch { return $null }
}

function Get-PmxBlockDescendants {
    param($Block)
    # lsblk OMITS "children" entirely for anything with no children — every leaf partition,
    # and every unpartitioned disk. Property access then yields $null, and @($null) is a
    # ONE-element array holding $null, not an empty one. Without the null filter the foreach
    # runs once per leaf with $child = $null and recurses on $null forever, ending in
    # "The script failed due to call depth overflow" — which killed Get-ProxmoxDisks, and so
    # every pmx command that touches a disk, on any real host.
    foreach ($child in @($Block.children | Where-Object { $null -ne $_ })) {
        $child
        Get-PmxBlockDescendants $child
    }
}

function Get-PmxBlockMajorMinor {
    param($Block)

    if ($null -eq $Block) { return '' }
    $property = $Block.PSObject.Properties['maj:min']
    if ($null -eq $property -or $null -eq $property.Value) { return '' }
    return "$($property.Value)".Trim()
}

function Get-PmxCanonicalPath {
    param([string]$Path)
    if (-not $Path) { return '' }
    $resolved = @(& readlink '-f' '--' $Path 2>$null) -join ''
    if ($resolved) { return $resolved.Trim() }
    return $Path
}

function Get-PmxStableIds {
    param([string]$DevicePath)

    if (-not (Test-Path -LiteralPath '/dev/disk/by-id')) { return @() }
    $canonical = Get-PmxCanonicalPath $DevicePath
    # NOT $matches — that is an automatic variable, and the -match on the next line rewrites it
    # into a Hashtable of capture groups. `$hashtable += $string` then throws "A hash table can
    # only be added to another hash table", which aborts Get-ProxmoxDisks and every pmx command
    # with it. It fires on any host where a *-partN link sorts before a whole-disk link — i.e.
    # every Proxmox host, since the boot disk is partitioned.
    $found = @()
    foreach ($link in @(Get-ChildItem -LiteralPath '/dev/disk/by-id' -Force -ErrorAction SilentlyContinue)) {
        if ($link.Name -match '-part\d+$') { continue }
        if ((Get-PmxCanonicalPath $link.FullName) -eq $canonical) { $found += $link.FullName }
    }

    return @($found | Sort-Object `
        @{ Expression = {
            $leaf = [IO.Path]::GetFileName($_)
            if ($leaf -match '^wwn-') { 0 }
            elseif ($leaf -match '^nvme-eui') { 1 }
            elseif ($leaf -match '^nvme-') { 2 }
            elseif ($leaf -match '^ata-') { 3 }
            elseif ($leaf -match '^scsi-') { 4 }
            elseif ($leaf -match '^usb-') { 5 }
            else { 9 }
        } }, @{ Expression = { $_ } })
}

function Get-PmxMountpoints {
    param($Block)
    $out = @()
    if ($Block.PSObject.Properties.Name -contains 'mountpoints') { $out += @($Block.mountpoints) }
    if ($Block.PSObject.Properties.Name -contains 'mountpoint') { $out += @($Block.mountpoint) }
    return @($out | Where-Object { $_ } | ForEach-Object { "$_" } | Sort-Object -Unique)
}

function Get-ProxmoxDisks {
    $tree = Invoke-PmxLsblkJson
    if (-not $tree) { return @() }
    $pveRequest = Invoke-PmxPveshRequest -Arguments @('get', '/nodes/localhost/disks/list', '--include-partitions', '1', '--skipsmart', '1')
    $pveRows = @($pveRequest.Data)
    $pveVerified = $pveRequest.Success

    $out = @()
    foreach ($disk in @($tree.blockdevices)) {
        if ("$($disk.type)" -ne 'disk') { continue }

        $name = [IO.Path]::GetFileName("$($disk.kname)")
        if (-not $name) { $name = [IO.Path]::GetFileName("$($disk.name)") }
        # zvols, loop devices, optical drives, RAM disks and device-mapper nodes are not
        # physical media. `lsblk` labels zvols as TYPE=disk, so TYPE alone is insufficient.
        if ($name -match '^(zd\d+|loop\d+|ram\d+|sr\d+|fd\d+|dm-\d+)$') { continue }

        $path = if ($disk.path) { "$($disk.path)" } elseif ($disk.name) { "$($disk.name)" } else { "/dev/$name" }
        $canonicalPath = Get-PmxCanonicalPath $path
        $pve = @($pveRows | Where-Object { $_.devpath -and (Get-PmxCanonicalPath "$($_.devpath)") -eq $canonicalPath }) |
            Select-Object -First 1
        # When the Proxmox disk API answered, it is authoritative about what constitutes
        # host physical media. It deliberately excludes zvol, loop, optical and iSCSI rows.
        if ($pveVerified -and -not $pve) { continue }
        $children = @(Get-PmxBlockDescendants $disk)
        # Preserve every child identity, not only partitions. A disk can have mapped,
        # encrypted, LVM or other nested descendants whose mount namespace or open handles
        # must be checked before any destructive operation is considered.
        $descendants = @($children | ForEach-Object {
            $childName = [IO.Path]::GetFileName("$($_.kname)")
            if (-not $childName) { $childName = [IO.Path]::GetFileName("$($_.name)") }
            $childPath = if ($_.path) {
                "$($_.path)"
            } elseif ("$($_.name)" -like '/*') {
                "$($_.name)"
            } elseif ($childName) {
                "/dev/$childName"
            } else {
                ''
            }
            [pscustomobject]@{
                Name        = $childName
                Path        = if ($childPath) { Get-PmxCanonicalPath $childPath } else { '' }
                Type        = "$($_.type)"
                MajorMinor  = Get-PmxBlockMajorMinor $_
                SizeBytes   = ConvertTo-PmxInt64 $_.size
                FileSystem  = "$($_.fstype)"
                Mountpoints = @(Get-PmxMountpoints $_)
            }
        })
        $parts = @($descendants | Where-Object { $_.Type -eq 'part' })
        $mounts = @((Get-PmxMountpoints $disk) + @($children | ForEach-Object { Get-PmxMountpoints $_ }) |
            Where-Object { $_ } | Sort-Object -Unique)
        $holdersPath = "/sys/class/block/$name/holders"
        $holders = if (Test-Path -LiteralPath $holdersPath) {
            @(Get-ChildItem -LiteralPath $holdersPath -ErrorAction SilentlyContinue | ForEach-Object Name)
        } else { @() }
        $slavesPath = "/sys/class/block/$name/slaves"
        $slaves = if (Test-Path -LiteralPath $slavesPath) {
            @(Get-ChildItem -LiteralPath $slavesPath -ErrorAction SilentlyContinue | ForEach-Object Name)
        } else { @() }
        $ids = @(Get-PmxStableIds $path)
        if ($pve -and $pve.by_id_link -and "$($pve.by_id_link)" -notmatch '-part\d+$' -and
            (Test-Path -LiteralPath "$($pve.by_id_link)")) {
            $ids = @("$($pve.by_id_link)") + @($ids | Where-Object { $_ -ne "$($pve.by_id_link)" })
        }
        $majorMinor = Get-PmxBlockMajorMinor $disk
        if (-not $majorMinor) {
            # Retain compatibility with an older lsblk JSON response while making the
            # resulting safety object fail closed if neither source yields an identity.
            $majorMinor = (@(& lsblk '-dn' '-o' 'MAJ:MIN' $path 2>$null) -join '').Trim()
        }
        $diskSeqPath = "/sys/class/block/$name/diskseq"
        $diskSeq = if (Test-Path -LiteralPath $diskSeqPath) { (Get-Content -LiteralPath $diskSeqPath -Raw -ErrorAction SilentlyContinue).Trim() } else { '' }
        $pveSerial = if ($pve -and "$($pve.serial)" -and "$($pve.serial)" -ne 'unknown') { "$($pve.serial)" } else { '' }
        $pveWwn = if ($pve -and "$($pve.wwn)" -and "$($pve.wwn)" -ne 'unknown') { "$($pve.wwn)" } else { '' }
        $model = if ($pve -and $pve.model) { "$($pve.model)" } else { "$($disk.model)" }
        $serial = if ($pveSerial) { $pveSerial } else { "$($disk.serial)" }

        $out += [pscustomobject]@{
            Name        = $name
            Path        = $canonicalPath
            SizeBytes   = if ($pve -and $pve.size) { ConvertTo-PmxInt64 $pve.size } else { ConvertTo-PmxInt64 $disk.size }
            Model       = ($model -replace '\s+', ' ').Trim()
            Serial      = ($serial -replace '\s+', ' ').Trim()
            Wwn         = if ($pveWwn) { $pveWwn } else { "$($disk.wwn)" }
            Transport   = "$($disk.tran)"
            Rotational  = if ($pve -and $pve.type) { "$($pve.type)" -eq 'hdd' } else { ("$($disk.rota)" -eq '1' -or $disk.rota -eq $true) }
            ReadOnly    = ("$($disk.ro)" -eq '1' -or $disk.ro -eq $true)
            FileSystem  = "$($disk.fstype)"
            StableId    = if ($ids.Count) { $ids[0] } else { '' }
            StableIds   = @($ids)
            MajorMinor  = $majorMinor
            DiskSeq     = $diskSeq
            Descendants = @($descendants)
            Partitions  = @($parts)
            Mountpoints = @($mounts)
            Holders     = @($holders)
            Slaves      = @($slaves)
            ProxmoxVerified = $pveVerified
            ProxmoxUse  = if ($pve -and $pve.used) { "$($pve.used)" } else { '' }
            ProxmoxMounted = if ($pve) { ($pve.mounted -eq 1 -or $pve.mounted -eq $true) } else { $false }
            CephOsdIds  = if ($pve -and $pve.'osdid-list') { @($pve.'osdid-list') } elseif ($pve -and $null -ne $pve.osdid) { @($pve.osdid) } else { @() }
            # NO Health/Wearout here. The list request above passes --skipsmart 1, so
            # PVE::Diskmanage::get_disks never runs smartctl and returns the literals
            # 'UNKNOWN' and 'N/A' for every disk, always. Nothing rendered them — but
            # Write-PmxEvidenceBundle serialises this whole object into identity.json, so
            # a refund bundle would have asserted "Health":"UNKNOWN" beside a smart.txt
            # reporting PASSED. Real health comes from Get-ProxmoxSmartInfo.
        }
    }
    return @($out | Sort-Object Name)
}

function Get-ProxmoxStorage {
    if (-not (Test-ProxmoxSupport)) { return @() }
    # 'localhost' is a pvesh alias for the node this shell runs on — correct on a single
    # node and on any cluster member for its own resources. No node-name lookup needed.
    $rows = @(Invoke-PmxPveshJson -Arguments @('get', '/nodes/localhost/storage'))
    return @($rows | ForEach-Object {
        [pscustomobject]@{
            Name       = "$($_.storage)"
            Type       = "$($_.type)"
            Active     = ($_.active -eq 1 -or $_.active -eq $true)
            Enabled    = (-not ($_.enabled -eq 0 -or $_.enabled -eq $false))
            Shared     = ($_.shared -eq 1 -or $_.shared -eq $true)
            UsedBytes  = ConvertTo-PmxInt64 $_.used
            TotalBytes = ConvertTo-PmxInt64 $_.total
            FreeBytes  = ConvertTo-PmxInt64 $_.avail
            Content    = "$($_.content)"
        }
    } | Sort-Object Name)
}

function Get-ProxmoxZfsPools {
    if (Test-ProxmoxSupport) {
        $api = Invoke-PmxPveshJson -Arguments @('get', '/nodes/localhost/disks/zfs')
        if ($null -ne $api) {
            return @(@($api) | ForEach-Object {
                $size = ConvertTo-PmxInt64 $_.size
                $alloc = ConvertTo-PmxInt64 $_.alloc
                [pscustomobject]@{
                    Name           = "$($_.name)"
                    Health         = "$($_.health)"
                    SizeBytes      = $size
                    AllocatedBytes = $alloc
                    FreeBytes      = if ($null -ne $_.free) { ConvertTo-PmxInt64 $_.free } else { [math]::Max(0, $size - $alloc) }
                    Fragmentation  = if ($null -ne $_.frag) { "$($_.frag)%" } else { 'unknown' }
                    Capacity       = if ($size -gt 0) { '{0:N0}%' -f (($alloc / $size) * 100) } else { 'unknown' }
                }
            })
        }
    }
    if (-not (Get-Command zpool -CommandType Application -ErrorAction SilentlyContinue)) { return @() }
    $rows = @(& zpool 'list' '-Hp' '-o' 'name,health,size,alloc,free,fragmentation,capacity' 2>$null)
    if ($LASTEXITCODE -ne 0) { return @() }
    return @($rows | ForEach-Object {
        $p = "$_" -split "\t"
        if ($p.Count -lt 7) { $p = "$_" -split '\s+' }
        if ($p.Count -ge 7) {
            [pscustomobject]@{
                Name          = $p[0]
                Health        = $p[1]
                SizeBytes     = ConvertTo-PmxInt64 $p[2]
                AllocatedBytes= ConvertTo-PmxInt64 $p[3]
                FreeBytes     = ConvertTo-PmxInt64 $p[4]
                Fragmentation = $p[5]
                Capacity      = $p[6]
            }
        }
    })
}

function Get-ProxmoxGuests {
    if (-not (Test-ProxmoxSupport)) { return @() }
    $rows = @(Invoke-PmxPveshJson -Arguments @('get', '/cluster/resources', '--type', 'vm'))
    return @($rows | ForEach-Object {
        [pscustomobject]@{
            Id          = [int]$_.vmid
            Kind        = if ("$($_.type)" -eq 'qemu') { 'VM' } else { 'CT' }
            Name        = "$($_.name)"
            Node        = "$($_.node)"
            Status      = "$($_.status)"
            CpuUsage    = if ($null -ne $_.cpu) { [double]$_.cpu } else { 0.0 }
            CpuCount    = if ($_.maxcpu) { [int]$_.maxcpu } else { 0 }
            MemoryBytes = ConvertTo-PmxInt64 $_.mem
            MaxMemory   = ConvertTo-PmxInt64 $_.maxmem
            DiskBytes   = ConvertTo-PmxInt64 $_.disk
            MaxDisk     = ConvertTo-PmxInt64 $_.maxdisk
            Uptime      = ConvertTo-PmxInt64 $_.uptime
        }
    } | Sort-Object Id)
}

function Get-ProxmoxUpdates {
    if (-not (Test-ProxmoxSupport)) { return @() }
    # 'localhost' is a pvesh alias for the node this shell runs on — no node-name lookup
    # needed. (An earlier version assigned one and never used it: a wasted pvesh call.)
    $rows = @(Invoke-PmxPveshJson -Arguments @('get', '/nodes/localhost/apt/update'))
    return @($rows | ForEach-Object {
        [pscustomobject]@{
            Package    = "$($_.Package)"
            Current    = "$($_.OldVersion)"
            Available  = "$($_.Version)"
            Origin     = "$($_.Origin)"
            Priority   = "$($_.Priority)"
            Description= "$($_.Title)"
        }
    } | Sort-Object Package)
}

function Get-PmxAtaAttributeRaw {
    param($Smart, [string[]]$Names, [int[]]$Ids)
    foreach ($row in @($Smart.ata_smart_attributes.table)) {
        if (("$($row.name)" -in $Names) -or ([int]$row.id -in $Ids)) {
            if ($row.raw -and $null -ne $row.raw.value) { return ConvertTo-PmxInt64 $row.raw.value }
        }
    }
    return $null
}

function Get-ProxmoxSmartInfo {
    param([Parameter(Mandatory)][string]$DevicePath)

    if (-not (Get-Command smartctl -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ Available = $false; Error = 'smartctl is not installed.' }
    }

    $raw = @(& smartctl '-j' '-x' $DevicePath 2>$null)
    $nativeCode = $LASTEXITCODE
    if (-not $raw) { return [pscustomobject]@{ Available = $false; Error = "smartctl returned no data for $DevicePath." } }
    try { $s = ($raw -join [Environment]::NewLine) | ConvertFrom-Json }
    catch { return [pscustomobject]@{ Available = $false; Error = "Could not parse SMART data for $DevicePath." } }
    $smartCode = if ($s.smartctl -and $null -ne $s.smartctl.exit_status) { [int]$s.smartctl.exit_status } else { $nativeCode }
    if (($smartCode -band 3) -ne 0) {
        return [pscustomobject]@{ Available = $false; Error = "smartctl could not open or inspect $DevicePath (exit $smartCode)." }
    }

    $passed = $null
    if ($s.smart_status -and $null -ne $s.smart_status.passed) { $passed = [bool]$s.smart_status.passed }
    $temperature = $null
    if ($s.temperature -and $null -ne $s.temperature.current) { $temperature = [int]$s.temperature.current }
    elseif ($s.nvme_smart_health_information_log -and $null -ne $s.nvme_smart_health_information_log.temperature) {
        $temperature = [int]$s.nvme_smart_health_information_log.temperature
    }

    $hours = $null
    if ($s.power_on_time -and $null -ne $s.power_on_time.hours) { $hours = ConvertTo-PmxInt64 $s.power_on_time.hours }
    elseif ($s.nvme_smart_health_information_log) { $hours = ConvertTo-PmxInt64 $s.nvme_smart_health_information_log.power_on_hours }
    $cycles = $null
    if ($null -ne $s.power_cycle_count) { $cycles = ConvertTo-PmxInt64 $s.power_cycle_count }
    elseif ($s.nvme_smart_health_information_log) { $cycles = ConvertTo-PmxInt64 $s.nvme_smart_health_information_log.power_cycles }

    $shortMinutes = $null; $longMinutes = $null; $selfTest = ''
    if ($s.ata_smart_data -and $s.ata_smart_data.self_test) {
        $selfTest = "$($s.ata_smart_data.self_test.status.string)"
        if ($s.ata_smart_data.self_test.polling_minutes) {
            $shortMinutes = $s.ata_smart_data.self_test.polling_minutes.short
            $longMinutes = $s.ata_smart_data.self_test.polling_minutes.extended
        }
    }

    [pscustomobject]@{
        Available             = $true
        Error                 = ''
        Model                 = "$($s.model_name)"
        Serial                = "$($s.serial_number)"
        Firmware              = "$($s.firmware_version)"
        Protocol              = "$($s.device.protocol)"
        CapacityBytes         = if ($s.user_capacity) { ConvertTo-PmxInt64 $s.user_capacity.bytes } else { 0L }
        OverallPassed         = $passed
        TemperatureC          = $temperature
        PowerOnHours          = $hours
        PowerCycles           = $cycles
        ReallocatedSectors    = Get-PmxAtaAttributeRaw $s @('Reallocated_Sector_Ct') @(5)
        PendingSectors        = Get-PmxAtaAttributeRaw $s @('Current_Pending_Sector') @(197)
        OfflineUncorrectable  = Get-PmxAtaAttributeRaw $s @('Offline_Uncorrectable') @(198)
        CrcErrors             = Get-PmxAtaAttributeRaw $s @('UDMA_CRC_Error_Count') @(199)
        PercentageUsed        = if ($s.nvme_smart_health_information_log -and $null -ne $s.nvme_smart_health_information_log.percentage_used) { [int]$s.nvme_smart_health_information_log.percentage_used } else { $null }
        MediaErrors           = if ($s.nvme_smart_health_information_log -and $null -ne $s.nvme_smart_health_information_log.media_errors) { ConvertTo-PmxInt64 $s.nvme_smart_health_information_log.media_errors } else { $null }
        SelfTestStatus        = $selfTest
        ShortTestMinutes      = $shortMinutes
        LongTestMinutes       = $longMinutes
    }
}

function Get-ProxmoxSmartReport {
    param([Parameter(Mandatory)][string]$DevicePath)
    if (-not (Get-Command smartctl -ErrorAction SilentlyContinue)) { return @('smartctl is not installed.') }
    return @(& smartctl '-x' $DevicePath 2>&1)
}

function Start-ProxmoxSmartTest {
    param(
        [Parameter(Mandatory)][string]$DevicePath,
        [Parameter(Mandatory)][ValidateSet('short', 'long')][string]$Kind
    )
    if (-not (Get-Command smartctl -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ Success = $false; Message = 'smartctl is not installed.'; Output = @() }
    }
    $output = @(& smartctl '-t' $Kind $DevicePath 2>&1)
    $code = $LASTEXITCODE
    return [pscustomobject]@{
        Success = (($code -band 7) -eq 0)
        Message = if (($code -band 7) -eq 0) { "SMART $Kind test started." } else { "smartctl could not start the $Kind test (exit $code)." }
        Output  = @($output)
    }
}

# ── authenticity flags ────────────────────────────────────────────────────────
# Every one of these is drawn from a REAL counterfeit that reached this owner's server and
# is documented in docs/proxmox.md: model literally "SSD 4TB", serial "003134", an all-zero
# WWN, ~18 MB/s sustained writes, and a drive that dropped off the bus twice.
#
# These are SIGNALS, never a verdict. The report says what was observed and what it
# suggests; it never prints "this is fake". That distinction is the difference between
# evidence a seller must answer and an accusation they can dismiss — and it is exactly the
# line the original session drew ("we cannot prove the NAND capacity is specifically fake").
function Get-PmxAuthenticityFlags {
    param([Parameter(Mandatory)]$Disk, $Smart)

    $flags = @()
    $add = { param($Id, $Severity, $Detail) $script:__pmxFlagSink += [pscustomobject]@{ Id = $Id; Severity = $Severity; Detail = $Detail } }
    $script:__pmxFlagSink = @()

    # A genuine drive carries a real IEEE WWN. Counterfeit controllers frequently report
    # zeros or nothing at all.
    $wwn = "$($Disk.Wwn)".Trim()
    if (-not $wwn) {
        & $add 'zero-wwn' 'high' 'the drive reports no WWN at all'
    } elseif ($wwn -match '^0[x]?0*$' -or ($wwn -replace '[^0-9a-fA-F]', '') -match '^0+$') {
        & $add 'zero-wwn' 'high' "the WWN is all zeros ('$wwn')"
    }

    # Real vendors name their products. "SSD 4TB" is a capacity, not a model.
    $model = "$($Disk.Model)".Trim()
    if (-not $model) {
        & $add 'generic-model' 'high' 'the drive reports no model name'
    } elseif ($model -match '^(SSD|HDD|DISK|General|Generic)[\s_-]*\d+\s*(GB|TB|MB)$' -or
              $model -match '^\d+\s*(GB|TB)\s*(SSD|HDD)$') {
        & $add 'generic-model' 'high' "the model name is a capacity, not a product: '$model'"
    }

    # Vendor serials are long and mixed. Six digits is a counter, not a serial.
    $serial = "$($Disk.Serial)".Trim()
    if (-not $serial) {
        & $add 'no-serial' 'high' 'the drive reports no serial number'
    } elseif ($serial.Length -lt 8) {
        & $add 'short-serial' 'medium' "the serial is only $($serial.Length) characters ('$serial')"
    } elseif ($serial -match '^\d+$') {
        & $add 'numeric-serial' 'low' "the serial is all digits ('$serial')"
    }

    # A SATA/SAS device with no SMART at all is abnormal; fake controllers often omit it.
    if ($Smart -and -not $Smart.Available -and "$($Disk.Transport)" -notmatch 'usb') {
        & $add 'no-smart' 'medium' "SMART is unavailable on a $($Disk.Transport) device: $($Smart.Error)"
    }

    # SMART's own capacity disagreeing with the block layer is the classic fake-capacity tell.
    if ($Smart -and $Smart.Available -and $Smart.CapacityBytes -gt 0 -and $Disk.SizeBytes -gt 0) {
        $delta = [math]::Abs($Smart.CapacityBytes - $Disk.SizeBytes)
        if ($delta -gt 1GB) {
            & $add 'size-mismatch' 'high' "SMART reports $($Smart.CapacityBytes) bytes, the kernel reports $($Disk.SizeBytes)"
        }
    }

    # Health/wear signals that a reseller cannot argue with.
    if ($Smart -and $Smart.Available) {
        if ($Smart.OverallPassed -eq $false) { & $add 'smart-failed' 'high' 'SMART overall-health assessment is FAILED' }
        foreach ($pair in @(
            @{ N = 'ReallocatedSectors';   F = 'reallocated-sectors' },
            @{ N = 'PendingSectors';       F = 'pending-sectors' },
            @{ N = 'OfflineUncorrectable'; F = 'uncorrectable-sectors' },
            @{ N = 'MediaErrors';          F = 'media-errors' })) {
            $v = $Smart.($pair.N)
            if ($null -ne $v -and $v -gt 0) { & $add $pair.F 'high' "$($pair.N) = $v" }
        }
    }

    $flags = @($script:__pmxFlagSink)
    Remove-Variable -Name __pmxFlagSink -Scope Script -ErrorAction SilentlyContinue
    return @($flags)
}

# Kernel messages that decided the real case. Matching the exact strings the owner grepped
# by hand keeps the evidence bundle comparable to what they already sent a seller.
$script:PF_PmxKernelPatterns = @(
    'DID_BAD_TARGET', 'device offline', 'I/O error', 'Synchronize Cache.*failed',
    'aborted journal', 'Remounting filesystem read-only', 'failed command', 'medium error',
    'Unaligned partial completion', 'rejecting I/O to offline device'
)

function Get-PmxKernelErrors {
    param([Parameter(Mandatory)][string]$DeviceName, [int]$Hours = 24)

    if (-not (Get-Command journalctl -CommandType Application -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ Available = $false; Error = 'journalctl is not available'; Lines = @(); Matches = @() }
    }
    $raw = @(& journalctl '-k' '--since' "-${Hours}h" '--no-pager' 2>$null)
    if ($LASTEXITCODE -ne 0) {
        return [pscustomobject]@{ Available = $false; Error = "journalctl exited $LASTEXITCODE (root may be required)"; Lines = @(); Matches = @() }
    }
    # Device-scoped first, so an unrelated disk's errors never end up in this bundle.
    $mine = @($raw | Where-Object { $_ -match [regex]::Escape($DeviceName) })
    $pattern = ($script:PF_PmxKernelPatterns -join '|')
    $decisive = @($mine | Where-Object { $_ -match $pattern })
    return [pscustomobject]@{
        Available = $true
        Error     = ''
        Lines     = @($mine)
        Matches   = @($decisive)
        Hours     = $Hours
    }
}

<#
.SYNOPSIS
    Everything needed to judge — or dispute — a disk, gathered in one non-destructive pass.
.DESCRIPTION
    Reads identity, SMART, authenticity signals and device-scoped kernel errors. Writes
    nothing to the disk. This is the automation of the manual evidence-gathering in
    docs/proxmox.md, which took half an hour of copy-paste AFTER a drive had already
    corrupted a filesystem.
#>
function Get-ProxmoxDiskEvidence {
    param([Parameter(Mandatory)]$Disk, [int]$KernelHours = 24)

    $device = if ($Disk.StableId) { $Disk.StableId } else { $Disk.Path }
    $smart  = Get-ProxmoxSmartInfo -DevicePath $device
    $flags  = @(Get-PmxAuthenticityFlags -Disk $Disk -Smart $smart)
    $kernel = Get-PmxKernelErrors -DeviceName $Disk.Name -Hours $KernelHours

    [pscustomobject]@{
        Disk        = $Disk
        Smart       = $smart
        Flags       = $flags
        Kernel      = $kernel
        SmartReport = @(Get-ProxmoxSmartReport -DevicePath $device)
        CollectedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss') + ' UTC'
        Host        = (Get-PmxNodeName)
    }
}

function Get-PmxParentDiskPath {
    param([string]$DevicePath)
    $current = Get-PmxCanonicalPath $DevicePath
    for ($i = 0; $i -lt 8 -and $current; $i++) {
        $type = (@(& lsblk '-dn' '-o' 'TYPE' $current 2>$null) -join '').Trim()
        if ($type -eq 'disk') { return $current }
        $parent = (@(& lsblk '-dn' '-o' 'PKNAME' $current 2>$null) -join '').Trim()
        if (-not $parent) { return $current }
        $current = Get-PmxCanonicalPath "/dev/$parent"
    }
    return $current
}

function Add-PmxDiskUseReason {
    param([hashtable]$Map, [string]$DevicePath, [string]$Reason)
    if (-not $DevicePath -or -not $Reason) { return }
    $disk = Get-PmxParentDiskPath $DevicePath
    if (-not $Map.ContainsKey($disk)) { $Map[$disk] = @() }
    if ($Reason -notin $Map[$disk]) { $Map[$disk] += $Reason }
}

function Get-PmxActiveDiskUses {
    $uses = @{}
    $errors = @()

    $zfs = Invoke-PmxPveshRequest -Arguments @('get', '/nodes/localhost/disks/zfs')
    if (-not $zfs.Success) {
        $errors += 'could not verify ZFS membership through Proxmox'
    } else {
        foreach ($pool in @($zfs.Data)) {
            $detail = Invoke-PmxPveshRequest -Arguments @('get', "/nodes/localhost/disks/zfs/$($pool.name)")
            if (-not $detail.Success) {
                $errors += "could not inspect ZFS pool $($pool.name)"
                continue
            }
            $queue = [System.Collections.Queue]::new()
            $queue.Enqueue($detail.Data)
            while ($queue.Count -gt 0) {
                $node = $queue.Dequeue()
                if ($node -and "$($node.name)" -like '/dev/*') {
                    Add-PmxDiskUseReason $uses "$($node.name)" "ZFS member of $($pool.name)"
                }
                foreach ($child in @($node.children)) { if ($child) { $queue.Enqueue($child) } }
            }
        }
    }

    $pvsCommand = Get-Command pvs -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pvsCommand) {
        $pvsRows = @(& $pvsCommand.Source '--noheadings' '--separator' '|' '-o' 'pv_name,vg_name,pv_tags' 2>$null)
        $pvsCode = $LASTEXITCODE
        if ($pvsCode -ne 0) { $errors += "could not verify LVM membership (pvs exit $pvsCode)" }
        foreach ($line in $pvsRows) {
            $p = "$line" -split '\|'
            if ($p.Count -ge 2) {
                $pv = $p[0].Trim(); $vg = $p[1].Trim(); $tags = if ($p.Count -ge 3) { $p[2].Trim() } else { '' }
                $label = if ($tags -match 'ceph') { "Ceph LVM device ($vg)" } else { "LVM physical volume ($vg)" }
                Add-PmxDiskUseReason $uses $pv $label
            }
        }
    } else { $errors += 'could not verify LVM membership (pvs missing)' }

    $swaponCommand = Get-Command swapon -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($swaponCommand) {
        $swapRows = @(& $swaponCommand.Source '--show=NAME' '--noheadings' '--raw' 2>$null)
        $swapCode = $LASTEXITCODE
        if ($swapCode -ne 0) { $errors += "could not verify swap membership (swapon exit $swapCode)" }
        foreach ($swap in $swapRows) {
            Add-PmxDiskUseReason $uses "$swap" 'active swap'
        }
    } else { $errors += 'could not verify swap membership (swapon missing)' }

    if (Test-Path -LiteralPath '/var/lib/ceph/osd') {
        foreach ($osd in @(Get-ChildItem -LiteralPath '/var/lib/ceph/osd' -Directory -ErrorAction SilentlyContinue)) {
            foreach ($leaf in @('block', 'block.db', 'block.wal')) {
                $link = Join-Path $osd.FullName $leaf
                if (Test-Path -LiteralPath $link) { Add-PmxDiskUseReason $uses $link "Ceph OSD $($osd.Name)" }
            }
        }
    }
    return [pscustomobject]@{ Uses = $uses; Errors = @($errors) }
}

function Get-PmxSignatureCheck {
    param([string]$DevicePath)
    $wipefs = Get-Command wipefs -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $wipefs) {
        return [pscustomobject]@{ Success = $false; Reasons = @(); Error = 'wipefs is missing' }
    }
    $raw = @(& $wipefs.Source '--json' '--output' 'DEVICE,OFFSET,TYPE,UUID,LABEL' $DevicePath 2>$null)
    $code = $LASTEXITCODE
    if ($code -ne 0 -or -not $raw) {
        return [pscustomobject]@{ Success = $false; Reasons = @(); Error = "wipefs inspection failed (exit $code)" }
    }
    try { $data = ($raw -join [Environment]::NewLine) | ConvertFrom-Json }
    catch { return [pscustomobject]@{ Success = $false; Reasons = @(); Error = 'wipefs returned malformed JSON' } }
    $reasons = @($data.signatures | ForEach-Object {
        $kind = if ($_.type) { "$($_.type)" } else { 'unknown' }
        $offset = if ($_.offset) { " at $($_.offset)" } else { '' }
        "on-disk signature: $kind$offset"
    })
    return [pscustomobject]@{ Success = $true; Reasons = $reasons; Error = '' }
}

function Get-PmxConfigReferenceCheck {
    param($Disk)
    $references = @()
    $needles = @($Disk.Path) + @($Disk.StableIds) | Where-Object { $_ } | Sort-Object -Unique
    $files = @()
    try {
        foreach ($dir in @('/etc/pve/qemu-server', '/etc/pve/lxc')) {
            if (Test-Path -LiteralPath $dir) {
                $files += @(Get-ChildItem -LiteralPath $dir -File -Filter '*.conf' -ErrorAction Stop)
            }
        }
        if (-not (Test-Path -LiteralPath '/etc/pve/storage.cfg')) {
            return [pscustomobject]@{ Success = $false; References = @(); Error = 'Proxmox storage.cfg is missing' }
        }
        $files += Get-Item -LiteralPath '/etc/pve/storage.cfg' -ErrorAction Stop
        foreach ($file in $files) {
            $raw = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop
            foreach ($needle in $needles) {
                if ($raw.Contains($needle)) {
                    $references += "referenced by Proxmox config $($file.Name)"
                    break
                }
            }
        }
    } catch {
        return [pscustomobject]@{ Success = $false; References = @(); Error = 'could not inspect every Proxmox guest/storage config' }
    }
    return [pscustomobject]@{ Success = $true; References = @($references | Sort-Object -Unique); Error = '' }
}

function Get-PmxMountNamespaceCheck {
    param([string[]]$MajorMinor)

    $identities = @($MajorMinor | Where-Object { $_ } | Sort-Object -Unique)
    if (-not $identities.Count -or @($identities | Where-Object { $_ -notmatch '^\d+:\d+$' }).Count) {
        return [pscustomobject]@{ Success = $false; References = @(); Error = 'one or more block-device major:minor identities are unavailable or malformed' }
    }
    $references = @()
    if (-not (Test-Path -LiteralPath '/proc')) {
        return [pscustomobject]@{ Success = $false; References = @(); Error = '/proc is unavailable' }
    }
    foreach ($proc in @(Get-ChildItem -LiteralPath '/proc' -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d+$' })) {
        $mountInfo = Join-Path $proc.FullName 'mountinfo'
        foreach ($line in @(Get-Content -LiteralPath $mountInfo -ErrorAction SilentlyContinue)) {
            $fields = "$line" -split ' '
            if ($fields.Count -gt 2 -and $fields[2] -in $identities) {
                $references += "block device $($fields[2]) is mounted in process namespace PID $($proc.Name)"
            }
        }
    }
    return [pscustomobject]@{ Success = $true; References = @($references | Sort-Object -Unique); Error = '' }
}

function Get-PmxOpenHandleCheck {
    param([string[]]$DevicePath)

    $paths = @($DevicePath | Where-Object { $_ } | Sort-Object -Unique)
    if (-not $paths.Count -or @($paths | Where-Object { $_ -notlike '/dev/*' -or $_ -match '[\x00-\x1f\x7f]' }).Count) {
        return [pscustomobject]@{ Success = $false; InUse = $false; InUsePaths = @(); Error = 'one or more block-device paths are unavailable or malformed' }
    }
    $fuser = Get-Command fuser -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $fuser) {
        return [pscustomobject]@{ Success = $false; InUse = $false; InUsePaths = @(); Error = 'fuser is missing' }
    }

    $inUsePaths = @()
    foreach ($path in $paths) {
        & $fuser.Source '-s' $path 2>$null
        $code = $LASTEXITCODE
        if ($code -eq 0) { $inUsePaths += $path; continue }
        if ($code -ne 1) {
            return [pscustomobject]@{ Success = $false; InUse = $false; InUsePaths = @($inUsePaths); Error = "fuser could not verify open handles for $path (exit $code)" }
        }
    }
    return [pscustomobject]@{ Success = $true; InUse = [bool]$inUsePaths.Count; InUsePaths = @($inUsePaths); Error = '' }
}

function Get-ProxmoxDiskSafety {
    param([Parameter(Mandatory)][string]$StablePath)

    $canonical = Get-PmxCanonicalPath $StablePath
    $disk = @(Get-ProxmoxDisks | Where-Object {
        $_.Path -eq $canonical -or $StablePath -in @($_.StableIds)
    }) | Select-Object -First 1
    $reasons = @()

    if (-not $disk) { $reasons += 'device is not a current physical disk'; return [pscustomobject]@{ Safe = $false; Disk = $null; Reasons = $reasons } }
    $stableLeaf = [IO.Path]::GetFileName($StablePath)
    if ($StablePath -notlike '/dev/disk/by-id/*' -or $stableLeaf -match '-part\d+$') { $reasons += 'a whole-disk /dev/disk/by-id identity is required' }
    if ($stableLeaf -notmatch '^[A-Za-z0-9._:+-]+$') { $reasons += 'the stable device identity contains unsafe characters' }
    if ($disk.StableId -eq '') { $reasons += 'the disk has no stable by-id identity' }
    if (-not $disk.Serial) { $reasons += 'the disk has no serial number to use for typed confirmation' }
    if ($disk.Serial -match '[\x00-\x1f\x7f]') { $reasons += 'the disk serial contains unsafe control characters' }
    # Ordinal, matching the identity guards below: two byte-different serials are two
    # different disks. (Counterfeits genuinely do ship duplicate serials — which is the
    # case this refuses, and identical strings compare equal under either comparison.)
    if (@(Get-ProxmoxDisks | Where-Object { $_.Serial -and [string]::Equals("$($_.Serial)", "$($disk.Serial)", [StringComparison]::Ordinal) }).Count -ne 1) { $reasons += 'the disk serial is not unique on this host' }
    if ($disk.SizeBytes -le 0) { $reasons += 'the disk has no trustworthy positive size' }
    if ($disk.MajorMinor -notmatch '^\d+:\d+$') { $reasons += 'the disk major:minor identity is unavailable' }
    if ($disk.DiskSeq -notmatch '^\d+$') { $reasons += 'the kernel disk sequence identity is unavailable' }
    if (-not $disk.ProxmoxVerified) { $reasons += 'Proxmox did not verify this as host physical media' }
    if ($disk.ReadOnly) { $reasons += 'the kernel reports the disk read-only' }
    if ($disk.FileSystem) { $reasons += "whole-disk filesystem signature: $($disk.FileSystem)" }
    if (@($disk.Partitions).Count) { $reasons += "has $(@($disk.Partitions).Count) partition(s): $(@($disk.Partitions.Name) -join ', ')" }
    if (@($disk.Mountpoints).Count) { $reasons += "mounted at $(@($disk.Mountpoints) -join ', ')" }
    if (@($disk.Holders).Count) { $reasons += "has kernel holder(s): $(@($disk.Holders) -join ', ')" }
    if (@($disk.Slaves).Count) { $reasons += "is composed from slave device(s): $(@($disk.Slaves) -join ', ')" }
    if ($disk.ProxmoxMounted) { $reasons += 'Proxmox reports the disk mounted' }
    if ($disk.ProxmoxUse) { $reasons += "Proxmox reports the disk in use: $($disk.ProxmoxUse)" }
    if (@($disk.CephOsdIds).Count) { $reasons += "assigned to Ceph OSD(s): $(@($disk.CephOsdIds) -join ', ')" }

    $majorMinorIdentities = @()
    $devicePaths = @()
    if ($disk.MajorMinor -match '^\d+:\d+$') { $majorMinorIdentities += "$($disk.MajorMinor)" }
    if ($disk.Path -like '/dev/*' -and $disk.Path -notmatch '[\x00-\x1f\x7f]') { $devicePaths += "$($disk.Path)" }

    if ($disk.PSObject.Properties.Name -notcontains 'Descendants') {
        $reasons += 'descendant block-device identity inventory is unavailable'
    } else {
        foreach ($descendant in @($disk.Descendants)) {
            if ($null -eq $descendant) {
                $reasons += 'a descendant block-device identity is unavailable'
                continue
            }
            $label = if ($descendant.Path) { "$($descendant.Path)" } elseif ($descendant.Name) { "$($descendant.Name)" } else { '<unknown>' }
            if ($descendant.MajorMinor -notmatch '^\d+:\d+$') {
                $reasons += "descendant major:minor identity is unavailable or malformed: $label"
            } else {
                $majorMinorIdentities += "$($descendant.MajorMinor)"
            }
            if ($descendant.Path -notlike '/dev/*' -or "$($descendant.Path)" -match '[\x00-\x1f\x7f]') {
                $reasons += "descendant device path is unavailable or malformed: $label"
            } else {
                $devicePaths += "$($descendant.Path)"
            }
        }
    }
    $majorMinorIdentities = @($majorMinorIdentities | Sort-Object -Unique)
    $devicePaths = @($devicePaths | Sort-Object -Unique)

    $active = Get-PmxActiveDiskUses
    $reasons += @($active.Errors)
    if ($active.Uses.ContainsKey($disk.Path)) { $reasons += @($active.Uses[$disk.Path]) }

    $signatures = Get-PmxSignatureCheck -DevicePath $disk.Path
    if (-not $signatures.Success) { $reasons += $signatures.Error } else { $reasons += @($signatures.Reasons) }

    $configs = Get-PmxConfigReferenceCheck -Disk $disk
    if (-not $configs.Success) { $reasons += $configs.Error } else { $reasons += @($configs.References) }

    $namespaces = Get-PmxMountNamespaceCheck -MajorMinor $majorMinorIdentities
    if (-not $namespaces.Success) { $reasons += $namespaces.Error } else { $reasons += @($namespaces.References) }

    $handles = Get-PmxOpenHandleCheck -DevicePath $devicePaths
    if (-not $handles.Success) {
        $reasons += $handles.Error
    } elseif ($handles.InUse) {
        $reasons += "block device(s) have open file handles: $(@($handles.InUsePaths) -join ', ')"
    }

    if (-not (Test-Admin)) { $reasons += 'capacity testing requires root' }
    if (-not (Test-Path -LiteralPath '/usr/bin/f3probe' -PathType Leaf)) { $reasons += 'trusted /usr/bin/f3probe is not installed' }
    if (-not (Get-Command udevadm -CommandType Application -ErrorAction SilentlyContinue)) { $reasons += 'udevadm is missing' }

    return [pscustomobject]@{
        Safe    = ($reasons.Count -eq 0)
        Disk    = $disk
        Reasons = @($reasons | Sort-Object -Unique)
    }
}

function Invoke-ProxmoxCapacityProbe {
    param(
        [Parameter(Mandatory)][string]$StablePath,
        [Parameter(Mandatory)][string]$ExpectedSerial,
        [Parameter(Mandatory)][long]$ExpectedSizeBytes,
        [Parameter(Mandatory)][string]$ExpectedMajorMinor,
        [Parameter(Mandatory)][string]$ExpectedDiskSeq,
        [string]$ExpectedWwn,
        [Parameter(Mandatory)][string]$Confirmation
    )

    # Ordinal, NOT -cne. PowerShell's -ceq/-cne are case-sensitive but CULTURE-sensitive,
    # and culture comparison gives zero weight to characters like U+00AD soft hyphen and
    # U+200B zero-width space — so "DESTROY ata-SSD_4TB_0031<U+00AD>34" compares EQUAL to
    # the real phrase. The phrase is meant to be copied from a rendered prompt, which is
    # exactly how an invisible character gets into it. Verified on pwsh 7.5: -cne accepts
    # all three zero-width variants; [StringComparison]::Ordinal rejects every one.
    $expectedPhrase = "DESTROY $([IO.Path]::GetFileName($StablePath))"
    if (-not [string]::Equals($Confirmation, $expectedPhrase, [StringComparison]::Ordinal)) {
        return [pscustomobject]@{ Success = $false; Message = 'Refused: destructive confirmation did not match exactly.'; ExitCode = $null; Output = @() }
    }
    $lockName = ($ExpectedMajorMinor -replace '[^0-9]', '_')
    if (-not $lockName) {
        return [pscustomobject]@{ Success = $false; Message = 'Refused: disk lock identity is unavailable.'; ExitCode = $null; Output = @() }
    }
    $lockPath = "/run/lock/powerflow-pmx-$lockName.lock"
    $lock = $null
    try {
        try {
            $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        } catch {
            return [pscustomobject]@{ Success = $false; Message = 'Refused: another capacity test holds this disk lock.'; ExitCode = $null; Output = @() }
        }

        $udevadm = Get-Command udevadm -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $udevadm) {
            return [pscustomobject]@{ Success = $false; Message = 'Refused: udevadm disappeared before revalidation.'; ExitCode = $null; Output = @() }
        }
        & $udevadm.Source 'settle' 2>$null
        $udevCode = $LASTEXITCODE
        if ($udevCode -ne 0) {
            return [pscustomobject]@{ Success = $false; Message = "Refused: udev did not settle cleanly (exit $udevCode)."; ExitCode = $null; Output = @() }
        }

        # Full preflight is intentionally repeated only after the per-disk lock is held.
        $safety = Get-ProxmoxDiskSafety -StablePath $StablePath
        if (-not $safety.Safe) {
            return [pscustomobject]@{ Success = $false; Message = "Refused after recheck: $($safety.Reasons -join '; ')"; ExitCode = $null; Output = @() }
        }
        $d = $safety.Disk
        # Ordinal for the same reason as the phrase above: these compare device identity,
        # where a culture-equal-but-byte-different string must never read as "unchanged".
        $identityChanged = (
            -not $d -or
            -not [string]::Equals("$($d.Serial)",     "$ExpectedSerial",     [StringComparison]::Ordinal) -or
            $d.SizeBytes -ne $ExpectedSizeBytes -or
            -not [string]::Equals("$($d.MajorMinor)", "$ExpectedMajorMinor", [StringComparison]::Ordinal) -or
            -not [string]::Equals("$($d.DiskSeq)",    "$ExpectedDiskSeq",    [StringComparison]::Ordinal) -or
            -not [string]::Equals("$($d.Wwn)",        "$ExpectedWwn",        [StringComparison]::Ordinal) -or
            $StablePath -notin @($d.StableIds)
        )
        if ($identityChanged) {
            return [pscustomobject]@{ Success = $false; Message = 'Refused: disk identity changed while awaiting confirmation.'; ExitCode = $null; Output = @() }
        }

        # f3probe's own words are the evidence — "Bad news: The device is a counterfeit of
        # type limbo", and the *Usable* size vs Announced size block. Printing and dropping
        # them threw away the one artefact this whole workflow exists to produce for a
        # refund claim, so the lines are CAPTURED as well as shown, and returned as Output
        # to match Start-ProxmoxSmartTest / Get-ProxmoxSmartReport.
        #
        # $PSNativeCommandUseErrorActionPreference (default $true on pwsh 7.4+) turns a
        # non-zero exit into a PowerShell error record. A counterfeit exits 102 — a SUCCESS
        # for our purposes — so it is pinned to Continue for this call only; otherwise a
        # user whose session sets ErrorActionPreference='Stop' would land in the catch and
        # be told "device state is unknown" about a probe that in fact completed.
        $output = @()
        $prevNative = $PSNativeCommandUseErrorActionPreference
        $prevEap = $ErrorActionPreference
        try {
            $PSNativeCommandUseErrorActionPreference = $false
            $ErrorActionPreference = 'Continue'
            & '/usr/bin/f3probe' '--destructive' '--time-ops' '--' $StablePath 2>&1 |
                ForEach-Object { $line = "$_"; $output += $line; Write-Host $line }
            $code = $LASTEXITCODE
        } catch {
            return [pscustomobject]@{ Success = $false; Message = 'Capacity probe was interrupted or failed; device state is unknown.'; ExitCode = $null; Output = @($output) }
        } finally {
            $PSNativeCommandUseErrorActionPreference = $prevNative
            $ErrorActionPreference = $prevEap
        }
        # Exit contract from f3probe's own source: fake_type == FKTY_GOOD ? 0 : 100 + fake_type.
        $message = switch ($code) {
            0   { 'Capacity verified: the announced size is genuine.' }
            101 { 'Test completed: the device is damaged.' }
            102 { 'Test completed: counterfeit device (limbo).' }
            103 { 'Test completed: counterfeit device (wraparound).' }
            104 { 'Test completed: counterfeit device (chain).' }
            default { "f3probe failed with exit code $code; device state may be incomplete." }
        }
        return [pscustomobject]@{ Success = ($code -eq 0); Message = $message; ExitCode = $code; Output = @($output) }
    } finally {
        if ($lock) { $lock.Dispose() }
    }
}
