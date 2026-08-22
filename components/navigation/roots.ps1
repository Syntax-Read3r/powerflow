# ==============================================================================
# PowerFlow — Navigation Search Roots
# ==============================================================================
# Domain   : Navigation
# File     : components/navigation/roots.ps1
# Purpose  : Where `nav` looks. Configurable, persisted, platform-aware.
# Functions: Get-NavSearchRoots, Add-NavSearchRoot, Remove-NavSearchRoot,
#            Reset-NavSearchRoots, Show-NavSearchRoots, Get-NavDefaultRoots,
#            Format-NavPath
# Depends  : platform adapters Get-HomePath, Get-PowerFlowNavigationDataPath
# ==============================================================================
#
# WHY THIS FILE EXISTS
#
# nav used to hardcode its search root to ~/Code. That is a fine Windows default and
# a terrible universal one: a Linux box keeps work in ~/linux-lab, /srv, /opt, /mnt —
# anywhere but ~/Code. So the root is now a configurable LIST, persisted to disk.
#
# WHY THE DEFAULT IS NOT `/`
#
# Scanning / walks /proc, /sys, /dev and /run — kernel-backed virtual filesystems that
# are not directories in any useful sense — and throws permission errors on most of the
# rest. On a bare Debian container / holds ~1,600 dirs to $HOME's 5, and a real server is
# far worse. You would wait seconds to fuzzy-match against mostly noise.
#
# $HOME is the honest default: it is where your work actually lives. If you genuinely
# want /srv or /opt in scope, add them — `nav roots add /srv` — and they are scanned too.
# ==============================================================================

$script:NavRootsFile = Join-Path (Get-PowerFlowNavigationDataPath) '.nav_roots.json'

<#
.SYNOPSIS
    The roots nav searches when it has no better context.
.DESCRIPTION
    Windows: ~/Code if it exists (the established convention), else ~.
    Linux:   ~ — it contains ~/Code, ~/linux-lab and everything else you actually work in.
#>
#
# ⚠️  THESE RETURN A COLLECTION. ALWAYS CALL THEM AS  @(Get-NavSearchRoots).
#
# PowerShell unrolls a single-element array on the way out of a function, so with one
# configured root the caller gets a bare STRING. `$roots[0]` is then the character 'C',
# not 'C:\Users\...', and nav silently searches nothing.
#
# Do NOT "fix" that here with `Write-Output -NoEnumerate`: it emits the array wrapped,
# the caller's own @() nests it into a List, and a later [string[]] cast stringifies that
# List to its TYPE NAME. That is not hypothetical — it wrote
# "System.Collections.Generic.List`1[System.Object]" into .nav_roots.json as a search root.
#
# Plain return + @() at the call site is the boring, correct idiom. Keep it.
#
function Get-NavDefaultRoots {
    $homeDir = Get-HomePath
    $code    = Join-Path $homeDir 'Code'

    # On Windows ~/Code is the convention and scoping to it keeps nav fast and precise.
    # On Linux there is no such convention, and ~ already contains ~/Code anyway.
    if ($script:PowerFlowOS -eq 'windows' -and (Test-Path $code)) { return @($code) }
    return @($homeDir)
}

<#
.SYNOPSIS
    Every root nav should search, configured roots first.
    Call as @(Get-NavSearchRoots) — see the note above.
#>
function Get-NavSearchRoots {
    if (Test-Path -LiteralPath $script:NavRootsFile) {
        try {
            $saved = @(Get-Content -LiteralPath $script:NavRootsFile -Raw | ConvertFrom-Json)
            $live  = @($saved | Where-Object { $_ -and (Test-Path $_) })
            if ($live.Count -gt 0) { return $live }
        } catch {
            Write-Warning "nav: could not read $script:NavRootsFile — using defaults."
        }
    }
    return @(Get-NavDefaultRoots)
}

function Save-NavSearchRoots {
    param([string[]]$Roots)
    # -InputObject, not the pipeline. Piping an array to ConvertTo-Json makes its shape
    # depend on how many elements it happens to have; -InputObject with an explicit
    # [string[]] always produces a flat JSON array, one root or ten.
    $rootsDir = Split-Path -Parent $script:NavRootsFile
    if (-not (Test-Path -LiteralPath $rootsDir)) {
        New-Item -ItemType Directory -Path $rootsDir -Force | Out-Null
    }
    ConvertTo-Json -InputObject ([string[]]$Roots) -Depth 2 | Set-Content -LiteralPath $script:NavRootsFile
}

function Add-NavSearchRoot {
    param([string]$Path)

    if (-not $Path) {
        Write-Host "❌ Usage: nav roots add <path>" -ForegroundColor Red
        return
    }

    if (-not (Test-Path $Path -PathType Container)) {
        Write-Host "❌ Not a directory: $Path" -ForegroundColor Red
        return
    }

    $full  = (Resolve-Path $Path).Path
    $roots = @(Get-NavSearchRoots)

    if ($roots -contains $full) {
        Write-Host "ℹ️  Already a search root: $full" -ForegroundColor DarkGray
        return
    }

    # Warn, but do not refuse — it is the user's shell.
    if ($full -eq [IO.Path]::GetPathRoot($full)) {
        Write-Host "⚠️  '$full' is a filesystem root." -ForegroundColor Yellow
        Write-Host "   nav will scan it 4 levels deep on every search. Expect it to be slow." -ForegroundColor DarkGray
    }

    Save-NavSearchRoots ($roots + $full)
    Write-Host "✅ Search root added: $full" -ForegroundColor Green
    Show-NavSearchRoots
}

