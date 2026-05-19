# ==============================================================================
# PowerFlow — Dependencies
# ==============================================================================
# Domain   : Core
# File     : components/core/dependencies.ps1
# Purpose  : Checks and installs required tools (Scoop, Starship, fzf, zoxide, lsd, git) and PowerShell updates
# Functions: Initialize-Dependencies, Check-PowerShellUpdates
# Depends  : config/PowerFlow.settings.ps1
# ==============================================================================

function Initialize-Dependencies {
    if (-not $script:CHECK_DEPENDENCIES) { return }

    Write-Host "🔍 Checking dependencies..." -ForegroundColor DarkGray

    # Check and install Scoop package manager
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-Host "📦 Installing Scoop package manager..." -ForegroundColor Yellow
        try {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
            Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
            Write-Host "✅ Scoop installed successfully" -ForegroundColor Green
        } catch {
            Write-Host "❌ Failed to install Scoop: $($_.Exception.Message)" -ForegroundColor Red
            return
        }
    }

    # Required tools for this profile
    $requiredTools = @(
        @{Name = "starship"; Command = "starship"; Description = "Cross-shell prompt"},
        @{Name = "fzf"; Command = "fzf"; Description = "Fuzzy finder"},
        @{Name = "zoxide"; Command = "zoxide"; Description = "Smart directory navigation"},
        @{Name = "lsd"; Command = "lsd"; Description = "Modern ls replacement"},
        @{Name = "git"; Command = "git"; Description = "Version control"}
    )

    $missingTools = @()
    foreach ($tool in $requiredTools) {
        if (-not (Get-Command $tool.Command -ErrorAction SilentlyContinue)) {
            $missingTools += $tool
        }
    }

    if ($missingTools.Count -gt 0) {
        Write-Host "📦 Installing missing tools: $($missingTools.Name -join ', ')" -ForegroundColor Yellow

        foreach ($tool in $missingTools) {
            try {
                Write-Host "   Installing $($tool.Name) ($($tool.Description))..." -ForegroundColor DarkGray
                scoop install $tool.Name *>$null
                Write-Host "   ✅ $($tool.Name) installed" -ForegroundColor Green
            } catch {
                Write-Host "   ❌ Failed to install $($tool.Name): $($_.Exception.Message)" -ForegroundColor Red
            }
        }

        # Refresh PATH after installations
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")

        Write-Host "🔄 Refreshing environment..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 1
    }
}


