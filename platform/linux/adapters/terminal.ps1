# ==============================================================================
# PowerFlow — Terminal Adapter (Linux)
# ==============================================================================
# Domain   : Platform / Linux
# File     : platform/linux/adapters/terminal.ps1
# Purpose  : Terminal "tab" management via tmux windows
# Contract : Test-TerminalSupport, Get-TerminalName, New-TerminalTab,
#            Send-TerminalKeys, Switch-TerminalTab, Close-TerminalTabAt
# Depends  : none
# ==============================================================================
#
# Linux has no single terminal API — every emulator differs. tmux is the portable
# answer: its *windows* map cleanly onto Windows Terminal *tabs*, and it works in
# any emulator, over SSH, and headless.
#
# Everything degrades gracefully: if tmux is missing, or we are not inside a tmux
# session, the command explains what to do instead of throwing.
# ==============================================================================

function Get-TerminalName { return 'tmux' }

function Test-TmuxInstalled {
    return [bool](Get-Command tmux -ErrorAction SilentlyContinue)
}

function Test-InTmuxSession {
    return [bool]$env:TMUX
}

function Test-TerminalSupport {
    return ((Test-TmuxInstalled) -and (Test-InTmuxSession))
}

# Shared guard — returns $true when tab commands can run.
function Assert-TerminalSupport {
    if (-not (Test-TmuxInstalled)) {
        Write-Host "❌ Tab management on Linux requires tmux." -ForegroundColor Red
        Write-Host "💡 Install it: $(Get-DependencyInstallHint 'tmux')" -ForegroundColor DarkGray
        return $false
    }
    if (-not (Test-InTmuxSession)) {
        Write-Host "❌ Not inside a tmux session — there are no tabs to manage." -ForegroundColor Red
        Write-Host "💡 Start one:  tmux" -ForegroundColor DarkGray
        return $false
    }
    return $true
}

function Send-TerminalKeys {
    param([Parameter(Mandatory)][string]$Keys)
    if (-not (Assert-TerminalSupport)) { return }
    tmux send-keys $Keys 2>$null
}

# Open a new tmux window running $Shell, starting in $Path.
function New-TerminalTab {
    param(
        [string]$Shell = 'pwsh',
        [string]$Path  = (Get-Location).Path
    )

    if (-not (Assert-TerminalSupport)) { return $false }

    $command = switch ($Shell.ToLower()) {
        { $_ -in @('pwsh', 'powershell', 'ps') } { 'pwsh' }
        { $_ -in @('bash', 'sh') }               { 'bash' }
        { $_ -in @('zsh') }                      { 'zsh' }
        { $_ -in @('fish') }                     { 'fish' }
        default                                   { $env:SHELL }
    }

    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        Write-Host "❌ Shell not found: $command" -ForegroundColor Red
        return $false
    }

    tmux new-window -c "$Path" $command 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "🆕 Opened new $command window in: $Path" -ForegroundColor Green
        return $true
    }

    Write-Host "❌ Failed to open a new tmux window." -ForegroundColor Red
    return $false
}

# Switch windows. -Index N jumps to that window; -Direction Next/Prev cycles.
function Switch-TerminalTab {
    param(
        [int]$Index,
        [ValidateSet('Next', 'Prev')][string]$Direction
    )

    if (-not (Assert-TerminalSupport)) { return $false }

    if     ($Direction -eq 'Next') { tmux next-window 2>$null }
    elseif ($Direction -eq 'Prev') { tmux previous-window 2>$null }
    else                           { tmux select-window -t $Index 2>$null }

    return ($LASTEXITCODE -eq 0)
}

function Close-TerminalTabAt {
    param([Parameter(Mandatory)][int]$Index)

    if (-not (Assert-TerminalSupport)) { return $false }

    tmux kill-window -t $Index 2>$null
    return ($LASTEXITCODE -eq 0)
}
