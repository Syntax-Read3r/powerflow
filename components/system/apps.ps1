# ==============================================================================
# PowerFlow — Installed Applications / Disk Reclaim
# ==============================================================================
# Domain   : System
# File     : components/system/apps.ps1
# Purpose  : Find what is actually eating the disk. Lists installed applications
#            within a size band, then lets you open, uninstall, or delete them.
# Functions: installed-apps, Get-SizeBands, Convert-ToBytes, Format-Size
# Depends  : Get-InstalledApplication, Uninstall-Application, Move-ToTrash,
#            Remove-PathPermanently, Test-TrashSupport, Test-ProtectedPath
#            (platform/<os>/adapters/apps.ps1)
#            Open-Path, Copy-ToClipboard
# ==============================================================================
#
# WHY SIZE BANDS
#
# A naive "list everything big" returns hundreds of rows spanning trivial to
# enormous, which is unreviewable — and an unreviewable list in front of a delete
# action is how people destroy things. So:
#
#   * Nothing below 1 GB is ever considered. If the disk is full, a 50 MB utility
#     is not the problem and does not belong in the list.
#   * A query must fit ENTIRELY inside ONE band. Bands widen as items get rarer,
#     so every band returns a list you can actually read.
#
#     installed-apps 2gb-4gb     -> OK   (inside 1–5 GB)
#     installed-apps 3gb-10gb    -> NO   (spans 1–5 GB and 5–20 GB)
#     installed-apps 500mb-2gb   -> NO   (below the 1 GB floor)
# ==============================================================================

$script:PF_MinimumSize = 1GB

function Get-SizeBands {
    return @(
        [pscustomobject]@{ Id = 1; Min = 1GB;  Max = 5GB;                  Label = '1 – 5 GB';   Note = 'most large apps' }
        [pscustomobject]@{ Id = 2; Min = 5GB;  Max = 20GB;                 Label = '5 – 20 GB';  Note = 'IDEs, toolchains, games' }
        [pscustomobject]@{ Id = 3; Min = 20GB; Max = 50GB;                 Label = '20 – 50 GB'; Note = 'rare — large suites' }
        [pscustomobject]@{ Id = 4; Min = 50GB; Max = [int64]::MaxValue;    Label = '50 GB +';    Note = 'VMs, disk images' }
    )
}

