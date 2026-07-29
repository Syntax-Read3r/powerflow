# ==============================================================================
# PowerFlow — System Health Adapter (Linux)
# ==============================================================================
# Domain   : Platform / Linux
# File     : platform/linux/adapters/health.ps1
# Purpose  : Machine vitals for pc-whoami / pc-cap — governor, CPU cap,
#            MCE/hardware errors, firmware
# Contract : Get-MachineInfo, Get-PowerSnapshot, Get-StabilityEvents,
#            Get-FirmwareInfo, Set-CpuMaxState, Export-StabilityReport
# Depends  : none
# ==============================================================================
#
# The Windows concepts map like this — close enough to share one dashboard,
# different enough that pretending they are identical would mislead:
#
#   power plan   → cpufreq GOVERNOR (performance / powersave / schedutil …)
#   CPU cap %    → scaling_max_freq as a fraction of cpuinfo_max_freq
#   WHEA         → kernel MCE ("machine check") lines in the journal
#   BIOS (CIM)   → /sys/class/dmi/id/* — readable WITHOUT root
#   minidumps    → /var/crash if kdump/apport exist; usually they do not
#
# Degradation is honest, perms.ps1-style: a container with no cpufreq says so —
# it does not invent a governor, and zero journal access is "cannot read", not
# "zero errors".
# ==============================================================================

$script:PF_CpufreqBase = '/sys/devices/system/cpu/cpu0/cpufreq'

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

# Dedicated VRAM per PCI slot, from amdgpu's sysfs.
#
# Keyed BY SLOT on purpose: a machine with two GPUs has two /sys/class/drm cards, and simply
# taking the largest mem_info_vram_total would credit the discrete card's VRAM to the iGPU.
# card*/device is a symlink into /sys/devices/pci…/0000:01:00.0, which carries the address.
function Get-DrmVramBySlot {
    $map = @{}
    foreach ($c in @(Get-ChildItem '/sys/class/drm' -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -match '^card\d+$' })) {     # skip card0-DP-1 connectors
        $f = Join-Path $c.FullName 'device/mem_info_vram_total'
        if (-not (Test-Path $f)) { continue }
        $target = (Get-Item (Join-Path $c.FullName 'device') -Force -ErrorAction SilentlyContinue).Target
        if (-not $target) { continue }
        # lspci prints the slot without the domain ("01:00.0"); sysfs includes it.
        if ("$target" -match '([0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9a-fA-F])(/|$)') {
            $map[$matches[1]] = [int64](Get-Content $f -ErrorAction SilentlyContinue)
        }
    }
    return $map
}

