# ============================================================================
# PowerFlow - Enhanced PowerShell Profile
# ============================================================================
# A beautiful, intelligent PowerShell profile that supercharges your terminal 
# experience with smart navigation, enhanced Git workflows, and productivity-
# focused tools.
# 
# Repository: https://github.com/Syntax-Read3r/powerflow
# Documentation: See README.md for complete feature list and usage examples
# Version: 1.0.0
# Release Date: 2024-01-XX
# ============================================================================

# Version management
$script:POWERFLOW_VERSION = "1.0.2"
$script:POWERFLOW_REPO = "Syntax-Read3r/powerflow"
$script:CHECK_PROFILE_UPDATES = $true
$script:CHECK_DEPENDENCIES = $true
$script:CHECK_UPDATES = $true

# Suppress progress bars for faster installation
$ProgressPreference = 'SilentlyContinue'

# ============================================================================
# ENHANCED PROFILE UPDATE CHECKING
# ============================================================================

function Check-PowerFlowUpdates {
    if (-not $script:CHECK_PROFILE_UPDATES) { return }
    
    # Check if we've already prompted for this version today
    $updateCheckFile = "$env:TEMP\.powerflow_update_check"
    $today = Get-Date -Format "yyyy-MM-dd"
    
    if (Test-Path $updateCheckFile) {
        $lastCheck = Get-Content $updateCheckFile -ErrorAction SilentlyContinue
        if ($lastCheck -eq $today) {
            return # Already checked today
        }
    }
    
    try {
        # Check for PowerFlow updates
        $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/$script:POWERFLOW_REPO/releases/latest" -TimeoutSec 5 -ErrorAction Stop
        $latestVersion = [Version]($latestRelease.tag_name -replace '^v')
        $currentVersion = [Version]$script:POWERFLOW_VERSION
        
        if ($latestVersion -gt $currentVersion) {
            Write-Host "🚀 PowerFlow update available: v$currentVersion → v$latestVersion" -ForegroundColor Cyan
            Write-Host "📍 Release: $($latestRelease.html_url)" -ForegroundColor DarkGray
            
            $choice = Read-Host "🔄 Update now? (y/n/s=skip today)"
            
            switch ($choice) {
                "y" {
                    powerflow-update
                }
                "s" {
                    Write-Host "⏭️  Skipping PowerFlow update check for today" -ForegroundColor Yellow
                    $today | Set-Content $updateCheckFile
                }
                default {
                    Write-Host "⏭️  PowerFlow update skipped" -ForegroundColor DarkGray
                }
            }
        } else {
            # Save successful check to avoid daily spam
            $today | Set-Content $updateCheckFile
        }
    } catch {
        # Silent fail for update checks to avoid slowing down profile loading
        Write-Host "⚠️  Could not check for PowerFlow updates (network/API limit)" -ForegroundColor DarkGray
    }
}

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

# Run initialization
try {
    Initialize-Dependencies
    Check-PowerShellUpdates
    Check-PowerFlowUpdates
} catch {
    Write-Host "⚠️  Initialization warning: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Restore progress preference
$ProgressPreference = 'Continue'

Write-Host "🚀 Profile initialization complete" -ForegroundColor Green

<#
.SYNOPSIS
    Open current directory in Windows File Explorer
.DESCRIPTION
    Opens the current working directory in Windows File Explorer.
    Simple and fast function for quick file system access.
.EXAMPLE
    open-pwd     # Opens current directory in File Explorer
    op           # Shorthand alias
#>
function open-pwd {
    try {
        $currentPath = (Get-Location).Path
        
        # Check if the path exists
        if (-not (Test-Path $currentPath)) {
            Write-Host "❌ Current directory does not exist: $currentPath" -ForegroundColor Red
            return
        }
        
        # Open in File Explorer
        explorer.exe $currentPath
        
        Write-Host "📁 Opened File Explorer: $currentPath" -ForegroundColor Green
        
    } catch {
        Write-Host "❌ Failed to open File Explorer: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function op {
    open-pwd
}


<#
.SYNOPSIS
    Beautiful interactive Git add-commit-push workflow
.DESCRIPTION
    Performs git add ., git commit -m, and git push with a beautiful interface.
    Shows current status, previous commits for context, and provides confirmations.
.EXAMPLE
    git-a     # Opens beautiful add-commit-push interface
#>
function git-a {
    # Check if we're in a git repository
    if (-not (git rev-parse --git-dir 2>$null)) {
        Write-Host "❌ Not in a Git repository" -ForegroundColor Red
        return
    }

    # Check for changes
    $status = git status --short
    if (-not $status) {
        Write-Host "✅ No changes to commit - working tree is clean" -ForegroundColor Green
        return
    }

    # Get current branch and commit history
    $branch = git rev-parse --abbrev-ref HEAD
    $commits = git log --oneline --color=always -n 2 2>$null
    
    # Format commits with numbering (latest first)
    $commitLines = @()
    if ($commits) {
        $commitArray = @($commits)
        for ($i = 0; $i -lt $commitArray.Count; $i++) {
            $commitLines += "   $($i + 1). $($commitArray[$i])"
        }
    } else {
        $commitLines += "   (No previous commits)"
    }

    # Enhanced file status formatting
    $fileLines = @()
    $status | ForEach-Object {
        $statusCode = $_.Substring(0, 2)
        $fileName = $_.Substring(3)
        
        switch ($statusCode.Trim()) {
            "M"  { $fileLines += "   📝 $fileName (modified)" }
            "A"  { $fileLines += "   ➕ $fileName (added)" }
            "D"  { $fileLines += "   🗑 $fileName (deleted)" }
            "R"  { $fileLines += "   🔄 $fileName (renamed)" }
            "C"  { $fileLines += "   📋 $fileName (copied)" }
            "??" { $fileLines += "   ❓ $fileName (untracked)" }
            default { $fileLines += "   📄 $fileName ($statusCode)" }
        }
    }

    # Minimalistic formatted display for fzf
    $formLines = @(
        "",
        "🌿 Branch: $branch",
        "",
        "📋 Files to be committed:"
    ) + $fileLines + @(
        "",
        "📚 Recent commit history:"
    ) + $commitLines + @(
        "",
        "💬 Type your commit message above and press Enter"
    )

    # Launch fzf with --print-query to get typed input, not selected line
    $fzfOutput = $formLines | fzf `
        --ansi `
        --reverse `
        --border=rounded `
        --height=80% `
        --prompt="📝 Commit Message: " `
        --header="🚀 Git Add → Commit → Push Workflow" `
        --header-first `
        --color="header:bold:blue,prompt:bold:green,border:cyan,spinner:yellow" `
        --margin=1 `
        --padding=1 `
        --print-query `
        --expect=enter
    
    # Extract the commit message from fzf output
    # --print-query returns the typed query on first line
    $commitMessage = ""
    if ($fzfOutput) {
        $lines = @($fzfOutput)
        if ($lines.Count -gt 0) {
            $commitMessage = $lines[0].Trim()
        }
    }

    # Validate commit message
    if ([string]::IsNullOrWhiteSpace($commitMessage) -or $commitMessage.Length -lt 3) {
        Write-Host "❌ Commit message too short or cancelled" -ForegroundColor Yellow
        return
    }

    # Execute the workflow with progress indicators
    Write-Host "📂 Adding all changes..." -ForegroundColor Yellow
    git add .
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ git add failed" -ForegroundColor Red
        return
    }
    Write-Host "✅ Files staged successfully" -ForegroundColor Green

    Write-Host "💾 Committing changes..." -ForegroundColor Yellow
    git commit -m $commitMessage
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ git commit failed" -ForegroundColor Red
        return
    }
    Write-Host "✅ Commit created successfully" -ForegroundColor Green

    Write-Host "🚀 Pushing to remote..." -ForegroundColor Yellow
    git push
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Successfully pushed to '$branch'" -ForegroundColor Green
    } else {
        Write-Host "❌ git push failed" -ForegroundColor Red
        Write-Host "💡 You may need to set upstream or resolve conflicts" -ForegroundColor DarkGray
    }
}




function git-rba {
    # Check if we're in a git repository
    if (-not (git rev-parse --git-dir 2>$null)) {
        Write-Host "❌ Not in a Git repository" -ForegroundColor Red
        return
    }

    # Get current branch name
    $currentBranch = git branch --show-current
    
    # Check if current branch matches rollback-<alphanumeric> pattern
    if ($currentBranch -notmatch '^rollback-[a-zA-Z0-9]+$') {
        Write-Host "❌ Error: Not on a rollback branch" -ForegroundColor Red
        Write-Host "Current branch: $currentBranch" -ForegroundColor Yellow
        Write-Host "Expected pattern: rollback-<alphanumeric> (e.g., rollback-781, rollback-a27, rollback-fix123)" -ForegroundColor Yellow
        return
    }

    Write-Host "🔄 Working on rollback branch: $currentBranch" -ForegroundColor Cyan

    # Check for changes
    $status = git status --short
    if (-not $status) {
        Write-Host "ℹ️  No changes to commit, working tree clean" -ForegroundColor Yellow
        Write-Host "🚀 Pushing existing commits to origin..." -ForegroundColor Blue
        git push origin $currentBranch
        
        # Show the GitHub PR creation link
        $repoUrl = git config --get remote.origin.url
        if ($repoUrl -like "*github.com*") {
            if ($repoUrl -match 'github\.com[:/](.+?)(?:\.git)?/?$') {
                $repoPath = $matches[1] -replace '\.git$', ''
                Write-Host ""
                Write-Host "🔗 Create a pull request by visiting:" -ForegroundColor Magenta
                Write-Host "   https://github.com/$repoPath/pull/new/$currentBranch" -ForegroundColor Blue
            }
        }
        Write-Host "✅ Rollback branch operations completed!" -ForegroundColor Green
        return
    }

    # Get commit history for current rollback branch only
    $commits = git log --oneline --color=always -n 2 $currentBranch 2>$null
    
    # Format commits with numbering (latest first)
    $commitLines = @()
    if ($commits) {
        $commitArray = @($commits)
        for ($i = 0; $i -lt $commitArray.Count; $i++) {
            $commitLines += "   $($i + 1). $($commitArray[$i])"
        }
    } else {
        $commitLines += "   (No previous commits)"
    }

    # Enhanced file status formatting
    $fileLines = @()
    $status | ForEach-Object {
        $statusCode = $_.Substring(0, 2)
        $fileName = $_.Substring(3)
        
        switch ($statusCode.Trim()) {
            "M"  { $fileLines += "   📝 $fileName (modified)" }
            "A"  { $fileLines += "   ➕ $fileName (added)" }
            "D"  { $fileLines += "   🗑 $fileName (deleted)" }
            "R"  { $fileLines += "   🔄 $fileName (renamed)" }
            "C"  { $fileLines += "   📋 $fileName (copied)" }
            "??" { $fileLines += "   ❓ $fileName (untracked)" }
            default { $fileLines += "   📄 $fileName ($statusCode)" }
        }
    }

    # Minimalistic formatted display for fzf
    $formLines = @(
        "",
        "🔄 Rollback Branch: $currentBranch",
        "",
        "📋 Files to be committed:"
    ) + $fileLines + @(
        "",
        "📚 Recent commit history (this branch):"
    ) + $commitLines + @(
        "",
        "💬 Type your commit message above and press Enter"
    )

    # Launch fzf with --print-query to get typed input, not selected line
    $fzfOutput = $formLines | fzf `
        --ansi `
        --reverse `
        --border=rounded `
        --height=80% `
        --prompt="📝 Commit Message: " `
        --header="🚀 Git Add → Commit → Push Workflow" `
        --header-first `
        --color="header:bold:blue,prompt:bold:green,border:cyan,spinner:yellow" `
        --margin=1 `
        --padding=1 `
        --print-query `
        --expect=enter
    
    # Extract the commit message from fzf output
    $commitMessage = ""
    if ($fzfOutput) {
        $lines = @($fzfOutput)
        if ($lines.Count -gt 0) {
            $commitMessage = $lines[0].Trim()
        }
    }

    # Validate commit message
    if ([string]::IsNullOrWhiteSpace($commitMessage) -or $commitMessage.Length -lt 3) {
        Write-Host "❌ Commit message too short or cancelled" -ForegroundColor Yellow
        return
    }

    # Execute the rollback workflow with progress indicators
    Write-Host "📂 Adding all changes..." -ForegroundColor Yellow
    git add .
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ git add failed" -ForegroundColor Red
        return
    }
    Write-Host "✅ Files staged successfully" -ForegroundColor Green

    Write-Host "💾 Committing changes..." -ForegroundColor Yellow
    git commit -m $commitMessage
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ git commit failed" -ForegroundColor Red
        return
    }
    Write-Host "✅ Commit created successfully" -ForegroundColor Green

    Write-Host "🚀 Pushing to origin $currentBranch..." -ForegroundColor Yellow
    git push origin $currentBranch
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Successfully pushed to '$currentBranch'" -ForegroundColor Green
    } else {
        Write-Host "❌ git push failed" -ForegroundColor Red
        Write-Host "💡 You may need to resolve conflicts or check remote access" -ForegroundColor DarkGray
        return
    }

    # Show the GitHub PR creation link
    $repoUrl = git config --get remote.origin.url
    if ($repoUrl -like "*github.com*") {
        if ($repoUrl -match 'github\.com[:/](.+?)(?:\.git)?/?$') {
            $repoPath = $matches[1] -replace '\.git$', ''
            Write-Host ""
            Write-Host "🔗 Create a pull request by visiting:" -ForegroundColor Magenta
            Write-Host "   https://github.com/$repoPath/pull/new/$currentBranch" -ForegroundColor Blue
        }
    }
    
    Write-Host "✅ Rollback branch operations completed!" -ForegroundColor Green
}

# Create shorter alias
Set-Alias -Name grba -Value git-rba



<#
.SYNOPSIS
    Create rollback branch and reset code to specific commit
.DESCRIPTION
    Creates a new branch named 'rollback-<last3chars>' where last3chars are the
    last 3 characters of the commit hash, then resets all code to that commit state.
    This allows you to safely rollback to any previous commit without losing work.
.PARAMETER commitHash
    The commit hash to rollback to (can be short or full hash)
.PARAMETER Force
    Skip confirmation prompts
.EXAMPLE
    git-rb abc1234              # Creates rollback-234 branch from commit abc1234
    git-rb abc1234 -Force       # Skip confirmation prompts
    git-rb HEAD~3               # Rollback 3 commits using relative reference
#>
function git-rb {
    param(
        [Parameter(Mandatory = $true)]
        [string]$commitHash,
        [switch]$Force
    )
    
    # Check if we're in a git repository
    if (-not (git rev-parse --git-dir 2>$null)) {
        Write-Host "❌ Not in a Git repository" -ForegroundColor Red
        return
    }
    
    # Resolve the commit hash to full hash and validate it exists
    try {
        $fullHash = git rev-parse $commitHash 2>$null
        if (-not $fullHash) {
            Write-Host "❌ Invalid commit hash: $commitHash" -ForegroundColor Red
            return
        }
    } catch {
        Write-Host "❌ Could not resolve commit: $commitHash" -ForegroundColor Red
        return
    }
    
    # Get short hash for display and branch naming
    $shortHash = git rev-parse --short $commitHash
    $last3Chars = $shortHash.Substring([Math]::Max(0, $shortHash.Length - 3))
    $branchName = "rollback-$last3Chars"
    
    # Get commit info for confirmation
    $commitInfo = git log --oneline -n 1 $commitHash
    $currentBranch = git rev-parse --abbrev-ref HEAD
    
    # Safety confirmation
    if (-not $Force) {
        Write-Host ""
        Write-Host "🔄 Git Rollback Operation" -ForegroundColor Cyan
        Write-Host "═══════════════════════════" -ForegroundColor Cyan
        Write-Host "📍 Current branch: $currentBranch" -ForegroundColor Yellow
        Write-Host "🎯 Target commit: $commitInfo" -ForegroundColor Green
        Write-Host "🌿 New branch: $branchName" -ForegroundColor Green
        Write-Host ""
        Write-Host "⚠️  This will:" -ForegroundColor Yellow
        Write-Host "   • Create new branch '$branchName'" -ForegroundColor DarkGray
        Write-Host "   • Switch to that branch" -ForegroundColor DarkGray
        Write-Host "   • Reset ALL code to match commit $shortHash" -ForegroundColor DarkGray
        Write-Host ""
        
        $confirm = Read-Host "Continue with rollback? (y/n)"
        if ($confirm -ne 'y' -and $confirm -ne 'Y') {
            Write-Host "❌ Rollback cancelled" -ForegroundColor Yellow
            return
        }
    }
    
    # Check if branch already exists
    $existingBranch = git branch --list $branchName
    if ($existingBranch) {
        if (-not $Force) {
            Write-Host "⚠️  Branch '$branchName' already exists!" -ForegroundColor Yellow
            $overwrite = Read-Host "Delete existing branch and recreate? (y/n)"
            if ($overwrite -ne 'y' -and $overwrite -ne 'Y') {
                Write-Host "❌ Rollback cancelled" -ForegroundColor Yellow
                return
            }
        }
        
        # Delete existing branch (force delete in case it's not merged)
        Write-Host "🗑 Deleting existing branch: $branchName" -ForegroundColor Yellow
        git branch -D $branchName
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Failed to delete existing branch" -ForegroundColor Red
            return
        }
    }
    
    # Create new branch from the target commit and switch to it
    Write-Host "🌿 Creating rollback branch: $branchName" -ForegroundColor Cyan
    git checkout -b $branchName $commitHash
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "✅ Rollback successful!" -ForegroundColor Green
        Write-Host "📍 Current branch: $branchName" -ForegroundColor Cyan
        Write-Host "🎯 Code state: $commitInfo" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "💡 Your code is now exactly as it was at commit $shortHash" -ForegroundColor DarkGray
        Write-Host "💡 Original branch '$currentBranch' remains unchanged" -ForegroundColor DarkGray
        Write-Host "💡 Use 'git checkout $currentBranch' to return to original state" -ForegroundColor DarkGray
        
        # Show current status
        Write-Host ""
        Write-Host "📊 Current status:" -ForegroundColor Cyan
        git status --short
        
    } else {
        Write-Host "❌ Failed to create rollback branch" -ForegroundColor Red
        Write-Host "💡 Check if the commit hash is valid and try again" -ForegroundColor DarkGray
    }
}












<#
.SYNOPSIS
    Enhanced Git add-commit-push with additional options
.DESCRIPTION
    Extended version with options for different workflows
.PARAMETER Quick
    Skip confirmations for rapid commits
.PARAMETER DryRun
    Show what would be done without executing
.PARAMETER AmendLast
    Amend the last commit instead of creating new one
.EXAMPLE
    git-a-plus -Quick           # Fast mode with minimal prompts
    git-a-plus -DryRun          # Preview mode
    git-a-plus -AmendLast       # Amend last commit