function Format-Size {
    param([int64]$Bytes)
    if ($Bytes -ge 1TB) { return ('{0:N2} TB' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N0} MB' -f ($Bytes / 1MB)) }
    return ('{0:N0} KB' -f ($Bytes / 1KB))
}

# How long ago was this installed? "Big AND old" is the strongest signal that
# something is safe to remove, so the age is shown next to the size.
function Format-Age {
    # Deliberately untyped: many apps have no recorded install date, and a
    # [datetime] parameter throws on $null rather than accepting it.
    param($Date)

    if (-not $Date -or $Date -isnot [datetime] -or $Date -eq [datetime]::MinValue) { return '     ?' }

    $days = [int]((Get-Date) - $Date).TotalDays
    if ($days -lt 0)   { return '     ?' }
    if ($days -eq 0)   { return ' today' }
    if ($days -lt 30)  { return ('{0,3}d  ' -f $days) }
    if ($days -lt 365) { return ('{0,3}mo ' -f [int]($days / 30)) }
    return ('{0,3}yr ' -f [math]::Round($days / 365, 0))
}

# "2gb" -> 2147483648. Returns $null when unparseable.
function Convert-ToBytes {
    param([string]$Text)

    if ($Text -notmatch '^\s*([\d.]+)\s*(tb|gb|mb|kb|b)?\s*$') { return $null }

    $value = [double]$matches[1]
    $unit  = if ($matches[2]) { $matches[2].ToLower() } else { 'b' }

    $mult = switch ($unit) {
        'tb' { 1TB } 'gb' { 1GB } 'mb' { 1MB } 'kb' { 1KB } default { 1 }
    }
    return [int64]($value * $mult)
}

function Show-SizeBandMenu {
    param([string]$Reason)

    if ($Reason) {
        Write-Host ""
        Write-Host "⚠️  $Reason" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "📊 Choose a size band" -ForegroundColor Cyan
    Write-Host "════════════════════" -ForegroundColor Cyan
    Write-Host "   Nothing below 1 GB is listed — if the disk is full, small apps are not the cause." -ForegroundColor DarkGray
    Write-Host ""

    foreach ($b in (Get-SizeBands)) {
        Write-Host ("   {0}) {1,-12} " -f $b.Id, $b.Label) -NoNewline -ForegroundColor White
        Write-Host $b.Note -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "   A custom range must fit inside ONE band, e.g. " -NoNewline -ForegroundColor DarkGray
    Write-Host "installed-apps 2gb-4gb" -ForegroundColor Yellow
    Write-Host ""

    $choice = Read-Host "Select a band (1-4) or 'q' to quit"
    if ($choice -eq 'q') { return $null }

    $band = (Get-SizeBands) | Where-Object { $_.Id -eq ($choice -as [int]) }
    if (-not $band) {
        Write-Host "❌ Invalid selection." -ForegroundColor Red
        return $null
    }
    return $band
}

# Parse "2gb-4gb" and validate it against the bands.
# Returns @{ Min; Max; Label } or $null (having explained why).
function Resolve-SizeRange {
    param([string]$Range)

    if ($Range -notmatch '^\s*(.+?)\s*-\s*(.+?)\s*$') {
        Show-SizeBandMenu "Could not read '$Range'. Use a range like 2gb-4gb."
        return $null
    }

    $min = Convert-ToBytes $matches[1]
    $max = Convert-ToBytes $matches[2]

    if ($null -eq $min -or $null -eq $max) {
        return (Show-SizeBandMenu "Could not read '$Range'. Use a range like 2gb-4gb.")
    }
    if ($min -ge $max) {
        return (Show-SizeBandMenu "The minimum ($(Format-Size $min)) must be smaller than the maximum ($(Format-Size $max)).")
    }
    if ($min -lt $script:PF_MinimumSize) {
        return (Show-SizeBandMenu "$(Format-Size $min) is below the 1 GB floor. Anything smaller cannot be what filled the disk.")
    }

    # The range must sit entirely inside ONE band. This is the safety rule: it stops
    # a sweep like 1gb-100gb returning everything at once in front of a delete action.
    foreach ($b in (Get-SizeBands)) {
        if ($min -ge $b.Min -and $max -le $b.Max) {
            return [pscustomobject]@{ Min = $min; Max = $max; Label = "$(Format-Size $min) – $(Format-Size $max)" }
        }
    }

    return (Show-SizeBandMenu "$(Format-Size $min) – $(Format-Size $max) spans more than one band. Keep a query inside a single band.")
}

# Shared fzf picker for a list of apps / folders / files. Used by every entry point
# so the row format, the stable index parsing, and the action menu stay in one place.
function Show-AppPicker {
    param(
        [Parameter(Mandatory)][object[]]$Items,
        [Parameter(Mandatory)][string]$Label
    )

    if ($Items.Count -eq 0) {
        Write-Host "✅ Nothing in $Label." -ForegroundColor Green
        return
    }

    $hits  = @($Items | Sort-Object SizeBytes -Descending)
    $total = ($hits | Measure-Object -Property SizeBytes -Sum).Sum
    Write-Host "📦 $($hits.Count) item(s), $(Format-Size $total) total" -ForegroundColor Green

    # Emit "index<TAB>display" and show only the display column. Parsing the index back
    # is stable no matter how the decoration changes — see
    # docs/solved-problems/powershell-fzf-decorated-row-parsing.md
    $rows = for ($i = 0; $i -lt $hits.Count; $i++) {
        $a    = $hits[$i]
        $loc  = if ($a.InstallLocation) { $a.InstallLocation } else { "($($a.Source) package)" }
        $icon = switch ($a.Source) { 'folder' { '📁' } 'file' { '📄' } default { '📦' } }
        "{0}`t{1,10}  {2}  {3} {4,-38} {5}" -f $i, (Format-Size $a.SizeBytes), (Format-Age $a.InstallDate), $icon, $a.Name, $loc
    }

    $selection = $rows | fzf --ansi --reverse --height=70% --border --no-sort `
        --delimiter="`t" --with-nth=2.. `
        --prompt="🗄️  $Label : " `
        --header="      SIZE      AGE   NAME / LOCATION   ·   Enter: choose an action  ·  Esc: cancel"

    if (-not $selection) { Write-Host "ℹ️  Nothing selected." -ForegroundColor DarkGray; return }

    $index = ($selection -split "`t", 2)[0].Trim() -as [int]
    if ($null -eq $index -or $index -lt 0 -or $index -ge $hits.Count) {
        Write-Host "❌ Could not read the selection." -ForegroundColor Red
        return
    }

    Invoke-AppAction -App $hits[$index]
}

# The band overview: how much is sitting in each band, across everything installed.
# The expensive scan already happened, so this costs nothing extra — and it answers
# "where is my disk actually going?" in one screen.
function Show-BandOverview {
    param([Parameter(Mandatory)][object[]]$Apps)

    $bands   = Get-SizeBands
    $summary = foreach ($b in $bands) {
        $inBand = @($Apps | Where-Object { $_.SizeBytes -ge $b.Min -and $_.SizeBytes -le $b.Max })
        [pscustomobject]@{
            Band  = $b
            Count = $inBand.Count
            Bytes = [int64](($inBand | Measure-Object -Property SizeBytes -Sum).Sum)
            Items = $inBand
        }
    }

    $grand = ($summary | Measure-Object -Property Bytes -Sum).Sum

    Write-Host ""
    Write-Host "╭─ 🗄️  DISK OVERVIEW  (nothing under 1 GB is counted)" -ForegroundColor Cyan
    Write-Host "│" -ForegroundColor Cyan
    Write-Host ("│  {0,-12} {1,6}   {2,12}" -f 'BAND', 'APPS', 'TOTAL') -ForegroundColor DarkGray

    foreach ($s in $summary) {
        $colour = if ($s.Count -eq 0) { 'DarkGray' } elseif ($s.Bytes -ge 100GB) { 'Red' } elseif ($s.Bytes -ge 20GB) { 'Yellow' } else { 'White' }
        Write-Host ("│  {0,-12} {1,6}   {2,12}" -f $s.Band.Label, $s.Count, (Format-Size $s.Bytes)) -ForegroundColor $colour
    }

    Write-Host "│" -ForegroundColor Cyan
    Write-Host ("│  {0,-12} {1,6}   {2,12}" -f 'TOTAL', ($summary | Measure-Object -Property Count -Sum).Sum, (Format-Size $grand)) -ForegroundColor Green
    Write-Host "╰─" -ForegroundColor Cyan
    Write-Host ""

    # Drill in: pick a band, get its apps. No rescan — we already have everything.
    $rows = for ($i = 0; $i -lt $summary.Count; $i++) {
        $s = $summary[$i]
        "{0}`t{1,-12} {2,6} apps   {3,12}" -f $i, $s.Band.Label, $s.Count, (Format-Size $s.Bytes)
    }

    $selection = $rows | fzf --ansi --reverse --height=40% --border --no-sort `
        --delimiter="`t" --with-nth=2.. `
        --prompt="📊 Open a band: " `
        --header="   BAND          APPS          TOTAL   ·   Enter: open  ·  Esc: quit"

    if (-not $selection) { Write-Host "ℹ️  Done." -ForegroundColor DarkGray; return }

    $index = ($selection -split "`t", 2)[0].Trim() -as [int]
    if ($null -eq $index -or $index -lt 0 -or $index -ge $summary.Count) {
        Write-Host "❌ Could not read the selection." -ForegroundColor Red
        return
    }

    $chosen = $summary[$index]
    if ($chosen.Count -eq 0) {
        Write-Host "✅ Nothing installed in $($chosen.Band.Label)." -ForegroundColor Green
        return
    }

    Show-AppPicker -Items $chosen.Items -Label $chosen.Band.Label
}

<#
.SYNOPSIS
    Find installed applications by size, then open, uninstall, or delete them.
.EXAMPLE
    installed-apps -o         # overview of every band, then drill into one
.EXAMPLE
    installed-apps            # choose a size band, then browse it
.EXAMPLE
    installed-apps 2gb-4gb    # apps between 2 GB and 4 GB
.EXAMPLE
    installed-apps 50gb-200gb # the really big offenders
#>
function Show-PFInstalledApps {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Range,
        [Alias('o')][switch]$Overview,
        [switch]$Measure
    )

    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
        Write-Host "❌ fzf is required. Install it: $(Get-DependencyInstallHint 'fzf')" -ForegroundColor Red
        return
    }

    # ── Overview: scan ONCE, summarise every band, then drill in without rescanning ──
    if ($Overview) {
        Write-Host ""
        Write-Host "🔍 Scanning every installed application..." -ForegroundColor Cyan

        $all = @(Get-InstalledApplication -Measure:$Measure |
                 Where-Object { $_.SizeBytes -ge $script:PF_MinimumSize })

        if ($all.Count -eq 0) {
            Write-Host "✅ Nothing installed at 1 GB or above." -ForegroundColor Green
            return
        }

        Show-BandOverview -Apps $all
        return
    }

    # ── Single band / explicit range ──────────────────────────────────────────
    if ($Range) {
        $window = Resolve-SizeRange $Range
        if (-not $window) { return }
    }
    else {
        $band = Show-SizeBandMenu
        if (-not $band) { return }
        $window = [pscustomobject]@{ Min = $band.Min; Max = $band.Max; Label = $band.Label }
    }

    Write-Host ""
    Write-Host "🔍 Scanning installed applications ($($window.Label))..." -ForegroundColor Cyan

    $hits = @(Get-InstalledApplication -Measure:$Measure |
              Where-Object { $_.SizeBytes -ge $window.Min -and $_.SizeBytes -le $window.Max })

    if ($hits.Count -eq 0) {
        Write-Host "✅ Nothing installed in $($window.Label)." -ForegroundColor Green
        Write-Host "💡 See where the space actually is: " -NoNewline -ForegroundColor DarkGray
        Write-Host "i-a -o" -ForegroundColor Yellow
        return
    }

    Show-AppPicker -Items $hits -Label $window.Label
}

# ── installed-apps ──────────────────────────────────────────────────────────
# The user-facing name is a shim so that --long flags bind at all: a param() block
# cannot bind them, and worse, misbinds them into the next value parameter. The shim
# must not declare param() of its own, or $args would not hold the whole line.
# See docs/plan/ethos/ETHOS.md.
function installed-apps { Invoke-PFParamCommand -Target 'Show-PFInstalledApps' -Command 'installed-apps' -Argv $args }

# Shorthand. Set-Alias (rather than a wrapper function) so every parameter forwards
# untouched — `i-a -o`, `i-a 2gb-4gb` and `i-a 50gb-200gb -Measure` all just work.
Set-Alias i-a installed-apps
Set-Alias d-b disk-big

<#
.SYNOPSIS
    Find the folders and files that are actually eating the disk.
.DESCRIPTION
    Registry enumeration only sees installed applications. It will never surface a
    169 GB docker_data.vhdx, a 30 GB node_modules, or a Downloads folder full of
    ISOs — none of those are "apps". This scans the places where bulk really
    accumulates and reports anything inside the chosen size band.
.EXAMPLE
    disk-big              # choose a size band interactively
.EXAMPLE
    disk-big 50gb-200gb   # the really big offenders
#>
function Show-PFDiskBig {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Range,
        [string]$Path
    )

    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
        Write-Host "❌ fzf is required. Install it: $(Get-DependencyInstallHint 'fzf')" -ForegroundColor Red
        return
    }

    if ($Range) {
        $window = Resolve-SizeRange $Range
        if (-not $window) { return }
    }
    else {
        $band = Show-SizeBandMenu
        if (-not $band) { return }
        $window = [pscustomobject]@{ Min = $band.Min; Max = $band.Max; Label = $band.Label }
    }

    $roots = if ($Path) { @($Path) } else { Get-DiskHotspot }

    Write-Host ""
    Write-Host "🔍 Scanning $($roots.Count) location(s) for items in $($window.Label)..." -ForegroundColor Cyan
    Write-Host "   This walks each folder to size it — give it a moment." -ForegroundColor DarkGray

    $found = [System.Collections.Generic.List[object]]::new()
    $n = 0

    foreach ($root in $roots) {
        $n++
        Write-Progress -Activity "Scanning for large items" -Status $root -PercentComplete (($n / $roots.Count) * 100)

        # Only look at the IMMEDIATE children of each hot spot. A 169 GB vhdx shows up
        # as a big file; a bloated node_modules shows up as a big folder. Going deeper
        # would just re-report the same bytes at every level.
        Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $item  = $_
            $bytes = if ($item.PSIsContainer) { Measure-FolderSize $item.FullName } else { [int64]$item.Length }

            if ($bytes -ge $window.Min -and $bytes -le $window.Max) {
                $found.Add([pscustomobject]@{
                    Name            = $item.Name
                    Version         = if ($item.PSIsContainer) { 'folder' } else { $item.Extension }
                    Publisher       = Split-Path $root -Leaf
                    SizeBytes       = [int64]$bytes
                    InstallLocation = $item.FullName
                    UninstallString = $null
                    Source          = if ($item.PSIsContainer) { 'folder' } else { 'file' }
                    Id              = $item.FullName
                })
            }
        }
    }
    Write-Progress -Activity "Scanning for large items" -Completed

    if ($found.Count -eq 0) {
        Write-Host "✅ Nothing in $($window.Label) in the usual hot spots." -ForegroundColor Green
        Write-Host "💡 Try another band, or scan a specific path: " -NoNewline -ForegroundColor DarkGray
        Write-Host "disk-big 1gb-5gb -Path D:\" -ForegroundColor Yellow
        return
    }

    Show-AppPicker -Items $found -Label $window.Label
}

