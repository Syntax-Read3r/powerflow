#Requires -Version 5.1

<#
.SYNOPSIS
    PowerFlow installer — shared by Windows and Linux.
.DESCRIPTION
    THE installer. install.sh is only a bootstrap that installs pwsh and then calls
    this file, so there is exactly one installer codebase for both platforms.

    Installs the full component tree next to $PROFILE, installs dependencies via
    the platform's package manager, and writes a manifest recording precisely what
    was placed and which tools PowerFlow itself installed — so uninstall can undo
    exactly that and nothing more.
.PARAMETER Yes
    Assume yes; no prompts (CI-safe).
.PARAMETER NoDeps
    Install PowerFlow only; skip starship/fzf/zoxide/lsd.
.PARAMETER Prefix
    Directory holding the PowerFlow source to install from. When omitted, the
    source is downloaded from GitHub.
.PARAMETER Platform
    Override platform detection (windows|linux). Defaults to auto-detect.
.EXAMPLE
    irm https://github.com/Syntax-Read3r/powerflow/releases/latest/download/install.ps1 | iex
.EXAMPLE
    ./install.ps1 -Yes -NoDeps
#>

param(
    [switch]$Yes,
    [switch]$Force,
    [switch]$NoDeps,
    [string]$Prefix,
    [ValidateSet('windows', 'linux', 'auto')][string]$Platform = 'auto'
)

$ErrorActionPreference = "Stop"
$REPO = "Syntax-Read3r/powerflow"

if ($Force) { $Yes = $true }   # -Force kept for backward compatibility

Write-Host ""
Write-Host "🚀 PowerFlow Installation" -ForegroundColor Cyan
Write-Host "=========================" -ForegroundColor Cyan

# ── Platform detection ────────────────────────────────────────────────────────
# $IsWindows does not exist on PowerShell 5.1 (it is $null, which is falsy), so
# check the edition first — 5.1 is always Desktop and always Windows.
if ($Platform -eq 'auto') {
    $Platform =
        if     ($PSVersionTable.PSEdition -eq 'Desktop') { 'windows' }
        elseif ($IsWindows)                              { 'windows' }
        elseif ($IsLinux)                                { 'linux' }
        else                                             { 'unsupported' }
}
if ($Platform -eq 'unsupported') {
    Write-Host "❌ Unsupported platform. PowerFlow supports Windows and Linux." -ForegroundColor Red
    exit 1
}
Write-Host "🖥️  Platform: $Platform" -ForegroundColor White

# ── Destination: the component tree lives beside $PROFILE ─────────────────────
#   Windows : ~/Documents/PowerShell/
#   Linux   : ~/.config/powershell/
$profilePath = $PROFILE
$profileDir  = Split-Path $profilePath -Parent
Write-Host "📁 Install location: $profileDir" -ForegroundColor White

if ((Test-Path $profilePath) -and -not $Yes) {
    Write-Host "⚠️  A PowerShell profile already exists." -ForegroundColor Yellow
    if ((Read-Host "Overwrite it? (y/n)") -ne 'y') {
        Write-Host "❌ Installation cancelled" -ForegroundColor Red
        exit 1
    }
}

if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}

# ── Back up an existing profile so uninstall can restore it ───────────────────
#
# The subtlety: on a RE-install the profile sitting on disk is PowerFlow's own. Backing
# that up would make the backup a copy of PowerFlow — and uninstall, which restores the
# backup, would then put PowerFlow back after deleting components/ and platform/. The
# user would be left with a profile that errors on every shell start.
#
# So: back up only what we did not write. If PowerFlow is already installed, keep
# pointing at the ORIGINAL pre-PowerFlow backup recorded in the existing manifest —
# which may legitimately be $null, meaning the user had no profile to begin with.
$manifestPath = Join-Path $profileDir '.powerflow-manifest.json'
$alreadyInstalled = Test-Path $manifestPath

