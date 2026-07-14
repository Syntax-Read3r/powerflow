# ==============================================================================
# PowerFlow — Version Management
# ==============================================================================
# Domain   : Core
# File     : components/core/version.ps1
# Purpose  : Handles PowerFlow update checking, version display, and self-update
# Functions: Check-PowerFlowUpdates, powerflow-update, Get-PowerFlowVersion, powerflow-version
# Depends  : config/PowerFlow.settings.ps1
# ==============================================================================


function Check-PowerFlowUpdates {
    if (-not $script:CHECK_PROFILE_UPDATES) { return }

    # Check if we've already prompted for this version today OR if we're in a rate limit cooldown
    $updateCheckFile = Join-Path (Get-TempPath) '.powerflow_update_check'
    $rateLimitFile = Join-Path (Get-TempPath) '.powerflow_rate_limit'
    $today = Get-Date -Format "yyyy-MM-dd"

    # Check for existing rate limit cooldown
    if (Test-Path $rateLimitFile) {
        try {
            $rateLimitData = Get-Content $rateLimitFile | ConvertFrom-Json
            $cooldownUntil = [DateTime]$rateLimitData.cooldownUntil

            if ((Get-Date) -lt $cooldownUntil) {
                # Still in cooldown period, skip silently
                return
            } else {
                # Cooldown expired, remove the file
                Remove-Item $rateLimitFile -ErrorAction SilentlyContinue
            }
        } catch {
            # If rate limit file is corrupted, remove it
            Remove-Item $rateLimitFile -ErrorAction SilentlyContinue
        }
    }

    # Check for daily update check
    if (Test-Path $updateCheckFile) {
        $lastCheck = Get-Content $updateCheckFile -ErrorAction SilentlyContinue
        if ($lastCheck -eq $today) {
            return # Already checked today
        }
    }

    try {
        # Check for PowerFlow updates with shorter timeout to fail fast
        $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/$script:POWERFLOW_REPO/releases/latest" -TimeoutSec 3 -ErrorAction Stop
        $latestVersion = [Version]($latestRelease.tag_name -replace '^v')
        $currentVersion = [Version]$script:POWERFLOW_VERSION

        if ($latestVersion -gt $currentVersion) {
            Write-Host ""
            Write-Host "🚀 PowerFlow update available: v$currentVersion → v$latestVersion" -ForegroundColor Cyan
            Write-Host "   Notes: $($latestRelease.html_url)" -ForegroundColor DarkGray
            Write-Host ""
            Write-Host "   1) Install now" -ForegroundColor White
            Write-Host "   2) Skip today" -ForegroundColor White
            Write-Host "   3) Turn off update reminders" -ForegroundColor White
            Write-Host ""

            $choice = Read-Host "   Choice [1/2/3]"

            switch ($choice) {
                "1" {
                    powerflow-update
                }
                "2" {
                    Write-Host "⏭️  Skipping update check for today." -ForegroundColor Yellow
                    $today | Set-Content $updateCheckFile
                }
                "3" {
                    $settingsPath = Join-Path $script:PowerFlowRoot "config\PowerFlow.settings.ps1"
                    if (Test-Path $settingsPath) {
                        $raw = Get-Content $settingsPath -Raw
                        $raw = $raw -replace '\$script:CHECK_PROFILE_UPDATES\s*=\s*\$true', '$script:CHECK_PROFILE_UPDATES = $false'
                        Set-Content $settingsPath $raw -Encoding UTF8
                    }
                    $script:CHECK_PROFILE_UPDATES = $false
                    $today | Set-Content $updateCheckFile
                    Write-Host "🔕 Update reminders disabled. Run 'pwsh-reminders' to re-enable." -ForegroundColor Yellow
                }
                default {
                    Write-Host "⏭️  Update skipped." -ForegroundColor DarkGray
                }
            }
        } else {
            # Save successful check to avoid daily spam
            $today | Set-Content $updateCheckFile
        }
    } catch {
        # Handle different types of errors intelligently
        $errorMessage = $_.Exception.Message

        if ($errorMessage -match "403|rate.?limit|API.?limit" -or $_.Exception.Response.StatusCode -eq 403) {
            # This is specifically a rate limit error
            # Set a longer cooldown period (3 days) to avoid spam
            $cooldownUntil = (Get-Date).AddDays(3).ToString("o")
            $rateLimitData = @{
                lastAttempt = (Get-Date).ToString("o")
                cooldownUntil = $cooldownUntil
                reason = "GitHub API rate limit"
            }

            try {
                $rateLimitData | ConvertTo-Json | Set-Content $rateLimitFile
            } catch {
                # If we can't write the cooldown file, just skip silently
            }

            # Show a one-time informative message
            Write-Host "ℹ️  Update check temporarily disabled (GitHub API limit). Will retry in 3 days." -ForegroundColor DarkGray
        } else {
            # For other network errors (timeouts, DNS issues, etc.), fail completely silently
            # This avoids spam when users have network issues or are offline
            # Don't set any cooldown files - just skip this attempt
        }
    }
}

