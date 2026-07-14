# ==============================================================================
# PowerFlow — Locations Adapter (Linux)
# ==============================================================================
# Domain   : Platform / Linux
# File     : platform/linux/adapters/locations.ps1
# Purpose  : Well-known config/data paths, following the XDG base-directory spec
# Contract : Get-StarshipConfigPath, Get-TerminalSettingsPath,
#            Get-PowerFlowDataPath, Get-PowerFlowConfigPath
# Depends  : none
# ==============================================================================

function Get-XdgConfigHome {
    if ($env:XDG_CONFIG_HOME) { return $env:XDG_CONFIG_HOME }
    return (Join-Path $HOME '.config')
}

function Get-XdgDataHome {
    if ($env:XDG_DATA_HOME) { return $env:XDG_DATA_HOME }
    return (Join-Path $HOME '.local/share')
}

function Get-StarshipConfigPath {
    return (Join-Path (Get-XdgConfigHome) 'starship.toml')
}

# There is no Windows Terminal on Linux. Callers must handle $null.
function Get-TerminalSettingsPath {
    return $null
}

function Get-PowerFlowDataPath {
    return (Join-Path (Get-XdgDataHome) 'powerflow')
}

function Get-PowerFlowConfigPath {
    return (Join-Path (Get-XdgConfigHome) 'powerflow')
}

# $env:TEMP is a Windows-ism and is unset on Linux — honour TMPDIR, else /tmp.
function Get-TempPath {
    if ($env:TMPDIR) { return $env:TMPDIR }
    return '/tmp'
}

function Get-HomePath {
    return $HOME
}
