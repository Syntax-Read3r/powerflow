# ==============================================================================
# PowerFlow — WSL Launcher
# ==============================================================================
# Domain   : Terminal
# File     : components/terminal/wsl.ps1
# Purpose  : Open Ubuntu/WSL tabs with path bridging from Windows to WSL filesystem
# Functions: open-ubuntu, open-wsl-simple
# Depends  : none
# ==============================================================================

# Alternative: Direct profile launcher by GUID (most reliable)
function open-ubuntu {
    Write-Host "🐧 Opening Ubuntu-20.04 directly..." -ForegroundColor Cyan

    # Use the exact GUID from your Windows Terminal settings
    $ubuntuGuid = "{07b52e3e-de2c-5db4-bd2d-ba144ed6c273}"

    try {
        Start-Process "wt" -ArgumentList "-w", "0", "nt", "-p", $ubuntuGuid -NoNewWindow
        Write-Host "✅ Ubuntu-20.04 tab opened!" -ForegroundColor Green

        # Show navigation command
        $currentPath = (Get-Location).Path
        $drive = $currentPath.Substring(0,1).ToLower()
        $restOfPath = $currentPath.Substring(3) -replace "\\", "/"
        $wslPath = "/mnt/$drive/$restOfPath"

        Write-Host ""
        Write-Host "📁 Navigate to current directory with:" -ForegroundColor Yellow
        Write-Host "cd '$wslPath'" -ForegroundColor White
        Set-Clipboard "cd '$wslPath'"
        Write-Host "📋 Command copied to clipboard!" -ForegroundColor Green

    } catch {
        Write-Host "❌ Failed to open Ubuntu: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "💡 Try manually clicking the dropdown and selecting Ubuntu-20.04" -ForegroundColor Yellow
    }
}

# Test what profile GUIDs are actually available

# Ultra-simple launcher that just uses the profile name
function open-wsl-simple {
    param([string]$ProfileName = "Ubuntu-20.04")

    Write-Host "🐧 Opening $ProfileName..." -ForegroundColor Cyan
    wt -w 0 nt -p $ProfileName

    $currentPath = (Get-Location).Path
    $drive = $currentPath.Substring(0,1).ToLower()
    $restOfPath = $currentPath.Substring(3) -replace "\\", "/"
    $wslPath = "/mnt/$drive/$restOfPath"

    Write-Host "✅ Tab opened! Navigate with: cd '$wslPath'" -ForegroundColor Green
    Set-Clipboard "cd '$wslPath'"
    Write-Host "📋 Command copied!" -ForegroundColor Green
}

# ── pwsh-h registration ───────────────────────────────────────────────────────
Register-PFCommand -Name 'open-ubuntu'     -Section '🐧 WSL (WINDOWS-ONLY)' -Synopsis 'open a WSL Ubuntu tab in Windows Terminal' -Platform 'Windows'
Register-PFCommand -Name 'open-wsl-simple' -Section '🐧 WSL (WINDOWS-ONLY)' -Synopsis 'open WSL without Terminal profiles' -Platform 'Windows'
