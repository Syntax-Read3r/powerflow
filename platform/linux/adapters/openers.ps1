# ==============================================================================
# PowerFlow — Openers Adapter (Linux)
# ==============================================================================
# Domain   : Platform / Linux
# File     : platform/linux/adapters/openers.ps1
# Purpose  : Open paths, files and URLs via xdg-open and the configured editor
# Contract : Open-Path, Open-Editor, Open-Url, Get-FileManagerName
# Depends  : none
# ==============================================================================

function Get-FileManagerName { return 'file manager' }

function Open-Path {
    param([Parameter(Mandatory)][string]$Path)

    if (Get-Command xdg-open -ErrorAction SilentlyContinue) {
        xdg-open $Path 2>/dev/null
    }
    else {
        Write-Host "⚠️  xdg-open not found — cannot open a file manager." -ForegroundColor Yellow
        Write-Host "   Path: $Path" -ForegroundColor DarkGray
    }
}

# Open in $EDITOR if set, else VS Code, else fall back to a sensible terminal editor.
function Open-Editor {
    param([Parameter(Mandatory)][string]$Path)

    if ($env:EDITOR -and (Get-Command $env:EDITOR -ErrorAction SilentlyContinue)) {
        & $env:EDITOR $Path
    }
    elseif (Get-Command code -ErrorAction SilentlyContinue) {
        code $Path
    }
    elseif (Get-Command nano -ErrorAction SilentlyContinue) {
        nano $Path
    }
    else {
        Write-Host "⚠️  No editor found. Set \$env:EDITOR or install VS Code." -ForegroundColor Yellow
        Write-Host "   Path: $Path" -ForegroundColor DarkGray
    }
}

function Open-Url {
    param([Parameter(Mandatory)][string]$Url)

    if (Get-Command xdg-open -ErrorAction SilentlyContinue) {
        xdg-open $Url 2>/dev/null
    }
    else {
        Write-Host "⚠️  xdg-open not found — copy this URL manually:" -ForegroundColor Yellow
        Write-Host "   $Url" -ForegroundColor Cyan
    }
}
