# ==============================================================================
# PowerFlow — File Rename
# ==============================================================================
# Domain   : Files
# File     : components/files/rename.ps1
# Purpose  : Interactive fuzzy-search file rename with a beautiful fzf interface
# Functions: rn
# Depends  : none
# ==============================================================================

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

# ── pwsh-h registration ───────────────────────────────────────────────────────
Register-PFCommand -Name 'rn' -Section '📂 ENHANCED FILE OPERATIONS' -Synopsis 'interactive rename with fzf picker' -Example 'rn draft.md'
