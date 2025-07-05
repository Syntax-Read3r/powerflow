<#
.SYNOPSIS
    PowerFlow Uninstallation Script
.DESCRIPTION
    Removes PowerFlow profile and optionally cleans up dependencies
#>

Write-Host "🗑️  PowerFlow Uninstall Script" -ForegroundColor Yellow
Write-Host "==============================" -ForegroundColor Yellow

$profilePath = $PROFILE

if (-not (Test-Path $profilePath)) {
    Write-Host "ℹ️  No PowerShell profile found" -ForegroundColor Yellow
    exit 0
}

# Check if it's PowerFlow profile
$content = Get-Content $profilePath -Raw
if ($content -notmatch "PowerFlow") {
    Write-Host "ℹ️  Profile doesn't appear to be PowerFlow" -ForegroundColor Yellow
    $continue = Read-Host "Remove anyway? (y/n)"
    if ($continue -ne 'y') {
        exit 0
    }
}

# Backup before removal
$backupPath = "$profilePath.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Write-Host "💾 Creating backup: $backupPath" -ForegroundColor Cyan
Copy-Item $profilePath $backupPath

# Remove profile
Remove-Item $profilePath -Force
Write-Host "✅ PowerFlow profile removed" -ForegroundColor Green
Write-Host "💾 Backup saved to: $backupPath" -ForegroundColor Cyan

# Ask about dependencies
Write-Host "`n🔧 Remove installed dependencies?" -ForegroundColor Yellow
Write-Host "  • Starship prompt" -ForegroundColor DarkGray
Write-Host "  • fzf, zoxide, lsd" -ForegroundColor DarkGray
Write-Host "  • FiraCode Nerd Font" -ForegroundColor DarkGray

$removeDeps = Read-Host "Remove dependencies? (y/n)"
if ($removeDeps -eq 'y') {
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Write-Host "🧹 Removing Scoop packages..." -ForegroundColor Yellow
        scoop uninstall starship fzf zoxide lsd FiraCode-NF
    }
}

Write-Host "`n✅ Uninstall complete" -ForegroundColor Green