# ==============================================================================
# PowerFlow — Storage (storage)
# ==============================================================================
# Domain   : System
# File     : components/system/storage.ps1
# Purpose  : One noun for "where did my space go", across every volume.
# Depends  : platform adapters (apps.ps1), help/registry.ps1, system/apps.ps1
# ==============================================================================
#
# WHY THIS EXISTS
#
# `installed-apps` and `disk-big` both answer "where did my space go", under two unrelated
# names — and NEITHER could answer the question that comes first: *which drive* is full.
# Get-DiskHotspot only ever returned system-drive locations ($env:LOCALAPPDATA,
# $env:ProgramFiles, $HOME\...), so on a machine with data drives everything but C: was
# invisible. Measured on the author's own box: four volumes, three of them unreachable,
# including a 1.8 TB external.
#
# THE SHAPE IS `dkr`'s, DELIBERATELY
#
#   storage              bare command does the most useful thing — every volume, fullest first
#   storage D:           REFINEMENT IS A WORD (or a target), never a flag
#   storage /mnt/data    the same word works on Linux, which is the point
#   storage apps         verbs are words
#   storage big
#   --show-native        flags are for MODIFIERS only
#
# WHY THE VOLUME IS POSITIONAL AND NOT `-D`
#
# A flag per drive letter is an unbounded set (-C -D -E -F …), which is exactly the
# "memorise flags" trap. It also cannot survive the port: Linux has no drive letters, so
# `-D` would have to mean something different there. And PowerShell resolves unambiguous
# parameter PREFIXES, so a `-D` switch silently competes with -Detailed and -Depth — the
# same class of collision as pwsh-h's [switch]$a / $advanced / $all.
#
# Nothing is renamed. `installed-apps`, `i-a`, `disk-big` and `d-b` keep working; the verbs
# below delegate to them, so no muscle memory breaks.
# ==============================================================================

# Sizes are reported in the unit that keeps the number readable, because a storage table is
# read by eye and "1,863.0 GB" is worse than "1.8 TB" for the only judgement being made.
function Format-StorageSize {
    param([double]$Bytes)
    if ($Bytes -ge 1TB) { return ('{0:N1} TB' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:N1} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N0} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
    return ('{0:N0} B' -f $Bytes)
}

# A bar answers "is this a problem" faster than a percentage does.
function Format-StorageBar {
    param([double]$UsedFraction, [int]$Width = 18)
    $filled = [Math]::Max(0, [Math]::Min($Width, [int][Math]::Round($UsedFraction * $Width)))
    return ('#' * $filled) + ('.' * ($Width - $filled))
}

# Colour by headroom, not by percentage alone: 10% of a 4 TB disk is still 400 GB, whereas
# 10% of a 128 GB SSD is trouble. Both a ratio AND an absolute floor have to be crossed.
function Get-StorageColour {
    param([double]$UsedFraction, [double]$FreeBytes)
    if ($UsedFraction -ge 0.90 -and $FreeBytes -lt 25GB) { return 'Red' }
    if ($UsedFraction -ge 0.85 -and $FreeBytes -lt 50GB) { return 'Yellow' }
    return 'Green'
}

function Show-StorageNative {
    param([string]$Command)
    Write-Host "  $Command" -ForegroundColor DarkGray
}

<#
.SYNOPSIS
    Every volume, fullest first — the answer to "which drive is full".
