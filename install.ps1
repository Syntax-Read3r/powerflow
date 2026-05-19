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

# Install Scoop if missing
if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-Host "`n📦 Installing Scoop package manager..." -ForegroundColor Yellow
    try {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
        Write-Host "✅ Scoop installed" -ForegroundColor Green
    } catch {
        Write-Host "❌ Failed to install Scoop: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "💡 Install Scoop manually then re-run this script" -ForegroundColor DarkGray
        exit 1
    }
} else {
    Write-Host "`n✅ Scoop already installed" -ForegroundColor Green
}

# Install required tools
Write-Host "`n📦 Installing required tools..." -ForegroundColor Yellow
$tools = @(
    @{ Name = "starship"; Description = "Cross-shell prompt" },
    @{ Name = "fzf";      Description = "Fuzzy finder (used by nav)" },
    @{ Name = "zoxide";   Description = "Smart directory navigation" },
    @{ Name = "lsd";      Description = "Modern ls replacement" },
    @{ Name = "git";      Description = "Version control" }
)

foreach ($tool in $tools) {
    if (Get-Command $tool.Name -ErrorAction SilentlyContinue) {
        Write-Host "   ✅ $($tool.Name) already installed" -ForegroundColor DarkGray
    } else {
        try {
            Write-Host "   Installing $($tool.Name) ($($tool.Description))..." -ForegroundColor DarkGray
            scoop install $tool.Name *>$null
            Write-Host "   ✅ $($tool.Name) installed" -ForegroundColor Green
        } catch {
            Write-Host "   ❌ Failed to install $($tool.Name): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# Refresh PATH so newly installed tools are immediately available in this session
$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("PATH", "User")

Write-Host "`n🎉 PowerFlow installed successfully!" -ForegroundColor Green
Write-Host "   Profile : $profilePath" -ForegroundColor DarkGray
Write-Host "   Tools   : starship, fzf, zoxide, lsd, git" -ForegroundColor DarkGray
Write-Host "`n🔄 Restart PowerShell to activate your profile" -ForegroundColor Cyan
Write-Host "💡 Type 'pwsh-h' for the full command reference" -ForegroundColor Yellow