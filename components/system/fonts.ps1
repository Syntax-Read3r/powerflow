# ==============================================================================
# PowerFlow — Font Setup
# ==============================================================================
# Domain   : System
# File     : components/system/fonts.ps1
# Purpose  : pwsh-font — install the Nerd Font, then tell you the one manual step
# Functions: pwsh-font
# Depends  : fonts adapter — Get-NerdFontName, Test-NerdFont, Install-NerdFont,
#            Get-NerdFontInstructions
# ==============================================================================
#
# Starship and lsd draw with Nerd Font glyphs. Without the font you get tofu boxes
# or CJK fallback where icons should be, and lsd's icons overlap filenames. This
# installs the font (via the platform adapter) and prints the terminal-config step
# that no tool can do for you. All OS work is in the adapter; this only renders.
# ==============================================================================

<#
.SYNOPSIS
    pwsh-font — install the Nerd Font PowerFlow's prompt and `ls` need, and show how
    to point your terminal at it.
.DESCRIPTION
    pwsh-font           install it if missing, then print the terminal-config step
    pwsh-font -status   report whether it is installed; install nothing
.EXAMPLE
    pwsh-font
#>
function pwsh-font {
    param([switch]$status)

    $name = Get-NerdFontName

    if ($status) {
        Write-Host ""
        if (Test-NerdFont) {
            Write-Host "✅ $name is installed." -ForegroundColor Green
        } else {
            Write-Host "❌ $name is not installed.  Run:  pwsh-font" -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Host (Get-NerdFontInstructions) -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    if (Test-NerdFont) {
        Write-Host "✅ $name is already installed." -ForegroundColor Green
    }
    else {
        Write-Host "🎨 Installing $name ..." -ForegroundColor Cyan
        if (Install-NerdFont) {
            Write-Host "✅ Installed $name" -ForegroundColor Green
        }
        else {
            Write-Host "⚠️  Could not install the font automatically." -ForegroundColor Yellow
            Write-Host "   $(Get-NerdFontInstallHint)" -ForegroundColor DarkGray
            Write-Host ""
            return
        }
    }

    Write-Host ""
    Write-Host (Get-NerdFontInstructions) -ForegroundColor DarkGray
    Write-Host ""
}

# ── pwsh-h registration ───────────────────────────────────────────────────────
Register-PFCommand -Name 'pwsh-font' -Section '⚙️ CONFIGURATION & SETTINGS' -Synopsis 'install the Nerd Font for the prompt and ls icons, and show the terminal step' -Example 'pwsh-font · pwsh-font -status'
