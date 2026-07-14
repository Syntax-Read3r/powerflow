# ==============================================================================
# PowerFlow — Openers Adapter (Windows)
# ==============================================================================
# Domain   : Platform / Windows
# File     : platform/windows/adapters/openers.ps1
# Purpose  : Open paths in the file manager, files in the editor, URLs in the browser
# Contract : Open-Path, Open-Editor, Open-Url, Get-FileManagerName
# Depends  : none
# ==============================================================================

function Get-FileManagerName { return 'File Explorer' }

# Open a directory in the system file manager
function Open-Path {
    param([Parameter(Mandatory)][string]$Path)
    explorer.exe $Path
}

# Open a file in the configured editor (VS Code)
function Open-Editor {
    param([Parameter(Mandatory)][string]$Path)
    code $Path
}

# Open a URL in the default browser
function Open-Url {
    param([Parameter(Mandatory)][string]$Url)
    Start-Process $Url
}
