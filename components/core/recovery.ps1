# ==============================================================================
# PowerFlow — Recovery
# ==============================================================================
# Domain   : Core
# File     : components/core/recovery.ps1
# Purpose  : Provides an interactive recovery and diagnostics menu for fixing PowerFlow issues
# Functions: pwsh-recovery, powerflow-uninstall
# Depends  : components/core/version.ps1, components/help/menu.ps1
# ==============================================================================

<#
.SYNOPSIS
    PowerFlow recovery and diagnostics
.DESCRIPTION
    Provides recovery options when PowerFlow has issues
.EXAMPLE
    pwsh-recovery     # Shows recovery options
#>
function pwsh-recovery {
    Write-Host ""
    Write-Host "🚑 PowerFlow Recovery Options:" -ForegroundColor Red
    Write-Host "═══════════════════════════════" -ForegroundColor Red
    Write-Host ""
    Write-Host "🔄 Quick Fixes:" -ForegroundColor Cyan
    Write-Host "  1. Reload profile: . `$PROFILE" -ForegroundColor DarkGray
    Write-Host "  2. Check dependencies: Get-Command starship,fzf,zoxide,lsd,git" -ForegroundColor DarkGray
    Write-Host "  3. Reinstall tools: scoop install starship fzf zoxide lsd git" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "🔧 Recovery Actions:" -ForegroundColor Cyan
    Write-Host "  4. Reinstall PowerFlow: irm https://raw.githubusercontent.com/$script:POWERFLOW_REPO/main/install.ps1 | iex" -ForegroundColor DarkGray
    Write-Host "  5. Reset to safe mode: Remove-Item `$PROFILE; . `$PROFILE" -ForegroundColor DarkGray
    Write-Host "  6. Edit profile manually: code `$PROFILE" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "📋 Diagnostics:" -ForegroundColor Cyan
    Write-Host "  7. Version info: Get-PowerFlowVersion" -ForegroundColor DarkGray
    Write-Host "  8. Check for updates: powerflow-update" -ForegroundColor DarkGray
    Write-Host "  9. Full help: pwsh-h" -ForegroundColor DarkGray
    Write-Host ""

    $choice = Read-Host "Choose an option (1-9) or 'q' to quit"

    switch ($choice) {
        "1" {
            Write-Host "🔄 Reloading profile..." -ForegroundColor Yellow
            . $PROFILE
        }
        "2" {
            Write-Host "🔍 Checking dependencies..." -ForegroundColor Yellow
            $tools = @("starship", "fzf", "zoxide", "lsd", "git")
            foreach ($tool in $tools) {
                $found = Get-Command $tool -ErrorAction SilentlyContinue
                Write-Host "  $tool : $(if ($found) { '✅ Found' } else { '❌ Missing' })" -ForegroundColor $(if ($found) { 'Green' } else { 'Red' })
            }
        }
        "3" {
            Write-Host "📦 Installing dependencies..." -ForegroundColor Yellow
            scoop install starship fzf zoxide lsd git
        }
        "4" {
            Write-Host "🔄 Reinstalling PowerFlow..." -ForegroundColor Yellow
            irm "https://raw.githubusercontent.com/$script:POWERFLOW_REPO/main/install.ps1" | iex
        }
        "5" {
            $confirm = Read-Host "⚠️  Remove current profile? This will reset PowerFlow. (y/n)"
            if ($confirm -eq 'y') {
                Remove-Item $PROFILE -Force
                Write-Host "✅ Profile removed. Restart PowerShell to use default profile." -ForegroundColor Green
            }
        }
        "6" {
            code $PROFILE
        }
        "7" {
            Get-PowerFlowVersion
        }
        "8" {
            powerflow-update
        }
        "9" {
            pwsh-h
        }
        "q" {
            Write-Host "👋 Recovery menu closed" -ForegroundColor DarkGray
        }
        default {
            Write-Host "❌ Invalid option" -ForegroundColor Red
        }
    }
}

function powerflow-uninstall {
    $profilePath = $PROFILE
    $profileDir  = Split-Path $profilePath -Parent

    Write-Host ""
    Write-Host "🗑️  PowerFlow Uninstall" -ForegroundColor Yellow
    Write-Host "═══════════════════════" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Profile   : $profilePath" -ForegroundColor DarkGray
    Write-Host "  Directory : $profileDir" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  This will remove:" -ForegroundColor White
    Write-Host "    • Microsoft.PowerShell_profile.ps1 (bootloader)" -ForegroundColor DarkGray
    Write-Host "    • config\  (settings)" -ForegroundColor DarkGray
    Write-Host "    • components\  (all functions)" -ForegroundColor DarkGray
    Write-Host ""

    $confirm = Read-Host "  Are you sure you want to uninstall PowerFlow? (yes/n)"
    if ($confirm -ne 'yes') {
        Write-Host "❌ Uninstall cancelled" -ForegroundColor Yellow
        return
    }

    # ── Backup ────────────────────────────────────────────────────────────────
    if (Test-Path $profilePath) {
        $backup = "$profilePath.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $profilePath $backup -ErrorAction SilentlyContinue
        Write-Host "💾 Backup saved: $backup" -ForegroundColor Cyan
    }

    # ── Remove bootloader ─────────────────────────────────────────────────────
    if (Test-Path $profilePath) {
        Remove-Item $profilePath -Force
        Write-Host "✅ Removed bootloader" -ForegroundColor Green
    }

    # ── Remove component directories ──────────────────────────────────────────
    foreach ($folder in @("config", "components")) {
        $path = Join-Path $profileDir $folder
        if (Test-Path $path) {
            Remove-Item $path -Recurse -Force
            Write-Host "✅ Removed $folder\" -ForegroundColor Green
        }
    }

    # ── Optional: remove Scoop dependencies ───────────────────────────────────
    Write-Host ""
    $removeDeps = Read-Host "  Remove Scoop dependencies (starship, fzf, zoxide, lsd)? (y/n)"
    if ($removeDeps -eq 'y') {
        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            scoop uninstall starship fzf zoxide lsd 2>$null
            Write-Host "✅ Scoop dependencies removed" -ForegroundColor Green
        } else {
            Write-Host "⚠️  Scoop not found — remove dependencies manually" -ForegroundColor Yellow
        }
    }

    Write-Host ""
    Write-Host "✅ PowerFlow uninstalled" -ForegroundColor Green
    Write-Host "🔄 Restart PowerShell to apply changes" -ForegroundColor Cyan
    Write-Host "🙏 Thanks for using PowerFlow!" -ForegroundColor DarkGray
    Write-Host ""
}
