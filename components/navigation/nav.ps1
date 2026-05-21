# ==============================================================================
# PowerFlow — Navigation
# ==============================================================================
# Domain   : Navigation
# File     : components/navigation/nav.ps1
# Purpose  : Smart project navigation with bookmark support and fzf fuzzy search
# Functions: nav, Test-NavFunction
# Depends  : components/navigation/bookmarks.ps1, components/navigation/projects.ps1
# ==============================================================================

function nav {
    param(
        [string]$command = $null,
        [string]$param1  = $null,
        [string]$param2  = $null,
        [switch]$verbose
    )

    Initialize-DefaultBookmarks

    # ---- No command: show help ------------------------------------------------
    if (-not $command) {
        Write-Host "💡 Navigation Commands:" -ForegroundColor Cyan
        Write-Host "═════════════════════" -ForegroundColor Cyan
        Write-Host "  nav <name>                   Fuzzy-find & go to project (4 levels deep)" -ForegroundColor DarkGray
        Write-Host "  nav b <bookmark>             Navigate to bookmark" -ForegroundColor DarkGray
        Write-Host "  nav create-b <name> | cb     Create bookmark at current dir" -ForegroundColor DarkGray
        Write-Host "  nav delete-b <name> | db     Delete bookmark" -ForegroundColor DarkGray
        Write-Host "  nav rename-b <old> <new>     Rename bookmark" -ForegroundColor DarkGray
        Write-Host "  nav list | l                 Interactive bookmark manager" -ForegroundColor DarkGray
        Write-Host "  Use -verbose for detailed search output" -ForegroundColor DarkGray
        return
    }

    if ($verbose) {
        Write-Host "🔎 nav: command='$command' param1='$param1' param2='$param2'" -ForegroundColor Yellow
    }

    # ---- Bookmark management --------------------------------------------------
    switch ($command) {
        { $_ -in @("create-b", "cb") } { Add-Bookmark    $param1;         return }
        { $_ -in @("delete-b", "db") } { Remove-Bookmark  $param1;         return }
        { $_ -in @("rename-b", "rb") } { Rename-Bookmark  $param1 $param2; return }
        { $_ -in @("list",     "l")  } { Show-BookmarkList;                 return }
    }

    # ---- Bookmark navigation (nav b <name>) -----------------------------------
    if ($command -eq "b") {
        if (-not $param1) {
            Write-Host "❌ Usage: nav b <bookmark-name>" -ForegroundColor Red
            return
        }
        $bookmarks = Get-Bookmarks
        $key = $param1.ToLower()
        if ($bookmarks.ContainsKey($key)) {
            $bmPath = $bookmarks[$key]
            if (Test-Path $bmPath) {
                Set-Location $bmPath
                Write-Host "📌 $param1 → $bmPath" -ForegroundColor Green
            } else {
                Write-Host "❌ Bookmark path no longer exists: $bmPath" -ForegroundColor Red
                Write-Host "💡 Remove with: nav delete-b $param1" -ForegroundColor DarkGray
            }
        } else {
            Write-Host "❌ Bookmark '$param1' not found" -ForegroundColor Red
            Write-Host "💡 See all bookmarks: nav list" -ForegroundColor DarkGray
        }
        return
    }

    # ---- Built-in shortcuts ---------------------------------------------------
    switch ($command) {
        "~"        { Set-Location $HOME;                 Write-Host "🏠 Home"            -ForegroundColor Cyan; return }
        "code"     { Set-Location "$HOME\Code";          Write-Host "💻 ~/Code"          -ForegroundColor Cyan; return }
        "projects" { Set-Location "$HOME\Code\Projects"; Write-Host "📂 ~/Code/Projects" -ForegroundColor Cyan; return }
    }

    # ---- Direct path ----------------------------------------------------------
    if (Test-Path $command -PathType Container) {
        Set-Location $command
        Write-Host "📁 $command" -ForegroundColor Green
        return
    }

    # ---- Determine search root ------------------------------------------------
    # Default: the "code" bookmark (~\Code).
    # If the current directory is inside a different (more specific) bookmark,
    # use that bookmark's root so nav stays contextual.
    $bookmarks  = Get-Bookmarks
    $searchRoot = if ($bookmarks["code"] -and (Test-Path $bookmarks["code"])) {
                      $bookmarks["code"]
                  } else {
                      "$HOME\Code"
                  }

    $currentPath  = $PWD.Path
    $longestMatch = $searchRoot.TrimEnd('\').Length

    foreach ($bm in $bookmarks.GetEnumerator()) {
        if ($bm.Key -eq "code") { continue }
        $bmPath  = $bm.Value.TrimEnd('\')
        $isUnder = $currentPath.Equals($bmPath, [StringComparison]::OrdinalIgnoreCase) -or
                   $currentPath.StartsWith($bmPath + '\', [StringComparison]::OrdinalIgnoreCase)
        if ($isUnder -and $bmPath.Length -gt $longestMatch) {
            $longestMatch = $bmPath.Length
            $searchRoot   = $bm.Value
        }
    }

    if ($verbose) { Write-Host "📂 Search root: $searchRoot" -ForegroundColor Cyan }

    # Join all supplied positional words into one query string so that
    # "nav source code" passes "source code" to fzf rather than just "source".
    $query = (@($command, $param1, $param2) | Where-Object { $_ }) -join ' '

    # ---- Fuzzy search via fzf (primary path) ----------------------------------
    if (Get-Command fzf -ErrorAction SilentlyContinue) {

        # Collect all traversable directories as relative paths
        $candidates = Search-Projects -BaseDir $searchRoot -MaxDepth 4 -All -Verbose:$verbose

        if (-not $candidates -or $candidates.Count -eq 0) {
            Write-Host "❌ No directories found in $searchRoot" -ForegroundColor Red
            return
        }

        $selected = $candidates | fzf `
            --query         $query `
            --select-1 `
            --exit-0 `
            --reverse `
            --border=rounded `
            --height=60% `
            --prompt="📁 Navigate: " `
            --header="🧭 PowerFlow  ($($candidates.Count) dirs, 4 levels) — press Enter to go, Esc to cancel" `
            --header-first `
            --color="header:bold:cyan,prompt:bold:green,border:cyan,spinner:yellow"

        if ($selected) {
            $fullPath = Join-Path $searchRoot $selected.Trim()
            Set-Location $fullPath
            Write-Host "🎯 $([System.IO.Path]::GetFileName($fullPath))" -ForegroundColor Green
            Write-Host "📍 $fullPath" -ForegroundColor DarkGray
        } else {
            # User pressed Esc or no fuzzy match survived
            Write-Host "❌ Cancelled" -ForegroundColor DarkGray
        }

        return
    }

    # ---- Fallback: BFS best-match (when fzf is not available) ----------------
    $result = Search-Projects -Name $query -BaseDir $searchRoot -MaxDepth 4 -Verbose:$verbose

    if ($result) {
        Set-Location $result
        Write-Host "🎯 $([System.IO.Path]::GetFileName($result))" -ForegroundColor Green
        Write-Host "📍 $result" -ForegroundColor DarkGray
    } else {
        Write-Host "❌ No project matching '$query' found" -ForegroundColor Red
        Write-Host "   Searched 4 levels deep in: $searchRoot" -ForegroundColor DarkGray
        Write-Host "💡 Install fzf for fuzzy search: scoop install fzf" -ForegroundColor DarkGray
    }
}

function Test-NavFunction {
    param([string]$path = $null)

    Write-Host "=== NAV DEBUG ===" -ForegroundColor Cyan

    $bookmarks = Get-Bookmarks
    Write-Host "Bookmarks:" -ForegroundColor Yellow
    $bookmarks.GetEnumerator() | Sort-Object Key | ForEach-Object {
        $ok = Test-Path $_.Value
        Write-Host "  $(if ($ok) { '✅' } else { '❌' }) $($_.Key) → $($_.Value)" `
            -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
    }

    Write-Host ""
    Write-Host "fzf available: $(if (Get-Command fzf -ErrorAction SilentlyContinue) { '✅' } else { '❌' })" -ForegroundColor Yellow

    if ($path) {
        Write-Host ""
        nav $path -verbose
    }
}

Set-Alias z nav
