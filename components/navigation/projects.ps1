# ==============================================================================
# PowerFlow — Projects Search
# ==============================================================================
# Domain   : Navigation
# File     : components/navigation/projects.ps1
# Purpose  : Recursively searches nested project directories within a base path
# Functions: Search-NestedProjects
# Depends  : none
# ==============================================================================

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
