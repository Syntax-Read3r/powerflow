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
function Invoke-PFRenameFile {
    param(
        # -Chmod comes FIRST so that `rn --chmod 600` binds it rather than letting "600"
        # fall into the remaining-arguments filename. ValueFromRemainingArguments collects
        # everything not otherwise bound, which is exactly what would swallow it.
        [string]$Chmod,
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
    $overwriting = $false
    if (Test-Path $newPath) {
        Write-Host "⚠️ File already exists: $newFileName" -ForegroundColor Yellow
        $confirm = Read-Host "Overwrite existing file? (y/n)"
        if ($confirm -ne 'y' -and $confirm -ne 'Y') {
            Write-Host "↩ Cancelled." -ForegroundColor DarkGray
            return
        }
        $overwriting = $true
    }

    # ── Perform the rename ────────────────────────────────────────────────────
    #
    # TWO BUGS LIVED IN THE NEXT LINE, and together they made the approved-overwrite path
    # fail every single time while reporting success.
    #
    # 1. RENAME-ITEM CANNOT OVERWRITE, even with -Force. Measured: it throws an IOException
    #    ("Cannot create a file when that file already exists"). So the block above asked the
    #    user to approve an overwrite that the very next line was incapable of performing.
    #    Move-Item -Force can, and is the primitive this always needed.
    #
    # 2. WITHOUT -ErrorAction Stop, THAT FAILURE NEVER REACHED THE CATCH. Also measured: the
    #    error is non-terminating, so execution simply carried on into the green
    #    "RENAME COMPLETED" banner below. The user was told the rename worked, the original
    #    was still there under its old name, and the file they agreed to overwrite was
    #    untouched — and then, with -Chmod, the permission half applied itself to $newPath,
    #    which in that state is the VICTIM file rather than the renamed one.
    #
    # -ErrorAction Stop is the load-bearing half. Swapping the cmdlet without it would simply
    # move the silent failure to a different message.
    try {
        if ($overwriting) {
            Move-Item -LiteralPath $fileInfo.FullName -Destination $newPath -Force -ErrorAction Stop
        }
        else {
            Rename-Item -LiteralPath $fileInfo.FullName -NewName $newFileName -ErrorAction Stop
        }

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

        # ── PF-FEAT-001: the permission half ─────────────────────────────────
        # Applied to the NEW path. Using the old one would chmod a file that no longer
        # exists — silently, since chmod on a missing path is an error nobody reads.
        if ($Chmod) {
            $newPath = Join-Path $currentPath $newFileName
            $result = Set-FileMode -Path $newPath -Mode $Chmod

            if ($result.Success) {
                Write-Host "✅ Permissions" -ForegroundColor Green
                Write-Host "   $($result.Numeric)  $($result.Symbolic)" -ForegroundColor White
                Write-Host ""
            }
            elseif (-not $result.Supported) {
                # The rename SUCCEEDED. Say that first: reporting only the failure would
                # read as though nothing had happened at all.
                Write-Host "⚠️  Renamed, but permissions were not changed." -ForegroundColor Yellow
                Write-Host "   $($result.Error)" -ForegroundColor DarkGray
                Write-Host ""
            }
            else {
                # DO NOT roll the rename back. It is what the user asked for and it worked;
                # undoing it to "clean up" would destroy a completed action because a second
                # one failed. Report the partial success and hand over the exact command.
                Write-Host "❌ Renamed, but could not set permissions to $Chmod" -ForegroundColor Red
                Write-Host "   $($result.Error)" -ForegroundColor DarkGray
                Write-Host ""
                Write-Host "   Run:" -ForegroundColor Yellow
                Write-Host "     chmod $Chmod '$newPath'" -ForegroundColor Cyan
                Write-Host ""
            }
        }

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

# `rn` is a shim so `--chmod` binds: a param() block cannot bind a double-dash flag, and
# worse, misbinds it into the next value parameter — here that is the filename, so
# `rn --chmod 600` would have tried to rename a file called "--chmod".
function rn { Invoke-PFParamCommand -Target 'Invoke-PFRenameFile' -Command 'rn' -Argv $args }

# ── pwsh-h registration ───────────────────────────────────────────────────────
Register-PFCommand -Name 'rn' -Section '📂 ENHANCED FILE OPERATIONS' `
    -Synopsis 'interactive rename with fzf picker; --chmod sets the mode after (Linux)' `
    -Example 'rn draft.md · rn wg.conf --chmod 600'