#>
function git-a-plus {
    param(
        [switch]$Quick,
        [switch]$DryRun,
        [switch]$AmendLast
    )

    # Check if we're in a git repository
    if (-not (git rev-parse --git-dir 2>$null)) {
        Write-Host "❌ Not in a Git repository" -ForegroundColor Red
        return
    }

    if ($AmendLast) {
        # Amend last commit workflow with beautiful styling
        $branch = git rev-parse --abbrev-ref HEAD
        $lastCommit = git log --oneline --color=always -n 1 2>$null
        $commits = git log --oneline --color=always -n 3 2>$null
        
        # Format recent commits for context
        $commitLines = @()
        if ($commits) {
            $commitArray = @($commits)
            for ($i = 0; $i -lt [Math]::Min($commitArray.Count, 3); $i++) {
                if ($i -eq 0) {
                    $commitLines += "   👑 $($commitArray[$i]) (current)"
                } else {
                    $commitLines += "   $($i + 1). $($commitArray[$i])"
                }
            }
        }

        # Beautiful formatted display for amend
        $formLines = @(
            "",
            "🌿 Branch: $branch",
            "",
            "🔄 Amending last commit:",
            "   👑 $lastCommit",
            "",
            "📚 Recent commit history:"
        ) + $commitLines + @(
            "",
            "💬 Type new commit message (or press Enter to keep current)"
        )

        # Launch fzf for amend message input
        $fzfOutput = $formLines | fzf `
            --ansi `
            --reverse `
            --border=rounded `
            --height=70% `
            --prompt="📝 New Message: " `
            --header="🔄 Amend Last Commit" `
            --header-first `
            --color="header:bold:yellow,prompt:bold:cyan,border:yellow" `
            --margin=1 `
            --padding=1 `
            --print-query `
            --expect=enter
        
        # Extract the new message
        $newMessage = ""
        if ($fzfOutput) {
            $lines = @($fzfOutput)
            if ($lines.Count -gt 0) {
                $newMessage = $lines[0].Trim()
            }
        }
        
        Write-Host "🔄 Amending commit..." -ForegroundColor Yellow
        
        if ([string]::IsNullOrWhiteSpace($newMessage)) {
            git add .
            git commit --amend --no-edit
            Write-Host "✅ Amended with original message" -ForegroundColor Green
        } else {
            git add .
            git commit --amend -m $newMessage
            Write-Host "✅ Amended with new message: $newMessage" -ForegroundColor Green
        }
        
        if ($LASTEXITCODE -eq 0) {
            $pushConfirm = Read-Host "🚀 Force push amended commit? (y/n)"
            if ($pushConfirm -eq 'y') {
                Write-Host "🚀 Force pushing..." -ForegroundColor Yellow
                git push --force-with-lease
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "✅ Successfully force-pushed amended commit" -ForegroundColor Green
                } else {
                    Write-Host "❌ Failed to push amended commit" -ForegroundColor Red
                }
            }
        } else {
            Write-Host "❌ Failed to amend commit" -ForegroundColor Red
        }
        return
    }

    if ($DryRun) {
        # Dry run mode with beautiful file status display
        $branch = git rev-parse --abbrev-ref HEAD
        $status = git status --short
        
        if (-not $status) {
            Write-Host ""
            Write-Host "╭─ 🔍 DRY RUN PREVIEW ─────────────────────────────────────────────────╮" -ForegroundColor Cyan
            Write-Host "│                                                                      │" -ForegroundColor Cyan
            Write-Host "│  ✅ No changes to commit - working tree is clean                    │" -ForegroundColor Cyan
            Write-Host "│                                                                      │" -ForegroundColor Cyan
            Write-Host "╰──────────────────────────────────────────────────────────────────────╯" -ForegroundColor Cyan
            Write-Host ""
            return
        }

        # Enhanced file status formatting (same as git-a)
        $fileLines = @()
        $status | ForEach-Object {
            $statusCode = $_.Substring(0, 2)
            $fileName = $_.Substring(3)
            
            switch ($statusCode.Trim()) {
                "M"  { $fileLines += "   📝 $fileName (modified)" }
                "A"  { $fileLines += "   ➕ $fileName (added)" }
                "D"  { $fileLines += "   🗑 $fileName (deleted)" }
                "R"  { $fileLines += "   🔄 $fileName (renamed)" }
                "C"  { $fileLines += "   📋 $fileName (copied)" }
                "??" { $fileLines += "   ❓ $fileName (untracked)" }
                default { $fileLines += "   📄 $fileName ($statusCode)" }
            }
        }

        # Beautiful dry run display
        Write-Host ""
        Write-Host "╭─ 🔍 DRY RUN PREVIEW ─────────────────────────────────────────────────╮" -ForegroundColor Cyan
        Write-Host "│                                                                      │" -ForegroundColor Cyan
        Write-Host "│  🌿 Branch: $branch".PadRight(69) + "│" -ForegroundColor Cyan
        Write-Host "│                                                                      │" -ForegroundColor Cyan
        Write-Host "╰──────────────────────────────────────────────────────────────────────╯" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "📋 Files that would be added:" -ForegroundColor Yellow
        $fileLines | ForEach-Object { Write-Host $_ -ForegroundColor White }
        Write-Host ""
        Write-Host "💡 Run 'git-a' to execute the actual workflow" -ForegroundColor Cyan
        Write-Host ""
        return
    }

    if ($Quick) {
        # Quick mode with minimal but beautiful styling
        $branch = git rev-parse --abbrev-ref HEAD
        $status = git status --short
        
        if (-not $status) {
            Write-Host "✅ No changes to commit - working tree is clean" -ForegroundColor Green
            return
        }

        # Show quick preview
        $fileCount = @($status).Count
        Write-Host ""
        Write-Host "╭─ ⚡ QUICK COMMIT MODE ───────────────────────────────────────────────╮" -ForegroundColor Yellow
        Write-Host "│                                                                      │" -ForegroundColor Yellow
        Write-Host "│  🌿 Branch: $branch".PadRight(69) + "│" -ForegroundColor Yellow
        Write-Host "│  📂 Files: $fileCount file(s) to commit".PadRight(69) + "│" -ForegroundColor Yellow
        Write-Host "│                                                                      │" -ForegroundColor Yellow
        Write-Host "╰──────────────────────────────────────────────────────────────────────╯" -ForegroundColor Yellow
        Write-Host ""

        Write-Host "💬 Commit message: " -NoNewline -ForegroundColor Cyan
        $commitMessage = Read-Host
        
        if ([string]::IsNullOrWhiteSpace($commitMessage) -or $commitMessage.Length -lt 3) {
            Write-Host "❌ Commit message too short or empty" -ForegroundColor Red
            return
        }

        Write-Host ""
        Write-Host "⚡ Executing quick workflow..." -ForegroundColor Yellow
        
        git add .
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ git add failed" -ForegroundColor Red
            return
        }
        Write-Host "✅ Files staged" -ForegroundColor Green

        git commit -m $commitMessage
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ git commit failed" -ForegroundColor Red
            return
        }
        Write-Host "✅ Commit created" -ForegroundColor Green

        git push
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Quick commit completed and pushed to '$branch'!" -ForegroundColor Green
        } else {
            Write-Host "❌ git push failed" -ForegroundColor Red
        }
        Write-Host ""
        return
    }

    # Default to standard git-a workflow
    git-a
}

# Add shorthand aliases with consistent naming
function git-aa { git-a-plus -Quick }      # Quick version
function git-ad { git-a-plus -DryRun }     # Dry run version  
function git-am { git-a-plus -AmendLast }  # Amend last commit
# Add shorthand aliases
function git-aq { git-a-plus -Quick }      # Quick version
function git-ad { git-a-plus -DryRun }     # Dry run version
function git-am { git-a-plus -AmendLast }  # Amend last commit

<#
.SYNOPSIS
    Configure Scoop package manager PATH if not already present
.DESCRIPTION
    Ensures Scoop's shims directory is in the PATH for access to installed packages.
    Only adds to PATH if not already present to avoid duplicates.
#>
if (-not ($env:PATH -like "*scoop*")) {
    $env:SCOOP = "$env:USERPROFILE\\scoop"
    $env:PATH += ";$env:SCOOP\\shims"
    Write-Verbose "🛠 Scoop PATH configured: $env:SCOOP\\shims"
}

<#
.SYNOPSIS
    Initialize Starship cross-shell prompt
.DESCRIPTION
    Starship provides a fast, customizable prompt with Git integration,
    language detection, and beautiful theming capabilities.
#>
Invoke-Expression (&starship init powershell)

<#
.SYNOPSIS
    Initialize Zoxide smart directory navigation with fuzzy search support
.DESCRIPTION
    Zoxide learns your directory usage patterns and provides intelligent
    navigation. Includes custom 'nav' function with interactive fuzzy search.
#>
$zoxideInit = &zoxide init --hook prompt powershell
Invoke-Expression ($zoxideInit -join "`n")

# Remove default 'z' alias to use our enhanced version
if (Test-Path Alias:\\z) { Remove-Item Alias:\\z -Force }

<#
.SYNOPSIS
    Auto-navigate to Code directory when starting from HOME
.DESCRIPTION
    Productivity enhancement: automatically moves to ~/Code directory
    when PowerShell starts from the user's home directory.
#>
if ((Get-Location).Path -eq $HOME) {
    Set-Location "$HOME\\Code"
    Write-Host "🏠 Auto-navigated to ~/Code" -ForegroundColor DarkGray
}


# ============================================================================
# ENHANCED SMART NAVIGATION SYSTEM WITH FIXED PROJECT SEARCH
# ============================================================================

<#
.SYNOPSIS
    Enhanced directory navigation with intelligent path resolution, persistent bookmarks, and project search
.DESCRIPTION
    Smart cd that handles relative paths, bookmarks, history, fuzzy search, and intelligent project search.
    Supports advanced patterns like ../path, ../../path, bookmark shortcuts, and automatic project discovery.
    Bookmarks are persistent across sessions. Now includes smart project search within ~/Code directory.
.PARAMETER path
    Directory path, bookmark name, project name, or navigation pattern
.PARAMETER save
    Bookmark current directory with specified name (alias: -s)
.PARAMETER list
    List all bookmarks (alias: -l)
.PARAMETER open
    Navigate to bookmark with specified name (alias: -o)
.PARAMETER recent
    Show recent directories
.PARAMETER root
    Navigate to Git/project root
.PARAMETER projects
    List all discoverable projects in ~/Code directory
.PARAMETER debug
    Enable debug output to troubleshoot search issues
.EXAMPLE
    nav                    # Interactive fuzzy directory picker
    nav docs              # Navigate to docs (zoxide smart search)
    nav chess-guru        # Smart project search in ~/Code subdirectories
    nav chess-guru -debug # Debug the search process
    nav ../src            # Go up one level then into src
    nav @home             # Jump to bookmarked location
    nav --save work       # Bookmark current directory as 'work'
    nav -s work           # Shorthand: bookmark current directory as 'work'  
    nav --list            # List all bookmarks
    nav -l                # Shorthand: list all bookmarks
    nav -o work           # Navigate to 'work' bookmark
    nav --projects        # List all discoverable projects in ~/Code
    nav projects          # Navigate to ~/Code/Projects
#>
# ============================================================================
# WORKING ENHANCED SMART NAVIGATION SYSTEM
# ============================================================================


$script:BookmarkFile = "$env:USERPROFILE\.nav_bookmarks.json"

function Initialize-DefaultBookmarks {
    $defaultBookmarks = @{
        "code" = "$HOME\Code"
        "documents" = "$HOME\Documents"
        "docs" = "$HOME\Documents"
        "pictures" = "$HOME\Pictures"
        "pics" = "$HOME\Pictures"
        "downloads" = "$HOME\Downloads"
        "download" = "$HOME\Downloads"
        "videos" = "$HOME\Videos"
    }
    
    # Only create if file doesn't exist
    if (-not (Test-Path $script:BookmarkFile)) {
        $defaultBookmarks | ConvertTo-Json | Set-Content $script:BookmarkFile
        Write-Host "📚 Initialized default bookmarks" -ForegroundColor Green
    }
}

function Get-Bookmarks {
    Initialize-DefaultBookmarks
    
    if (Test-Path $script:BookmarkFile) {
        try {
            return Get-Content $script:BookmarkFile | ConvertFrom-Json -AsHashtable
        } catch {
            Write-Host "❌ Error reading bookmarks: $($_.Exception.Message)" -ForegroundColor Red
            return @{}
        }
    }
    return @{}
}