# Every real display adapter, discrete first.
#
# Two sources, deliberately in this order:
#   1. nvidia-smi — when the proprietary driver is loaded it gives the marketing name and
#      the TRUE VRAM, neither of which lspci knows.
#   2. lspci — covers everything else (Intel/AMD/virtio) and is present wherever pciutils
#      is. Its device field looks like "AD103 [GeForce RTX 4080]": the bracketed part is
#      the product name, the bare part is the silicon, so we prefer the brackets.
# If neither exists we say so rather than invent a name.
function Get-GpuInfo {
    $out = [System.Collections.Generic.List[object]]::new()

    if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
        $q = nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader,nounits 2>/dev/null
        foreach ($line in @($q)) {
            if (-not $line) { continue }
            $p = $line -split '\s*,\s*'
            if ($p.Count -lt 2) { continue }
            $out.Add([pscustomobject]@{
                Name       = $p[0].Trim()
                Vendor     = 'NVIDIA'
                VramGB     = [math]::Round([double]$p[1] / 1024, 0)   # reported in MiB
                Driver     = if ($p.Count -ge 3) { $p[2].Trim() } else { $null }
                Integrated = $false
                Healthy    = $true
                Resolution = $null
            })
        }
    }

    if (Get-Command lspci -ErrorAction SilentlyContinue) {
        $vramBySlot = Get-DrmVramBySlot
        # -mm is the machine-readable form: slot "class" "vendor" "device" ...
        foreach ($line in @(lspci -mm 2>/dev/null)) {
            if ($line -notmatch '^(\S+)\s+"([^"]*)"\s+"([^"]*)"\s+"([^"]*)"') { continue }
            $slot = $matches[1]; $class = $matches[2]; $vendor = $matches[3]; $device = $matches[4]
            if ($class -notmatch 'VGA compatible controller|3D controller|Display controller') { continue }

            $short = Format-HwVendor $vendor
            # Already reported by nvidia-smi (which has better data) → skip the duplicate.
            if ($short -eq 'NVIDIA' -and ($out | Where-Object Vendor -eq 'NVIDIA')) { continue }

            $product = if ($device -match '\[([^\]]+)\]') { $matches[1] } else { $device }
            $name = if ($product -match '^(?i)' + [regex]::Escape($short)) { $product } else { "$short $product" }

            $vram = if ($vramBySlot.ContainsKey($slot)) { $vramBySlot[$slot] } else { 0 }

            # Integrated vs discrete, by PCI TOPOLOGY rather than by vendor.
            #
            # Vendor is not a reliable signal: AMD ships both discrete cards and APUs, so
            # "AMD ⇒ discrete" mislabels every Ryzen iGPU. Nor is "has no VRAM figure" —
            # amdgpu only publishes mem_info_vram_total when its driver is bound, so a
            # perfectly ordinary discrete card reads 0 on a live-USB or in a container.
            # Bus 00 is the root complex, where integrated graphics live; a discrete card
            # is always behind a PCIe bridge on a higher bus (01:00.0, 03:00.0, …).
            $integrated = if ($vram) { $false }
                          elseif ($slot -match '^0{1,4}:?0*0:') { $true }
                          elseif ($slot -match '^00:')          { $true }
                          else                                  { $false }

            $out.Add([pscustomobject]@{
                Name       = ($name -replace '\s+', ' ').Trim()
                Vendor     = $short
                VramGB     = if ($vram) { [math]::Round($vram / 1GB, 0) } else { 0 }
                Driver     = $null
                Integrated = $integrated
                Healthy    = $true
                Resolution = $null
            })
        }
    }

    # Discrete first, then by VRAM — matching the Windows adapter, so a discrete card whose
    # VRAM is unknown still outranks an iGPU instead of sorting down among the zeroes.
    return @($out | Sort-Object -Property @{ Expression = 'Integrated' },
                                          @{ Expression = 'VramGB'; Descending = $true }, Name)
}

