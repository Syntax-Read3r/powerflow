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
function storage {
    # NO param() block. A param() would bind -a and -D as parameter NAMES, and PowerShell's
    # prefix matching would make -D ambiguous with any other D parameter. See the header.
    $showNative = $false
    $words      = @()

    foreach ($argument in $args) {
        $token = "$argument"
        if (-not $token) { continue }
        if ($token -eq '--show-native') { $showNative = $true; continue }
        if ($token -in @('-h', '--help')) { Show-StorageHelp; return }
        $words += $token
    }

    $verb = if ($words.Count) { $words[0] } else { '' }
    $rest = @($words | Select-Object -Skip 1)

    switch ($verb.ToLowerInvariant()) {
        ''       { Show-StorageOverview -ShowNative:$showNative; return }
        'help'   { Show-StorageHelp; return }
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
Register-PFCommand -Name 'storage apps' -Section '🗄️ DISK RECLAIM' `
    -Synopsis 'installed apps by size band' -Example 'storage apps 2gb-4gb'
Register-PFCommand -Name 'storage big' -Section '🗄️ DISK RECLAIM' `
    -Synopsis 'large folders and files (vhdx, node_modules, caches)' -Example 'storage big 50gb-200gb'
Register-PFCommand -Name 'storage docker' -Section '🗄️ DISK RECLAIM' `
    -Synopsis 'reclaimable container space, per the daemon' -Example 'storage docker'
