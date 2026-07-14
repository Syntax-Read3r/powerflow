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
        Write-Host ""
        Write-Host "  nav roots                    Show where nav searches" -ForegroundColor DarkGray
        Write-Host "  nav roots add <path>         Also search <path>  (e.g. /srv, /opt)" -ForegroundColor DarkGray
        Write-Host "  nav roots rm <path>          Stop searching <path>" -ForegroundColor DarkGray
        Write-Host "  nav roots reset              Back to the platform default" -ForegroundColor DarkGray
        Write-Host ""
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

    # ---- Search root management (nav roots ...) -------------------------------
    if ($command -eq "roots") {
        switch ($param1) {
            { $_ -in @("add", "a")          } { Add-NavSearchRoot    $param2; return }
            { $_ -in @("rm", "remove", "d") } { Remove-NavSearchRoot $param2; return }
            { $_ -in @("reset")             } { Reset-NavSearchRoots;         return }
            default                           { Show-NavSearchRoots;          return }
        }
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
    # Join-Path, never "$HOME\Code" — on Linux that string interpolates to the literal
    # path "/home/munya\Code" (backslash is a legal filename character there, not a
    # separator), so it silently never matches anything.
    $homeDir = Get-HomePath
    switch ($command) {
        "~"    { Set-Location $homeDir; Write-Host "🏠 $homeDir" -ForegroundColor Cyan; return }
        "home" { Set-Location $homeDir; Write-Host "🏠 $homeDir" -ForegroundColor Cyan; return }
        "code" {
            $codeDir = Join-Path $homeDir 'Code'
            if (Test-Path $codeDir) {
                Set-Location $codeDir
                Write-Host "💻 $(Format-NavPath $codeDir)" -ForegroundColor Cyan
            } else {
                Write-Host "❌ No Code directory at $codeDir" -ForegroundColor Red
                Write-Host "💡 Bookmark yours instead:  cd <dir>; nav cb code" -ForegroundColor DarkGray
            }
            return
        }
        "projects" {
            $projDir = Join-Path (Join-Path $homeDir 'Code') 'Projects'
            if (Test-Path $projDir) {
                Set-Location $projDir
                Write-Host "📂 $(Format-NavPath $projDir)" -ForegroundColor Cyan
            } else {
                Write-Host "❌ No Projects directory at $projDir" -ForegroundColor Red
                Write-Host "💡 Bookmark yours instead:  cd <dir>; nav cb projects" -ForegroundColor DarkGray
            }
            return
        }
    }

    # ---- Direct path ----------------------------------------------------------
    if (Test-Path $command -PathType Container) {
        Set-Location $command
        Write-Host "📁 $command" -ForegroundColor Green
        return
    }

    # ---- Determine search roots ------------------------------------------------
    # Normally: the configured roots (Linux defaults to ~, Windows to ~/Code).
    # But if the current directory sits inside a bookmark, that bookmark wins — it is
    # a far better guess at what you meant than a global scan. Deepest bookmark wins.
    $sep       = [IO.Path]::DirectorySeparatorChar
    $bookmarks = Get-Bookmarks
    $current   = $PWD.Path.TrimEnd($sep)

    # Case-insensitive on Windows, case-SENSITIVE on Linux — /home/Foo and /home/foo
    # are genuinely different directories there.
    $cmp = if ($script:PowerFlowOS -eq 'windows') { [StringComparison]::OrdinalIgnoreCase }
           else                                   { [StringComparison]::Ordinal }

    $contextRoot  = $null
    $longestMatch = 0
    foreach ($bm in $bookmarks.GetEnumerator()) {
        $bmPath = ([string]$bm.Value).TrimEnd($sep)
        if (-not $bmPath -or $bmPath -eq $homeDir.TrimEnd($sep)) { continue }  # ~ is not "context"
        $isUnder = $current.Equals($bmPath, $cmp) -or $current.StartsWith($bmPath + $sep, $cmp)
        if ($isUnder -and $bmPath.Length -gt $longestMatch) {
            $longestMatch = $bmPath.Length
            $contextRoot  = $bm.Value
        }
    }

    $searchRoots = if ($contextRoot) { @($contextRoot) } else { @(Get-NavSearchRoots) }

    if ($verbose) {
        Write-Host "📂 Search roots: $($searchRoots -join ', ')" -ForegroundColor Cyan
        if ($contextRoot) { Write-Host "   (context: you are inside bookmark '$contextRoot')" -ForegroundColor DarkGray }
    }

    # Join all supplied positional words into one query string so that
    # "nav source code" passes "source code" to fzf rather than just "source".
    $query = (@($command, $param1, $param2) | Where-Object { $_ }) -join ' '

    # ---- Fuzzy search via fzf (primary path) ----------------------------------
    if (Get-Command fzf -ErrorAction SilentlyContinue) {

        # Map the string fzf shows -> the full path to cd into. Building the map here
        # (rather than re-joining the selection against a root afterwards) is what makes
        # multiple roots possible at all: two roots can hold the same relative path.
        $map = [ordered]@{}
        $multi = $searchRoots.Count -gt 1

        foreach ($root in $searchRoots) {
            foreach ($rel in (Search-Projects -BaseDir $root -MaxDepth 4 -All -Verbose:$verbose)) {
                $full    = Join-Path $root $rel
                $display = if ($multi) { Format-NavPath $full } else { $rel }
                if (-not $map.Contains($display)) { $map[$display] = $full }
            }
        }

        if ($map.Count -eq 0) {
            Write-Host "❌ No directories found in: $($searchRoots -join ', ')" -ForegroundColor Red
            Write-Host "💡 Point nav somewhere else:  nav roots add <path>" -ForegroundColor DarkGray
            return
        }

        $rootLabel = ($searchRoots | ForEach-Object { Format-NavPath $_ }) -join ', '

        $selected = $map.Keys | fzf `
            --query         $query `
            --select-1 `
            --exit-0 `
            --reverse `
            --border=rounded `
            --height=60% `
            --prompt="📁 Navigate: " `
            --header="🧭 PowerFlow  $($map.Count) dirs · 4 levels · $rootLabel — Enter to go, Esc to cancel" `
            --header-first `
            --color="header:bold:cyan,prompt:bold:green,border:cyan,spinner:yellow"

        if ($selected) {
            $fullPath = $map[$selected.Trim()]
            Set-Location $fullPath
            Write-Host "🎯 $([System.IO.Path]::GetFileName($fullPath))" -ForegroundColor Green
            Write-Host "📍 $(Format-NavPath $fullPath)" -ForegroundColor DarkGray
        } else {
            # User pressed Esc or no fuzzy match survived
            Write-Host "❌ Cancelled" -ForegroundColor DarkGray
        }

        return
    }

    # ---- Fallback: BFS best-match (when fzf is not available) ----------------
    $result = $null
    foreach ($root in $searchRoots) {
        $result = Search-Projects -Name $query -BaseDir $root -MaxDepth 4 -Verbose:$verbose
        if ($result) { break }
    }

    if ($result) {
        Set-Location $result
        Write-Host "🎯 $([System.IO.Path]::GetFileName($result))" -ForegroundColor Green
        Write-Host "📍 $(Format-NavPath $result)" -ForegroundColor DarkGray
    } else {
        Write-Host "❌ No project matching '$query' found" -ForegroundColor Red
        Write-Host "   Searched 4 levels deep in: $(($searchRoots | ForEach-Object { Format-NavPath $_ }) -join ', ')" -ForegroundColor DarkGray
        Write-Host "💡 Search elsewhere:  nav roots add <path>" -ForegroundColor DarkGray
        Write-Host "💡 Install fzf for fuzzy search: $(Get-DependencyInstallHint 'fzf')" -ForegroundColor DarkGray
    }
}

function Test-NavFunction {
    param([string]$path = $null)

    Write-Host "=== NAV DEBUG ===" -ForegroundColor Cyan
    Write-Host "Platform: $script:PowerFlowOS   Separator: '$([IO.Path]::DirectorySeparatorChar)'   Home: $(Get-HomePath)" -ForegroundColor DarkGray

    Show-NavSearchRoots

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
