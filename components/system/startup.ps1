# ==============================================================================
# PowerFlow — Startup Items
# ==============================================================================
# Domain   : System
# File     : components/system/startup.ps1
# Purpose  : start-folder — see and manage everything that runs at login, from one
#            list, without hunting for the Startup folder
# Functions: start-folder, Show-StartupList, Invoke-StartupAction
# Depends  : Get-StartupEntry, Set-StartupEntryState, Remove-StartupEntry,
#            Add-StartupEntry, Get-StartupFolderPath
#            (platform/<os>/adapters/startup.ps1) ; Open-Path ; fzf (optional)
# ==============================================================================
#
# WHY THIS EXISTS
#
# The Startup folder is buried (shell:startup, or six levels into AppData) and it is only
# PART of the story: on Windows most autostart entries live in the registry Run keys, and
# Task Manager's "disable" doesn't delete them, it flags them. So "what starts with my
# machine?" has no single answer anywhere in the OS. start-folder is that single answer.
#
# DISABLE FIRST, DELETE SECOND
#
# The default action (Enter) TOGGLES an entry, because "stop this starting up" is what
# people actually want and it is completely reversible — Windows keeps the entry and
# clears a flag; Linux keeps the .desktop and clears Hidden=true. Deleting is a separate,
# confirmed key (ctrl-d), and it shows the full command first: a deleted registry Run
# value cannot be recovered, since nothing records what its command line was.
# That is the same reasoning as installed-apps' size bands — never put an unreviewable
# list in front of a destructive action.
# ==============================================================================

<#
.SYNOPSIS
    start-folder — manage what runs at login.
.DESCRIPTION
    start-folder            the picker: Enter toggles · ctrl-d deletes · ctrl-o opens
    start-folder list       print the list (no fzf needed; also what pipes get)
    start-folder add <path> add a program to your Startup folder
    start-folder open       open the Startup folder in your file manager

    Windows shows the Startup folders AND the registry Run keys, with each entry's real
    enabled/disabled state (Task Manager disables by flag, not deletion). Linux shows XDG
    autostart .desktop entries, where Hidden=true is the same idea.
.EXAMPLE
    start-folder
    start-folder add "C:\Tools\thing.exe"
