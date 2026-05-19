# ==============================================================================
# PowerFlow — Navigation
# ==============================================================================
# Domain   : Navigation
# File     : components/navigation/nav.ps1
# Purpose  : Smart directory navigation with bookmark support and project search
# Functions: nav, Test-NavFunction
# Depends  : components/navigation/bookmarks.ps1, components/navigation/projects.ps1
# ==============================================================================

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

# Core navigation aliases
Set-Alias z nav                    # Main navigation function
# Set-Alias cd nav                   # Override cd with enhanced navigation
