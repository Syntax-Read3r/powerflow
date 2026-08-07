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

<#
.SYNOPSIS
    The REAL path of a standard user folder (Documents, Downloads, Pictures, …).
.DESCRIPTION
    Linux has the same trap as Windows in a different shape: XDG user directories can be
    RELOCATED or LOCALISED. On a French desktop Documents is ~/Documents, but on a Spanish
    one it is ~/Documentos — and any of them can be pointed elsewhere entirely. The mapping
    lives in ~/.config/user-dirs.dirs as XDG_DOCUMENTS_DIR="$HOME/...".

    xdg-user-dir(1) is the sanctioned lookup but is not installed everywhere, so the file is
    parsed directly when the binary is missing, and ~/<Name> is the last resort.
#>
function Get-UserFolderPath {
    param(
        [Parameter(Mandatory)][ValidateSet('Documents','Downloads','Pictures','Videos','Music','Desktop')][string]$Name,
        # Same contract as Windows so the two signatures match (CI parity checks this).
        # 'local' means ~/<Name> literally, ignoring an XDG redirect — the Linux equivalent of
        # "keep my files out of OneDrive". Returns '' when absent so the caller can offer mkdir.
        [ValidateSet('auto', 'local', 'known')][string]$Prefer = 'auto'
    )

    if ($Prefer -eq 'local') {
        $localPath = Join-Path (Get-HomePath) $Name
        if (Test-Path -LiteralPath $localPath) { return $localPath }
        return ''
    }

    $key = $Name.ToUpperInvariant()

    if (Get-Command xdg-user-dir -CommandType Application -ErrorAction SilentlyContinue) {
        try {
            $p = (& xdg-user-dir $key 2>$null | Select-Object -First 1)
            if ($p -and (Test-Path -LiteralPath "$p")) { return "$p".Trim() }
        } catch { }
    }

    $dirsFile = Join-Path (Get-XdgConfigHome) 'user-dirs.dirs'
    if (Test-Path -LiteralPath $dirsFile) {
        try {
            foreach ($line in (Get-Content -LiteralPath $dirsFile -ErrorAction Stop)) {
                if ($line -match "^\s*XDG_${key}_DIR\s*=\s*`"?([^`"]+)`"?") {
                    $raw = $Matches[1].Replace('$HOME', (Get-HomePath))
                    if (Test-Path -LiteralPath $raw) { return $raw }
                }
            }
        } catch { }
    }

    $fallback = Join-Path (Get-HomePath) $Name
    if (Test-Path -LiteralPath $fallback) { return $fallback }
    return ''
}
