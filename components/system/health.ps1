# ==============================================================================
# PowerFlow — System Health
# ==============================================================================
# Domain   : System
# File     : components/system/health.ps1
# Purpose  : pc-whoami — the machine's vital signs on one screen; pc-cap — a CPU
#            cap with guaranteed restoration
# Functions: pc-whoami, pc-cap
# Depends  : platform adapters (health.ps1): Get-MachineInfo, Get-PowerSnapshot,
#            Get-StabilityEvents, Get-FirmwareInfo, Set-CpuMaxState,
#            Export-StabilityReport · elevation adapter: Assert-Admin
#            · Format-Size (components/system/apps.ps1 — loads earlier)
# ==============================================================================
#
# Design rules (docs/plan/pc-whoami/README.md):
#   · Green stays silent; every ⚠️ names the flag that drills in.
#   · No hex, no GUIDs, no provider names — the adapter decodes, this renders.
#   · pc-cap records the prior state to disk BEFORE changing anything, refuses to
#     overwrite an existing record, verifies restore by re-query, and pc-whoami
#     banners for as long as the record exists. An abandoned cap cannot go
#     unnoticed — that failure mode is the reason this feature exists.
# ==============================================================================

$script:PowerStateFile = Join-Path (Get-HomePath) '.powerflow-power-state.json'

# ── shared rendering ──────────────────────────────────────────────────────────
function Write-HealthRow {
    param([string]$Label, [string]$Value, [string]$Warn = $null, [string]$Hint = $null)
    Write-Host ("   {0,-8} " -f $Label) -NoNewline -ForegroundColor DarkGray
    Write-Host $Value -NoNewline -ForegroundColor White
    if ($Warn) { Write-Host "   ⚠️ $Warn" -NoNewline -ForegroundColor Yellow }
    Write-Host ""
    if ($Hint) { Write-Host "            └─ details:  $Hint" -ForegroundColor DarkGray }
}

