# ==============================================================================
# PowerFlow — PowerShell Update Adapter (Windows)
# ==============================================================================
# Domain   : Platform / Windows
# File     : platform/windows/adapters/pwsh-update.ps1
# Purpose  : Detect how PowerShell was installed (MSI / winget / Store / Scoop)
#            and drive the correct upgrade path for it
# Contract : Invoke-PowerShellUpdate
# Depends  : Open-Url (openers.ps1), Get-TempPath (locations.ps1)
# ==============================================================================
#
# Moved out of components/core/dependencies.ps1 in v3.0.0. Every branch here is
# Windows-only: winget, MSI assets, the Microsoft Store, and a .bat trampoline
# that survives the current pwsh process exiting mid-upgrade.
# ==============================================================================

# Turn off PowerFlow's PowerShell update checks by rewriting the settings file.
#
# The flag lives in config/PowerFlow.settings.ps1 — NOT in $PROFILE. Before this fix
# the function rewrote $PROFILE, where the string `$script:CHECK_UPDATES = $true` does not
# exist (it moved into the settings file in the v3.0.0 split), so the replace matched
# nothing and option 4 silently did nothing — the prompt came back every session. This now
# mirrors the Linux adapter, which already targeted the settings file correctly.
function Disable-PowerShellUpdateCheck {
    Write-Host "🚫 Disabling automatic update checks" -ForegroundColor Yellow
    try {
        $settings = Join-Path $script:PowerFlowRoot 'config/PowerFlow.settings.ps1'
        $content  = Get-Content $settings -Raw
        $updated  = $content -replace '\$script:CHECK_UPDATES = \$true', '$script:CHECK_UPDATES = $false'
        if ($updated -ne $content) {
            Set-Content $settings $updated
            Write-Host "✅ Automatic update checks disabled" -ForegroundColor Green
        } else {
            Write-Host "💡 Already disabled — or set `$script:CHECK_UPDATES = `$false in config/PowerFlow.settings.ps1" -ForegroundColor DarkGray
        }
    } catch {
        Write-Host "💡 Edit config/PowerFlow.settings.ps1 and set `$script:CHECK_UPDATES = `$false" -ForegroundColor DarkGray
    }
}

# Open the MSI asset matching this machine's architecture, else the release page.
function Open-PowerShellMsi {
    param([Parameter(Mandatory)]$LatestRelease)

    $architecture = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
    $msiAsset = $LatestRelease.assets | Where-Object {
        $_.name -like "*win-$architecture.msi" -and $_.name -notlike "*arm*"
    } | Select-Object -First 1

    if ($msiAsset) {
        Write-Host "🌐 Opening MSI download: $($msiAsset.name)" -ForegroundColor Cyan
        Open-Url $msiAsset.browser_download_url
        Write-Host "📦 Run the MSI after download to update PowerShell" -ForegroundColor Green
        Write-Host "🔄 Then restart your terminal" -ForegroundColor Green
    } else {
        Write-Host "❌ Could not find an MSI for your architecture" -ForegroundColor Red
        Write-Host "🌐 Opening release page..." -ForegroundColor Cyan
        Open-Url $LatestRelease.html_url
    }
}

