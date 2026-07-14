# ==============================================================================
# PowerFlow — File Operations
# ==============================================================================
# Domain   : Files
# File     : components/files/operations.ps1
# Purpose  : Safe rm, cut-paste mv workflow, mv-t, mv-c, rmdir, touch, mkdir
# Functions: rm, mv, mv-t, mv-c, rmdir, touch, mkdir
# Depends  : none
# ==============================================================================

Remove-Item Alias:rm    -Force -ErrorAction SilentlyContinue
Remove-Item Alias:rmdir -Force -ErrorAction SilentlyContinue
Remove-Item Alias:mv    -Force -ErrorAction SilentlyContinue

function rm {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Name,
        [switch]$f
    )

    $targets = @()

    if ($Name -and $Name.Count -gt 0) {
        # Each argument is its own path pattern, so wildcards (rm *.log) and
        # multiple targets (rm a.txt b.txt) both work.
        foreach ($pattern in $Name) {
            $found = @(Get-Item -Path $pattern -Force -ErrorAction SilentlyContinue)
            if ($found.Count -gt 0) { $targets += $found }
        }

        # Nothing matched as a pattern. Retry the whole argument list as one
        # literal name — covers an unquoted filename with spaces ("rm my report.txt")
        # and names containing wildcard characters ("rm build[1].log").
        if ($targets.Count -eq 0) {
            $literal = $Name -join ' '
            $targets = @(Get-Item -LiteralPath $literal -Force -ErrorAction SilentlyContinue)
        }

        if ($targets.Count -eq 0) {
            Write-Warning "⚠️ File or directory not found: $($Name -join ' ')"
            return
        }
    }
    else {
        # No name given → use fzf to pick a file (if available)
        if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
            Write-Warning "fzf is not installed or not in PATH. Install it or call 'Remove-Item' directly."
            return
        }

        $selection = Get-ChildItem -Force | fzf --ansi --prompt "Select file/dir to delete: " | ForEach-Object {
            ($_ -split '\s+', 2)[-1]
        }

        if (-not $selection) {
            Write-Host "ℹ️ No selection made. Nothing deleted." -ForegroundColor DarkGray
            return
        }

        $targets = @(Get-Item -LiteralPath $selection -ErrorAction SilentlyContinue)
        if ($targets.Count -eq 0) {
            Write-Warning "⚠️ File or directory not found: $selection"
            return
        }
    }

    # Overlapping patterns (rm *.log *.txt a.log) can match the same item twice
    $targets = @($targets | Sort-Object -Property FullName -Unique)

    if (-not $f) {
        if ($targets.Count -eq 1) {
            $confirm = Read-Host "⚠️ Delete '$($targets[0].FullName)'? [y/N]"
        }
        else {
            Write-Host "⚠️ About to delete $($targets.Count) items:" -ForegroundColor Yellow
            foreach ($t in $targets) {
                $icon = if ($t.PSIsContainer) { "📁" } else { "📄" }
                Write-Host "   $icon $($t.FullName)" -ForegroundColor DarkGray
            }
            $confirm = Read-Host "⚠️ Delete all $($targets.Count) items? [y/N]"
        }

        if ($confirm -notin @('y','Y')) {
            Write-Host "❌ Deletion cancelled." -ForegroundColor Yellow
            return
        }
    }

    $deleted = 0
    foreach ($t in $targets) {
        try {
            Remove-Item -LiteralPath $t.FullName -Recurse -Force -ErrorAction Stop
            Write-Host "✅ Deleted: $($t.FullName)" -ForegroundColor Green
            $deleted++
        }
        catch {
            Write-Host "❌ Failed to delete '$($t.FullName)': $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    if ($targets.Count -gt 1) {
        Write-Host "🗑️  Deleted $deleted of $($targets.Count) items" -ForegroundColor Cyan
    }
}

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