# Whole-drive sizes, rendered for a one-line summary. Deliberately NOT Format-Size (which
# apps.ps1 owns and installed-apps needs to 2dp): at drive scale "931.51 GB" is noise where
# "932 GB" is the fact, and these rows are already long.
function Format-DriveSize {
    param([int64]$Bytes)
    if ($Bytes -ge 1TB) { return ('{0:N1} TB' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:N0} GB' -f ($Bytes / 1GB)) }
    # The MB branch is not decoration: without it a small device renders as "0 GB" (a 107 MB
    # volume did exactly that). Small drives are still real drives — a USB stick belongs in
    # the list, correctly sized.
    return ('{0:N0} MB' -f ($Bytes / 1MB))
}

function Get-CpuCapRecord {
    if (-not (Test-Path $script:PowerStateFile)) { return $null }
    try { return Get-Content $script:PowerStateFile -Raw | ConvertFrom-Json } catch { return $null }
}

<#
.SYNOPSIS
    pc-whoami — the machine's vital signs, one screen.
.DESCRIPTION
    pc-whoami            the dashboard: CPU, RAM, BIOS age, power plan, CPU cap,
                         hardware errors, crash dumps
    pc-whoami -power     every power plan, caps decoded (no hex, no GUIDs)
    pc-whoami -crashes   hardware errors + bugchecks + dumps  (-export bundles them)
    pc-whoami -bios      firmware version, age, board model
    pc-whoami -ram       programs using 0.5 GB or MORE, by program (read-only)
    pc-whoami --ram      the inverse — programs using LESS than 0.5 GB
    pc-whoami -ram java  that program's processes with command lines — and close one
                         (--ram java works too; a named program shows all its processes)
    -days N              widen the stability window (default 7)
    -min N               -ram threshold in GB (default 0.5)
#>
function pc-whoami {
    param(
        # TWO positional slots, both load-bearing:
        #
        #  position 0  the program name for `-ram java`. Without it "java" bound to the first
        #              bare parameter — [int]$days — and died with "cannot convert to Int32".
        #  position 1  the program name for `--ram java`. PowerShell has no double-dash switch
        #              syntax: it parses `--ram` as the literal STRING "--ram" and hands it to
        #              position 0, which then leaves "java" with nowhere to go ("a positional
        #              parameter cannot be found"). Slot 1 catches it. No process can be called
        #              "--ram", so reading that token as a flag is unambiguous.
        [Parameter(Position = 0)][string]$name,
        [Parameter(Position = 1)][string]$program,
        [switch]$power,
        [switch]$crashes,
        [switch]$bios,
        [switch]$ram,
        [switch]$export,
        [int]$days = 7,
        [double]$min = 0.5
    )

    # `--ram` means "the SMALL ones" — everything under the threshold, the inverse of `-ram`.
    $under = $false
    if ($name -eq '--ram') { $under = $true; $ram = $true; $name = $program; $program = '' }

    # A bare name plainly means "drill into this program" — `pc-whoami java` used to print the
    # whole dashboard and silently ignore the word typed.
    if ($name -and -not ($power -or $crashes -or $bios -or $ram)) { $ram = $true }

    # Two words means an unquoted program name ("Memory Compression" is a real one). Position 1
    # would otherwise swallow the second word and we would report the first as "not running".
    if ($ram -and $name -and $program) {
        Write-Host ""
        Write-Host "❓ Program names with a space need quoting:" -ForegroundColor Yellow
        Write-Host "   pc-whoami -ram `"$name $program`"" -ForegroundColor Cyan
        Write-Host ""
        return
    }

    if ($power)   { Show-PowerDetail;                       return }
    if ($crashes) { Show-CrashDetail -Days $days -Export:$export; return }
    if ($bios)    { Show-BiosDetail;                        return }
    if ($ram)     {
        # A named program shows ALL of its processes either way — the threshold is a property
        # of the overview, not of one program's process list.
        if ($name) { Show-RamProcesses -Name $name } else { Show-RamDetail -MinGB $min -Under:$under }
        return
    }

    $m    = Get-MachineInfo
    $snap = Get-PowerSnapshot
    $fw   = Get-FirmwareInfo
    $ev   = Get-StabilityEvents -Days $days

    Write-Host ""
    Write-Host "🖥️  MACHINE" -ForegroundColor Cyan
    Write-HealthRow 'CPU' "$($m.CpuName) · $($m.Cores)c/$($m.Threads)t"

    # One row PER adapter — a machine legitimately has both an iGPU and a card, and they are
    # different hardware, so they get their own lines rather than being merged or picked
    # between. The label distinguishes them ('iGPU'), which also explains why an integrated
    # chip shows no VRAM: it shares system memory, it is not a fault.
    foreach ($g in @($m.Gpus)) {
        $label = if ($g.Integrated) { 'iGPU' } else { 'GPU' }
        $bits  = @($g.Name)
        if ($g.VramGB -gt 0) { $bits += "$($g.VramGB) GB" }
        Write-HealthRow $label ($bits -join ' · ') $(if (-not $g.Healthy) { 'driver reports a problem' })
    }
    if (-not @($m.Gpus).Count) { Write-HealthRow 'GPU' 'no display adapter detected' }

    # RAM: a spec sheet, not just a number — "32 GB · DDR4-3600 · 4x8GB".
    $mem  = $m.Memory
    if ($mem -and $mem.Detail) {
        $bits = @("$($mem.TotalGB) GB")
        $bits += if ($mem.Type -and $mem.SpeedMTs) { "$($mem.Type)-$($mem.SpeedMTs)" }
                 elseif ($mem.Type)                { $mem.Type }
                 elseif ($mem.SpeedMTs)            { "$($mem.SpeedMTs) MT/s" }
        $bits += $mem.Layout
        # Slot occupancy is NOT repeated here — the dedicated 'Slots' row below owns it.
        # Running slower than the sticks are rated for means XMP/EXPO is off — a real and
        # completely invisible performance loss, so it earns a warning rather than silence.
        $slow = if ($mem.RatedMTs -gt $mem.SpeedMTs -and $mem.SpeedMTs -gt 0) {
            "rated $($mem.RatedMTs) — XMP/EXPO may be off"
        }
        Write-HealthRow 'RAM' (@($bits | Where-Object { $_ }) -join ' · ') $slow
    } else {
        Write-HealthRow 'RAM' "$($m.RamGB) GB" $(if ($mem) { $mem.Note })
    }

    # Storage: one row per physical drive — what it is, how big, how much is left. The
    # interface (NVMe/SATA/USB) and, for a spinning disk, its RPM are what actually separate
    # a modern M.2 from an old 2.5" SATA; Windows leaves the form-factor field blank, so an
    # inferred size is shown only where the bus makes it certain.
    foreach ($d in @($m.Disks)) {
        # Form factor first, so it reads as hardware: "M.2 NVMe SSD", "SATA HDD 7200rpm".
        $spec = @()
        if ($d.FormFactor)            { $spec += $d.FormFactor }
        if ($d.Bus)                   { $spec += $d.Bus }
        if ($d.Media -ne 'unknown')   { $spec += $d.Media }
        if ($d.Rpm)                   { $spec += "$($d.Rpm)rpm" }

        $bits = @($d.Name, (Format-DriveSize $d.SizeBytes), ($spec -join ' '))
        if ($d.FreeBytes -gt 0) {
            $bits += "$(Format-DriveSize $d.FreeBytes) free$(if ($d.Letters) { " on $($d.Letters)" })"
        }
        if ($d.External) { $bits += 'external' }

        # A nearly-full drive is a genuine vital, and PowerFlow already has the tool for it.
        $warn = $null; $hint = $null
        if ($d.SizeBytes -gt 0 -and $d.FreeBytes -gt 0) {
            $pct = [math]::Round(100 * $d.FreeBytes / $d.SizeBytes)
            if ($pct -le 10) { $warn = "only $pct% free"; $hint = 'installed-apps 1gb-5gb' }
        }
        if (-not $d.Healthy) { $warn = 'the drive reports a health problem' }
        Write-HealthRow 'Disk' ($bits -join ' · ') $warn $hint
    }

    # Upgrade headroom, read from the motherboard's own SMBIOS records rather than guessed.
    #
    # The label is 'Ports', NOT 'Bays' — this counts connectors ON THE BOARD, and a bay is a
    # mounting position in the CASE. Calling it Bays read as "6 places I can put a drive",
    # which the board cannot promise: you also need a free bay and a spare PSU lead. Two
    # further limits SMBIOS cannot express, so we do not imply them away: many boards MUX
    # M.2 against specific SATA ports (populating an M.2 can switch a SATA port off), and the
    # declared connectors are what physically exist, not what is currently enabled.
    $sl = $m.Slots
    if ($sl -and $sl.Supported) {
        $storage = @()
        if ($sl.M2Total)   { $storage += "M.2 $($sl.M2Total - $sl.M2Used) of $($sl.M2Total) free" }
        if ($sl.SataTotal) { $storage += "SATA $($sl.SataTotal - $sl.SataUsed) of $($sl.SataTotal) free" }
        if ($storage) { Write-HealthRow 'Ports' ($storage -join ' · ') }

        $exp = @()
        if ($sl.PcieTotal) { $exp += "PCIe $($sl.PcieFree) of $($sl.PcieTotal) free" }
        if ($sl.MemTotal)  {
            $memFree = $sl.MemTotal - $sl.MemUsed
            $exp += "RAM $memFree of $($sl.MemTotal) slots free" + $(if ($sl.MemMaxGB) { " (max $($sl.MemMaxGB) GB)" })
        }
        if ($exp) { Write-HealthRow 'Slots' ($exp -join ' · ') }
    }

    # Motherboard. Get-FirmwareInfo has carried the board vendor/model since v3.4.0 — it was
    # simply never rendered, so pc-whoami could tell you your BIOS version without telling
    # you which board it was for.
    if ($fw.Supported -and ($fw.BoardVendor -or $fw.BoardName)) {
        Write-HealthRow 'Board' ((@($fw.BoardVendor, $fw.BoardName) | Where-Object { $_ }) -join ' ')
    }

    if ($fw.Supported) {
        $dateStr = if ($fw.BiosDate) { $fw.BiosDate.ToString('yyyy-MM-dd') } else { 'date unknown' }
        $ageWarn = $null
        if ($fw.BiosDate) {
            $years = [math]::Floor(((Get-Date) - $fw.BiosDate).TotalDays / 365)
            if ($years -ge 2) { $ageWarn = "over $years years old" }
        }
        Write-HealthRow 'BIOS' "$($fw.BiosVersion) ($dateStr)" $ageWarn $(if ($ageWarn) { 'pc-whoami -bios' })
    } else {
        Write-HealthRow 'BIOS' $fw.Note
    }

    # Uptime last: it is the one line here that is state rather than hardware. (It used to
    # share the RAM row, which no longer fits now that RAM carries type/speed/layout.)
    $up = $m.Uptime
    Write-HealthRow 'Up' ("{0}d {1}h" -f $up.Days, $up.Hours)

    Write-Host ""
    Write-Host "🔌 POWER" -ForegroundColor Cyan
    if ($snap.Supported) {
        $planWarn = if (-not $snap.IsStockPlan) { 'custom/OEM plan — not a system default' }
        Write-HealthRow 'Plan' $snap.PlanName $planWarn $(if ($planWarn) { 'pc-whoami -power' })

        # A desktop has no battery, so the DC number is noise — show it only when
        # there is a battery for it to apply to.
        $capStr = if ($snap.HasBattery -and $null -ne $snap.DCMaxPercent) {
            "$($snap.ACMaxPercent)% on AC · $($snap.DCMaxPercent)% on battery"
        } else { "$($snap.ACMaxPercent)%" }
        $capWarn = if ($snap.ACMaxPercent -lt 100) { 'full speed is being withheld' }
        Write-HealthRow 'CPU cap' $capStr $capWarn $(if ($capWarn) { 'pc-whoami -power' })
    } else {
        Write-HealthRow 'Plan' $snap.Note
    }

    $rec = Get-CpuCapRecord
    if ($rec) {
        Write-Host ""
        Write-Host "   ⚠️  CPU capped at $($rec.cappedTo)% by pc-cap on $([datetime]$rec.savedAt | Get-Date -Format 'MMM d')" -ForegroundColor Yellow
        Write-Host "      undo:  pc-cap restore" -ForegroundColor Cyan
    }

    Write-Host ""
    Write-Host "💥 STABILITY (last $($ev.Days) days)" -ForegroundColor Cyan
    if ($ev.Supported) {
        $hwCount = $ev.HardwareErrors.Count
        $hwWarn  = if ($hwCount -gt 0) { 'the hardware itself reported faults' }
        Write-HealthRow 'HW errors' "$hwCount" $hwWarn $(if ($hwWarn) { 'pc-whoami -crashes' })

        if ($ev.Dumps.Count -gt 0) {
            Write-HealthRow 'Dumps' "$($ev.Dumps.Count) · newest $($ev.Dumps[0].Time.ToString('MMM d'))" 'the OS crashed hard enough to write these' 'pc-whoami -crashes'
        } else {
            Write-HealthRow 'Dumps' 'none'
        }
        foreach ($n in $ev.Notes) { Write-Host "   ℹ️  $n" -ForegroundColor DarkGray }
    } else {
        foreach ($n in $ev.Notes) { Write-HealthRow 'Events' $n }
    }
    Write-Host ""
}

function Show-PowerDetail {
    $snap = Get-PowerSnapshot
    Write-Host ""
    if (-not $snap.Supported) {
        Write-Host "❌ $($snap.Note)" -ForegroundColor Red
        Write-Host ""
        return
    }

    Write-Host "🔌 POWER PLANS" -ForegroundColor Cyan
    foreach ($p in $snap.AllPlans) {
        $mark  = if ($p.Active) { '▶' } else { ' ' }
        $badge = if (-not $p.IsStock) { '  ⚠️ custom/OEM' } else { '' }
        Write-Host " $mark $($p.Name)$badge" -ForegroundColor $(if ($p.Active) { 'Green' } else { 'White' })
    }

    Write-Host ""
    Write-Host "   Maximum processor state (the CPU cap):" -ForegroundColor DarkGray
    Write-Host "     plugged in : " -NoNewline -ForegroundColor DarkGray
    Write-Host "$($snap.ACMaxPercent)%" -ForegroundColor $(if ($snap.ACMaxPercent -lt 100) { 'Yellow' } else { 'Green' })
    if ($snap.HasBattery -and $null -ne $snap.DCMaxPercent) {
        Write-Host "     on battery : " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($snap.DCMaxPercent)%" -ForegroundColor $(if ($snap.DCMaxPercent -lt 100) { 'Yellow' } else { 'Green' })
    }
    if ($snap.ACMaxPercent -lt 100) {
        Write-Host ""
        Write-Host "   ⚠️  A cap below 100% means the CPU is never allowed full speed." -ForegroundColor Yellow
        $rec = Get-CpuCapRecord
        if ($rec) { Write-Host "      This one is pc-cap's — undo it with:  pc-cap restore" -ForegroundColor Cyan }
        else      { Write-Host "      PowerFlow did not set this — a power plan, OEM tool, or script did." -ForegroundColor DarkGray }
    }

    if ((Get-LessonMode) -ne 'off' -and $snap.RealCommand) {
        Write-Host ""
        Write-Host "  🐧 real command: " -NoNewline -ForegroundColor DarkGray
        Write-Host $snap.RealCommand -ForegroundColor Cyan
    }
    Write-Host ""
}

function Show-CrashDetail {
    param([int]$Days = 7, [switch]$Export)

    $ev = Get-StabilityEvents -Days $Days
    Write-Host ""
    Write-Host "💥 STABILITY — last $Days days" -ForegroundColor Cyan

    if (-not $ev.Supported) {
        foreach ($n in $ev.Notes) { Write-Host "   ❌ $n" -ForegroundColor Red }
        Write-Host ""
        return
    }

    Write-Host ""
    Write-Host "   Hardware errors: $($ev.HardwareErrors.Count)" -ForegroundColor $(if ($ev.HardwareErrors.Count) { 'Yellow' } else { 'Green' })
    foreach ($e in ($ev.HardwareErrors | Select-Object -First 5)) {
        $t = if ($e.Time) { $e.Time.ToString('MMM d HH:mm') + '  ' } else { '' }
        Write-Host "     $t$($e.Summary)" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "   Crashes / previous boot: $($ev.Bugchecks.Count)" -ForegroundColor $(if ($ev.Bugchecks.Count) { 'Yellow' } else { 'Green' })
    foreach ($e in ($ev.Bugchecks | Select-Object -First 3)) {
        $t = if ($e.Time) { $e.Time.ToString('MMM d HH:mm') + '  ' } else { '' }
        Write-Host "     $t$($e.Summary)" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "   Dump files: $($ev.Dumps.Count)" -ForegroundColor $(if ($ev.Dumps.Count) { 'Yellow' } else { 'Green' })
    foreach ($d in ($ev.Dumps | Select-Object -First 5)) {
        Write-Host "     $($d.Time.ToString('MMM d HH:mm'))  $([math]::Round($d.SizeKB/1KB,1)) MB  $($d.Path)" -ForegroundColor DarkGray
    }

    foreach ($n in $ev.Notes) { Write-Host "   ℹ️  $n" -ForegroundColor DarkGray }

    if ($Export) {
        $dir   = Join-Path (Get-HomePath) 'Desktop'
        if (-not (Test-Path $dir)) { $dir = Get-HomePath }   # headless boxes have no Desktop
        $dir   = Join-Path $dir 'pc-crash-report'
        $files = Export-StabilityReport -Directory $dir -Days $Days
        Write-Host ""
        Write-Host "   📦 Evidence bundle written — hand this folder to whoever is helping you:" -ForegroundColor Green
        foreach ($f in $files) { Write-Host "      $f" -ForegroundColor DarkGray }
    } else {
        Write-Host ""
        Write-Host "   💡 pc-whoami -crashes -export   writes the raw evidence to a folder" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# pc-whoami -ram — what is actually holding memory. READ-ONLY, on purpose.
#
# Grouped by program, because one browser is dozens of processes: per-PID rows would show
# "chrome 180 MB" forty times and bury the 7 GB answer.
#
# Nothing can be killed from here. An earlier build let you close a whole group, which meant
# one keystroke ended 48 VS Code processes — far too blunt an action to sit against a list
# this long. Killing lives in `pc-whoami -ram <name>`, where the scope is one program, every
# process is shown with its command line, and exactly one PID goes at a time.
function Show-RamDetail {
    param([double]$MinGB = 0.5, [switch]$Under)

    $minBytes = [int64]($MinGB * 1GB)
    $mem  = (Get-MachineInfo).Memory

    if ($Under) {
        # Everything BELOW the bar. Asking the adapter for a 1-byte floor and filtering here
        # keeps one code path in the adapter; the floor of 1 also drops the zero-memory rows.
        $rows = @(Get-ProcessMemoryUsage -MinBytes 1 | Where-Object { $_.Bytes -lt $minBytes })
    } else {
        $rows = @(Get-ProcessMemoryUsage -MinBytes $minBytes)
    }

    $headline = if ($Under) { "programs using LESS than $MinGB GB" } else { "programs using $MinGB GB or more" }
    Write-Host ""
    Write-Host "🧠 MEMORY — $headline" -ForegroundColor Cyan
    Write-Host ""

    if (-not $rows.Count) {
        if ($Under) {
            Write-Host "   ✨ Everything running is using $MinGB GB or more." -ForegroundColor Green
            Write-Host "   pc-whoami -ram   shows them" -ForegroundColor DarkGray
        } else {
            Write-Host "   ✨ Nothing is using $MinGB GB or more." -ForegroundColor Green
            Write-Host "   pc-whoami --ram  shows what is below the bar" -ForegroundColor DarkGray
        }
        Write-Host ""
        return
    }

    # The under-the-bar list is long by nature (small programs are numerous). Biggest-first and
    # capped, with the remainder counted rather than silently dropped.
    $shown = $rows
    $hidden = 0
    if ($Under -and $rows.Count -gt 25) {
        $shown  = $rows | Select-Object -First 25
        $hidden = $rows.Count - 25
    }

    $w = ($shown.Name | Measure-Object -Maximum Length).Maximum + 2
    foreach ($r in $shown) {
        Write-Host ("   {0}" -f $r.Name.PadRight($w)) -NoNewline -ForegroundColor White
        Write-Host ("{0,9}" -f (Format-DriveSize $r.Bytes)) -NoNewline -ForegroundColor Yellow
        Write-Host ("{0,7}%" -f $r.Percent) -NoNewline -ForegroundColor DarkGray
        if ($r.Count -gt 1) { Write-Host ("   {0} processes" -f $r.Count) -NoNewline -ForegroundColor DarkGray }
        if ($r.Protected)   { Write-Host "   🔒 system-critical" -NoNewline -ForegroundColor DarkYellow }
        if ($r.IsSelf)      { Write-Host "   ← this shell" -NoNewline -ForegroundColor DarkCyan }
        Write-Host ""
    }

    $sum = ($rows | Measure-Object -Property Bytes -Sum).Sum
    Write-Host ""
    if ($hidden) { Write-Host "   …and $hidden more below $MinGB GB" -ForegroundColor DarkGray }
    Write-Host ("   Listed: {0} of {1} GB installed" -f (Format-DriveSize $sum), $mem.TotalGB) -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "   💡 pc-whoami -ram <name>   see that program's individual processes, and close one" -ForegroundColor DarkGray
    Write-Host "      e.g.  pc-whoami -ram $($rows[0].Name)" -ForegroundColor DarkGray
    if (-not $Under) { Write-Host "      pc-whoami --ram          the small ones, below $MinGB GB" -ForegroundColor DarkGray }
    Write-Host ""
}

# ── one program, expanded ─────────────────────────────────────────────────────
# This is the ONLY place a process can be killed.
#
# The overview deliberately cannot: its rows are whole programs, and "close Code" there would
# have ended 48 processes on one keystroke — too blunt to offer against a list that long. Here
# the scope is one named program, every process is shown with its command line, and the kill
# takes exactly one PID. You have to know what you are ending before you can end it.
function Show-RamProcesses {
    param([Parameter(Mandatory)][string]$Name)

    # PATTERNS ARE REFUSED, and this guard is the most important line in the file.
    #
    # Get-Process -Name is wildcard-enabled, so `pc-whoami -ram *` listed all 529 processes on
    # this machine — 428 of them killable, including explorer, dwm and the terminal itself.
    # ctrl-a would then have offered to end all of them behind a confirmation of "type the
    # program name", where the program name IS '*' — a single asterisk, the same character
    # just typed as the argument. That silently converts "scoped to one named program" into
    # "the whole session", which is the exact invariant this feature is built on.
    if ($Name -match '[\*\?\[\]]') {
        Write-Host ""
        Write-Host "🔒 pc-whoami -ram takes ONE program name, not a pattern." -ForegroundColor Red
        Write-Host "   '$Name' would match many programs at once, and closing a match set is" -ForegroundColor DarkGray
        Write-Host "   not something a single confirmation can meaningfully authorise." -ForegroundColor DarkGray
        Write-Host "   Name the program:  pc-whoami -ram java" -ForegroundColor DarkGray
        Write-Host "   Or see everything: pc-whoami -ram   ·   pc-whoami --ram" -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    $procs = @(Get-ProcessDetail -Name $Name)
    Write-Host ""
    if (-not $procs.Count) {
        Write-Host "🧠 Nothing called '$Name' is running." -ForegroundColor Yellow
        Write-Host "   pc-whoami -ram   lists what is actually using memory" -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    $sum = ($procs | Measure-Object -Property Bytes -Sum).Sum
    Write-Host "🧠 $Name — $($procs.Count) process$(if ($procs.Count -ne 1) { 'es' }) · $(Format-DriveSize $sum) total" -ForegroundColor Cyan
    Write-Host ""

    foreach ($p in $procs) {
        Write-Host ("   {0,-8}" -f $p.Pid) -NoNewline -ForegroundColor Green
        Write-Host ("{0,9}" -f (Format-DriveSize $p.Bytes)) -NoNewline -ForegroundColor Yellow
        Write-Host ("{0,6}%" -f $p.Percent) -NoNewline -ForegroundColor DarkGray
        if ($null -ne $p.Started) {
            Write-Host ("   up {0}" -f (Format-RamAge ((Get-Date) - $p.Started))) -NoNewline -ForegroundColor DarkGray
        }
        if ($p.Protected) { Write-Host "   🔒" -NoNewline -ForegroundColor DarkYellow }
        if ($p.IsSelf)    { Write-Host "   ← this shell" -NoNewline -ForegroundColor DarkCyan }
        Write-Host ""
        # The command line is the reason this view exists — it is what tells eight javas apart.
        Write-Host ("            {0}" -f (Format-RamTrim $p.CommandLine 150)) -ForegroundColor DarkGray
    }

    $interactive = -not [Console]::IsOutputRedirected -and -not [Console]::IsInputRedirected `
                   -and (Get-Command fzf -ErrorAction SilentlyContinue)
    if (-not $interactive) {
        Write-Host ""
        Write-Host "   (run this in a terminal with fzf to close one of these)" -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    Write-Host ""
    # The header must count what ctrl-a will ACTUALLY close, not how many rows are on screen:
    # Stop-RamGroup filters out protected processes and this shell, so "closes ALL 8" was a
    # promise the action would not keep when two of the eight are untouchable.
    $killable = @($procs | Where-Object { -not $_.Protected -and -not $_.IsSelf })
    $lines = $procs | ForEach-Object {
        $tag = if ($_.Protected) { ' [system-critical]' } elseif ($_.IsSelf) { ' [this shell]' } else { '' }
        # Tag FIRST so it cannot fall off the right edge behind a long command line.
        "{0}`t{1,-8} {2,9} {3} {4}" -f $procs.IndexOf($_), $_.Pid, (Format-DriveSize $_.Bytes),
                                       $tag.PadRight(18), (Format-RamTrim $_.CommandLine 150)
    }
    $groupOffer = if ($killable.Count -eq $procs.Count) { "ctrl-a closes all $($procs.Count)" }
                  elseif ($killable.Count)              { "ctrl-a closes $($killable.Count) of $($procs.Count) (system-critical and this shell stay)" }
                  else                                  { "nothing here can be closed" }
    # --expect gives one picker two verbs: close this process, or close the whole program.
    # Killing the group is only offered HERE, where you have already seen every process and
    # its command line — the same action from the overview would have been blind.
    # --expect is passed UNCONDITIONALLY: without it fzf prints one line instead of two, and the
    # $sel[0]=key / $sel[1]=row parsing below would silently read the row as the key. When
    # nothing is killable the header says so and Stop-RamGroup refuses.
    $sel = $lines | fzf --delimiter "`t" --with-nth 2 --expect=ctrl-a `
        --reverse --border=rounded --height=60% `
        --prompt="🧠 $Name : " `
        --header="Enter closes the selected PROCESS · $groupOffer · Esc leaves everything running" `
        --header-first --color="header:bold:cyan,prompt:bold:green,border:cyan"

    if (-not $sel) { Write-Host "   Nothing closed." -ForegroundColor DarkGray; Write-Host ""; return }
    $key = @($sel)[0]           # '' for Enter, 'ctrl-a' for the group
    $row = @($sel)[1]
    if (-not $row) { Write-Host "   Nothing closed." -ForegroundColor DarkGray; Write-Host ""; return }

    if ($key -eq 'ctrl-a') { Stop-RamGroup -Name $Name -Processes $procs }
    else                   { Stop-RamProcess -Process $procs[[int](($row -split "`t")[0])] }
}

# Kill EVERY process of one program. Offered only from the drill-in, and warned harder than a
# single kill because the blast radius is the whole application: closing all of Code or java
# loses unsaved work everywhere at once, not in one window.
function Stop-RamGroup {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)]$Processes)

    # The two refusals still apply, but per-process: the group is filtered rather than
    # rejected, so "close all pwsh" closes the other shells and leaves yours running.
    $skipProtected = @($Processes | Where-Object Protected)
    $skipSelf      = @($Processes | Where-Object { $_.IsSelf -and -not $_.Protected })
    $targets       = @($Processes | Where-Object { -not $_.Protected -and -not $_.IsSelf })

    Write-Host ""
    if (-not $targets.Count) {
        Write-Host "🔒 Nothing in '$Name' can be closed — every process is system-critical or is this shell." -ForegroundColor Red
        Write-Host ""
        return
    }

    $sum = ($targets | Measure-Object -Property Bytes -Sum).Sum
    Write-Host "🗑️  Close ALL $($targets.Count) '$Name' process$(if ($targets.Count -ne 1) { 'es' })?" -ForegroundColor Yellow
    Write-Host "    $(Format-DriveSize $sum) · PIDs $(($targets.Pid | Select-Object -First 12) -join ', ')$(if ($targets.Count -gt 12) { ', …' })" -ForegroundColor DarkGray
    Write-Host "    ⚠️  This ends the WHOLE program. Unsaved work in every one of these is lost." -ForegroundColor Red
    foreach ($s in $skipProtected) { Write-Host "    🔒 PID $($s.Pid) is system-critical and will be left running." -ForegroundColor DarkYellow }
    foreach ($s in $skipSelf)      { Write-Host "    ← PID $($s.Pid) is this shell and will be left running." -ForegroundColor DarkCyan }

    if ((Read-Host "    Type the program name to confirm") -ne $Name) {
        Write-Host "❌ Nothing closed." -ForegroundColor Yellow; Write-Host ""; return
    }

    # Per-PID reporting: a group genuinely can partially fail — a process may exit on its own
    # between listing and killing, or belong to another user. "Closed 6 of 8" is the truth.
    #
    # $freed accumulates only what was ACTUALLY closed. Reporting $sum here would claim the
    # whole group's memory back even when half the kills failed.
    $killed = 0; $freed = 0; $failed = @()
    foreach ($p in $targets) {
        # Same identity re-check as the single kill — this loop runs after the prompt.
        if (-not (Test-RamStillSame -Row $p)) { $failed += "$($p.Pid) (exited before we got there)"; continue }
        try { Stop-Process -Id $p.Pid -Force -ErrorAction Stop; $killed++; $freed += $p.Bytes }
        catch { $failed += "$($p.Pid) ($($_.Exception.Message -replace '\s+', ' '))" }
    }

    if ($killed) { Write-Host "✅ Closed $killed of $($targets.Count) — $(Format-DriveSize $freed) should return." -ForegroundColor Green }
    foreach ($f in $failed) { Write-Host "   ⚠️  could not close PID $f" -ForegroundColor Yellow }
    if (-not $killed) { Write-Host "❌ Nothing was closed." -ForegroundColor Red }
    Write-Host ""
}