# RAM as a spec sheet. Type and speed live in SMBIOS, which on Linux means dmidecode and
# therefore ROOT — /sys/firmware/dmi/tables/DMI is mode 0400. So:
#   * the total always works (/proc/meminfo)
#   * detail is attempted as root, or via `sudo -n` (non-interactive: it succeeds only with
#     passwordless sudo and NEVER prompts — a status command must not block on a password)
#   * otherwise we report the size and say plainly why there is no more
function Get-MemoryInfo {
    $totalGB = 0
    if (Test-Path /proc/meminfo) {
        $mem = Get-Content /proc/meminfo | Where-Object { $_ -match '^MemTotal:\s*(\d+)' } | Select-Object -First 1
        if ($mem -match '(\d+)') { $totalGB = [math]::Round([int64]$matches[1] / 1MB) }
    }

    $plain = [pscustomobject]@{ TotalGB = $totalGB; Detail = $false; Note = $null }

    if (-not (Get-Command dmidecode -ErrorAction SilentlyContinue)) {
        $plain.Note = 'install dmidecode for type/speed'
        return $plain
    }

    $raw = if ((id -u) -eq '0') {
        dmidecode -t 17 2>/dev/null
    } elseif (Get-Command sudo -ErrorAction SilentlyContinue) {
        sudo -n dmidecode -t 17 2>/dev/null
    } else { $null }

    if (-not $raw) {
        $plain.Note = 'type/speed needs root (sudo dmidecode -t 17)'
        return $plain
    }

    # dmidecode prints one block per slot; empty slots say "No Module Installed".
    $caps = @(); $types = @(); $running = @(); $rated = @(); $vendors = @(); $parts = @(); $slots = 0
    $cur = @{}
    foreach ($line in @($raw) + @('')) {
        if ($line -match '^Memory Device' -or $line -eq '') {
            if ($cur.Count) {
                $slots++
                if ($cur.Size -and $cur.Size -notmatch 'No Module') {
                    if ($cur.Size -match '(\d+)\s*(MB|GB)') {
                        $caps += if ($matches[2] -eq 'GB') { [int]$matches[1] } else { [math]::Round([int]$matches[1] / 1024) }
                    }
                    if ($cur.Type      -and $cur.Type -notmatch 'Unknown|Other') { $types   += $cur.Type }
                    if ($cur.Speed     -match '(\d+)')                           { $rated   += [int]$matches[1] }
                    if ($cur.Configured -match '(\d+)')                          { $running += [int]$matches[1] }
                    if ($cur.Vendor    -and $cur.Vendor -notmatch 'Unknown|Not Specified') { $vendors += $cur.Vendor }
                    if ($cur.Part      -and $cur.Part   -notmatch 'Unknown|Not Specified') { $parts   += $cur.Part }
                }
                $cur = @{}
            }
            continue
        }
        switch -Regex ($line) {
            '^\s*Size:\s*(.+)$'                    { $cur.Size       = $matches[1].Trim() }
            '^\s*Type:\s*(.+)$'                    { $cur.Type       = $matches[1].Trim() }
            '^\s*Speed:\s*(.+)$'                   { $cur.Speed      = $matches[1].Trim() }
            '^\s*Configured Memory Speed:\s*(.+)$' { $cur.Configured = $matches[1].Trim() }
            '^\s*Manufacturer:\s*(.+)$'            { $cur.Vendor     = $matches[1].Trim() }
            '^\s*Part Number:\s*(.+)$'             { $cur.Part       = $matches[1].Trim() }
        }
    }

    if ($caps.Count -eq 0) {
        $plain.Note = 'dmidecode reported no populated slots'
        return $plain
    }

    $uniqTypes = @($types | Sort-Object -Unique)
    $capDesc = if (($caps | Sort-Object -Unique).Count -eq 1) { "{0}x{1}GB" -f $caps.Count, $caps[0] }
               else { ($caps | ForEach-Object { "${_}GB" }) -join '+' }
    $run = @($running | Sort-Object -Unique); $rat = @($rated | Sort-Object -Unique)

    [pscustomobject]@{
        TotalGB    = $totalGB
        Detail     = $true
        Type       = if ($uniqTypes.Count -eq 1) { $uniqTypes[0] } elseif ($uniqTypes.Count) { $uniqTypes -join '/' } else { $null }
        SpeedMTs   = if ($run) { $run[-1] } elseif ($rat) { $rat[-1] } else { 0 }
        RatedMTs   = if ($rat) { $rat[-1] } else { 0 }
        Sticks     = $caps.Count
        SlotsTotal = $slots
        Layout     = $capDesc
        Vendor     = (@($vendors | Sort-Object -Unique) -join '/')
        PartNumber = (@($parts   | Sort-Object -Unique) -join '/')
        Note       = $null
    }
}

