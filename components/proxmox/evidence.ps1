# ==============================================================================
# PowerFlow — Proxmox Disk Evidence
# ==============================================================================
# Domain   : Proxmox
# File     : components/proxmox/evidence.ps1
# Purpose  : Disk authenticity reporting and portable evidence bundles
# Functions: Show-PmxEvidence, Write-PmxEvidenceBundle
# Depends  : components/proxmox/shared.ps1, components/proxmox/physical-disks.ps1
# ==============================================================================

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