function Format-RamAge {
    param([TimeSpan]$Span)
    # Floor, not [int]: [int] ROUNDS, so 1d 18h printed as "2d 18h" — an uptime that reads
    # older than it is. A negative span (clock skew) is not a duration worth showing.
    if ($Span.Ticks -lt 0)      { return '' }
    if ($Span.TotalDays -ge 1)  { return ('{0}d {1}h' -f [int][math]::Floor($Span.TotalDays), $Span.Hours) }
    if ($Span.TotalHours -ge 1) { return ('{0}h {1}m' -f [int][math]::Floor($Span.TotalHours), $Span.Minutes) }
    return ('{0}m' -f [int][math]::Floor($Span.TotalMinutes))
}

# Trim from the MIDDLE, keeping both ends.
#
# Head-truncation defeated the entire point of the drill-in: java command lines share a long
# identical prefix (the JVM path and -classpath blob), so cutting the tail rendered eight
# genuinely different processes as eight byte-identical rows — in exactly the case this view
# exists to solve. The distinguishing part (the jar, the main class, the port) lives at the END.
function Format-RamTrim {
    param([string]$Text, [int]$Max = 120)
    if (-not $Text) { return '' }
    if ($Max -lt 8) { $Max = 8 }              # below this a middle-ellipsis says nothing
    if ($Text.Length -le $Max) { return $Text }
    $head = [int]($Max * 0.45)
    $tail = $Max - $head - 1
    return $Text.Substring(0, $head) + '…' + $Text.Substring($Text.Length - $tail)
}

