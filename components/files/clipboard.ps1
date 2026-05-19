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
        explorer.exe $currentPath

        Write-Host "📁 Opened File Explorer: $currentPath" -ForegroundColor Green

    } catch {
        Write-Host "❌ Failed to open File Explorer: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function op {
    open-pwd
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
