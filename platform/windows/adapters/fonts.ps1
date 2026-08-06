# ==============================================================================
# PowerFlow — Fonts Adapter (Windows)
# ==============================================================================
# Domain   : Platform / Windows
# File     : platform/windows/adapters/fonts.ps1
# Purpose  : Install and detect the Nerd Font that Starship and lsd draw with
# Contract : Get-NerdFontName, Test-NerdFont, Install-NerdFont,
#            Uninstall-NerdFont, Get-NerdFontInstructions
# Depends  : Scoop prerequisite via packages adapter (the nerd-fonts bucket)
# ==============================================================================
#
# Same story as Linux: Starship and lsd draw with Nerd Font glyphs, and without the
# font the terminal shows tofu boxes or CJK fallback where icons should be. Scoop's
# nerd-fonts bucket installs the font PER-USER and registers it in HKCU — no admin —
# so it fits PowerFlow's existing Scoop-based dependency flow cleanly.
#
# Registry reads live HERE, in an adapter, not in components/ — which is precisely
# the boundary the architecture rule draws.
# ==============================================================================

# The Mono variant: single-cell glyphs, so lsd's icons never overlap filenames.
# Scoop package 'FiraCode-NF-Mono' registers it as 'FiraCode Nerd Font Mono'.
function Get-NerdFontName    { return 'FiraCode Nerd Font Mono' }
function Get-NerdFontPackage { return 'FiraCode-NF-Mono' }

$script:PF_NerdFontInstallError = $null

function Test-NerdFontRegistryName {
    param([AllowEmptyString()][string]$Name)
    # Scoop registers filename-derived properties such as
    # `FiraCodeNerdFontMono-Regular (TrueType)`, while other installers may use
    # the human family label `FiraCode Nerd Font Mono`. Normalize both forms.
    $normalized = $Name -replace '[^A-Za-z0-9]', ''
    return ($normalized -like '*FiraCodeNerdFontMono*')
}

function Test-NerdFont {
    # A registered font appears as a value under the Fonts key — per-user (HKCU,
    # where Scoop puts it) or machine-wide (HKLM). Checking the registry detects the
    # font however it was installed, not just Scoop's copy.
    foreach ($key in @(
        'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts',
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts')) {
        if (Test-Path $key) {
            $names = (Get-Item $key).Property
            # The MONO family specifically — a plain 'FiraCode Nerd Font' or '…Propo' is
            # the double-width variant that overlaps filenames, so matching it loosely
            # would report success and skip installing the Mono that fixes the problem.
            if ($names | Where-Object { Test-NerdFontRegistryName "$_" }) { return $true }
        }
    }
    return $false
}

function Install-NerdFont {
    $script:PF_NerdFontInstallError = $null
    if (Test-NerdFont) { return $true }

    # `pwsh-font` can be invoked outside the main installer. Scoop is an explicit
    # Windows prerequisite, so reuse the packages adapter's bootstrap instead of
    # telling the user to install it manually.
    if (-not (Get-Command Test-PackageManager -ErrorAction SilentlyContinue) -or
        -not (Get-Command Install-PackageManager -ErrorAction SilentlyContinue)) {
        $script:PF_NerdFontInstallError = 'The Windows packages adapter is not loaded.'
        return $false
    }
    if (-not (Test-PackageManager) -and -not (Install-PackageManager)) {
        $script:PF_NerdFontInstallError = 'PowerFlow could not install its Scoop prerequisite.'
        return $false
    }
    if (-not (Test-PackageManager)) {
        $script:PF_NerdFontInstallError = 'Scoop is installed but is not callable in this PowerShell process.'
        return $false
    }

    # The nerd-fonts bucket is a git repo; adding it twice is harmless (Scoop just
    # says it already exists). Capture failures so the hint reports the real cause.
    $bucketOutput = @(& scoop bucket add nerd-fonts 2>&1)
    if (-not $?) {
        $script:PF_NerdFontInstallError = "Could not add Scoop's nerd-fonts bucket: $($bucketOutput -join ' ')"
        return $false
    }

    $installOutput = @(& scoop install (Get-NerdFontPackage) 2>&1)
    if (-not $?) {
        $script:PF_NerdFontInstallError = "Scoop could not install $(Get-NerdFontPackage): $($installOutput -join ' ')"
        return $false
    }

    if (-not (Test-NerdFont)) {
        $script:PF_NerdFontInstallError = 'Scoop completed, but Windows did not expose the expected Mono font registration.'
        return $false
    }
    return $true
}

function Uninstall-NerdFont {
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) { return $true }
    scoop uninstall (Get-NerdFontPackage) *>$null
    return $true
}

# Recovery hint on install failure — the Scoop specifics live here, not in the
# platform-agnostic component (which the architecture gate forbids from naming Scoop).
function Get-NerdFontInstallHint {
    if ($script:PF_NerdFontInstallError) {
        return "$script:PF_NerdFontInstallError Run 'pwsh-font' again after correcting that error."
    }
    return "PowerFlow installs Scoop automatically. Manual recovery: scoop bucket add nerd-fonts; scoop install $(Get-NerdFontPackage)"
}

function Get-NerdFontInstructions {
    $lines = @(
        "One manual step — point Windows Terminal at the font:"
        ""
        "  Set the terminal font to:  $(Get-NerdFontName)"
        ""
        "  Windows Terminal : Settings (Ctrl+,) → Profiles → Defaults → Appearance"
        "                     → Font face → $(Get-NerdFontName)"
        "                     (or run 'pwsh-settings' to open settings.json)"
        ""
        "  Open a NEW tab afterwards. The 'Mono' variant is deliberate — it keeps"
        "  lsd's icons from overlapping filenames."
    )
    return ($lines -join "`n")
}
