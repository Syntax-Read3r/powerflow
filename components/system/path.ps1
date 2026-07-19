# ==============================================================================
# PowerFlow — PATH Management
# ==============================================================================
# Domain   : System
# File     : components/system/path.ps1
# Purpose  : Add directories to the User or System PATH without quoting
# Functions: set-path
# Depends  : Add-PersistentPathEntry, Test-PersistentPathEntry, Get-PathScopeLabel
#            (platform/<os>/adapters/env.ps1)
# ==============================================================================

function set-path {
    param(
        [switch]$System,
        [Parameter(Mandatory, ValueFromRemainingArguments)]
        [string[]]$PathParts
    )

    $newPath = ($PathParts -join ' ').Trim()
    $scope   = if ($System) { 'System' } else { 'User' }
    $label   = Get-PathScopeLabel -Scope $scope

    if (-not (Test-Path $newPath)) {
        Write-Host "⚠️  Directory does not exist on disk (path added anyway)" -ForegroundColor Yellow
    }

    if (Test-PersistentPathEntry -Directory $newPath -Scope $scope) {
        Write-Host "ℹ️  Already in $label PATH — nothing to do." -ForegroundColor Cyan
        return
    }

    # The adapter owns the elevation check for System scope and returns $false if denied.
    if (Add-PersistentPathEntry -Directory $newPath -Scope $scope) {
        Write-Host "✅ Added to $label PATH: $newPath" -ForegroundColor Green
        Write-Host "💡 Active in this session immediately" -ForegroundColor Cyan
    } else {
        Write-Host "❌ Failed to add to $label PATH — please try again." -ForegroundColor Red
    }
}

# ── pwsh-h registration ───────────────────────────────────────────────────────
Register-PFCommand -Name 'set-path' -Section '⚙️ CONFIGURATION & SETTINGS' -Synopsis 'add a directory to PATH (-system needs admin)' -Example 'set-path C:\tools'