function Save-Bookmarks {
    param([hashtable]$bookmarks)
    
    try {
        $bookmarks | ConvertTo-Json | Set-Content $script:BookmarkFile
        return $true
    } catch {
        Write-Host "❌ Error saving bookmarks: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Add-Bookmark {
    param(
        [string]$name,
        [string]$path = $PWD.Path
    )
    
    if (-not $name) {
        Write-Host "❌ Error: Bookmark name is required" -ForegroundColor Red
        Write-Host "💡 Usage: nav create-b <name> or nav cb <name>" -ForegroundColor DarkGray
        return
    }
    
    if (-not (Test-Path $path)) {
        Write-Host "❌ Error: Path does not exist: $path" -ForegroundColor Red
        return
    }
    
    $bookmarks = Get-Bookmarks
    $bookmarks[$name.ToLower()] = $path
    
    if (Save-Bookmarks $bookmarks) {
        Write-Host "📌 Bookmark '$name' created → $path" -ForegroundColor Green
    }
}

function Remove-Bookmark {
    param([string]$name)
    
    if (-not $name) {
        Write-Host "❌ Error: Bookmark name is required" -ForegroundColor Red
        Write-Host "💡 Usage: nav delete-b <name> or nav db <name>" -ForegroundColor DarkGray
        return
    }
    
    $bookmarks = Get-Bookmarks
    $lowerName = $name.ToLower()
    
    if (-not $bookmarks.ContainsKey($lowerName)) {
        Write-Host "❌ Bookmark '$name' not found" -ForegroundColor Red
        return
    }
    
    # Confirmation prompt
    Write-Host "🗑️  Delete bookmark '$name' → $($bookmarks[$lowerName])?" -ForegroundColor Yellow
    $confirmation = Read-Host "Confirm (y/n)"
    
    if ($confirmation -eq 'y' -or $confirmation -eq 'Y') {
        $bookmarks.Remove($lowerName)
        if (Save-Bookmarks $bookmarks) {
            Write-Host "✅ Bookmark '$name' deleted" -ForegroundColor Green
        }
    } else {
        Write-Host "❌ Deletion cancelled" -ForegroundColor Yellow
    }
}

function Rename-Bookmark {
    param(
        [string]$oldName,
        [string]$newName
    )
    
    if (-not $oldName -or -not $newName) {
        Write-Host "❌ Error: Both old and new bookmark names are required" -ForegroundColor Red
        Write-Host "💡 Usage: nav rename-b <oldname> <newname> or nav rb <oldname> <newname>" -ForegroundColor DarkGray
        return
    }
    
    $bookmarks = Get-Bookmarks
    $lowerOldName = $oldName.ToLower()
    $lowerNewName = $newName.ToLower()
    
    if (-not $bookmarks.ContainsKey($lowerOldName)) {
        Write-Host "❌ Bookmark '$oldName' not found" -ForegroundColor Red
        return
    }
    
    if ($bookmarks.ContainsKey($lowerNewName)) {
        Write-Host "❌ Bookmark '$newName' already exists" -ForegroundColor Red
        return
    }
    
    $path = $bookmarks[$lowerOldName]
    $bookmarks.Remove($lowerOldName)
    $bookmarks[$lowerNewName] = $path
    
    if (Save-Bookmarks $bookmarks) {
        Write-Host "📝 Bookmark renamed: '$oldName' → '$newName'" -ForegroundColor Green
    }
}

function Show-BookmarkList {
    $bookmarks = Get-Bookmarks
    
    if ($bookmarks.Count -eq 0) {
        Write-Host "📚 No bookmarks found" -ForegroundColor Yellow
        return
    }
    
    Write-Host "📚 Available Bookmarks:" -ForegroundColor Cyan
    Write-Host "═══════════════════════" -ForegroundColor Cyan
    
    $sortedBookmarks = $bookmarks.GetEnumerator() | Sort-Object Key
    $index = 0
    $bookmarkArray = @()
    
    foreach ($bookmark in $sortedBookmarks) {
        $bookmarkArray += @{Name = $bookmark.Key; Path = $bookmark.Value}
        $status = if (Test-Path $bookmark.Value) { "✅" } else { "❌" }
        Write-Host "$($index + 1). $status $($bookmark.Key) → $($bookmark.Value)" -ForegroundColor $(if (Test-Path $bookmark.Value) { "Green" } else { "Red" })
        $index++
    }
    
    Write-Host "`n💡 Actions:" -ForegroundColor DarkGray
    Write-Host "   Enter number to navigate | 'c <name>' to create | 'd <name>' to delete | 'r <old> <new>' to rename | 'q' to quit" -ForegroundColor DarkGray
    
    while ($true) {
        $input = Read-Host "`nChoice"
        
        if ($input -eq 'q') {
            break
        }
        
        # Handle navigation by number
        if ($input -match '^\d+$') {
            $choice = [int]$input - 1
            if ($choice -ge 0 -and $choice -lt $bookmarkArray.Count) {
                $selectedBookmark = $bookmarkArray[$choice]
                if (Test-Path $selectedBookmark.Path) {
                    Set-Location $selectedBookmark.Path
                    Write-Host "📍 Navigated to: $($selectedBookmark.Name)" -ForegroundColor Green
                    break
                } else {
                    Write-Host "❌ Path no longer exists: $($selectedBookmark.Path)" -ForegroundColor Red
                }
            } else {
                Write-Host "❌ Invalid choice. Please enter a number between 1 and $($bookmarkArray.Count)" -ForegroundColor Red
            }
        }
        # Handle quick actions
        elseif ($input -match '^c\s+(.+)$') {
            Add-Bookmark $matches[1]
        }
        elseif ($input -match '^d\s+(.+)$') {
            Remove-Bookmark $matches[1]
        }
        elseif ($input -match '^r\s+(\S+)\s+(\S+)$') {
            Rename-Bookmark $matches[1] $matches[2]
        }
        else {
            Write-Host "❌ Invalid input. Try again or 'q' to quit." -ForegroundColor Red
        }
    }
}

function Search-NestedProjects {
    param(
        [string]$projectName,
        [string]$baseDir,
        [switch]$verbose
    )
    
    if ($verbose) { Write-Host "🔍 Starting nested search for '$projectName' in: $baseDir" -ForegroundColor Magenta }
    
    if (-not (Test-Path $baseDir)) {
        if ($verbose) { Write-Host "❌ Base directory not found: $baseDir" -ForegroundColor Red }
        return $null
    }
    
    # Convert search term for parent folder matching (chess-guru -> chess guru)
    $parentSearchTerm = $projectName -replace '-', ' '
    if ($verbose) { Write-Host "🔄 Parent search term: '$parentSearchTerm'" -ForegroundColor Yellow }
    
    try {
        $subDirs = Get-ChildItem -LiteralPath $baseDir -Directory -Force
        
        foreach ($subDir in $subDirs) {
            if ($verbose) { Write-Host "  📂 Checking: $($subDir.Name)" -ForegroundColor Gray }
            
            # Check if this subdirectory name matches our parent search term
            $isParentMatch = ($subDir.Name -like "*$parentSearchTerm*") -or ($subDir.Name -eq $parentSearchTerm)
            
            if ($isParentMatch) {
                if ($verbose) { Write-Host "  ⚡ Found potential parent: $($subDir.Name)" -ForegroundColor Green }
                
                # Look inside this subdirectory for the actual project
                try {
                    $innerDirs = Get-ChildItem -LiteralPath $subDir.FullName -Directory -Force
                    
                    foreach ($innerDir in $innerDirs) {
                        if ($verbose) { Write-Host "    🔍 Inner dir: $($innerDir.Name)" -ForegroundColor Cyan }
                        
                        # Check for exact match first
                        if ($innerDir.Name -eq $projectName) {
                            if ($verbose) { Write-Host "    ⭐ EXACT MATCH FOUND!" -ForegroundColor Green }
                            return $innerDir.FullName
                        }
                        
                        # Check for fuzzy match
                        if ($innerDir.Name -like "*$projectName*") {
                            if ($verbose) { Write-Host "    ⚡ FUZZY MATCH FOUND!" -ForegroundColor Green }
                            return $innerDir.FullName
                        }
                    }
                } catch {
                    if ($verbose) { Write-Host "    ❌ Could not access inner directories: $($_.Exception.Message)" -ForegroundColor Red }
                }
            }
            
            # Also check if we should recursively search this directory (for deeper nesting)
            try {
                $deeperDirs = Get-ChildItem -LiteralPath $subDir.FullName -Directory -Force
                
                foreach ($deeperDir in $deeperDirs) {
                    # Check if this deeper directory matches our parent search term
                    if ($deeperDir.Name -like "*$parentSearchTerm*" -or $deeperDir.Name -eq $parentSearchTerm) {
                        if ($verbose) { Write-Host "  🔎 Found deeper parent: $($subDir.Name)\$($deeperDir.Name)" -ForegroundColor Blue }
                        
                        # Look inside this deeper directory
                        try {
                            $deepestDirs = Get-ChildItem -LiteralPath $deeperDir.FullName -Directory -Force
                            
                            foreach ($deepestDir in $deepestDirs) {
                                if ($verbose) { Write-Host "    🔍 Deepest dir: $($deepestDir.Name)" -ForegroundColor Cyan }
                                
                                # Check for exact match
                                if ($deepestDir.Name -eq $projectName) {
                                    if ($verbose) { Write-Host "    ⭐ DEEP EXACT MATCH FOUND!" -ForegroundColor Green }
                                    return $deepestDir.FullName
                                }
                                
                                # Check for fuzzy match
                                if ($deepestDir.Name -like "*$projectName*") {
                                    if ($verbose) { Write-Host "    ⚡ DEEP FUZZY MATCH FOUND!" -ForegroundColor Green }
                                    return $deepestDir.FullName
                                }
                            }
                        } catch {
                            if ($verbose) { Write-Host "    ❌ Could not access deepest directories: $($_.Exception.Message)" -ForegroundColor Red }
                        }
                    }
                }
            } catch {
                # Silent fail for deeper search - this is optional
            }
        }
    } catch {
        if ($verbose) { Write-Host "❌ Error searching nested projects: $($_.Exception.Message)" -ForegroundColor Red }
    }
    
    return $null
}

function nav {
    param(
        [string]$command = $null,
        [string]$param1 = $null,
        [string]$param2 = $null,
        [switch]$verbose
    )
    
    # Initialize bookmarks on first run
    Initialize-DefaultBookmarks
    
    # If no command provided, show help
    if (-not $command) {
        Write-Host "💡 Navigation Commands:" -ForegroundColor Cyan
        Write-Host "═════════════════════" -ForegroundColor Cyan
        Write-Host "  nav <project-name>           Navigate to project" -ForegroundColor DarkGray
        Write-Host "  nav b <bookmark>             Navigate to bookmark" -ForegroundColor DarkGray
        Write-Host "  nav create-b <name> | cb     Create bookmark (current dir)" -ForegroundColor DarkGray
        Write-Host "  nav delete-b <name> | db     Delete bookmark" -ForegroundColor DarkGray
        Write-Host "  nav rename-b <old> <new>     Rename bookmark" -ForegroundColor DarkGray
        Write-Host "  nav list | l                 Show interactive bookmark list" -ForegroundColor DarkGray
        Write-Host "  Use -verbose for detailed output" -ForegroundColor DarkGray
        return
    }
    
    if ($verbose) {
        Write-Host "=== NAV FUNCTION ===" -ForegroundColor Cyan
        Write-Host "Command: '$command'" -ForegroundColor Yellow
        Write-Host "Param1: '$param1'" -ForegroundColor Yellow
        Write-Host "Param2: '$param2'" -ForegroundColor Yellow
    }
    
    # Handle bookmark management commands
    switch ($command) {
        { $_ -in @("create-b", "cb") } {
            Add-Bookmark $param1
            return
        }
        { $_ -in @("delete-b", "db") } {
            Remove-Bookmark $param1
            return
        }
        { $_ -in @("rename-b", "rb") } {
            Rename-Bookmark $param1 $param2
            return
        }
        { $_ -in @("list", "l") } {
            Show-BookmarkList
            return
        }
    }
    
    # Handle bookmark navigation (nav b <bookmark>)
    if ($command -eq "b") {
        if (-not $param1) {
            Write-Host "❌ Error: Bookmark name is required" -ForegroundColor Red
            Write-Host "💡 Usage: nav b <bookmark-name>" -ForegroundColor DarkGray
            return
        }
        
        $bookmarks = Get-Bookmarks
        $bookmarkName = $param1.ToLower()
        
        if ($bookmarks.ContainsKey($bookmarkName)) {
            $bookmarkPath = $bookmarks[$bookmarkName]
            if (Test-Path $bookmarkPath) {
                Set-Location $bookmarkPath
                Write-Host "📌 Navigated to bookmark: $param1" -ForegroundColor Green
                Write-Host "📍 Location: $bookmarkPath" -ForegroundColor Cyan
                return
            } else {
                Write-Host "❌ Bookmark path no longer exists: $bookmarkPath" -ForegroundColor Red
                Write-Host "💡 Use 'nav delete-b $param1' to remove invalid bookmark" -ForegroundColor DarkGray
                return
            }
        } else {
            Write-Host "❌ Bookmark '$param1' not found" -ForegroundColor Red
            Write-Host "💡 Use 'nav list' to see available bookmarks" -ForegroundColor DarkGray
            return
        }
    }
    
    # === RESTORED WORKING SEARCH LOGIC FROM ORIGINAL ===
    
    # For project search, determine the search directory
# For project search, determine the search directory
$currentPath = $PWD.Path
$searchDir = $currentPath  # Always start with current directory

# Check if we're in a bookmarked location (for context, but don't change search directory)
$bookmarks = Get-Bookmarks
$isInBookmarkedLocation = $false
$parentBookmark = $null

foreach ($bookmark in $bookmarks.GetEnumerator()) {
    if ($currentPath.StartsWith($bookmark.Value, [StringComparison]::OrdinalIgnoreCase)) {
        $isInBookmarkedLocation = $true
        $parentBookmark = $bookmark.Value
        # FIXED: Don't change $searchDir - keep current directory!
        break
    }
}

# Only default to Code bookmark if we're in a completely unrelated location
if (-not $isInBookmarkedLocation) {
    $searchDir = $bookmarks["code"]  # Default to Code bookmark only if not in any bookmark location
    if ($verbose) { Write-Host "Not in bookmarked location, defaulting to Code directory" -ForegroundColor Yellow }
} else {
    if ($verbose) { Write-Host "In bookmarked location ($parentBookmark), searching from current directory: $currentPath" -ForegroundColor Green }
}
    
    $path = $command  # The project name to search for
    
    # Handle special shortcuts first
    switch ($path) {
        "~" { 
            Set-Location $HOME
            Write-Host "🏠 Navigated to Home" -ForegroundColor Cyan
            return
        }
        "code" {
            Set-Location "$HOME\Code"
            Write-Host "💻 Navigated to Code" -ForegroundColor Cyan
            return
        }
        "projects" {
            Set-Location "$HOME\Code\Projects"
            Write-Host "📂 Navigated to Projects" -ForegroundColor Cyan
            return
        }
    }
    
    # Try direct path first
    if (Test-Path $path -PathType Container) {
        Set-Location $path
        Write-Host "📁 Navigated to: $path" -ForegroundColor Green
        return
    }
    
    # === CORE SEARCH LOGIC - Based on working original function ===
    
    if ($verbose) {
        Write-Host "Search directory: $searchDir" -ForegroundColor Green
        Write-Host "Search directory exists: $(Test-Path $searchDir)" -ForegroundColor Green
    }
    
    if (-not (Test-Path $searchDir)) {
        Write-Host "❌ Search directory not found!" -ForegroundColor Red
        return
    }
    
    # First, check top-level directories in search location
    if ($verbose) { Write-Host "`nListing top-level directories in ${searchDir}:" -ForegroundColor Cyan }
    try {
        $topDirs = Get-ChildItem -LiteralPath $searchDir -Directory -Force
        
        if ($verbose) {
            $topDirs | ForEach-Object {
                Write-Host "  📁 $($_.Name)" -ForegroundColor Green
            }
        }
        
        # Check for direct matches in top-level directories
        foreach ($topDir in $topDirs) {
            if ($topDir.Name -eq $path) {
                Set-Location $topDir.FullName
                Write-Host "🎯 Found project: $path" -ForegroundColor Green
                return
            }
            if ($topDir.Name -like "*$path*") {
                Set-Location $topDir.FullName
                Write-Host "🎯 Found similar project: $($topDir.Name)" -ForegroundColor Green
                Write-Host "💡 Searched for: $path" -ForegroundColor DarkGray
                return
            }
        }
    } catch {
        Write-Host "❌ Error listing directories: $($_.Exception.Message)" -ForegroundColor Red
        return
    }
    
    # === MAIN SEARCH LOGIC - Search in Projects folder (if we're in Code) ===
    if ($searchDir -eq $bookmarks["code"]) {
        if ($verbose) { Write-Host "`nSearching for '$path' in Projects folder:" -ForegroundColor Cyan }
        
        $projectsDir = "$searchDir\Projects"
        if (Test-Path $projectsDir) {
            if ($verbose) { Write-Host "Projects directory exists: ✅" -ForegroundColor Green }
            
            try {
                $projectSubDirs = Get-ChildItem -LiteralPath $projectsDir -Directory -Force
                if ($verbose) { Write-Host "Found $($projectSubDirs.Count) subdirectories in Projects:" -ForegroundColor Yellow }
                
                # Go through each subdirectory in Projects
                foreach ($subDir in $projectSubDirs) {
                    if ($verbose) { Write-Host "  📂 $($subDir.Name)" -ForegroundColor Cyan }
                    
                    # Check if this folder contains the target project
                    $subPath = $subDir.FullName
                    try {
                        $innerDirs = Get-ChildItem -LiteralPath $subPath -Directory -Force
                        
                        foreach ($innerDir in $innerDirs) {
                            # Check for EXACT MATCH first
                            if ($innerDir.Name -eq $path) {
                                Set-Location $innerDir.FullName
                                Write-Host "🎯 Found project: $path in $($subDir.Name)" -ForegroundColor Green
                                return
                            }
                            
                            if ($verbose) {
                                $match = if ($innerDir.Name -eq $path) { " ⭐ EXACT MATCH!" } 
                                        elseif ($innerDir.Name -like "*$path*") { " ⚡ FUZZY MATCH!" } 
                                        else { "" }
                                Write-Host "    💼 $($innerDir.Name)$match" -ForegroundColor $(if ($match) { "Green" } else { "Gray" })
                            }
                        }
                        
                        # If no exact match found, check for FUZZY MATCHES
                        foreach ($innerDir in $innerDirs) {
                            if ($innerDir.Name -like "*$path*") {
                                Set-Location $innerDir.FullName
                                Write-Host "🎯 Found similar project: $($innerDir.Name) in $($subDir.Name)" -ForegroundColor Green
                                Write-Host "💡 Searched for: $path" -ForegroundColor DarkGray
                                return
                            }
                        }
                        
                    } catch {
                        if ($verbose) { Write-Host "    ❌ Could not access: $($_.Exception.Message)" -ForegroundColor Red }
                    }
                }
            } catch {
                Write-Host "❌ Error accessing Projects directory: $($_.Exception.Message)" -ForegroundColor Red
                return
            }
        } else {
            if ($verbose) { Write-Host "Projects directory not found: ❌" -ForegroundColor Red }
        }
        
        # === NESTED SEARCH in Projects folder ===
        if ($verbose) { Write-Host "`n🔍 Trying nested search in Projects..." -ForegroundColor Magenta }
        
        $nestedResult = Search-NestedProjects -projectName $path -baseDir $projectsDir -verbose:$verbose
        if ($nestedResult) {
            Set-Location $nestedResult
            $relativePath = $nestedResult.Replace("$projectsDir\", "")
            Write-Host "🎯 Found nested project: $path" -ForegroundColor Green
            Write-Host "📍 Location: Projects\$relativePath" -ForegroundColor Cyan
            return
        }
        
        # Search in other top-level directories (Applications, Learning Area, etc.)
        if ($verbose) { Write-Host "`nSearching in other top-level directories:" -ForegroundColor Cyan }
        
        $otherSearchDirs = @("Applications", "Learning Area", "React Native", "Deblotter", "pass-book")
        
        foreach ($dirName in $otherSearchDirs) {
            $otherSearchDir = "$searchDir\$dirName"
            if (Test-Path $otherSearchDir) {
                if ($verbose) { Write-Host "Searching in $dirName..." -ForegroundColor Cyan }
                
                try {
                    $subDirs = Get-ChildItem -LiteralPath $otherSearchDir -Directory -Force
                    
                    # Check for exact matches first
                    foreach ($subDir in $subDirs) {
                        if ($subDir.Name -eq $path) {
                            Set-Location $subDir.FullName
                            Write-Host "🎯 Found project: $path in $dirName" -ForegroundColor Green
                            return
                        }
                    }
                    
                    # Then check for fuzzy matches
                    foreach ($subDir in $subDirs) {
                        if ($subDir.Name -like "*$path*") {
                            Set-Location $subDir.FullName
                            Write-Host "🎯 Found similar project: $($subDir.Name) in $dirName" -ForegroundColor Green
                            Write-Host "💡 Searched for: $path" -ForegroundColor DarkGray
                            return
                        }
                    }
                } catch {
                    if ($verbose) { Write-Host "❌ Error accessing ${dirName}: $($_.Exception.Message)" -ForegroundColor Red }
                }
                
                # === NESTED SEARCH in other directories too ===
                if ($verbose) { Write-Host "🔍 Trying nested search in $dirName..." -ForegroundColor Magenta }
                
                $nestedResult = Search-NestedProjects -projectName $path -baseDir $otherSearchDir -verbose:$verbose
                if ($nestedResult) {
                    Set-Location $nestedResult
                    $relativePath = $nestedResult.Replace("$otherSearchDir\", "")
                    Write-Host "🎯 Found nested project: $path in $dirName" -ForegroundColor Green
                    Write-Host "📍 Location: $dirName\$relativePath" -ForegroundColor Cyan
                    return
                }
            }
        }
    } else {
        # === SEARCH LOGIC FOR NON-CODE BOOKMARKS ===
        if ($verbose) { Write-Host "`nSearching for '$path' in current bookmark location:" -ForegroundColor Cyan }
        
        try {
            $subDirs = Get-ChildItem -LiteralPath $searchDir -Directory -Force
            if ($verbose) { Write-Host "Found $($subDirs.Count) subdirectories:" -ForegroundColor Yellow }
            
            # Check for exact matches first
            foreach ($subDir in $subDirs) {
                if ($subDir.Name -eq $path) {
                    Set-Location $subDir.FullName
                    Write-Host "🎯 Found project: $path" -ForegroundColor Green
                    return
                }
            }
            
            # Then check for fuzzy matches
            foreach ($subDir in $subDirs) {
                if ($subDir.Name -like "*$path*") {
                    Set-Location $subDir.FullName
                    Write-Host "🎯 Found similar project: $($subDir.Name)" -ForegroundColor Green
                    Write-Host "💡 Searched for: $path" -ForegroundColor DarkGray
                    return
                }
            }
            
            # Try nested search in non-Code locations too
            if ($verbose) { Write-Host "`n🔍 Trying nested search..." -ForegroundColor Magenta }
            
            $nestedResult = Search-NestedProjects -projectName $path -baseDir $searchDir -verbose:$verbose
            if ($nestedResult) {
                Set-Location $nestedResult
                $relativePath = $nestedResult.Replace("$searchDir\", "")
                Write-Host "🎯 Found nested project: $path" -ForegroundColor Green
                Write-Host "📍 Location: $relativePath" -ForegroundColor Cyan
                return
            }
            
        } catch {
            Write-Host "❌ Error accessing directory: $($_.Exception.Message)" -ForegroundColor Red
            return
        }
    }
    
    # If we get here, nothing was found
    Write-Host "❌ No matches found for: $path" -ForegroundColor Red
    Write-Host "💡 Searched in: $searchDir" -ForegroundColor DarkGray
    if ($searchDir -eq $bookmarks["code"]) {
        Write-Host "💡 Searched areas:" -ForegroundColor DarkGray
        Write-Host "   • Top-level Code directories" -ForegroundColor DarkGray
        Write-Host "   • Projects subdirectories (including nested)" -ForegroundColor DarkGray
        Write-Host "   • Applications, Learning Area, React Native, etc. (including nested)" -ForegroundColor DarkGray
    }
    Write-Host "💡 Use 'nav $path -verbose' for detailed search output" -ForegroundColor DarkGray
    Write-Host "💡 Use 'nav b <bookmark>' to search in a different location" -ForegroundColor DarkGray
}

# For testing - keep your original test function available
function Test-NavFunction {
    param(
        [string]$path = $null,
        [switch]$debug
    )
    
    Write-Host "=== NAV FUNCTION DEBUG TEST ===" -ForegroundColor Cyan
    Write-Host "Path parameter: '$path'" -ForegroundColor Yellow
    Write-Host "Debug flag: $debug" -ForegroundColor Yellow
    Write-Host "All parameters: $($PSBoundParameters | Out-String)" -ForegroundColor Yellow
    
    # Test bookmarks
    Write-Host "`n=== TESTING BOOKMARKS ===" -ForegroundColor Magenta
    $bookmarks = Get-Bookmarks
    Write-Host "Available bookmarks:" -ForegroundColor Green
    $bookmarks.GetEnumerator() | Sort-Object Key | ForEach-Object {
        $status = if (Test-Path $_.Value) { "✅" } else { "❌" }
        Write-Host "  $status $($_.Key) → $($_.Value)" -ForegroundColor $(if (Test-Path $_.Value) { "Green" } else { "Red" })
    }
    
    # Test the nested search if path provided
    if ($path) {
        Write-Host "`n=== TESTING NESTED SEARCH ===" -ForegroundColor Magenta
        $codeDir = "$HOME\Code"
        $projectsDir = "$codeDir\Projects"
        $nestedResult = Search-NestedProjects -projectName $path -baseDir $projectsDir -verbose
        if ($nestedResult) {
            Write-Host "✅ Nested search found: $nestedResult" -ForegroundColor Green
        } else {
            Write-Host "❌ Nested search found nothing" -ForegroundColor Red
        }
    }
}


# ============================================================================
# ENHANCED DIRECTORY INFO
# ============================================================================

<#
.SYNOPSIS
    Show detailed information about current directory
.EXAMPLE
    here    # Show current directory info
#>
function here {
    $location = Get-Location
    $items = Get-ChildItem -Force
    $dirs = $items | Where-Object { $_.PSIsContainer }
    $files = $items | Where-Object { -not $_.PSIsContainer }
    $size = ($files | Measure-Object -Property Length -Sum).Sum
    
    Write-Host "`n📍 Current Location Info:" -ForegroundColor Cyan
    Write-Host "  📁 Path: $($location.Path)" -ForegroundColor Green
    Write-Host "  📊 Contents: $($dirs.Count) directories, $($files.Count) files" -ForegroundColor Green
    Write-Host "  💾 Total Size: $([math]::Round($size / 1MB, 2)) MB" -ForegroundColor Green
    
    # Show Git info if in repository
    $gitBranch = git rev-parse --abbrev-ref HEAD 2>$null
    if ($gitBranch) {
        Write-Host "  🌳 Git Branch: $gitBranch" -ForegroundColor Green
    }
    
    # Show project type
    if (Test-Path "package.json") { Write-Host "  📦 Node.js Project" -ForegroundColor Yellow }
    if (Test-Path "Cargo.toml") { Write-Host "  🦀 Rust Project" -ForegroundColor Yellow }
    if (Test-Path "requirements.txt") { Write-Host "  🐍 Python Project" -ForegroundColor Yellow }
    if (Test-Path "go.mod") { Write-Host "  🐹 Go Project" -ForegroundColor Yellow }
}

# ============================================================================
# NAVIGATION ALIASES & SHORTCUTS
# ============================================================================

# Core navigation aliases
Set-Alias z nav                    # Main navigation function
# Set-Alias cd nav                   # Override cd with enhanced navigation

# ============================================================================
# FAST PARENT DIRECTORY SHORTCUTS (Keep for Speed!)
# ============================================================================









# Enhanced dot navigation functions that support directory names
# Replace your existing .., ..., .... functions with these enhanced versions

<#
.SYNOPSIS
    Enhanced parent directory navigation with optional target directory
.DESCRIPTION
    Go up one level, optionally followed by navigating to a target directory
.PARAMETER targetDir
    Optional directory name to navigate to after going up
.EXAMPLE
    ..                 # Go up one level (original behavior)
    .. management      # Go up one level, then into management
    .. "Web Apps"      # Go up one level, then into "Web Apps" (with spaces)
#>
function .. {
    param(
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$targetDirParts
    )
    
    # Go up one level first
    Set-Location ..
    
    # If a target directory was specified, navigate to it
    if ($targetDirParts) {
        $targetDir = $targetDirParts -join ' '
        Write-Host "🔍 Going up 1 level → '$targetDir'" -ForegroundColor DarkGray
        
        # Store current location before nav attempt
        $beforeNav = Get-Location
        nav $targetDir
        $afterNav = Get-Location
        
        # If nav didn't change location (failed), show current directory listing
        if ($beforeNav.Path -eq $afterNav.Path) {
            Write-Host "`n📁 Current directory contents:" -ForegroundColor Cyan
            ls
        }
    }
}

<#
.SYNOPSIS
    Enhanced parent directory navigation - go up two levels with optional target
.DESCRIPTION
    Go up two levels, optionally followed by navigating to a target directory
.PARAMETER targetDir
    Optional directory name to navigate to after going up
.EXAMPLE
    ...                # Go up two levels (original behavior)
    ... projects       # Go up two levels, then into projects
    ... "My Folder"    # Go up two levels, then into "My Folder" (with spaces)
#>
function ... {
    param(
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$targetDirParts
    )
    
    # Go up two levels first
    Set-Location ../..
    
    # If a target directory was specified, navigate to it
    if ($targetDirParts) {
        $targetDir = $targetDirParts -join ' '
        Write-Host "🔍 Going up 2 levels → '$targetDir'" -ForegroundColor DarkGray
        
        # Store current location before nav attempt
        $beforeNav = Get-Location
        nav $targetDir
        $afterNav = Get-Location
        
        # If nav didn't change location (failed), show current directory listing
        if ($beforeNav.Path -eq $afterNav.Path) {
            Write-Host "`n📁 Current directory contents:" -ForegroundColor Cyan
            ls
        }
    }
}

<#
.SYNOPSIS
    Enhanced parent directory navigation - go up three levels with optional target
.DESCRIPTION
    Go up three levels, optionally followed by navigating to a target directory
.PARAMETER targetDir
    Optional directory name to navigate to after going up
.EXAMPLE
    ....               # Go up three levels (original behavior)
    .... code          # Go up three levels, then into code
    .... "My Project"  # Go up three levels, then into "My Project" (with spaces)
#>
function .... {
    param(
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$targetDirParts
    )
    
    # Go up three levels first
    Set-Location ../../..
    
    # If a target directory was specified, navigate to it
    if ($targetDirParts) {
        $targetDir = $targetDirParts -join ' '
        Write-Host "🔍 Going up 3 levels → '$targetDir'" -ForegroundColor DarkGray
        
        # Store current location before nav attempt
        $beforeNav = Get-Location
        nav $targetDir
        $afterNav = Get-Location
        
        # If nav didn't change location (failed), show current directory listing
        if ($beforeNav.Path -eq $afterNav.Path) {
            Write-Host "`n📁 Current directory contents:" -ForegroundColor Cyan
            ls
        }
    }
}

<#
.SYNOPSIS
    Enhanced parent directory navigation - go up four levels with optional target
.DESCRIPTION
    Go up four levels, optionally followed by navigating to a target directory
.PARAMETER targetDir
    Optional directory name to navigate to after going up
.EXAMPLE
    .....              # Go up four levels
    ..... documents    # Go up four levels, then into documents
#>
function ..... {
    param(
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$targetDirParts
    )
    
    # Go up four levels first
    Set-Location ../../../..
    
    # If a target directory was specified, navigate to it
    if ($targetDirParts) {
        $targetDir = $targetDirParts -join ' '
        Write-Host "🔍 Going up 4 levels → '$targetDir'" -ForegroundColor DarkGray
        
        # Store current location before nav attempt
        $beforeNav = Get-Location
        nav $targetDir
        $afterNav = Get-Location
        
        # If nav didn't change location (failed), show current directory listing
        if ($beforeNav.Path -eq $afterNav.Path) {
            Write-Host "`n📁 Current directory contents:" -ForegroundColor Cyan
            ls
        }
    }
}

# Keep your existing home directory function unchanged
function ~ { Set-Location $HOME }











# Additional useful aliases
Set-Alias pwd Get-Location         # Print working directory

<#
.SYNOPSIS
    Navigate to previous directory (like cd - in bash)
.EXAMPLE
    back    # Go to previous directory
    cd-     # Alternative syntax
#>
function back {
    if ($global:NAV_HISTORY -and $global:NAV_HISTORY.Count -ge 2) {
        $previousPath = $global:NAV_HISTORY[-2]
        Set-Location $previousPath
        Write-Host "🔙 Navigated back to: $previousPath" -ForegroundColor Yellow
    } else {
        Write-Host "❌ No previous directory in history" -ForegroundColor Red
    }
}

Set-Alias cd- back              # Traditional cd- syntax

function copy-pwd {
    $path = (Get-Location).Path
    Set-Clipboard -Value $path
    Write-Host "📋 Copied path: $path" -ForegroundColor Green
}




function paste-file {
    param(
        [switch]$Force,
        [string]$Path = (Get-Location).Path
    )
    
    try {
        # Get clipboard content as text (file path stored by copy-file with 'FILE:' prefix)
        $clipboardContent = Get-Clipboard -ErrorAction SilentlyContinue
        
        if (-not $clipboardContent -or -not $clipboardContent.StartsWith('FILE:')) {
            Write-Host "❌ No file found in clipboard" -ForegroundColor Red
            Write-Host "💡 Use 'cf <filename>' to copy a file first" -ForegroundColor DarkGray
            return
        }
        
        # Extract file path (remove 'FILE:' prefix)
        $sourceFile = $clipboardContent.Substring(5)
        
        if (-not (Test-Path $sourceFile)) {
            Write-Host "❌ Source file no longer exists: $sourceFile" -ForegroundColor Red
            return
        }
        
        # Ensure destination directory exists
        if (-not (Test-Path $Path -PathType Container)) {
            Write-Host "❌ Destination directory not found: $Path" -ForegroundColor Red
            return
        }
        
        $fileName = Split-Path $sourceFile -Leaf
        $destinationPath = Join-Path $Path $fileName
        
        # Check if file already exists
        if (Test-Path $destinationPath) {
            # Check if source and destination are the exact same file path
            $resolvedSource = (Resolve-Path $sourceFile).Path
            $resolvedDestination = (Resolve-Path $destinationPath).Path
            
            if ($resolvedSource -eq $resolvedDestination) {
                # Same file path - can only rename, not overwrite
                Write-Host "⚠️  Source and destination are the same file: $fileName" -ForegroundColor Yellow
                Write-Host "   Path: $resolvedSource" -ForegroundColor DarkGray
                
                if (-not $Force) {
                    $choice = Read-Host "Rename the copy? (y/n/r=rename manually)"
                    
                    if ($choice -eq 'r') {
                        $newName = Read-Host "Enter new filename"
                        if (-not $newName) {
                            Write-Host "⏭️  Cancelled" -ForegroundColor Yellow
                            return
                        }
                        $destinationPath = Join-Path $Path $newName
                        $fileName = $newName
                    } elseif ($choice -eq 'y') {
                        # Auto-generate copy name
                        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
                        $extension = [System.IO.Path]::GetExtension($fileName)
                        $counter = 1
                        
                        do {
                            $newFileName = "${baseName} - Copy$(if ($counter -gt 1) { " ($counter)" })${extension}"
                            $destinationPath = Join-Path $Path $newFileName
                            $counter++
                        } while (Test-Path $destinationPath)
                        
                        $fileName = $newFileName
                    } else {
                        Write-Host "⏭️  Cancelled" -ForegroundColor Yellow
                        return
                    }
                } else {
                    # Force mode - auto-rename
                    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
                    $extension = [System.IO.Path]::GetExtension($fileName)
                    $counter = 1
                    
                    do {
                        $newFileName = "${baseName} - Copy$(if ($counter -gt 1) { " ($counter)" })${extension}"
                        $destinationPath = Join-Path $Path $newFileName
                        $counter++
                    } while (Test-Path $destinationPath)
                    
                    $fileName = $newFileName
                }
            } else {
                # Different files with same name - allow overwrite or rename
                if (-not $Force) {
                    Write-Host "⚠️  File already exists: $fileName" -ForegroundColor Yellow
                    Write-Host "   Source: $sourceFile" -ForegroundColor DarkGray
                    Write-Host "   Destination: $destinationPath" -ForegroundColor DarkGray
                    
                    $choice = Read-Host "Overwrite existing file? (y/n/r=rename new file)"
                    
                    if ($choice -eq 'r') {
                        $newName = Read-Host "Enter new filename for the incoming file"
                        if (-not $newName) {
                            Write-Host "⏭️  Cancelled" -ForegroundColor Yellow
                            return
                        }
                        $destinationPath = Join-Path $Path $newName
                        $fileName = $newName
                    } elseif ($choice -ne 'y') {
                        Write-Host "⏭️  Cancelled" -ForegroundColor Yellow
                        return
                    }
                }
                
                # Remove existing file for clean overwrite (only when it's a different file)
                if ((Test-Path $destinationPath) -and ($choice -eq 'y' -or $Force)) {
                    Remove-Item $destinationPath -Force
                }
            }
        }
        
        # Copy the file
        Copy-Item -Path $sourceFile -Destination $destinationPath -Force
        
        $copiedFile = Get-Item $destinationPath
        Write-Host "✅ Pasted: $fileName" -ForegroundColor Green
        Write-Host "   📍 Location: $destinationPath" -ForegroundColor Cyan
        Write-Host "   📊 Size: $([math]::Round($copiedFile.Length / 1KB, 2)) KB" -ForegroundColor Cyan
        
    } catch {
        Write-Host "❌ Error pasting file: $($_.Exception.Message)" -ForegroundColor Red
    }
}



<#
.SYNOPSIS
    Enhanced copy-file function with better clipboard handling
.DESCRIPTION
    Updated version that works better with the paste-file function
#>
function copy-file {
    param(
        [Parameter(Mandatory = $true)]
        [string]$filePath
    )
    
    if (-not (Test-Path $filePath)) {
        Write-Host "❌ File not found: $filePath" -ForegroundColor Red
        return
    }
    
    try {
        # Get the full path
        $fullPath = (Resolve-Path $filePath).Path
        
        # Store file path in clipboard with 'FILE:' prefix for paste-file to recognize
        Set-Clipboard -Value "FILE:$fullPath"
        
        $fileInfo = Get-Item $fullPath
        Write-Host "📋 Copied file to clipboard: $($fileInfo.Name)" -ForegroundColor Green
        Write-Host "💡 Use 'pf' to paste, 'pf -Force' to overwrite without asking" -ForegroundColor DarkGray
        
    } catch {
        Write-Host "❌ Error copying file: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Short aliases
function cf { 
    param([string]$filePath)
    copy-file $filePath 
}

function pf { 
    param([switch]$Force, [string]$Path)
    if ($Path) {
        paste-file -Force:$Force -Path $Path
    } else {
        paste-file -Force:$Force
    }
}

# ============================================================================
# FILE SYSTEM ALIASES & OPERATIONS
# ============================================================================

<#
.SYNOPSIS
    Standard file system aliases for cross-platform familiarity
.DESCRIPTION
    Provides Unix-like aliases for common file operations to improve
    productivity for users familiar with bash/zsh
#>

# Remove built-in ls alias and replace with custom function
if (Test-Path Alias:\ls) { Remove-Item Alias:\ls -Force }

function ls {
    param(
        [string]$path = ".",
        
        [Alias("tree")]
        [switch]$t,
        
        [Alias("depth")]
        [int]$d = 0
    )
    
    # Check if lsd is available
    if (-not (Get-Command lsd -ErrorAction SilentlyContinue)) {
        Write-Host "⚠️ lsd not found. Install with: scoop install lsd" -ForegroundColor Yellow
        Get-ChildItem $path
        return
    }
    
    # Resolve the target path
    $targetPath = if ($path -eq ".") { 
        Get-Location 
    } else { 
        if (Test-Path $path) {
            Resolve-Path $path
        } else {
            Write-Host "❌ Path not found: $path" -ForegroundColor Red
            return
        }
    }
    
    # Smart depth detection if not overridden
    if ($d -eq 0) {
        # Check if we're dealing with node_modules or inside a Node.js project
        $isNodeContext = ($path -like "*node_modules*") -or 
                        ($targetPath -like "*node_modules*") -or
                        (Test-Path (Join-Path $targetPath "package.json")) -or
                        (Test-Path (Join-Path $targetPath "node_modules"))
        
        $d = if ($isNodeContext) { 2 } else { 3 }
    }
    
    # Base lsd arguments for clean output
    $baseArgs = @(
        "--group-dirs=first"        # Group directories first
        "--icon=always"             # Always show icons
        "--color=always"            # Always use colors
    )
    
    if ($t) {
        # Tree view with smart depth
        $treeArgs = $baseArgs + @(
            "--tree"
            "--depth=$d"
        )
        
        Write-Host "🌳 Tree view (depth: $d)" -ForegroundColor DarkGray
        & lsd @treeArgs $path
    } else {
        # Regular detailed listing
        Write-Host "📁 Directory listing" -ForegroundColor DarkGray
        & lsd @baseArgs $path
    }
}

Set-Alias clr clear                                 # Clear screen
function la { Get-ChildItem -Force }                # List all files including hidden
function ll { Get-ChildItem -Force | Format-List }  # Long listing format

# File operations
Set-Alias cat Get-Content                           # Display file contents
if (Test-Path Alias:\\cp) { Remove-Item Alias:\\cp -Force }  # Remove default cp alias
Set-Alias cp Copy-Item                              # Copy files/directories
                           # Move/rename files

Remove-Item Alias:rm -Force
Remove-Item Alias:rmdir -Force
Remove-Item Alias:mv -Force


















# ============================================================================
# ENHANCED MOVE AND RENAME FUNCTIONS WITH BEAUTIFUL FZF STYLING
# ============================================================================

# Remove the built-in mv alias so our custom function works
if (Test-Path Alias:\mv) { Remove-Item Alias:\mv -Force }

# Global variable to store the file being moved
$script:MoveInHand = $null

<#
.SYNOPSIS
    Enhanced file moving with cut-and-paste workflow
.DESCRIPTION
    Two-stage move operation: mv <file> cuts the file, mv-t pastes it in current directory.
    Provides beautiful feedback and handles edge cases gracefully.
.PARAMETER fileName
    Name of file to cut for moving (first stage)
.EXAMPLE
    mv belief-index     # Cuts 'belief-index' for moving
    # Navigate to desired directory
    mv-t               # Pastes 'belief-index' in current directory
#>
function mv {
    param(
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$fileNameParts,
        [switch]$detailed
    )
    
    # Join all arguments to handle filenames with spaces
    $fileName = if ($fileNameParts) { $fileNameParts -join ' ' } else { $null }
    
    # If no filename provided, show current status and help
    if ([string]::IsNullOrWhiteSpace($fileName)) {
        if ($script:MoveInHand) {
            Write-Host "📦 Currently holding: " -NoNewline -ForegroundColor Cyan
            Write-Host "$($script:MoveInHand.Name)" -ForegroundColor Yellow
            Write-Host "💡 Use 'mv-t' to paste in current directory" -ForegroundColor DarkGray
            Write-Host "💡 Use 'mv <newfile>' to drop current and hold new file" -ForegroundColor DarkGray
            Write-Host "💡 Use 'mv-c' to cancel and drop current file" -ForegroundColor DarkGray
        } else {
            Write-Host "💡 Enhanced Move Commands:" -ForegroundColor Cyan
            Write-Host "═════════════════════════" -ForegroundColor Cyan
            Write-Host "  mv <filename>        Cut file for moving (smart search)" -ForegroundColor DarkGray
            Write-Host "  mv-t                 Paste held file in current directory" -ForegroundColor DarkGray
            Write-Host "  mv-c                 Cancel move operation (drop held file)" -ForegroundColor DarkGray
            Write-Host "  mv <filename> -detailed  Show detailed search process" -ForegroundColor DarkGray
        }
        return
    }
    
    if ($detailed) {
        Write-Host "=== SMART MV FUNCTION ===" -ForegroundColor Cyan
        Write-Host "Searching for: '$fileName'" -ForegroundColor Yellow
        Write-Host "Current directory: $PWD" -ForegroundColor Yellow
    }
    
    $currentPath = $PWD.Path
    
    # Handle special cases
    if ($fileName -eq "." -or $fileName -eq "..") {
        Write-Host "❌ Cannot move current or parent directory reference" -ForegroundColor Red
        return
    }
    
    # If we already have something in hand, inform about dropping it
    if ($script:MoveInHand) {
        Write-Host "📦 Dropping previous file: " -NoNewline -ForegroundColor Yellow
        Write-Host "$($script:MoveInHand.Name)" -ForegroundColor White
        Write-Host "🔄 Now preparing: " -NoNewline -ForegroundColor Cyan
        Write-Host "$fileName" -ForegroundColor White
    }
    
    # Try exact path first (absolute or relative)
    if (Test-Path $fileName) {
        if ($detailed) { Write-Host "✅ Found exact path: $fileName" -ForegroundColor Green }
        $foundItem = Get-Item $fileName
        $script:MoveInHand = @{
            FullPath = $foundItem.FullName
            Name = $foundItem.Name
            SourceDirectory = $foundItem.DirectoryName
        }
        Write-Host "✂️  Cut file for moving: " -NoNewline -ForegroundColor Green
        Write-Host "$($foundItem.Name)" -ForegroundColor Yellow
        Write-Host "📁 From: $($foundItem.DirectoryName)" -ForegroundColor DarkGray
        Write-Host "💡 Navigate to destination, then use 'mv-t' to paste" -ForegroundColor Cyan
        return
    }
    
    # === SMART SEARCH LOGIC (like nav function) ===
    
    if ($detailed) { Write-Host "`n🔍 Starting smart search in current directory..." -ForegroundColor Cyan }
    
    try {
        # Get all items in current directory
        $allItems = Get-ChildItem -Path $currentPath -Force -ErrorAction SilentlyContinue
        
        if ($detailed) {
            Write-Host "Found $($allItems.Count) items in current directory" -ForegroundColor Yellow
        }
        
        # Phase 1: Look for EXACT MATCHES
        if ($detailed) { Write-Host "`n📋 Phase 1: Checking for exact matches..." -ForegroundColor Magenta }
        
        $exactMatches = @()
        foreach ($item in $allItems) {
            if ($item.Name -eq $fileName) {
                $exactMatches += $item
                if ($detailed) { Write-Host "  ⭐ EXACT MATCH: $($item.Name)" -ForegroundColor Green }
            }
        }
        
        if ($exactMatches.Count -eq 1) {
            $targetItem = $exactMatches[0]
            $script:MoveInHand = @{
                FullPath = $targetItem.FullName
                Name = $targetItem.Name
                SourceDirectory = $targetItem.DirectoryName
            }
            Write-Host "✂️  Cut file for moving: " -NoNewline -ForegroundColor Green
            Write-Host "$($targetItem.Name)" -ForegroundColor Yellow
            Write-Host "📁 From: $($targetItem.DirectoryName)" -ForegroundColor DarkGray
            Write-Host "💡 Navigate to destination, then use 'mv-t' to paste" -ForegroundColor Cyan
            return
        } elseif ($exactMatches.Count -gt 1) {
            Write-Host "⚠️ Multiple exact matches found:" -ForegroundColor Yellow
            for ($i = 0; $i -lt $exactMatches.Count; $i++) {
                $itemType = if ($exactMatches[$i].PSIsContainer) { "📁 Directory" } else { "📄 File" }
                Write-Host "  [$($i+1)] $($exactMatches[$i].Name) ($itemType)" -ForegroundColor Cyan
            }
            $choice = Read-Host "Enter number to cut for moving (or 'q' to quit)"
            if ($choice -eq 'q') { return }
            if ([int]::TryParse($choice, [ref]$null) -and $choice -ge 1 -and $choice -le $exactMatches.Count) {
                $targetItem = $exactMatches[$choice - 1]
                $script:MoveInHand = @{
                    FullPath = $targetItem.FullName
                    Name = $targetItem.Name
                    SourceDirectory = $targetItem.DirectoryName
                }
                Write-Host "✂️  Cut file for moving: " -NoNewline -ForegroundColor Green
                Write-Host "$($targetItem.Name)" -ForegroundColor Yellow
                Write-Host "📁 From: $($targetItem.DirectoryName)" -ForegroundColor DarkGray
                Write-Host "💡 Navigate to destination, then use 'mv-t' to paste" -ForegroundColor Cyan
                return
            } else {
                Write-Host "❌ Invalid selection" -ForegroundColor Red
                return
            }
        }
        
        # Phase 2: Look for FUZZY MATCHES (contains the search term)
        if ($detailed) { Write-Host "`n📋 Phase 2: Checking for fuzzy matches..." -ForegroundColor Magenta }
        
        $fuzzyMatches = @()
        foreach ($item in $allItems) {
            if ($item.Name -like "*$fileName*" -and $item.Name -ne $fileName) {
                $fuzzyMatches += $item
                if ($detailed) { Write-Host "  ⚡ FUZZY MATCH: $($item.Name)" -ForegroundColor Yellow }
            }
        }
        
        if ($fuzzyMatches.Count -eq 1) {
            $targetItem = $fuzzyMatches[0]
            Write-Host "🎯 Found similar file: $($targetItem.Name)" -ForegroundColor Green
            Write-Host "💡 Searched for: $fileName" -ForegroundColor DarkGray
            $script:MoveInHand = @{
                FullPath = $targetItem.FullName
                Name = $targetItem.Name
                SourceDirectory = $targetItem.DirectoryName
            }
            Write-Host "✂️  Cut file for moving: " -NoNewline -ForegroundColor Green
            Write-Host "$($targetItem.Name)" -ForegroundColor Yellow
            Write-Host "📁 From: $($targetItem.DirectoryName)" -ForegroundColor DarkGray
            Write-Host "💡 Navigate to destination, then use 'mv-t' to paste" -ForegroundColor Cyan
            return
        } elseif ($fuzzyMatches.Count -gt 1) {
            Write-Host "🔍 Multiple similar files found:" -ForegroundColor Yellow
            for ($i = 0; $i -lt $fuzzyMatches.Count; $i++) {
                $itemType = if ($fuzzyMatches[$i].PSIsContainer) { "📁 Directory" } else { "📄 File" }
                Write-Host "  [$($i+1)] $($fuzzyMatches[$i].Name) ($itemType)" -ForegroundColor Cyan
            }
            $choice = Read-Host "Enter number to cut for moving (or 'q' to quit)"
            if ($choice -eq 'q') { return }
            if ([int]::TryParse($choice, [ref]$null) -and $choice -ge 1 -and $choice -le $fuzzyMatches.Count) {
                $targetItem = $fuzzyMatches[$choice - 1]
                $script:MoveInHand = @{
                    FullPath = $targetItem.FullName
                    Name = $targetItem.Name
                    SourceDirectory = $targetItem.DirectoryName
                }
                Write-Host "✂️  Cut file for moving: " -NoNewline -ForegroundColor Green
                Write-Host "$($targetItem.Name)" -ForegroundColor Yellow
                Write-Host "📁 From: $($targetItem.DirectoryName)" -ForegroundColor DarkGray
                Write-Host "💡 Navigate to destination, then use 'mv-t' to paste" -ForegroundColor Cyan
                return
            } else {
                Write-Host "❌ Invalid selection" -ForegroundColor Red
                return
            }
        }
        
        # Phase 3: Try common file extensions
        if ($detailed) { Write-Host "`n📋 Phase 3: Trying common file extensions..." -ForegroundColor Magenta }
        
        $commonExtensions = @(".txt", ".md", ".json", ".xml", ".csv", ".log", ".ps1", ".py", ".js", ".html", ".css")
        $extensionMatches = @()
        
        foreach ($ext in $commonExtensions) {
            $testName = "$fileName$ext"
            $match = $allItems | Where-Object { $_.Name -eq $testName }
            if ($match) {
                $extensionMatches += $match
                if ($detailed) { Write-Host "  💡 EXTENSION MATCH: $testName" -ForegroundColor Cyan }
            }
        }
        
        if ($extensionMatches.Count -eq 1) {
            $targetItem = $extensionMatches[0]
            Write-Host "🎯 Found file with extension: $($targetItem.Name)" -ForegroundColor Green
            Write-Host "💡 Searched for: $fileName" -ForegroundColor DarkGray
            $script:MoveInHand = @{
                FullPath = $targetItem.FullName
                Name = $targetItem.Name
                SourceDirectory = $targetItem.DirectoryName
            }
            Write-Host "✂️  Cut file for moving: " -NoNewline -ForegroundColor Green
            Write-Host "$($targetItem.Name)" -ForegroundColor Yellow
            Write-Host "📁 From: $($targetItem.DirectoryName)" -ForegroundColor DarkGray
            Write-Host "💡 Navigate to destination, then use 'mv-t' to paste" -ForegroundColor Cyan
            return
        } elseif ($extensionMatches.Count -gt 1) {
            Write-Host "🔍 Multiple files found with extensions:" -ForegroundColor Yellow
            for ($i = 0; $i -lt $extensionMatches.Count; $i++) {
                Write-Host "  [$($i+1)] $($extensionMatches[$i].Name)" -ForegroundColor Cyan
            }
            $choice = Read-Host "Enter number to cut for moving (or 'q' to quit)"
            if ($choice -eq 'q') { return }
            if ([int]::TryParse($choice, [ref]$null) -and $choice -ge 1 -and $choice -le $extensionMatches.Count) {
                $targetItem = $extensionMatches[$choice - 1]
                $script:MoveInHand = @{
                    FullPath = $targetItem.FullName
                    Name = $targetItem.Name
                    SourceDirectory = $targetItem.DirectoryName
                }
                Write-Host "✂️  Cut file for moving: " -NoNewline -ForegroundColor Green
                Write-Host "$($targetItem.Name)" -ForegroundColor Yellow
                Write-Host "📁 From: $($targetItem.DirectoryName)" -ForegroundColor DarkGray
                Write-Host "💡 Navigate to destination, then use 'mv-t' to paste" -ForegroundColor Cyan
                return
            } else {
                Write-Host "❌ Invalid selection" -ForegroundColor Red
                return
            }
        }
        
    } catch {
        Write-Host "❌ Error during search: $($_.Exception.Message)" -ForegroundColor Red
        return
    }
    
    # If we get here, nothing was found
    Write-Host "❌ No matches found for: $fileName" -ForegroundColor Red
    Write-Host "💡 Searched in: $currentPath" -ForegroundColor DarkGray
    Write-Host "💡 Tried:" -ForegroundColor DarkGray
    Write-Host "   • Exact filename match" -ForegroundColor DarkGray
    Write-Host "   • Partial filename matches (fuzzy)" -ForegroundColor DarkGray
    Write-Host "   • Common file extensions (.txt, .md, .json, etc.)" -ForegroundColor DarkGray
    Write-Host "💡 Use 'mv $fileName -detailed' for detailed search output" -ForegroundColor DarkGray
    Write-Host "💡 Use full filename if you know it exactly" -ForegroundColor DarkGray
}

<#
.SYNOPSIS
    Paste the file that was cut with mv command
.DESCRIPTION
    Second stage of the move operation. Moves the previously cut file to current directory.
.EXAMPLE
    mv-t     # Pastes the file that was cut with mv command
#>
function mv-t {
    if (-not $script:MoveInHand) {
        Write-Host "❌ No file currently held for moving" -ForegroundColor Red
        Write-Host "💡 Use 'mv <filename>' first to cut a file for moving" -ForegroundColor DarkGray
        return
    }
    
    $sourceFile = $script:MoveInHand.FullPath
    $fileName = $script:MoveInHand.Name
    $sourceDir = $script:MoveInHand.SourceDirectory
    $currentDir = $PWD.Path
    
    # Check if source file still exists
    if (-not (Test-Path $sourceFile)) {
        Write-Host "❌ Source file no longer exists: $fileName" -ForegroundColor Red
        Write-Host "📁 Expected location: $sourceFile" -ForegroundColor DarkGray
        $script:MoveInHand = $null
        return
    }
    
    # Check if we're trying to move to the same directory
    if ($sourceDir -eq $currentDir) {
        Write-Host "⚠️ Source and destination are the same directory" -ForegroundColor Yellow
        Write-Host "📁 Directory: $currentDir" -ForegroundColor DarkGray
        Write-Host "💡 Navigate to a different directory first" -ForegroundColor Cyan
        return
    }
    
    # Check if file already exists in destination
    $destinationPath = Join-Path $currentDir $fileName
    if (Test-Path $destinationPath) {
        Write-Host "⚠️ File already exists in destination: $fileName" -ForegroundColor Yellow
        Write-Host "📁 Destination: $currentDir" -ForegroundColor DarkGray
        
        $choice = Read-Host "Overwrite existing file? (y/n)"
        if ($choice -ne 'y' -and $choice -ne 'Y') {
            Write-Host "❌ Move operation cancelled" -ForegroundColor Yellow
            return
        }
    }
    
    # Perform the move
    try {
        Move-Item -Path $sourceFile -Destination $currentDir -Force
        
        # Success message
        Write-Host ""
        Write-Host "╭─ ✅ MOVE COMPLETED ─────────────────────────────────────────────────╮" -ForegroundColor Green
        Write-Host "│                                                                     │" -ForegroundColor Green
        Write-Host "│  📄 File: $fileName".PadRight(68) + "│" -ForegroundColor Green
        Write-Host "│  📁 From: $sourceDir".PadRight(68) + "│" -ForegroundColor Green
        Write-Host "│  📍 To:   $currentDir".PadRight(68) + "│" -ForegroundColor Green
        Write-Host "│                                                                     │" -ForegroundColor Green
        Write-Host "╰─────────────────────────────────────────────────────────────────────╯" -ForegroundColor Green
        Write-Host ""
        
        # Clear the held file
        $script:MoveInHand = $null
        
    } catch {
        Write-Host ""
        Write-Host "╭─ ❌ MOVE FAILED ────────────────────────────────────────────────────╮" -ForegroundColor Red
        Write-Host "│                                                                     │" -ForegroundColor Red
        Write-Host "│  📄 File: $fileName".PadRight(68) + "│" -ForegroundColor Red
        Write-Host "│  ❌ Error: $($_.Exception.Message)".PadRight(68) + "│" -ForegroundColor Red
        Write-Host "│                                                                     │" -ForegroundColor Red
        Write-Host "╰─────────────────────────────────────────────────────────────────────╯" -ForegroundColor Red
        Write-Host ""
        Write-Host "💡 The file is still held. Try mv-t again after resolving the issue." -ForegroundColor Cyan
    }
}

<#
.SYNOPSIS
    Cancel move operation and drop the held file
.DESCRIPTION
    Cancels the current move operation without moving the file.
.EXAMPLE
    mv-c     # Cancels move and drops held file
#>
function mv-c {
    if (-not $script:MoveInHand) {
        Write-Host "ℹ️ No file currently held for moving" -ForegroundColor Yellow
        return
    }
    
    Write-Host "🗑️ Dropped file from move queue: " -NoNewline -ForegroundColor Yellow
    Write-Host "$($script:MoveInHand.Name)" -ForegroundColor White
    $script:MoveInHand = $null
    Write-Host "✅ Move operation cancelled" -ForegroundColor Green
}

<#
.SYNOPSIS
    Enhanced file renaming with beautiful FZF interface
.DESCRIPTION
    Interactive file renaming using fuzzy search to select file and beautiful
    interface for entering new name. Includes smart search capabilities.
.PARAMETER fileName
    Optional filename to rename directly (skips file picker)
.EXAMPLE
    rn                  # Opens file picker, then rename interface
    rn myfile.txt       # Renames myfile.txt directly with interface
#>
function rn {
    param(
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$fileNameParts
    )
    
    # Join all arguments to handle filenames with spaces
    $fileName = if ($fileNameParts) { $fileNameParts -join ' ' } else { $null }
    
    $currentPath = $PWD.Path
    $targetFile = $null
    
    # If no filename provided, use fzf to pick a file
    if ([string]::IsNullOrWhiteSpace($fileName)) {
        $allItems = Get-ChildItem -Path $currentPath -Force | Where-Object { -not $_.PSIsContainer }
        
        if ($allItems.Count -eq 0) {
            Write-Host "❌ No files found in current directory" -ForegroundColor Red
            return
        }
        
        # Create beautiful file list for fzf
        $fileList = $allItems | ForEach-Object {
            $size = if ($_.Length -lt 1KB) { "$($_.Length) B" }
                   elseif ($_.Length -lt 1MB) { "$([math]::Round($_.Length / 1KB, 1)) KB" }
                   else { "$([math]::Round($_.Length / 1MB, 1)) MB" }
            
            $modified = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
            
            "📄 {0,-30} 📊 {1,-8} 📅 {2}" -f $_.Name, $size, $modified
        }
        
        $selected = $fileList | fzf --ansi --reverse --height=60% --border --prompt="🔄 Select file to rename: " `
            --header="📄 File | 📊 Size | 📅 Modified | Enter: Select | Esc: Cancel"
        
        if (-not $selected) {
            Write-Host "❌ No file selected" -ForegroundColor Yellow
            return
        }
        
        # Extract filename from selection
        if ($selected -match '^📄\s+(\S+)') {
            $fileName = $matches[1]
        } else {
            Write-Host "❌ Could not extract filename from selection" -ForegroundColor Red
            return
        }
    }
    
    # Find the target file (same smart search as mv function)
    if (Test-Path $fileName) {
        $targetFile = Get-Item $fileName
    } else {
        # Smart search logic
        $allItems = Get-ChildItem -Path $currentPath -Force
        
        # Exact match first
        $exactMatch = $allItems | Where-Object { $_.Name -eq $fileName -and -not $_.PSIsContainer }
        if ($exactMatch) {
            $targetFile = $exactMatch
        } else {
            # Fuzzy match
            $fuzzyMatches = $allItems | Where-Object { $_.Name -like "*$fileName*" -and -not $_.PSIsContainer }
            if ($fuzzyMatches.Count -eq 1) {
                $targetFile = $fuzzyMatches[0]
                Write-Host "🎯 Found similar file: $($targetFile.Name)" -ForegroundColor Green
                Write-Host "💡 Searched for: $fileName" -ForegroundColor DarkGray
            } elseif ($fuzzyMatches.Count -gt 1) {
                Write-Host "🔍 Multiple similar files found:" -ForegroundColor Yellow
                for ($i = 0; $i -lt $fuzzyMatches.Count; $i++) {
                    Write-Host "  [$($i+1)] $($fuzzyMatches[$i].Name)" -ForegroundColor Cyan
                }
                $choice = Read-Host "Enter number to rename (or 'q' to quit)"
                if ($choice -eq 'q') { return }
                if ([int]::TryParse($choice, [ref]$null) -and $choice -ge 1 -and $choice -le $fuzzyMatches.Count) {
                    $targetFile = $fuzzyMatches[$choice - 1]
                } else {
                    Write-Host "❌ Invalid selection" -ForegroundColor Red
                    return
                }
            }
        }
    }
    
    if (-not $targetFile) {
        Write-Host "❌ File not found: $fileName" -ForegroundColor Red
        return
    }
    
    # Get file info for display
    $fileInfo = $targetFile
    $currentName = $fileInfo.Name
    $fileSize = if ($fileInfo.Length -lt 1KB) { "$($fileInfo.Length) B" }
                elseif ($fileInfo.Length -lt 1MB) { "$([math]::Round($fileInfo.Length / 1KB, 1)) KB" }
                else { "$([math]::Round($fileInfo.Length / 1MB, 1)) MB" }
    
    # Beautiful rename interface using fzf
    $formLines = @(
        "",
        "🔄 File Rename Operation",
        "════════════════════════",
        "",
        "📄 Current name: $currentName",
        "📊 File size: $fileSize",
        "📁 Location: $currentPath",
        "📅 Modified: $($fileInfo.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))",
        "",
        "💡 Type the new filename above and press Enter",
        "💡 Press Ctrl+C or Esc to cancel",
        "",
        "⚠️  Note: Include file extension if changing it"
    )
    
    # Launch fzf with --print-query to get typed input
    $fzfOutput = $formLines | fzf `
        --ansi `
        --reverse `
        --border=rounded `
        --height=80% `
        --prompt="🔄 New filename: " `
        --header="📝 File Rename Interface" `
        --header-first `
        --color="header:bold:cyan,prompt:bold:green,border:yellow,spinner:yellow" `
        --margin=1 `
        --padding=1 `
        --print-query `
        --expect=enter
    
    # Extract the new filename from fzf output
    $newFileName = ""
    if ($fzfOutput) {
        $lines = @($fzfOutput)
        if ($lines.Count -gt 0) {
            $newFileName = $lines[0].Trim()
        }
    }
    
    # Validate new filename
    if ([string]::IsNullOrWhiteSpace($newFileName)) {
        Write-Host "❌ Rename cancelled - no filename provided" -ForegroundColor Yellow
        return
    }
    
    if ($newFileName -eq $currentName) {
        Write-Host "❌ New filename is the same as current filename" -ForegroundColor Yellow
        return
    }
    
    # Check if new filename already exists
    $newPath = Join-Path $currentPath $newFileName
    if (Test-Path $newPath) {
        Write-Host "⚠️ File already exists: $newFileName" -ForegroundColor Yellow
        $confirm = Read-Host "Overwrite existing file? (y/n)"
        if ($confirm -ne 'y' -and $confirm -ne 'Y') {
            Write-Host "❌ Rename cancelled" -ForegroundColor Yellow
            return
        }
    }
    
    # Perform the rename
    try {
        Rename-Item -Path $fileInfo.FullName -NewName $newFileName
        
        # Success message
        Write-Host ""
        Write-Host "╭─ ✅ RENAME COMPLETED ──────────────────────────────────────────────╮" -ForegroundColor Green
        Write-Host "│                                                                     │" -ForegroundColor Green
        Write-Host "│  📄 Old name: $currentName".PadRight(68) + "│" -ForegroundColor Green
        Write-Host "│  📄 New name: $newFileName".PadRight(68) + "│" -ForegroundColor Green
        Write-Host "│  📁 Location: $currentPath".PadRight(68) + "│" -ForegroundColor Green
        Write-Host "│                                                                     │" -ForegroundColor Green
        Write-Host "╰─────────────────────────────────────────────────────────────────────╯" -ForegroundColor Green
        Write-Host ""
        
    } catch {
        Write-Host ""
        Write-Host "╭─ ❌ RENAME FAILED ─────────────────────────────────────────────────╮" -ForegroundColor Red
        Write-Host "│                                                                     │" -ForegroundColor Red
        Write-Host "│  📄 File: $currentName".PadRight(68) + "│" -ForegroundColor Red
        Write-Host "│  ❌ Error: $($_.Exception.Message)".PadRight(68) + "│" -ForegroundColor Red
        Write-Host "│                                                                     │" -ForegroundColor Red
        Write-Host "╰─────────────────────────────────────────────────────────────────────╯" -ForegroundColor Red
        Write-Host ""
    }
}




































function rmdir {
    $line = $MyInvocation.Line.Replace("rmdir", "").Trim()

    if (-not $line) {
        Write-Warning "⚠️ No path provided"
        return
    }

    $path = $line.Trim('"')
    $resolved = Resolve-Path -LiteralPath $path -ErrorAction SilentlyContinue

    if (-not $resolved) {
        Write-Warning "⚠️ Path not found: $path"
        return
    }

    $fullPath = $resolved.Path

    # Check for children
    $children = Get-ChildItem -LiteralPath $fullPath -Force -ErrorAction SilentlyContinue
    $hasChildren = $children.Count -gt 0

    if ($hasChildren) {
        $confirm = Read-Host "⚠️ Directory '$path' contains items. Delete everything? [y/N]"
        if ($confirm -ne 'y' -and $confirm -ne 'Y') {
            Write-Host "❌ Deletion cancelled." -ForegroundColor Yellow
            return
        }
    }

    try {
        Remove-Item -LiteralPath $fullPath -Recurse -Force -ErrorAction Stop
        Write-Host "✅ Directory '$path' deleted successfully" -ForegroundColor Green
    } catch {
        Write-Warning "❌ Failed to delete '$path': $($_.Exception.Message)"
        return
    }

    ls
}






<#
.SYNOPSIS
    Create new empty file (Unix-style touch command)
.PARAMETER f
    File path to create
#>
function touch { 
    param($f) 
    New-Item -ItemType File -Path $f -Force 
}






<#
.SYNOPSIS
    Create new directory (enhanced mkdir)
.PARAMETER name
    Directory name/path to create
#>


function mkdir {
    param(
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$name
    )
    
    # Join all arguments with spaces
    $folderName = $name -join ' '
    
    # Check if name is empty or whitespace only
    if ([string]::IsNullOrWhiteSpace($folderName)) {
        throw "Directory name cannot be empty or whitespace only"
    }
    
    # Check for leading or trailing spaces
    if ($folderName.StartsWith(' ') -or $folderName.EndsWith(' ')) {
        throw "Directory name cannot start or end with spaces"
    }
    
    # Check that name contains only allowed characters
    if ($folderName -notmatch '^[a-zA-Z ._-]+$') {
        throw "Directory name can only contain letters (a-z, A-Z), spaces, and the symbols: hyphen (-), period (.), underscore (_)"
    }
    
    # Count special symbols and ensure only one of each is allowed
    $hyphenCount = ($folderName.ToCharArray() | Where-Object { $_ -eq '-' } | Measure-Object).Count
    $periodCount = ($folderName.ToCharArray() | Where-Object { $_ -eq '.' } | Measure-Object).Count
    $underscoreCount = ($folderName.ToCharArray() | Where-Object { $_ -eq '_' } | Measure-Object).Count
    $spaceCount = ($folderName.ToCharArray() | Where-Object { $_ -eq ' ' } | Measure-Object).Count
    
    if ($hyphenCount -gt 1) {
        throw "Directory name can contain at most one hyphen (-). Found $hyphenCount."
    }
    if ($periodCount -gt 1) {
        throw "Directory name can contain at most one period (.). Found $periodCount."
    }
    if ($underscoreCount -gt 1) {
        throw "Directory name can contain at most one underscore (_). Found $underscoreCount."
    }
    if ($spaceCount -gt 1) {
        throw "Directory name can contain at most 2 words (1 space). Found $($spaceCount + 1) words."
    }
    
    # Create the directory
    try {
        New-Item -ItemType Directory -Path $folderName -Force
        Write-Host "Directory '$folderName' created successfully" -ForegroundColor Green
    }
    catch {
        throw "Failed to create directory '$folderName': $($_.Exception.Message)"
    }
}






    
# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

<#
.SYNOPSIS
    Text search and system utilities
.DESCRIPTION
    Common utilities for file searching, paging, and command resolution
#>
Set-Alias grep Select-String                        # Search text in files
Set-Alias less more                                 # Page through content

<#
.SYNOPSIS
    Find the location of a command (Unix-style which)
.PARAMETER cmd
    Command name to locate
.EXAMPLE
    which git     # Shows path to git executable
#>
function which { 
    param($cmd) 
    Get-Command $cmd | Select-Object -ExpandProperty Definition 
}












# ============================================================================
# GIT UTILITIES & WORKFLOW FUNCTIONS
# ============================================================================




function gh-l {
    param (
        [int]$Count = 10,
        [string]$Token
    )
    
    # Allow positional parameter for count: gh-l 15
    if ($args.Count -gt 0 -and $args[0] -match '^\d+$') {
        $Count = [int]$args[0]
    }
    
    $credentialName = "gh-l-github-token"
    
    # Function to securely store token in Windows Credential Manager
    function Set-GitHubToken {
        param([string]$Token)
        try {
            # Store in Windows Credential Manager using cmdkey
            $result = & cmdkey /generic:$credentialName /user:github /pass:$Token 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✅ Token saved securely in Windows Credential Manager" -ForegroundColor Green
                return $true
            } else {
                Write-Host "⚠️ Could not save to Credential Manager: $result" -ForegroundColor Yellow
                return $false
            }
        } catch {
            Write-Host "⚠️ Could not save token: $($_.Exception.Message)" -ForegroundColor Yellow
            return $false
        }
    }
    
    # Function to retrieve token from Windows Credential Manager
    function Get-GitHubToken {
        try {
            # Check if credential exists
            $result = & cmdkey /list:$credentialName 2>&1
            if ($LASTEXITCODE -eq 0 -and $result -match "GENERIC") {
                # Use .NET CredentialManager to retrieve the password
                Add-Type -TypeDefinition @"
                using System;
                using System.Runtime.InteropServices;
                using System.Text;

                public class CredentialManager
                {
                    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
                    public static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr credentialPtr);

                    [DllImport("advapi32.dll", SetLastError = true)]
                    public static extern void CredFree(IntPtr cred);

                    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
                    public struct CREDENTIAL
                    {
                        public int Flags;
                        public int Type;
                        public string TargetName;
                        public string Comment;
                        public long LastWritten;
                        public int CredentialBlobSize;
                        public IntPtr CredentialBlob;
                        public int Persist;
                        public int AttributeCount;
                        public IntPtr Attributes;
                        public string TargetAlias;
                        public string UserName;
                    }

                    public static string GetPassword(string target)
                    {
                        IntPtr credPtr;
                        if (CredRead(target, 1, 0, out credPtr))
                        {
                            var credential = (CREDENTIAL)Marshal.PtrToStructure(credPtr, typeof(CREDENTIAL));
                            var password = Marshal.PtrToStringUni(credential.CredentialBlob, credential.CredentialBlobSize / 2);
                            CredFree(credPtr);
                            return password;
                        }
                        return null;
                    }
                }
"@
                
                $password = [CredentialManager]::GetPassword($credentialName)
                if ($password) {
                    Write-Host "🔐 Using saved token from Credential Manager" -ForegroundColor DarkGreen
                    return $password
                }
            }
            return $null
        } catch {
            return $null
        }
    }
    
    # Function to get commit count for a repo in specified timeframe
    function Get-CommitCount {
        param(
            [string]$RepoFullName,
            [string]$Since,
            [hashtable]$Headers
        )
        try {
            $commitsUrl = "https://api.github.com/repos/$RepoFullName/commits?since=$Since&per_page=100"
            $commits = Invoke-RestMethod -Uri $commitsUrl -Headers $Headers -ErrorAction SilentlyContinue
            return $commits.Count
        } catch {
            return 0
        }
    }
    
    # Get token from various sources
    if (-not $Token) {
        # Try environment variable first
        $Token = $env:GITHUB_TOKEN
        
        # If no env token, check credential manager
        if (-not $Token) {
            $Token = Get-GitHubToken
        }
    }
    
    # If still no token, prompt for it
    if (-not $Token) {
        Write-Host "❌ GitHub Personal Access Token required for private repos" -ForegroundColor Red
        Write-Host ""
        Write-Host "🔧 Setup instructions:" -ForegroundColor Cyan
        Write-Host "  1. Go to: https://github.com/settings/tokens" -ForegroundColor DarkGray
        Write-Host "  2. Generate new token (classic) with 'repo' scope" -ForegroundColor DarkGray
        Write-Host "  3. Copy the token and paste it below" -ForegroundColor DarkGray
        Write-Host ""
        
        $secureInput = Read-Host "🔑 Enter your GitHub token (input hidden)" -AsSecureString
        $Token = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureInput)
        )
        
        if ($Token) {
            $save = Read-Host "💾 Save token securely in Windows Credential Manager? (y/n)"
            if ($save -eq 'y') {
                Set-GitHubToken -Token $Token
            }
        }
    }
    
    if (-not $Token) {
        Write-Host "❌ No token provided" -ForegroundColor Red
        return
    }
    
    # Calculate date filters
    $now = Get-Date
    $yesterday = $now.AddDays(-1).ToString("yyyy-MM-ddTHH:mm:ssZ")
    $lastWeek = $now.AddDays(-7).ToString("yyyy-MM-ddTHH:mm:ssZ")
    
    # Get ALL repositories first, then sort manually to ensure correct order
    # GitHub API sometimes doesn't sort reliably, so we'll fetch everything and sort ourselves
    $allRepos = @()
    $page = 1
    $perPage = 100  # Max per page
    
    try {
        $headers = @{
            "Authorization" = "Bearer $Token"
            "Accept" = "application/vnd.github.v3+json"
            "User-Agent" = "pwsh-gh-l"
        }
        
        Write-Host "🔐 Fetching all your repositories to ensure proper sorting..." -ForegroundColor Cyan
        
        do {
            $url = "https://api.github.com/user/repos?per_page=$perPage&page=$page&affiliation=owner"
            $pageRepos = Invoke-RestMethod -Uri $url -Headers $headers
            
            if ($pageRepos.Count -gt 0) {
                $allRepos += $pageRepos
                Write-Host "📦 Fetched $($allRepos.Count) repositories..." -ForegroundColor DarkGray
                $page++
            }
        } while ($pageRepos.Count -eq $perPage)  # Continue while we get full pages
        
        Write-Host "✅ Found $($allRepos.Count) total repositories" -ForegroundColor Green
        
        # Now sort ALL repos by pushed_at date (most recent first) and take only what we need
        Write-Host "🔍 Debugging: Sorting $($allRepos.Count) repositories by push date..." -ForegroundColor Yellow
        
        # Add sorting with explicit date conversion and debugging
        $sortedRepos = $allRepos | ForEach-Object {
            $pushDate = try { 
                [DateTime]$_.pushed_at 
            } catch { 
                [DateTime]"1900-01-01"  # Fallback for invalid dates
            }
            
            [PSCustomObject]@{
                Repo = $_
                PushDate = $pushDate
                PushDateString = $pushDate.ToString("yyyy-MM-dd HH:mm")
            }
        } | Sort-Object PushDate -Descending
        
        # Show top 3 for debugging
        Write-Host "🔍 Top 3 most recent pushes:" -ForegroundColor Yellow
        $sortedRepos | Select-Object -First 3 | ForEach-Object {
            Write-Host "   $($_.Repo.name) - $($_.PushDateString)" -ForegroundColor DarkGray
        }
        
        $repos = $sortedRepos | Select-Object -First $Count -ExpandProperty Repo
        
        Write-Host "🎯 Showing top $Count most recently pushed repositories" -ForegroundColor Cyan
        
        if (-not $repos) {
            Write-Host "ℹ️ No repositories found." -ForegroundColor Yellow
            return
        }
        
        Write-Host "📊 Analyzing commit activity..." -ForegroundColor Yellow
        
        # Get terminal width for dynamic sizing
        $terminalWidth = try { 
            $Host.UI.RawUI.WindowSize.Width 
        } catch { 
            120  # fallback width
        }
        
        # Calculate fzf height based on available repos and terminal size
        $maxHeight = [Math]::Min($repos.Count + 5, 25)  # +5 for headers/borders, max 25
        
        $choices = $repos | ForEach-Object {
            $repoName = $_.name
            $privacy = if ($_.private) { "🔒" } else { "🌐" }
            $language = if ($_.language) { $_.language } else { "Text" }
            
            # Get the last push date - show full date for debugging
            $lastPush = ([DateTime]$_.pushed_at).ToString("yyyy-MM-dd")
            
            # Get commit counts (this adds some delay but provides valuable info)
            $commits24h = Get-CommitCount -RepoFullName $_.full_name -Since $yesterday -Headers $headers
            $commits1w = Get-CommitCount -RepoFullName $_.full_name -Since $lastWeek -Headers $headers
            
            # Format with proper spacing - adjust column widths based on terminal
            $nameWidth = [Math]::Min(30, [Math]::Max(20, $terminalWidth * 0.25))
            $langWidth = [Math]::Min(12, [Math]::Max(8, $terminalWidth * 0.12))
            
            "{0} {1,-$nameWidth}  📅{2}  📊24h:{3,2}  📈1w:{4,2}  💻{5,-$langWidth}" -f `
                $privacy, $repoName, $lastPush, $commits24h, $commits1w, $language
        }
        
        # Header for the display
        $header = "🔒=Private 🌐=Public | 📅=Last Push (YYYY-MM-DD) | 📊=Commits 24h | 📈=Commits 1w | 💻=Language"
        
        $selection = $choices | fzf --ansi --reverse --height=$maxHeight --border --no-sort `
            --prompt="📦 Recent Repos ($Count shown): " --header="$header"
        
        if ($selection) {
            # Extract repo name from selection - handle emoji encoding issues
            # The emojis might display as different Unicode characters in different terminals
            # So we'll match more flexibly: any character(s) followed by spaces, then the repo name
            
            Write-Host "🔍 Debug: Selection = '$selection'" -ForegroundColor Yellow
            
            # More flexible pattern: skip the first few characters (emoji), then capture the repo name
            # Pattern explanation: ^\S*\s+(\S+) = start of line, non-spaces (emoji), spaces, then repo name
            if ($selection -match '^\S+\s+(\S+)') {
                $selectedRepoName = $matches[1].Trim()
                Write-Host "🔍 Debug: Extracted repo name = '$selectedRepoName'" -ForegroundColor Yellow
                
                # Find the full repo object to get URL and details
                $selectedRepo = $repos | Where-Object { $_.name -eq $selectedRepoName }
                if ($selectedRepo) {
                    $repoUrl = $selectedRepo.html_url
                    $repoFullName = $selectedRepo.full_name  # owner/repo format
                    
                    Set-Clipboard $repoUrl
                    Write-Host "📋 Copied URL: $repoUrl" -ForegroundColor Green
                    Write-Host "`n🔧 What would you like to do with '$selectedRepoName'?" -ForegroundColor Cyan
                    Write-Host "  1. Clone repository" -ForegroundColor DarkGray
                    Write-Host "  2. Open in browser" -ForegroundColor DarkGray
                    Write-Host "  3. Copy SSH URL instead" -ForegroundColor DarkGray
                    Write-Host "  4. Delete repository (⚠️ PERMANENT)" -ForegroundColor Red
                    Write-Host "  5. Just copied HTTP URL" -ForegroundColor DarkGray
                    
                    $action = Read-Host "Choose action (1-5)"
                    switch ($action) {
                        "1" {
                            Write-Host "📂 Cloning repository..." -ForegroundColor Cyan
                            Write-Host "Running: git clone $repoUrl" -ForegroundColor DarkGray
                            git clone $repoUrl
                            if ($LASTEXITCODE -eq 0) {
                                Write-Host "✅ Repository cloned successfully!" -ForegroundColor Green
                            } else {
                                Write-Host "❌ Clone failed. Check your git configuration." -ForegroundColor Red
                            }
                        }
                        "2" {
                            Write-Host "🌐 Opening in browser..." -ForegroundColor Cyan
                            Start-Process $repoUrl
                        }
                        "3" {
                            # Convert HTTPS URL to SSH
                            $sshUrl = $repoUrl -replace "https://github.com/", "git@github.com:" -replace "\.git$", "" + ".git"
                            Set-Clipboard $sshUrl
                            Write-Host "📋 Copied SSH URL: $sshUrl" -ForegroundColor Green
                        }
                        "4" {
                            # DANGEROUS: Delete repository with triple confirmation
                            Write-Host "`n⚠️ WARNING: YOU ARE ABOUT TO DELETE A REPOSITORY!" -ForegroundColor Red -BackgroundColor Yellow
                            Write-Host "Repository: $repoFullName" -ForegroundColor White -BackgroundColor Red
                            Write-Host "This action is PERMANENT and CANNOT be undone!" -ForegroundColor Red
                            Write-Host "All code, issues, pull requests, and history will be lost forever!" -ForegroundColor Red
                            
                            # First confirmation
                            Write-Host "`n🔴 CONFIRMATION 1 of 3:" -ForegroundColor Red
                            $confirm1 = Read-Host "Type the repository name '$selectedRepoName' to continue"
                            if ($confirm1 -ne $selectedRepoName) {
                                Write-Host "❌ Repository name mismatch. Deletion cancelled." -ForegroundColor Green
                                break
                            }
                            
                            # Second confirmation  
                            Write-Host "`n🔴 CONFIRMATION 2 of 3:" -ForegroundColor Red
                            $confirm2 = Read-Host "Type 'DELETE' (in capitals) to confirm you want to delete this repository"
                            if ($confirm2 -ne "DELETE") {
                                Write-Host "❌ Confirmation failed. Deletion cancelled." -ForegroundColor Green
                                break
                            }
                            
                            # Third confirmation
                            Write-Host "`n🔴 FINAL CONFIRMATION 3 of 3:" -ForegroundColor Red
                            Write-Host "This is your LAST CHANCE to cancel!" -ForegroundColor Red
                            $confirm3 = Read-Host "Type 'I UNDERSTAND THIS IS PERMANENT' to proceed with deletion"
                            if ($confirm3 -ne "I UNDERSTAND THIS IS PERMANENT") {
                                Write-Host "❌ Final confirmation failed. Deletion cancelled." -ForegroundColor Green
                                break
                            }
                            
                            # Proceed with deletion
                            Write-Host "`n💀 Deleting repository..." -ForegroundColor Red
                            try {
                                $deleteUrl = "https://api.github.com/repos/$repoFullName"
                                $deleteResult = Invoke-RestMethod -Uri $deleteUrl -Method DELETE -Headers $headers
                                Write-Host "💀 Repository '$selectedRepoName' has been permanently deleted." -ForegroundColor Red
                                Write-Host "🔄 You may want to run gh-l again to refresh the list." -ForegroundColor Yellow
                            } catch {
                                if ($_.Exception.Message -match "404") {
                                    Write-Host "❌ Repository not found. It may have already been deleted." -ForegroundColor Yellow
                                } elseif ($_.Exception.Message -match "403") {
                                    Write-Host "❌ Permission denied. You may not have delete permissions for this repository." -ForegroundColor Red
                                } else {
                                    Write-Host "❌ Failed to delete repository: $($_.Exception.Message)" -ForegroundColor Red
                                }
                            }
                        }
                        default {
                            Write-Host "✅ Done. HTTPS URL is on your clipboard." -ForegroundColor Green
                        }
                    }
                } else {
                    Write-Host "❌ Could not find repository details for: '$selectedRepoName'" -ForegroundColor Red
                    Write-Host "🔍 Available repos: $($repos.name -join ', ')" -ForegroundColor DarkGray
                }
            } else {
                Write-Host "❌ Could not extract repository name from selection" -ForegroundColor Red
                Write-Host "🔍 Selection format: '$selection'" -ForegroundColor DarkGray
                Write-Host "💡 Try selecting a different repository" -ForegroundColor Yellow
            }
        }
    } catch {
        if ($_.Exception.Message -match "401") {
            Write-Warning "❌ Authentication failed. Token may be invalid or expired."
            # Optionally remove saved token if it's invalid
            $remove = Read-Host "🗑️ Remove saved token from Credential Manager? (y/n)"
            if ($remove -eq 'y') {
                & cmdkey /delete:$credentialName 2>$null
                Write-Host "🗑️ Saved token removed from Credential Manager" -ForegroundColor Yellow
            }
        } elseif ($_.Exception.Message -match "403") {
            Write-Warning "❌ Forbidden. Token may lack proper permissions (needs 'repo' scope)."
        } else {
            Write-Warning "❌ Failed to fetch repos: $($_.Exception.Message)"
        }
    }
}

# Helper function to remove saved token from Credential Manager
function gh-l-reset {
    $credentialName = "gh-l-github-token"
    try {
        $result = & cmdkey /delete:$credentialName 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "🗑️ GitHub token removed from Credential Manager" -ForegroundColor Green
        } else {
            Write-Host "ℹ️ No saved token found in Credential Manager" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "⚠️ Error removing token: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Helper function to check if token is saved
function gh-l-status {
    $credentialName = "gh-l-github-token"
    try {
        $result = & cmdkey /list:$credentialName 2>&1
        if ($LASTEXITCODE -eq 0 -and $result -match "GENERIC") {
            Write-Host "✅ GitHub token is saved in Credential Manager" -ForegroundColor Green
        } else {
            Write-Host "ℹ️ No GitHub token saved" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "ℹ️ No GitHub token saved" -ForegroundColor Yellow
    }
}








<#
.SYNOPSIS
    Nuclear Git reset - flush all changes and clean repository
.DESCRIPTION
    Performs a hard reset to HEAD, removes all untracked files, and fetches
    latest changes. Includes confirmation prompt for safety.
.EXAMPLE
    git-f     # Prompts for confirmation, then resets and cleans repo
#>
function git-f {
    $confirm = Read-Host "⚠️  Flush all changes and clean repo? (y/n)"
    if ($confirm -eq 'y') {
        Write-Host "🧹 Flushing..." -ForegroundColor Yellow
        git reset --hard HEAD        # Reset to last commit
        git clean -fdx              # Remove all untracked files and directories
        git fetch --all --prune     # Fetch latest and prune deleted branches
        Write-Host "✅ Repository cleaned and updated" -ForegroundColor Green
    } else {
        Write-Host "❌ Cancelled." -ForegroundColor DarkGray
    }
}

function git-branch {
    # Check if we're in a git repository
    if (-not (git rev-parse --git-dir 2>$null)) {
        Write-Host "❌ Not in a Git repository" -ForegroundColor Red
        return
    }

    # Get current branch
    $currentBranch = git branch --show-current
    
    # Get main branch name (main or master)
    $mainBranch = $null
    if (git show-ref --verify --quiet refs/heads/main) {
        $mainBranch = "main"
    } elseif (git show-ref --verify --quiet refs/heads/master) {
        $mainBranch = "master"
    }

    # Create branch list with simple markers (avoiding emoji encoding issues)
    $branches = @()
    git branch -a --format="%(refname:short)|%(HEAD)|local" | ForEach-Object {
        $parts = $_ -split '\|'
        $branchName = $parts[0]
        $isCurrent = $parts[1] -eq '*'
        $marker = if ($isCurrent) { "* " } else { "  " }
        $branches += [PSCustomObject]@{
            DisplayName = "$marker$branchName"
            ActualName = $branchName
            IsCurrent = $isCurrent
            IsRemote = $false
        }
    }

    # Add remote branches
    git branch -r --format="%(refname:short)" | Where-Object { $_ -notmatch '/HEAD' } | ForEach-Object {
        $branchName = $_
        $localName = $branchName -replace '^origin/', ''
        # Only add if no local branch exists with same name
        if ($branches.ActualName -notcontains $localName) {
            $branches += [PSCustomObject]@{
                DisplayName = "  $branchName (remote)"
                ActualName = $branchName
                IsCurrent = $false
                IsRemote = $true
            }
        }
    }

    # Use fzf to select branch
    $selected = $branches.DisplayName | fzf --reverse --height=40% --border --prompt="Select branch: " --header="↑↓ navigate, Enter to select, Esc to cancel"
    
    if (-not $selected) {
        Write-Host "No branch selected" -ForegroundColor DarkGray
        return
    }

    # Find the selected branch object
    $selectedBranch = $branches | Where-Object { $_.DisplayName -eq $selected }
    $branchName = $selectedBranch.ActualName
    $isRemote = $selectedBranch.IsRemote
    $isCurrent = $selectedBranch.IsCurrent

    # Copy branch name to clipboard (clean name without remote prefix for local operations)
    $cleanBranchName = $branchName -replace '^origin/', ''
    Set-Clipboard $cleanBranchName
    Write-Host "📋 Copied branch: $cleanBranchName" -ForegroundColor Green

    # Don't allow operations on current branch
    if ($isCurrent) {
        Write-Host "⚠️  Cannot perform operations on current branch" -ForegroundColor Yellow
        return
    }

    # Show action menu
    $actions = @(
        "1. Switch to branch",
        "2. Delete branch locally",
        "3. Delete branch remotely", 
        "4. Delete branch locally AND remotely",
        "5. Cancel"
    )
    
    Write-Host "`nAvailable actions:" -ForegroundColor Cyan
    $actions | ForEach-Object { Write-Host $_ -ForegroundColor White }
    $choice = Read-Host "`nSelect action (1-5)"

    switch ($choice) {
        "1" {
            # Switch to branch
            if ($isRemote) {
                $localName = $branchName -replace '^origin/', ''
                Write-Host "Creating local tracking branch: $localName" -ForegroundColor Yellow
                git checkout -b $localName $branchName
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "✅ Created and switched to local branch: $localName" -ForegroundColor Green
                }
            } else {
                git checkout $branchName
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "✅ Switched to branch: $branchName" -ForegroundColor Green
                }
            }
        }
        "2" {
            # Delete locally
            if ($isRemote) {
                Write-Host "⚠️  Cannot delete remote branch locally. Use option 3 or 4." -ForegroundColor Yellow
                return
            }
            Invoke-DeleteBranch -BranchName $branchName -Location "local" -MainBranch $mainBranch
        }
        "3" {
            # Delete remotely
            $remoteBranchName = if ($isRemote) { $branchName -replace '^origin/', '' } else { $branchName }
            Invoke-DeleteBranch -BranchName $remoteBranchName -Location "remote" -MainBranch $mainBranch
        }
        "4" {
            # Delete both
            $remoteBranchName = if ($isRemote) { $branchName -replace '^origin/', '' } else { $branchName }
            Invoke-DeleteBranch -BranchName $remoteBranchName -Location "both" -MainBranch $mainBranch
        }
        "5" {
            Write-Host "Cancelled" -ForegroundColor DarkGray
        }
        default {
            Write-Host "Invalid choice" -ForegroundColor Red
        }
    }
}

function Invoke-DeleteBranch {
    param(
        [string]$BranchName,
        [string]$Location, # "local", "remote", or "both"
        [string]$MainBranch
    )
    
    # Check if branches exist
    $localExists = git branch --list $BranchName | ForEach-Object { $_.Trim() -replace '^\*?\s*', '' } | Where-Object { $_ -eq $BranchName }
    $remoteExists = git branch -r --list "origin/$BranchName" | ForEach-Object { $_.Trim() -replace 'origin/', '' } | Where-Object { $_ -eq $BranchName }
    
    # Check if branch is merged into main
    $isMerged = $false
    if ($MainBranch -and $localExists) {
        try {
            $mergeBase = git merge-base $BranchName $MainBranch 2>$null
            $branchCommit = git rev-parse $BranchName 2>$null
            $isMerged = $mergeBase -eq $branchCommit
        } catch {
            # If we can't determine, assume not merged for safety
            $isMerged = $false
        }
    }

    # Show what exists
    Write-Host "`n📍 Branch status:" -ForegroundColor Cyan
    Write-Host "   Local: $(if ($localExists) { '✅ Exists' } else { '❌ Not found' })" -ForegroundColor $(if ($localExists) { 'Green' } else { 'Red' })
    Write-Host "   Remote: $(if ($remoteExists) { '✅ Exists' } else { '❌ Not found' })" -ForegroundColor $(if ($remoteExists) { 'Green' } else { 'Red' })

    # Adjust location based on what actually exists
    $originalLocation = $Location
    if ($Location -eq "both") {
        if (-not $localExists -and -not $remoteExists) {
            Write-Host "❌ Branch doesn't exist locally or remotely" -ForegroundColor Red
            return
        } elseif (-not $localExists) {
            $Location = "remote"
            Write-Host "ℹ️  Only remote branch exists, will delete remotely only" -ForegroundColor Yellow
        } elseif (-not $remoteExists) {
            $Location = "local"
            Write-Host "ℹ️  Only local branch exists, will delete locally only" -ForegroundColor Yellow
        }
    } elseif ($Location -eq "local" -and -not $localExists) {
        Write-Host "❌ Local branch doesn't exist" -ForegroundColor Red
        return
    } elseif ($Location -eq "remote" -and -not $remoteExists) {
        Write-Host "❌ Remote branch doesn't exist" -ForegroundColor Red
        return
    }

    # Show warnings
    Write-Host "`n⚠️  WARNING: You are about to DELETE branch '$BranchName'" -ForegroundColor Red
    
    if ($originalLocation -eq "both") {
        Write-Host "🔥 This will delete the branch BOTH locally AND remotely (where it exists)!" -ForegroundColor Red
    } elseif ($Location -eq "remote") {
        Write-Host "🌐 This will delete the branch from the remote repository!" -ForegroundColor Red
    } else {
        Write-Host "💻 This will delete the local branch!" -ForegroundColor Yellow
    }

    if (-not $isMerged -and $MainBranch -and $localExists) {
        Write-Host "🚨 DANGER: This branch does NOT appear to be merged into '$MainBranch'!" -ForegroundColor Red
        Write-Host "🚨 You may lose commits that exist only on this branch!" -ForegroundColor Red
    } elseif ($isMerged) {
        Write-Host "✅ Branch appears to be merged into '$MainBranch'" -ForegroundColor Green
    }

    # Final confirmation
    $confirmation = Read-Host "`nType 'DELETE' to confirm deletion, or anything else to cancel"
    
    if ($confirmation -ne "DELETE") {
        Write-Host "Deletion cancelled" -ForegroundColor Green
        return
    }

    # Perform deletion
    $localSuccess = $true
    $remoteSuccess = $true
    
    if (($Location -eq "local" -or $Location -eq "both") -and $localExists) {
        Write-Host "Deleting local branch..." -ForegroundColor Yellow
        if ($isMerged) {
            git branch -d $BranchName
        } else {
            git branch -D $BranchName  # Force delete unmerged branch
        }
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Local branch deleted successfully" -ForegroundColor Green
        } else {
            Write-Host "❌ Failed to delete local branch" -ForegroundColor Red
            $localSuccess = $false
        }
    }
    
    if (($Location -eq "remote" -or $Location -eq "both") -and $remoteExists) {
        Write-Host "Deleting remote branch..." -ForegroundColor Yellow
        git push origin --delete $BranchName
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Remote branch deleted successfully" -ForegroundColor Green
        } else {
            Write-Host "❌ Failed to delete remote branch" -ForegroundColor Red
            $remoteSuccess = $false
        }
    }
    
    # Final status
    $overallSuccess = $localSuccess -and $remoteSuccess
    if ($overallSuccess) {
        Write-Host "`n🎉 Branch deletion completed successfully!" -ForegroundColor Green
    } else {
        Write-Host "`n⚠️  Branch deletion completed with some issues (see details above)" -ForegroundColor Yellow
    }
}

<# 
.SYNOPSIS
    Shorthand alias for git-branch function
.DESCRIPTION
    Quick access to the interactive branch picker and manager
.EXAMPLE
    git-b
    # Same as git-branch
#>
function git-b {
    git-branch
}
<#
.SYNOPSIS
    Shorthand alias for git-pick function  
.DESCRIPTION
    Quick access to the interactive commit picker
.EXAMPLE
    git-p     # Same as git-pick
#>
function git-p {
    git-pick
}

<#
.SYNOPSIS
    Quick checkout to main branch
.DESCRIPTION
    Convenience function to quickly switch to the main branch
#>
function git-cm { 
    git checkout main 
    Write-Host "🔄 Switched to main branch" -ForegroundColor Cyan
}

<#
.SYNOPSIS
    Safe Git branch deletion with current branch protection
.DESCRIPTION
    Deletes a Git branch using -d flag (safe delete), but prevents
    deletion of the currently checked out branch
.PARAMETER branchName
    Name of the branch to delete
.EXAMPLE
    git-bd feature-branch     # Safely deletes 'feature-branch'
#>
function git-bd {
    param([Parameter(Mandatory = $true)][string]$branchName)
    
    # Get current branch for safety check
    $currentBranch = git rev-parse --abbrev-ref HEAD
    
    if ($branchName -eq $currentBranch) {
        Write-Host "⚠️  You are currently on '$branchName'. Switch to another branch before deleting." -ForegroundColor Yellow
        return
    }
    
    # Attempt safe deletion (only if merged)
    git branch -d $branchName
    if ($LASTEXITCODE -eq 0) {
        Write-Host "🗑 Deleted branch: $branchName" -ForegroundColor Green
    } else {
        Write-Host "❌ Could not delete branch: $branchName (not fully merged?)" -ForegroundColor Red
        Write-Host "💡 Use git-bD to force delete unmerged branches" -ForegroundColor DarkGray
    }
}

<#
.SYNOPSIS
    Force-delete a Git branch with safety checks
.DESCRIPTION
    Deletes a Git branch using -D flag (force delete), but first checks if you're
    currently on that branch to prevent accidental deletion of current branch.
.PARAMETER branchName
    Name of the branch to force delete
.EXAMPLE
    git-bD feature-branch     # Force deletes 'feature-branch' if not current
#>
function git-bD {
    param([Parameter(Mandatory = $true)][string]$branchName)

    # Get current branch name for safety check
    $currentBranch = git rev-parse --abbrev-ref HEAD

    # Prevent deletion of currently checked out branch
    if ($branchName -eq $currentBranch) {
        Write-Host "⚠️  You are currently on '$branchName'. Switch to another branch before force-deleting." -ForegroundColor Yellow
        return
    }

    # Attempt force deletion
    git branch -D $branchName
    if ($LASTEXITCODE -eq 0) {
        Write-Host "💥 Force-deleted branch: $branchName" -ForegroundColor Yellow
    } else {
        Write-Host "❌ Could not force delete branch: $branchName (may not exist)" -ForegroundColor Red
    }
}

<#
.SYNOPSIS
    Enhanced branch creation and switching with beautiful interface
.DESCRIPTION
    Multi-purpose branch function with beautiful fuzzy search interface:
    - No args: Interactive branch picker with enhanced formatting
    - One arg: Create/switch to branch
    - Two args: Create branch with suffix or from specific commit
.PARAMETER label
    Branch name or prefix
.PARAMETER suffixOrCommit
    Branch suffix or commit hash to branch from
.EXAMPLE
    git-c.sb                    # Beautiful interactive branch picker
    git-c.sb feature            # Create/switch to 'feature' branch
    git-c.sb feature auth       # Create/switch to 'feature-auth' branch
#>
function git-c.sb {
    param([string]$label, [string]$suffixOrCommit)
    
    # Interactive mode: beautiful fuzzy branch picker
    if (-not $label) {
        # Check if we're in a git repository
        if (-not (git rev-parse --git-dir 2>$null)) {
            Write-Host "❌ Not in a Git repository" -ForegroundColor Red
            return
        }

        # Get current branch for highlighting
        $currentBranch = git rev-parse --abbrev-ref HEAD

        # Get all branches with enhanced formatting
        git branch -a --format="%(refname:short)" |
            ForEach-Object {
                $branch = $_
                if ($branch -eq $currentBranch) {
                    "🌟 $branch (current)"
                } elseif ($branch -like "origin/*") {
                    "🌐 $branch"
                } elseif ($branch -like "remotes/*") {
                    "📡 $branch"
                } else {
                    "🌿 $branch"
                }
            } |
            fzf --ansi --reverse --height=50% --border --prompt="🔀 Switch Branch: " `
                --header="🌟 Current | 🌿 Local | 🌐 Remote | Enter: Switch | Esc: Cancel" |
            ForEach-Object {
                # Extract clean branch name
                $selected = $_ -replace '^[🌟🌐📡🌿]\s*', ''
                $selected = $selected -replace '\s*\(current\)$', ''
                $selected = $selected -replace '^origin/', ''
                
                if ($selected -and $selected -ne $currentBranch) {
                    git switch $selected
                    Write-Host "🔄 Switched to branch: $selected" -ForegroundColor Cyan
                } else {
                    Write-Host "❌ No branch change needed" -ForegroundColor DarkGray
                }
            }
        return
    }
    
    # Construct branch name
    $branchName = if ($suffixOrCommit) { "$label-$suffixOrCommit" } else { $label }
    
    # Check if branch already exists
    $exists = git branch --list $branchName
    
    if ($exists) {
        # Switch to existing branch
        git switch $branchName
        Write-Host "🔄 Switched to existing branch: $branchName" -ForegroundColor Cyan
    } else {
        # Create new branch
        if ($suffixOrCommit -match '^[a-f0-9]{6,40}$') {
            # Create from specific commit
            git checkout -b $branchName $suffixOrCommit
            Write-Host "🌿 Created from $suffixOrCommit and switched to: $branchName" -ForegroundColor Green
        } else {
            # Create from current HEAD
            git checkout -b $branchName
            Write-Host "🌿 Created and switched to new branch: $branchName" -ForegroundColor Green
        }
    }
}

<#
.SYNOPSIS
    Enhanced interactive Git log with beautiful formatting and actions
.DESCRIPTION
    Beautiful Git log viewer with fzf interface. Provides options to:
    - Copy commit hash to clipboard
    - Show full commit details
    - Create branch from selected commit
    - Cherry-pick commit
.EXAMPLE
    git-l     # Opens beautiful interactive log viewer
#>
function git-l {
    # Check if we're in a git repository
    if (-not (git rev-parse --git-dir 2>$null)) {
        Write-Host "❌ Not in a Git repository" -ForegroundColor Red
        return
    }

    # Simplified git log command - no preview to avoid Unix command issues
    git log --oneline --graph --all --decorate --color=always |
        fzf --ansi --reverse --height=70% --border --prompt="🔍 Git Log: " `
            --header="📋 Enter: Copy hash & choose action | Esc: Cancel" |
        ForEach-Object {
            # Extract commit hash more reliably
            if ($_ -match '\b([a-f0-9]{7,40})\b') {
                $hash = $matches[1]
                Set-Clipboard $hash
                Write-Host "📋 Copied commit hash: $hash" -ForegroundColor Green
                
                # Show the selected line for context
                Write-Host "📝 Selected: $_" -ForegroundColor DarkGray
                
                # Offer additional actions
                Write-Host "`n🔧 What would you like to do with this commit?" -ForegroundColor Cyan
                Write-Host "  1. Show full details (git show)" -ForegroundColor DarkGray
                Write-Host "  2. Create branch from this commit" -ForegroundColor DarkGray
                Write-Host "  3. Cherry-pick this commit" -ForegroundColor DarkGray
                Write-Host "  4. Nothing (just copied hash)" -ForegroundColor DarkGray
                
                $action = Read-Host "Choose action (1-4)"
                switch ($action) {
                    "1" { 
                        Write-Host "`n🔍 Showing commit details..." -ForegroundColor Cyan
                        git show $hash --color=always
                    }
                    "2" { 
                        $branchName = Read-Host "🌿 Enter new branch name"
                        if ($branchName) {
                            git checkout -b $branchName $hash
                            Write-Host "✅ Created and switched to branch: $branchName" -ForegroundColor Green
                        }
                    }
                    "3" { 
                        $confirm = Read-Host "🍒 Cherry-pick commit ${hash}? (y/n)"
                        if ($confirm -eq 'y') {
                            git cherry-pick $hash
                            if ($LASTEXITCODE -eq 0) {
                                Write-Host "🍒 Cherry-picked commit: $hash" -ForegroundColor Green
                            } else {
                                Write-Host "❌ Cherry-pick failed. Check for conflicts." -ForegroundColor Red
                            }
                        }
                    }
                    default { 
                        Write-Host "✅ Hash copied to clipboard" -ForegroundColor Green 
                    }
                }
            } else {
                Write-Host "❌ Could not extract commit hash from: $_" -ForegroundColor Red
            }
        }
}

function git-log {
    git-l
}





<#
.SYNOPSIS
    Interactive Git status with beautiful formatting and quick actions
.DESCRIPTION
    Beautiful git status viewer with interactive file staging/unstaging
.EXAMPLE
    git-s     # Opens interactive status viewer
#>
function git-s {
    # Check if we're in a git repository
    if (-not (git rev-parse --git-dir 2>$null)) {
        Write-Host "❌ Not in a Git repository" -ForegroundColor Red
        return
    }

    # Get git status with formatting
    git status --porcelain |
        ForEach-Object {
            $status = $_.Substring(0,2)
            $file = $_.Substring(3)
            
            switch ($status) {
                "??" { "❓ $file (untracked)" }
                " M" { "📝 $file (modified)" }
                "M " { "✅ $file (staged)" }
                "A " { "➕ $file (added)" }
                "D " { "🗑 $file (deleted)" }
                " D" { "❌ $file (deleted, unstaged)" }
                "R " { "🔄 $file (renamed)" }
                default { "📄 $file ($status)" }
            }
        } |
        fzf --ansi --reverse --height=60% --border --prompt="📊 Git Status: " `
            --header="Space: Stage/Unstage | Ctrl-D: Diff | Ctrl-R: Reset | Enter: Select | Esc: Cancel" `
            --multi |
        ForEach-Object {
            # Extract filename from formatted line
            $line = $_
            if ($line -match '^[📄📝✅➕🗑❌🔄❓]\s+(.+?)\s+\(') {
                $filename = $matches[1]
                Write-Host "📋 Selected: $filename" -ForegroundColor Green
                
                # Ask what to do with the file - FIXED: Use ${} to delimit variable
                Write-Host "`n🔧 Actions for ${filename}:" -ForegroundColor Cyan
                Write-Host "  1. Stage file (git add)" -ForegroundColor DarkGray
                Write-Host "  2. Unstage file (git reset)" -ForegroundColor DarkGray
                Write-Host "  3. Show diff" -ForegroundColor DarkGray
                Write-Host "  4. Discard changes" -ForegroundColor DarkGray
                
                $action = Read-Host "Choose action (1-4)"
                switch ($action) {
                    "1" { 
                        git add $filename
                        Write-Host "✅ Staged: $filename" -ForegroundColor Green
                    }
                    "2" { 
                        git reset HEAD $filename
                        Write-Host "📤 Unstaged: $filename" -ForegroundColor Yellow
                    }
                    "3" { 
                        git diff $filename --color=always | less -R
                    }
                    "4" {
                        $confirm = Read-Host "⚠️  Discard all changes to ${filename}? (y/n)"
                        if ($confirm -eq 'y') {
                            git checkout -- $filename
                            Write-Host "🗑 Discarded changes: $filename" -ForegroundColor Red
                        }
                    }
                }
            }
        }
}

# Shorthand alias
function git-st { git-s }

<#
.SYNOPSIS
    Interactive fuzzy Git commit hash picker that copies selected hash to clipboard
.DESCRIPTION
    Uses fzf to display a searchable, colorized git log with graph visualization.
    When a commit is selected, extracts and copies the commit hash to clipboard.
.EXAMPLE
    git-pick     # Opens fzf interface, select commit, hash copied to clipboard
#>
function git-pick {
    git log --oneline --all --graph --color=always |
        fzf --ansi --reverse |
        ForEach-Object {
            # Extract commit hash using regex pattern matching
            if ($_ -match '^\*? ?([a-f0-9]{7,40})') {
                Set-Clipboard $matches[1]
                Write-Host "📋 Copied commit: $($matches[1])" -ForegroundColor Green
            }
        }
}

<#
.SYNOPSIS
    Interactive Git stash manager with beautiful interface
.DESCRIPTION
    Beautiful git stash viewer with interactive stash management
.EXAMPLE
    git-stash     # Opens interactive stash manager
#>
function git-stash {
    # Check if we're in a git repository
    if (-not (git rev-parse --git-dir 2>$null)) {
        Write-Host "❌ Not in a Git repository" -ForegroundColor Red
        return
    }

    # Check if there are any stashes
    $stashes = git stash list
    if (-not $stashes) {
        Write-Host "📭 No stashes found" -ForegroundColor Yellow
        return
    }

    # Format stashes beautifully - PowerShell compatible version
    git stash list --color=always |
        fzf --ansi --reverse --height=50% --border --prompt="📦 Git Stash: " `
            --header="Enter: Apply | 1-4: Choose action | Esc: Cancel" |
        ForEach-Object {
            # Extract stash reference
            if ($_ -match '^(stash@\{\d+\})') {
                $stashRef = $matches[1]
                Write-Host "📦 Selected stash: $stashRef" -ForegroundColor Green
                
                Write-Host "`n🔧 Stash actions:" -ForegroundColor Cyan
                Write-Host "  1. Apply (keep stash)" -ForegroundColor DarkGray
                Write-Host "  2. Pop (apply and remove)" -ForegroundColor DarkGray
                Write-Host "  3. Show contents" -ForegroundColor DarkGray
                Write-Host "  4. Drop (delete)" -ForegroundColor DarkGray
                
                $action = Read-Host "Choose action (1-4)"
                switch ($action) {
                    "1" { 
                        git stash apply $stashRef
                        Write-Host "✅ Applied stash: $stashRef" -ForegroundColor Green
                    }
                    "2" { 
                        git stash pop $stashRef
                        Write-Host "📤 Popped stash: $stashRef" -ForegroundColor Green
                    }
                    "3" { 
                        git stash show -p $stashRef --color=always
                    }
                    "4" {
                        $confirm = Read-Host "⚠️  Drop stash $stashRef? (y/n)"
                        if ($confirm -eq 'y') {
                            git stash drop $stashRef
                            Write-Host "🗑 Dropped stash: $stashRef" -ForegroundColor Red
                        }
                    }
                }
            }
        }
}

