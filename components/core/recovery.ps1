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
    Write-Host "  3. Reinstall tools: $(Get-DependencyInstallHint 'starship fzf zoxide lsd git')" -ForegroundColor DarkGray
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
            foreach ($tool in (Get-RequiredTools)) {
                if (Install-Dependency $tool.Name) {
                    Write-Host "  ✅ $($tool.Name)" -ForegroundColor Green
                } else {
                    Write-Host "  ❌ $($tool.Name) — try: $(Get-DependencyInstallHint $tool.Name)" -ForegroundColor Red
                }
            }
        }
        "4" {
            Write-Host "🔄 Reinstalling PowerFlow..." -ForegroundColor Yellow
            irm "https://github.com/$script:POWERFLOW_REPO/releases/latest/download/install.ps1" | iex
        }
        "5" {
            $confirm = Read-Host "⚠️  Remove current profile? This will reset PowerFlow. (y/n)"
            if ($confirm -eq 'y') {
                # BACK UP FIRST. A recovery tool must never be the thing that loses the file —
                # and this same file already had a timestamped backup helper further down; the
                # delete simply did not use it. If the backup cannot be written, nothing is
                # removed: refusing is better than destroying the only copy.
                if (Test-Path -LiteralPath $PROFILE) {
                    $backup = "$PROFILE.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                    Copy-Item -LiteralPath $PROFILE -Destination $backup -ErrorAction SilentlyContinue
                    if (Test-Path -LiteralPath $backup) {
                        Write-Host "💾 Backup saved: $backup" -ForegroundColor Cyan
                    }
                    else {
                        Write-Host '❌ Could not back up the profile; nothing was removed.' -ForegroundColor Red
                        return
                    }
                }
                Remove-Item $PROFILE -Force
                Write-Host "✅ Profile removed. Restart PowerShell to use default profile." -ForegroundColor Green
            }
        }
        "6" {
            Open-Editor $PROFILE
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
        Write-Host "↩ Uninstall cancelled" -ForegroundColor DarkGray
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

    # ── Optional: remove dependencies ─────────────────────────────────────────
    Write-Host ""
    $mgr = Get-PackageManagerName
    $removeDeps = Read-Host "  Remove dependencies via $mgr (starship, fzf, zoxide, lsd)? (y/n)"
    if ($removeDeps -eq 'y') {
        if (Test-PackageManager) {
            if (Uninstall-Dependency @('starship', 'fzf', 'zoxide', 'lsd')) {
                Write-Host "✅ Dependencies removed" -ForegroundColor Green
            } else {
                Write-Host "⚠️  Some dependencies could not be removed" -ForegroundColor Yellow
            }
        } else {
            Write-Host "⚠️  No package manager found — remove dependencies manually" -ForegroundColor Yellow
        }
    }

    Write-Host ""
    Write-Host "✅ PowerFlow uninstalled" -ForegroundColor Green
    Write-Host "🔄 Restart PowerShell to apply changes" -ForegroundColor Cyan
    Write-Host "🙏 Thanks for using PowerFlow!" -ForegroundColor DarkGray
    Write-Host ""
}

# ── pwsh-h registration ───────────────────────────────────────────────────────
Register-PFCommand -Name 'pwsh-recovery'       -Section '⚙️ CONFIGURATION & SETTINGS' -Synopsis 'PowerFlow recovery and diagnostics menu'
Register-PFCommand -Name 'powerflow-uninstall' -Section '⚙️ CONFIGURATION & SETTINGS' -Synopsis 'remove PowerFlow; keeps tools you already had'
