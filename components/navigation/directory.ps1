# ==============================================================================
# PowerFlow — Directory Utilities
# ==============================================================================
# Domain   : Navigation
# File     : components/navigation/directory.ps1
# Purpose  : Parent-directory shortcuts, home navigation, back, copy-pwd, and here command
# Functions: here, .., ..., ...., ....., ~, back, copy-pwd
# Depends  : components/navigation/nav.ps1
# ==============================================================================

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
# FAST PARENT DIRECTORY SHORTCUTS
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
    Copy-ToClipboard $path
    Write-Host "📋 Copied path: $path" -ForegroundColor Green
}

# ── pwsh-h registration ───────────────────────────────────────────────────────
Register-PFCommand -Name '..'       -Aliases @('...', '....', '.....') -Section '🧭 SMART NAVIGATION & BOOKMARKS' -Synopsis 'up one level (each extra dot goes one deeper)'
Register-PFCommand -Name 'here'     -Section '🧭 SMART NAVIGATION & BOOKMARKS' -Synopsis 'show where you are, with quick actions'
Register-PFCommand -Name 'back'     -Aliases @('cd-') -Section '🧭 SMART NAVIGATION & BOOKMARKS' -Synopsis 'return to the previous directory'
Register-PFCommand -Name '~'        -Section '🧭 SMART NAVIGATION & BOOKMARKS' -Synopsis 'go home'
Register-PFCommand -Name 'copy-pwd' -Section '🧭 SMART NAVIGATION & BOOKMARKS' -Synopsis 'copy the current path to the clipboard'
