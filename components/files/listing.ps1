# ==============================================================================
# PowerFlow — File Listing
# ==============================================================================
# Domain   : Files
# File     : components/files/listing.ps1
# Purpose  : ls that honours GNU flags, with PowerFlow's extras on long flags
# Functions: ls, la, ll
# Depends  : Get-DependencyInstallHint (platform/<os>/adapters/packages.ps1)
# ==============================================================================
#
# THE RULE:  single dash belongs to Linux.  long dash belongs to PowerFlow.
#
#     ls -l -a -d -h -R -t -S -r        GNU semantics, exactly
#     ls --tree  /  ls --depth 3        PowerFlow
#
# WHY THERE IS NO param() BLOCK
#
# There used to be one — `param([string]$path, [switch]$t, [int]$d)` — and it was a bug,
# not a style choice. With a param block PowerShell tries to bind `-l` as a PARAMETER NAME:
#
#     ls -l          -> "A parameter cannot be found that matches parameter name 'l'"
#     ls -ld ward-a  -> silently swallowed into $args and DISCARDED, then listed the
#                       CURRENT directory instead of ward-a. No error. Just wrong.
#
# Worse, the old flags actively CONTRADICTED GNU:
#     -t  GNU = sort by time      PowerFlow = tree view
#     -d  GNU = the directory itself, not its contents   PowerFlow = tree depth
#
# So `ls -t` on Linux silently produced a tree instead of a time-sorted list.
#
# With no param block, $args receives argv verbatim and we parse it ourselves.
# ==============================================================================

if (Test-Path Alias:\ls) { Remove-Item Alias:\ls -Force }

