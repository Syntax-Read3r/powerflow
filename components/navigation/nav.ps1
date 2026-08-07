# ==============================================================================
# PowerFlow — Navigation
# ==============================================================================
# Domain   : Navigation
# File     : components/navigation/nav.ps1
# Purpose  : Smart project navigation with bookmark support and fzf fuzzy search
# Functions: nav, Test-NavFunction
# Depends  : components/navigation/bookmarks.ps1, components/navigation/projects.ps1
# ==============================================================================

# ==============================================================================
# WHY nav HAND-PARSES $args INSTEAD OF USING param()
#
# `nav -srv complete` could never work with a param() block: PowerShell tries to bind
# -srv as a PARAMETER NAME, finds no match, and the token never reaches the body — nav
# simply printed its help. This is the identical trap documented for `rm -rf` in
# COMPONENTS.md footnote 5, and the reason `ls` has no param() block either.
#
# Hand-parsing $args is the only way a PowerShell function can accept user-invented flags.
# ==============================================================================
function nav {
    Initialize-DefaultBookmarks

    $verbose    = $false
    $anchorVerb = $false
    $rootKey    = ''
    $words      = @()

    foreach ($argument in $args) {
        $token = "$argument"
        if ($token -in @('-verbose', '-v')) { $verbose = $true; continue }
        # --anchor is a VERB, not a starting point, so it is caught before the -<root> lookup.
        # --start-repo is accepted because that is what the owner first reached for.
        if ($token -in @('--anchor', '-anchor', '--start-repo')) { $anchorVerb = $true; continue }
        if ($token.StartsWith('-', [StringComparison]::Ordinal) -and $token.Length -gt 1) {
            $canonical = Resolve-PFRootAlias $token
            if ($canonical) { $rootKey = $canonical; continue }
            # An unknown -token is NOT silently swallowed. A mistyped starting point would
            # otherwise search the default roots and read as "that directory doesn't exist".
            Write-Host "❌ Unknown starting point '$token'." -ForegroundColor Red
            Write-Host "   Available:  $((Get-PFNamedRoots).Keys -join ' · ')" -ForegroundColor DarkGray
            Write-Host '   See them with their paths:  nav roots' -ForegroundColor DarkGray
            return
        }
        $words += $token
    }

    $command = if ($words.Count -ge 1) { $words[0] } else { $null }
    $param1  = if ($words.Count -ge 2) { $words[1] } else { $null }
    $param2  = if ($words.Count -ge 3) { $words[2] } else { $null }

    # ---- nav --anchor <path> <name>   ( '.' means here, as in `code .` ) -------
    if ($anchorVerb) {
        Add-PFAnchor -Path $(if ($words.Count -ge 1) { $words[0] } else { '' }) `
                     -Name $(if ($words.Count -ge 2) { $words[1] } else { '' })
        return
    }

    # ---- nav anchors [rm <name>] ----------------------------------------------
    if ($words.Count -and $words[0] -in @('anchors', 'anchor')) {
        if ($words.Count -ge 2 -and $words[1] -in @('rm', 'remove', 'd', 'delete')) {
            Remove-PFAnchor -Name $(if ($words.Count -ge 3) { $words[2] } else { '' })
            return
        }
        Show-PFAnchors
        return
    }

    # ---- Nothing at all: show help --------------------------------------------
    if (-not $command -and -not $rootKey) {
        $choices = Get-PFRootChoices
        Write-Host ''
        Write-Host '🧭 nav — go somewhere without typing a path' -ForegroundColor Cyan
        Write-Host '  nav <name>              fuzzy-find a directory, 4 levels deep' -ForegroundColor White
        Write-Host '  nav -<start> <name>     search from a named starting point' -ForegroundColor White
        Write-Host '  nav -<start>            go straight to that starting point' -ForegroundColor White
        Write-Host '  nav <path>              a real path still just works' -ForegroundColor White
        Write-Host ''
        Write-Host '  Starting points on this machine:' -ForegroundColor DarkGray
        foreach ($key in $choices.Keys) {
            $c = $choices[$key]
            $alias = if (@($c.Aliases).Count) { "   also -$(@($c.Aliases) -join ' -')" } else { '' }
            Write-Host ("    -{0,-11} {1}{2}" -f $c.Name, (Format-NavPath @($c.Paths)[0]), $alias) -ForegroundColor DarkGray
        }
        Write-Host ''
        Write-Host '  nav b <name>            jump to a bookmark' -ForegroundColor White
        Write-Host '  nav b .                 bookmark the directory you are in' -ForegroundColor White
        Write-Host '  nav list                manage bookmarks (Enter go · ctrl-d delete)' -ForegroundColor White
        Write-Host '  nav cb <name> · nav db <name> · nav rb <old> <new>' -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '  nav roots               where a bare nav searches, and every starting point' -ForegroundColor White
        Write-Host '  nav roots add <path>    also search <path>' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    if ($verbose) {
        Write-Host "🔎 nav: root='$rootKey' words=[$($words -join ', ')]" -ForegroundColor Yellow
    }

    # ---- Bookmark management --------------------------------------------------
    switch ($command) {
        { $_ -in @('create-b', 'cb') } { Add-Bookmark    $param1;         return }
        { $_ -in @('delete-b', 'db') } { Remove-Bookmark $param1;         return }
        { $_ -in @('rename-b', 'rb') } { Rename-Bookmark $param1 $param2; return }
        { $_ -in @('list',     'l')  } { Show-BookmarkList;               return }
    }

    # ---- Search root management (nav roots ...) -------------------------------
    if ($command -eq 'roots') {
        switch ($param1) {
            { $_ -in @('add', 'a')          } { Add-NavSearchRoot    $param2; return }
            { $_ -in @('rm', 'remove', 'd') } { Remove-NavSearchRoot $param2; return }
            { $_ -in @('reset')             } { Reset-NavSearchRoots;         return }
            default {
                Show-NavSearchRoots
                Write-Host '🎯 Named starting points   (nav -<name> · ls -<name>)' -ForegroundColor Cyan
                $choices = Get-PFRootChoices
                foreach ($key in $choices.Keys) {
                    $c = $choices[$key]
                    $alias = if (@($c.Aliases).Count) { "   also -$(@($c.Aliases) -join ' -')" } else { '' }
                    Write-Host ("  -{0,-11} {1}{2}" -f $c.Name, (@($c.Paths) -join ', '), $alias) -ForegroundColor DarkGray
                }
                Write-Host ''
                return
            }
        }
    }

    # ---- Bookmarks: `nav b <name>`, and `nav b .` to bookmark where you are ----
    if ($command -eq 'b') {
        # `nav b .` reads as "bookmark HERE". It cannot collide with a real bookmark
        # because '.' is not a legal bookmark name, so the intent is unambiguous.
        # The owner tried exactly this and got "Bookmark '.' not found".
        if ($param1 -in @('.', './', '.\')) {
            $name = if ($param2) { $param2 } else { Split-Path -Leaf $PWD.Path }
            Add-Bookmark $name
            return
        }
        if (-not $param1) {
            Write-Host '❌ Use:  nav b <bookmark>    ·    nav b .   bookmarks where you are' -ForegroundColor Red
            Write-Host '💡 See all bookmarks: nav list' -ForegroundColor DarkGray
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
                Write-Host "💡 Remove with: nav db $param1" -ForegroundColor DarkGray
            }
        } else {
            Write-Host "❌ Bookmark '$param1' not found" -ForegroundColor Red
            Write-Host '💡 See all: nav list    ·    bookmark here: nav b .' -ForegroundColor DarkGray
        }
        return
    }

    # ---- Named starting point: `nav -pics screenshots`, or bare `nav -pics` ----
    $anchorRoots = @()
    if ($rootKey) {
        $named = Get-PFNamedRoots
        # Built-in first, then user anchors — the same precedence Resolve-PFRootAlias uses, so
        # a saved anchor can never quietly change what -code or -home mean.
        $anchorRoots = if ($named.Contains($rootKey)) { @($named[$rootKey]) } else { @((Get-PFUserAnchors)[$rootKey]) }
        if (-not $command) {
            $target = @($anchorRoots)[0]
            Set-Location $target
            Write-Host "🎯 $(Format-NavPath $target)" -ForegroundColor Green
            return
        }
        # An anchor SCOPES the normal search — it does not get a search of its own.
        #
        # The first version pre-filtered (exact→contains) and only opened a picker when more
        # than one survived, and that picker was a plain list with no query and no live
        # filtering. That is strictly worse than what `nav ai` already gives you: every
        # candidate in fzf, the query pre-filled, "126/171" narrowing as you type, up/down to
        # choose. Two different pickers in one command is exactly the inconsistency this
        # redesign was supposed to remove — so the anchor now just replaces the search roots
        # and falls through to the one real search below.
    }

    # ---- Built-in shortcuts ---------------------------------------------------
    # Join-Path, never "$HOME\Code" — on Linux that string interpolates to the literal
    # path "/home/you\Code" (backslash is a legal filename character there, not a
    # separator), so it silently never matches anything.
    $homeDir = Get-HomePath
    switch ($command) {
        '~'    { Set-Location $homeDir; Write-Host "🏠 $homeDir" -ForegroundColor Cyan; return }
        'home' { Set-Location $homeDir; Write-Host "🏠 $homeDir" -ForegroundColor Cyan; return }
        'code' {
            $codeDir = Join-Path $homeDir 'Code'
            if (Test-Path $codeDir) {
                Set-Location $codeDir
                Write-Host "💻 $(Format-NavPath $codeDir)" -ForegroundColor Cyan
            } else {
                Write-Host "❌ No Code directory at $codeDir" -ForegroundColor Red
                Write-Host '💡 Bookmark yours instead:  cd <dir>; nav b .' -ForegroundColor DarkGray
            }
            return
        }
        'projects' {
            $projDir = Join-Path (Join-Path $homeDir 'Code') 'Projects'
            if (Test-Path $projDir) {
                Set-Location $projDir
                Write-Host "📂 $(Format-NavPath $projDir)" -ForegroundColor Cyan
            } else {
                Write-Host "❌ No Projects directory at $projDir" -ForegroundColor Red
                Write-Host '💡 Bookmark yours instead:  cd <dir>; nav b .' -ForegroundColor DarkGray
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
    # Normally: the configured roots. But if the current directory sits inside a
    # bookmark, that bookmark wins — it is a far better guess at what you meant than a
    # global scan. Deepest bookmark wins.
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

    # An explicit anchor OUTRANKS context inference. If you typed `nav -srv downloads` you meant
    # /srv, even while standing inside a bookmark — guessing otherwise would ignore what you said.
    $searchRoots = if ($anchorRoots.Count) { $anchorRoots }
                   elseif ($contextRoot)   { @($contextRoot) }
                   else                    { @(Get-NavSearchRoots) }

    if ($verbose) {
        Write-Host "📂 Search roots: $($searchRoots -join ', ')" -ForegroundColor Cyan
        if ($contextRoot) { Write-Host "   (context: you are inside bookmark '$contextRoot')" -ForegroundColor DarkGray }
    }

    # Join all supplied positional words into one query so that "nav source code" passes
    # "source code" to fzf rather than just "source".
    $query = $words -join ' '

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
            Write-Host "💡 Try a starting point:  nav -<start> $query      (nav roots lists them)" -ForegroundColor DarkGray
            Write-Host '💡 Or point nav somewhere else:  nav roots add <path>' -ForegroundColor DarkGray
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
        Write-Host "💡 Try a starting point:  nav -<start> $query      (nav roots lists them)" -ForegroundColor DarkGray
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

# ── pwsh-h registration ───────────────────────────────────────────────────────
Register-PFCommand -Name 'nav' -Aliases @('z') -Section '🧭 SMART NAVIGATION & BOOKMARKS' -Synopsis 'fuzzy-find and jump to a directory, 4 levels deep' -Example 'nav chess-guru · nav -pics screenshots'
Register-PFCommand -Name 'nav b'       -Section '🧭 SMART NAVIGATION & BOOKMARKS' -Synopsis 'jump to a bookmark; nav b . bookmarks where you are' -Example 'nav b docs · nav b . · nav list'
Register-PFCommand -Name 'nav roots'   -Section '🧭 SMART NAVIGATION & BOOKMARKS' -Synopsis 'where a bare nav searches, plus every named starting point' -Example 'nav roots add /srv'
Register-PFCommand -Name 'nav anchors' -Section '🧭 SMART NAVIGATION & BOOKMARKS' -Synopsis 'starting points for nav -<name>; add your own, built-ins are protected' -Example 'nav --anchor . mon · nav anchors rm mon'
