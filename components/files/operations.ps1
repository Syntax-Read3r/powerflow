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

# ══════════════════════════════════════════════════════════════════════════════
#  GNU FLAG PARSING
# ══════════════════════════════════════════════════════════════════════════════
#
# These functions take NO param() block, and that is deliberate. A param() block makes
# PowerShell try to bind `-r`, `-p` and `-f` as PARAMETER NAMES. It then either throws
# ("the parameter name 'p' is ambiguous") or silently drops the flag into $args, where it
# is mistaken for a filename. This is the identical bug that made `ls -ld dir` list the
# wrong directory — see components/files/listing.ps1.
#
# Parsing $args by hand is the only way a PowerShell function can accept `rm -rf x`.
#
# On Linux none of this runs: platform/linux/bindings.ps1 removes these functions so the
# real GNU coreutils are reached. It exists so that the SAME muscle memory works on
# Windows, where there is no GNU tool to fall back to.
<#
.SYNOPSIS
    Split argv into GNU-style flags and paths.
.DESCRIPTION
    Handles bundled short flags (-rf == -r -f), long flags (--recursive), and `--`
    (everything after it is a path, even if it starts with a dash — the only way to
    delete a file genuinely named "-rf").
    Returns @{ Flags = @{r=$true; f=$true}; Paths = @('x'); Unknown = @() }
#>
function Split-GnuArgs {
    param([string[]]$Argv, [hashtable]$LongMap = @{})

    $flags   = @{}
    $paths   = @()
    $unknown = @()
    $endOfFlags = $false

    foreach ($a in $Argv) {
        $s = [string]$a

        if ($endOfFlags)      { $paths += $s; continue }
        if ($s -eq '--')      { $endOfFlags = $true; continue }

        if ($s -match '^--(.+)$') {
            $long = $matches[1]
            if ($LongMap.ContainsKey($long)) { $flags[$LongMap[$long]] = $true }
            else                             { $unknown += $s }
            continue
        }

        # -rf  ->  r, f.  A lone "-" is a path (stdin convention), not a flag.
        if ($s -match '^-(.+)$') {
            foreach ($c in $matches[1].ToCharArray()) { $flags["$c"] = $true }
            continue
        }

        $paths += $s
    }

    return @{ Flags = $flags; Paths = $paths; Unknown = $unknown }
}