#>
function Show-StorageOverview {
    param([switch]$ShowNative)

    $volumes = @(Get-StorageVolume)
    if (-not $volumes.Count) {
        Write-Host 'No storage volumes could be enumerated.' -ForegroundColor Yellow
        return
    }

    # The adapter owns the native string — a component that branches on the OS to build one
    # has already broken the boundary, however harmless the string looks.
    if ($ShowNative) { Show-StorageNative (Get-StorageNativeCommand -Operation 'list') }

    Write-Host ''
    Write-Host 'STORAGE' -ForegroundColor Cyan
    Write-Host ''

    # Fullest first: the volume you need to act on should not be the one you have to hunt for.
    $ordered = @($volumes | Sort-Object -Property @{
        Expression = { if ($_.SizeBytes -gt 0) { 1 - ($_.FreeBytes / $_.SizeBytes) } else { 0 } }
        Descending = $true
    })

    foreach ($volume in $ordered) {
        $used     = [double]($volume.SizeBytes - $volume.FreeBytes)
        $fraction = if ($volume.SizeBytes -gt 0) { $used / $volume.SizeBytes } else { 0 }
        $colour   = Get-StorageColour -UsedFraction $fraction -FreeBytes $volume.FreeBytes
        $label    = if ($volume.Label) { $volume.Label } else { $volume.FileSystem }
        $marker   = if ($volume.IsSystem) { '*' } else { ' ' }

        $line = '{0}{1,-12} {2,-16} {3} {4,3:N0}%  {5,9} free of {6,-9}' -f
                    $marker,
                    $volume.Name,
                    $(if ("$label".Length -gt 15) { "$label".Substring(0, 14) + '.' } else { $label }),
                    (Format-StorageBar -UsedFraction $fraction),
                    ($fraction * 100),
                    (Format-StorageSize $volume.FreeBytes),
                    (Format-StorageSize $volume.SizeBytes)
        Write-Host $line -ForegroundColor $colour
    }

    Write-Host ''
    Write-Host '  * system volume' -ForegroundColor DarkGray
    Write-Host '  storage <name>   what is on one volume        storage apps   installed apps by size' -ForegroundColor DarkGray
    Write-Host '  storage big      large folders and files      storage docker container space' -ForegroundColor DarkGray
    Write-Host ''
}

<#
.SYNOPSIS
    What is taking the space on ONE volume — its top-level directories, biggest first.
.DESCRIPTION
    Deliberately NOT the curated hot-spot list. That list exists because the system drive has
    a known layout worth knowing about - the local app-data tree, the docker root. A data
    drive has no conventional layout at all, so the honest answer is to size its top-level children and
    let the sizes speak.

    Only the immediate children are measured. Going deeper re-reports the same bytes at every
    level, which reads as a much bigger problem than it is.
#>
Register-PFEducation -Topic 'storage-overview' `
    -Analogy 'Each row is one place files can live — a drive on Windows, a mounted filesystem on Linux — with a bar showing how full it is.' `
    -Lines @(
        @{ Term = 'the bar';  Means = 'How much of that volume is already used. It turns amber, then red, as it fills.' }
        @{ Term = 'free';     Means = 'What is left. This is the number that runs out and stops things working.' }
        @{ Term = 'order';    Means = 'Fullest first, because the one about to cause a problem should be the one you see.' }
        @{ Term = 'missing?'; Means = 'Pseudo-filesystems (snap loops, per-session tmpfs) are hidden — they are not real storage.' }
    ) `
    -Footer 'storage <name> drills into one · storage report adds memory and layout · read-only, both.'

function Show-StorageVolumeDetail {
    param([Parameter(Mandatory)]$Volume, [switch]$ShowNative)

    Write-Host ''
    $used     = [double]($Volume.SizeBytes - $Volume.FreeBytes)
    $fraction = if ($Volume.SizeBytes -gt 0) { $used / $Volume.SizeBytes } else { 0 }
    Write-Host ("$($Volume.Name)  $(Format-StorageSize $used) used of $(Format-StorageSize $Volume.SizeBytes)" +
                "  ($(Format-StorageSize $Volume.FreeBytes) free)") -ForegroundColor Cyan
    if ($Volume.Label) { Write-Host "  $($Volume.Label)" -ForegroundColor DarkGray }
    Write-Host ''

    if ($ShowNative) { Show-StorageNative (Get-StorageNativeCommand -Operation 'measure' -Root $Volume.Root) }

    Write-Host '  sizing top-level folders...' -ForegroundColor DarkGray

    $rows = @()
    $children = @(Get-ChildItem -LiteralPath $Volume.Root -Force -ErrorAction SilentlyContinue)
    $index = 0
    foreach ($child in $children) {
        $index++
        Write-Progress -Activity "Sizing $($Volume.Name)" -Status $child.Name `
            -PercentComplete (($index / [Math]::Max(1, $children.Count)) * 100)
        $bytes = if ($child.PSIsContainer) { [int64](Measure-FolderSize -Path $child.FullName) } else { [int64]$child.Length }
        if ($bytes -le 0) { continue }
        $rows += [pscustomobject]@{ Name = $child.Name; Bytes = $bytes; IsFolder = $child.PSIsContainer }
    }
    Write-Progress -Activity "Sizing $($Volume.Name)" -Completed

    if (-not $rows.Count) {
        Write-Host '  Nothing measurable at the top level (permissions, or an empty volume).' -ForegroundColor Yellow
        Write-Host ''
        return
    }

    Write-Host ''
    foreach ($row in ($rows | Sort-Object Bytes -Descending | Select-Object -First 20)) {
        $share = if ($used -gt 0) { $row.Bytes / $used } else { 0 }
        $kind  = if ($row.IsFolder) { 'dir ' } else { 'file' }
        Write-Host ('  {0,10}  {1}  {2} {3}' -f
            (Format-StorageSize $row.Bytes),
            (Format-StorageBar -UsedFraction $share -Width 12),
            $kind,
            $row.Name)
    }
    Write-Host ''
    Write-Host '  Only top-level children are sized - going deeper re-counts the same bytes.' -ForegroundColor DarkGray
    Write-Host ''
}

