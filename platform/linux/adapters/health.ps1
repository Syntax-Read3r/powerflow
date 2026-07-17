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

function Get-MachineInfo {
    $cpuName = 'unknown'; $threads = 0; $cores = 0
    if (Test-Path /proc/cpuinfo) {
        $info    = Get-Content /proc/cpuinfo
        $m       = $info | Where-Object { $_ -match '^model name\s*:\s*(.+)$' } | Select-Object -First 1
        if ($m -match ':\s*(.+)$') { $cpuName = ($matches[1] -replace '\s+', ' ').Trim() }
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
        BoardVendor = & $read 'board_vendor'
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