# Physical drives via lsblk — no root needed, unlike the SMBIOS-based memory detail.
#
#   ROTA (rotational)  1 = spinning platter (HDD), 0 = solid state. This is the kernel's own
#                      answer, straight from /sys/block/*/queue/rotational — the exact
#                      equivalent of Windows' MediaType, and just as authoritative.
#   TRAN (transport)   nvme / sata / usb — the interface, which with ROTA is what really
#                      separates a modern M.2 from an old 2.5" SATA drive.
#   -b -P              bytes, and KEY="value" output that parses without column guessing.
#
# Free space is attributed via PKNAME (a partition's parent disk), so a drive's figure is the
# sum of its own mounted partitions rather than a whole-machine total.
function Get-DiskInfo {
    if (-not (Get-Command lsblk -ErrorAction SilentlyContinue)) { return @() }

    $rows = @(lsblk -b -P -o NAME,TYPE,ROTA,SIZE,MODEL,TRAN,MOUNTPOINT,FSAVAIL,PKNAME 2>/dev/null)
    if (-not $rows) { return @() }

    $parse = {
        param($line)
        $h = @{}
        foreach ($m in [regex]::Matches($line, '(\w+)="([^"]*)"')) { $h[$m.Groups[1].Value] = $m.Groups[2].Value }
        return $h
    }

    $disks = @(); $freeByDisk = @{}; $mountsByDisk = @{}
    foreach ($line in $rows) {
        $r = & $parse $line
        if ($r.TYPE -eq 'disk') { $disks += , $r; continue }
        # A mounted partition contributes its free space to its parent disk.
        if ($r.MOUNTPOINT -and $r.PKNAME) {
            $avail = 0
            if ("$($r.FSAVAIL)" -match '^\d+$') { $avail = [int64]$r.FSAVAIL }
            $freeByDisk[$r.PKNAME]   = [int64]($freeByDisk[$r.PKNAME]) + $avail
            $mountsByDisk[$r.PKNAME] = @($mountsByDisk[$r.PKNAME]) + $r.MOUNTPOINT | Where-Object { $_ }
        }
    }

    $out = foreach ($d in $disks) {
        # Skip things that are not real drives: loopbacks, ram disks, optical, device-mapper.
        if ($d.NAME -match '^(loop|ram|sr|dm-|zram)') { continue }
        # …and skip zero-size block devices. Hypervisors and card readers expose empty
        # placeholder devices (a container showed "Virtual Disk · 0 GB"); a drive that holds
        # nothing is not a drive worth a row.
        if (-not ("$($d.SIZE)" -match '^\d+$') -or [int64]$d.SIZE -le 0) { continue }

        $media = if ($d.ROTA -eq '1') { 'HDD' } elseif ($d.ROTA -eq '0') { 'SSD' } else { 'unknown' }
        $bus   = if ($d.TRAN) { $d.TRAN.ToUpper() } else { $null }
        # Same inference (and same caveat) as the Windows adapter: NVMe ships as M.2, and a
        # SATA SSD is a 2.5" drive. A spinning disk gets no guessed size.
        $form  = if ($bus -eq 'NVME') { 'M.2' } elseif ($bus -eq 'SATA' -and $media -eq 'SSD') { '2.5"' } else { $null }

        [pscustomobject]@{
            Id         = $d.NAME
            Name       = if ($d.MODEL) { ($d.MODEL -replace '\s+', ' ').Trim() } else { $d.NAME }
            Media      = $media
            Bus        = if ($bus -eq 'NVME') { 'NVMe' } else { $bus }
            Rpm        = 0          # needs smartctl + root; not worth a password for a status line
            FormFactor = $form
            SizeBytes  = if ("$($d.SIZE)" -match '^\d+$') { [int64]$d.SIZE } else { 0 }
            FreeBytes  = if ($freeByDisk.ContainsKey($d.NAME)) { [int64]$freeByDisk[$d.NAME] } else { 0 }
            Letters    = (@($mountsByDisk[$d.NAME]) -join ' ')
            External   = ($bus -eq 'USB')
            Healthy    = $true      # SMART needs root; claiming health we cannot see would lie
            # The drive carrying / — the one you care about first.
            System     = ((@($mountsByDisk[$d.NAME]) -contains '/'))
        }
    }
    # Boot drive, then other internal drives (biggest first), then anything unpluggable.
    return @($out | Sort-Object -Property @{ Expression = 'External' },
                                          @{ Expression = 'System'; Descending = $true },
                                          @{ Expression = 'SizeBytes'; Descending = $true }, Id)
}

# Processes you must never kill. PID 1 is the init system — killing it panics the kernel —
# and kernel threads (kthreadd and its children) are not user processes at all; a kill signal
# to them is meaningless at best.
#
# dbus-daemon and the systemd-* helpers are the Linux equivalent of Windows' svchost here:
# they are session/service plumbing, they can accumulate real memory, and killing them breaks
# the desktop or the service manager rather than freeing anything useful.
$script:PF_ProtectedProcs = @(
    'systemd', 'init', 'kthreadd', 'kernel', 'kworker', 'ksoftirqd', 'migration',
    'dbus-daemon', 'dbus-broker', 'systemd-journald', 'systemd-logind', 'systemd-udevd',
    'systemd-oomd', 'systemd-resolved',
    # The session, for the same reason svchost is protected on Windows: these hold real memory
    # so they sort high in a memory list, and ending one does not free anything — it takes the
    # desktop down with every unsaved window on it. The display managers are here because
    # killing them logs the session out immediately.
    'Xorg', 'Xwayland', 'gnome-shell', 'gnome-session-b', 'plasmashell', 'kwin_x11',
    'kwin_wayland', 'mutter', 'sway', 'Hyprland', 'lightdm', 'gdm3', 'gdm', 'sddm'
)

