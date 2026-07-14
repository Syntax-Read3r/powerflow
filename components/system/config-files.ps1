# ==============================================================================
# PowerFlow — Configuration File Utilities
# ==============================================================================
# Domain   : System
# File     : components/system/config-files.ps1
# Purpose  : Open the PowerShell profile, Starship config, and terminal settings
# Functions: pwsh-profile, pwsh-starship, pwsh-settings
# Depends  : Open-Editor, Get-StarshipConfigPath, Get-TerminalSettingsPath
#            (platform/<os>/adapters/)
# ==============================================================================

function pwsh-profile {
    if (Test-Path $PROFILE) {
        Open-Editor $PROFILE
        Write-Host "📄 Opened PowerShell profile: $PROFILE" -ForegroundColor Cyan
    } else {
        Write-Host "⚠️ Profile does not exist at: $PROFILE" -ForegroundColor Yellow
    }
}

function pwsh-starship {
    $starshipPath = Get-StarshipConfigPath

    if (Test-Path $starshipPath) {
        Open-Editor $starshipPath
        Write-Host "🚀 Opened Starship config: $starshipPath" -ForegroundColor Cyan
    } else {
        Write-Host "❌ Could not find starship.toml at: $starshipPath" -ForegroundColor Red
    }
}

function pwsh-settings {
    $settingsPath = Get-TerminalSettingsPath

    # Linux has no Windows Terminal — the adapter returns $null.
    if (-not $settingsPath) {
        Write-Host "ℹ️  Windows Terminal settings are not available on this platform." -ForegroundColor Cyan
        Write-Host "💡 Configure your terminal emulator directly." -ForegroundColor DarkGray
        return
    }

    if (Test-Path $settingsPath) {
        Open-Editor $settingsPath
        Write-Host "⚙️  Opened Windows Terminal settings.json" -ForegroundColor Cyan
    } else {
        Write-Host "❌ Could not find Windows Terminal settings.json" -ForegroundColor Red
    }
}
