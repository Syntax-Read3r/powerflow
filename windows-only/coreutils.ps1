# ==============================================================================

# `rmdir` and `md` are built-in aliases for Remove-Item/New-Item, and an ALIAS outranks a
# FUNCTION — so the definitions below are unreachable while they exist. (`mkdir` is
# shipped as a *function*, which a redefinition simply replaces, and `touch` does not
# exist at all; only `rmdir` actually needs this today. The loop covers all three so that
# a future PowerShell release promoting one of them to an alias cannot quietly disable a
# command here.)
#
# This clearing is Windows-only BY DESIGN. Doing it in components/ is what used to hide
# the GNU tools on Linux.
foreach ($_pfAlias in @('rmdir', 'mkdir', 'touch')) {
    if (Test-Path "Alias:\$_pfAlias") { Remove-Item "Alias:\$_pfAlias" -Force -ErrorAction SilentlyContinue }
}
Remove-Variable _pfAlias -ErrorAction SilentlyContinue
# PowerFlow — GNU coreutil clones (Windows only)
# ==============================================================================

# `rmdir` and `md` are built-in aliases for Remove-Item/New-Item, and an ALIAS outranks a
# FUNCTION — so the definitions below are unreachable while they exist. (`mkdir` is
# shipped as a *function*, which a redefinition simply replaces, and `touch` does not
# exist at all; only `rmdir` actually needs this today. The loop covers all three so that
# a future PowerShell release promoting one of them to an alias cannot quietly disable a
# command here.)
#
# This clearing is Windows-only BY DESIGN. Doing it in components/ is what used to hide
# the GNU tools on Linux.
foreach ($_pfAlias in @('rmdir', 'mkdir', 'touch')) {
    if (Test-Path "Alias:\$_pfAlias") { Remove-Item "Alias:\$_pfAlias" -Force -ErrorAction SilentlyContinue }
}
Remove-Variable _pfAlias -ErrorAction SilentlyContinue
# Domain   : Windows-only
# File     : windows-only/coreutils.ps1
# Purpose  : mkdir -p, touch and rmdir for a platform that has none of them
# Functions: mkdir, touch, rmdir
# Depends  : components/files/operations.ps1 (Split-GnuArgs)
# ==============================================================================

# `rmdir` and `md` are built-in aliases for Remove-Item/New-Item, and an ALIAS outranks a
# FUNCTION — so the definitions below are unreachable while they exist. (`mkdir` is
# shipped as a *function*, which a redefinition simply replaces, and `touch` does not
# exist at all; only `rmdir` actually needs this today. The loop covers all three so that
# a future PowerShell release promoting one of them to an alias cannot quietly disable a
# command here.)
#
# This clearing is Windows-only BY DESIGN. Doing it in components/ is what used to hide
# the GNU tools on Linux.
foreach ($_pfAlias in @('rmdir', 'mkdir', 'touch')) {
    if (Test-Path "Alias:\$_pfAlias") { Remove-Item "Alias:\$_pfAlias" -Force -ErrorAction SilentlyContinue }
}
Remove-Variable _pfAlias -ErrorAction SilentlyContinue
#
# WHY THESE LIVE HERE AND NOT IN components/.
#
# Each of these is a REIMPLEMENTATION of a tool Linux already ships, and a better one:
# GNU mkdir, touch and rmdir are on every Linux box. A PowerShell function outranks a
# native binary in name resolution, so defining them in components/ hid the real tools —
# which then had to be surgically removed again on Linux by platform/linux/bindings.ps1.
#
# That arrangement failed in the dangerous direction: the shadowing was created
# unconditionally and undone conditionally, so anything that stopped the undo from
# running left Linux with a silently substituted tool. Defining them only where they
# are wanted inverts that — nothing to undo, and a load failure costs Windows a
# convenience rather than handing Linux a footgun.
#
# Windows really does lack all three: it has no `touch` at all, its `mkdir` is a
# New-Item wrapper with no GNU flags, and `rmdir` is an alias for Remove-Item that
# will not ask before taking a directory's contents with it.
#
# See also components/files/operations.ps1, whose `del` and `mvf` are NOT clones — their
# semantics differ from the GNU tools, which is why they carry PowerFlow's own names and
# exist on both platforms.
# ==============================================================================

# `rmdir` and `md` are built-in aliases for Remove-Item/New-Item, and an ALIAS outranks a
# FUNCTION — so the definitions below are unreachable while they exist. (`mkdir` is
# shipped as a *function*, which a redefinition simply replaces, and `touch` does not
# exist at all; only `rmdir` actually needs this today. The loop covers all three so that
# a future PowerShell release promoting one of them to an alias cannot quietly disable a
# command here.)
#
# This clearing is Windows-only BY DESIGN. Doing it in components/ is what used to hide
# the GNU tools on Linux.
foreach ($_pfAlias in @('rmdir', 'mkdir', 'touch')) {
    if (Test-Path "Alias:\$_pfAlias") { Remove-Item "Alias:\$_pfAlias" -Force -ErrorAction SilentlyContinue }
}
Remove-Variable _pfAlias -ErrorAction SilentlyContinue
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
                Write-Host "↩ Cancelled." -ForegroundColor DarkGray
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

# ── pwsh-h registration ───────────────────────────────────────────────────────
Register-PFCommand -Name 'mkdir' -Section '📂 ENHANCED FILE OPERATIONS' -Synopsis 'create directories; -p builds the whole chain' -Example 'mkdir -p src/app/ui' -Platform 'Windows'
Register-PFCommand -Name 'touch' -Section '📂 ENHANCED FILE OPERATIONS' -Synopsis 'bump a timestamp or create; NEVER truncates' -Example 'touch -c maybe.txt' -Platform 'Windows'
Register-PFCommand -Name 'rmdir' -Section '📂 ENHANCED FILE OPERATIONS' -Synopsis 'remove a directory; asks before taking contents' -Platform 'Windows'
