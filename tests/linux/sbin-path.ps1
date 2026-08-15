# ==============================================================================
# PF-BUG-007 — /sbin and /usr/sbin must be reachable under pwsh
# ==============================================================================
# Reported from a real VM:
#
#     ❯ swapon --show
#     swapon: The term 'swapon' is not recognized as a name of a cmdlet, function,
#             script file, or executable program.
#     ❯ sudo /sbin/swapon --show      # works fine
#
# swapon was never missing. It lives in /sbin, which Debian keeps off a normal user's
# PATH. In bash this is easy to miss, because `sudo` runs with root's own secure_path and
# finds it anyway. Under pwsh it is not: PowerShell resolves the command name against the
# CALLER's PATH before sudo runs at all, so it fails at resolution with a message that
# reads "not installed" rather than "not on your PATH" — and the admin goes looking for a
# package that is already there.
#
# Runs INSIDE a Linux container, because PATH composition is the thing under test and it
# cannot be faked from Windows.
# ==============================================================================

$ErrorActionPreference = 'Continue'
$fail = 0
function Ok([bool]$c, [string]$m, [string]$d = '') {
    if (-not $c) { $script:fail++ }
    Write-Host ("  {0} {1}{2}" -f $(if ($c) { 'ok  ' } else { 'FAIL' }), $m, $(if ($d) { "   $d" } else { '' }))
}

# REPRODUCE THE REPORTED CONDITION FIRST.
#
# A container usually runs as root, and root's PATH already contains the sbin directories —
# so loading the profile there proves nothing: the fix correctly does nothing, and the test
# would pass while never exercising the bug. The report came from a NON-ROOT user on Debian,
# where these directories are absent from PATH. Strip them to recreate that.
$stripped = ($env:PATH -split ':' | Where-Object { $_ -notin @('/usr/local/sbin', '/usr/sbin', '/sbin') }) -join ':'
$env:PATH = $stripped

Write-Host ''
Write-Host "-- PATH before the profile (sbin stripped, as a normal user sees it) --"
$before = $env:PATH
Write-Host "  $before"

# Prove the bug exists in this state, or the rest of the test is measuring nothing.
$swaponBefore = Get-Command swapon -ErrorAction SilentlyContinue
if (Test-Path '/usr/sbin/swapon') {
    Ok ($null -eq $swaponBefore) 'precondition: swapon is NOT resolvable before the profile loads'
}

. /pf/Microsoft.PowerShell_profile.ps1 *> $null

Write-Host ''
Write-Host "-- the admin directories are on PATH afterwards ---------------"
foreach ($dir in @('/usr/local/sbin', '/usr/sbin', '/sbin')) {
    if (-not (Test-Path $dir)) {
        # Arch and recent Fedora merge these into /usr/bin; absent is not a failure.
        Write-Host ("  --   {0,-16} not present on this distro (nothing to add)" -f $dir)
        continue
    }
    Ok (($env:PATH -split ':') -contains $dir) "$dir is on PATH"
}

Write-Host ''
Write-Host "-- the tools that prompted the report now resolve -------------"
# Only assert on tools this image actually ships; a missing package is not a PATH bug.
foreach ($tool in @('swapon', 'fdisk', 'blkid', 'ip', 'ss', 'useradd', 'shutdown')) {
    $real = @('/usr/local/sbin', '/usr/sbin', '/sbin', '/usr/bin', '/bin') |
            ForEach-Object { Join-Path $_ $tool } | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $real) {
        Write-Host ("  --   {0,-10} not installed in this image" -f $tool)
        continue
    }
    $resolved = Get-Command $tool -ErrorAction SilentlyContinue | Select-Object -First 1
    Ok ([bool]$resolved) "$tool resolves" $(if ($resolved) { "$($resolved.Source)" } else { "exists at $real but is unreachable" })
}

Write-Host ''
Write-Host "-- the user's own PATH entries still win ----------------------"
# APPENDED, not prepended: a tool the user put earlier on PATH must keep winning over a
# same-named one in /sbin, or this fix would silently change which binary runs.
$firstBefore = ($before -split ':')[0]
$firstAfter = ($env:PATH -split ':')[0]
Ok ($firstBefore -eq $firstAfter) 'the first PATH entry is unchanged' "was '$firstBefore', now '$firstAfter'"

# Every entry that was already there must keep its relative order — the fix only APPENDS.
$beforeList = @($before -split ':')
$afterList = @($env:PATH -split ':')
$survivors = @($afterList | Where-Object { $beforeList -contains $_ })
Ok ((($survivors -join ':') -eq ($beforeList -join ':'))) `
    'the pre-existing PATH is preserved in order — nothing was reordered or dropped'

# And anything the profile ADDED must come after everything that was already there, so a
# same-named binary earlier on the user's PATH still wins.
foreach ($dir in @('/usr/local/sbin', '/usr/sbin', '/sbin')) {
    if (-not (Test-Path $dir)) { continue }
    if ($beforeList -contains $dir) { continue }   # not ours; its position is not ours to judge
    $idx = $afterList.IndexOf($dir)
    Ok ($idx -ge $beforeList.Count) "$dir was APPENDED, after every pre-existing entry" "index=$idx, pre-existing=$($beforeList.Count)"
}

Write-Host ''
Write-Host "-- no duplicates, however many times the profile loads --------"
. /pf/Microsoft.PowerShell_profile.ps1 *> $null
foreach ($dir in @('/usr/local/sbin', '/usr/sbin', '/sbin')) {
    if (-not (Test-Path $dir)) { continue }
    $count = @($env:PATH -split ':' | Where-Object { $_ -eq $dir }).Count
    Ok ($count -eq 1) "$dir appears exactly once after a second load" "count=$count"
}

Write-Host ''
Write-Host "-- the interpolation trap that caused this ---------------------"
# "$env:PATH:$dir" reads the colon as part of the variable NAME, asks for an env var called
# `PATH:`, gets nothing, and yields just $dir — replacing PATH instead of appending to it.
# The ~/.local/bin line shipped in exactly that form. Static check, because the broken form
# only misbehaves when its guard fires, and the guard is machine-dependent.
$pathsFile = '/pf/config/paths.linux.ps1'
$src = Get-Content -LiteralPath $pathsFile -Raw
$code = [regex]::Replace($src, '(?m)^\s*#.*$', '')

$bad = [regex]::Matches($code, '"\$env:PATH:')
Ok ($bad.Count -eq 0) 'no "$env:PATH:..." interpolation remains — it REPLACES PATH, never appends'
$assignments = [regex]::Matches($code, '\$env:PATH\s*=\s*"([^"]*)"')
foreach ($m in $assignments) {
    Ok ($m.Groups[1].Value -match '\$\{env:PATH\}') `
        "every PATH assignment must brace the name: $($m.Groups[1].Value)"
}

# And prove the appended form actually appends, here, in this shell.
$env:PATH = '/usr/bin:/bin'
$probe = '/tmp/pf-probe-dir'
$env:PATH = "${env:PATH}:$probe"
Ok ($env:PATH -eq "/usr/bin:/bin:$probe") 'the braced form appends' "got '$env:PATH'"

Write-Host ''
if ($fail) { Write-Host "$fail CHECK(S) FAILED"; exit 1 }
Write-Host 'PF-BUG-007: the admin directories are reachable, and nothing was reordered'
