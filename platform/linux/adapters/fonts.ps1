# ==============================================================================
# PowerFlow — Fonts Adapter (Linux)
# ==============================================================================
# Domain   : Platform / Linux
# File     : platform/linux/adapters/fonts.ps1
# Purpose  : Install and detect the Nerd Font that Starship and lsd draw with
# Contract : Get-NerdFontName, Test-NerdFont, Install-NerdFont,
#            Uninstall-NerdFont, Get-NerdFontInstructions
# Depends  : fontconfig (fc-list / fc-cache) — degrades gracefully without it
# ==============================================================================
#
# WHY A FONT IS ITS OWN ADAPTER, NOT JUST ANOTHER DEPENDENCY
#
# Starship and lsd emit glyphs from Unicode's Private Use Area. With no Nerd Font
# installed, Linux font fallback picks whatever DOES have those codepoints — almost
# always Noto CJK — so you get Chinese characters where icons should be, and because
# CJK glyphs are double-width they overlap filenames in `ls`. Installing the font is
# the fix; the tool dependencies (starship/lsd) do not carry it.
#
# A font also does not fit Test-Dependency's `Get-Command` model — there is no
# command to run — so it needs its own detection (fc-list) and its own install
# (download + fc-cache), which is exactly what an adapter is for.
#
# THE HALF WE CANNOT AUTOMATE: setting the terminal emulator's font. There are a
# dozen Linux terminals and no common config API, so the install puts the glyphs on
# the system and Get-NerdFontInstructions tells the user the one manual step.
# ==============================================================================

# The Mono variant, deliberately: it forces every glyph — icons included — into a
# single cell, which is what stops lsd's icons from encroaching on filenames.
function Get-NerdFontName { return 'FiraCode Nerd Font Mono' }

# PowerFlow's own copy lives in its own directory, so uninstall removes exactly what
# it placed and never a Nerd Font the user installed themselves.
$script:PF_FontDir = Join-Path $HOME '.local/share/fonts/PowerFlow-NerdFont'

function Test-NerdFont {
    # No fontconfig (a bare server with no desktop) → nothing renders a terminal font
    # anyway. Report "not present" rather than erroring.
    if (-not (Get-Command fc-list -ErrorAction SilentlyContinue)) { return $false }
    # Match the MONO family specifically. A user with plain 'FiraCode Nerd Font' or
    # '…Propo' has the wrong (double-width) variant — the one that overlaps filenames —
    # so a loose 'FiraCode Nerd' match would report success and never install the Mono
    # that actually fixes the problem.
    $hit = fc-list 2>/dev/null | Select-String -Pattern 'FiraCode Nerd Font Mono' -SimpleMatch
    return [bool]$hit
}

function Install-NerdFont {
    if (Test-NerdFont) { return $true }

    if (-not (Get-Command fc-cache -ErrorAction SilentlyContinue)) {
        # No fontconfig: installing font files would be pointless — nothing indexes
        # them. Headless servers land here, and that is fine.
        return $false
    }

    try {
        $zip = Join-Path ([IO.Path]::GetTempPath()) "FiraCode-NF-$(Get-Random).zip"
        # -OutFile with a redirect-following release URL. Invoke-WebRequest, not curl:
        # a slim box may have neither curl nor wget, but pwsh is guaranteed present.
        Invoke-WebRequest -Uri 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip' `
            -OutFile $zip -TimeoutSec 180 -ErrorAction Stop

        $extract = Join-Path ([IO.Path]::GetTempPath()) "FiraCode-NF-$(Get-Random)"
        # Expand-Archive is built into pwsh — no `unzip` dependency, which a minimal
        # container often lacks.
        Expand-Archive -Path $zip -DestinationPath $extract -Force

        New-Item -ItemType Directory -Path $script:PF_FontDir -Force | Out-Null

        # Prefer the Mono TTFs (what we recommend); fall back to all TTFs if the
        # upstream naming ever changes, so an install never ends up empty.
        $ttf = @(Get-ChildItem $extract -Recurse -Filter '*Mono*.ttf')
        if ($ttf.Count -eq 0) { $ttf = @(Get-ChildItem $extract -Recurse -Filter '*.ttf') }
        foreach ($f in $ttf) { Copy-Item $f.FullName $script:PF_FontDir -Force }

        Remove-Item $zip, $extract -Recurse -Force -ErrorAction SilentlyContinue

        fc-cache -f $script:PF_FontDir 2>&1 | Out-Null
        return (Test-NerdFont)
    }
    catch {
        return $false
    }
}

function Uninstall-NerdFont {
    # Only ever removes PowerFlow's own directory — a Nerd Font the user installed
    # elsewhere is untouched.
    if (Test-Path $script:PF_FontDir) {
        Remove-Item $script:PF_FontDir -Recurse -Force -ErrorAction SilentlyContinue
        if (Get-Command fc-cache -ErrorAction SilentlyContinue) { fc-cache -f 2>&1 | Out-Null }
    }
    return $true
}

# Shown when the automatic install fails — platform-specific recovery, kept in the
# adapter so the component never has to name fontconfig or a package manager.
function Get-NerdFontInstallHint {
    return "Install fontconfig (provides fc-cache), or download the font manually from`n   https://github.com/ryanoasis/nerd-fonts/releases/latest"
}

function Get-NerdFontInstructions {
    $lines = @(
        "One manual step PowerFlow cannot do for you — point your terminal at the font:"
        ""
        "  Set your terminal's font to:  $(Get-NerdFontName)"
        ""
        "  GNOME Terminal / Console : Preferences → your profile → Text → Custom font"
        "  Ptyxis (Fedora 40+)      : ☰ → Preferences → Fonts"
        "  Konsole                  : Settings → Edit Profile → Appearance → Font"
        "  Kitty / Alacritty        : set 'font_family' / 'font.normal' in the config"
        ""
        "  Open a NEW terminal window afterwards. The 'Mono' variant is deliberate — it"
        "  keeps lsd's icons from overlapping filenames."
    )
    return ($lines -join "`n")
}
