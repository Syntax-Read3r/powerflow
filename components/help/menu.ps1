# ==============================================================================
# PowerFlow — Help
# ==============================================================================
# Domain   : Help
# File     : components/help/menu.ps1
# Purpose  : pwsh-h — rendered entirely from the command registry
# Functions: pwsh-h, Show-PFManual, Show-PFHelpSections, Show-PFCommandDetail,
#            Show-PFHelpBrowser
# Depends  : components/help/registry.ps1 (the data), components/shell/lessons.ps1
# ==============================================================================
#
# There is no hand-drawn menu any more. Every row below is GENERATED from
# Register-PFCommand calls that live beside the functions they document, so the
# help cannot drift from the code — CI fails the release if a user-facing command
# has no registration (release-validate.yml, "help registry covers every command").
#
# The old menu was a 350-line wall of box characters: rows went missing (an audit
# found 4), went false (`ls -t` documented as "tree view" a full version after it
# became GNU time-sort), and 11 rows drifted off the 80-char grid from emoji-width
# bugs. Alignment is now arithmetic, not surgery.
#
# TWO VIEWS, ON PURPOSE:
#   pwsh-h        the MANUAL — the default. A quiet, grouped, printed reference you
#                 scroll like a page. A handful of broad chapters, no fzf, no chrome.
#   pwsh-h -a     the BROWSER — the interactive fzf finder (was the old default). For
#                 when you want to search rather than read.
# The default is the manual because "show me everything, let me read" is what a help
# command is for; searching is the power move you opt into.
# ==============================================================================

<#
.SYNOPSIS
    pwsh-h — every PowerFlow command.
.DESCRIPTION
    pwsh-h              the manual — grouped, printed, scroll to read (the default)
    pwsh-h -a           the interactive fzf browser  (pwsh-help -advanced also works)
    pwsh-h git          one section (nav · git · github · files · linux · health …)
    pwsh-h chmod        one command, or its Linux lesson
    pwsh-h permissions  every lesson in a topic
#>
function pwsh-h {
    param([Parameter(Position = 0)][string]$Topic = '', [switch]$a, [switch]$advanced, [switch]$all)

    # -a / -advanced → the searchable fzf browser. Falls back to the manual when output
    # is redirected or fzf is absent (a pipe, a script, CI) so it can never hang.
    if ($a -or $advanced) {
        $interactive = -not [Console]::IsOutputRedirected -and (Get-Command fzf -ErrorAction SilentlyContinue)
        if ($interactive) { Show-PFHelpBrowser } else { Show-PFManual }
        return
    }

    if ($Topic) {
        $reg = Get-PFCommandRegistry

        # 1. Exact command (or alias) → detail view, plus its lesson if one exists.
        $hit = $reg | Where-Object { $_.Name -eq $Topic -or $Topic -in $_.Aliases } | Select-Object -First 1
        if ($hit) { Show-PFCommandDetail $hit; return }

        # 2. A Linux lesson (real name, brother name, or topic like 'permissions').
        if ((Get-Command Get-LinuxLesson -ErrorAction SilentlyContinue) -and (Get-LinuxLesson -Command $Topic)) {
            Show-Lesson -Command $Topic; return
        }
        if ((Get-Command Get-LessonTopics -ErrorAction SilentlyContinue) -and ($Topic.ToLower() -in (Get-LessonTopics))) {
            lesson $Topic; return
        }

        # 3. A section keyword: pwsh-h git → 🎯 ENHANCED GIT WORKFLOW, etc.
        $sections = @((Get-PFHelpSections) | Where-Object { $_ -match [regex]::Escape($Topic) })
        if ($sections.Count -gt 0) {
            foreach ($s in $sections) { Show-PFHelpSections -Only $s }
            return
        }

        # 4. Substring match over names + synopses — a search, effectively.
        $near = @($reg | Where-Object { $_.Name -match [regex]::Escape($Topic) -or $_.Synopsis -match [regex]::Escape($Topic) })
        if ($near.Count -gt 0) {
            Write-Host ""
            Write-Host "🔍 Commands matching '$Topic':" -ForegroundColor Cyan
            Show-PFHelpRows $near
            Write-Host ""
            return
        }

        Write-Host "❌ Nothing called '$Topic'. Try:  pwsh-h" -ForegroundColor Red
        return
    }

    # Bare pwsh-h (and the legacy -all): the readable manual. No fzf, so it prints and
    # scrolls the same at a terminal, down a pipe, or in CI.
    Show-PFManual
}