# What is actually holding RAM, grouped by program. Same contract and same reasoning as the
# Windows adapter: grouped because one browser is dozens of processes, and WorkingSet64 —
# which PowerShell maps to RSS on Linux — because that is the resident physical memory.
function Get-ProcessMemoryUsage {
    param([int64]$MinBytes = 536870912)   # 0.5 GB

    $total = 0
    if (Test-Path /proc/meminfo) {
        $mem = Get-Content /proc/meminfo | Where-Object { $_ -match '^MemTotal:\s*(\d+)' } | Select-Object -First 1
        if ($mem -match '(\d+)') { $total = [int64]$matches[1] * 1024 }   # kB -> bytes
    }

    $procs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.WorkingSet64 -gt 0 })
    if (-not $procs) { return @() }

    $out = foreach ($g in ($procs | Group-Object -Property ProcessName)) {
        $bytes = ($g.Group | Measure-Object -Property WorkingSet64 -Sum).Sum
        if ($bytes -lt $MinBytes) { continue }

        $procPids = @($g.Group | Sort-Object WorkingSet64 -Descending | Select-Object -ExpandProperty Id)
        [pscustomobject]@{
            Name      = $g.Name
            Bytes     = [int64]$bytes
            Percent   = if ($total) { [math]::Round(100 * $bytes / $total, 1) } else { 0 }
            Count     = $g.Count
            Pids      = $procPids
            # PID 1 is protected whatever it is called, not just by name.
            Protected = (($g.Name -in $script:PF_ProtectedProcs) -or ($procPids -contains 1))
            IsSelf    = ($procPids -contains $PID)
        }
    }
    return @($out | Sort-Object Bytes -Descending)
}

# One program, expanded into its individual processes. Same contract and same reasoning as the
# Windows adapter: without the command line, eight rows called "java" are indistinguishable.
#
# /proc/<pid>/cmdline is NUL-separated (that is how argv is stored), so the separators are
# turned back into spaces. It is readable for your own processes without root; another user's
# is not, and that is reported rather than shown blank.
function Get-ProcessDetail {
    param([Parameter(Mandatory)][string]$Name)

    # EXACT match, deliberately not `Get-Process -Name $Name`: that parameter is
    # wildcard-enabled, so '*' would return every process and hand a whole-session kill list to
    # the caller. The component refuses patterns too; this keeps the adapter contract exact on
    # its own, and identical to the Windows side.
    $procs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -eq $Name })
    if (-not $procs) { return @() }

    $total = 0
    if (Test-Path /proc/meminfo) {
        $mem = Get-Content /proc/meminfo | Where-Object { $_ -match '^MemTotal:\s*(\d+)' } | Select-Object -First 1
        if ($mem -match '(\d+)') { $total = [int64]$matches[1] * 1024 }
    }

    $out = foreach ($p in $procs) {
        $cmdline = $null
        $f = "/proc/$($p.Id)/cmdline"
        if (Test-Path $f) {
            try {
                $raw = [IO.File]::ReadAllBytes($f)
                if ($raw.Length) { $cmdline = ([Text.Encoding]::UTF8.GetString($raw) -replace "`0", ' ').Trim() }
            } catch { }
        }
        if (-not $cmdline) {
            try { $cmdline = $p.Path } catch { $cmdline = $null }
            # An empty cmdline with a live PID is a kernel thread; say so rather than blank.
            if (-not $cmdline) { $cmdline = '(kernel thread, or owned by another user)' }
        }
        # Computed BEFORE the hashtable: `Key = try {} catch {}` does not parse — try is a
        # statement, not an expression. StartTime/CPU throw for another user's processes.
        $cpu = $null;  try { $cpu = [math]::Round($p.CPU, 0) } catch { }
        $when = $null; try { $when = $p.StartTime }            catch { }

        [pscustomobject]@{
            Pid         = [int]$p.Id
            Name        = $p.ProcessName
            Bytes       = [int64]$p.WorkingSet64
            Percent     = if ($total) { [math]::Round(100 * $p.WorkingSet64 / $total, 1) } else { 0 }
            CpuSeconds  = $cpu
            Started     = $when
            CommandLine = ($cmdline -replace '\s+', ' ').Trim()
            Protected   = (($p.ProcessName -in $script:PF_ProtectedProcs) -or ([int]$p.Id -eq 1))
            IsSelf      = ([int]$p.Id -eq $PID)
        }
    }
    return @($out | Sort-Object Bytes -Descending)
}