# Is the PID still the process we listed?
#
# Rows are captured before the picker and before the confirmation prompt — seconds can pass. If
# the listed process exits in that window and the OS reuses its number, `Stop-Process -Id` would
# force-kill an unrelated program. Name plus start time settles it: a recycled PID never has the
# original's start time. StartTime throws for some other-user processes, hence the guard.
function Test-RamStillSame {
    param([Parameter(Mandatory)]$Row)
    $live = Get-Process -Id $Row.Pid -ErrorAction SilentlyContinue
    if (-not $live) { return $false }
    if ($live.ProcessName -ne $Row.Name) { return $false }
    if ($null -ne $Row.Started) {
        try { if ($live.StartTime -ne $Row.Started) { return $false } } catch { }
    }
    return $true
}

# Kill ONE process, with the two refusals that matter and a confirmation naming the cost.
function Stop-RamProcess {
    param([Parameter(Mandatory)]$Process)

    Write-Host ""
    if ($Process.Protected) {
        Write-Host "🔒 '$($Process.Name)' is a system-critical process — PowerFlow will not kill it." -ForegroundColor Red
        Write-Host "   Ending it would take the machine down instantly, not free memory." -ForegroundColor DarkGray
        Write-Host ""
        return
    }
    if ($Process.IsSelf) {
        Write-Host "🛑 That is the shell you are typing in — closing it would end this session." -ForegroundColor Red
        Write-Host ""
        return
    }

    Write-Host "🗑️  Close PID $($Process.Pid) ($($Process.Name))?" -ForegroundColor Yellow
    Write-Host "    $(Format-DriveSize $Process.Bytes) · $(Format-RamTrim $Process.CommandLine 150)" -ForegroundColor DarkGray
    Write-Host "    ⚠️  This is a kill, not a polite close — unsaved work in it is lost." -ForegroundColor Red
    # The PID is the confirmation: it is specific to the one process being ended, where a
    # program name would be equally true of the seven others left running.
    if ((Read-Host "    Type the PID to confirm") -ne "$($Process.Pid)") {
        Write-Host "❌ Nothing closed." -ForegroundColor Yellow; Write-Host ""; return
    }

    # Re-check identity AFTER the prompt: the process may have exited while it was on screen,
    # and killing a recycled PID would hit something the user never saw.
    if (-not (Test-RamStillSame -Row $Process)) {
        Write-Host "⏭️  PID $($Process.Pid) is no longer that process — it exited. Nothing closed." -ForegroundColor Yellow
        Write-Host ""; return
    }

    try {
        Stop-Process -Id $Process.Pid -Force -ErrorAction Stop
        Write-Host "✅ Closed PID $($Process.Pid) — $(Format-DriveSize $Process.Bytes) should return." -ForegroundColor Green
    } catch {
        Write-Host "❌ Could not close PID $($Process.Pid): $($_.Exception.Message -replace '\s+', ' ')" -ForegroundColor Red
    }
    Write-Host ""
}