# ══════════════════════════════════════════════════════════════════════════════
#  ls --perms — PF-FEAT-002
# ══════════════════════════════════════════════════════════════════════════════
# NOT another `ls -l`. GNU's long listing already works and lsd renders it well; a second
# copy would earn nothing. This answers a different question — "who can do what to these
# files" — by putting the mode first, in both notations, and saying nothing else.
#
# Three commands now sit on permissions and they do not overlap:
#   ls -l          GNU long listing, everything about every file
#   ls --perms     just the modes, compact, with the dangerous ones marked
#   perms <path>   one path, explained in full (components/shell/teach.ps1)
function Show-PFPermissionListing {
    param([string]$Path = '.', [switch]$All)

    if (-not (Test-PermsSupported)) {
        # Deliberately NOT faked from NTFS ACLs. They are a different model — an ordered
        # list of allow/deny entries per identity, with inheritance — and any numeric
        # rendering would be a guess the user might act on. Windows already has `ls -l`
        # and Get-Acl; what it does not have is a POSIX mode, so say that.
        Write-Host ''
        Write-Host 'POSIX permissions do not exist on this platform.' -ForegroundColor Yellow
        Write-Host '  Windows uses NTFS ACLs, which do not reduce to a numeric mode.' -ForegroundColor DarkGray
        Write-Host '  Try:  Get-Acl <path> | Format-List      or      icacls <path>' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    $target = if ($Path) { $Path } else { '.' }
    if (-not (Test-Path -LiteralPath $target)) {
        Write-Host "No such path: $target" -ForegroundColor Red
        return
    }

    $items = @(Get-ChildItem -LiteralPath $target -Force:$All -ErrorAction SilentlyContinue |
               Sort-Object { -not $_.PSIsContainer }, Name)
    if (-not $items.Count) {
        Write-Host '  (empty)' -ForegroundColor DarkGray
        return
    }

    $rows = @()
    foreach ($item in $items) {
        $mode = Get-FileMode -Path $item.FullName
        if (-not $mode) { continue }

        # A trailing slash marks a directory without spending a column on it.
        $name = if ($mode.Type -eq 'd') { "$($item.Name)/" } else { $item.Name }

        # Only the modes that are genuinely dangerous, and only with a reason. Marking
        # everything unusual would train the reader to ignore the column — the point is
        # that a mark here is worth stopping for.
        $numeric = $mode.Numeric
        $warn = ''
        if ($mode.Others.Substring(1, 1) -eq 'w') { $warn = 'world-writable' }
        # setuid/setgid on an executable is how a normal user runs code as someone else.
        if ($numeric.Length -ge 4) {
            $special = [int]$numeric.Substring(0, 1)
            if ($special -band 4) { $warn = if ($warn) { "$warn · setuid" } else { 'setuid' } }
            if ($special -band 2) { $warn = if ($warn) { "$warn · setgid" } else { 'setgid' } }
        }

        $rows += [pscustomobject]@{
            Symbolic = $mode.Symbolic
            Numeric  = $numeric
            Name     = $name
            Warn     = $warn
            IsDir    = ($mode.Type -eq 'd')
        }
    }

    if (-not $rows.Count) {
        Write-Host '  (no readable entries)' -ForegroundColor DarkGray
        return
    }

    # Measured columns: a symbolic mode is 10 characters until an ACL or a security context
    # adds a '+' or '.', and a numeric one is 3 or 4 depending on the special bits.
    $symWidth = (@($rows | ForEach-Object { $_.Symbolic.Length }) | Sort-Object -Descending)[0]
    $numWidth = (@($rows | ForEach-Object { $_.Numeric.Length }) | Sort-Object -Descending)[0]

    Write-Host ''
    Write-Host ("  {0}  {1}  {2}" -f 'PERM'.PadRight($symWidth), 'MODE'.PadRight($numWidth), 'NAME') -ForegroundColor DarkGray
    foreach ($row in $rows) {
        Write-Host ("  {0}  " -f $row.Symbolic.PadRight($symWidth)) -NoNewline -ForegroundColor DarkGray
        Write-Host ("{0}  " -f $row.Numeric.PadRight($numWidth)) -NoNewline -ForegroundColor Cyan
        Write-Host $row.Name -NoNewline -ForegroundColor $(if ($row.IsDir) { 'Blue' } else { 'White' })
        if ($row.Warn) { Write-Host "   ⚠ $($row.Warn)" -NoNewline -ForegroundColor Yellow }
        Write-Host ''
    }
    Write-Host ''

    if (Test-PFEducateRequested) { Write-PFEducation -Topic 'ls-perms' }
}

Register-PFEducation -Topic 'ls-perms' `
    -Analogy 'Every file carries three sets of permissions: what its owner may do, what its group may do, and what everyone else may do.' `
    -Lines @(
        @{ Term = 'PERM';  Means = 'The three sets in order — owner, group, everyone. r read, w write, x run.' }
        @{ Term = 'MODE';  Means = 'The same thing as three digits, which is what chmod takes. 600 is owner-only.' }
        @{ Term = 'd';     Means = 'A leading d means it is a directory; x on a directory means you may enter it.' }
        @{ Term = '⚠';     Means = 'Marked only when genuinely risky: anyone can write to it, or it runs as another user.' }
    ) `
    -Footer 'perms <path> explains one file in full · rn <file> --chmod 600 changes one.'

function ls {
    $pfTree   = $false
    $pfDepth  = 0
    $gnuArgs  = @()

    $pfRoot   = ''
    $pfTarget = ''
    $pfPerms  = $false

    # Root flags must be intercepted BEFORE the lsd hand-off. lsd bundles unknown shorts, so
    # `ls -srv complete` reached it as -s -r -v and died with "unexpected argument '-s'".
    $namedRoots = @()
    try { $namedRoots = @((Get-PFNamedRoots).Keys) } catch { }

    # --educate is cross-cutting and this command is hand-parsed, so it must be removed
    # before the loop: anything left in $gnuArgs is handed to lsd, which would reject it.
    $lsArgs = $args
    if (Get-Command Split-PFEducateFlag -ErrorAction SilentlyContinue) {
        $split = Split-PFEducateFlag -Argv $args -Command 'ls'
        $lsArgs = $split.Argv
        Set-PFEducateRequested $split.Educate
    }

    for ($i = 0; $i -lt $lsArgs.Count; $i++) {
        $a = [string]$lsArgs[$i]
        switch -Regex ($a) {
            '^--tree$'  { $pfTree = $true }
            # Intercepted before the lsd hand-off, like --tree: lsd would bundle an unknown
            # long flag into shorts and die on it.
            '^-{1,2}perms$' { $pfPerms = $true }
            # -recurse / -Recurse: the spelling a PowerShell user already knows. Get-ChildItem
            # habits should not be punished. NOT -r — that is GNU reverse-sort and lsd honours
            # it; -R is GNU recursive and already works.
            '^-{1,2}recurse$' { $pfTree = $true }
            '^--depth$'       { $i++; $pfDepth = [int]$lsArgs[$i] }
            '^--depth='       { $pfDepth = [int]($a -split '=', 2)[1] }
            '^-depth$'        { $i++; $pfDepth = [int]$lsArgs[$i] }
            default {
                $bare = $a -replace '^-{1,2}', ''
                if ($a.StartsWith('-') -and $namedRoots -contains $bare.ToLowerInvariant()) {
                    $pfRoot = $bare.ToLowerInvariant()
                }
                else { $gnuArgs += $a }           # everything else is GNU's
            }
        }
    }

    # --perms is answered here, AFTER the root/target resolution below has had its chance —
    # so `ls --perms` and `ls --perms /etc` both work. Placed before the lsd hand-off because
    # this view is PowerFlow's own, not a wrapper over lsd.
    if ($pfPerms -and -not $pfRoot) {
        $permTarget = @($gnuArgs | Where-Object { -not $_.StartsWith('-') } | Select-Object -Last 1)
        $showAll = @($gnuArgs | Where-Object { $_ -match '^-[a-zA-Z]*a' }).Count -gt 0
        try {
            Show-PFPermissionListing -Path $(if ($permTarget) { $permTarget } else { '.' }) -All:$showAll
        }
        finally {
            # ls clears its own flag: it never enters Invoke-PFParamCommand, whose finally
            # does this for every other command.
            if (Get-Command Set-PFEducateRequested -ErrorAction SilentlyContinue) {
                Set-PFEducateRequested $false
            }
        }
        return
    }

    # --educate on a view that has no lesson. Saying nothing would be a silent no-op for a
    # flag the user deliberately typed, which is the failure the flag convention exists to
    # prevent — so point at the view that does explain itself.
    if ((Get-Command Test-PFEducateRequested -ErrorAction SilentlyContinue) -and (Test-PFEducateRequested)) {
        Write-Host '  note: --educate explains the permission view — try: ls --perms --educate' -ForegroundColor DarkGray
        if (Get-Command Set-PFEducateRequested -ErrorAction SilentlyContinue) { Set-PFEducateRequested $false }
    }

    # `ls -srv complete` — find the directory, then list it. Same resolver nav will use, so the
    # two can never disagree about where a name lives.
    if ($pfRoot) {
        $needle = @($gnuArgs | Where-Object { -not $_.StartsWith('-') } | Select-Object -Last 1)
        if (-not $needle) {
            $named = Get-PFNamedRoots
            $pfTarget = @($named[$pfRoot])[0]     # bare `ls -srv` lists the root itself
        }
        else {
            $resolved = Resolve-PFRootedDirectory -Name "$needle" -RootKey $pfRoot
            if (-not $resolved.Success) {
                Write-Host "❌ $($resolved.Error)" -ForegroundColor Red
                Write-Host "   Starting points:  $((Get-PFNamedRoots).Keys -join ' · ')" -ForegroundColor DarkGray
                return
            }
            # Ambiguity gets a PICKER, not a refusal. Refusing where a picker would do is the
            # house anti-pattern — srv, start-folder and pc-whoami --ram all pick. Falls back to
            # listing the candidates only when there is no interactive terminal or no fzf.
            $paths = @($resolved.Paths)
            if ($paths.Count -gt 1) {
                if ([Console]::IsOutputRedirected -or -not (Get-Command fzf -ErrorAction SilentlyContinue)) {
                    Write-Host "❌ '$needle' matches more than one directory under -$($pfRoot):" -ForegroundColor Red
                    $paths | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray }
                    return
                }
                $picked = $paths | fzf --height=40% --layout=reverse --border --header="ls -$pfRoot $needle — $($paths.Count) matches"
                if (-not $picked) { return }
                $paths = @("$picked")
            }
            $pfTarget = $paths[0]
            $gnuArgs  = @($gnuArgs | Where-Object { $_ -ne $needle })
        }
        Write-Host "📁 $pfTarget" -ForegroundColor DarkGray
        $gnuArgs += $pfTarget
    }

    # ── PowerFlow: --tree ─────────────────────────────────────────────────────
    if ($pfTree) {
        if (-not (Get-Command lsd -ErrorAction SilentlyContinue)) {
            Write-Host "⚠️  --tree needs lsd. Install: $(Get-DependencyInstallHint 'lsd')" -ForegroundColor Yellow
            return
        }

        # Smart depth: shallower inside Node projects, which are pathologically deep.
        if ($pfDepth -le 0) {
            $target = if ($gnuArgs.Count -gt 0) { $gnuArgs[-1] } else { '.' }
            $isNode = (Test-Path (Join-Path $target 'package.json')) -or ($target -like '*node_modules*')
            $pfDepth = if ($isNode) { 2 } else { 3 }
        }

        Write-Host "🌳 Tree view (depth: $pfDepth)" -ForegroundColor DarkGray
        # Let lsd detect the destination: keep icons/colour at an interactive prompt,
        # but emit plain text when the listing feeds grep, a file, or another command.
        & lsd --tree "--depth=$pfDepth" --group-dirs=first --icon=auto --color=auto @gnuArgs
        return
    }

    # ── Everything else is GNU's ──────────────────────────────────────────────
    # lsd is a drop-in for GNU ls and understands -l -a -A -h -d -R -t -S -r -1 -i,
    # so the user's flags mean exactly what they mean on Linux — they just come out
    # prettier. If lsd is missing, fall through to the real ls so the flags STILL work.
    if (Get-Command lsd -ErrorAction SilentlyContinue) {
        # `always` leaves an ANSI reset after the filename. That invisible suffix makes
        # end-anchored pipelines such as `ls -l ... | grep -E 'sdg$'` miss valid rows.
        & lsd --group-dirs=first --icon=auto --color=auto @gnuArgs
        return
    }

    $nativeLs = Get-Command ls -CommandType Application -ErrorAction SilentlyContinue |
                Select-Object -First 1
    if ($nativeLs) {
        & $nativeLs.Source @gnuArgs
        return
    }

    # Windows with no lsd and no ls.exe — degrade, but never silently.
    Write-Host "⚠️  lsd not found. Install: $(Get-DependencyInstallHint 'lsd')" -ForegroundColor Yellow
    $path = @($gnuArgs | Where-Object { $_ -notlike '-*' })
    if ($path) { Get-ChildItem -Force @path } else { Get-ChildItem -Force }
}

# la / ll are GNU's own conventional shorthands — keep them meaning what they mean there.
function la { ls -a  @args }     # all, including dotfiles
function ll { ls -lh @args }     # long, human-readable sizes

Set-Alias clr clear                                 # Clear screen

# `cat` and `cp` are deliberately NOT defined here. PowerShell already ships both as
# built-in aliases on Windows (cat -> Get-Content, cp -> Copy-Item), so PowerFlow's
# versions added nothing there — while on Linux they outranked and hid the real GNU
# tools, which then had to be stripped back out again by a platform file. Defining
# nothing is both simpler and correct on both platforms.

# ── pwsh-h registration ───────────────────────────────────────────────────────
Register-PFCommand -Name 'ls'  -Section '📂 ENHANCED FILE OPERATIONS' -Synopsis 'pretty listing; GNU flags, --tree/--depth, and -<root> starting points' -Example 'ls -la · ls --recurse --depth 2 · ls -srv complete'
Register-PFCommand -Name 'la'  -Section '📂 ENHANCED FILE OPERATIONS' -Synopsis 'ls -a: everything, dotfiles included'
Register-PFCommand -Name 'll'  -Section '📂 ENHANCED FILE OPERATIONS' -Synopsis 'ls -lh: permissions, owner, size, date - composes with --tree/--depth' -Example 'll · ll --recurse --depth 2'
Register-PFCommand -Name 'clr' -Section '📂 ENHANCED FILE OPERATIONS' -Synopsis 'clear the screen'