function Remove-NavSearchRoot {
    param([string]$Path)

    if (-not $Path) {
        Write-Host "❌ Usage: nav roots rm <path>" -ForegroundColor Red
        return
    }

    $roots = @(Get-NavSearchRoots)
    $kept  = @($roots | Where-Object {
        $_ -ne $Path -and $_.TrimEnd([IO.Path]::DirectorySeparatorChar) -ne $Path.TrimEnd([IO.Path]::DirectorySeparatorChar)
    })

    if ($kept.Count -eq $roots.Count) {
        Write-Host "❌ Not a search root: $Path" -ForegroundColor Red
        Show-NavSearchRoots
        return
    }

    Save-NavSearchRoots $kept
    Write-Host "✅ Search root removed: $Path" -ForegroundColor Green
    Show-NavSearchRoots
}

function Reset-NavSearchRoots {
    if (Test-Path -LiteralPath $script:NavRootsFile) { Remove-Item -LiteralPath $script:NavRootsFile -Force }
    Write-Host "✅ Search roots reset to the platform default" -ForegroundColor Green
    Show-NavSearchRoots
}

function Show-NavSearchRoots {
    $roots      = @(Get-NavSearchRoots)
    $isDefault  = -not (Test-Path -LiteralPath $script:NavRootsFile)

    Write-Host ""
    Write-Host "🧭 nav search roots" -NoNewline -ForegroundColor Cyan
    Write-Host $(if ($isDefault) { "  (platform default)" } else { "  (configured)" }) -ForegroundColor DarkGray
    Write-Host "───────────────────" -ForegroundColor Cyan

    foreach ($r in $roots) {
        $ok = Test-Path $r
        Write-Host "  $(if ($ok) { '✅' } else { '❌' }) $r" -ForegroundColor $(if ($ok) { 'White' } else { 'Red' })
    }

    Write-Host ""
    Write-Host "  nav roots add <path>    add a root (e.g. /srv, /opt, /mnt/data)" -ForegroundColor DarkGray
    Write-Host "  nav roots rm  <path>    remove a root" -ForegroundColor DarkGray
    Write-Host "  nav roots reset         back to the default" -ForegroundColor DarkGray
    Write-Host ""
}

<#
.SYNOPSIS
    Shorten a full path for display — $HOME becomes ~.
#>
function Format-NavPath {
    param([string]$Path)

    $homeDir = (Get-HomePath).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $sep     = [IO.Path]::DirectorySeparatorChar

    if ($Path.StartsWith($homeDir + $sep)) {
        return '~' + $Path.Substring($homeDir.Length)
    }
    if ($Path -eq $homeDir) { return '~' }
    return $Path
}

# ==============================================================================
# NAMED ROOTS — the shared starting points behind `nav -<root>` and `ls -<root>`
# ==============================================================================
#
# `nav <name>` searches the configured roots. Named roots let a single invocation
# start somewhere else without making a bookmark first:
#
#     nav -pics screenshots        ls -srv complete
#     nav -docs invoices           ll -dl -recurse -depth 2
#
# CANONICAL NAME + ALIASES. `pictures` is the canonical root; `pics` is an alias.
# Both work, and `nav roots` prints both so neither has to be memorised.
#
# WHY /dev, /proc, /sys AND /run ARE ABSENT
#
# The owner's words: "some folders contain block device special files such as /dev
# so they should not be considered as the starting point because there is nothing
# for a user to do there." Same reasoning the header above gives for the default not
# being `/`. Anything you would only ever read with a kernel tool is not a nav target.
#
# `nav` and `ls` MUST both resolve through Resolve-PFRootedDirectory, so the two can
# never disagree about which roots exist or how a name is matched.
# ==============================================================================

function Get-PFRootAliases {
    return [ordered]@{
        'pics'      = 'pictures'
        'pic'       = 'pictures'
        'docs'      = 'documents'
        'doc'       = 'documents'
        'dl'        = 'downloads'
        'down'      = 'downloads'
        'vids'      = 'videos'
        'vid'       = 'videos'
        'desk'      = 'desktop'
        'conf'      = 'config'
        'cfg'       = 'config'
    }
}

