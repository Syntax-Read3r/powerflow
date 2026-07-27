# ==============================================================================
# PowerFlow — System Health Adapter (Windows)
# ==============================================================================
# Domain   : Platform / Windows
# File     : platform/windows/adapters/health.ps1
# Purpose  : Machine vitals for pc-whoami / pc-cap — power plan, CPU cap,
#            hardware errors, firmware
# Contract : Get-MachineInfo, Get-PowerSnapshot, Get-StabilityEvents,
#            Get-FirmwareInfo, Set-CpuMaxState, Export-StabilityReport
# Depends  : none
# ==============================================================================
#
# Everything powercfg/WHEA/CIM lives HERE, not in the component. The component
# renders; this file is the only place that knows what a GUID alias is.
# ==============================================================================

# The stock Windows plans, by GUID — names are localised, GUIDs are not. Anything
# not in this table was created by an OEM tool (Armoury Crate's "GameTurbo"), a
# vendor utility, or a script — which is exactly the thing worth flagging.
$script:PF_StockPlans = @{
    '381b4222-f694-41f0-9685-ff5bb260df2e' = 'Balanced'
    '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' = 'High performance'
    'a1841308-3541-4fab-bc81-f71556f20b4a' = 'Power saver'
    'e9a42b02-d5df-448d-aa00-03f14749eb61' = 'Ultimate Performance'
}

# SMBIOS memory types (SMBIOS spec 7.18.2). Win32_PhysicalMemory.MemoryType reports 0
# ("Unknown") on essentially every modern board — this machine's DDR4 included — so
# SMBIOSMemoryType is the field to trust.
$script:PF_MemoryTypes = @{
    20 = 'DDR'; 21 = 'DDR2'; 22 = 'DDR2 FB-DIMM'; 24 = 'DDR3'; 26 = 'DDR4'
    27 = 'LPDDR'; 28 = 'LPDDR2'; 29 = 'LPDDR3'; 30 = 'LPDDR4'; 34 = 'DDR5'; 35 = 'LPDDR5'
}

# Adapters that are not really a GPU: streaming/remote/virtual display drivers. They show
# up in Win32_VideoController next to the real hardware (this machine lists a "Virtual
# Desktop Monitor"), and reporting one as your GPU would be nonsense.
$script:PF_VirtualGpuPattern =
    'Virtual|Parsec|RDP |Remote Display|Citrix|VMware|VirtualBox|Hyper-V|DisplayLink|' +
    'Oculus|Meta |IddCx|Mirror Driver|Basic Display|Basic Render'

# Hardware vendor strings are legal boilerplate ("Advanced Micro Devices, Inc. [AMD/ATI]",
# "ASUSTeK COMPUTER INC.") and nobody wants that in a one-line summary. Same function name
# on both platforms so the two health adapters stay symmetrical.
function Format-HwVendor {
    param([string]$Vendor)
    if (-not $Vendor) { return $null }
    switch -Regex ($Vendor) {
        'NVIDIA'                         { return 'NVIDIA' }
        'Intel'                          { return 'Intel' }
        # \b matters: -match is case-insensitive, so a bare 'ATI' would match "Corporation".
        'Advanced Micro Devices|\bAMD\b|\bATI\b' { return 'AMD' }
        'ASUSTeK|ASUS'                   { return 'ASUS' }
        'Micro-Star|MSI'                 { return 'MSI' }
        'Gigabyte'                       { return 'Gigabyte' }
        'ASRock'                         { return 'ASRock' }
        default {
            return (($Vendor -replace '(?i)\s*(Corporation|Computer|Corp\.?|Inc\.?|Co\.,? ?Ltd\.?|Technology|Technologies|International|LLC|GmbH)\.?', ' ') -replace '\s+', ' ').Trim(' ', ',', '.')
        }
    }
}

# True VRAM per adapter, keyed by driver description.
#
# WHY NOT Win32_VideoController.AdapterRAM: it is a uint32, so it WRAPS above 4 GB — a
# 16 GB RTX 4080 reports ~4.29 GB (4293918720). The display-class registry keys carry
# qwMemorySize, a 64-bit value, which is correct.
function Get-GpuVramMap {
    $map = @{}
    $class = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    Get-ChildItem $class -ErrorAction SilentlyContinue | ForEach-Object {
        $desc = $_.GetValue('DriverDesc')
        $qw   = $_.GetValue('HardwareInformation.qwMemorySize')
        if ($desc -and $qw) { $map[[string]$desc] = [int64]$qw }
    }
    return $map
}