#>
function start-folder {
    param([Parameter(Position = 0)][string]$Action, [Parameter(Position = 1)][string]$Target)

    switch ($Action.ToLower()) {
        'open' {
            $p = Get-StartupFolderPath
            Write-Host "📂 $p" -ForegroundColor Cyan
            Open-Path $p
            return
        }
        'add' {
            if (-not $Target) { Write-Host "❌ Which program? e.g. start-folder add C:\Tools\thing.exe" -ForegroundColor Red; return }
            if (Add-StartupEntry -Path $Target) {
                Write-Host "✅ Added to startup: $Target" -ForegroundColor Green
                Write-Host "   (start-folder to see it · Enter there toggles it off)" -ForegroundColor DarkGray
            } else {
                Write-Host "❌ Could not add '$Target' (does the path exist?)" -ForegroundColor Red
            }
            return
        }
    }

    $entries = @(Get-StartupEntry)
    if ($entries.Count -eq 0) {
        Write-Host ""
        Write-Host "✨ Nothing runs at login." -ForegroundColor Green
        Write-Host "   Add something with:  start-folder add <path>" -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    # Print mode: asked for explicitly, piped, or no fzf. Never launches a picker.
    $interactive = -not [Console]::IsOutputRedirected -and (Get-Command fzf -ErrorAction SilentlyContinue)
    if ($Action -eq 'list' -or -not $interactive) { Show-StartupList $entries; return }

    # ── the picker is a MANAGER ────────────────────────────────────────────────
    # --expect reports which key ended the selection, so one picker does three verbs.
    $lines = $entries | ForEach-Object {
        $mark = if ($_.State -eq 'disabled') { '○' } else { '●' }
        $adm  = if ($_.Scope -eq 'machine') { ' 🔒' } else { '' }
        # index <TAB> display — the index maps the choice back to the real object.
        "{0}`t{1} {2}{3}  ·  {4}  ·  {5}" -f $entries.IndexOf($_), $mark, $_.Name, $adm, $_.Source, $_.Command
    }

    $sel = $lines | fzf `
        --delimiter "`t" --with-nth 2 `
        --expect=ctrl-d,ctrl-o `
        --reverse --border=rounded --height=70% `
        --prompt="🚀 Startup: " `
        --header="● on · ○ off · 🔒 needs admin — Enter toggles · ctrl-d deletes · ctrl-o opens folder · Esc closes" `
        --header-first `
        --color="header:bold:cyan,prompt:bold:green,border:cyan"

    $fzfExit = $LASTEXITCODE
    if (-not $sel) {
        if ($fzfExit -eq 1) { Write-PFNothingFound 'No startup entry matched what you typed.' }
        return
    }

    # fzf's FIRST output line is the pressed key ('' for Enter), the second is the row.
    $keyPressed = @($sel)[0]
    $row        = @($sel)[1]
    if (-not $row) { Write-Host "↩ Cancelled" -ForegroundColor DarkGray; return }

    $entry = $entries[[int](($row -split "`t")[0])]
    Invoke-StartupAction -Entry $entry -Key $keyPressed
}

function Show-StartupList {
    param($Entries)

    Write-Host ""
    Write-Host "🚀 Runs at login — $($Entries.Count) item$(if ($Entries.Count -ne 1) { 's' })" -ForegroundColor Cyan
    $w = ($Entries.Name | Measure-Object -Maximum Length).Maximum + 2

    foreach ($group in ($Entries | Group-Object Source)) {
        Write-Host ""
        Write-Host "  $($group.Name)" -ForegroundColor DarkCyan
        foreach ($e in $group.Group) {
            $on = $e.State -ne 'disabled'
            Write-Host "    $(if ($on) { '●' } else { '○' }) " -NoNewline -ForegroundColor $(if ($on) { 'Green' } else { 'DarkGray' })
            Write-Host ($e.Name.PadRight($w)) -NoNewline -ForegroundColor $(if ($on) { 'White' } else { 'DarkGray' })
            if ($e.State -eq 'disabled') { Write-Host "[off] " -NoNewline -ForegroundColor Yellow }
            if ($e.Scope -eq 'machine')  { Write-Host "[admin] " -NoNewline -ForegroundColor DarkYellow }
            Write-Host $e.Command -ForegroundColor DarkGray
        }
    }
    Write-Host ""
    Write-Host "   start-folder to manage these · start-folder add <path> to add one" -ForegroundColor DarkGray
    if ($script:PowerFlowOS -eq 'linux') {
        Write-Host "   (XDG autostart runs at DESKTOP login — not on SSH; services live in systemctl --user)" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# Apply whichever verb the picker's key selected.
function Invoke-StartupAction {
    param([Parameter(Mandatory)]$Entry, [string]$Key)

    switch ($Key) {
        'ctrl-o' {
            $p = Get-StartupFolderPath -Machine:($Entry.Scope -eq 'machine')
            Write-Host "📂 $p" -ForegroundColor Cyan
            Open-Path $p
        }
        'ctrl-d' {
            Write-Host ""
            Write-Host "🗑️  Delete this startup entry?" -ForegroundColor Yellow
            Write-Host "    $($Entry.Name)" -ForegroundColor White
            Write-Host "    $($Entry.Source)" -ForegroundColor DarkGray
            Write-Host "    $($Entry.Command)" -ForegroundColor DarkGray
            if ($Entry.Kind -eq 'registry') {
                Write-Host "    ⚠️  A registry entry cannot be restored — nothing records its command line." -ForegroundColor Red
                Write-Host "       Enter (toggle off) is reversible and usually what you want." -ForegroundColor DarkGray
            }
            if ([Console]::IsInputRedirected) { Write-Host "   (need a terminal to confirm)" -ForegroundColor DarkGray; return }
            if ((Read-Host "    Type the name to confirm") -ne $Entry.Name) {
                Write-Host "❌ Not deleted." -ForegroundColor Yellow; return
            }
            if (Remove-StartupEntry -Entry $Entry) { Write-Host "✅ Deleted: $($Entry.Name)" -ForegroundColor Green }
            else { Write-Host "❌ Could not delete '$($Entry.Name)'." -ForegroundColor Red }
        }
        default {
            # Enter → toggle. The reversible verb, so no confirmation.
            $turnOn = ($Entry.State -eq 'disabled')
            $verb   = if ($turnOn) { 'ON' } else { 'OFF' }
            Write-Host ""
            Write-Host "🔧 Turning $($Entry.Name) $verb ..." -ForegroundColor DarkGray
            if (Set-StartupEntryState -Entry $Entry -Enabled $turnOn) {
                Write-Host "✅ $($Entry.Name) is now $verb at login" -ForegroundColor Green
                Write-Host "   (run start-folder again and press Enter to put it back)" -ForegroundColor DarkGray
            } else {
                Write-Host "❌ Could not change '$($Entry.Name)'." -ForegroundColor Red
                if ($Entry.Scope -eq 'machine') { Write-Host "   It is machine-wide — approve the UAC prompt, or run elevated." -ForegroundColor DarkGray }
            }
        }
    }
}

Set-Alias startup start-folder

# ── registration ──────────────────────────────────────────────────────────────
Register-PFCommand -Name 'start-folder' -Section '⚙️ CONFIGURATION & SETTINGS' -Aliases @('startup') `
    -Synopsis 'manage what runs at login - Enter toggles, ctrl-d deletes' `
    -Example 'start-folder · start-folder list · start-folder add C:\t.exe'