<#
.SYNOPSIS
    Interactive Git remote manager
.DESCRIPTION
    Beautiful interface for managing Git remotes
.EXAMPLE
    git-remote     # Opens interactive remote manager
#>
function git-remote {
    # Check if we're in a git repository
    if (-not (git rev-parse --git-dir 2>$null)) {
        Write-Host "❌ Not in a Git repository" -ForegroundColor Red
        return
    }

    # Get remotes with URLs
    git remote -v |
        ForEach-Object {
            if ($_ -match '^(\w+)\s+(.+?)\s+\((fetch|push)\)') {
                $name = $matches[1]
                $url = $matches[2]
                $type = $matches[3]
                
                if ($type -eq "fetch") {
                    if ($url -match "github\.com") {
                        "🐙 $name → $url"
                    } elseif ($url -match "gitlab\.com") {
                        "🦊 $name → $url"
                    } elseif ($url -match "bitbucket\.org") {
                        "🪣 $name → $url"
                    } else {
                        "🌐 $name → $url"
                    }
                }
            }
        } |
        fzf --ansi --reverse --height=40% --border --prompt="🌐 Git Remotes: " `
            --header="Enter: Choose action | Esc: Cancel" |
        ForEach-Object {
            # Extract remote name
            if ($_ -match '^[🐙🦊🪣🌐]\s+(\w+)\s+→') {
                $remoteName = $matches[1]
                Write-Host "🌐 Selected remote: $remoteName" -ForegroundColor Green
                
                Write-Host "`n🔧 Remote actions:" -ForegroundColor Cyan
                Write-Host "  1. Fetch from remote" -ForegroundColor DarkGray
                Write-Host "  2. Push to remote" -ForegroundColor DarkGray
                Write-Host "  3. Show remote info" -ForegroundColor DarkGray
                Write-Host "  4. Set new URL" -ForegroundColor DarkGray
                
                $action = Read-Host "Choose action (1-4)"
                switch ($action) {
                    "1" { 
                        git fetch $remoteName
                        Write-Host "📥 Fetched from: $remoteName" -ForegroundColor Green
                    }
                    "2" { 
                        $branch = git rev-parse --abbrev-ref HEAD
                        git push $remoteName $branch
                        Write-Host "📤 Pushed to: $remoteName" -ForegroundColor Green
                    }
                    "3" { 
                        git remote show $remoteName
                    }
                    "4" {
                        $newUrl = Read-Host "Enter new URL for $remoteName"
                        if ($newUrl) {
                            git remote set-url $remoteName $newUrl
                            Write-Host "✅ Updated URL for: $remoteName" -ForegroundColor Green
                        }
                    }
                }
            }
        }
}