<#
.SYNOPSIS
    Reclaimable container space, from the daemon's own accounting.
.DESCRIPTION
    A filesystem walk of /var/lib/docker CANNOT answer this. overlay2 layers are shared
    between images, so summing directory sizes double-counts and reports a number that does
    not correspond to anything you can actually free. Only the daemon knows what is
    reclaimable, so this defers to it rather than guessing.
#>
function Show-StorageDocker {
    param([switch]$ShowNative)

    if (-not (Get-Command Get-ContainerEngineInfo -ErrorAction SilentlyContinue)) {
        Write-Host 'Docker support is not loaded.' -ForegroundColor Yellow
        return
    }
    $engine = Get-ContainerEngineInfo -Engine 'docker'
    if ($engine.State -ne 'ready') {
        Write-Host "Docker is not available ($($engine.State)): $($engine.Error)." -ForegroundColor Yellow
        Write-Host '  dkr   for the full diagnosis' -ForegroundColor DarkGray
        return
    }

    if ($ShowNative) { Show-StorageNative 'docker system df' }
    Write-Host ''
    Write-Host 'CONTAINER STORAGE' -ForegroundColor Cyan
    Write-Host '  Reported by the daemon - a directory walk of the docker root would' -ForegroundColor DarkGray
    Write-Host '  double-count shared overlay2 layers.' -ForegroundColor DarkGray
    Write-Host ''
    foreach ($line in @(Invoke-PFContainerEngine -Engine $engine -EngineArgs @('system', 'df'))) {
        Write-Host "  $line"
    }
    Write-Host ''
}

function Show-StorageHelp {
    Write-Host ''
    Write-Host 'storage - where did my space go' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  storage                 every volume, fullest first' -ForegroundColor White

    # The example uses a REAL volume from this machine rather than a hardcoded 'D:' or
    # '/mnt/data'. That keeps the component OS-agnostic and makes the help concrete: it names
    # something the reader can actually type here.
    $sample = @(Get-StorageVolume | Where-Object { -not $_.IsSystem } | Select-Object -First 1)
    if (-not $sample.Count) { $sample = @(Get-StorageVolume | Select-Object -First 1) }
    $example = if ($sample.Count) { $sample[0].Name } else { '<volume>' }
    Write-Host "  storage $($example.PadRight(15)) what is on one volume  (a name, never a flag)" -ForegroundColor White
    Write-Host '  storage apps            installed apps by size band' -ForegroundColor White
    Write-Host '  storage big             large folders and files' -ForegroundColor White
    Write-Host '  storage docker          reclaimable container space' -ForegroundColor White
    Write-Host ''
    Write-Host '  --show-native           print the real command it runs' -ForegroundColor White
    Write-Host ''
    Write-Host '  The volume is a TARGET, not a flag: a flag per drive letter would be an' -ForegroundColor DarkGray
    Write-Host '  unbounded set, and drive letters do not exist on Linux.' -ForegroundColor DarkGray
    Write-Host ''
}

<#
.SYNOPSIS
    Where did my space go - across every volume.
