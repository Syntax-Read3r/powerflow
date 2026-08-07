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

function ls {
    $pfTree   = $false
    $pfDepth  = 0
    $gnuArgs  = @()

    $pfRoot   = ''
    $pfTarget = ''

    # Root flags must be intercepted BEFORE the lsd hand-off. lsd bundles unknown shorts, so
    # `ls -srv complete` reached it as -s -r -v and died with "unexpected argument '-s'".
    $namedRoots = @()
    try { $namedRoots = @((Get-PFNamedRoots).Keys) } catch { }

    for ($i = 0; $i -lt $args.Count; $i++) {
        $a = [string]$args[$i]
        switch -Regex ($a) {
            '^--tree$'  { $pfTree = $true }
            # -recurse / -Recurse: the spelling a PowerShell user already knows. Get-ChildItem
            # habits should not be punished. NOT -r — that is GNU reverse-sort and lsd honours
            # it; -R is GNU recursive and already works.
            '^-{1,2}recurse$' { $pfTree = $true }
            '^--depth$'       { $i++; $pfDepth = [int]$args[$i] }
            '^--depth='       { $pfDepth = [int]($a -split '=', 2)[1] }
            '^-depth$'        { $i++; $pfDepth = [int]$args[$i] }
            default {
                $bare = $a -replace '^-{1,2}', ''
                if ($a.StartsWith('-') -and $namedRoots -contains $bare.ToLowerInvariant()) {
                    $pfRoot = $bare.ToLowerInvariant()
                }
                else { $gnuArgs += $a }           # everything else is GNU's
            }
        }
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
            # house anti-pattern — srv, start-folder and pc-whoami -ram all pick. Falls back to
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

# NOTE: `cat` and `cp` are aliased here for WINDOWS, which has neither.
# platform/linux/bindings.ps1 strips both on Linux so the real GNU tools win.
Set-Alias cat Get-Content
if (Test-Path Alias:\cp) { Remove-Item Alias:\cp -Force }
Set-Alias cp Copy-Item

# ── pwsh-h registration ───────────────────────────────────────────────────────
Register-PFCommand -Name 'ls'  -Section '📂 ENHANCED FILE OPERATIONS' -Synopsis 'pretty listing; GNU flags, --tree/--depth, and -<root> starting points' -Example 'ls -la · ls -recurse -depth 2 · ls -srv complete'
Register-PFCommand -Name 'la'  -Section '📂 ENHANCED FILE OPERATIONS' -Synopsis 'ls -a: everything, dotfiles included'
Register-PFCommand -Name 'll'  -Section '📂 ENHANCED FILE OPERATIONS' -Synopsis 'ls -lh: permissions, owner, size, date - composes with --tree/--depth' -Example 'll · ll -recurse -depth 2'
Register-PFCommand -Name 'clr' -Section '📂 ENHANCED FILE OPERATIONS' -Synopsis 'clear the screen'
Register-PFCommand -Name 'cat' -Section '📂 ENHANCED FILE OPERATIONS' -Synopsis 'print a file (the GNU cat on Linux)'
Register-PFCommand -Name 'cp'  -Section '📂 ENHANCED FILE OPERATIONS' -Synopsis 'copy files (the GNU cp on Linux)'
