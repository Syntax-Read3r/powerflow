# ==============================================================================
# PowerFlow — File Clipboard
# ==============================================================================
# Domain   : Files
# File     : components/files/clipboard.ps1
# Purpose  : Copy and paste files via clipboard, open current directory in Explorer
# Functions: open-pwd, op, paste-file, copy-file, cf, pf
# Depends  : none
# ==============================================================================

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
        Open-Path $currentPath

        Write-Host "📁 Opened File Explorer: $currentPath" -ForegroundColor Green

    } catch {
        Write-Host "❌ Failed to open File Explorer: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function op {
    open-pwd
}

function Invoke-PFPasteFile {
    param(
        [switch]$Force,
        [string]$Path = (Get-Location).Path
    )

    try {
        # Get clipboard content as text (file path stored by copy-file with 'FILE:' prefix)
        $clipboardContent = Get-FromClipboard

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

        # ── Copy the file ─────────────────────────────────────────────────────
        #
        # -ErrorAction Stop, because Copy-Item fails NON-TERMINATINGLY: without it a failed
        # copy walks straight past the catch into the "✅ Pasted" banner below.
        #
        # This one was worse than an ordinary false success, because the next two lines
        # CORROBORATE it. When the destination already existed, `Get-Item $destinationPath`
        # finds the OLD file and the "📊 Size" line prints its size — a plausible number
        # beside a green tick, describing a file that was never written. A false success that
        # shows evidence is far harder to disbelieve than a bare one.
        #
        # Verified by comparing length against the source afterwards, rather than trusting a
        # silent return: this is a data operation, and the house rule is to read state back.
        Copy-Item -Path $sourceFile -Destination $destinationPath -Force -ErrorAction Stop

        $copiedFile = Get-Item -LiteralPath $destinationPath -ErrorAction Stop
        $sourceItem = Get-Item -LiteralPath $sourceFile -ErrorAction SilentlyContinue
        if ($sourceItem -and -not $sourceItem.PSIsContainer -and $copiedFile.Length -ne $sourceItem.Length) {
            throw "Copy reported no error, but $destinationPath is $($copiedFile.Length) bytes and the source is $($sourceItem.Length)"
        }

        Write-Host "✅ Pasted: $fileName" -ForegroundColor Green
        Write-Host "   📍 Location: $destinationPath" -ForegroundColor Cyan
        Write-Host "   📊 Size: $([math]::Round($copiedFile.Length / 1KB, 2)) KB" -ForegroundColor Cyan

    } catch {
        Write-Host "❌ Error pasting file: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ── paste-file ──────────────────────────────────────────────────────────
# The user-facing name is a shim so that --long flags bind at all: a param() block
# cannot bind them, and worse, misbinds them into the next value parameter. The shim
# must not declare param() of its own, or $args would not hold the whole line.
# See docs/plan/ethos/ETHOS.md.
function paste-file { Invoke-PFParamCommand -Target 'Invoke-PFPasteFile' -Command 'paste-file' -Argv $args }

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
        Copy-ToClipboard "FILE:$fullPath"

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

# `pf` is the short name for the same command, so it shims onto the same implementation
# rather than forwarding through `paste-file`. Forwarding would have gone through the shim
# and reported `-Force` as a legacy spelling the user never typed. The Path/no-Path branch
# is gone too: an absent value parameter simply is not passed, which is what the branch was
# emulating.
function pf { Invoke-PFParamCommand -Target 'Invoke-PFPasteFile' -Command 'pf' -Argv $args }

# ── pwsh-h registration ───────────────────────────────────────────────────────
Register-PFCommand -Name 'open-pwd'   -Aliases @('op') -Section '📂 ENHANCED FILE OPERATIONS' -Synopsis 'open the current folder in the file manager'
Register-PFCommand -Name 'copy-file'  -Aliases @('cf') -Section '📂 ENHANCED FILE OPERATIONS' -Synopsis 'copy a file to the clipboard (fzf picker)'
Register-PFCommand -Name 'paste-file' -Aliases @('pf') -Section '📂 ENHANCED FILE OPERATIONS' -Synopsis 'paste the clipboard file into this folder'
