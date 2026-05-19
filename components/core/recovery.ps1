# ==============================================================================
# PowerFlow — Recovery
# ==============================================================================
# Domain   : Core
# File     : components/core/recovery.ps1
# Purpose  : Provides an interactive recovery and diagnostics menu for fixing PowerFlow issues
# Functions: pwsh-recovery
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