<#
.SYNOPSIS
    Check for PowerFlow profile updates
.DESCRIPTION
    Checks GitHub repository for newer versions and offers to update
.EXAMPLE
    powerflow-update     # Check for updates interactively
#>
function powerflow-update {
    Write-Host "🔍 Checking for PowerFlow updates..." -ForegroundColor Cyan

    try {
        # Get latest release info from GitHub
        $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/${script:POWERFLOW_REPO}/releases/latest" -TimeoutSec 10 -ErrorAction Stop
        $latestVersion = $latestRelease.tag_name -replace '^v', ''
        $currentVersion = $script:POWERFLOW_VERSION

        Write-Host "📦 Current version: v${currentVersion}" -ForegroundColor Green
        Write-Host "🌐 Latest version: v${latestVersion}" -ForegroundColor Green

        # Compare versions
        if ([Version]$latestVersion -gt [Version]$currentVersion) {
            Write-Host ""
            Write-Host "🚀 PowerFlow update available!" -ForegroundColor Yellow
            Write-Host "📍 Release notes: $($latestRelease.html_url)" -ForegroundColor DarkGray
            Write-Host ""
            Write-Host "Changes in v${latestVersion}:" -ForegroundColor Cyan

            # Show release notes (first 500 chars)
            $releaseNotes = $latestRelease.body
            if ($releaseNotes.Length -gt 500) {
                $releaseNotes = $releaseNotes.Substring(0, 500) + "..."
            }
            Write-Host $releaseNotes -ForegroundColor DarkGray
            Write-Host ""

            $choice = Read-Host "🔄 Update PowerFlow now? (y/n)"

            if ($choice -eq 'y' -or $choice -eq 'Y') {
                Write-Host "📦 Updating PowerFlow..." -ForegroundColor Yellow

                try {
                    # Backup current profile
                    $backupPath = "$PROFILE.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                    Copy-Item $PROFILE $backupPath -Force
                    Write-Host "💾 Backed up current profile to: $backupPath" -ForegroundColor Green

                    # Download new profile
                    $newProfileUrl = "https://raw.githubusercontent.com/${script:POWERFLOW_REPO}/main/Microsoft.PowerShell_profile.ps1"
                    Invoke-RestMethod -Uri $newProfileUrl -OutFile $PROFILE

                    Write-Host "✅ PowerFlow updated successfully!" -ForegroundColor Green
                    Write-Host "🔄 Restart PowerShell or run '. `$PROFILE' to load the new version" -ForegroundColor Cyan

                } catch {
                    Write-Host "❌ Update failed: $($_.Exception.Message)" -ForegroundColor Red
                    Write-Host "🔄 Restoring from backup..." -ForegroundColor Yellow

                    if (Test-Path $backupPath) {
                        Copy-Item $backupPath $PROFILE -Force
                        Write-Host "✅ Profile restored from backup" -ForegroundColor Green
                    }
                }
            } else {
                Write-Host "⏭️  Update cancelled" -ForegroundColor Yellow
            }

        } elseif ([Version]$latestVersion -eq [Version]$currentVersion) {
            Write-Host "✅ PowerFlow is up to date!" -ForegroundColor Green
        } else {
            Write-Host "🚀 You're running a development version (v${currentVersion} > v${latestVersion})" -ForegroundColor Cyan
        }

    } catch {
        if ($_.Exception.Message -match "404") {
            Write-Host "❌ PowerFlow repository not found. Check repository URL." -ForegroundColor Red
        } elseif ($_.Exception.Message -match "403") {
            Write-Host "❌ GitHub API rate limit exceeded. Try again later." -ForegroundColor Red
        } else {
            Write-Host "⚠️  Could not check for updates: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "🌐 Check manually: https://github.com/${script:POWERFLOW_REPO}/releases" -ForegroundColor DarkGray
        }
    }
}

<#
.SYNOPSIS
    Get detailed PowerFlow version information