# ── the generated print view ──────────────────────────────────────────────────
function Show-PFHelpRows {
    param($Commands)
    # One computed width for the whole run — this is the entire alignment system.
    $w = ($Commands | ForEach-Object {
        $_.Name.Length + $(if ($_.Aliases.Count) { (" (" + ($_.Aliases -join ', ') + ")").Length } else { 0 })
    } | Measure-Object -Maximum).Maximum + 2

    foreach ($c in $Commands) {
        $label = $c.Name + $(if ($c.Aliases.Count) { " (" + ($c.Aliases -join ', ') + ")" } else { "" })
        Write-Host ("  {0}" -f $label.PadRight($w)) -NoNewline -ForegroundColor Green
        Write-Host $c.Synopsis -ForegroundColor White
    }
}

# ── the manual (default pwsh-h) ───────────────────────────────────────────────
# A printed reference grouped into chapters (registry.ps1 → $PF_HelpChapters), meant to
# be read and scrolled, not searched. Commands are platform-filtered by the registry, so
# a Linux box never sees Windows-only rows and vice-versa.
function Show-PFManual {
    $reg  = Get-PFCommandRegistry
    $rule = '─' * 54

    Write-Host ""
    Write-Host "  PowerFlow Command Manual" -NoNewline -ForegroundColor Cyan
    Write-Host "   v$script:POWERFLOW_VERSION · $($reg.Count) commands" -ForegroundColor DarkGray
    Write-Host "  $rule" -ForegroundColor DarkGray
    Write-Host "  Scroll to read.  " -NoNewline -ForegroundColor DarkGray
    Write-Host "pwsh-h <name>" -NoNewline -ForegroundColor Green
    Write-Host " opens one in detail · " -NoNewline -ForegroundColor DarkGray
    Write-Host "pwsh-h -a" -NoNewline -ForegroundColor Green
    Write-Host " searches." -ForegroundColor DarkGray

    # Fold sections into chapters, preserving each chapter's section order (and the
    # registry's within-section order) — Sort-Object is unstable, so we collect by hand.
    $seen = @()
    foreach ($chapter in (Get-PFHelpChapters)) {
        $rows = @()
        foreach ($sec in $chapter.Sections) { $rows += @($reg | Where-Object Section -eq $sec) }
        $seen += $chapter.Sections
        if ($rows.Count) { Show-PFManualChapter $chapter.Title $rows $rule }
    }

    # Anything registered into a section no chapter claims still prints — a new section
    # can't silently disappear from the manual just because nobody filed it in a chapter.
    $orphans = @($reg | Where-Object { $_.Section -notin $seen })
    if ($orphans.Count) { Show-PFManualChapter '📦 MORE' $orphans $rule }

    Write-Host ""
}

function Show-PFManualChapter {
    param([string]$Title, $Rows, [string]$Rule)
    Write-Host ""
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "  $Rule" -ForegroundColor DarkGray

    # One column width for the chapter — the whole alignment system, same as the sections
    # view. Names print green, aliases dim; padding is computed from the full label so the
    # two colours don't throw the synopsis column off.
    $w = ($Rows | ForEach-Object {
        $_.Name.Length + $(if ($_.Aliases.Count) { (" (" + ($_.Aliases -join ', ') + ")").Length } else { 0 })
    } | Measure-Object -Maximum).Maximum + 2

    foreach ($c in $Rows) {
        $aliasStr = if ($c.Aliases.Count) { " (" + ($c.Aliases -join ', ') + ")" } else { "" }
        $labelLen = $c.Name.Length + $aliasStr.Length
        Write-Host "    " -NoNewline
        Write-Host $c.Name -NoNewline -ForegroundColor Green
        if ($aliasStr) { Write-Host $aliasStr -NoNewline -ForegroundColor DarkGray }
        Write-Host (' ' * [Math]::Max(1, $w - $labelLen)) -NoNewline
        Write-Host $c.Synopsis -ForegroundColor Gray
    }
}

function Show-PFHelpSections {
    param([string]$Only)

    $reg = Get-PFCommandRegistry
    Write-Host ""
    if (-not $Only) {
        Write-Host "🚀 PowerFlow v$script:POWERFLOW_VERSION — $($reg.Count) commands" -ForegroundColor Cyan
        Write-Host "   pwsh-h <section|command>  filters · bare pwsh-h is the manual · pwsh-h -a searches" -ForegroundColor DarkGray
    }

    foreach ($section in (Get-PFHelpSections)) {
        if ($Only -and $section -ne $Only) { continue }
        $rows = @($reg | Where-Object Section -eq $section)
        if ($rows.Count -eq 0) { continue }
        Write-Host ""
        Write-Host $section -ForegroundColor Cyan
        Show-PFHelpRows $rows
    }
    Write-Host ""
}