function Get-PFNamedRoots {
    $homeDir = Get-HomePath
    $roots = [ordered]@{}

    # The user folders every desktop OS has. Same names on Windows and Linux, so a
    # person moving between them types the same thing.
    #
    # Resolved through the ADAPTER, never Join-Path $home 'Documents'. On Windows with
    # OneDrive Known Folder Move — the default on many installs — Documents/Pictures/Desktop
    # are redirected to ~\OneDrive\..., and ~\Pictures may not exist at all. Naive joining
    # made `nav -pics` vanish and `nav -docs` land in an empty local stub. Linux has the same
    # trap via XDG user-dirs, which can be relocated or localised (~/Documentos).
    $roots['home']      = @($homeDir)
    $roots['code']      = @((Join-Path $homeDir 'Code'))
    # The preference decides the policy; the adapter answers "where is X under policy P".
    # Under 'local' a folder that does not exist is simply not offered — Repair-PFUserFolders
    # is how you create it, deliberately, rather than nav inventing directories on your disk.
    $pref = Get-PFFolderPreference
    foreach ($folder in @('Documents', 'Downloads', 'Pictures', 'Videos', 'Music', 'Desktop')) {
        $real = Get-UserFolderPath -Name $folder -Prefer $pref
        if ($real) { $roots[$folder.ToLowerInvariant()] = @($real) }
    }

    if ($script:PowerFlowOS -eq 'linux') {
        $roots['srv']    = @('/srv')
        $roots['opt']    = @('/opt')
        $roots['www']    = @('/var/www')
        $roots['etc']    = @('/etc')
        $roots['log']    = @('/var/log')
        $roots['mnt']    = @('/mnt', '/media')
        $roots['config'] = @((Join-Path $homeDir '.config'))
        $roots['tmp']    = @('/tmp')
    }
    else {
        # Built from Get-HomePath, never $env:APPDATA — components must not read environment
        # variables directly (the architecture gate enforces it, and it caught this).
        $roots['config'] = @((Join-Path $homeDir 'AppData\Roaming'), (Join-Path $homeDir '.config'))
        $roots['tmp']    = @((Get-TempPath))
    }

    # Only offer roots that exist on THIS machine. A flag resolving to nothing is worse
    # than no flag, because a failed search looks like the directory is missing.
    $live = [ordered]@{}
    foreach ($key in $roots.Keys) {
        $paths = @($roots[$key] | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
        if ($paths.Count) { $live[$key] = $paths }
    }
    return $live
}

<#
.SYNOPSIS
    Turn '-pics' / 'pics' / 'pictures' into the canonical root name, or '' if unknown.
#>
function Resolve-PFRootAlias {
    param([string]$Token)
    $bare = "$Token".TrimStart('-').ToLowerInvariant()
    if (-not $bare) { return '' }
    $named = Get-PFNamedRoots
    if ($named.Contains($bare)) { return $bare }
    $aliases = Get-PFRootAliases
    if ($aliases.Contains($bare)) {
        $canonical = $aliases[$bare]
        if ($named.Contains($canonical)) { return $canonical }
    }
    # User anchors resolve to themselves. Checked LAST so a built-in always wins — a saved
    # anchor must never silently change what -code or -home mean.
    if ((Get-PFUserAnchors).Contains($bare)) { return $bare }
    # ...and a user's own extra spelling resolves to the anchor it names, for the same
    # reason and with the same precedence: after every built-in, never before one.
    $userAliases = Get-PFUserAnchorAliases
    if ($userAliases.Contains($bare)) { return $userAliases[$bare] }
    return ''
}

<#
.SYNOPSIS
    Every root name usable on this machine, canonical names with their aliases.
#>
function Get-PFRootChoices {
    $named   = Get-PFNamedRoots
    $aliases = Get-PFRootAliases
    $out = [ordered]@{}
    foreach ($key in $named.Keys) {
        $short = @($aliases.Keys | Where-Object { $aliases[$_] -eq $key })
        $out[$key] = [pscustomobject]@{
            Name    = $key
            Aliases = @($short)
            Paths   = @($named[$key])
        }
    }
    return $out
}

<#
.SYNOPSIS
    Find a directory by (fuzzy) name under a named root, or under nav's search roots.
.DESCRIPTION
    Returns Success/Paths/Error. Exact leaf matches win outright; only when there are
    none does it fall back to a contains-match, so `complete` never loses to `incomplete`.
#>
<#
.SYNOPSIS
    Find a directory by name under a named root, or under nav's search roots.
.DESCRIPTION
    Delegates the walk to Search-Projects, which already prunes node_modules/.git/dist/
    build/target. A naive `Get-ChildItem -Recurse -Depth 4 -Force` here took minutes on a
    real dev tree — it descends into every node_modules — and made `nav -code x` unusable.
    Reusing the pruned walk also means nav's root search and this share one traversal cost
    model, so they can never diverge on speed either.

    Exact leaf matches win outright; only when there are none does it fall back to a
    contains-match, so `complete` never loses to `incomplete`.
#>
function Resolve-PFRootedDirectory {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$RootKey = '',
        [int]$MaxDepth = 4
    )

    if ($RootKey) {
        $canonical = Resolve-PFRootAlias $RootKey
        if (-not $canonical) {
            $known = @((Get-PFNamedRoots).Keys) -join ', '
            return [pscustomobject]@{ Success = $false; Paths = @()
                Error = "unknown starting point '-$($RootKey.TrimStart('-'))'. Available here: $known" }
        }
        $named = Get-PFNamedRoots
        $searchRoots = if ($named.Contains($canonical)) { @($named[$canonical]) } else { @((Get-PFUserAnchors)[$canonical]) }
    }
    else {
        $searchRoots = @(Get-NavSearchRoots)
    }

    $candidates = @()
    foreach ($root in $searchRoots) {
        foreach ($rel in @(Search-Projects -BaseDir $root -MaxDepth $MaxDepth -All)) {
            $candidates += [pscustomobject]@{ Leaf = (Split-Path -Leaf $rel); Full = (Join-Path $root $rel) }
        }
    }
    if (-not $candidates.Count) {
        return [pscustomobject]@{ Success = $false; Paths = @()
            Error = "no directories found under: $($searchRoots -join ', ')" }
    }

    $hits = @($candidates | Where-Object { $_.Leaf -ieq $Name })
    if (-not $hits.Count) { $hits = @($candidates | Where-Object { $_.Leaf -ilike "*$Name*" }) }
    if (-not $hits.Count) {
        return [pscustomobject]@{ Success = $false; Paths = @()
            Error = "no directory matching '$Name' under: $($searchRoots -join ', ')" }
    }
    return [pscustomobject]@{ Success = $true; Paths = @($hits | ForEach-Object { $_.Full } | Sort-Object -Unique); Error = '' }
}