# Add shorthand aliases
function git-sh { git-stash }      # Shorthand for git stash
function git-r { git-remote }      # Shorthand for git remote

<#
.SYNOPSIS
    Deep clean Next.js project and reinstall dependencies
.DESCRIPTION
    Removes .next build directory, node_modules, and lockfile, then
    reinstalls all dependencies. Useful for resolving build issues.
.EXAMPLE
    git-next     # Prompts for confirmation, then cleans and reinstalls
#>
function git-next {
    $confirm = Read-Host "🧼 Deep clean .next + node_modules + lockfile and reinstall? (y/n)"
    if ($confirm -eq 'y') {
        Write-Host "`n🚿 Cleaning..." -ForegroundColor Cyan
        try {
            # Remove build artifacts and dependencies
            Remove-Item -Recurse -Force .next,node_modules,package-lock.json -ErrorAction Stop
            Write-Host "✅ Removed .next, node_modules, and lockfile." -ForegroundColor Green
        } catch {
            Write-Warning "⚠️ Some files may be locked or in use. Try closing editors and rerunning."
        }
        
        Write-Host "`n📦 Reinstalling dependencies..." -ForegroundColor Cyan
        npm install
        Write-Host "✅ Reinstall complete." -ForegroundColor Green
    } else {
        Write-Host "❌ Cancelled." -ForegroundColor DarkGray
    }
}

