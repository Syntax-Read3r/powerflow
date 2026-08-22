# ==============================================================================
# PowerFlow — File Operations
# ==============================================================================
# Domain   : Files
# File     : components/files/operations.ps1
# Purpose  : Safe delete (del) and the cut/paste move workflow (mvf, mv-t, mv-c)
# Functions: Split-GnuArgs, del, Invoke-GnuMove, mvf, mv-t, mv-c
# Depends  : none
# ==============================================================================
#
# WHY THESE ARE NOT CALLED rm AND mv.
#
# PowerShell resolves a bare name as:  Alias -> Function -> Cmdlet -> Native binary.
# A function therefore BEATS a native binary, so a function named `rm` hides
# /usr/bin/rm on Linux. That matters because these are not reimplementations of the
# GNU tools — the semantics differ. PowerFlow's delete refuses a directory without
# -r but drives an fzf picker and confirms; PowerFlow's move is a cut/paste workflow
# where one argument HOLDS a file rather than moving it. Silently substituting either
# for the GNU tool a Linux user's reflexes expect would burn someone exactly once.
#
# So the canonical names are PowerFlow's own — `del` and `mvf` — and they mean the same
# thing on every platform. Windows, which has no GNU tool to defer to, additionally
# binds `rm` and `mv` to them in platform/windows/bindings.ps1; Linux does not, and the
# real coreutils are reached with nothing to undo.
#
# Both functions report themselves as the name they were INVOKED as (see $self below),
# so `rm -rf x` on Windows says "rm:" and `del -rf x` says "del:".
# ==============================================================================

# `del`, `erase`, `rd` and `ri` are built-in aliases for Remove-Item, and an ALIAS
# outranks a FUNCTION — so `function del` below would never be reached while they exist.
# Note what is deliberately NOT here: `rm`, `mv` and `rmdir` are left alone, because on
# Linux those names must keep resolving to the coreutils.
foreach ($_pfAlias in @('del', 'erase', 'rd', 'ri')) {
    if (Test-Path "Alias:\$_pfAlias") { Remove-Item "Alias:\$_pfAlias" -Force -ErrorAction SilentlyContinue }
}
Remove-Variable _pfAlias -ErrorAction SilentlyContinue

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
# This parsing runs on both platforms, because `del` and `mvf` exist on both. It is what
# lets `del -rf x` work at all: a PowerShell function cannot otherwise accept `-rf`.
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
        #
        # A SINGLE-DASH WORD IS NOT A BUNDLE. Bundling every character was a data-loss
        # defect, measured on this parser:
        #
        #   rm -force  x  ->  c e f o r  ->  recursive AND force   (the r in "fo-r-ce")
        #   rm -verbose x ->  b e o r s v ->  recursive
        #   rm -interactive x -> a c e i n r t v -> recursive
        #
        # So the safest-sounding word switched on recursion, and `-force` — the flag people
        # type most reflexively — became `rm -rf`. `ls` teaches single-dash words as the
        # PowerFlow-friendly spelling, so the style the tree teaches was the unsafe one here.
        #
        # Three cases now, in order:
        #   1. the word names a long option  -> that flag, exactly as `--word` would
        #   2. every character is a declared flag letter -> a real GNU bundle (-rf)
        #   3. otherwise -> refused BY NAME, and no flag is set
        #
        # Case 3 is the seatbelt: a token this parser does not understand can no longer set
        # a destructive flag as a side effect of its spelling.
        if ($s -match '^-(.+)$') {
            $token = $matches[1]

            # 1. `-force` is treated as `--force`, which is what the user meant.
            if ($LongMap.ContainsKey($token)) { $flags[$LongMap[$token]] = $true; continue }

            # 2. A genuine short bundle: every character must be a letter this command
            #    actually declares. The declared set is the LongMap's own values, plus the
            #    uppercase forms GNU uses for the same meaning (-R for recursive).
            $known = @{}
            foreach ($letter in $LongMap.Values) {
                $known["$letter"] = $true
                $known["$([string]$letter).ToUpperInvariant()".Substring(0, 1).ToUpperInvariant()] = $true
            }
            $allKnown = $token.Length -gt 0
            foreach ($c in $token.ToCharArray()) {
                if (-not ($known.ContainsKey("$c") -or $known.ContainsKey("$c".ToLowerInvariant()))) {
                    $allKnown = $false; break
                }
            }
            if ($allKnown) {
                foreach ($c in $token.ToCharArray()) { $flags["$c"] = $true }
                continue
            }

            # 3. Neither a known word nor a valid bundle. Refuse it by name.
            $unknown += $s
            continue
        }

        $paths += $s
    }

    return @{ Flags = $flags; Paths = $paths; Unknown = $unknown }
}