function Show-BiosDetail {
    $fw = Get-FirmwareInfo
    Write-Host ""
    if (-not $fw.Supported) {
        Write-Host "❌ $($fw.Note)" -ForegroundColor Red
        Write-Host ""
        return
    }

    Write-Host "🧬 FIRMWARE" -ForegroundColor Cyan
    Write-HealthRow 'Version' "$($fw.BiosVersion)  ($($fw.BiosVendor))"
    if ($fw.BiosDate) {
        $years = [math]::Round(((Get-Date) - $fw.BiosDate).TotalDays / 365, 1)
        Write-HealthRow 'Date' $fw.BiosDate.ToString('yyyy-MM-dd') $(if ($years -ge 2) { "$years years old" })
    }
    Write-HealthRow 'Board' "$($fw.BoardVendor) $($fw.BoardName)"
    Write-Host ""
    # Deliberately NOT auto-checking vendor sites — scraping ASUS/MSI pages is
    # fragile and puts a network call in a diagnostic tool. Hand over the search.
    Write-Host "   💡 To check for updates, search:  " -NoNewline -ForegroundColor DarkGray
    Write-Host "$($fw.BoardVendor) $($fw.BoardName) BIOS" -ForegroundColor Cyan
    Write-Host ""
}

<#
.SYNOPSIS
    pc-cap — cap the CPU's maximum speed, with guaranteed restoration.