# ── the detail view (also the fzf preview content) ────────────────────────────
function Show-PFCommandDetail {
    param($Command)

    Write-Host ""
    Write-Host "  $($Command.Name)" -NoNewline -ForegroundColor Green
    if ($Command.Aliases.Count) { Write-Host "  ($($Command.Aliases -join ', '))" -NoNewline -ForegroundColor DarkGray }
    if ($Command.Platform -ne 'Both') { Write-Host "  [$($Command.Platform) only]" -NoNewline -ForegroundColor Yellow }
    Write-Host ""
    Write-Host "  $($Command.Synopsis)" -ForegroundColor White
    if ($Command.Example) {
        Write-Host "  e.g.  " -NoNewline -ForegroundColor DarkGray
        Write-Host $Command.Example -ForegroundColor Cyan
    }
    Write-Host "  $($Command.Section)" -ForegroundColor DarkGray

    # If a lesson exists for this command, say so — the two systems stay linked.
    if ((Get-Command Get-LinuxLesson -ErrorAction SilentlyContinue) -and (Get-LinuxLesson -Command $Command.Name)) {
        Write-Host "  🎓 there is a lesson:  lesson $($Command.Name)" -ForegroundColor Cyan
    }
    Write-Host ""
}

# ── the fzf browser ───────────────────────────────────────────────────────────
function Show-PFHelpBrowser {
    $reg = Get-PFCommandRegistry

    # Preview files: one per command, regenerated when the count changes (i.e. on
    # upgrade). fzf's preview runs under cmd on Windows and sh on Linux — reading a
    # file is the one thing both do identically.
    $pvDir = Join-Path (Get-TempPath) 'powerflow-help'
    $stamp = Join-Path $pvDir 'count.txt'
    if (-not (Test-Path $stamp) -or (Get-Content $stamp -ErrorAction SilentlyContinue) -ne "$($reg.Count)") {
        New-Item -ItemType Directory -Path $pvDir -Force | Out-Null
        foreach ($c in $reg) {
            $safe = ($c.Name -replace '[^\w-]', '_')
            $txt  = @("$($c.Name)" + $(if ($c.Aliases.Count) { "  ($($c.Aliases -join ', '))" } else { "" }))
            $txt += ""
            $txt += "  $($c.Synopsis)"
            if ($c.Example)            { $txt += "  e.g. $($c.Example)" }
            if ($c.Platform -ne 'Both'){ $txt += "  [$($c.Platform) only]" }
            $txt += ""
            $txt += "  $($c.Section)"
            $txt -join "`n" | Set-Content (Join-Path $pvDir "$safe.txt") -Encoding UTF8
        }
        "$($reg.Count)" | Set-Content $stamp
    }

    $reader = if ($script:PowerFlowOS -eq 'linux') { 'cat' } else { 'type' }
    $lines  = $reg | ForEach-Object {
        $safe = ($_.Name -replace '[^\w-]', '_')
        # name <TAB> synopsis <TAB> preview-file — fzf shows fields 1-2, preview reads 3
        "{0}`t{1}`t{2}" -f $_.Name, $_.Synopsis, (Join-Path $pvDir "$safe.txt")
    }

    $sel = $lines | fzf `
        --delimiter "`t" --with-nth "1,2" --nth 1,2 `
        --preview "$reader {3}" --preview-window 'down,7,wrap' `
        --reverse --border=rounded --height=80% `
        --prompt="📖 PowerFlow help: " `
        --header="$($reg.Count) commands — type to filter · Enter for details · Esc to close" `
        --header-first `
        --color="header:bold:cyan,prompt:bold:green,border:cyan"

    if ($sel) {
        $name = ($sel -split "`t")[0]
        $cmd  = (Get-PFCommandRegistry) | Where-Object Name -eq $name | Select-Object -First 1
        if ($cmd) { Show-PFCommandDetail $cmd }
    }
}

# ── pwsh-h registration ───────────────────────────────────────────────────────
# pwsh-help is the long name; it takes the same flags, so `pwsh-help -advanced` == `pwsh-h -a`.
Set-Alias pwsh-help pwsh-h
Register-PFCommand -Name 'pwsh-h' -Section '⚙️ CONFIGURATION & SETTINGS' -Aliases @('pwsh-help') `
    -Synopsis 'the command manual - grouped list; -a for the fzf browser' `
    -Example 'pwsh-h · pwsh-h -a · pwsh-h git'
