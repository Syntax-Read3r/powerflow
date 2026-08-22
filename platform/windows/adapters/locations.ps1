# ==============================================================================
# PowerFlow — Locations Adapter (Windows)
# ==============================================================================
# Domain   : Platform / Windows
# File     : platform/windows/adapters/locations.ps1
# Purpose  : Well-known config/data paths that differ per platform
# Contract : Get-StarshipConfigPath, Get-TerminalSettingsPath,
#            Get-PowerFlowDataPath, Get-PowerFlowConfigPath,
#            Get-PowerFlowNavigationDataPath
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

# Bookmarks and search roots historically lived directly beneath $HOME. Honour an
# explicit data home without moving existing users who have not configured one.
function Get-PowerFlowNavigationDataPath {
    if (-not [string]::IsNullOrWhiteSpace($env:POWERFLOW_DATA_HOME)) {
        return $env:POWERFLOW_DATA_HOME
    }
    return (Get-HomePath)
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

<#
.SYNOPSIS
    The REAL path of a standard user folder (Documents, Downloads, Pictures, …).
.DESCRIPTION
    Join-Path $HOME 'Documents' is WRONG on a modern Windows install. With OneDrive
    Known Folder Move — the default on many setups — Documents/Pictures/Desktop are
    redirected to %USERPROFILE%\OneDrive\..., and the local ~\Documents is either an
    empty stub or absent entirely. Measured on a real machine:

        ~\Pictures                 does not exist
        MyPictures  (real)         C:\Users\<you>\OneDrive\Pictures
        ~\Documents                exists, but is NOT the live one
        MyDocuments (real)         C:\Users\<you>\OneDrive\Documents

    So `nav -pics` was unavailable and `nav -docs` would have landed in the empty stub.
    GetFolderPath consults the Known Folder registry and follows the redirect.

    Downloads has no Environment.SpecialFolder member, so it falls back to ~\Downloads
    (which Known Folder Move does not redirect by default).
#>
function Get-UserFolderPath {
    param(
        [Parameter(Mandatory)][ValidateSet('Documents','Downloads','Pictures','Videos','Music','Desktop')][string]$Name,
        # auto  — whatever Windows says, following the OneDrive redirect. Correct for most people.
        # local — insist on %USERPROFILE%\<Name>, for people who deliberately keep files OFF
        #         OneDrive. Returns '' when it does not exist so the CALLER can offer to create
        #         it; silently falling back to the redirect would defeat the whole preference.
        # known — the redirect target explicitly, even when a local folder also exists.
        [ValidateSet('auto', 'local', 'known')][string]$Prefer = 'auto'
    )

    if ($Prefer -eq 'local') {
        $localPath = Join-Path (Get-HomePath) $Name
        if (Test-Path -LiteralPath $localPath) { return $localPath }
        return ''
    }

    $special = @{
        Documents = 'MyDocuments'; Pictures = 'MyPictures'
        Videos    = 'MyVideos';    Music    = 'MyMusic'
        Desktop   = 'Desktop'
    }
    if ($special.ContainsKey($Name)) {
        try {
            $p = [Environment]::GetFolderPath($special[$Name])
            if ($p -and (Test-Path -LiteralPath $p)) { return $p }
        } catch { }
    }
    $fallback = Join-Path (Get-HomePath) $Name
    if (Test-Path -LiteralPath $fallback) { return $fallback }
    return ''
}