# Upgrade headroom from the motherboard, the same SMBIOS records Windows reads — here via
# dmidecode, which means root. Types 8 (port connectors) and 9 (system slots); memory slots
# come from Get-MemoryInfo, which already parses type 17.
function Get-SlotInfo {
    $plain = [pscustomobject]@{ Supported = $false; M2Total = 0; M2Used = 0; SataTotal = 0
                                SataUsed = 0; PcieTotal = 0; PcieFree = 0; MemTotal = 0
                                MemUsed = 0; MemMaxGB = 0 }
    if (-not (Get-Command dmidecode -ErrorAction SilentlyContinue)) { return $plain }

    $raw = if ((id -u) -eq '0') { dmidecode -t 8 -t 9 2>/dev/null }
           elseif (Get-Command sudo -ErrorAction SilentlyContinue) { sudo -n dmidecode -t 8 -t 9 2>/dev/null }
           else { $null }
    if (-not $raw) { return $plain }

    $m2 = 0; $sata = 0; $pcieTotal = 0; $pcieFree = 0
    $desig = $null; $inSlot = $false; $usage = $null
    foreach ($line in @($raw) + @('')) {
        if ($line -match '^(Port Connector Information|System Slot Information)' -or $line -eq '') {
            if ($desig) {
                if ($inSlot) {
                    $pcieTotal++
                    if ($usage -match '(?i)available') { $pcieFree++ }
                } else {
                    if ($desig -match 'M\.?2' -and $desig -notmatch '(?i)wifi|wlan|cnvi|key.?e') { $m2++ }
                    elseif ($desig -match '(?i)sata') {
                        # Vendors label SATA in pairs ("SATA6G_12" = two ports).
                        $tail = ($desig -split '[_-]')[-1]
                        $digits = ($tail -replace '\D', '')
                        $sata += if ($digits.Length -ge 1) { $digits.Length } else { 1 }
                    }
                }
            }
            $desig = $null; $usage = $null
            $inSlot = ($line -match '^System Slot')
            continue
        }
        switch -Regex ($line) {
            '^\s*Internal Reference Designator:\s*(.+)$' { if (-not $desig) { $desig = $matches[1].Trim() } }
            '^\s*Designation:\s*(.+)$'                   { $desig = $matches[1].Trim() }
            '^\s*Current Usage:\s*(.+)$'                 { $usage = $matches[1].Trim() }
        }
    }

    $mem = Get-MemoryInfo
    $disks = @(Get-DiskInfo)
    return [pscustomobject]@{
        Supported = $true
        M2Total   = $m2
        M2Used    = @($disks | Where-Object { $_.Bus -eq 'NVMe' }).Count
        SataTotal = $sata
        SataUsed  = @($disks | Where-Object { $_.Bus -eq 'SATA' }).Count
        PcieTotal = $pcieTotal
        PcieFree  = $pcieFree
        MemTotal  = if ($mem.Detail) { [int]$mem.SlotsTotal } else { 0 }
        MemUsed   = if ($mem.Detail) { [int]$mem.Sticks } else { 0 }
        MemMaxGB  = 0
    }
}

function Get-MachineInfo {
    $cpuName = 'unknown'; $threads = 0; $cores = 0
    if (Test-Path /proc/cpuinfo) {
        $info    = Get-Content /proc/cpuinfo
        $m       = $info | Where-Object { $_ -match '^model name\s*:\s*(.+)$' } | Select-Object -First 1
        # (R)/(TM) are legal boilerplate, stripped here as they are for GPU names.
        if ($m -match ':\s*(.+)$') { $cpuName = ((($matches[1] -replace '\((R|TM)\)', '') -replace '\s+', ' ')).Trim() }
        $threads = @($info | Where-Object { $_ -match '^processor\s*:' }).Count
        $c       = $info | Where-Object { $_ -match '^cpu cores\s*:\s*(\d+)' } | Select-Object -First 1
        $cores   = if ($c -match ':\s*(\d+)') { [int]$matches[1] } else { $threads }
    }

    $ramGB = 0
    if (Test-Path /proc/meminfo) {
        $mem = Get-Content /proc/meminfo | Where-Object { $_ -match '^MemTotal:\s*(\d+)' } | Select-Object -First 1
        if ($mem -match '(\d+)') { $ramGB = [math]::Round([int64]$matches[1] / 1MB) }   # kB -> GB
    }

    [pscustomobject]@{
        CpuName = $cpuName
        Cores   = $cores
        Threads = $threads
        RamGB   = $ramGB
        Memory  = (Get-MemoryInfo)
        Gpus    = (Get-GpuInfo)
        Disks   = (Get-DiskInfo)
        Slots   = (Get-SlotInfo)
        Uptime  = (Get-Uptime)
    }
}