#>
# ══════════════════════════════════════════════════════════════════════════════
#  storage report — PF-FEAT-006
# ══════════════════════════════════════════════════════════════════════════════
# Replaces the sequence an admin runs on a new box to answer ONE question — how is this
# machine laid out, and is anything under pressure:
#
#     lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS
#     sudo fdisk -l /dev/sda
#     swapon --show
#     free -h
#     cat /etc/fstab
#
# Five commands, four of them read-only and one asking for a password. This is one command,
# read-only throughout, and it needs no sudo: everything comes from /proc and lsblk's JSON
# on Linux, and from CIM on Windows.
#
# Deliberately NOT a wrapper that shells out to all five. Each section is built from the
# adapter contract, so the same view renders on both platforms and neither `free` nor
# procps needs to be installed.
function Show-StorageReport {
    param([switch]$ShowNative)

    $volumes = @(Get-StorageVolume)
    $memory  = Get-StorageMemory
    $layout  = Get-StorageLayout

    Write-Host ''
    Write-Host '  🗄️  STORAGE AND MEMORY' -ForegroundColor Cyan
    Write-Host '  ────────────────────────────────────────────────────────────' -ForegroundColor DarkGray

    # ── 1. volumes: the question people actually open this for ────────────────
    if ($volumes.Count) {
        Write-Host ''
        Write-Host '  MOUNTED' -ForegroundColor White
        $nameWidth = 4
        foreach ($v in $volumes) { if ("$($v.Name)".Length -gt $nameWidth) { $nameWidth = "$($v.Name)".Length } }
        # Used is DERIVED: the adapter contract is { Name; SizeBytes; FreeBytes }. Reading a
        # $v.UsedBytes that does not exist yields $null, and $null/Size is 0 — which rendered
        # every bar empty beside a free-space figure that said otherwise.
        foreach ($v in ($volumes | Sort-Object {
                if ($_.SizeBytes) { ($_.SizeBytes - $_.FreeBytes) / $_.SizeBytes } else { 0 } } -Descending)) {
            $fraction = if ($v.SizeBytes) { ($v.SizeBytes - $v.FreeBytes) / $v.SizeBytes } else { 0 }
            Write-Host ("    {0}  " -f "$($v.Name)".PadRight($nameWidth)) -NoNewline -ForegroundColor White
            Write-Host ("{0}  " -f (Format-StorageBar -UsedFraction $fraction)) -NoNewline
            Write-Host ("{0,4:N0}%  " -f ($fraction * 100)) -NoNewline `
                -ForegroundColor (Get-StorageColour -UsedFraction $fraction -FreeBytes $v.FreeBytes)
            Write-Host ("{0} free of {1}" -f (Format-StorageSize $v.FreeBytes), (Format-StorageSize $v.SizeBytes)) -ForegroundColor DarkGray
        }
    }

    # ── 2. memory and swap ────────────────────────────────────────────────────
    if ($memory.Supported) {
        Write-Host ''
        Write-Host '  MEMORY' -ForegroundColor White
        # Measured, not hardcoded: the swap label is "swap" on Linux and "pagefile" on
        # Windows, so a fixed width lines up on one platform and overflows on the other.
        $labelWidth = @('RAM', 'cache', "$($memory.SwapLabel)") |
                      ForEach-Object { $_.Length } | Sort-Object -Descending | Select-Object -First 1

        # Memory gets its own colour rule rather than Get-StorageColour's: that one requires an
        # absolute free-BYTES floor tuned for disks (25/50 GB), which RAM would essentially never
        # cross, so every machine would read green no matter how squeezed it was.
        $memFraction = if ($memory.TotalBytes) { $memory.UsedBytes / $memory.TotalBytes } else { 0 }
        $memColour = if ($memFraction -ge 0.90) { 'Red' } elseif ($memFraction -ge 0.75) { 'Yellow' } else { 'Green' }
        Write-Host ('    {0}  ' -f 'RAM'.PadRight($labelWidth)) -NoNewline -ForegroundColor White
        Write-Host ("{0}  " -f (Format-StorageBar -UsedFraction $memFraction)) -NoNewline
        Write-Host ("{0,4:N0}%  " -f ($memFraction * 100)) -NoNewline -ForegroundColor $memColour
        Write-Host ("{0} available of {1}" -f (Format-StorageSize $memory.AvailableBytes), (Format-StorageSize $memory.TotalBytes)) -ForegroundColor DarkGray

        # Cache is called out because it is the single most misread number here: it looks
        # like consumed memory and is handed straight back when something needs it.
        if ($memory.CacheBytes -gt 0) {
            Write-Host ('    {0}  ' -f 'cache'.PadRight($labelWidth)) -NoNewline -ForegroundColor DarkGray
            Write-Host ("{0} — counted as used, but yours the moment anything asks" -f (Format-StorageSize $memory.CacheBytes)) -ForegroundColor DarkGray
        }

        if ($memory.SwapTotalBytes -gt 0) {
            # Swap in use at all is worth noticing, so this is stricter than the RAM rule:
            # sustained swapping is the symptom people actually chase.
            $swapFraction = $memory.SwapUsedBytes / $memory.SwapTotalBytes
            $swapColour = if ($swapFraction -ge 0.50) { 'Red' } elseif ($swapFraction -ge 0.20) { 'Yellow' } else { 'Green' }
            Write-Host ('    {0}  ' -f "$($memory.SwapLabel)".PadRight($labelWidth)) -NoNewline -ForegroundColor White
            Write-Host ("{0}  " -f (Format-StorageBar -UsedFraction $swapFraction)) -NoNewline
            Write-Host ("{0,4:N0}%  " -f ($swapFraction * 100)) -NoNewline -ForegroundColor $swapColour
            Write-Host ("{0} used of {1}" -f (Format-StorageSize $memory.SwapUsedBytes), (Format-StorageSize $memory.SwapTotalBytes)) -ForegroundColor DarkGray
            foreach ($area in @($memory.SwapAreas)) {
                Write-Host ("      {0}  {1}" -f $area.Name, $area.Type) -ForegroundColor DarkGray
            }
        }
        else {
            Write-Host ('    {0}  none configured' -f "$($memory.SwapLabel)".PadRight($labelWidth)) -ForegroundColor DarkGray
        }
    }

    # ── 3. the physical layout ────────────────────────────────────────────────
    if ($layout.Supported -and @($layout.Devices).Count) {
        Write-Host ''
        Write-Host '  LAYOUT' -ForegroundColor White
        foreach ($device in $layout.Devices) {
            Write-Host ("    {0}  {1}" -f $device.Name, (Format-StorageSize $device.SizeBytes)) -ForegroundColor White
            foreach ($part in @($device.Partitions)) {
                $where = if ($part.MountPoint) { $part.MountPoint } else { 'not mounted' }
                $fs    = if ($part.FsType) { $part.FsType } else { '—' }
                Write-Host ("      {0,-10} {1,8}  {2,-8}  {3}" -f $part.Name, (Format-StorageSize $part.SizeBytes), $fs, $where) -ForegroundColor DarkGray
            }
        }
    }
    elseif (-not $layout.Supported -and $layout.Reason) {
        Write-Host ''
        Write-Host "  LAYOUT unavailable — $($layout.Reason)" -ForegroundColor DarkGray
    }

    if ($ShowNative) {
        Write-Host ''
        Show-StorageNative
    }

    Write-Host ''
    Write-Host '  storage <name> drills into one volume · storage big finds what is eating it' -ForegroundColor DarkGray
}

Register-PFEducation -Topic 'storage-report' `
    -Analogy 'Think of the machine as a building: the volumes are rooms and how full they are, memory is the desk space being worked on right now, and the layout is the floor plan underneath both.' `
    -Lines @(
        @{ Term = 'MOUNTED';   Means = 'Filesystems you can actually write to, fullest first.' }
        @{ Term = 'free';      Means = 'Space left on that volume — the number that runs out and stops things.' }
        @{ Term = 'RAM';       Means = 'Working memory. "Available" is what a new program could take right now.' }
        @{ Term = 'cache';     Means = 'Memory holding recently-read files. It counts as used but is given back on demand.' }
        @{ Term = 'swap / pagefile'; Means = 'Disk standing in for RAM — swap on Linux, pagefile on Windows. A little is normal; climbing steadily is not.' }
        @{ Term = 'LAYOUT';    Means = 'The physical disks and the partitions cut from them.' }
        @{ Term = 'not mounted'; Means = 'A partition with no path attached, so nothing can read or write it yet.' }
    ) `
    -Footer 'Everything here is read-only — this command changes nothing.'

# ==============================================================================
# storage root — where should what grows live, and what still does not
# ==============================================================================
#
# Read-only, always. It reports and points; it never moves, declares or deletes anything.
#
# Eligibility itself lives in components/shared/volumes.ps1, because `nav setup` asks the
# same question about directories that this asks about volumes, and two copies of a rule
# about hardware is precisely the drift this repository has been bitten by before.
# ==============================================================================

function Show-StorageRoot {
    param([switch]$ShowNative)

    $candidates = @(Get-PFStorageCandidate)
    $eligible   = @($candidates | Where-Object { $_.Eligible })

    Write-Host ''
    Write-Host '🗄️  STORAGE ROOT — where what grows could live' -ForegroundColor Cyan
    Write-Host '────────────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
    Write-Host ('  {0,-6} {1,-16} {2,10} {3,10}  {4}' -f 'VOLUME', 'LABEL', 'SIZE', 'FREE', 'VERDICT') -ForegroundColor DarkGray
    foreach ($c in $candidates) {
        $verdict = if ($c.Eligible) { 'eligible' } else { $c.Reason }
        $colour  = if ($c.Eligible) { 'Green' } elseif ($c.IsSystem) { 'White' } else { 'DarkGray' }
        # Assigned, never inlined into the -f argument list: an `if` used directly as an
        # argument expression is a 5.1 parse hazard, and this profile supports 5.1.
        $label   = "$($c.Label)"
        if ($label.Length -gt 16) { $label = $label.Substring(0, 16) }
        Write-Host ('  {0,-6} {1,-16} {2,10} {3,10}  {4}' -f $c.Name, $label,
                    (Format-StorageSize $c.SizeBytes), (Format-StorageSize $c.FreeBytes), $verdict) -ForegroundColor $colour
    }

    Write-Host ''
    if (-not $eligible.Count) {
        Write-Host '  No volume besides the system one qualifies — so the system drive is the answer here,' -ForegroundColor DarkGray
        Write-Host '  and keeping what grows tidy matters more than moving it.' -ForegroundColor DarkGray
    }

    # ---- what is still on the system drive ------------------------------------
    $stragglers = @()
    try { $stragglers = @(Get-StorageStraggler) } catch { }

    $unmoved   = @($stragglers | Where-Object { -not $_.Redirected })
    $linked    = @($stragglers | Where-Object { $_.Redirected })
    $totalSize = ($unmoved | Measure-Object SizeBytes -Sum).Sum

    Write-Host '  ON THE SYSTEM DRIVE' -ForegroundColor Cyan
    if (-not $unmoved.Count) {
        Write-Host '    Nothing known is still parked there.' -ForegroundColor Green
    }
    else {
        Write-Host ('    {0,-20} {1,10}  {2}' -f 'WHAT', 'SIZE', 'MOVED BY') -ForegroundColor DarkGray
        foreach ($s in $unmoved) {
            $how = if ($s.Variable) { $s.Variable } else { 'no variable — needs a link' }
            Write-Host ('    {0,-20} {1,10}  {2}' -f $s.Name, (Format-StorageSize $s.SizeBytes), $how) `
                       -ForegroundColor (Get-StorageColour ([double]$s.SizeBytes / 1GB * 10))
            if ($ShowNative) { Write-Host ('      {0}' -f $s.Path) -ForegroundColor DarkGray }
        }
        Write-Host ('    {0,-20} {1,10}' -f 'total', (Format-StorageSize $totalSize)) -ForegroundColor White
    }

    # Already-redirected paths still EXIST on the system drive and still measure the same
    # size through the link. Reporting them as unmoved would nag about finished work.
    if ($linked.Count) {
        Write-Host ''
        Write-Host '  ALREADY REDIRECTED (the directory is a link; the bytes are elsewhere)' -ForegroundColor Cyan
        foreach ($s in $linked) {
            Write-Host ('    {0,-20} {1,10}' -f $s.Name, (Format-StorageSize $s.SizeBytes)) -ForegroundColor DarkGray
        }
    }

    Write-Host ''
    Write-Host '  Read-only — this command moves nothing.' -ForegroundColor DarkGray
    Write-Host '  storage root --show-native   the full path of every row' -ForegroundColor DarkGray
    Write-Host ''
}

Register-PFEducation -Topic 'storage-root' `
    -Analogy 'A kitchen with one small worktop and a large empty table: the question is not whether the table is bigger, but whether it is yours to use and still there tomorrow.' `
    -Lines @(
        @{ Term = 'eligible';       Means = 'Not the system volume, not on a disk you can unplug, and PowerFlow could actually create a file there — probed, not assumed.' }
        @{ Term = 'removable disk'; Means = 'Windows reports USB drives as "Fixed", so this is decided by the bus the DISK is on, not by the volume type.' }
        @{ Term = 'not writable';   Means = 'A mount can be read-only or owned by another user while its permission bits look fine. The only honest test is to try writing.' }
        @{ Term = 'MOVED BY';       Means = 'The variable that relocates it. "needs a link" means the tool offers none, so a junction or symlink is the only route.' }
        @{ Term = 'already redirected'; Means = 'The directory is a link: it still exists and measures the same, but the bytes are elsewhere. Finished work, not a finding.' }
    ) `
    -Footer 'Nothing here changes anything. It is a report you can run before and after an install.'

function storage {
    # NO param() block. A param() would bind -a and -D as parameter NAMES, and PowerShell's
    # prefix matching would make -D ambiguous with any other D parameter. See the header.
    $showNative = $false
    $words      = @()

    # --educate is pulled out FIRST. This command hand-parses its arguments, so an
    # unrecognised token falls through to the verb switch and is reported as "no volume or
    # command matching '--educate'" — the unbindable-token failure the flag convention
    # exists to prevent.
    $educated = Split-PFEducateFlag -Argv $args -Command 'storage'
    $educate  = $educated.Educate

    foreach ($argument in $educated.Argv) {
        $token = "$argument"
        if (-not $token) { continue }
        if ($token -eq '--show-native') { $showNative = $true; continue }
        if ($token -in @('-h', '--help')) { Show-StorageHelp; return }
        $words += $token
    }

    $verb = if ($words.Count) { $words[0] } else { '' }
    $rest = @($words | Select-Object -Skip 1)

    switch ($verb.ToLowerInvariant()) {
        ''       {
            Show-StorageOverview -ShowNative:$showNative
            if ($educate) { Write-PFEducation -Topic 'storage-overview' }
            return
        }
        'help'   { Show-StorageHelp; return }
        'report' {
            Show-StorageReport -ShowNative:$showNative
            if ($educate) { Write-PFEducation -Topic 'storage-report' }
            return
        }
        'root' {
            Show-StorageRoot -ShowNative:$showNative
            if ($educate) { Write-PFEducation -Topic 'storage-root' }
            return
        }
        'docker' { Show-StorageDocker -ShowNative:$showNative; return }
        'apps'   {
            # Delegates rather than reimplements: installed-apps already owns the size-band
            # browser, and duplicating it would create two things to keep in step.
            if ($rest.Count) { installed-apps @rest } else { installed-apps -o }
            return
        }
        'big' {
            if ($rest.Count) { disk-big @rest } else { disk-big }
            return
        }
    }

    # Not a verb, so it is a volume target.
    $volume = Resolve-StorageVolume -Selector $verb
    if ($volume) {
        Show-StorageVolumeDetail -Volume $volume -ShowNative:$showNative
        return
    }

    Write-Host "No volume or command matching '$verb'." -ForegroundColor Red
    $names = @(Get-StorageVolume | ForEach-Object { $_.Name })
    if ($names.Count) { Write-Host "  Volumes here: $($names -join '  ')" -ForegroundColor DarkGray }
    Write-Host '  storage help' -ForegroundColor DarkGray
}

Register-PFCommand -Name 'storage' -Section '🗄️ DISK RECLAIM' `
    -Synopsis 'every volume, fullest first; a name drills into one' -Example 'storage · storage D: · storage apps'
Register-PFCommand -Name 'storage report' -Section '🗄️ DISK RECLAIM' `
    -Synopsis 'volumes, memory, swap and disk layout in one read-only view' -Example 'storage report --educate'
Register-PFCommand -Name 'storage apps' -Section '🗄️ DISK RECLAIM' `
    -Synopsis 'installed apps by size band' -Example 'storage apps 2gb-4gb'
Register-PFCommand -Name 'storage big' -Section '🗄️ DISK RECLAIM' `
    -Synopsis 'large folders and files (vhdx, node_modules, caches)' -Example 'storage big 50gb-200gb'
Register-PFCommand -Name 'storage docker' -Section '🗄️ DISK RECLAIM' `
    -Synopsis 'reclaimable container space, per the daemon' -Example 'storage docker'
Register-PFCommand -Name 'storage root' -Section '🗄️ DISK RECLAIM' `
    -Synopsis 'which drive could hold what grows, and what is still on the system one' -Example 'storage root --educate'