$backup = $null
if (Test-Path $profilePath) {
    if ($alreadyInstalled) {
        try {
            $backup = (Get-Content $manifestPath -Raw | ConvertFrom-Json).backup
        } catch {
            $backup = $null
        }
        if ($backup -and (Test-Path $backup)) {
            Write-Host "💾 Reinstall — keeping your original backup: $(Split-Path $backup -Leaf)" -ForegroundColor Yellow
        } else {
            $backup = $null
        }
    }
    else {
        $stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backup = "$profilePath.powerflow-backup.$stamp"
        Copy-Item $profilePath $backup -Force
        Write-Host "💾 Backed up existing profile -> $(Split-Path $backup -Leaf)" -ForegroundColor Yellow
    }
}

# ── Source: local tree if we have one, else download ──────────────────────────
$tempDir = $null
if ($Prefix -and (Test-Path (Join-Path $Prefix 'components'))) {
    $source = $Prefix
    Write-Host "📦 Installing from: $source" -ForegroundColor White
}
elseif (Test-Path (Join-Path $PSScriptRoot 'components')) {
    $source = $PSScriptRoot
    Write-Host "📦 Installing from: $source (local checkout)" -ForegroundColor White
}
else {
    Write-Host "⬇️  Downloading PowerFlow..." -ForegroundColor Yellow
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "powerflow-$(Get-Random)"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    $zip = Join-Path $tempDir 'powerflow.zip'

    Invoke-WebRequest -Uri "https://github.com/$REPO/archive/refs/heads/main.zip" -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $tempDir -Force
    $source = (Get-ChildItem -Path $tempDir -Directory -Filter 'powerflow-*' | Select-Object -First 1).FullName

    if (-not $source) {
        Write-Host "❌ Unexpected archive layout." -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ Downloaded" -ForegroundColor Green
}

# ── Copy the tree ─────────────────────────────────────────────────────────────
# platform/ and windows-only/ are REQUIRED — without them no adapters load and every
# component call fails.
Write-Host ""
Write-Host "📂 Installing components..." -ForegroundColor Yellow

$installedFiles = New-Object System.Collections.Generic.List[string]

Copy-Item (Join-Path $source 'Microsoft.PowerShell_profile.ps1') $profilePath -Force
$installedFiles.Add($profilePath)

foreach ($dir in @('config', 'components', 'platform', 'windows-only')) {
    $src = Join-Path $source $dir
    if (-not (Test-Path $src)) { continue }

    $dst = Join-Path $profileDir $dir
    if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
    Copy-Item $src $dst -Recurse -Force

    Get-ChildItem $dst -Recurse -File | ForEach-Object { $installedFiles.Add($_.FullName) }
    Write-Host "   ✅ $dir/" -ForegroundColor Green
}

# Runtime docs. `git-rl -h` READS docs/git-rl/ at runtime to print the setup prompt and
# write the guide into a user's project — so these are not documentation, they are a
# dependency. Without them, git-rl -h has to fall back to fetching from GitHub, which
# fails offline. The rest of docs/ (logs, plans) is deliberately NOT installed.
$docsSrc = Join-Path $source 'docs/git-rl'
if (Test-Path $docsSrc) {
    $docsDst = Join-Path $profileDir 'docs/git-rl'
    if (Test-Path $docsDst) { Remove-Item $docsDst -Recurse -Force }
    New-Item -ItemType Directory -Path $docsDst -Force | Out-Null
    Copy-Item "$docsSrc/*" $docsDst -Recurse -Force

    Get-ChildItem $docsDst -Recurse -File | ForEach-Object { $installedFiles.Add($_.FullName) }
    Write-Host "   ✅ docs/git-rl/  (git-rl -h reads these at runtime)" -ForegroundColor Green
}

# uninstall.ps1 ships alongside so the profile can remove itself later
$uninstallSrc = Join-Path $source 'uninstall.ps1'
if (Test-Path $uninstallSrc) {
    $uninstallDst = Join-Path $profileDir 'uninstall.ps1'
    Copy-Item $uninstallSrc $uninstallDst -Force
    $installedFiles.Add($uninstallDst)
}

# ── Dependencies ──────────────────────────────────────────────────────────────
# Load the platform's packages adapter and use it, rather than hardcoding Scoop
# here — this is why the adapter layer exists.
$dependencies = @()

if (-not $NoDeps) {
    Write-Host ""
    Write-Host "📦 Installing dependencies..." -ForegroundColor Yellow

    . (Join-Path $profileDir "platform/$Platform/adapters/packages.ps1")
    if ($Platform -eq 'linux') {
        . (Join-Path $profileDir "platform/$Platform/adapters/locations.ps1")
    }

    if (-not (Test-PackageManager)) {
        Write-Host "   Setting up package manager..." -ForegroundColor DarkGray
        Install-PackageManager | Out-Null
    }

    foreach ($tool in @('starship', 'fzf', 'zoxide', 'lsd', 'git')) {
        # Record whether PowerFlow installed it — uninstall must NEVER remove a
        # tool the user already had.
        $preExisting = Test-Dependency $tool

        if ($preExisting) {
            Write-Host "   ✅ $tool (already present)" -ForegroundColor DarkGray
        }
        else {
            Write-Host "   Installing $tool..." -ForegroundColor DarkGray
            if (Install-Dependency $tool) {
                Write-Host "   ✅ $tool installed" -ForegroundColor Green
            } else {
                Write-Host "   ⚠️  $tool failed — try: $(Get-DependencyInstallHint $tool)" -ForegroundColor Yellow
            }
        }

        $dependencies += @{
            name                 = $tool
            manager              = (Get-PackageManagerName)
            installedByPowerFlow = (-not $preExisting)
        }
    }
}

# ── Manifest ──────────────────────────────────────────────────────────────────
# The uninstaller reads this. Without it, uninstall is guesswork — which is how
# the old Ubuntu port ended up deleting people's ~/.bashrc outright.
$version = 'unknown'
$settings = Join-Path $profileDir 'config/PowerFlow.settings.ps1'
if (Test-Path $settings) {
    $m = Select-String -Path $settings -Pattern '\$script:POWERFLOW_VERSION\s*=\s*"([^"]+)"'
    if ($m) { $version = $m.Matches[0].Groups[1].Value }
}

$manifest = [ordered]@{
    version      = $version
    platform     = $Platform
    installedAt  = (Get-Date).ToUniversalTime().ToString('o')
    profilePath  = $profilePath
    installRoot  = $profileDir
    backup       = $backup
    files        = @($installedFiles)
    dependencies = @($dependencies)
}

$manifestPath = Join-Path $profileDir '.powerflow-manifest.json'
$manifest | ConvertTo-Json -Depth 5 | Set-Content $manifestPath -Encoding UTF8
Write-Host ""
Write-Host "📝 Manifest written ($($installedFiles.Count) files tracked)" -ForegroundColor DarkGray

if ($tempDir -and (Test-Path $tempDir)) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }

# ── Done ──────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "🎉 PowerFlow v$version installed!" -ForegroundColor Green
Write-Host "   Platform : $Platform" -ForegroundColor DarkGray
Write-Host "   Profile  : $profilePath" -ForegroundColor DarkGray
if ($backup) { Write-Host "   Backup   : $backup" -ForegroundColor DarkGray }
Write-Host ""
if ($Platform -eq 'linux') {
    # "Restart your shell" is WRONG on Linux and used to send people in circles:
    # PowerFlow is a PowerShell profile, so restarting bash does nothing at all. The
    # caller (install.sh) then offers to wire pwsh into login.
    Write-Host "🐚 PowerFlow is a PowerShell profile — start it with:  pwsh" -ForegroundColor Cyan
    Write-Host "💡 Then type 'pwsh-h' for the full command reference" -ForegroundColor Yellow
    Write-Host "🐧 Note: rm/mv/cp/cat stay as the GNU tools. PowerFlow's versions are 'del' and 'mvf'." -ForegroundColor DarkGray
}
else {
    Write-Host "🔄 Restart your shell to activate PowerFlow" -ForegroundColor Cyan
    Write-Host "💡 Then type 'pwsh-h' for the full command reference" -ForegroundColor Yellow
}
Write-Host ""
