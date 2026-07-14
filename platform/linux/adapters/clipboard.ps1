# ==============================================================================
# PowerFlow — Clipboard Adapter (Linux)
# ==============================================================================
# Domain   : Platform / Linux
# File     : platform/linux/adapters/clipboard.ps1
# Purpose  : Read and write the system clipboard via wl-clipboard / xclip / xsel
# Contract : Copy-ToClipboard, Get-FromClipboard, Test-ClipboardSupport
# Depends  : none
# ==============================================================================
#
# Linux has no built-in clipboard API — it belongs to the display server.
# Wayland and X11 use different tools, so detect once at load and cache it.
# ==============================================================================

function Get-ClipboardBackend {
    if ($script:PF_ClipboardBackend) { return $script:PF_ClipboardBackend }

    $isWayland = [bool]$env:WAYLAND_DISPLAY

    $script:PF_ClipboardBackend =
        if     ($isWayland -and (Get-Command wl-copy -ErrorAction SilentlyContinue)) { 'wl-clipboard' }
        elseif (Get-Command xclip -ErrorAction SilentlyContinue)                     { 'xclip' }
        elseif (Get-Command xsel  -ErrorAction SilentlyContinue)                     { 'xsel' }
        elseif (Get-Command wl-copy -ErrorAction SilentlyContinue)                   { 'wl-clipboard' }
        else                                                                          { 'none' }

    return $script:PF_ClipboardBackend
}

function Test-ClipboardSupport {
    return ((Get-ClipboardBackend) -ne 'none')
}

function Copy-ToClipboard {
    param([Parameter(Mandatory, ValueFromPipeline)][AllowEmptyString()][string]$Value)

    process {
        switch (Get-ClipboardBackend) {
            'wl-clipboard' { $Value | wl-copy }
            'xclip'        { $Value | xclip -selection clipboard }
            'xsel'         { $Value | xsel --clipboard --input }
            default {
                Write-Host "⚠️  No clipboard tool found. Install one:" -ForegroundColor Yellow
                Write-Host "   Wayland: wl-clipboard   |   X11: xclip" -ForegroundColor DarkGray
            }
        }
    }
}

function Get-FromClipboard {
    switch (Get-ClipboardBackend) {
        'wl-clipboard' { return (wl-paste 2>$null) }
        'xclip'        { return (xclip -selection clipboard -o 2>$null) }
        'xsel'         { return (xsel --clipboard --output 2>$null) }
        default        { return $null }
    }
}