# Every real display adapter, discrete first (sorted by VRAM). Keeps a card whose driver
# is unhealthy and flags it — a GPU in an error state is exactly what pc-whoami is for.
function Get-GpuInfo {
    $vram = Get-GpuVramMap
    $all  = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)

    $real = $all | Where-Object {
        $n = "$($_.Name) $($_.AdapterCompatibility)"
        $_.Name -and $n -notmatch $script:PF_VirtualGpuPattern
    }

    $out = foreach ($g in $real) {
        # DEDICATED VRAM only, and only from the registry.
        #
        # AdapterRAM is deliberately NOT used as a fallback: on an integrated GPU it reports
        # SHARED system memory (this machine's UHD 770 claims ~2 GB), so trusting it both
        # invents VRAM the chip does not have and makes the iGPU look discrete.
        $dedicated = if ($vram.ContainsKey([string]$g.Name)) { $vram[[string]$g.Name] } else { 0 }

        # Discrete when it has dedicated memory, or when it is a discrete-only brand whose
        # driver simply did not publish the value (VRAM then reads as unknown, not zero).
        #
        # \bATI\b is NOT optional: -match is case-insensitive and substring-based, so a bare
        # 'ATI' matches "Intel Corpor(ati)on" and would label every Intel iGPU discrete.
        $integrated = -not ($dedicated -or ($g.AdapterCompatibility -match 'NVIDIA|Advanced Micro|\bATI\b'))

        [pscustomobject]@{
            # (R)/(TM) are legal boilerplate, not part of the product name.
            Name    = ((($g.Name -replace '\((R|TM)\)', '') -replace '\s+', ' ')).Trim()
            Vendor  = (Format-HwVendor $g.AdapterCompatibility)
            VramGB  = if ($dedicated) { [math]::Round($dedicated / 1GB, 0) } else { 0 }
            Driver  = $g.DriverVersion
            Integrated = $integrated
            Healthy = ($g.Status -eq 'OK')
            Resolution = if ($g.CurrentHorizontalResolution) {
                "$($g.CurrentHorizontalResolution)x$($g.CurrentVerticalResolution)@$($g.CurrentRefreshRate)Hz"
            } else { $null }
        }
    }
    # Discrete first, then by VRAM — so a discrete card with unpublished VRAM still outranks
    # an iGPU instead of sorting down among the zeroes.
    return @($out | Sort-Object -Property @{ Expression = 'Integrated' },
                                           @{ Expression = 'VramGB'; Descending = $true }, Name)
}

# RAM as a spec sheet, not just a number: type, speed, and how the sticks are arranged.
function Get-MemoryInfo {
    $cs     = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $sticks = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
    $array  = Get-CimInstance Win32_PhysicalMemoryArray -ErrorAction SilentlyContinue | Select-Object -First 1

    $totalGB = if ($cs) { [math]::Round($cs.TotalPhysicalMemory / 1GB) } else { 0 }
    if (-not $sticks) {
        return [pscustomobject]@{ TotalGB = $totalGB; Detail = $false; Note = 'no SMBIOS memory data' }
    }

    $types = @($sticks | ForEach-Object { $script:PF_MemoryTypes[[int]$_.SMBIOSMemoryType] } |
               Where-Object { $_ } | Sort-Object -Unique)
    # Mixed types are possible (and worth seeing) on a board with different modules.
    $type = if ($types.Count -eq 1) { $types[0] } elseif ($types.Count -gt 1) { $types -join '/' } else { $null }

    # ConfiguredClockSpeed is what the sticks actually RUN at; Speed is what they are rated
    # for. They differ when XMP/EXPO is off — a real, common, invisible performance loss,
    # so we report the running speed and expose the rating separately.
    $running = @($sticks | ForEach-Object { [int]$_.ConfiguredClockSpeed } | Where-Object { $_ -gt 0 } | Sort-Object -Unique)
    $rated   = @($sticks | ForEach-Object { [int]$_.Speed }                | Where-Object { $_ -gt 0 } | Sort-Object -Unique)

    $caps    = @($sticks | ForEach-Object { [math]::Round($_.Capacity / 1GB) })
    $capDesc = if (($caps | Sort-Object -Unique).Count -eq 1) {
        "{0}x{1}GB" -f $caps.Count, $caps[0]
    } else {
        ($caps | ForEach-Object { "${_}GB" }) -join '+'
    }

    [pscustomobject]@{
        TotalGB    = $totalGB
        Detail     = $true
        Type       = $type
        SpeedMTs   = if ($running) { $running[-1] } elseif ($rated) { $rated[-1] } else { 0 }
        RatedMTs   = if ($rated)   { $rated[-1] }   else { 0 }
        Sticks     = $caps.Count
        SlotsTotal = if ($array -and $array.MemoryDevices) { [int]$array.MemoryDevices } else { 0 }
        Layout     = $capDesc
        Vendor     = (@($sticks | ForEach-Object { $_.Manufacturer } | Where-Object { $_ } | Sort-Object -Unique) -join '/')
        PartNumber = (@($sticks | ForEach-Object { ($_.PartNumber ?? '').Trim() } | Where-Object { $_ } | Sort-Object -Unique) -join '/')
        Note       = $null
    }
}