.DESCRIPTION
    pc-cap             show the current cap and any active pc-cap record
    pc-cap 85          cap at 85% — records the prior state to disk FIRST
    pc-cap restore     put back exactly what was recorded, verify, then forget

    The record is ~/.powerflow-power-state.json. While it exists, pc-whoami
    shows a banner — an abandoned cap cannot go unnoticed.
#>
function pc-cap {
    param([string]$Value)

    $rec = Get-CpuCapRecord

    # ── show ──────────────────────────────────────────────────────────────────
    if (-not $Value) {
        $snap = Get-PowerSnapshot
        Write-Host ""
        if (-not $snap.Supported) { Write-Host "❌ $($snap.Note)" -ForegroundColor Red; Write-Host ""; return }
        Write-Host "🔌 CPU cap: " -NoNewline -ForegroundColor Cyan
        Write-Host "$($snap.ACMaxPercent)%" -ForegroundColor $(if ($snap.ACMaxPercent -lt 100) { 'Yellow' } else { 'Green' })
        if ($rec) {
            Write-Host "   pc-cap set this on $([datetime]$rec.savedAt | Get-Date -Format 'MMM d HH:mm') — before that it was $($rec.acMax)%" -ForegroundColor Yellow
            Write-Host "   undo:  pc-cap restore" -ForegroundColor Cyan
        } else {
            Write-Host "   usage:  pc-cap 85   ·   pc-cap restore" -ForegroundColor DarkGray
        }
        Write-Host ""
        return
    }

    # ── restore ───────────────────────────────────────────────────────────────
    if ($Value -eq 'restore') {
        if (-not $rec) {
            Write-Host "ℹ️  Nothing to restore — pc-cap has no active record." -ForegroundColor DarkGray
            return
        }
        # Assert-Admin RETURNS $false (it does not throw) — the result must gate the action.
        if (-not (Assert-Admin "Restoring the CPU cap")) { return }

        $dc = if ($null -ne $rec.dcMax) { [int]$rec.dcMax } else { -1 }
        $ok = Set-CpuMaxState -ACPercent ([int]$rec.acMax) -DCPercent $dc -PlanId $rec.planId

        if ($ok) {
            # Forget the record ONLY after the re-query agreed. A restore that did
            # not verifiably happen must stay visible — that is the entire point.
            Remove-Item $script:PowerStateFile -Force
            Write-Host "✅ Restored: CPU cap back to $($rec.acMax)% on '$($rec.planName)'" -ForegroundColor Green
        } else {
            Write-Host "❌ Restore did not verify — the record is KEPT so nothing is lost." -ForegroundColor Red
            Write-Host "   Your original values: AC $($rec.acMax)%$(if ($null -ne $rec.dcMax) { `" · DC $($rec.dcMax)%`" }) on plan '$($rec.planName)'" -ForegroundColor DarkGray
        }
        return
    }

    # ── set ───────────────────────────────────────────────────────────────────
    $pct = 0
    if (-not [int]::TryParse($Value, [ref]$pct) -or $pct -lt 5 -or $pct -gt 100) {
        Write-Host "❌ pc-cap takes a percentage between 5 and 100, or 'restore' — got '$Value'" -ForegroundColor Red
        return
    }

    if ($rec) {
        # 100 → 85 → 70 must not make "restore" mean 85. The first record holds
        # the true original; refuse to bury it.
        Write-Host "❌ A pc-cap record already exists (prior state: $($rec.acMax)%, saved $([datetime]$rec.savedAt | Get-Date -Format 'MMM d'))." -ForegroundColor Red
        Write-Host "   Restore it first:  pc-cap restore" -ForegroundColor Cyan
        return
    }

    if (-not (Assert-Admin "Capping the CPU")) { return }

    $snap = Get-PowerSnapshot
    if (-not $snap.Supported) { Write-Host "❌ $($snap.Note)" -ForegroundColor Red; return }

    # THE ORDER IS THE FEATURE: record first, change second. If anything dies
    # between these two steps, the truth is already on disk.
    @{
        savedAt  = (Get-Date).ToString('o')
        planId   = $snap.PlanId
        planName = $snap.PlanName
        acMax    = $snap.ACMaxPercent
        dcMax    = $snap.DCMaxPercent
        cappedTo = $pct
        reason   = "pc-cap $pct"
    } | ConvertTo-Json | Set-Content $script:PowerStateFile

    $dc = if ($null -ne $snap.DCMaxPercent) { $pct } else { -1 }
    $ok = Set-CpuMaxState -ACPercent $pct -DCPercent $dc

    if ($ok) {
        Write-Host "✅ CPU capped at $pct%  (was $($snap.ACMaxPercent)%)" -ForegroundColor Green
        Write-Host "   Undo any time:  pc-cap restore" -ForegroundColor Cyan
        Write-Host "   pc-whoami will show a banner until you do." -ForegroundColor DarkGray
    } else {
        Write-Host "⚠️  Could not verify the cap was applied." -ForegroundColor Yellow
        Write-Host "   Your prior state IS recorded ($($snap.ACMaxPercent)%) — 'pc-cap restore' remains safe." -ForegroundColor DarkGray
    }
}

# ── pwsh-h registration ───────────────────────────────────────────────────────
Register-PFCommand -Name 'pc-whoami' -Section '🖥️ MACHINE HEALTH' -Synopsis 'vitals: CPU, GPU, RAM, drives, BIOS age, power, errors' -Example 'pc-whoami -ram · -power · -crashes · -bios'
Register-PFCommand -Name 'pc-cap'    -Section '🖥️ MACHINE HEALTH' -Synopsis 'cap CPU speed; prior state recorded for safe undo' -Example 'pc-cap 85 · pc-cap restore'