# ============================================================================
# WINDOWS TERMINAL TAB MANAGEMENT
# ============================================================================

<#
.SYNOPSIS
    Windows Terminal tab control utilities
.DESCRIPTION
    Functions for managing Windows Terminal tabs using SendKeys automation.
    Requires Windows Forms assembly for keyboard input simulation.
#>

# Load Windows Forms for SendKeys functionality
Add-Type -AssemblyName System.Windows.Forms

<#
.SYNOPSIS
    Send keyboard shortcuts to Windows Terminal
.PARAMETER keys
    Key combination string in SendKeys format
#>
function send-keys { 
    param([string]$keys)
    [System.Windows.Forms.SendKeys]::SendWait($keys) 
}

<#
.SYNOPSIS
    Open new Windows Terminal tab in current directory
.DESCRIPTION
    Creates a new tab in the current Windows Terminal window,
    starting in the same directory as the current tab
#>
function open-nt { 
    $cwd = Get-Location
    wt -w 0 nt --startingDirectory "$($cwd.Path)"
    Write-Host "🆕 Opened new tab in: $($cwd.Path)" -ForegroundColor Green
}

<#
.SYNOPSIS
    Close current terminal tab/session
#>
function close-ct { exit }

<#
.SYNOPSIS
    Switch to next terminal tab
