# ==============================================================================
# PowerFlow — Version Management
# ==============================================================================
# Domain   : Core
# File     : components/core/version.ps1
# Purpose  : Handles PowerFlow update checking, version display, and self-update
# Functions: Check-PowerFlowUpdates, powerflow-update, Get-PowerFlowVersion, powerflow-version
# Depends  : config/PowerFlow.settings.ps1
# ==============================================================================


# ── update-check plumbing ─────────────────────────────────────────────────────

<#
.SYNOPSIS
    The newest published PowerFlow version, WITHOUT spending API quota.
.DESCRIPTION
    github.com/<repo>/releases/latest 302-redirects to .../tag/vX.Y.Z. Reading that
    Location header is the website, not the API — no meaningful rate limit. The API is
    only the fallback, and an anonymous-API 403 is precisely what silently killed the
    v3.3.2 release, so avoiding it by default is not a micro-optimisation.
#>
function Get-LatestPowerFlowVersion {
    try {
        $resp = Invoke-WebRequest -Uri "https://github.com/$script:POWERFLOW_REPO/releases/latest" `
                    -MaximumRedirection 0 -SkipHttpErrorCheck -TimeoutSec 3 -ErrorAction Stop
        $loc = @($resp.Headers.Location)[0]
        if ($loc -match '/tag/v?([\d][\d.]*)$') {
            return [pscustomobject]@{ Version = [Version]$matches[1]; Url = "$loc" }
        }
    } catch {}

    # Fallback: the API (rate-limited when anonymous — hence the cooldown handling
    # in the caller).
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$script:POWERFLOW_REPO/releases/latest" `
               -TimeoutSec 3 -ErrorAction Stop
    return [pscustomobject]@{ Version = [Version]($rel.tag_name -replace '^v'); Url = $rel.html_url }
}

# The snooze marker holds an ISO date; checks are suppressed until it passes.
# (The old file held today's date and compared equality — "defer" could only ever
# mean "until midnight".)
function Test-UpdateSnoozed {
    $f = Join-Path (Get-TempPath) '.powerflow_update_check'
    if (-not (Test-Path $f)) { return $false }
    try {
        $until = [DateTime](Get-Content $f -ErrorAction Stop | Select-Object -First 1)
        return ((Get-Date) -lt $until)
    } catch { return $false }   # unreadable/legacy marker -> just check again
}

function Set-UpdateSnooze {
    param([int]$Days = 1)
    (Get-Date).Date.AddDays($Days).ToString('yyyy-MM-dd') |
        Set-Content (Join-Path (Get-TempPath) '.powerflow_update_check')
}

function Check-PowerFlowUpdates {
    if (-not $script:CHECK_PROFILE_UPDATES) { return }

    $rateLimitFile = Join-Path (Get-TempPath) '.powerflow_rate_limit'

    # Rate-limit cooldown from a previous 403 still active? Skip silently.
    if (Test-Path $rateLimitFile) {
        try {
            if ((Get-Date) -lt [DateTime]((Get-Content $rateLimitFile | ConvertFrom-Json).cooldownUntil)) { return }
            Remove-Item $rateLimitFile -ErrorAction SilentlyContinue
        } catch { Remove-Item $rateLimitFile -ErrorAction SilentlyContinue }
    }

    if (Test-UpdateSnoozed) { return }

    try {
        $latest  = Get-LatestPowerFlowVersion
        $current = [Version]$script:POWERFLOW_VERSION

        if ($latest.Version -le $current) {
            Set-UpdateSnooze -Days 1     # up to date; don't ask the network again today
            return
        }

        # A profile load with REDIRECTED stdin (scripts, scp, tooling that forgot
        # -NoProfile) has nobody to answer Read-Host — it would read EOF and fall
        # through. Announce on one line, snooze the day, never block.
        if ([Console]::IsInputRedirected) {
            Write-Host "🚀 PowerFlow v$($latest.Version) is available (you have v$current) — run: powerflow-update" -ForegroundColor Cyan
            Set-UpdateSnooze -Days 1
            return
        }

        Write-Host ""
        Write-Host "🚀 PowerFlow update available: v$current → v$($latest.Version)" -ForegroundColor Cyan
        Write-Host "   Notes: $($latest.Url)" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "   1) Install now" -ForegroundColor White
        Write-Host "   2) Remind me tomorrow" -ForegroundColor White
        Write-Host "   3) Snooze for a week" -ForegroundColor White
        Write-Host "   4) Turn off update reminders" -ForegroundColor White
        Write-Host ""

        switch (Read-Host "   Choice [1/2/3/4]") {
            "1" { powerflow-update -Yes }
            "2" { Set-UpdateSnooze -Days 1; Write-Host "⏭️  Okay — tomorrow." -ForegroundColor Yellow }
            "3" { Set-UpdateSnooze -Days 7; Write-Host "😴 Snoozed until $((Get-Date).Date.AddDays(7).ToString('MMM d'))." -ForegroundColor Yellow }
            "4" {
                $settingsPath = Join-Path $script:PowerFlowRoot "config\PowerFlow.settings.ps1"
                if (Test-Path $settingsPath) {
                    $raw = Get-Content $settingsPath -Raw
                    $raw = $raw -replace '\$script:CHECK_PROFILE_UPDATES\s*=\s*\$true', '$script:CHECK_PROFILE_UPDATES = $false'
                    Set-Content $settingsPath $raw -Encoding UTF8
                }
                $script:CHECK_PROFILE_UPDATES = $false
                Write-Host "🔕 Update reminders disabled. Run 'pwsh-reminders' to re-enable." -ForegroundColor Yellow
            }
            default { Set-UpdateSnooze -Days 1; Write-Host "⏭️  Skipped — I'll ask again tomorrow." -ForegroundColor DarkGray }
        }
    } catch {
        if ($_.Exception.Message -match "403|rate.?limit" -or $_.Exception.Response.StatusCode -eq 403) {
            # 403 = rate limited. Cool down for 3 days so a limited IP isn't hammered
            # by every new shell.
            try {
                @{ lastAttempt = (Get-Date).ToString('o')
                   cooldownUntil = (Get-Date).AddDays(3).ToString('o')
                   reason = 'GitHub API rate limit' } | ConvertTo-Json | Set-Content $rateLimitFile
            } catch {}
            Write-Host "ℹ️  Update check paused (GitHub API limit). Will retry in 3 days." -ForegroundColor DarkGray
        }
        # Anything else (offline, DNS, timeout): silent — a dead network should not
        # make opening a shell noisy.
    }
}

<#
.SYNOPSIS
    powerflow-update — upgrade PowerFlow in place, the WHOLE tree.
.DESCRIPTION
    Downloads install.ps1 from the repo and runs it. The installer fetches the full
    tree itself, recognises its own manifest (so an existing install is upgraded, not
    interrogated), keeps the original pre-PowerFlow profile backup, and preserves
    dependency ownership. Everything a real upgrade needs — because it IS the installer.

    ⚠️ HISTORY, so nobody "simplifies" this back: the previous implementation
    downloaded ONLY Microsoft.PowerShell_profile.ps1 and overwrote $PROFILE — a relic
    of the pre-2.0 monolith. On the component layout that produced a NEW bootloader
    loading OLD components, and since $script:POWERFLOW_VERSION lives in config/ (which
    it never touched), the "updated" install still reported the old version and
    re-prompted every day, forever.
.EXAMPLE
    powerflow-update          # confirm, then upgrade
    powerflow-update -Yes     # no questions (the startup prompt uses this)
#>
function powerflow-update {
    param([switch]$Yes)

    Write-Host "🔍 Checking for PowerFlow updates..." -ForegroundColor Cyan

    try {
        $latest  = Get-LatestPowerFlowVersion
        $current = [Version]$script:POWERFLOW_VERSION

        Write-Host "📦 Current: v$current   🌐 Latest: v$($latest.Version)" -ForegroundColor Green

        if ($latest.Version -eq $current) {
            Write-Host "✅ PowerFlow is up to date!" -ForegroundColor Green
            return
        }
        if ($latest.Version -lt $current) {
            Write-Host "🚀 You're running a development version (v$current > v$($latest.Version))" -ForegroundColor Cyan
            return
        }

        Write-Host "📍 Release notes: $($latest.Url)" -ForegroundColor DarkGray

        if (-not $Yes) {
            if ((Read-Host "🔄 Update PowerFlow to v$($latest.Version) now? (y/n)") -notin @('y', 'Y')) {
                Write-Host "⏭️  Update cancelled" -ForegroundColor Yellow
                return
            }
        }

        Write-Host "📦 Updating PowerFlow (full tree, via the installer)..." -ForegroundColor Yellow

        $tmp = Join-Path (Get-TempPath) "powerflow-update-$(Get-Random)"
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            $installer = Join-Path $tmp 'install.ps1'
            Invoke-RestMethod -Uri "https://raw.githubusercontent.com/$script:POWERFLOW_REPO/main/install.ps1" `
                -OutFile $installer -TimeoutSec 30 -ErrorAction Stop

            # A CHILD pwsh, -NoProfile: the installer must not run inside the very
            # session whose files it is replacing.
            & pwsh -NoProfile -File $installer -Yes -NoDeps
            if ($LASTEXITCODE -ne 0) {
                Write-Host "❌ The installer reported failure (exit $LASTEXITCODE). Nothing to roll back — it backs itself up." -ForegroundColor Red
                return
            }

            Write-Host ""
            Write-Host "✅ PowerFlow updated to v$($latest.Version)!" -ForegroundColor Green
            Write-Host "🔄 Restart your shell (or run:  . `$PROFILE ) to load it" -ForegroundColor Cyan
        }
        finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    } catch {
        if ($_.Exception.Message -match "403") {
            Write-Host "❌ GitHub API rate limit exceeded. Try again later." -ForegroundColor Red
        } else {
            Write-Host "⚠️  Could not update: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "🌐 Manual route: https://github.com/$script:POWERFLOW_REPO/releases" -ForegroundColor DarkGray
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

# ── pwsh-h registration ───────────────────────────────────────────────────────
Register-PFCommand -Name 'powerflow-version'   -Section '⚙️ CONFIGURATION & SETTINGS' -Synopsis 'show the PowerFlow version'
Register-PFCommand -Name 'powerflow-update'    -Section '⚙️ CONFIGURATION & SETTINGS' -Synopsis 'full-tree update via the real installer'
Register-PFCommand -Name 'Get-PowerFlowVersion' -Section '⚙️ CONFIGURATION & SETTINGS' -Synopsis 'detailed version and install status'
Register-PFCommand -Name 'pwsh-reminders'      -Section '⚙️ CONFIGURATION & SETTINGS' -Synopsis 'toggle the startup update reminder'