function rm {
    $parsed = Split-GnuArgs -Argv $args -LongMap @{
        'recursive' = 'r'; 'force' = 'f'; 'verbose' = 'v'; 'interactive' = 'i'; 'dir' = 'd'
    }

    $force     = $parsed.Flags.ContainsKey('f')
    $recurse   = $parsed.Flags.ContainsKey('r') -or $parsed.Flags.ContainsKey('R')
    $askAlways = $parsed.Flags.ContainsKey('i')
    $Name      = $parsed.Paths

    foreach ($u in $parsed.Unknown) { Write-Host "rm: unknown option '$u'" -ForegroundColor Yellow }

    # -i beats -f, exactly as in GNU: whichever you meant, the safe one wins.
    if ($askAlways) { $force = $false }

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

    # GNU refuses to delete a directory without -r, and that is a real safety feature, not
    # pedantry: `rm build` with a typo'd path should not silently take a tree with it.
    # (Only when paths were NAMED. Picking a directory in the fzf picker is explicit intent.)
    if (-not $recurse -and $Name -and $Name.Count -gt 0) {
        $dirs = @($targets | Where-Object { $_.PSIsContainer })
        if ($dirs.Count -gt 0) {
            foreach ($d in $dirs) {
                Write-Host "rm: cannot remove '$($d.Name)': Is a directory" -ForegroundColor Red
            }
            Write-Host "💡 Use -r to recurse:  " -NoNewline -ForegroundColor DarkGray
            Write-Host "rm -rf $($dirs[0].Name)" -ForegroundColor Cyan
            $targets = @($targets | Where-Object { -not $_.PSIsContainer })
            if ($targets.Count -eq 0) { return }
        }
    }

    if (-not $force) {
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

# ── GNU mv: the two-or-more-argument form ─────────────────────────────────────
<#
.SYNOPSIS
    The real `mv src dst` — move/rename, as bash means it.
.DESCRIPTION
    PowerFlow's own mv is a CUT/PASTE workflow (mv <file> holds it, mv-t pastes). That is a
    genuinely useful thing and it stays. But it meant `mv a.txt b.txt` — the most basic
    operation in any shell — joined its arguments into the single filename "a.txt b.txt",
    found nothing, and silently did nothing at all.

    So: ONE argument still cuts. TWO OR MORE is a real move.

    Overwriting prompts unless -f, which matches PowerFlow's `rm` rather than GNU (GNU
    clobbers silently). Consistency inside PowerFlow beats strict parity, and the safe
    direction is the right one to differ in.
#>
function Invoke-GnuMove {
    param(
        [string[]]$Paths,
        [switch]$Force,        # -f  overwrite without asking
        [switch]$NoClobber,    # -n  never overwrite
        [switch]$ShowVerbose   # -v
    )

    $dest    = $Paths[-1]
    $sources = @($Paths[0..($Paths.Count - 2)])

    $destIsDir = Test-Path -LiteralPath $dest -PathType Container

    # A trailing separator means "this must be a directory" — `mv f nope/` should fail
    # rather than quietly create a FILE called "nope".
    if (($dest -match '[\\/]$') -and -not $destIsDir) {
        Write-Host "mv: target '$dest' is not a directory" -ForegroundColor Red
        return
    }
    if ($sources.Count -gt 1 -and -not $destIsDir) {
        Write-Host "mv: target '$dest' is not a directory" -ForegroundColor Red
        Write-Host "   (moving several files needs a directory to move them INTO)" -ForegroundColor DarkGray
        return
    }

    foreach ($s in $sources) {
        $item = Get-Item -LiteralPath $s -Force -ErrorAction SilentlyContinue
        if (-not $item) {
            Write-Host "mv: cannot stat '$s': No such file or directory" -ForegroundColor Red
            continue
        }

        $target = if ($destIsDir) { Join-Path $dest $item.Name } else { $dest }

        # mv a.txt a.txt — do nothing rather than delete-then-move it into oblivion.
        $targetFull = [IO.Path]::GetFullPath((Join-Path $PWD.Path $target))
        if ($targetFull -eq $item.FullName) {
            Write-Host "mv: '$s' and '$target' are the same file" -ForegroundColor Yellow
            continue
        }

        if (Test-Path -LiteralPath $target) {
            if ($NoClobber) {
                if ($ShowVerbose) { Write-Host "   skipped (exists): $target" -ForegroundColor DarkGray }
                continue
            }
            if (-not $Force) {
                $confirm = Read-Host "⚠️  Overwrite '$target'? [y/N]"
                if ($confirm -notin @('y','Y')) {
                    Write-Host "❌ Skipped: $target" -ForegroundColor Yellow
                    continue
                }
            }
            Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
        }

        try {
            Move-Item -LiteralPath $item.FullName -Destination $target -Force -ErrorAction Stop
            Write-Host "✅ $($item.Name) " -NoNewline -ForegroundColor Green
            Write-Host "→ $target" -ForegroundColor DarkGray
        }
        catch {
            Write-Host "❌ mv: cannot move '$s' to '$target': $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

<#
.SYNOPSIS
    mv — a real move with 2+ arguments; a cut/paste hold with 1.
.DESCRIPTION
    mv src dst          rename/move                     (GNU)
    mv a b c dir/       move several into a directory   (GNU)
    mv -f src dst       overwrite without asking
    mv -n src dst       never overwrite

    mv <file>           CUT it — PowerFlow's own workflow
    mv-t                paste it in the current directory
    mv-c                cancel
.EXAMPLE
    mv old.txt new.txt          # rename
    mv report.pdf ~/Documents/  # move into a folder
    mv belief-index             # cut, then navigate, then mv-t
#>
function mv {
    # -detailed is PowerFlow's own and must be pulled out BEFORE flag parsing:
    # Split-GnuArgs would otherwise read "-detailed" as the bundled short flags
    # -d -e -t -a -i -l -e -d. (Per PowerFlow's rule the long form --detailed is the
    # correct spelling, but the single-dash one is accepted so nobody's habit breaks.)
    $argv     = @()
    $detailed = $false
    foreach ($a in $args) {
        if ("$a" -in @('-detailed', '--detailed')) { $detailed = $true } else { $argv += "$a" }
    }

    $parsed = Split-GnuArgs -Argv $argv -LongMap @{
        'force' = 'f'; 'no-clobber' = 'n'; 'verbose' = 'v'; 'interactive' = 'i'
    }
    $paths = @($parsed.Paths)

    foreach ($u in $parsed.Unknown) { Write-Host "mv: unknown option '$u'" -ForegroundColor Yellow }

    # ── 2+ paths: a real move ─────────────────────────────────────────────────
    if ($paths.Count -ge 2) {
        # ...unless this is an UNQUOTED filename with spaces. `mv my report.txt` used to
        # cut "my report.txt", and it should still do so — but only when that reading is
        # the unambiguous one: the joined name exists AND the first word does not.
        # `mv a.txt b.txt` is unaffected, because a.txt exists.
        $joined = $paths -join ' '
        if ((Test-Path -LiteralPath $joined) -and -not (Test-Path -LiteralPath $paths[0])) {
            $paths = @($joined)     # fall through to the cut path below
        }
        else {
            Invoke-GnuMove -Paths $paths `
                -Force:($parsed.Flags.ContainsKey('f')) `
                -NoClobber:($parsed.Flags.ContainsKey('n')) `
                -ShowVerbose:($parsed.Flags.ContainsKey('v'))
            return
        }
    }

    $fileName = if ($paths.Count -ge 1) { $paths[0] } else { $null }

    # If no filename provided, show current status and help
    if ([string]::IsNullOrWhiteSpace($fileName)) {
        if ($script:MoveInHand) {
            Write-Host "📦 Currently holding: " -NoNewline -ForegroundColor Cyan
            Write-Host "$($script:MoveInHand.Name)" -ForegroundColor Yellow
            Write-Host "💡 Use 'mv-t' to paste in current directory" -ForegroundColor DarkGray
            Write-Host "💡 Use 'mv <newfile>' to drop current and hold new file" -ForegroundColor DarkGray
            Write-Host "💡 Use 'mv-c' to cancel and drop current file" -ForegroundColor DarkGray
        } else {
            Write-Host "💡 Move Commands:" -ForegroundColor Cyan
            Write-Host "═════════════════" -ForegroundColor Cyan
            Write-Host "  mv <src> <dst>       Move or rename it, right now  (like bash)" -ForegroundColor DarkGray
            Write-Host "  mv <a> <b> <dir>/    Move several files into a directory" -ForegroundColor DarkGray
            Write-Host "     -f  overwrite without asking      -n  never overwrite" -ForegroundColor DarkGray
            Write-Host ""
            Write-Host "  mv <filename>        ✂️  CUT it for moving (smart search)" -ForegroundColor DarkGray
            Write-Host "  mv-t                 Paste the held file in the current directory" -ForegroundColor DarkGray
            Write-Host "  mv-c                 Cancel — drop the held file" -ForegroundColor DarkGray
            Write-Host "  mv <filename> --detailed   Show the search process" -ForegroundColor DarkGray
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

<#
.SYNOPSIS
    rmdir <dir>...  — remove a directory. Asks before taking anything with it.
.DESCRIPTION
    The old version read $MyInvocation.Line and did a string .Replace("rmdir", "") on it —
    which mangled any path with "rmdir" in it (rmdir ./rmdir-tests → "./-tests"), could not
    see flags at all, and broke on quoting.
#>
function rmdir {
    $parsed = Split-GnuArgs -Argv $args -LongMap @{ 'parents' = 'p'; 'verbose' = 'v' }

    foreach ($u in $parsed.Unknown) { Write-Host "rmdir: unknown option '$u'" -ForegroundColor Yellow }

    if ($parsed.Paths.Count -eq 0) {
        Write-Host "❌ rmdir: no directory given" -ForegroundColor Red
        Write-Host "   usage: rmdir <dir>...   (use 'rm -rf <dir>' to force)" -ForegroundColor DarkGray
        return
    }

    foreach ($p in $parsed.Paths) {
        $resolved = Resolve-Path -LiteralPath $p -ErrorAction SilentlyContinue
        if (-not $resolved) {
            Write-Host "rmdir: failed to remove '$p': No such file or directory" -ForegroundColor Red
            continue
        }

        $full = $resolved.Path
        if (-not (Test-Path -LiteralPath $full -PathType Container)) {
            Write-Host "rmdir: failed to remove '$p': Not a directory" -ForegroundColor Red
            continue
        }

        $children = @(Get-ChildItem -LiteralPath $full -Force -ErrorAction SilentlyContinue)
        if ($children.Count -gt 0) {
            Write-Host "⚠️  '$p' is not empty — $($children.Count) item(s) inside." -ForegroundColor Yellow
            $confirm = Read-Host "   Delete it and everything in it? [y/N]"
            if ($confirm -notin @('y','Y')) {
                Write-Host "❌ Cancelled." -ForegroundColor Yellow
                continue
            }
        }

        try {
            Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction Stop
            Write-Host "✅ Removed: $p" -ForegroundColor Green
        }
        catch {
            Write-Host "❌ rmdir: failed to remove '$p': $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

<#
.SYNOPSIS
    touch <file>...  — update a file's timestamp, creating it if it does not exist.
.DESCRIPTION
    ⚠️ THIS USED TO DESTROY YOUR FILE.

        function touch { param($f); New-Item -ItemType File -Path $f -Force }

    `New-Item -Force` on an EXISTING file truncates it to zero bytes. So `touch README.md`
    silently emptied README.md. GNU touch does no such thing — it only updates the
    timestamp, and creating the file is what it does when the file is ABSENT.

    An existing file is now never rewritten; only its LastWriteTime moves.
.EXAMPLE
    touch new.txt            create it (or bump its timestamp if it exists)
    touch a.txt b.txt        several at once
    touch -c maybe.txt       bump it ONLY if it exists; never create
#>
function touch {
    $parsed = Split-GnuArgs -Argv $args -LongMap @{
        'no-create' = 'c'; 'verbose' = 'v'
    }
    $noCreate = $parsed.Flags.ContainsKey('c')
    $verbose  = $parsed.Flags.ContainsKey('v')

    foreach ($u in $parsed.Unknown) { Write-Host "touch: unknown option '$u'" -ForegroundColor Yellow }

    if ($parsed.Paths.Count -eq 0) {
        Write-Host "❌ touch: no file given" -ForegroundColor Red
        Write-Host "   usage: touch <file>...   ·   touch -c <file>  (never create)" -ForegroundColor DarkGray
        return
    }

    foreach ($p in $parsed.Paths) {
        if (Test-Path -LiteralPath $p) {
            # Exists: move the timestamp, and DO NOT touch the contents.
            try {
                $now = Get-Date
                $item = Get-Item -LiteralPath $p -Force
                $item.LastWriteTime  = $now
                $item.LastAccessTime = $now
                if ($verbose) { Write-Host "🕒 $($item.Name)" -ForegroundColor DarkGray }
            }
            catch {
                Write-Host "❌ touch: cannot update '$p': $($_.Exception.Message)" -ForegroundColor Red
            }
            continue
        }

        if ($noCreate) { continue }   # -c: absent and we were told not to create it

        try {
            New-Item -ItemType File -Path $p -ErrorAction Stop | Out-Null
            Write-Host "📄 $p" -ForegroundColor Green
        }
        catch {
            Write-Host "❌ touch: cannot create '$p': $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

<#
.SYNOPSIS
    mkdir [-p] <dir>...  — create directories.
.DESCRIPTION
    The old version rejected any name matching anything other than ^[a-zA-Z ._-]+$ — so
    `mkdir v2` threw (a digit!), `mkdir src/app` threw (a slash!), and `mkdir -p a/b/c`
    threw before it even got that far, because param() tried to bind -p as a parameter
    name and reported it as "ambiguous". It also joined all its arguments with spaces, so
    `mkdir a b` made a single directory called "a b".

    Now: real names, real flags, one directory per argument.
.EXAMPLE
    mkdir dist
    mkdir -p src/components/ui      create the whole chain
    mkdir a b c                     three directories, not one called "a b c"
#>
function mkdir {
    $parsed = Split-GnuArgs -Argv $args -LongMap @{
        'parents' = 'p'; 'verbose' = 'v'
    }
    $parents = $parsed.Flags.ContainsKey('p')
    $verbose = $parsed.Flags.ContainsKey('v')

    foreach ($u in $parsed.Unknown) { Write-Host "mkdir: unknown option '$u'" -ForegroundColor Yellow }

    if ($parsed.Paths.Count -eq 0) {
        Write-Host "❌ mkdir: no directory name given" -ForegroundColor Red
        Write-Host "   usage: mkdir <dir>...   ·   mkdir -p a/b/c  (create parents)" -ForegroundColor DarkGray
        return
    }

    foreach ($p in $parsed.Paths) {
        # Only reject what the FILESYSTEM would reject. The previous character allowlist
        # was so strict it excluded digits.
        $invalid = [IO.Path]::GetInvalidFileNameChars() | Where-Object { $_ -notin @('\', '/') }
        $leaf    = Split-Path $p -Leaf
        $bad     = @($leaf.ToCharArray() | Where-Object { $_ -in $invalid })
        if ($bad.Count -gt 0) {
            Write-Host "❌ mkdir: '$p' contains characters this filesystem forbids: $($bad -join ' ')" -ForegroundColor Red
            continue
        }

        if (Test-Path -LiteralPath $p) {
            # GNU: `mkdir -p existing` succeeds silently; plain `mkdir existing` is an error.
            if (-not $parents) {
                Write-Host "mkdir: cannot create directory '$p': File exists" -ForegroundColor Red
            }
            elseif ($verbose) {
                Write-Host "📁 $p (already exists)" -ForegroundColor DarkGray
            }
            continue
        }

        # Without -p, the parent must already exist — again, GNU's behaviour, and it
        # catches a typo'd path instead of silently building the whole wrong tree.
        $parent = Split-Path $p -Parent
        if (-not $parents -and $parent -and -not (Test-Path -LiteralPath $parent)) {
            Write-Host "mkdir: cannot create directory '$p': No such file or directory" -ForegroundColor Red
            Write-Host "💡 Use -p to create the parents:  " -NoNewline -ForegroundColor DarkGray
            Write-Host "mkdir -p $p" -ForegroundColor Cyan
            continue
        }

        try {
            New-Item -ItemType Directory -Path $p -Force:$parents -ErrorAction Stop | Out-Null
            Write-Host "📁 $p" -ForegroundColor Green
        }
        catch {
            Write-Host "❌ mkdir: cannot create '$p': $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# ── pwsh-h registration ───────────────────────────────────────────────────────
Register-PFCommand -Name 'rm'    -Section '📂 ENHANCED FILE OPERATIONS' -Synopsis 'delete with GNU flags; refuses a dir without -r' -Example 'rm -rf node_modules · rm *.log'
Register-PFCommand -Name 'mv'    -Section '📂 ENHANCED FILE OPERATIONS' -Synopsis '2+ args move like bash; 1 arg cuts (mv-t pastes)' -Example 'mv old.txt new.txt'
Register-PFCommand -Name 'mv-t'  -Section '📂 ENHANCED FILE OPERATIONS' -Synopsis 'paste the cut file here'
Register-PFCommand -Name 'mv-c'  -Section '📂 ENHANCED FILE OPERATIONS' -Synopsis 'cancel the cut - drop the held file'
Register-PFCommand -Name 'mkdir' -Section '📂 ENHANCED FILE OPERATIONS' -Synopsis 'create directories; -p builds the whole chain' -Example 'mkdir -p src/app/ui'
Register-PFCommand -Name 'touch' -Section '📂 ENHANCED FILE OPERATIONS' -Synopsis 'bump a timestamp or create; NEVER truncates' -Example 'touch -c maybe.txt'
Register-PFCommand -Name 'rmdir' -Section '📂 ENHANCED FILE OPERATIONS' -Synopsis 'remove a directory; asks before taking contents'
