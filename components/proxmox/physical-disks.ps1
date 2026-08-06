# ==============================================================================
# PowerFlow — Proxmox Physical Disks
# ==============================================================================
# Domain   : Proxmox
# File     : components/proxmox/physical-disks.ps1
# Purpose  : Physical disk selection, SMART, and capacity-test workflows
# Functions: Resolve-PmxDisk, Show-PmxDisks, Show-PmxSmart, Show-PmxDisk,
#            Invoke-PmxSmartTest, Invoke-PmxCapacityTest
# Depends  : components/proxmox/shared.ps1, Proxmox adapter contract
# ==============================================================================

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

