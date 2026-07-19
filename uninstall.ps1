#Requires -Version 5.1

<#
.SYNOPSIS
    PowerFlow uninstaller — shared by Windows and Linux.
.DESCRIPTION
    Reads the manifest written at install time and removes EXACTLY what PowerFlow
    placed — nothing else.

    The rule that makes this safe:

        A dependency with installedByPowerFlow = false is NEVER touched.

    If you already had fzf before installing PowerFlow, uninstalling PowerFlow does
    not remove fzf. The old Ubuntu port's uninstaller deleted ~/.bashrc outright,
    and the old Windows one ripped out shared Scoop tools regardless of who
    installed them. A manifest is precisely what prevents that class of mistake.
.PARAMETER Yes
    Assume yes; no prompts (CI-safe).
.PARAMETER Purge
    Also remove user data (bookmarks).
.PARAMETER KeepDeps
    Do not remove any dependencies, even ones PowerFlow installed.
#>

param(
    [switch]$Yes,
    [switch]$Purge,
    [switch]$KeepDeps
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "🗑️  PowerFlow Uninstall" -ForegroundColor Cyan
Write-Host "======================" -ForegroundColor Cyan
Write-Host ""

$profileDir   = Split-Path $PROFILE -Parent
$manifestPath = Join-Path $profileDir '.powerflow-manifest.json'

# ── No manifest: fall back to a conservative removal ──────────────────────────
if (-not (Test-Path $manifestPath)) {
    Write-Host "⚠️  No manifest found at $manifestPath" -ForegroundColor Yellow
    Write-Host "   PowerFlow was installed before v3.0.0, or by hand." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "   Falling back to a conservative removal: the profile and component" -ForegroundColor DarkGray
    Write-Host "   directories only. NO dependencies will be touched, because without" -ForegroundColor DarkGray
    Write-Host "   a manifest there is no way to know which ones you already had." -ForegroundColor DarkGray
    Write-Host ""

    if (-not $Yes -and (Read-Host "Continue? (y/n)") -ne 'y') {
        Write-Host "❌ Cancelled" -ForegroundColor Yellow; exit 0
    }

    foreach ($d in @('config', 'components', 'platform', 'windows-only', 'docs')) {
        $p = Join-Path $profileDir $d
        if (Test-Path $p) { Remove-Item $p -Recurse -Force; Write-Host "  ✅ removed $d/" -ForegroundColor Green }
    }
    if (Test-Path $PROFILE) { Remove-Item $PROFILE -Force; Write-Host "  ✅ removed profile" -ForegroundColor Green }

    Write-Host ""
    Write-Host "✅ PowerFlow removed. Restart your shell." -ForegroundColor Green
    exit 0
}

$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

$removableDeps = @()
$keptDeps      = @()
if ($manifest.dependencies) {
    if (-not $KeepDeps) {
        $removableDeps = @($manifest.dependencies | Where-Object { $_.installedByPowerFlow })
    }
    $keptDeps = @($manifest.dependencies | Where-Object { -not $_.installedByPowerFlow })
}

# ── Show exactly what will happen BEFORE doing any of it ──────────────────────
Write-Host "PowerFlow v$($manifest.version) ($($manifest.platform))" -ForegroundColor White
Write-Host "Installed: $($manifest.installedAt)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Will REMOVE:" -ForegroundColor Yellow
Write-Host "  • $($manifest.files.Count) tracked files (profile + config/ + components/ + platform/)" -ForegroundColor DarkGray
if ($removableDeps.Count -gt 0) {
    Write-Host "  • dependencies PowerFlow installed: $(($removableDeps.name) -join ', ')" -ForegroundColor DarkGray
}
if ($Purge) { Write-Host "  • user data: bookmarks (-Purge)" -ForegroundColor DarkGray }

if ($keptDeps.Count -gt 0) {
    Write-Host ""
    Write-Host "Will KEEP — you already had these before PowerFlow:" -ForegroundColor Green
    Write-Host "  • $(($keptDeps.name) -join ', ')" -ForegroundColor DarkGray
}

if ($manifest.backup) {
    Write-Host ""
    Write-Host "Will RESTORE your previous profile from:" -ForegroundColor Cyan
    Write-Host "  • $($manifest.backup)" -ForegroundColor DarkGray
}

Write-Host ""
if (-not $Yes -and (Read-Host "Proceed? (y/n)") -ne 'y') {
    Write-Host "❌ Cancelled — nothing was removed." -ForegroundColor Yellow
    exit 0
}

# ── 1. Remove dependencies FIRST (the adapter lives in files we're about to delete)
if ($removableDeps.Count -gt 0) {
    Write-Host ""
    Write-Host "📦 Removing dependencies PowerFlow installed..." -ForegroundColor Yellow

    $adapter = Join-Path $manifest.installRoot "platform/$($manifest.platform)/adapters/packages.ps1"
    if (Test-Path $adapter) {
        . $adapter
        if (Uninstall-Dependency @($removableDeps.name)) {
            Write-Host "✅ Removed: $(($removableDeps.name) -join ', ')" -ForegroundColor Green
        } else {
            Write-Host "⚠️  Some could not be removed — remove manually: $(($removableDeps.name) -join ', ')" -ForegroundColor Yellow
        }
    } else {
        Write-Host "⚠️  Packages adapter missing — remove manually: $(($removableDeps.name) -join ', ')" -ForegroundColor Yellow
    }
}

# ── 2. Remove installed files ─────────────────────────────────────────────────
Write-Host ""
$removed = 0
foreach ($f in $manifest.files) {
    if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue; $removed++ }
}
Write-Host "✅ Removed $removed of $($manifest.files.Count) tracked files" -ForegroundColor Green

foreach ($d in @('config', 'components', 'platform', 'windows-only', 'docs')) {
    $p = Join-Path $manifest.installRoot $d
    if (Test-Path $p) { Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue }
}

# ── 3. Restore the backed-up profile ──────────────────────────────────────────
if ($manifest.backup -and (Test-Path $manifest.backup)) {
    Copy-Item $manifest.backup $manifest.profilePath -Force
    Write-Host "♻️  Restored your previous profile" -ForegroundColor Green
}

# ── 4. Optional purge of user data ────────────────────────────────────────────
# User data = things the USER built up (bookmarks, nav roots, saved SSH servers).
# Kept by default: reinstalling should not cost anyone their server list.
$userData = @(
    @{ Label = 'bookmarks';   Path = (Join-Path $HOME '.nav_bookmarks.json') }
    @{ Label = 'nav roots';   Path = (Join-Path $HOME '.nav_roots.json') }
    @{ Label = 'SSH servers'; Path = (Join-Path $HOME '.powerflow-servers.json') }
)
if ($Purge) {
    Write-Host ""
    Write-Host "🧹 Purging user data..." -ForegroundColor Yellow
    foreach ($d in $userData) {
        if (Test-Path $d.Path) { Remove-Item $d.Path -Force; Write-Host "  ✅ $($d.Label)" -ForegroundColor Green }
    }
}
else {
    $kept = @($userData | Where-Object { Test-Path $_.Path } | ForEach-Object Label)
    if ($kept.Count) {
        Write-Host ""
        Write-Host "💾 Kept your $($kept -join ', '). Use -Purge to remove them." -ForegroundColor DarkGray
    }
}

Remove-Item $manifestPath -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "✅ PowerFlow uninstalled" -ForegroundColor Green
Write-Host "🔄 Restart your shell to apply" -ForegroundColor Cyan
Write-Host "🙏 Thanks for using PowerFlow!" -ForegroundColor DarkGray
Write-Host ""