function Get-PowerSnapshot {
    if (-not (Test-Path "$script:PF_CpufreqBase/scaling_governor")) {
        return [pscustomobject]@{
            Supported = $false
            Note      = 'cpufreq is not exposed here (VM or container without CPU frequency control)'
        }
    }

    $governor = (Get-Content "$script:PF_CpufreqBase/scaling_governor" -ErrorAction SilentlyContinue)
    $hwMax    = [int64](Get-Content "$script:PF_CpufreqBase/cpuinfo_max_freq" -ErrorAction SilentlyContinue)
    $curMax   = [int64](Get-Content "$script:PF_CpufreqBase/scaling_max_freq" -ErrorAction SilentlyContinue)
    $pct      = if ($hwMax -gt 0) { [math]::Round($curMax / $hwMax * 100) } else { $null }

    $available = @()
    if (Test-Path "$script:PF_CpufreqBase/scaling_available_governors") {
        $available = @((Get-Content "$script:PF_CpufreqBase/scaling_available_governors") -split '\s+' |
            Where-Object { $_ } | ForEach-Object {
                [pscustomobject]@{ Id = $_; Name = $_; Active = ($_ -eq $governor); IsStock = $true }
            })
    }

    [pscustomobject]@{
        Supported    = $true
        PlanId       = $governor
        PlanName     = "$governor (cpufreq governor)"
        IsStockPlan  = $true      # governors ship with the kernel; there is no OEM-injected governor
        ACMaxPercent = $pct
        DCMaxPercent = $null      # Linux does not split the cap by power source
        HasBattery   = [bool](Get-ChildItem /sys/class/power_supply/BAT* -ErrorAction SilentlyContinue)
        AllPlans     = $available
        Note         = $null
        RealCommand  = "cat $script:PF_CpufreqBase/scaling_max_freq"
    }
}