.DESCRIPTION
    Uses Ctrl+Tab keyboard shortcut to cycle to next tab
#>
function next-t { 
    send-keys "^{TAB}"
    Write-Host "➡️ Switched to next tab" -ForegroundColor Cyan
}

<#
.SYNOPSIS
    Switch to previous terminal tab  
.DESCRIPTION
    Uses Ctrl+Shift+Tab keyboard shortcut to cycle to previous tab
#>
function prev-t { 
    send-keys "^+{TAB}"
    Write-Host "⬅️ Switched to previous tab" -ForegroundColor Cyan
}

<#
.SYNOPSIS
    Switch to specific terminal tab by index
.PARAMETER index
    Tab number (1-9) to switch to
.EXAMPLE
    open-t 3     # Switches to tab 3
#>
function open-t {
    param([int]$index)
    if ($index -lt 1 -or $index -gt 9) {
        Write-Host "❌ Tab index must be between 1–9" -ForegroundColor Red
        return
    }
    send-keys "%$index"  # Alt+Number shortcut
    Write-Host "🔀 Switched to tab $index" -ForegroundColor Cyan
}

<#
.SYNOPSIS
    Close specific terminal tab by index
.PARAMETER index
    Tab number (1-9) to close
.EXAMPLE
    close-t 2     # Switches to tab 2 then closes it