# Uninstall + reinstall via winget. This has to run from a .bat trampoline: the
# current pwsh process must exit before winget can replace it.
function Invoke-WingetReinstall {
    $batchScript = @"
@echo off
title PowerShell Update Process
echo.
echo ======================================
echo   PowerShell Automated Update
echo ======================================
echo.
echo Waiting for PowerShell to close...
timeout /t 3 /nobreak >nul

echo.
echo [1/3] Uninstalling current PowerShell...
winget uninstall Microsoft.PowerShell --silent --force
if errorlevel 1 (
    echo Warning: Uninstall may have failed, continuing...
)

echo.
echo [2/3] Installing PowerShell via winget...
winget install Microsoft.PowerShell --accept-source-agreements --accept-package-agreements --force
if errorlevel 1 (
    echo Error: Installation failed!
    pause
    exit /b 1
)

echo.
echo [3/3] Starting new PowerShell...
timeout /t 2 /nobreak >nul
start "" "pwsh"

echo.
echo Update complete! A new PowerShell window should be open.
echo You can close this window.
echo.
pause
"@

    $batchPath = Join-Path (Get-TempPath) 'update_powershell.bat'
    $batchScript | Set-Content $batchPath

    Write-Host "🚀 Starting automated update..." -ForegroundColor Green
    Start-Process cmd.exe -ArgumentList "/c `"$batchPath`"" -WindowStyle Normal
    Start-Sleep -Seconds 1
    Write-Host "👋 Goodbye! See you in the updated PowerShell..." -ForegroundColor Cyan
    exit
}

# Entry point — called by Check-PowerShellUpdates when a newer release exists.
function Invoke-PowerShellUpdate {
    param(
        [Parameter(Mandatory)]$LatestRelease,
        [Parameter(Mandatory)]$CurrentVersion,
        [Parameter(Mandatory)]$LatestVersion,
        [Parameter(Mandatory)][string]$UpdateCheckFile,
        [Parameter(Mandatory)][string]$Today
    )

    Write-Host "🚀 PowerShell update available: v$CurrentVersion → v$LatestVersion" -ForegroundColor Cyan

    # ── How was PowerShell actually installed? ────────────────────────────────
    $psPath              = $PSHOME
    $isWingetListed      = $false
    $actualInstallMethod = "Unknown"

    if     ($psPath -like "*Program Files\PowerShell*") { $actualInstallMethod = "MSI" }
    elseif ($psPath -like "*WindowsApps*")              { $actualInstallMethod = "Microsoft Store" }
    elseif ($psPath -like "*scoop*")                    { $actualInstallMethod = "Scoop" }

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        try {
            $wingetList = winget list Microsoft.PowerShell 2>$null
            if ($wingetList -match "Microsoft.PowerShell") { $isWingetListed = $true }
        } catch { }
    }

    Write-Host "📍 Release page: $($LatestRelease.html_url)" -ForegroundColor DarkGray

    # ── MSI install that winget ALSO claims — the broken state ────────────────
    if ($actualInstallMethod -eq "MSI" -and $isWingetListed) {
        Write-Host "⚠️  CONFLICT DETECTED:" -ForegroundColor Yellow
        Write-Host "   • Installation: MSI at $psPath" -ForegroundColor DarkGray
        Write-Host "   • Winget database has a conflicting entry" -ForegroundColor DarkGray
        Write-Host "   • This prevents proper updates" -ForegroundColor DarkGray
        Write-Host ""

        $choice = Read-Host "🔧 Fix this: (1) Uninstall + fresh winget install (2) Manual MSI update (3) Skip today (4) Disable checks"

        switch ($choice) {
            "1" {
                Write-Host "🗑️  This will uninstall the current PowerShell and reinstall via winget" -ForegroundColor Yellow
                Write-Host "⚠️  Your current PowerShell session will close!" -ForegroundColor Red
                Write-Host "💡 A new PowerShell window will open when complete" -ForegroundColor Cyan
                if ((Read-Host "Continue? (y/n)") -eq 'y') {
                    try { Invoke-WingetReinstall }
                    catch {
                        Write-Host "❌ Failed to start update process: $($_.Exception.Message)" -ForegroundColor Red
                        Write-Host "💡 Try the manual MSI update (option 2)" -ForegroundColor DarkGray
                    }
                } else {
                    Write-Host "❌ Update cancelled" -ForegroundColor Yellow
                }
            }
            "2" {
                Open-PowerShellMsi -LatestRelease $LatestRelease
                Write-Host "💡 Note: this will not fix the winget conflict" -ForegroundColor DarkGray
            }
            "3" { Write-Host "⏭️  Skipping update check for today" -ForegroundColor Yellow; $Today | Set-Content $UpdateCheckFile }
            "4" { Disable-PowerShellUpdateCheck }
            default { Write-Host "⏭️  Update check skipped" -ForegroundColor DarkGray }
        }
    }
    # ── Clean MSI install (no winget conflict) ────────────────────────────────
    elseif ($actualInstallMethod -eq "MSI") {
        Write-Host "🔧 Clean MSI installation detected" -ForegroundColor Green

        switch (Read-Host "🔄 (1) Download MSI update (2) Migrate to winget (3) Skip today (4) Disable checks") {
            "1" { Open-PowerShellMsi -LatestRelease $LatestRelease }
            "2" {
                Write-Host "🔄 Migrating to winget management..." -ForegroundColor Cyan
                try {
                    winget install Microsoft.PowerShell --force --accept-source-agreements --accept-package-agreements
                    Write-Host "✅ Migration complete! Restart your terminal." -ForegroundColor Green
                } catch {
                    Write-Host "❌ Migration failed: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            "3" { $Today | Set-Content $UpdateCheckFile }
            "4" { Disable-PowerShellUpdateCheck }
        }
    }
    # ── Microsoft Store / MSIX install ────────────────────────────────────────
    # winget LISTS msix packages too, so this MUST come before the winget branch —
    # otherwise a Store install is treated as "winget-managed" and told to "restart your
    # terminal", which is wrong. An MSIX package can't be replaced while ANY of its
    # processes run: winget only STAGES the new version, and it applies once every
    # instance has closed. So the honest guidance is "close them all / reboot".
    elseif ($actualInstallMethod -eq "Microsoft Store") {
        Write-Host "🔧 Microsoft Store (MSIX) installation detected" -ForegroundColor Green
        Write-Host "   Note: an MSIX update only takes effect once EVERY PowerShell window is closed." -ForegroundColor DarkGray

        switch (Read-Host "🔄 (1) Stage update via winget (2) Open the Microsoft Store (3) Skip today (4) Disable checks") {
            "1" {
                Write-Host "📦 Staging update via winget..." -ForegroundColor Yellow
                try {
                    winget upgrade Microsoft.PowerShell --accept-source-agreements --accept-package-agreements
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "✅ Update staged." -ForegroundColor Green
                        Write-Host "   It applies once you CLOSE EVERY PowerShell window (terminal tabs, VS Code" -ForegroundColor DarkGray
                        Write-Host "   terminals, panes) — or reboot. Opening a new tab alone keeps the old version." -ForegroundColor DarkGray
                    } else {
                        Write-Host "❌ Winget update failed (exit code: $LASTEXITCODE)" -ForegroundColor Red
                        Write-Host "💡 Try the Microsoft Store (option 2)" -ForegroundColor DarkGray
                    }
                } catch {
                    Write-Host "❌ Winget update error: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            "2" { Write-Host "🏪 Opening the Microsoft Store..." -ForegroundColor Cyan; Open-Url 'ms-windows-store://pdp/?productid=9MZ1SNWT0N5D' }
            "3" { $Today | Set-Content $UpdateCheckFile }
            "4" { Disable-PowerShellUpdateCheck }
        }
    }
    # ── winget-managed install ────────────────────────────────────────────────
    elseif ($isWingetListed) {
        Write-Host "🔧 Winget-managed installation detected" -ForegroundColor Green

        switch (Read-Host "🔄 (1) Update via winget (2) Manual download (3) Skip today (4) Disable checks") {
            "1" {
                Write-Host "📦 Updating via winget..." -ForegroundColor Yellow
                try {
                    winget upgrade Microsoft.PowerShell --accept-source-agreements --accept-package-agreements
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "✅ Update successful! Restart your terminal." -ForegroundColor Green
                    } else {
                        Write-Host "❌ Winget update failed (exit code: $LASTEXITCODE)" -ForegroundColor Red
                        Write-Host "💡 Try the manual download (option 2)" -ForegroundColor DarkGray
                    }
                } catch {
                    Write-Host "❌ Winget update error: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            "2" { Write-Host "🌐 Opening release page..." -ForegroundColor Cyan; Open-Url $LatestRelease.html_url }
            "3" { $Today | Set-Content $UpdateCheckFile }
            "4" { Disable-PowerShellUpdateCheck }
        }
    }
    # ── Anything else (Store, Scoop, unknown) ─────────────────────────────────
    else {
        Write-Host "🔧 Installation method: $actualInstallMethod" -ForegroundColor Yellow

        switch (Read-Host "🔄 (1) Manual download (2) Try winget (3) Skip today (4) Disable checks") {
            "1" { Open-Url $LatestRelease.html_url }
            "2" {
                try {
                    winget install Microsoft.PowerShell --force --accept-source-agreements --accept-package-agreements
                    Write-Host "✅ Winget install complete!" -ForegroundColor Green
                } catch {
                    Write-Host "❌ Winget install failed: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            "3" { $Today | Set-Content $UpdateCheckFile }
            "4" { Disable-PowerShellUpdateCheck }
        }
    }
}