# ==============================================================================
# ANCHORS — user-defined starting points
# ==============================================================================
#
# WHY "ANCHOR" AND NOT "START REPO"
#
# They are not repos — any directory qualifies. And "root" was already taken by
# `nav roots` (where a BARE nav searches), so overloading it would have made two
# different things share one word. An anchor is a fixed point you navigate FROM,
# which is exactly the semantic, and it stays clearly distinct from a bookmark:
#
#     nav b docs          go there              (a destination)
#     nav -docs report    search under it       (an anchor)
#
# BUILT-IN anchors (home, code, pictures, srv, …) are derived from the platform and
# CANNOT be deleted — there is nothing stored to delete. Only what a user adds is
# removable, and `nav anchors` marks which is which so that is never a surprise.
# ==============================================================================

$script:NavAnchorsFile = Join-Path (Get-HomePath) '.nav_anchors.json'

# ── ONE ANCHOR, SEVERAL SPELLINGS ─────────────────────────────────────────────
#
# The built-ins have always answered to more than one name — `-pictures` and `-pics`
# reach the same place. User anchors could not, so a person who wanted both `-projects`
# and `-pro` had to save the same directory twice, and `nav anchors` then listed two
# unrelated rows for one folder.
#
#     { "projects": { "path": "D:\\Projects", "aliases": ["pro"] } }
#
# THE OLD FLAT SHAPE IS STILL READ:
#
#     { "mon": "C:\\monitoring" }
#
# A string value means "path, no aliases". Anyone upgrading keeps every anchor they had,
# and the file is rewritten in the richer shape the next time one is added or removed.
# Reading both shapes costs four lines; a migration that runs at profile load would be a
# startup failure mode nobody asked for.
# ──────────────────────────────────────────────────────────────────────────────

<#
.SYNOPSIS
    Every user anchor as name -> { Name; Path; Aliases }.
#>
function Get-PFUserAnchorTable {
    if (-not (Test-Path $script:NavAnchorsFile)) { return [ordered]@{} }
    try {
        $saved = Get-Content $script:NavAnchorsFile -Raw | ConvertFrom-Json
        $out = [ordered]@{}
        foreach ($p in $saved.PSObject.Properties) {
            $path    = ''
            $aliases = @()
            if ($p.Value -is [string]) { $path = "$($p.Value)" }
            elseif ($p.Value) {
                $path = "$($p.Value.path)"
                # A one-element list round-trips through ConvertTo-Json as a bare string;
                # @() normalises both back to a list. Same trap Save-NavSearchRoots documents.
                $aliases = @($p.Value.aliases | Where-Object { $_ })
            }
            # An anchor whose directory is gone is not offered at all: a starting point that
            # resolves nowhere reads as "your files vanished", not "your config is stale".
            if ($path -and (Test-Path -LiteralPath $path)) {
                $out[$p.Name] = [pscustomobject]@{
                    Name    = $p.Name
                    Path    = $path
                    Aliases = @($aliases | ForEach-Object { "$_".ToLowerInvariant() })
                }
            }
        }
        return $out
    } catch { return [ordered]@{} }
}

<#
.SYNOPSIS
    User anchors as name -> path — the shape every existing caller already expects.
#>
function Get-PFUserAnchors {
    $out   = [ordered]@{}
    $table = Get-PFUserAnchorTable
    foreach ($key in $table.Keys) { $out[$key] = $table[$key].Path }
    return $out
}

<#
.SYNOPSIS
    The extra spellings a user gave their own anchors, as alias -> canonical name.
#>
function Get-PFUserAnchorAliases {
    $out   = [ordered]@{}
    $table = Get-PFUserAnchorTable
    foreach ($key in $table.Keys) {
        foreach ($alias in @($table[$key].Aliases)) {
            if ($alias -and -not $out.Contains($alias)) { $out[$alias] = $key }
        }
    }
    return $out
}