# Physical drives: what they are (SSD/HDD), how big, and how much is left.
#
# Get-PhysicalDisk is preferred; the MSFT_PhysicalDisk CIM class is the fallback for a box
# where the Storage module is missing (Server Core, a trimmed image). Both report MediaType,
# which is the only reliable SSD/HDD answer — Win32_DiskDrive does not carry it.
#
# Keyed by DeviceId, never by name: this machine has TWO identically-named NVMe drives, so
# grouping by FriendlyName would silently merge them into one row.
function Get-DiskInfo {
    $disks = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
    if (-not $disks) {
        try {
            $disks = @(Get-CimInstance -Namespace root/Microsoft/Windows/Storage `
                                       -ClassName MSFT_PhysicalDisk -ErrorAction Stop)
        } catch { return @() }
    }
    if (-not $disks) { return @() }

    # Free space lives on VOLUMES, capacity on DISKS — partitions are the join between them.
    $freeByDisk = @{}
    $lettersByDisk = @{}
    foreach ($p in @(Get-Partition -ErrorAction SilentlyContinue | Where-Object DriveLetter)) {
        $v = Get-Volume -DriveLetter $p.DriveLetter -ErrorAction SilentlyContinue
        if (-not $v) { continue }
        $n = [string]$p.DiskNumber
        $freeByDisk[$n]    = [int64]($freeByDisk[$n]) + [int64]$v.SizeRemaining
        $lettersByDisk[$n] = @($lettersByDisk[$n]) + "$($p.DriveLetter):" | Where-Object { $_ }
    }

    $out = foreach ($d in $disks) {
        $id = [string]$d.DeviceId
        # MediaType is occasionally 'Unspecified' on NVMe; the bus then settles it, since
        # there is no such thing as a spinning NVMe drive.
        $media = switch ("$($d.MediaType)") {
            'SSD'  { 'SSD' }
            'HDD'  { 'HDD' }
            'SCM'  { 'SCM' }
            default { if ("$($d.BusType)" -eq 'NVMe') { 'SSD' } else { 'unknown' } }
        }

        # Rotational speed, when the drive really is spinning. SSDs report 0 and USB
        # enclosures report 'Unknown' (the bridge hides it), so only a real number is used —
        # this is what actually tells an old 7200rpm platter drive from a modern SSD.
        $rpm = 0
        if ("$($d.SpindleSpeed)" -match '^\d+$' -and [int]$d.SpindleSpeed -gt 0) { $rpm = [int]$d.SpindleSpeed }

        # FORM FACTOR IS INFERRED, and deliberately so: Get-PhysicalDisk.FormFactor is blank
        # on every drive in practice (verified — NVMe reports nothing, USB reports 'Unknown'),
        # so there is no API answer to read. The bus is a sound proxy for consumer hardware:
        # NVMe ships as M.2, and a SATA SSD is a 2.5" drive. A spinning SATA disk could be
        # 3.5" or 2.5" with no way to tell, so it gets its RPM instead of a guessed size.
        $form = switch -Regex ("$($d.BusType)|$media") {
            '^NVMe'      { 'M.2' }
            '^SATA\|SSD' { '2.5"' }
            default      { $null }
        }

        [pscustomobject]@{
            Id         = $id
            Name       = ("$($d.FriendlyName)" -replace '\s+', ' ').Trim()
            Media      = $media
            Bus        = "$($d.BusType)"
            Rpm        = $rpm
            FormFactor = $form
            SizeBytes  = [int64]$d.Size
            FreeBytes  = if ($freeByDisk.ContainsKey($id)) { [int64]$freeByDisk[$id] } else { 0 }
            Letters    = (@($lettersByDisk[$id]) -join ' ')
            # A USB drive is storage you can unplug — worth distinguishing from the disks the
            # machine actually runs on.
            External   = ("$($d.BusType)" -in @('USB', '1394', 'Fibre Channel'))
            Healthy    = ("$($d.HealthStatus)" -in @('Healthy', ''))
            # The drive Windows boots from — the one you care about first.
            System     = ((@($lettersByDisk[$id]) -contains "$env:SystemDrive"))
        }
    }
    # Boot drive, then other internal drives (biggest first), then anything unpluggable.
    return @($out | Sort-Object -Property @{ Expression = 'External' },
                                          @{ Expression = 'System'; Descending = $true },
                                          @{ Expression = 'SizeBytes'; Descending = $true }, Id)
}

# Upgrade headroom, straight from the motherboard's own SMBIOS records.
#
# WHERE EACH NUMBER COMES FROM (nothing here is a hardcoded board database):
#   M.2 sockets   Type 8 port connectors whose designator is M.2 …(SOCKET3). Wi-Fi/CNVi
#                 M.2 keys are excluded — they take a radio, not a drive.
#   SATA ports    Type 8 connectors of PortType 32 (SATA). Vendors label them in PAIRS
#                 ("SATA6G_12" = ports 1 and 2), so the trailing digit run is counted
#                 rather than assuming one port per record.
#   PCIe slots    Type 9 system slots, which carry a real used/free flag (CurrentUsage
#                 3 = Available, 4 = In Use) — no inference needed.
#   Memory        Type 16/17: declared slots vs populated, plus the board's max capacity.
#
# Occupancy for M.2/SATA is counted from the drives actually attached by bus, because SMBIOS
# describes the BOARD, not what is plugged into it.
function Get-SlotInfo {
    $ports = @()
    try { $ports = @(Get-CimInstance Win32_PortConnector -ErrorAction Stop) } catch { }
    $slots = @(Get-CimInstance Win32_SystemSlot -ErrorAction SilentlyContinue)
    $array = Get-CimInstance Win32_PhysicalMemoryArray -ErrorAction SilentlyContinue | Select-Object -First 1
    $sticks = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue).Count
    $disks  = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)

    # ── M.2 storage sockets ───────────────────────────────────────────────────
    $m2 = @($ports | Where-Object {
        $d = "$($_.InternalReferenceDesignator)$($_.ExternalReferenceDesignator)"
        $d -match 'M\.?2' -and $d -notmatch '(?i)wifi|wlan|cnvi|bt|key.?e'
    }).Count

    # ── SATA ports (counted from paired designators) ──────────────────────────
    $sata = 0
    foreach ($p in $ports) {
        $d = "$($p.InternalReferenceDesignator)$($p.ExternalReferenceDesignator)"
        if ([int]$p.PortType -ne 32 -and $d -notmatch '(?i)sata') { continue }
        # Take the label's last segment: "SATA6G_12" -> "12" (two ports), "SATA1" -> "1".
        $tail = ($d -split '[_-]')[-1]
        $digits = ($tail -replace '\D', '')
        $sata += if ($digits.Length -ge 1) { $digits.Length } else { 1 }
    }

    $m2Used   = @($disks | Where-Object { "$($_.BusType)" -eq 'NVMe' }).Count
    $sataUsed = @($disks | Where-Object { "$($_.BusType)" -eq 'SATA' }).Count

    [pscustomobject]@{
        Supported  = [bool]($ports.Count -or $slots.Count -or $array)
        M2Total    = $m2
        M2Used     = [math]::Min($m2Used, [math]::Max($m2, $m2Used))
        SataTotal  = $sata
        SataUsed   = [math]::Min($sataUsed, [math]::Max($sata, $sataUsed))
        PcieTotal  = $slots.Count
        PcieFree   = @($slots | Where-Object { [int]$_.CurrentUsage -eq 3 }).Count
        MemTotal   = if ($array -and $array.MemoryDevices) { [int]$array.MemoryDevices } else { 0 }
        MemUsed    = $sticks
        MemMaxGB   = if ($array -and $array.MaxCapacityEx) { [math]::Round([int64]$array.MaxCapacityEx / 1MB) } else { 0 }
    }
}

function Get-MachineInfo {
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $cs  = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue

    [pscustomobject]@{
        # (R)/(TM) are legal boilerplate, stripped here as they are for GPU names.
        CpuName = if ($cpu) { ((($cpu.Name -replace '\((R|TM)\)', '') -replace '\s+', ' ')).Trim() } else { 'unknown' }
        Cores   = if ($cpu) { [int]$cpu.NumberOfCores } else { 0 }
        Threads = if ($cpu) { [int]$cpu.NumberOfLogicalProcessors } else { 0 }
        RamGB   = if ($cs)  { [math]::Round($cs.TotalPhysicalMemory / 1GB) } else { 0 }
        Memory  = (Get-MemoryInfo)
        Gpus    = (Get-GpuInfo)
        Disks   = (Get-DiskInfo)
        Slots   = (Get-SlotInfo)
        Uptime  = (Get-Uptime)
    }
}

<#
.SYNOPSIS
    The active power plan and CPU cap, decoded — no hex, no GUID aliases.
#>
function Get-PowerSnapshot {
    $active = (powercfg /getactivescheme 2>$null) -join ' '
    if (-not $active -or $active -notmatch 'GUID:\s*([0-9a-fA-F-]+)\s+\((.+)\)') {
        return [pscustomobject]@{ Supported = $false; Note = 'powercfg gave no active scheme' }
    }
    $planId   = $matches[1].ToLower()
    $planName = $matches[2]

    # powercfg reports the cap as "Current AC Power Setting Index: 0x00000055".
    # 0x55 is 85 — the decoding humans always have to be told about happens here.
    $q  = (powercfg /query SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 2>$null) -join "`n"
    $ac = $null; $dc = $null
    if ($q -match 'AC Power Setting Index:\s*0x([0-9a-fA-F]+)') { $ac = [Convert]::ToInt32($matches[1], 16) }
    if ($q -match 'DC Power Setting Index:\s*0x([0-9a-fA-F]+)') { $dc = [Convert]::ToInt32($matches[1], 16) }

    $plans = @()
    foreach ($line in (powercfg /list 2>$null)) {
        if ($line -match 'GUID:\s*([0-9a-fA-F-]+)\s+\((.+?)\)\s*(\*)?\s*$') {
            $id = $matches[1].ToLower()
            $plans += [pscustomobject]@{
                Id      = $id
                Name    = $matches[2]
                Active  = [bool]$matches[3]
                IsStock = $script:PF_StockPlans.ContainsKey($id)
            }
        }
    }

    [pscustomobject]@{
        Supported    = $true
        PlanId       = $planId
        PlanName     = $planName
        IsStockPlan  = $script:PF_StockPlans.ContainsKey($planId)
        ACMaxPercent = $ac
        DCMaxPercent = $dc
        HasBattery   = [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
        AllPlans     = $plans
        Note         = $null
        # Shown as a teaching line by the component (lesson mode) — the raw command
        # this call wraps, so the tool teaches what it replaces.
        RealCommand  = 'powercfg /query SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX'
    }
}

<#
.SYNOPSIS
    Hardware errors (WHEA), bugchecks, and crash dumps within a window.
#>
function Get-StabilityEvents {
    param([int]$Days = 7)

    $since = (Get-Date).AddDays(-$Days)
    $notes = @()

    # Get-WinEvent THROWS when zero events match — an empty week must not look
    # like an error, so both queries are try/caught to empty lists.
    $whea = @()
    try {
        $whea = @(Get-WinEvent -FilterHashtable @{
            LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $since
        } -ErrorAction Stop | ForEach-Object {
            [pscustomobject]@{ Time = $_.TimeCreated; Id = $_.Id; Summary = (($_.Message -split "`n")[0]).Trim() }
        })
    } catch {}

    $bugchecks = @()
    try {
        $bugchecks = @(Get-WinEvent -FilterHashtable @{
            LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001; StartTime = $since
        } -ErrorAction Stop | ForEach-Object {
            [pscustomobject]@{ Time = $_.TimeCreated; Id = $_.Id; Summary = (($_.Message -split "`n")[0]).Trim() }
        })
    } catch {}

    $dumps = @(Get-ChildItem (Join-Path $env:SystemRoot 'Minidump\*.dmp') -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | ForEach-Object {
            [pscustomobject]@{ Path = $_.FullName; Time = $_.LastWriteTime; SizeKB = [math]::Round($_.Length / 1KB) }
        })
    if (-not (Test-Path (Join-Path $env:SystemRoot 'Minidump'))) {
        $notes += 'No minidump folder — dumps may be disabled, or none has ever been written.'
    }
    elseif ($dumps.Count -eq 0 -and -not (Test-Admin)) {
        # The folder exists but lists as empty without elevation. "0 dumps" next to
        # bugcheck records that name dump files would be a lie of omission.
        $notes += 'The minidump folder needs an elevated session to list — 0 here does not mean 0 exist.'
    }

    [pscustomobject]@{
        Supported      = $true
        Days           = $Days
        HardwareErrors = $whea
        Bugchecks      = $bugchecks
        Dumps          = $dumps
        Notes          = $notes
    }
}

function Get-FirmwareInfo {
    $bios  = Get-CimInstance Win32_BIOS      -ErrorAction SilentlyContinue
    $board = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue

    if (-not $bios) {
        return [pscustomobject]@{ Supported = $false; Note = 'Win32_BIOS returned nothing' }
    }

    [pscustomobject]@{
        Supported   = $true
        BiosVersion = $bios.SMBIOSBIOSVersion
        BiosDate    = $bios.ReleaseDate          # CIM cmdlets give a real [datetime]
        BiosVendor  = $bios.Manufacturer
        BoardVendor = (Format-HwVendor $board.Manufacturer)
        BoardName   = $board.Product
        Note        = $null
    }
}

<#
.SYNOPSIS
    Set the CPU maximum-state cap. Returns $true only after READING THE VALUE BACK.
.DESCRIPTION
    powercfg exits 0 on plenty of failures (bad GUID scope, insufficient rights on
    some SKUs). Trusting its exit code is how "restored afterward" becomes a lie —
    so success here means the re-query agrees, nothing less.
#>
function Set-CpuMaxState {
    param(
        [Parameter(Mandatory)][int]$ACPercent,
        [int]$DCPercent = -1,
        [string]$PlanId          # target a specific plan; default = the active one
    )

    $target = if ($PlanId) { $PlanId } else { 'SCHEME_CURRENT' }

    powercfg /setacvalueindex $target SUB_PROCESSOR PROCTHROTTLEMAX $ACPercent 2>$null | Out-Null
    if ($DCPercent -ge 0) {
        powercfg /setdcvalueindex $target SUB_PROCESSOR PROCTHROTTLEMAX $DCPercent 2>$null | Out-Null
    }
    powercfg /setactive SCHEME_CURRENT 2>$null | Out-Null

    $snap = Get-PowerSnapshot
    if (-not $snap -or -not $snap.Supported) { return $false }
    if ($PlanId -and $snap.PlanId -ne $PlanId.ToLower()) {
        # We modified a plan that is not active; the active snapshot cannot verify
        # it. Re-query the target plan directly.
        $q = (powercfg /query $PlanId SUB_PROCESSOR PROCTHROTTLEMAX 2>$null) -join "`n"
        return ($q -match 'AC Power Setting Index:\s*0x([0-9a-fA-F]+)' -and
                [Convert]::ToInt32($matches[1], 16) -eq $ACPercent)
    }
    return ($snap.ACMaxPercent -eq $ACPercent)
}

<#
.SYNOPSIS
    Write the raw evidence bundle (WHEA XML, bugcheck text, dump inventory) to a folder.
#>
function Export-StabilityReport {
    param([Parameter(Mandatory)][string]$Directory, [int]$Days = 7)

    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    $since   = (Get-Date).AddDays(-$Days)
    $written = @()

    try {
        $xml = Get-WinEvent -FilterHashtable @{
            LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $since
        } -ErrorAction Stop | ForEach-Object { $_.ToXml() }
        $p = Join-Path $Directory 'whea-events.xml'
        $xml | Set-Content $p; $written += $p
    } catch {}

    try {
        $txt = Get-WinEvent -FilterHashtable @{
            LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001; StartTime = $since
        } -ErrorAction Stop | Format-List TimeCreated, Message | Out-String
        $p = Join-Path $Directory 'bugchecks.txt'
        $txt | Set-Content $p; $written += $p
    } catch {}

    $ev = Get-StabilityEvents -Days $Days
    $p = Join-Path $Directory 'dump-inventory.txt'
    ($ev.Dumps | Format-Table Time, SizeKB, Path -AutoSize | Out-String) | Set-Content $p
    $written += $p

    return $written
}
