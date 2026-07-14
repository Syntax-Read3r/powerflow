# ==============================================================================
# PowerFlow — Locations Adapter (Windows)
# ==============================================================================
# Domain   : Platform / Windows
# File     : platform/windows/adapters/locations.ps1
# Purpose  : Well-known config/data paths that differ per platform
# Contract : Get-StarshipConfigPath, Get-TerminalSettingsPath,
#            Get-PowerFlowDataPath, Get-PowerFlowConfigPath
# Depends  : none
# ==============================================================================

function Get-StarshipConfigPath {
    return (Join-Path $HOME '.config\starship.toml')
}

# Windows Terminal settings.json. $null on platforms without Windows Terminal.
function Get-TerminalSettingsPath {
    return (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json')
}

# Where PowerFlow stores its own data (bookmarks, manifest, state markers)
function Get-PowerFlowDataPath {
    return (Join-Path $env:LOCALAPPDATA 'PowerFlow')
}

function Get-PowerFlowConfigPath {
    return (Join-Path $env:APPDATA 'PowerFlow')
}

# Temp directory for state markers. $env:TEMP does not exist on Linux, so every
# component must go through this adapter rather than reading $env:TEMP directly.
function Get-TempPath {
    return $env:TEMP
}

# Home directory. $env:USERPROFILE does not exist on Linux; $HOME works on both,
# and on Windows it resolves to the same place.
function Get-HomePath {
    return $HOME
}