# ── disk-big ────────────────────────────────────────────────────────────────
# A shim so --path binds. With a bare param() block it would bind as the VALUE of $Range
# and the real path would fall into $args — see docs/plan/ethos/ETHOS.md. d-b points at
# this name, so the short alias gets the same translation.
function disk-big { Invoke-PFParamCommand -Target 'Show-PFDiskBig' -Command 'disk-big' -Argv $args }

# The action menu for a chosen app, folder or file.
function Invoke-AppAction {
    param([Parameter(Mandatory)]$App)

    $loc      = $App.InstallLocation
    $hasPath  = $loc -and (Test-Path -LiteralPath $loc)
    $isLocked = $hasPath -and (Test-ProtectedPath $loc)
    $isApp    = $App.Source -notin @('folder', 'file')

    # A virtual disk is not junk. Deleting docker_data.vhdx destroys every image,
    # container and volume on the machine — and it still would not be the right fix,
    # because a VHDX grows but never shrinks. Most of its size is usually reclaimable
    # slack, not live data. Prune inside Docker, then COMPACT the disk.
    $isVirtualDisk = $loc -and ($loc -match '\.(vhdx|vhd|vmdk|vdi|qcow2)$')

    $ageDays = if ($App.InstallDate) { [int]((Get-Date) - $App.InstallDate).TotalDays } else { -1 }

    Write-Host ""
    Write-Host "╭─ $($App.Name)" -ForegroundColor Cyan
    Write-Host "│  Size      : $(Format-Size $App.SizeBytes)" -ForegroundColor White
    if ($App.InstallDate) {
        Write-Host "│  Installed : $($App.InstallDate.ToString('yyyy-MM-dd'))  ($ageDays days ago)" -ForegroundColor White
    } else {
        Write-Host "│  Installed : unknown" -ForegroundColor DarkGray
    }
    Write-Host "│  Type      : $($App.Version)" -ForegroundColor DarkGray
    Write-Host "│  Source    : $($App.Source)" -ForegroundColor DarkGray
    Write-Host "│  Location  : $(if ($hasPath) { $loc } else { '(managed by the package manager — no folder)' })" -ForegroundColor DarkGray
    if ($isLocked) {
        Write-Host "│  🛑 PROTECTED — this path cannot be deleted" -ForegroundColor Red
    }
    Write-Host "╰─" -ForegroundColor Cyan

    # Big AND old is the strongest "you probably don't need this" signal.
    if ($ageDays -gt 365 -and $App.SizeBytes -ge 5GB) {
        Write-Host ""
        Write-Host "  💡 $(Format-Size $App.SizeBytes), untouched for over a year — a strong reclaim candidate." -ForegroundColor Yellow
    }

    if ($isVirtualDisk) {
        Write-Host ""
        Write-Host "  ⚠️  This is a VIRTUAL DISK." -ForegroundColor Yellow
        Write-Host "     Deleting it destroys everything inside it — for Docker that means every" -ForegroundColor DarkGray
        Write-Host "     image, container and volume you have." -ForegroundColor DarkGray
        Write-Host "     It also grows but never shrinks, so most of its size is probably" -ForegroundColor DarkGray
        Write-Host "     reclaimable slack rather than live data. The right fix is:" -ForegroundColor DarkGray
        Write-Host "       docker system prune -a --volumes     " -NoNewline -ForegroundColor Cyan
        Write-Host "# free the space inside" -ForegroundColor DarkGray
        Write-Host "       then compact the .vhdx                " -NoNewline -ForegroundColor Cyan
        Write-Host "# hand it back to Windows" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "  1) Open the parent folder" -ForegroundColor White
    Write-Host "  2) Copy the path to the clipboard" -ForegroundColor White

    if ($isApp) {
        Write-Host "  3) Uninstall properly " -NoNewline -ForegroundColor Green
        Write-Host "(recommended — runs the real uninstaller)" -ForegroundColor DarkGray
    } else {
        Write-Host "  3) Uninstall " -NoNewline -ForegroundColor DarkGray
        Write-Host "(n/a — this is a $($App.Source), not an installed app)" -ForegroundColor DarkGray
    }

    Write-Host "  4) Delete → Recycle Bin / trash " -NoNewline -ForegroundColor Yellow
    Write-Host "(recoverable)" -ForegroundColor DarkGray
    Write-Host "  5) Delete → PERMANENTLY " -NoNewline -ForegroundColor Red
    Write-Host "(cannot be undone)" -ForegroundColor DarkGray
    Write-Host "  q) Cancel" -ForegroundColor DarkGray
    Write-Host ""

    switch (Read-Host "Choose") {

        '1' {
            if (-not $hasPath) { Write-Host "❌ No folder on disk for this package." -ForegroundColor Red; return }
            Open-Path (Split-Path -Parent $loc)
            Write-Host "📂 Opened: $(Split-Path -Parent $loc)" -ForegroundColor Green
        }

        '2' {
            if (-not $hasPath) { Write-Host "❌ No path to copy." -ForegroundColor Red; return }
            Copy-ToClipboard $loc
            Write-Host "📋 Copied: $loc" -ForegroundColor Green
        }

        '3' {
            if (-not $isApp) {
                Write-Host "❌ This is a $($App.Source), not an installed app — there is nothing to uninstall." -ForegroundColor Red
                Write-Host "💡 Use option 4 or 5 to delete it." -ForegroundColor DarkGray
                return
            }

            Write-Host ""
            Write-Host "🔧 Uninstalling '$($App.Name)' via its own uninstaller..." -ForegroundColor Yellow
            if ((Read-Host "Continue? (y/n)") -ne 'y') { Write-Host "❌ Cancelled." -ForegroundColor Yellow; return }

            if (Uninstall-Application -App $App) {
                Write-Host "✅ Uninstalled '$($App.Name)' — reclaimed ~$(Format-Size $App.SizeBytes)" -ForegroundColor Green
            } else {
                Write-Host "❌ Uninstall did not complete." -ForegroundColor Red
            }
        }

        '4' {
            if (-not $hasPath) { Write-Host "❌ Nothing on disk to delete." -ForegroundColor Red; return }
            if ($isLocked)     { Write-Host "🛑 Protected path — refusing." -ForegroundColor Red; return }

            if ($isApp) {
                Write-Warning "Deleting the folder does NOT uninstall the app. It leaves the uninstaller, registry entries and PATH shims behind. Option 3 is the clean way."
            }
            if ($isVirtualDisk) {
                Write-Warning "This is a virtual disk — deleting it destroys every image, container and volume inside it."
            }

            Write-Host ""
            Write-Host "🗑️  Send to Recycle Bin / trash:" -ForegroundColor Yellow
            Write-Host "    $loc  ($(Format-Size $App.SizeBytes))" -ForegroundColor White
            if ((Read-Host "Continue? (y/n)") -ne 'y') { Write-Host "❌ Cancelled." -ForegroundColor Yellow; return }

            if (Move-ToTrash $loc) {
                Write-Host "✅ Moved to trash — recoverable if this was a mistake." -ForegroundColor Green
            } else {
                Write-Host "❌ Could not move to trash." -ForegroundColor Red
            }
        }

        '5' {
            if (-not $hasPath) { Write-Host "❌ Nothing on disk to delete." -ForegroundColor Red; return }
            if ($isLocked)     { Write-Host "🛑 Protected path — refusing." -ForegroundColor Red; return }

            Write-Host ""
            Write-Host "☠️  PERMANENT DELETE — this cannot be undone." -ForegroundColor Red
            Write-Host "    $loc  ($(Format-Size $App.SizeBytes))" -ForegroundColor White

            if ($isApp)         { Write-Warning "This does NOT uninstall the app; it only removes its files." }
            if ($isVirtualDisk) { Write-Warning "VIRTUAL DISK — this destroys every image, container and volume inside it. Consider pruning and compacting instead." }

            Write-Host ""

            # Typing the name is deliberate friction. A y/n prompt is far too easy to
            # fat-finger for something unrecoverable.
            $typed = Read-Host "Type the name exactly to confirm ('$($App.Name)')"
            if ($typed -ne $App.Name) {
                Write-Host "❌ Name did not match — cancelled. Nothing was deleted." -ForegroundColor Yellow
                return
            }

            if (Remove-PathPermanently $loc) {
                Write-Host "✅ Permanently deleted — reclaimed $(Format-Size $App.SizeBytes)" -ForegroundColor Green
            } else {
                Write-Host "❌ Delete failed." -ForegroundColor Red
            }
        }

        default { Write-Host "❌ Cancelled." -ForegroundColor DarkGray }
    }
}

# ── pwsh-h registration ───────────────────────────────────────────────────────
Register-PFCommand -Name 'installed-apps' -Aliases @('i-a') -Section '🗄️ DISK RECLAIM' -Synopsis 'browse installed apps by size band; -o for overview' -Example 'i-a -o · i-a 2gb-4gb'
Register-PFCommand -Name 'disk-big'       -Aliases @('d-b') -Section '🗄️ DISK RECLAIM' -Synopsis 'large folders and files (vhdx, node_modules, caches)' -Example 'd-b 50gb-200gb'
