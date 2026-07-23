# ==============================================================================
# PowerFlow — Bookmarks
# ==============================================================================
# Domain   : Navigation
# File     : components/navigation/bookmarks.ps1
# Purpose  : Persistent bookmark management — create, delete, rename, list, and navigate to bookmarks
# Functions: Initialize-DefaultBookmarks, Get-Bookmarks, Save-Bookmarks, Add-Bookmark, Remove-Bookmark, Rename-Bookmark, Show-BookmarkList
# Depends  : none
# ==============================================================================

$script:BookmarkFile = Join-Path (Get-HomePath) '.nav_bookmarks.json'

function Initialize-DefaultBookmarks {
    # Only create if file doesn't exist
    if (Test-Path $script:BookmarkFile) { return }

    $homeDir = Get-HomePath

    # Join-Path, never "$HOME\Code" — a hardcoded backslash produces the literal
    # path "/home/you\Code" on Linux, which of course never exists.
    $candidates = [ordered]@{
        "code"      = (Join-Path $homeDir 'Code')
        "documents" = (Join-Path $homeDir 'Documents')
        "docs"      = (Join-Path $homeDir 'Documents')
        "pictures"  = (Join-Path $homeDir 'Pictures')
        "pics"      = (Join-Path $homeDir 'Pictures')
        "downloads" = (Join-Path $homeDir 'Downloads')
        "download"  = (Join-Path $homeDir 'Downloads')
        "videos"    = (Join-Path $homeDir 'Videos')
    }

    # Bookmark only what exists. A headless server has no ~/Pictures and no ~/Code,
    # and a bookmark that points nowhere is worse than no bookmark at all.
    $defaultBookmarks = @{ "home" = $homeDir }
    foreach ($entry in $candidates.GetEnumerator()) {
        if (Test-Path $entry.Value) { $defaultBookmarks[$entry.Key] = $entry.Value }
    }

    $defaultBookmarks | ConvertTo-Json | Set-Content $script:BookmarkFile
    Write-Host "📚 Initialized $($defaultBookmarks.Count) default bookmarks" -ForegroundColor Green
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
