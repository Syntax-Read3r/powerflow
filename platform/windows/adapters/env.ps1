# ==============================================================================
# PowerFlow — Environment Adapter (Windows)
# ==============================================================================
# Domain   : Platform / Windows
# File     : platform/windows/adapters/env.ps1
# Purpose  : Read and write the persistent (registry-backed) PATH
# Contract : Get-PersistentPath, Add-PersistentPathEntry, Get-PathScopeLabel
# Depends  : Assert-Admin (platform/windows/adapters/elevation.ps1)
# ==============================================================================

# Human-readable label for a scope, used in messages.
function Get-PathScopeLabel {
    param([ValidateSet('User', 'System')][string]$Scope = 'User')
    return $Scope
}

# The persistent PATH for a scope, as a single delimited string.
function Get-PersistentPath {
    param([ValidateSet('User', 'System')][string]$Scope = 'User')

    $target = if ($Scope -eq 'System') { 'Machine' } else { 'User' }
    return [System.Environment]::GetEnvironmentVariable('Path', $target)
}

# Append a directory to the persistent PATH. Returns $true if it is present afterwards.
# Handles the elevation check for System scope.
function Add-PersistentPathEntry {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [ValidateSet('User', 'System')][string]$Scope = 'User'
    )

    if ($Scope -eq 'System' -and -not (Assert-Admin 'System PATH')) { return $false }

    $target     = if ($Scope -eq 'System') { 'Machine' } else { 'User' }
    $current    = [System.Environment]::GetEnvironmentVariable('Path', $target)
    $entries    = $current -split ';' | Where-Object { $_ -ne '' }
    $normalized = $Directory.TrimEnd('\')

    if (($entries | ForEach-Object { $_.TrimEnd('\') }) -contains $normalized) {
        return $true   # already present — caller reports "nothing to do"
    }

    $updated = $current.TrimEnd(';') + ";$Directory"
    [System.Environment]::SetEnvironmentVariable('Path', $updated, $target)

    $verified = ([System.Environment]::GetEnvironmentVariable('Path', $target) -split ';' |
                 ForEach-Object { $_.TrimEnd('\') }) -contains $normalized

    if ($verified) { $env:Path += ";$Directory" }

    return $verified
}

# Is the directory already on the persistent PATH for this scope?
function Test-PersistentPathEntry {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [ValidateSet('User', 'System')][string]$Scope = 'User'
    )

    $entries = (Get-PersistentPath -Scope $Scope) -split ';' | Where-Object { $_ -ne '' }
    return (($entries | ForEach-Object { $_.TrimEnd('\') }) -contains $Directory.TrimEnd('\'))
}
