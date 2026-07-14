# ==============================================================================
# PowerFlow — Clipboard Adapter (Windows)
# ==============================================================================
# Domain   : Platform / Windows
# File     : platform/windows/adapters/clipboard.ps1
# Purpose  : Read and write the system clipboard
# Contract : Copy-ToClipboard, Get-FromClipboard, Test-ClipboardSupport
# Depends  : none
# ==============================================================================

function Test-ClipboardSupport { return $true }

function Copy-ToClipboard {
    param([Parameter(Mandatory, ValueFromPipeline)][AllowEmptyString()][string]$Value)
    process {
        Set-Clipboard -Value $Value
    }
}

function Get-FromClipboard {
    return (Get-Clipboard -ErrorAction SilentlyContinue)
}
