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
    return ('{0:N0} GB' -f ($Bytes / 1GB))
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
    -days N              widen the stability window (default 7)
#>
function pc-whoami {
    param(
        [switch]$power,
        [switch]$crashes,
        [switch]$bios,
        [switch]$export,
        [int]$days = 7
    )

    if ($power)   { Show-PowerDetail;                       return }
    if ($crashes) { Show-CrashDetail -Days $days -Export:$export; return }
    if ($bios)    { Show-BiosDetail;                        return }

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
    $sl = $m.Slots
    if ($sl -and $sl.Supported) {
        $storage = @()
        if ($sl.M2Total)   { $storage += "M.2 $($sl.M2Total - $sl.M2Used) of $($sl.M2Total) free" }
        if ($sl.SataTotal) { $storage += "SATA $($sl.SataTotal - $sl.SataUsed) of $($sl.SataTotal) free" }
        if ($storage) { Write-HealthRow 'Bays' ($storage -join ' · ') }

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
Register-PFCommand -Name 'pc-whoami' -Section '🖥️ MACHINE HEALTH' -Synopsis 'vitals: power plan, CPU cap, HW errors, BIOS age' -Example 'pc-whoami -power · -crashes · -bios'
Register-PFCommand -Name 'pc-cap'    -Section '🖥️ MACHINE HEALTH' -Synopsis 'cap CPU speed; prior state recorded for safe undo' -Example 'pc-cap 85 · pc-cap restore'
