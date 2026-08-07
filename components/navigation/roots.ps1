# ==============================================================================
# PowerFlow — Navigation Search Roots
# ==============================================================================
# Domain   : Navigation
# File     : components/navigation/roots.ps1
# Purpose  : Where `nav` looks. Configurable, persisted, platform-aware.
# Functions: Get-NavSearchRoots, Add-NavSearchRoot, Remove-NavSearchRoot,
#            Reset-NavSearchRoots, Show-NavSearchRoots, Get-NavDefaultRoots,
#            Format-NavPath
# Depends  : platform adapter Get-HomePath
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

$script:NavRootsFile = Join-Path (Get-HomePath) '.nav_roots.json'

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
    if (Test-Path $script:NavRootsFile) {
        try {
            $saved = @(Get-Content $script:NavRootsFile -Raw | ConvertFrom-Json)
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
    ConvertTo-Json -InputObject ([string[]]$Roots) -Depth 2 | Set-Content $script:NavRootsFile
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
    if (Test-Path $script:NavRootsFile) { Remove-Item $script:NavRootsFile -Force }
    Write-Host "✅ Search roots reset to the platform default" -ForegroundColor Green
    Show-NavSearchRoots
}

function Show-NavSearchRoots {
    $roots      = @(Get-NavSearchRoots)
    $isDefault  = -not (Test-Path $script:NavRootsFile)

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

function Get-PFUserAnchors {
    if (-not (Test-Path $script:NavAnchorsFile)) { return [ordered]@{} }
    try {
        $saved = Get-Content $script:NavAnchorsFile -Raw | ConvertFrom-Json
        $out = [ordered]@{}
        foreach ($p in $saved.PSObject.Properties) {
            if ($p.Value -and (Test-Path -LiteralPath $p.Value)) { $out[$p.Name] = "$($p.Value)" }
        }
        return $out
    } catch { return [ordered]@{} }
}

function Save-PFUserAnchors {
    param([Parameter(Mandatory)]$Anchors)
    try {
        ($Anchors | ConvertTo-Json -Depth 3) | Set-Content -LiteralPath $script:NavAnchorsFile -Encoding UTF8
        return $true
    } catch {
        Write-Host "❌ Could not save anchors: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Add-PFAnchor {
    param([string]$Path, [string]$Name)

    if (-not $Path -or -not $Name) {
        Write-Host '❌ Use:  nav --anchor <path> <name>     ( . means the directory you are in )' -ForegroundColor Red
        Write-Host '   e.g.  nav --anchor . mon      then:  nav -mon <destination>' -ForegroundColor DarkGray
        return
    }
    # '.' is the everywhere-convention for "here", as in `code .`.
    $full = if ($Path -in @('.', './', '.\')) { $PWD.Path } else { (Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue).Path }
    if (-not $full -or -not (Test-Path -LiteralPath $full -PathType Container)) {
        Write-Host "❌ Not a directory: $Path" -ForegroundColor Red
        return
    }

    $key = $Name.TrimStart('-').ToLowerInvariant()
    if ($key -notmatch '^[a-z0-9][a-z0-9_-]*$') {
        Write-Host "❌ Anchor names are lowercase letters, digits, dashes: '$Name'" -ForegroundColor Red
        return
    }
    # A user anchor must never shadow a built-in, or `nav -code` would silently change meaning.
    if ((Get-PFNamedRoots).Contains($key) -or (Get-PFRootAliases).Contains($key)) {
        Write-Host "❌ '-$key' is a built-in starting point — pick another name." -ForegroundColor Red
        Write-Host '   See them all:  nav anchors' -ForegroundColor DarkGray
        return
    }

    $anchors = Get-PFUserAnchors
    $existing = $anchors[$key]
    $anchors[$key] = $full
    if (Save-PFUserAnchors $anchors) {
        if ($existing) { Write-Host "✅ -$key → $full   (was $existing)" -ForegroundColor Green }
        else           { Write-Host "✅ -$key → $full" -ForegroundColor Green }
        Write-Host "   Use it:  nav -$key <destination>   ·   ls -$key <destination>" -ForegroundColor DarkGray
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
    $anchors = Get-PFUserAnchors
    if (-not $anchors.Contains($key)) {
        Write-Host "❌ No anchor called '-$key'." -ForegroundColor Red
        Write-Host '   See them all:  nav anchors' -ForegroundColor DarkGray
        return
    }
    $was = $anchors[$key]
    $anchors.Remove($key)
    if (Save-PFUserAnchors $anchors) { Write-Host "✅ Removed -$key   ($was)" -ForegroundColor Green }
}

function Show-PFAnchors {
    $builtIn = Get-PFRootChoices
    $user    = Get-PFUserAnchors

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
        Write-Host ('  -{0,-13} {1,-9} {2}' -f $key, 'yours', $user[$key]) -ForegroundColor White
    }
    Write-Host ''
    if (-not $user.Count) {
        Write-Host '  You have not added any yet.' -ForegroundColor DarkGray
    }
    Write-Host '  nav --anchor . <name>     anchor the directory you are in' -ForegroundColor DarkGray
    Write-Host '  nav anchors rm <name>     remove one you added (built-ins cannot be removed)' -ForegroundColor DarkGray
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
