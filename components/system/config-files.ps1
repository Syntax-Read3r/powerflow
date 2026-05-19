# ==============================================================================
# PowerFlow — Configuration File Utilities
# ==============================================================================
# Domain   : System
# File     : components/system/config-files.ps1
# Purpose  : Open PowerShell profile, Starship config, and Windows Terminal settings in VS Code
# Functions: pwsh-profile, pwsh-starship, pwsh-settings
# Depends  : none
# ==============================================================================

function pwsh-profile {
    if (Test-Path $PROFILE) {
        code $PROFILE
        Write-Host "📄 Opened PowerShell profile: $PROFILE" -ForegroundColor Cyan
    } else {
        Write-Host "⚠️ Profile does not exist at: $PROFILE" -ForegroundColor Yellow
    }
}

function pwsh-starship {
    $starshipPath = "$HOME\\.config\\starship.toml"

    if (Test-Path $starshipPath) {
        code $starshipPath
        Write-Host "🚀 Opened Starship config: $starshipPath" -ForegroundColor Cyan
    } else {
        Write-Host "❌ Could not find starship.toml at: $starshipPath" -ForegroundColor Red
    }
}

function pwsh-settings {
    $wtSettings = "$env:LOCALAPPDATA\\Packages\\Microsoft.WindowsTerminal_8wekyb3d8bbwe\\LocalState\\settings.json"

    if (Test-Path $wtSettings) {
        code $wtSettings
        Write-Host "⚙️  Opened Windows Terminal settings.json" -ForegroundColor Cyan
    } else {
        Write-Host "❌ Could not find Windows Terminal settings.json" -ForegroundColor Red
    }
}
