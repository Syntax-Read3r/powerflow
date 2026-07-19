# ==============================================================================
# PowerFlow — Help
# ==============================================================================
# Domain   : Help
# File     : components/help/menu.ps1
# Purpose  : pwsh-h — rendered entirely from the command registry
# Functions: pwsh-h, Show-PFCommandDetail
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
# ==============================================================================

<#
.SYNOPSIS
    pwsh-h — every PowerFlow command.
.DESCRIPTION
    pwsh-h              interactive fzf browser (plain print when piped / no fzf)
    pwsh-h -all         print everything, grouped by section
    pwsh-h git          one section (nav · git · github · files · linux · health …)
    pwsh-h chmod        one command, or its Linux lesson
    pwsh-h permissions  every lesson in a topic
#>
function pwsh-h {
    param([Parameter(Position = 0)][string]$Topic = '', [switch]$all)

    if ($all) { Show-PFHelpSections; return }

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

        Write-Host "❌ Nothing called '$Topic'. Try:  pwsh-h -all" -ForegroundColor Red
        return
    }

    # Bare pwsh-h: fzf browser when there is a human at a terminal; plain print
    # otherwise (piped output, scripts, no fzf installed).
    $interactive = -not [Console]::IsOutputRedirected -and (Get-Command fzf -ErrorAction SilentlyContinue)
    if ($interactive) { Show-PFHelpBrowser } else { Show-PFHelpSections }
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

function Show-PFHelpSections {
    param([string]$Only)

    $reg = Get-PFCommandRegistry
    Write-Host ""
    if (-not $Only) {
        Write-Host "🚀 PowerFlow v$script:POWERFLOW_VERSION — $($reg.Count) commands" -ForegroundColor Cyan
        Write-Host "   pwsh-h <section|command>  filters · bare pwsh-h opens the fzf browser" -ForegroundColor DarkGray
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
Register-PFCommand -Name 'pwsh-h' -Section '⚙️ CONFIGURATION & SETTINGS' -Synopsis 'this help - fzf browser, or filter by section/command' -Example 'pwsh-h git · pwsh-h chmod · pwsh-h -all'
