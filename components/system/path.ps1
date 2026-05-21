# ==============================================================================
# PowerFlow — PATH Management
# ==============================================================================
# Domain   : System
# File     : components/system/path.ps1
# Purpose  : Add directories to User or System PATH without quoting
# Functions: set-path
# Depends  : none
# ==============================================================================

function set-path {
    param(
        [switch]$System,
        [Parameter(Mandatory, ValueFromRemainingArguments)]
        [string[]]$PathParts
    )

    $newPath = ($PathParts -join ' ').Trim()
    $scope   = if ($System) { 'Machine' } else { 'User' }
    $label   = if ($System) { 'System'  } else { 'User' }

    if ($System) {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            Write-Host "❌ System PATH requires an elevated (Administrator) session." -ForegroundColor Red
            return
        }
    }

    if (-not (Test-Path $newPath)) {
        Write-Host "⚠️  Directory does not exist on disk (path added anyway)" -ForegroundColor Yellow
    }

    $current    = [System.Environment]::GetEnvironmentVariable('Path', $scope)
    $entries    = $current -split ';' | Where-Object { $_ -ne '' }
    $normalized = $newPath.TrimEnd('\')

    if (($entries | ForEach-Object { $_.TrimEnd('\') }) -contains $normalized) {
        Write-Host "ℹ️  Already in $label PATH — nothing to do." -ForegroundColor Cyan
        return
    }

    $updated = $current.TrimEnd(';') + ";$newPath"
    [System.Environment]::SetEnvironmentVariable('Path', $updated, $scope)

    $verified = ([System.Environment]::GetEnvironmentVariable('Path', $scope) -split ';' |
                 ForEach-Object { $_.TrimEnd('\') }) -contains $normalized

    if ($verified) {
        Write-Host "✅ Added to $label PATH: $newPath" -ForegroundColor Green
        $env:Path += ";$newPath"
        Write-Host "💡 Active in this session immediately" -ForegroundColor Cyan
    } else {
        Write-Host "❌ Failed to add to $label PATH — please try again." -ForegroundColor Red
    }
}