function Get-StabilityEvents {
    param([int]$Days = 7)

    $notes = @()

    if (-not (Get-Command journalctl -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{
            Supported = $false; Days = $Days
            HardwareErrors = @(); Bugchecks = @(); Dumps = @()
            Notes = @('journalctl is not available — cannot read the kernel log history.')
        }
    }

    # Kernel-ring hardware errors. "cannot read" and "none found" are different facts.
    $kernLines = @(journalctl -k --since "-${Days}d" -p err --no-pager -q 2>/dev/null)
    if ($LASTEXITCODE -ne 0) {
        $notes += 'Could not read the kernel journal (permissions?) — hardware-error count is unknown, not zero.'
        $kernLines = @()
    }
    $mce = @($kernLines | Where-Object { $_ -match 'mce|machine check|hardware error|MCE' } | ForEach-Object {
        [pscustomobject]@{ Time = $null; Id = $null; Summary = $_.Trim() }
    })

    # Previous boot's errors — the "why did it die?" question. Absent when the
    # journal is not persistent (RAM-backed), which is itself worth saying.
    $bugchecks = @()
    $prev = @(journalctl -b -1 -p err --no-pager -q 2>/dev/null | Select-Object -Last 5)
    if ($LASTEXITCODE -eq 0 -and $prev.Count -gt 0) {
        $bugchecks = @($prev | ForEach-Object { [pscustomobject]@{ Time = $null; Id = $null; Summary = $_.Trim() } })
    } elseif ($LASTEXITCODE -ne 0) {
        $notes += 'No previous-boot journal — it is RAM-backed. Persist it: sudo mkdir -p /var/log/journal'
    }

    $dumps = @(Get-ChildItem /var/crash -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | ForEach-Object {
            [pscustomobject]@{ Path = $_.FullName; Time = $_.LastWriteTime; SizeKB = [math]::Round($_.Length / 1KB) }
        })
    if (-not (Test-Path /var/crash)) {
        $notes += 'No /var/crash — no crash-dump facility (kdump/apport) is installed. Absence of dumps is not evidence of health.'
    }

    [pscustomobject]@{
        Supported      = $true
        Days           = $Days
        HardwareErrors = $mce
        Bugchecks      = $bugchecks
        Dumps          = $dumps
        Notes          = $notes
    }
}

function Get-FirmwareInfo {
    # /sys/class/dmi/id is world-readable — no root, no dmidecode needed. Some
    # hypervisors do not populate it; say so rather than invent a version.
    $dmi = '/sys/class/dmi/id'
    if (-not (Test-Path "$dmi/bios_version")) {
        return [pscustomobject]@{ Supported = $false; Note = 'DMI data not exposed by this machine/hypervisor' }
    }

    $read = { param($f) (Get-Content "$dmi/$f" -ErrorAction SilentlyContinue | Select-Object -First 1) }

    # bios_date is typically MM/DD/YYYY
    $date = $null
    $raw  = & $read 'bios_date'
    if ($raw) {
        try { $date = [datetime]::ParseExact($raw, 'MM/dd/yyyy', [Globalization.CultureInfo]::InvariantCulture) }
        catch { try { $date = [datetime]$raw } catch {} }
    }

    [pscustomobject]@{
        Supported   = $true
        BiosVersion = & $read 'bios_version'
        BiosDate    = $date
        BiosVendor  = & $read 'bios_vendor'
        BoardVendor = (Format-HwVendor (& $read 'board_vendor'))
        BoardName   = & $read 'board_name'
        Note        = $null
    }
}

<#
.SYNOPSIS
    Cap every core's scaling_max_freq at a percentage of its hardware max.
.DESCRIPTION
    Needs root (sysfs is root-writable). Resets on reboot — deliberately kept
    that way: a temporary safety cap that self-heals suits the use case better
    than one that persists by accident.
#>
function Set-CpuMaxState {
    param(
        [Parameter(Mandatory)][int]$ACPercent,
        [int]$DCPercent = -1,     # ignored: Linux has one cap, not an AC/DC pair
        [string]$PlanId           # ignored: governors are not the write target
    )

    if (-not (Test-Path "$script:PF_CpufreqBase/cpuinfo_max_freq")) { return $false }

    $hwMax  = [int64](Get-Content "$script:PF_CpufreqBase/cpuinfo_max_freq")
    $target = [int64]($hwMax * $ACPercent / 100)

    $writer = if ((id -u) -eq '0') { @() } else { @('sudo') }
    foreach ($cpu in (Get-ChildItem /sys/devices/system/cpu -Directory -Filter 'cpu[0-9]*')) {
        $f = Join-Path $cpu.FullName 'cpufreq/scaling_max_freq'
        if (Test-Path $f) {
            & sh -c "echo $target | $(($writer + 'tee') -join ' ') '$f' > /dev/null" 2>$null
        }
    }

    # Verify by reading back — the same rule as the Windows side.
    $now = [int64](Get-Content "$script:PF_CpufreqBase/scaling_max_freq" -ErrorAction SilentlyContinue)
    if ($hwMax -le 0) { return $false }
    return ([math]::Round($now / $hwMax * 100) -eq $ACPercent)
}

function Export-StabilityReport {
    param([Parameter(Mandatory)][string]$Directory, [int]$Days = 7)

    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    $written = @()

    if (Get-Command journalctl -ErrorAction SilentlyContinue) {
        $p = Join-Path $Directory 'kernel-errors.txt'
        journalctl -k --since "-${Days}d" -p err --no-pager 2>/dev/null | Set-Content $p
        $written += $p

        $p = Join-Path $Directory 'previous-boot-errors.txt'
        journalctl -b -1 -p err --no-pager 2>/dev/null | Set-Content $p
        $written += $p
    }

    $ev = Get-StabilityEvents -Days $Days
    $p = Join-Path $Directory 'dump-inventory.txt'
    ($ev.Dumps | Format-Table Time, SizeKB, Path -AutoSize | Out-String) | Set-Content $p
    $written += $p

    return $written
}
