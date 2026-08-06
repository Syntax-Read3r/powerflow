# ==============================================================================
# PowerFlow — Dependencies
# ==============================================================================
# Domain   : Core
# File     : components/core/dependencies.ps1
# Purpose  : Enforces the platform package-manager prerequisite, checks and installs
#            required tools (Starship, fzf, zoxide, lsd, git), and checks PowerShell updates
# Functions: Initialize-Dependencies, Check-PowerShellUpdates, Get-RequiredTools
# Depends  : config/PowerFlow.settings.ps1
#            Test-Dependency, Install-Dependency, Test-PackageManager,
#            Install-PackageManager, Get-PackageManagerName
#            (platform/<os>/adapters/packages.ps1)
# ==============================================================================

# The tools PowerFlow depends on. Shared by Initialize-Dependencies, the recovery
# menu, and the installers, so the list lives in exactly one place.
function Get-RequiredTools {
    return @(
        @{Name = "starship"; Description = "Cross-shell prompt"},
        @{Name = "fzf";      Description = "Fuzzy finder"},
        @{Name = "zoxide";   Description = "Smart directory navigation"},
        @{Name = "lsd";      Description = "Modern ls replacement"},
        @{Name = "git";      Description = "Version control"}
    )
}

function Initialize-Dependencies {
    if (-not $script:CHECK_DEPENDENCIES) { return }

    Write-Host "🔍 Checking dependencies..." -ForegroundColor DarkGray

    # Ensure the platform prerequisite exists (Scoop on Windows; the distro's
    # package manager on Linux). Scoop is shared infrastructure and is never
    # removed by PowerFlow uninstall.
    if (-not (Test-PackageManager)) {
        $mgr = Get-PackageManagerName
        Write-Host "📦 Setting up package manager ($mgr)..." -ForegroundColor Yellow
        if (-not (Install-PackageManager)) {
            Write-Host "❌ No usable package manager — skipping dependency install." -ForegroundColor Red
            return
        }
        Write-Host "✅ Package manager ready" -ForegroundColor Green
    }

    $missingTools = @(Get-RequiredTools | Where-Object { -not (Test-Dependency $_.Name) })

    if ($missingTools.Count -gt 0) {
        Write-Host "📦 Installing missing tools: $($missingTools.Name -join ', ')" -ForegroundColor Yellow

        foreach ($tool in $missingTools) {
            Write-Host "   Installing $($tool.Name) ($($tool.Description))..." -ForegroundColor DarkGray
            if (Install-Dependency $tool.Name) {
                Write-Host "   ✅ $($tool.Name) installed" -ForegroundColor Green
            } else {
                Write-Host "   ❌ Failed to install $($tool.Name)" -ForegroundColor Red
                Write-Host "      Try: $(Get-DependencyInstallHint $tool.Name)" -ForegroundColor DarkGray
            }
        }

        Write-Host "🔄 Refreshing environment..." -ForegroundColor DarkGray
    }
}

function Check-PowerShellUpdates {
    if (-not $script:CHECK_UPDATES) { return }

    # NEVER prompt when stdin is redirected. The update check runs during profile
    # load, so in CI, a script, or `curl … | bash` a Read-Host here would block the
    # whole shell waiting for input that is never coming.
    if ([Console]::IsInputRedirected) { return }

    # Only prompt once per day. Get-TempPath is an adapter — $env:TEMP does not
    # exist on Linux, so components must never read it directly.
    $updateCheckFile = Join-Path (Get-TempPath) '.pwsh_update_check'
    $today = Get-Date -Format "yyyy-MM-dd"

    if (Test-Path $updateCheckFile) {
        $lastCheck = Get-Content $updateCheckFile -ErrorAction SilentlyContinue
        if ($lastCheck -eq $today) { return }   # already checked today
    }

    try {
        $currentVersion = $PSVersionTable.PSVersion

        $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/PowerShell/PowerShell/releases/latest" -TimeoutSec 5 -ErrorAction Stop
        $latestVersion = [Version]($latestRelease.tag_name -replace '^v')

        if ($latestVersion -gt $currentVersion) {
            # HOW to upgrade is entirely platform-specific (winget/MSI on Windows,
            # apt/snap on Linux) — the adapter owns that decision.
            Invoke-PowerShellUpdate `
                -LatestRelease   $latestRelease `
                -CurrentVersion  $currentVersion `
                -LatestVersion   $latestVersion `
                -UpdateCheckFile $updateCheckFile `
                -Today           $today
        }
        else {
            $today | Set-Content $updateCheckFile   # up to date — do not re-check today
        }
    }
    catch {
        # Never let an update check slow down or break profile load.
        Write-Host "⚠️  Could not check for PowerShell updates (network/API limit)" -ForegroundColor DarkGray
    }
}