function Check-PowerShellUpdates {
    if (-not $script:CHECK_UPDATES) { return }

    # Check if we've already prompted for this version today
    $updateCheckFile = "$env:TEMP\.pwsh_update_check"
    $today = Get-Date -Format "yyyy-MM-dd"

    if (Test-Path $updateCheckFile) {
        $lastCheck = Get-Content $updateCheckFile -ErrorAction SilentlyContinue
        if ($lastCheck -eq $today) {
            return # Already checked today
        }
    }

    try {
        # Get current PowerShell version
        $currentVersion = $PSVersionTable.PSVersion

        # Check for updates via GitHub API
        $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/PowerShell/PowerShell/releases/latest" -TimeoutSec 5 -ErrorAction Stop
        $latestVersion = [Version]($latestRelease.tag_name -replace '^v')

        if ($latestVersion -gt $currentVersion) {
            Write-Host "🚀 PowerShell update available: v$currentVersion → v$latestVersion" -ForegroundColor Cyan

            # Detect installation method and conflicts
            $psPath = $PSHOME
            $isWingetListed = $false
            $actualInstallMethod = "Unknown"

            # Check actual installation location
            if ($psPath -like "*Program Files\PowerShell*") {
                $actualInstallMethod = "MSI"
            } elseif ($psPath -like "*WindowsApps*") {
                $actualInstallMethod = "Microsoft Store"
            } elseif ($psPath -like "*scoop*") {
                $actualInstallMethod = "Scoop"
            }

            # Check if winget thinks it's managing PowerShell
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                try {
                    $wingetList = winget list Microsoft.PowerShell 2>$null
                    if ($wingetList -match "Microsoft.PowerShell") {
                        $isWingetListed = $true
                    }
                } catch { }
            }

            # Handle MSI + winget conflict
            if ($actualInstallMethod -eq "MSI" -and $isWingetListed) {
                Write-Host "⚠️  CONFLICT DETECTED:" -ForegroundColor Yellow
                Write-Host "   • Installation: MSI at $psPath" -ForegroundColor DarkGray
                Write-Host "   • Winget database has conflicting entry" -ForegroundColor DarkGray
                Write-Host "   • This prevents proper updates" -ForegroundColor DarkGray
                Write-Host "📍 Release page: $($latestRelease.html_url)" -ForegroundColor DarkGray
                Write-Host ""

                $choice = Read-Host "🔧 Fix this: (1) Uninstall + fresh winget install (2) Manual MSI update (3) Skip today (4) Disable checks"

                switch ($choice) {
                    "1" {
                        Write-Host "🗑️  This will uninstall current PowerShell and install fresh via winget" -ForegroundColor Yellow
                        Write-Host "⚠️  Your current PowerShell session will close!" -ForegroundColor Red
                        Write-Host "💡 A new PowerShell window will open when complete" -ForegroundColor Cyan
                        $confirm = Read-Host "Continue? (y/n)"

                        if ($confirm -eq 'y') {
                            try {
                                # Create automated update script
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
echo ✅ Update complete! New PowerShell window should be open.
echo You can close this window.
echo.
pause
"@

                                $batchPath = "$env:TEMP\update_powershell.bat"
                                $batchScript | Set-Content $batchPath

                                Write-Host "🚀 Starting automated update..." -ForegroundColor Green

                                # Start the batch script and exit current PowerShell
                                Start-Process cmd.exe -ArgumentList "/c `"$batchPath`"" -WindowStyle Normal
                                Start-Sleep -Seconds 1
                                Write-Host "👋 Goodbye! See you in the updated PowerShell..." -ForegroundColor Cyan
                                exit

                            } catch {
                                Write-Host "❌ Failed to start update process: $($_.Exception.Message)" -ForegroundColor Red
                                Write-Host "💡 Try manual update (option 2)" -ForegroundColor DarkGray
                            }
                        } else {
                            Write-Host "❌ Update cancelled" -ForegroundColor Yellow
                        }
                    }
                    "2" {
                        # Manual MSI download
                        $architecture = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
                        $msiAsset = $latestRelease.assets | Where-Object {
                            $_.name -like "*win-$architecture.msi" -and $_.name -notlike "*arm*"
                        } | Select-Object -First 1

                        if ($msiAsset) {
                            Write-Host "🌐 Opening MSI download: $($msiAsset.name)" -ForegroundColor Cyan
                            Start-Process $msiAsset.browser_download_url
                            Write-Host "📦 After download, run the MSI to update PowerShell" -ForegroundColor Green
                            Write-Host "🔄 Then restart your terminal" -ForegroundColor Green
                            Write-Host "💡 Note: This won't fix the winget conflict" -ForegroundColor DarkGray
                        } else {
                            Write-Host "❌ Could not find MSI for your architecture" -ForegroundColor Red
                            Write-Host "🌐 Opening release page..." -ForegroundColor Cyan
                            Start-Process $latestRelease.html_url
                        }
                    }
                    "3" {
                        Write-Host "⏭️  Skipping update check for today" -ForegroundColor Yellow
                        $today | Set-Content $updateCheckFile
                    }
                    "4" {
                        Write-Host "🚫 Disabling automatic update checks" -ForegroundColor Yellow
                        try {
                            $profileContent = Get-Content $PROFILE -Raw
                            $updatedContent = $profileContent -replace '\$script:CHECK_UPDATES = \$true', '$script:CHECK_UPDATES = $false'
                            if ($updatedContent -ne $profileContent) {
                                Set-Content $PROFILE $updatedContent
                                Write-Host "✅ Automatic update checks disabled in profile" -ForegroundColor Green
                            }
                        } catch {
                            Write-Host "💡 Edit your profile and set `$script:CHECK_UPDATES = `$false" -ForegroundColor DarkGray
                        }
                    }
                    default {
                        Write-Host "⏭️  Update check skipped" -ForegroundColor DarkGray
                    }
                }
            } elseif ($actualInstallMethod -eq "MSI" -and -not $isWingetListed) {
                # Handle clean installations (no conflicts)
                Write-Host "🔧 Clean MSI installation detected" -ForegroundColor Green
                Write-Host "📍 Release page: $($latestRelease.html_url)" -ForegroundColor DarkGray

                $choice = Read-Host "🔄 (1) Download MSI update (2) Migrate to winget (3) Skip today (4) Disable checks"

                switch ($choice) {
                    "1" {
                        $architecture = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
                        $msiAsset = $latestRelease.assets | Where-Object {
                            $_.name -like "*win-$architecture.msi" -and $_.name -notlike "*arm*"
                        } | Select-Object -First 1

                        if ($msiAsset) {
                            Write-Host "🌐 Opening MSI download: $($msiAsset.name)" -ForegroundColor Cyan
                            Start-Process $msiAsset.browser_download_url
                            Write-Host "📦 Run the MSI after download to update" -ForegroundColor Green
                        } else {
                            Start-Process $latestRelease.html_url
                        }
                    }
                    "2" {
                        Write-Host "🔄 Migrating to winget management..." -ForegroundColor Cyan
                        try {
                            winget install Microsoft.PowerShell --force --accept-source-agreements --accept-package-agreements
                            Write-Host "✅ Migration complete! Restart your terminal." -ForegroundColor Green
                        } catch {
                            Write-Host "❌ Migration failed: $($_.Exception.Message)" -ForegroundColor Red
                        }
                    }
                    "3" {
                        $today | Set-Content $updateCheckFile
                    }
                    "4" {
                        Write-Host "🚫 Disabling automatic update checks" -ForegroundColor Yellow
                        try {
                            $profileContent = Get-Content $PROFILE -Raw
                            $updatedContent = $profileContent -replace '\$script:CHECK_UPDATES = \$true', '$script:CHECK_UPDATES = $false'
                            if ($updatedContent -ne $profileContent) {
                                Set-Content $PROFILE $updatedContent
                                Write-Host "✅ Disabled in profile" -ForegroundColor Green
                            }
                        } catch {
                            Write-Host "💡 Edit profile: `$script:CHECK_UPDATES = `$false" -ForegroundColor DarkGray
                        }
                    }
                }
            } elseif ($isWingetListed) {
                # Handle winget-managed installations
                Write-Host "🔧 Winget-managed installation detected" -ForegroundColor Green
                Write-Host "📍 Release page: $($latestRelease.html_url)" -ForegroundColor DarkGray

                $choice = Read-Host "🔄 (1) Update via winget (2) Manual download (3) Skip today (4) Disable checks"

                switch ($choice) {
                    "1" {
                        Write-Host "📦 Updating via winget..." -ForegroundColor Yellow
                        try {
                            winget upgrade Microsoft.PowerShell --accept-source-agreements --accept-package-agreements
                            if ($LASTEXITCODE -eq 0) {
                                Write-Host "✅ Update successful! Restart your terminal." -ForegroundColor Green
                            } else {
                                Write-Host "❌ Winget update failed (exit code: $LASTEXITCODE)" -ForegroundColor Red
                                Write-Host "💡 Try manual download (option 2)" -ForegroundColor DarkGray
                            }
                        } catch {
                            Write-Host "❌ Winget update error: $($_.Exception.Message)" -ForegroundColor Red
                        }
                    }
                    "2" {
                        Write-Host "🌐 Opening release page for manual download..." -ForegroundColor Cyan
                        Start-Process $latestRelease.html_url
                    }
                    "3" {
                        $today | Set-Content $updateCheckFile
                    }
                    "4" {
                        Write-Host "🚫 Disabling automatic update checks" -ForegroundColor Yellow
                        try {
                            $profileContent = Get-Content $PROFILE -Raw
                            $updatedContent = $profileContent -replace '\$script:CHECK_UPDATES = \$true', '$script:CHECK_UPDATES = $false'
                            if ($updatedContent -ne $profileContent) {
                                Set-Content $PROFILE $updatedContent
                                Write-Host "✅ Disabled in profile" -ForegroundColor Green
                            }
                        } catch {
                            Write-Host "💡 Edit profile: `$script:CHECK_UPDATES = `$false" -ForegroundColor DarkGray
                        }
                    }
                }
            } else {
                # Handle other installation methods
                Write-Host "🔧 Installation method: $actualInstallMethod" -ForegroundColor Yellow
                Write-Host "📍 Release page: $($latestRelease.html_url)" -ForegroundColor DarkGray

                $choice = Read-Host "🔄 (1) Manual download (2) Try winget (3) Skip today (4) Disable checks"

                switch ($choice) {
                    "1" {
                        Start-Process $latestRelease.html_url
                    }
                    "2" {
                        try {
                            winget install Microsoft.PowerShell --force --accept-source-agreements --accept-package-agreements
                            Write-Host "✅ Winget install complete!" -ForegroundColor Green
                        } catch {
                            Write-Host "❌ Winget install failed: $($_.Exception.Message)" -ForegroundColor Red
                        }
                    }
                    "3" {
                        $today | Set-Content $updateCheckFile
                    }
                    "4" {
                        Write-Host "🚫 Disabling automatic update checks" -ForegroundColor Yellow
                        try {
                            $profileContent = Get-Content $PROFILE -Raw
                            $updatedContent = $profileContent -replace '\$script:CHECK_UPDATES = \$true', '$script:CHECK_UPDATES = $false'
                            if ($updatedContent -ne $profileContent) {
                                Set-Content $PROFILE $updatedContent
                                Write-Host "✅ Disabled in profile" -ForegroundColor Green
                            }
                        } catch {
                            Write-Host "💡 Edit profile: `$script:CHECK_UPDATES = `$false" -ForegroundColor DarkGray
                        }
                    }
                }
            }
        } else {
            # Save successful check to avoid daily spam
            $today | Set-Content $updateCheckFile
        }
    } catch {
        # Silent fail for update checks to avoid slowing down profile loading
        Write-Host "⚠️  Could not check for PowerShell updates (network/API limit)" -ForegroundColor DarkGray
    }
}
