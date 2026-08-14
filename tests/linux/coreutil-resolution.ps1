# ==============================================================================
# The Linux leg: does removing platform/linux/bindings.ps1 actually leave the
# coreutils reachable?
# ==============================================================================
# Runs INSIDE a Linux container with the working tree mounted at /pf. This is the check the
# deleted platform/linux/bindings.ps1 used to make at runtime.
#
# CI covers it too, in release-validate-linux.yml: a `distros` matrix (Debian, Ubuntu, Fedora,
# Arch, openSUSE, Alpine) and a dedicated `linux` job, both asserting these names resolve to
# real binaries. This script is the same check run LOCALLY, before pushing — a coreutil
# regression found here costs a minute, found in a release run it costs the release.
# ==============================================================================

$ErrorActionPreference = 'Continue'
$fail = 0

Write-Host ''
Write-Host "platform: $($PSVersionTable.Platform)  IsLinux=$IsLinux  pwsh $($PSVersionTable.PSVersion)"
Write-Host ''

# ── 1. load the real profile, exactly as a Linux user would ───────────────────
Write-Host '-- loading the profile --------------------------------------'
$loadOutput = @()
try { $loadOutput = @(. /pf/Microsoft.PowerShell_profile.ps1 *>&1 | ForEach-Object { "$_" }) }
catch { Write-Host "  FAIL profile threw: $($_.Exception.Message)"; exit 1 }
$loadOutput | ForEach-Object { Write-Host "  | $_" }

# A missing Linux bindings file must NOT produce a warning: absence is now the normal case.
$warned = @($loadOutput | Where-Object { $_ -match 'component not found.*bindings' })
if ($warned) { Write-Host '  FAIL the profile warned about the missing bindings file'; $fail++ }
else { Write-Host '  ok   no warning about the absent bindings file' }

# ── 2. the coreutils must still be the real binaries ─────────────────────────
Write-Host ''
Write-Host '-- coreutil names must resolve to a NATIVE BINARY -----------'
# `pwd` is deliberately NOT in this list. Measured with -NoProfile in this same image:
# PowerShell itself keeps `pwd` as an alias for Get-Location on Linux, unlike cat/rm/mv/cp/ls
# which it drops on Unix precisely to avoid clashing. So `pwd` being an Alias is the platform's
# baseline, not something PowerFlow did — asserting otherwise would be testing PowerShell.
foreach ($name in @('rm', 'mv', 'cp', 'cat', 'mkdir', 'touch', 'rmdir', 'grep', 'less', 'head', 'tail', 'df', 'du')) {
    $c = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $c) {
        # Not every one of these is installed in a minimal image; absent is not shadowed.
        Write-Host ("  --   {0,-6} not installed in this image (cannot be shadowed)" -f $name)
        continue
    }
    $ok = ($c.CommandType -eq 'Application')
    if (-not $ok) { $fail++ }
    Write-Host ("  {0} {1,-6} {2} {3}" -f $(if ($ok) { 'ok  ' } else { 'FAIL' }), $name, $c.CommandType, $c.Source)
}

# ── 3. PowerFlow's own names must exist ──────────────────────────────────────
Write-Host ''
Write-Host '-- PowerFlow file commands ----------------------------------'
foreach ($pair in @(@{ N = 'del'; T = 'Function' }, @{ N = 'mvf'; T = 'Function' },
                    @{ N = 'mv-t'; T = 'Function' }, @{ N = 'mv-c'; T = 'Function' },
                    @{ N = 'ls'; T = 'Function' })) {
    $c = Get-Command $pair.N -ErrorAction SilentlyContinue | Select-Object -First 1
    $kind = if ($c) { "$($c.CommandType)" } else { 'ABSENT' }
    $ok = ($kind -eq $pair.T)
    if (-not $ok) { $fail++ }
    Write-Host ("  {0} {1,-5} {2}  (expected {3})" -f $(if ($ok) { 'ok  ' } else { 'FAIL' }), $pair.N, $kind, $pair.T)
}

# ── 4. the Windows-only clones must NOT be loaded here ───────────────────────
Write-Host ''
Write-Host '-- windows-only/ must not load on Linux ---------------------'
foreach ($name in @('mkdir', 'touch', 'rmdir', 'which')) {
    $c = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
    $isFn = ($c -and $c.CommandType -eq 'Function')
    if ($isFn) { $fail++ }
    Write-Host ("  {0} {1,-6} {2}" -f $(if ($isFn) { 'FAIL' } else { 'ok  ' }), $name,
        $(if ($c) { "$($c.CommandType)" } else { 'absent' }))
}

# ── 5. del/mvf must actually work, and name themselves correctly ─────────────
Write-Host ''
Write-Host '-- del reports itself and refuses a directory without -r ----'
$probe = '/tmp/pf-probe'
New-Item -ItemType Directory -Path $probe -Force | Out-Null
$out = @(del --definitely-not-a-flag /tmp/pf-nonexistent-xyz *>&1 | ForEach-Object { "$_" }) -join ' '
$ok = $out -clike '*del:*'
if (-not $ok) { $fail++ }
Write-Host ("  {0} del introduces itself as 'del:'  -> {1}" -f $(if ($ok) { 'ok  ' } else { 'FAIL' }), ($out -replace '\s+', ' ').Trim())

# GNU rm must still refuse a directory without -r — the seatbelt the old bindings file existed
# to preserve.
$rmOut = @(& /usr/bin/rm $probe 2>&1 | ForEach-Object { "$_" }) -join ' '
$stillThere = Test-Path $probe
$ok = $stillThere
if (-not $ok) { $fail++ }
Write-Host ("  {0} GNU rm still refuses a directory without -r (dir survives: {1})" -f `
    $(if ($ok) { 'ok  ' } else { 'FAIL' }), $stillThere)
Remove-Item $probe -Recurse -Force -ErrorAction SilentlyContinue

# ── 6. the flag convention works here too ────────────────────────────────────
Write-Host ''
Write-Host '-- flag shims on Linux --------------------------------------'
foreach ($cmd in @('pc-whoami', 'pwsh-h', 'installed-apps', 'set-path', 'team-room')) {
    $c = Get-Command $cmd -ErrorAction SilentlyContinue | Select-Object -First 1
    $ok = $c -and $c.CommandType -eq 'Function' -and $c.Parameters.Keys.Count -eq 0
    if (-not $ok) { $fail++ }
    Write-Host ("  {0} {1,-15} shim present, no param() of its own" -f $(if ($ok) { 'ok  ' } else { 'FAIL' }), $cmd)
}
$refusal = @(pwsh-h --zzz-not-a-flag *>&1 | ForEach-Object { "$_" }) -join ' '
$ok = $refusal -clike '*unknown option*'
if (-not $ok) { $fail++ }
Write-Host ("  {0} an unknown --flag is refused on Linux too" -f $(if ($ok) { 'ok  ' } else { 'FAIL' }))

Write-Host ''
if ($fail) { Write-Host "$fail LINUX CHECK(S) FAILED"; exit 1 }
Write-Host 'LINUX LEG PASSED'
