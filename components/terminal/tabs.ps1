# ==============================================================================
# PowerFlow — Terminal Tab Management
# ==============================================================================
# Domain   : Terminal
# File     : components/terminal/tabs.ps1
# Purpose  : Open, close and navigate terminal tabs
# Functions: send-keys, open-nt, close-ct, next-t, prev-t, open-t, close-t
# Depends  : New-TerminalTab, Switch-TerminalTab, Close-TerminalTabAt,
#            Send-TerminalKeys (platform/<os>/adapters/terminal.ps1)
# ==============================================================================
#
# Windows -> Windows Terminal tabs (wt + SendKeys)
# Linux   -> tmux windows
# The adapter hides the difference; this file only expresses the commands.
# ==============================================================================

function send-keys {
    param([string]$keys)
    Send-TerminalKeys $keys
}

function open-nt {
    param([string]$Shell = "pwsh")
    New-TerminalTab -Shell $Shell -Path (Get-Location).Path | Out-Null
}

function close-ct { exit }

function next-t {
    if (Switch-TerminalTab -Direction Next) {
        Write-Host "➡️ Switched to next tab" -ForegroundColor Cyan
    }
}

function prev-t {
    if (Switch-TerminalTab -Direction Prev) {
        Write-Host "⬅️ Switched to previous tab" -ForegroundColor Cyan
    }
}

function open-t {
    param([int]$index)

    if ($index -lt 1 -or $index -gt 9) {
        Write-Host "❌ Tab index must be between 1–9" -ForegroundColor Red
        return
    }

    if (Switch-TerminalTab -Index $index) {
        Write-Host "🔀 Switched to tab $index" -ForegroundColor Cyan
    }
}

function close-t {
    param([int]$index)

    if ($index -lt 1 -or $index -gt 9) {
        Write-Host "❌ Tab index must be between 1–9" -ForegroundColor Red
        return
    }

    if (Close-TerminalTabAt -Index $index) {
        Write-Host "🗑 Closed tab $index" -ForegroundColor Yellow
    }
}

# ── pwsh-h registration ───────────────────────────────────────────────────────
Register-PFCommand -Name 'open-nt'   -Section '🪟 TERMINAL TABS' -Synopsis 'open a new terminal tab' -Platform 'Windows'
Register-PFCommand -Name 'close-ct'  -Section '🪟 TERMINAL TABS' -Synopsis 'close the current tab' -Platform 'Windows'
Register-PFCommand -Name 'next-t'    -Aliases @('prev-t') -Section '🪟 TERMINAL TABS' -Synopsis 'switch to the next / previous tab' -Platform 'Windows'
Register-PFCommand -Name 'open-t'    -Section '🪟 TERMINAL TABS' -Synopsis 'switch to tab N' -Example 'open-t 3' -Platform 'Windows'
Register-PFCommand -Name 'close-t'   -Section '🪟 TERMINAL TABS' -Synopsis 'close tab N' -Platform 'Windows'
Register-PFCommand -Name 'send-keys' -Section '🪟 TERMINAL TABS' -Synopsis 'send keystrokes to another tab' -Platform 'Windows'