#>
function close-t {
    param([int]$index)
    if ($index -lt 1 -or $index -gt 9) {
        Write-Host "❌ Tab index must be between 1–9" -ForegroundColor Red
        return
    }
    send-keys "%$index"                # Switch to tab
    Start-Sleep -Milliseconds 100      # Brief pause
    send-keys "^+w"                    # Close tab shortcut
    Write-Host "🗑 Closed tab $index" -ForegroundColor Yellow
}

# ============================================================================
# CONFIGURATION FILE UTILITIES
# ============================================================================

<#
.SYNOPSIS
    Opens PowerShell profile in VS Code for editing
.DESCRIPTION
    Checks if the PowerShell profile exists and opens it in VS Code.
    Displays helpful feedback about the profile location.
.EXAMPLE
    pwsh-profile     # Opens $PROFILE in VS Code
#>
function pwsh-profile {
    if (Test-Path $PROFILE) {
        code $PROFILE
        Write-Host "📄 Opened PowerShell profile: $PROFILE" -ForegroundColor Cyan
    } else {
        Write-Host "⚠️ Profile does not exist at: $PROFILE" -ForegroundColor Yellow
    }
}

<#
.SYNOPSIS
    Opens Starship prompt configuration file in VS Code
.DESCRIPTION
    Locates and opens the starship.toml configuration file in the user's
    .config directory. Starship is a cross-shell prompt customization tool.
.EXAMPLE
    pwsh-starship     # Opens ~/.config/starship.toml in VS Code
#>
function pwsh-starship {
    $starshipPath = "$HOME\\.config\\starship.toml"

    if (Test-Path $starshipPath) {
        code $starshipPath
        Write-Host "🚀 Opened Starship config: $starshipPath" -ForegroundColor Cyan
    } else {
        Write-Host "❌ Could not find starship.toml at: $starshipPath" -ForegroundColor Red
    }
}

<#
.SYNOPSIS
    Opens Windows Terminal settings.json in VS Code
.DESCRIPTION
    Locates and opens the Windows Terminal configuration file for editing.
    This allows customization of terminal appearance, key bindings, and profiles.
.EXAMPLE
    pwsh-settings     # Opens Windows Terminal settings.json in VS Code
#>
function pwsh-settings {
    $wtSettings = "$env:LOCALAPPDATA\\Packages\\Microsoft.WindowsTerminal_8wekyb3d8bbwe\\LocalState\\settings.json"

    if (Test-Path $wtSettings) {
        code $wtSettings
        Write-Host "⚙️  Opened Windows Terminal settings.json" -ForegroundColor Cyan
    } else {
        Write-Host "❌ Could not find Windows Terminal settings.json" -ForegroundColor Red
    }
}


# ============================================================================
# POWERFLOW VERSION MANAGEMENT FUNCTIONS
# ============================================================================
# Add these functions to your Microsoft.PowerShell_profile.ps1

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
    PowerFlow recovery and diagnostics
.DESCRIPTION
    Provides recovery options when PowerFlow has issues
.EXAMPLE
    pwsh-recovery     # Shows recovery options
#>
function pwsh-recovery {
    Write-Host ""
    Write-Host "🚑 PowerFlow Recovery Options:" -ForegroundColor Red
    Write-Host "═══════════════════════════════" -ForegroundColor Red
    Write-Host ""
    Write-Host "🔄 Quick Fixes:" -ForegroundColor Cyan
    Write-Host "  1. Reload profile: . `$PROFILE" -ForegroundColor DarkGray
    Write-Host "  2. Check dependencies: Get-Command starship,fzf,zoxide,lsd,git" -ForegroundColor DarkGray
    Write-Host "  3. Reinstall tools: scoop install starship fzf zoxide lsd git" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "🔧 Recovery Actions:" -ForegroundColor Cyan
    Write-Host "  4. Reinstall PowerFlow: irm https://raw.githubusercontent.com/$script:POWERFLOW_REPO/main/install.ps1 | iex" -ForegroundColor DarkGray
    Write-Host "  5. Reset to safe mode: Remove-Item `$PROFILE; . `$PROFILE" -ForegroundColor DarkGray
    Write-Host "  6. Edit profile manually: code `$PROFILE" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "📋 Diagnostics:" -ForegroundColor Cyan
    Write-Host "  7. Version info: Get-PowerFlowVersion" -ForegroundColor DarkGray
    Write-Host "  8. Check for updates: powerflow-update" -ForegroundColor DarkGray
    Write-Host "  9. Full help: pwsh-h" -ForegroundColor DarkGray
    Write-Host ""
    
    $choice = Read-Host "Choose an option (1-9) or 'q' to quit"
    
    switch ($choice) {
        "1" { 
            Write-Host "🔄 Reloading profile..." -ForegroundColor Yellow
            . $PROFILE
        }
        "2" { 
            Write-Host "🔍 Checking dependencies..." -ForegroundColor Yellow
            $tools = @("starship", "fzf", "zoxide", "lsd", "git")
            foreach ($tool in $tools) {
                $found = Get-Command $tool -ErrorAction SilentlyContinue
                Write-Host "  $tool : $(if ($found) { '✅ Found' } else { '❌ Missing' })" -ForegroundColor $(if ($found) { 'Green' } else { 'Red' })
            }
        }
        "3" { 
            Write-Host "📦 Installing dependencies..." -ForegroundColor Yellow
            scoop install starship fzf zoxide lsd git
        }
        "4" { 
            Write-Host "🔄 Reinstalling PowerFlow..." -ForegroundColor Yellow
            irm "https://raw.githubusercontent.com/$script:POWERFLOW_REPO/main/install.ps1" | iex
        }
        "5" {
            $confirm = Read-Host "⚠️  Remove current profile? This will reset PowerFlow. (y/n)"
            if ($confirm -eq 'y') {
                Remove-Item $PROFILE -Force
                Write-Host "✅ Profile removed. Restart PowerShell to use default profile." -ForegroundColor Green
            }
        }
        "6" { 
            code $PROFILE
        }
        "7" { 
            Get-PowerFlowVersion
        }
        "8" { 
            powerflow-update
        }
        "9" { 
            pwsh-h
        }
        "q" { 
            Write-Host "👋 Recovery menu closed" -ForegroundColor DarkGray
        }
        default { 
            Write-Host "❌ Invalid option" -ForegroundColor Red
        }
    }
}





# ============================================================================
# COMPREHENSIVE HELP SYSTEM
# ============================================================================

<#
.SYNOPSIS
    Displays comprehensive help menu for all PowerShell shortcuts and functions
.DESCRIPTION
    Shows organized reference of all available aliases, functions, and shortcuts
    including navigation, file operations, Git commands, terminal management,
    and productivity utilities. Beautiful ASCII art formatting for readability.
.EXAMPLE
    pwsh-h     # Displays the complete help menu
#>
function pwsh-h {
    $helpText = @"

╔══════════════════════════════════════════════════════════════════════════════╗
║                    🐚 POWERSHELL COMMAND REFERENCE                           ║
║                         Enhanced Profile v6.0                                ║
╚══════════════════════════════════════════════════════════════════════════════╝

┌─ 🧭 SMART NAVIGATION & BOOKMARKS ────────────────────────────────────────────┐
│  🎯 CORE NAVIGATION:                                                         │
│  nav <project>       → smart project search in ~/Code and bookmarked dirs    │
│  nav -verbose        → detailed search output for troubleshooting            │
│  z <project>         → alias for nav                                         │
│                                                                              │
│  🔖 BOOKMARK MANAGEMENT:                                                     │
│  nav b <bookmark>    → navigate to bookmark                                  │
│  nav create-b <name> → create bookmark (current dir)                         │
│  nav cb <name>       → shorthand for create-b                                │
│  nav delete-b <name> → delete bookmark with confirmation                     │
│  nav db <name>       → shorthand for delete-b                                │
│  nav rename-b <old> <new> → rename existing bookmark                         │
│  nav rb <old> <new>  → shorthand for rename-b                                │
│  nav list            → interactive bookmark manager                          │
│  nav l               → shorthand for list                                    │
│                                                                              │
│  ⬆️ PARENT NAVIGATION:                                                       │
│  ..                  → go up one level (fast!)                               │
│  ...                 → go up two levels (fast!)                              │
│  ....                → go up three levels (fast!)                            │
│  ~                   → go to home directory                                  │
│                                                                              │
│  📍 LOCATION UTILITIES:                                                      │
│  here                → detailed info about current directory                 │
│  copy-pwd            → copy current path to clipboard                        │
│  open-pwd            → open current directory in File Explorer               │
│  op                  → alias for open-pwd                                    │
│  back                → go to previous directory                              │
│  cd-                 → alias for back                                        │
│  pwd                 → print working directory (alias)                       │
└───────────────────────────────────────────────────────────────────────────────┘

┌─ 📂 ENHANCED FILE OPERATIONS ────────────────────────────────────────────────┐
│  📋 DIRECTORY LISTING:                                                       │
│  ls [path]           → beautiful directory listing with lsd                  │
│  ls -t [path]        → tree view with smart depth detection                  │
│  ls -t -d <N> [path] → tree view with custom depth                           │
│  la                  → list all files including hidden                       │
│  ll                  → long list format with details                         │
│                                                                              │
│  📄 FILE VIEWING & SEARCH:                                                   │
│  cat <file>          → display file contents                                 │
│  grep <pattern>      → search text in files                                  │
│  less <file>         → page through file content                             │
│  which <cmd>         → show command location                                 │
│                                                                              │
│  🔧 FILE MANIPULATION:                                                       │
│  cp <src> <dst>      → copy files/directories                                │
│  touch <file>        → create new empty file                                 │
│  mkdir <dir>         → create new directory (strict naming rules)            │
│                                                                              │
│  ✂️ CUT-AND-PASTE FILE WORKFLOW:                                             │
│  mv <filename>       → 🎯 smart cut file for moving (supports fuzzy search)  │
│  mv-t                → paste cut file in current directory                   │
│  mv-c                → cancel move operation (drop held file)                │
│                                                                              │
│  🏷️ ENHANCED RENAME:                                                         │
│  rn [filename]       → 🎨 beautiful interactive rename with fuzzy search     │
│                                                                              │
│  🗑️ SMART FILE REMOVAL:                                                      │
│  rm <filename>       → 🎯 smart remove with fuzzy search                     │
│  rm <filename> -f    → force remove (hidden files, .git, etc.)               │
│  rmdir <path>        → enhanced directory removal with confirmations         │
│                                                                              │
│  📋 FILE CLIPBOARD OPERATIONS:                                               │
│  copy-file <file>    → copy file to clipboard for pasting                    │
│  cf <file>           → shorthand for copy-file                               │
│  paste-file [path]   → paste file from clipboard                             │
│  pf [path]           → shorthand for paste-file                              │
│  pf -Force [path]    → paste file with overwrite confirmation skip           │
└──────────────────────────────────────────────────────────────────────────────┘

┌─ 🎯 ENHANCED GIT WORKFLOW ───────────────────────────────────────────────────┐
│  🚀 ADD-COMMIT-PUSH WORKFLOW:                                                │
│  git-a               → 🎨 beautiful add → commit → push workflow             │
│  git-a-plus          → enhanced version with multiple modes:                 │
│    git-aq            → ⚡ quick mode (minimal prompts)                        │
│    git-ad            → 🔍 dry run mode (preview changes)                     │
│    git-am            → 🔄 amend last commit with new message                 │
│                                                                              │
│  🔄 ROLLBACK WORKFLOW:                                                       │
│  git-rb <commit>     → 🔄 create rollback branch from specific commit        │
│  git-rba             → 🚀 rollback branch add-commit-push (rollback-* only)  │
│  grba                → alias for git-rba                                     │
│                                                                              │
│  🔥 INTERACTIVE INTERFACES:                                                  │
│  git-l               → 🌟 beautiful interactive log viewer with actions      │
│  git-log             → alias for git-l                                       │
│  git-pick            → 🎯 commit hash picker (copies to clipboard)           │
│  git-p               → alias for git-pick                                    │
│  git-branch          → 🌿 beautiful branch picker with delete actions        │
│  git-b               → alias for git-branch                                  │
│  git-c.sb            → 🔀 enhanced branch creation/switching interface       │
│  git-s               → 📊 interactive status viewer with quick actions       │
│  git-st              → alias for git-s                                       │
│  git-stash           → 📦 interactive stash manager                          │
│  git-sh              → alias for git-stash                                   │
│  git-remote          → 🌐 interactive remote manager                          │
│  git-r               → alias for git-remote                                  │
│                                                                              │ 
│  🛠 UTILITY COMMANDS:                                                        │
│  git-f               → nuclear reset + clean + fetch (with confirmation)     │
│  git-cm              → quickly checkout main branch                          │
│  git-bd <branch>     → safe delete branch (prevents current branch)          │
│  git-bD <branch>     → force delete branch (with safety check)               │
│  git-next            → clean .next + node_modules + reinstall deps           │
│                                                                              │
│  🐙 GITHUB INTEGRATION:                                                      │
│  gh-l [count]        → 🚀 list your GitHub repos with activity stats         │
│  gh-l-reset          → remove saved GitHub token                             │
│  gh-l-status         → check if GitHub token is saved                        │
└──────────────────────────────────────────────────────────────────────────────┘

┌─ 🪟 TERMINAL TAB MANAGEMENT ─────────────────────────────────────────────────┐
│  open-nt             → open new Windows Terminal tab                         │
│  close-ct            → close current tab                                     │
│  next-t              → switch to next terminal tab                           │
│  prev-t              → switch to previous terminal tab                       │
│  open-t <N>          → switch to terminal tab N (1-9)                        │
│  close-t <N>         → switch to tab N then close it                         │
│  send-keys <keys>    → send keyboard shortcuts to terminal                   │
└──────────────────────────────────────────────────────────────────────────────┘



┌─ ⚙️  CONFIGURATION & SETTINGS ───────────────────────────────────────────────┐
│  pwsh-profile        → open PowerShell profile in VS Code                    │
│  pwsh-starship       → open Starship prompt config                           │
│  pwsh-settings       → open Windows Terminal settings.json                   │
│  pwsh-h              → show this help menu                                   │
│  pwsh-recovery       → PowerFlow recovery and diagnostics menu               │
│                                                                              │
│  🔄 VERSION MANAGEMENT:                                                      │
│  Get-PowerFlowVersion → detailed PowerFlow version and status info           │
│  powerflow-version   → quick version display                                 │
│  powerflow-update    → check for and install PowerFlow updates               │
└──────────────────────────────────────────────────────────────────────────────┘

┌─ 🔧 DEBUGGING & TESTING ─────────────────────────────────────────────────────┐
│  Test-NavFunction    → debug navigation search with detailed output          │
└──────────────────────────────────────────────────────────────────────────────┘

┌─ 🚀 KEY FEATURES ────────────────────────────────────────────────────────────┐
│  🎯 Smart File Operations → mv, rm, rn all support fuzzy search and patterns │
│  🔖 Persistent Bookmarks  → Saved across sessions in JSON file               │
│  ✂️ Cut-Paste Workflow   → mv cuts files, mv-t pastes, mv-c cancels          │
│  🔄 Git Rollback System  → Create rollback branches from any commit          │
│  🐙 GitHub Integration   → Browse, clone, delete repos with token security   │
│  🌟 Starship Prompt      → Beautiful, informative prompt with Git info       │
│  📋 Clipboard Integration → All interactive tools copy results to clipboard  │
│  🔍 Fuzzy Search         → Interactive pickers with fzf for everything       │
│  🛡️  Safety Checks       → Prevents accidental deletion and data loss        │
│  🎨 Beautiful UI         → Consistent emoji indicators and color schemes     │
│  ⚡ Context-Aware        → Tools adapt to current repository state            │
│  🌳 Git Integration      → Deep integration with Git workflows               │
└──────────────────────────────────────────────────────────────────────────────┘

📚 DOCUMENTATION: All functions include detailed help via Get-Help

"@
    
    Write-Host $helpText -ForegroundColor White
}

# ============================================================================
# STARTUP LOGGING & INITIALIZATION COMPLETE
# ============================================================================

<#
.SYNOPSIS
    Log PowerShell profile initialization for debugging and monitoring
.DESCRIPTION
    Appends timestamp and initialization message to log file for tracking
    profile loading and potential troubleshooting
#>

# Profile initialization complete
Write-Host "✅ PowerFlow profile loaded! Type " -NoNewline -ForegroundColor Green
Write-Host "pwsh-h" -NoNewline -ForegroundColor Yellow  
Write-Host " for help" -ForegroundColor Green