function Save-PFUserAnchorTable {
    param([Parameter(Mandatory)]$Table)
    try {
        $doc = [ordered]@{}
        foreach ($key in $Table.Keys) {
            $doc[$key] = [ordered]@{
                path    = $Table[$key].Path
                aliases = @($Table[$key].Aliases)
            }
        }
        ($doc | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $script:NavAnchorsFile -Encoding UTF8
        return $true
    } catch {
        Write-Host "❌ Could not save anchors: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

<#
.SYNOPSIS
    Normalise any word into an anchor spelling, or '' if nothing usable is left.
#>
function ConvertTo-PFAnchorKey {
    param([string]$Text)
    $key = "$Text".TrimStart('-').ToLowerInvariant()
    # A folder is allowed spaces and dots; an anchor spelling is not. "My Code.v2" -> "my-code-v2".
    $key = $key -replace '[^a-z0-9_-]+', '-'
    return $key.Trim('-')
}

<#
.SYNOPSIS
    Why this spelling cannot be used, or '' if it can.
.DESCRIPTION
    -Owner names the anchor being written, so re-anchoring an existing name is an UPDATE
    rather than a collision with itself.
#>
function Get-PFAnchorNameProblem {
    param([Parameter(Mandatory)][string]$Key, [string]$Owner = '')

    if ($Key -notmatch '^[a-z0-9][a-z0-9_-]*$') {
        return 'anchor spellings are lowercase letters, digits, dashes'
    }
    # A user anchor must never shadow a built-in, or `nav -code` would change meaning.
    if ((Get-PFNamedRoots).Contains($Key) -or (Get-PFRootAliases).Contains($Key)) {
        return "'-$Key' is a built-in starting point"
    }
    $table = Get-PFUserAnchorTable
    foreach ($name in $table.Keys) {
        if ($name -eq $Owner) { continue }
        if ($name -eq $Key) { return "'-$Key' already points at $($table[$name].Path)" }
        if (@($table[$name].Aliases) -contains $Key) { return "'-$Key' is already a spelling of -$name" }
    }
    return ''
}

function Add-PFAnchor {
    param([string]$Path, [string]$Name, [string[]]$Aliases = @())

    if (-not $Path) {
        Write-Host '❌ Use:  nav --anchor <path> [name] [more names...]   ( . means the directory you are in )' -ForegroundColor Red
        Write-Host '   e.g.  nav --anchor D:\Projects pro      then:  nav -projects  ·  nav -pro' -ForegroundColor DarkGray
        return
    }
    # '.' is the everywhere-convention for "here", as in `code .`.
    $full = if ($Path -in @('.', './', '.\')) { $PWD.Path } else { (Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue).Path }
    if (-not $full -or -not (Test-Path -LiteralPath $full -PathType Container)) {
        Write-Host "❌ Not a directory: $Path" -ForegroundColor Red
        return
    }

    # THE FOLDER NAMES ITSELF FIRST. `nav --anchor D:\Projects` needs no second argument —
    # the directory's own name is the spelling anyone would have reached for. Words the user
    # supplies are ADDITIONAL spellings, so `-projects` and `-pro` both work and neither
    # replaces the other. When the folder's name is unusable (it is a built-in, or already
    # taken) the user's own first word becomes the canonical one instead.
    $leafKey  = ConvertTo-PFAnchorKey (Split-Path -Leaf $full)
    $wordKeys = @(@(@($Name) + @($Aliases)) | Where-Object { $_ } |
                  ForEach-Object { ConvertTo-PFAnchorKey $_ } | Where-Object { $_ } | Select-Object -Unique)

    $canonical = ''
    $wanted    = @()
    if ($leafKey -and -not (Get-PFAnchorNameProblem -Key $leafKey -Owner $leafKey)) {
        $canonical = $leafKey
        $wanted    = @($wordKeys | Where-Object { $_ -ne $leafKey })
    }
    elseif ($wordKeys.Count) {
        $canonical = $wordKeys[0]
        $wanted    = @($wordKeys | Select-Object -Skip 1)
    }
    else {
        $why = if ($leafKey) { (Get-PFAnchorNameProblem -Key $leafKey -Owner $leafKey) } else { 'its folder name has no usable letters' }
        Write-Host "❌ Cannot name this anchor after its folder — $why." -ForegroundColor Red
        Write-Host "   Give it a name:  nav --anchor `"$full`" <name>" -ForegroundColor DarkGray
        return
    }

    $table = Get-PFUserAnchorTable

    # SPELLINGS ACCUMULATE, they are never replaced. Re-anchoring an existing directory —
    # to move it, or to add one more word for it — used to overwrite the alias list with
    # whatever happened to be on THIS command line, so `nav --anchor D:\DevTools` after an
    # earlier `... devt devtool` silently destroyed both. Anything a user deliberately
    # named stays named until they remove the anchor.
    $kept = @()
    if ($table.Contains($canonical)) { $kept = @($table[$canonical].Aliases) }

    # An alias that clashes is REPORTED AND DROPPED, not fatal. The anchor the user asked
    # for is still worth creating, and saying which spelling was refused is more use than
    # refusing the lot.
    foreach ($alias in $wanted) {
        if ($kept -contains $alias) { continue }
        $problem = Get-PFAnchorNameProblem -Key $alias -Owner $canonical
        if ($problem) { Write-Host "⚠️  Skipped -$alias — $problem." -ForegroundColor Yellow; continue }
        $kept += $alias
    }

    $was = if ($table.Contains($canonical)) { $table[$canonical].Path } else { '' }
    $table[$canonical] = [pscustomobject]@{ Name = $canonical; Path = $full; Aliases = @($kept) }

    if (Save-PFUserAnchorTable $table) {
        $spellings = @(@($canonical) + $kept | ForEach-Object { "-$_" }) -join ' · '
        if ($was) { Write-Host "✅ $spellings → $full   (was $was)" -ForegroundColor Green }
        else      { Write-Host "✅ $spellings → $full" -ForegroundColor Green }
        Write-Host "   Use it:  nav -$canonical <destination>   ·   ls -$canonical" -ForegroundColor DarkGray
    }
}

function Remove-PFAnchor {
    param([string]$Name)

    if (-not $Name) { Write-Host '❌ Use:  nav anchors rm <name>' -ForegroundColor Red; return }
    $key = $Name.TrimStart('-').ToLowerInvariant()

    if ((Get-PFNamedRoots).Contains($key) -or (Get-PFRootAliases).Contains($key)) {
        Write-Host "❌ '-$key' is built in — it is derived from this machine, so there is nothing to delete." -ForegroundColor Red
        Write-Host '   Only anchors you created can be removed.  nav anchors' -ForegroundColor DarkGray
        return
    }
    # Removing by ANY of its spellings. Someone who only ever types `nav -pro` should not
    # have to discover that the anchor's canonical name is `projects` in order to delete it.
    $table = Get-PFUserAnchorTable
    if (-not $table.Contains($key)) {
        $aliasOf = Get-PFUserAnchorAliases
        if ($aliasOf.Contains($key)) { $key = $aliasOf[$key] }
    }
    if (-not $table.Contains($key)) {
        Write-Host "❌ No anchor called '-$key'." -ForegroundColor Red
        Write-Host '   See them all:  nav anchors' -ForegroundColor DarkGray
        return
    }
    $record = $table[$key]
    $table.Remove($key)
    if (Save-PFUserAnchorTable $table) {
        $spellings = @(@($record.Name) + @($record.Aliases) | ForEach-Object { "-$_" }) -join ' · '
        Write-Host "✅ Removed $spellings   ($($record.Path))" -ForegroundColor Green
    }
}

function Show-PFAnchors {
    $builtIn = Get-PFRootChoices
    $user    = Get-PFUserAnchorTable

    Write-Host ''
    Write-Host '⚓ ANCHORS — starting points for  nav -<name> <destination>  and  ls -<name>' -ForegroundColor Cyan
    Write-Host '──────────────────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
    Write-Host ('  {0,-14} {1,-9} {2}' -f 'ANCHOR', 'KIND', 'PATH') -ForegroundColor DarkGray
    foreach ($key in $builtIn.Keys) {
        $c = $builtIn[$key]
        $alias = if (@($c.Aliases).Count) { "  (-$(@($c.Aliases) -join ' -'))" } else { '' }
        Write-Host ('  -{0,-13} {1,-9} {2}{3}' -f $c.Name, 'built-in', (@($c.Paths) -join ', '), $alias) -ForegroundColor DarkGray
    }
    foreach ($key in $user.Keys) {
        $record = $user[$key]
        $alias  = if (@($record.Aliases).Count) { "  (-$(@($record.Aliases) -join ' -'))" } else { '' }
        Write-Host ('  -{0,-13} {1,-9} {2}{3}' -f $record.Name, 'yours', $record.Path, $alias) -ForegroundColor White
    }
    Write-Host ''
    if (-not $user.Count) {
        Write-Host '  You have not added any yet.' -ForegroundColor DarkGray
    }
    Write-Host '  nav --anchor . <name>     anchor the directory you are in' -ForegroundColor DarkGray
    Write-Host '  nav --anchor <path> a b   one anchor, several spellings' -ForegroundColor DarkGray
    Write-Host '  nav anchors rm <name>     remove one you added, by any of its spellings' -ForegroundColor DarkGray
    Write-Host '  nav setup                 find your code drive and name it' -ForegroundColor DarkGray
    Write-Host ''
}

# ==============================================================================
# USER-FOLDER PREFERENCE — OneDrive-redirected or local?
# ==============================================================================
#
# Windows' Known Folder Move sends Documents/Pictures/Desktop to ~\OneDrive\... by
# default, and following that is right for most people — it is where their files
# actually are. But plenty of people deliberately keep files OFF OneDrive, and for
# them "correct" is the local folder.
#
# So it is a PREFERENCE, not a fact, and it lives in PowerFlow config rather than in
# the adapter: the adapter answers "where is X under policy P", the component decides P.
#
# The mkdir case is the point of the whole thing. If you prefer local and ~\Pictures
# does not exist, the honest response is to OFFER TO CREATE IT — not to silently fall
# back to the OneDrive path, which would ignore the preference you just set.
# ==============================================================================

$script:NavFolderPrefFile = Join-Path (Get-PowerFlowConfigPath) 'folder-preference.json'

function Get-PFFolderPreference {
    if (-not (Test-Path -LiteralPath $script:NavFolderPrefFile)) { return 'auto' }
    try {
        $saved = Get-Content -LiteralPath $script:NavFolderPrefFile -Raw | ConvertFrom-Json
        if ("$($saved.preference)" -in @('auto', 'local', 'known')) { return "$($saved.preference)" }
    } catch { }
    return 'auto'
}

function Set-PFFolderPreference {
    param([Parameter(Mandatory)][ValidateSet('auto', 'local', 'known')][string]$Preference)
    try {
        $dir = Split-Path -Parent $script:NavFolderPrefFile
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        (@{ preference = $Preference } | ConvertTo-Json) | Set-Content -LiteralPath $script:NavFolderPrefFile -Encoding UTF8
        return $true
    } catch {
        Write-Host "❌ Could not save the folder preference: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

<#
.SYNOPSIS
    Report which standard folders are missing under the CURRENT preference, and offer mkdir.
.DESCRIPTION
    Only meaningful for 'local': under 'auto' the OS tells us where the folder is and it
    exists by definition. Creating is never automatic — it is a real directory on the user's
    disk, so it is offered and confirmed.
#>
function Repair-PFUserFolders {
    param([switch]$Force)

    $pref = Get-PFFolderPreference
    if ($pref -ne 'local') {
        Write-Host "ℹ️  Folder preference is '$pref' — the OS decides where these live, so there is nothing to create." -ForegroundColor DarkGray
        Write-Host '   Switch with:  pwsh-config  →  User folders' -ForegroundColor DarkGray
        return
    }

    $homeDir = Get-HomePath
    $missing = @()
    foreach ($folder in @('Documents', 'Downloads', 'Pictures', 'Videos', 'Music', 'Desktop')) {
        if (-not (Get-UserFolderPath -Name $folder -Prefer 'local')) { $missing += $folder }
    }
    if (-not $missing.Count) {
        Write-Host '✅ Every standard folder exists locally.' -ForegroundColor Green
        return
    }

    Write-Host ''
    Write-Host "📁 Preference is LOCAL, but these do not exist under $homeDir :" -ForegroundColor Yellow
    $missing | ForEach-Object { Write-Host "     $_" -ForegroundColor DarkGray }
    Write-Host ''
    if (-not $Force) {
        if ([Console]::IsInputRedirected) {
            Write-Host '   Re-run with -Force to create them (no prompt available on a piped stdin).' -ForegroundColor DarkGray
            return
        }
        $answer = Read-Host "   Create $($missing.Count) folder(s)? [y/N]"
        if ($answer -notmatch '^(y|yes)$') { Write-Host '   Nothing created.' -ForegroundColor DarkGray; return }
    }
    foreach ($folder in $missing) {
        $target = Join-Path $homeDir $folder
        try {
            New-Item -ItemType Directory -Path $target -Force -ErrorAction Stop | Out-Null
            Write-Host "   ✅ $target" -ForegroundColor Green
        } catch {
            Write-Host "   ❌ $target — $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# ==============================================================================
# nav setup — find the drive your code lives on, name it, and search it
# ==============================================================================
#
# WHY THIS EXISTS
#
# nav's default root is ~/Code on Windows and ~ on Linux. Both sit on the SYSTEM drive.
# Someone who keeps their work on a second disk — the ordinary arrangement once a machine
# has one — gets a nav that cannot see a single one of their projects, with nothing on
# screen to suggest the roots are why. Measured on the machine this was written for: the
# search roots were the home directory and one folder inside it, while every repository
# lived on another drive entirely, so `nav <anything>` was searching the wrong disk.
#
# The command does three things, in this order, and asks before each:
#
#   1. picks the directory your code lives in       ->  the anchor's path
#   2. names it: the folder names itself, plus any word you prefer
#   3. offers to make it what a BARE nav searches   ->  the roots list
#
# STEP 3 IS SEPARATE ON PURPOSE. An anchor buys you `nav -pro <name>`; only a search root
# makes plain `nav <name>` reach the drive at all. Doing one without the other is the
# half-fix that leaves the original complaint exactly where it was.
#
# It is useful on a single-drive machine too — that was an explicit requirement. There the
# candidate list is simply the conventional and already-configured directories, and naming
# those is still worth doing.
# ==============================================================================

<#
.SYNOPSIS
    Directories worth offering as a code root, likeliest first.
.DESCRIPTION
    Non-system volumes lead, because finding them is the entire point. Within those,
    folders whose name is one people actually use for code sort above the rest — but
    nothing is hidden, because a guess about someone's layout should bias an order,
    never shorten a list.
#>
function Get-PFCodeRootCandidate {
    $likely = @('projects', 'project', 'code', 'coding', 'dev', 'development', 'repos',
                'repositories', 'src', 'source', 'git', 'workspace', 'work')
    $seen = @{}
    $out  = @()

    # Eligibility comes from the SHARED classifier, never a second copy of the rule here.
    # It already knows that drive type is not a safety signal — Windows reports a
    # USB-attached external as DriveType='Fixed' — and decides from the disk's bus instead.
    #
    # Removable drives are MARKED, not hidden. A drive that silently vanished from the list
    # would be its own puzzle, and someone who genuinely wants an external disk can still
    # choose it deliberately — but it sorts last and says what it is.
    $volumes = @()
    try { $volumes = @(Get-PFStorageCandidate) } catch { }

    foreach ($vol in @($volumes | Where-Object { -not $_.IsSystem })) {
        # On Linux a "volume" is a MOUNT, and plenty of mounts are machinery: /boot holds a
        # bootloader, /snap holds one squashfs per package, /var/lib/<daemon> holds a
        # daemon's store. None of them is anywhere a person keeps code, and offering them
        # would bury the one or two mounts that matter. Windows roots are drive letters and
        # never match this.
        if ("$($vol.Root)" -match '^/(boot|snap|var|run|sys|proc|dev)(/|$)') { continue }
        # A volume that cannot be written to is no use as a code root at all, whatever it
        # holds — the classifier already probed this rather than reading permission bits.
        if (-not $vol.Writable) { continue }
        $removable = [bool]$vol.External
        foreach ($child in @(Get-ChildItem -LiteralPath $vol.Root -Directory -Force -ErrorAction SilentlyContinue)) {
            # Volume bookkeeping, not anybody's code.
            if ($child.Name -like '$*' -or $child.Name -eq 'System Volume Information') { continue }
            if ($seen.ContainsKey($child.FullName)) { continue }
            $seen[$child.FullName] = $true
            $out += [pscustomobject]@{
                Path      = $child.FullName
                Volume    = $vol.Name
                Likely    = ((@($likely) -contains $child.Name.ToLowerInvariant()) -and -not $removable)
                OffSystem = $true
                Removable = $removable
            }
        }
    }

    foreach ($p in @(@(Get-NavSearchRoots) + @((Join-Path (Get-HomePath) 'Code')))) {
        if (-not $p -or -not (Test-Path -LiteralPath $p)) { continue }
        if ($seen.ContainsKey($p)) { continue }
        $seen[$p] = $true
        $out += [pscustomobject]@{ Path = $p; Volume = ''; Likely = $false; OffSystem = $false; Removable = $false }
    }

    # Internal off-system drives first, then the system drive's own directories, and
    # anything unpluggable last regardless of how promising its name looked.
    return @($out | Sort-Object -Property @{ Expression = 'Removable'; Ascending = $true },
                                          @{ Expression = 'OffSystem'; Descending = $true },
                                          @{ Expression = 'Likely';    Descending = $true },
                                          'Path')
}

<#
.SYNOPSIS
    Choose a code root — fzf where it exists, a numbered list where it does not.
.DESCRIPTION
    Refusing where a picker would do is the house anti-pattern, so the candidates are
    always offered. Typing a path that is not on the list stays possible either way: a
    guessed list you cannot override is just a smaller cage.
#>
function Select-PFCodeRoot {
    param([Parameter(Mandatory)]$Candidates)

    $rows = @($Candidates | ForEach-Object {
        $tag = if ($_.OffSystem) { "[$($_.Volume)]" } else { '[system]' }
        # An unpluggable disk says so on its own row. A code root that disappears when a
        # cable moves is worth one word of warning at the moment of choosing.
        $note = if ($_.Removable) { '  ⚠ removable' } else { '' }
        '{0,-9} {1}{2}' -f $tag, $_.Path, $note
    })

    if (Get-Command fzf -ErrorAction SilentlyContinue) {
        $picked = $rows | fzf --reverse --border=rounded --height=45% --prompt='code root> ' `
                              --header='Where does your code live?  Enter chooses · Esc to type a path instead' --header-first
        $fzfExit = $LASTEXITCODE
        if (-not $picked) {
            # Escape is a decision and the caller prints "Cancelled"; exit 1 means the query
            # matched no candidate, which is a different thing and says so here.
            if ($fzfExit -eq 1) { Write-PFNothingFound 'No candidate matched what you typed.' }
            return ''
        }
        # Map the row back by INDEX. Parsing the path out of the rendered row would break
        # the moment a row gained a second column — and one just did.
        $index = [array]::IndexOf($rows, "$picked")
        if ($index -ge 0) { return $Candidates[$index].Path }
        return ''
    }

    Write-Host ''
    for ($i = 0; $i -lt $rows.Count; $i++) {
        Write-Host ('  {0,2}. {1}' -f ($i + 1), $rows[$i]) -ForegroundColor White
    }
    Write-Host ''
    $answer = Read-Host '   Number, or a path'
    if (-not $answer) { return '' }
    if ($answer -match '^\d+$' -and [int]$answer -ge 1 -and [int]$answer -le $rows.Count) {
        return $Candidates[[int]$answer - 1].Path
    }
    return $answer
}

<#
.SYNOPSIS
    nav setup [path] [name] [more names...] — name your code drive, and search it.
#>
function Invoke-PFDevRootSetup {
    param([string]$Path = '', [string]$Name = '', [string[]]$Aliases = @(), [switch]$Yes)

    # A prompt on a redirected stdin reads EOF and answers itself. Every prompt below is
    # therefore gated, and the non-interactive route is stated rather than attempted.
    $interactive = -not [Console]::IsInputRedirected

    # ---- 1. which directory ---------------------------------------------------
    $target = ''
    if ($Path) {
        $target = if ($Path -in @('.', './', '.\')) { $PWD.Path }
                  else { (Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue).Path }
    }
    else {
        $candidates = @(Get-PFCodeRootCandidate)
        $offSystem  = @($candidates | Where-Object { $_.OffSystem })

        Write-Host ''
        Write-Host '🧭 nav setup — where does your code live?' -ForegroundColor Cyan
        if ($offSystem.Count) {
            $drives = @($offSystem | ForEach-Object { $_.Volume } | Sort-Object -Unique) -join ', '
            Write-Host "   Found another drive: $drives" -ForegroundColor Green
        }
        else {
            Write-Host '   No drive besides the system one — naming what you have is still worth doing.' -ForegroundColor DarkGray
        }

        if (-not $interactive) {
            Write-Host '   stdin is not a terminal, so there is nothing to ask. Name it directly:' -ForegroundColor DarkGray
            Write-Host '     nav setup <path> [name] [more names...]' -ForegroundColor DarkGray
            return
        }
        if (-not $candidates.Count) {
            Write-Host '   Nothing to offer. Point it somewhere:  nav setup <path> [name]' -ForegroundColor DarkGray
            return
        }

        $chosen = Select-PFCodeRoot -Candidates $candidates
        if (-not $chosen) { Write-Host '↩ Cancelled.' -ForegroundColor DarkGray; return }
        $target = (Resolve-Path -LiteralPath $chosen -ErrorAction SilentlyContinue).Path
    }

    if (-not $target -or -not (Test-Path -LiteralPath $target -PathType Container)) {
        Write-Host "❌ Not a directory: $(if ($Path) { $Path } else { 'nothing chosen' })" -ForegroundColor Red
        return
    }

    # ---- 2. name it -----------------------------------------------------------
    $extra = @($Aliases | Where-Object { $_ })
    if ($interactive -and -not $Name -and -not $extra.Count) {
        $leaf = ConvertTo-PFAnchorKey (Split-Path -Leaf $target)
        Write-Host ''
        if ($leaf) { Write-Host "   It will answer to  -$leaf  — its own folder name." -ForegroundColor DarkGray }
        $word = Read-Host '   A shorter word for it, if you want one (Enter to skip)'
        if ($word) { $extra = @($word) }
    }

    Add-PFAnchor -Path $target -Name $Name -Aliases $extra

    # ---- 3. make a BARE nav search it -----------------------------------------
    $roots = @(Get-NavSearchRoots)
    if ($roots -contains $target) {
        Write-Host '   A bare  nav  already searches it.' -ForegroundColor DarkGray
        return
    }

    Write-Host ''
    Write-Host '   A bare  nav <name>  currently searches:' -ForegroundColor DarkGray
    foreach ($r in $roots) { Write-Host "     $(Format-NavPath $r)" -ForegroundColor DarkGray }
    Write-Host "   $target is not among them, so plain  nav  will not find anything there." -ForegroundColor Yellow

    if (-not $Yes) {
        if (-not $interactive) {
            Write-Host "   Add it with:  nav roots add `"$target`"" -ForegroundColor DarkGray
            return
        }
        $answer = Read-Host '   Search it too? [Y/n]'
        if ($answer -match '^(n|no)$') {
            Write-Host '   Left as it was — the anchor still works.' -ForegroundColor DarkGray
            return
        }
    }
    Add-NavSearchRoot $target
}
