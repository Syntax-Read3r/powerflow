#Requires -Version 5.1

<#
.SYNOPSIS
    PowerFlow Installation Script
.DESCRIPTION
    Installs PowerFlow PowerShell profile with all dependencies
.PARAMETER Force
    Overwrite existing profile without confirmation
.EXAMPLE
    .\install.ps1
    .\install.ps1 -Force
#>

param([switch]$Force)

$ErrorActionPreference = "Stop"

Write-Host "🚀 PowerFlow Installation Script" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan

# Check PowerShell version
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "❌ PowerShell 5.1 or higher required" -ForegroundColor Red
    exit 1
}

# Get profile path
$profilePath = $PROFILE
$profileDir = Split-Path $profilePath -Parent

Write-Host "📁 Profile location: $profilePath" -ForegroundColor White

# Check if profile exists
if ((Test-Path $profilePath) -and -not $Force) {
    Write-Host "⚠️  PowerShell profile already exists!" -ForegroundColor Yellow
    $choice = Read-Host "Overwrite existing profile? (y/n)"
    if ($choice -ne 'y') {
        Write-Host "❌ Installation cancelled" -ForegroundColor Red
        exit 1
    }
}

# Create profile directory if needed
if (-not (Test-Path $profileDir)) {
    Write-Host "📂 Creating profile directory..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}

# Download latest profile
try {
    Write-Host "⬇️  Downloading PowerFlow profile..." -ForegroundColor Yellow
    $downloadUrl = "https://raw.githubusercontent.com/Syntax-Read3r/powerflow/main/Microsoft.PowerShell_profile.ps1"
    Invoke-RestMethod -Uri $downloadUrl -OutFile $profilePath
    Write-Host "✅ Profile downloaded successfully" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to download profile: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "`n🎉 PowerFlow installed successfully!" -ForegroundColor Green
Write-Host "🔄 Restart PowerShell or run: . `$PROFILE" -ForegroundColor Cyan
Write-Host "💡 Type 'pwsh-h' for help after restart" -ForegroundColor Yellow