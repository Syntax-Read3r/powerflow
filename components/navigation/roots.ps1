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
