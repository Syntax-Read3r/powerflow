# ==============================================================================
# PowerFlow — File Listing
# ==============================================================================
# Domain   : Files
# File     : components/files/listing.ps1
# Purpose  : Enhanced ls using lsd with tree view, and common listing aliases
# Functions: ls, la, ll
# Depends  : none
# ==============================================================================

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