function del {
    # Report as the name actually typed. On Windows `rm` is bound to this function, and a
    # message reading "del: ..." after the user typed `rm` would name a command they did
    # not run. The allow-list matters: InvocationName echoes whatever the caller wrote, so
    # `& $cmd ...` reports "&" and an indirect call can report nothing at all — neither is
    # a command name, and printing one would be worse than printing the canonical name.
    $self = "$($MyInvocation.InvocationName)"
    if ($self -notin @('del', 'rm')) { $self = 'del' }

    $parsed = Split-GnuArgs -Argv $args -LongMap @{
        'recursive' = 'r'; 'force' = 'f'; 'verbose' = 'v'; 'interactive' = 'i'; 'dir' = 'd'
    }

    $force     = $parsed.Flags.ContainsKey('f')
    $recurse   = $parsed.Flags.ContainsKey('r') -or $parsed.Flags.ContainsKey('R')
    $askAlways = $parsed.Flags.ContainsKey('i')
    $Name      = $parsed.Paths

    foreach ($u in $parsed.Unknown) { Write-Host "${self}: unknown option '$u'" -ForegroundColor Yellow }

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
        # literal name — covers an unquoted filename with spaces ("del my report.txt")
        # and names containing wildcard characters ("del build[1].log").
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
                Write-Host "${self}: cannot remove '$($d.Name)': Is a directory" -ForegroundColor Red
            }
            Write-Host "💡 Use -r to recurse:  " -NoNewline -ForegroundColor DarkGray
            Write-Host "$self -rf $($dirs[0].Name)" -ForegroundColor Cyan
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
        [switch]$ShowVerbose,  # -v
        [string]$Self = 'mvf'  # the name the caller was invoked as, for messages
    )

    $dest    = $Paths[-1]
    $sources = @($Paths[0..($Paths.Count - 2)])

    $destIsDir = Test-Path -LiteralPath $dest -PathType Container

    # A trailing separator means "this must be a directory" — `mv f nope/` should fail
    # rather than quietly create a FILE called "nope".
    if (($dest -match '[\\/]$') -and -not $destIsDir) {
        Write-Host "${Self}: target '$dest' is not a directory" -ForegroundColor Red
        return
    }
    if ($sources.Count -gt 1 -and -not $destIsDir) {
        Write-Host "${Self}: target '$dest' is not a directory" -ForegroundColor Red
        Write-Host "   (moving several files needs a directory to move them INTO)" -ForegroundColor DarkGray
        return
    }

    foreach ($s in $sources) {
        $item = Get-Item -LiteralPath $s -Force -ErrorAction SilentlyContinue
        if (-not $item) {
            Write-Host "${Self}: cannot stat '$s': No such file or directory" -ForegroundColor Red
            continue
        }

        $target = if ($destIsDir) { Join-Path $dest $item.Name } else { $dest }

        # mv a.txt a.txt — do nothing rather than delete-then-move it into oblivion.
        $targetFull = [IO.Path]::GetFullPath((Join-Path $PWD.Path $target))
        if ($targetFull -eq $item.FullName) {
            Write-Host "${Self}: '$s' and '$target' are the same file" -ForegroundColor Yellow
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
            Write-Host "❌ ${Self}: cannot move '$s' to '$target': $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

<#
.SYNOPSIS
    mvf — a real move with 2+ arguments; a cut/paste hold with 1.
.DESCRIPTION
    On Windows this is also reachable as `mv`. On Linux `mv` stays the GNU tool, because
    the one-argument form here CUTS rather than moves and quietly changing that meaning
    would be the wrong kind of surprise.

    mvf src dst         rename/move                     (GNU)
    mvf a b c dir/      move several into a directory   (GNU)
    mvf -f src dst      overwrite without asking
    mvf -n src dst      never overwrite

    mvf <file>          CUT it — PowerFlow's own workflow
    mv-t                paste it in the current directory
    mv-c                cancel
.EXAMPLE
    mvf old.txt new.txt          # rename
    mvf report.pdf ~/Documents/  # move into a folder
    mvf belief-index             # cut, then navigate, then mv-t
#>
function mvf {
    # See `del` above: report as the name actually typed, since Windows binds `mv` here.
    $self = "$($MyInvocation.InvocationName)"
    if ($self -notin @('mvf', 'mv')) { $self = 'mvf' }

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

    foreach ($u in $parsed.Unknown) { Write-Host "${self}: unknown option '$u'" -ForegroundColor Yellow }

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
            Invoke-GnuMove -Paths $paths -Self $self `
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
            Write-Host "💡 Use '$self <newfile>' to drop current and hold new file" -ForegroundColor DarkGray
            Write-Host "💡 Use 'mv-c' to cancel and drop current file" -ForegroundColor DarkGray
        } else {
            Write-Host "💡 Move Commands:" -ForegroundColor Cyan
            Write-Host "═════════════════" -ForegroundColor Cyan
            Write-Host ("  {0,-20} Move or rename it, right now  (like bash)" -f "$self <src> <dst>") -ForegroundColor DarkGray
            Write-Host ("  {0,-20} Move several files into a directory" -f "$self <a> <b> <dir>/") -ForegroundColor DarkGray
            Write-Host "     -f  overwrite without asking      -n  never overwrite" -ForegroundColor DarkGray
            Write-Host ""
            Write-Host ("  {0,-20} ✂️  CUT it for moving (smart search)" -f "$self <filename>") -ForegroundColor DarkGray
            Write-Host ("  {0,-20} Paste the held file in the current directory" -f 'mv-t') -ForegroundColor DarkGray
            Write-Host ("  {0,-20} Cancel — drop the held file" -f 'mv-c') -ForegroundColor DarkGray
            Write-Host ("  {0,-20} Show the search process" -f "$self <file> --detailed") -ForegroundColor DarkGray
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
    Write-Host "💡 Use '$self $fileName --detailed' for detailed search output" -ForegroundColor DarkGray
    Write-Host "💡 Use full filename if you know it exactly" -ForegroundColor DarkGray
}

<#
.SYNOPSIS
    Paste the file that was cut with mvf (or `mv` on Windows)
.DESCRIPTION
    Second stage of the move operation. Moves the previously cut file to current directory.
.EXAMPLE
    mv-t     # Pastes the file that was cut with mv command
#>
function mv-t {
    if (-not $script:MoveInHand) {
        Write-Host "❌ No file currently held for moving" -ForegroundColor Red
        Write-Host "💡 Use 'mvf <filename>' first to cut a file for moving" -ForegroundColor DarkGray
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

    # ── Perform the move ──────────────────────────────────────────────────────
    #
    # -ErrorAction Stop IS THE WHOLE FIX. Move-Item's failures are NON-TERMINATING by
    # default, so without it a failed move never reaches the catch below — execution walks
    # straight into the green "MOVE COMPLETED" banner and then clears $script:MoveInHand.
    # The user is told the file moved, the file has not moved, and the cut they were holding
    # is gone. Measured: a Move-Item onto an existing path writes an error to the stream and
    # returns; `try/catch` around it never fires.
    #
    # The catch's own advice — "The file is still held" — was therefore true only in the one
    # case where it could not print.
    #
    # The move is then VERIFIED by reading the filesystem back rather than trusting a silent
    # return, which is the house rule for anything that changes state.
    try {
        Move-Item -Path $sourceFile -Destination $currentDir -Force -ErrorAction Stop

        $landed = Join-Path $currentDir $fileName
        if (-not (Test-Path -LiteralPath $landed)) {
            throw "Move reported no error, but nothing arrived at $landed"
        }

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







# ── pwsh-h registration ───────────────────────────────────────────────────────
# `del` and `mvf` are the canonical names on BOTH platforms. Windows additionally binds
# `rm` and `mv` to them (platform/windows/bindings.ps1, which registers those aliases);
# on Linux those two names belong to the coreutils.
Register-PFCommand -Name 'del'   -Section '📂 ENHANCED FILE OPERATIONS' -Synopsis 'delete with GNU flags; refuses a dir without -r' -Example 'del -rf node_modules · del *.log'
Register-PFCommand -Name 'mvf'   -Section '📂 ENHANCED FILE OPERATIONS' -Synopsis '2+ args move like bash; 1 arg cuts (mv-t pastes)' -Example 'mvf old.txt new.txt'
Register-PFCommand -Name 'mv-t'  -Section '📂 ENHANCED FILE OPERATIONS' -Synopsis 'paste the cut file here'
Register-PFCommand -Name 'mv-c'  -Section '📂 ENHANCED FILE OPERATIONS' -Synopsis 'cancel the cut - drop the held file'
