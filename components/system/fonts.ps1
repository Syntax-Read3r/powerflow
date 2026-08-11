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
    pwsh-font --status   report whether it is installed; install nothing
.EXAMPLE
    pwsh-font
#>
function Install-PFNerdFontCommand {
    # UNRECOGNISED ARGUMENTS ARE REFUSED, not ignored. PowerShell cannot bind `--status` to a
    # param() switch — it parses as a positional VALUE — and because this is a simple function
    # with no [CmdletBinding()], the token is silently collected into $args instead of erroring.
    # $status therefore stayed false and execution fell past the reporting branch and INSTALLED
    # a font. A GNU habit turned a read-only query into a write.
    #
    # Refusing unknown tokens is the general fix: it turns every unbindable `--long` on this
    # command from a silent wrong action into an error that names the spelling that works.
    param([switch]$status)

    $unknown = @($args | ForEach-Object { "$_" } | Where-Object { $_ })
    if ($unknown.Count) {
        $plural = if ($unknown.Count -ne 1) { 's' } else { '' }
        Write-Host "❌ pwsh-font: unknown argument$plural`: $($unknown -join ', ')" -ForegroundColor Red
        foreach ($token in $unknown) {
            if ($token -match '^--(.+)$') {
                Write-Host "   A double-dash flag cannot bind here. Try:  pwsh-font -$($Matches[1])" -ForegroundColor DarkGray
            }
        }
        Write-Host '   pwsh-font          install the Nerd Font' -ForegroundColor DarkGray
        Write-Host '   pwsh-font --status  report whether it is installed, and install nothing' -ForegroundColor DarkGray
        return
    }

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

# ── pwsh-font ──────────────────────────────────────────────────────────
# The user-facing name is a shim so that --long flags bind at all: a param() block
# cannot bind them, and worse, misbinds them into the next value parameter. The shim
# must not declare param() of its own, or $args would not hold the whole line.
# See docs/plan/ethos/ETHOS.md.
function pwsh-font { Invoke-PFParamCommand -Target 'Install-PFNerdFontCommand' -Command 'pwsh-font' -Argv $args }

# ── pwsh-h registration ───────────────────────────────────────────────────────
Register-PFCommand -Name 'pwsh-font' -Section '⚙️ CONFIGURATION & SETTINGS' -Synopsis 'install the Nerd Font for the prompt and ls icons, and show the terminal step' -Example 'pwsh-font · pwsh-font --status'