.DESCRIPTION
    Shows current PowerFlow version, repository info, and installation status
.EXAMPLE
    Get-PowerFlowVersion     # Shows detailed version info
#>
function Get-PowerFlowVersion {
    Write-Host ""
    Write-Host "╭─ 🚀 POWERFLOW VERSION INFO ─────────────────────────────────────────────╮" -ForegroundColor Cyan
    Write-Host "│                                                                          │" -ForegroundColor Cyan
   Write-Host "│  📦 Version: ${script:POWERFLOW_VERSION}".PadRight(73) + "│" -ForegroundColor Cyan
Write-Host "│  📍 Repository: ${script:POWERFLOW_REPO}".PadRight(73) + "│" -ForegroundColor Cyan
    Write-Host "│  📄 Profile: $PROFILE".PadRight(73) + "│" -ForegroundColor Cyan

    # Check installation status
    $profileExists = Test-Path $PROFILE
    $depsInstalled = @("starship", "fzf", "zoxide", "lsd", "git") | ForEach-Object {
        Get-Command $_ -ErrorAction SilentlyContinue
    } | Measure-Object | Select-Object -ExpandProperty Count

    Write-Host "│  ✅ Profile Loaded: $profileExists".PadRight(73) + "│" -ForegroundColor Cyan
    Write-Host "│  🔧 Dependencies: $depsInstalled/5 installed".PadRight(73) + "│" -ForegroundColor Cyan

    # Check last update
    if (Test-Path $script:BookmarkFile) {
        $bookmarkCount = (Get-Bookmarks).Count
        Write-Host "│  🔖 Bookmarks: $bookmarkCount configured".PadRight(73) + "│" -ForegroundColor Cyan
    }

    Write-Host "│                                                                          │" -ForegroundColor Cyan
    Write-Host "╰──────────────────────────────────────────────────────────────────────────╯" -ForegroundColor Cyan
    Write-Host ""
}

<#
.SYNOPSIS
    Show PowerFlow version (short format)
.DESCRIPTION
    Quick version display for status checks
.EXAMPLE
    powerflow-version     # Shows version info
#>
function powerflow-version {
    Write-Host "🚀 PowerFlow v${script:POWERFLOW_VERSION}" -ForegroundColor Cyan
    Write-Host "📍 Repository: ${script:POWERFLOW_REPO}" -ForegroundColor DarkGray
    Write-Host "📄 Profile: $PROFILE" -ForegroundColor DarkGray
}

function pwsh-reminders {
    $settingsPath = Join-Path $script:PowerFlowRoot "config\PowerFlow.settings.ps1"
    $current = $script:CHECK_PROFILE_UPDATES
    $statusText = if ($current) { "✅ ON" } else { "🔕 OFF" }

    Write-Host ""
    Write-Host "🔔 Update reminders: $statusText" -ForegroundColor Cyan
    Write-Host ""

    if ($current) {
        $choice = Read-Host "Turn off update reminders? (y/n)"
        if ($choice -eq 'y') {
            if (Test-Path $settingsPath) {
                $raw = Get-Content $settingsPath -Raw
                $raw = $raw -replace '\$script:CHECK_PROFILE_UPDATES\s*=\s*\$true', '$script:CHECK_PROFILE_UPDATES = $false'
                Set-Content $settingsPath $raw -Encoding UTF8
            }
            $script:CHECK_PROFILE_UPDATES = $false
            Write-Host "🔕 Update reminders disabled. Run 'pwsh-reminders' to re-enable." -ForegroundColor Yellow
        } else {
            Write-Host "No change." -ForegroundColor DarkGray
        }
    } else {
        $choice = Read-Host "Turn on update reminders? (y/n)"
        if ($choice -eq 'y') {
            if (Test-Path $settingsPath) {
                $raw = Get-Content $settingsPath -Raw
                $raw = $raw -replace '\$script:CHECK_PROFILE_UPDATES\s*=\s*\$false', '$script:CHECK_PROFILE_UPDATES = $true'
                Set-Content $settingsPath $raw -Encoding UTF8
            }
            $script:CHECK_PROFILE_UPDATES = $true
            # Delete daily-check marker so the update check fires on next profile load
            Remove-Item (Join-Path (Get-TempPath) '.powerflow_update_check') -ErrorAction SilentlyContinue
            Write-Host "🔔 Update reminders enabled. You'll be notified on the next profile load." -ForegroundColor Green
        } else {
            Write-Host "No change." -ForegroundColor DarkGray
        }
    }
    Write-Host ""
}
