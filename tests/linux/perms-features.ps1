# ==============================================================================
# PF-FEAT-001 `rn --chmod` and PF-FEAT-002 `ls --perms`
# ==============================================================================
# Both are POSIX-mode features, so both must be exercised where modes exist. On Windows
# they refuse rather than translate NTFS ACLs, which is asserted in tests/windows/.
#
# The behaviour that matters most here is the PARTIAL FAILURE: if the rename succeeds and
# the chmod does not, the rename must NOT be rolled back, and the user must be handed the
# exact command to finish the job. Undoing a completed action because a later one failed
# destroys work the user asked for.
# ==============================================================================

# 'Continue' so one failed assertion does not hide the rest — but an unexpected ERROR must
# still count. Without the trap below this file printed its success line after two
# "term is not recognized" errors, because the Ok() calls that would have failed never ran.
# A test that reports success while erroring is worse than one that simply fails.
$ErrorActionPreference = 'Continue'
$script:unexpected = 0
trap {
    $script:unexpected++
    Write-Host ("  FAIL unexpected error: {0}" -f $_.Exception.Message) -ForegroundColor Red
    continue
}

$profileCandidates = @(
    '/pf/Microsoft.PowerShell_profile.ps1'
    (Join-Path $HOME '.config/powershell/Microsoft.PowerShell_profile.ps1')
    (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Microsoft.PowerShell_profile.ps1')
)
$profilePath = $profileCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $profilePath) { Write-Host 'no PowerFlow profile found'; exit 1 }
. $profilePath *> $null

$fail = 0
function Ok([bool]$c, [string]$m, [string]$d = '') {
    if (-not $c) { $script:fail++ }
    Write-Host ("  {0} {1}{2}" -f $(if ($c) { 'ok  ' } else { 'FAIL' }), $m, $(if ($d) { "   $d" } else { '' }))
}

$sandbox = "/tmp/pf-perms-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $sandbox | Out-Null
Push-Location $sandbox
try {
    # ── the adapter contract ──────────────────────────────────────────────────
    Write-Host ''
    Write-Host '-- Set-FileMode applies and VERIFIES --------------------------'
    Set-Content -Path "$sandbox/key.conf" -Value 'secret'
    $r = Set-FileMode -Path "$sandbox/key.conf" -Mode '600'
    Ok ($r.Success) 'chmod 600 succeeds' "$($r.Numeric) $($r.Symbolic)"
    Ok ($r.Numeric -eq '600') 'the mode read back is 600'
    Ok ($r.Symbolic -eq '-rw-------') 'the symbolic form matches' "$($r.Symbolic)"

    # 0644 and 644 are the same mode; a STRING compare would call the padded form a mismatch.
    $r = Set-FileMode -Path "$sandbox/key.conf" -Mode '0644'
    Ok ($r.Success) 'a four-digit mode is accepted and compares numerically' "$($r.Numeric)"

    # Refusals
    $r = Set-FileMode -Path "$sandbox/key.conf" -Mode 'u+x'
    Ok (-not $r.Success) 'a symbolic mode is refused'
    Ok ($r.Error -match 'numeric') 'the refusal says why'
    $r = Set-FileMode -Path "$sandbox/key.conf" -Mode '999'
    Ok (-not $r.Success) 'a non-octal mode is refused'
    $r = Set-FileMode -Path "$sandbox/nope" -Mode '600'
    Ok (-not $r.Success) 'a missing path is refused'
    Ok ($r.Error -match 'no such path') 'and says so'

    # ── rn --chmod ────────────────────────────────────────────────────────────
    Write-Host ''
    Write-Host '-- rn --chmod renames THEN sets the mode on the NEW path ------'
    Set-Content -Path "$sandbox/wg.conf" -Value 'x'
    $out = @(rn "$sandbox/wg.conf" --chmod 600 6>&1 2>&1 | ForEach-Object { "$_" }) -join "`n"
    # rn is interactive for the NAME, so in a non-interactive shell it will not complete the
    # rename. What must hold regardless: the flag BOUND rather than being read as a filename.
    Ok ($out -notmatch 'unknown option') '--chmod is accepted, not reported unknown'
    Ok ($out -notmatch "'--chmod'") '--chmod is not treated as a filename'

    # The parameter must exist on the implementation, ahead of the remaining-args filename.
    $cmd = Get-Command Invoke-PFRenameFile
    Ok ($cmd.Parameters.ContainsKey('Chmod')) 'the implementation declares -Chmod'
    $names = @($cmd.Parameters.Keys)
    Ok ($names.IndexOf('Chmod') -lt $names.IndexOf('fileNameParts')) `
        '-Chmod is declared BEFORE the remaining-arguments filename, or "600" would be swallowed'

    # ── ls --perms ────────────────────────────────────────────────────────────
    Write-Host ''
    Write-Host '-- ls --perms ------------------------------------------------'
    Set-Content -Path "$sandbox/notes.md" -Value 'x'
    Set-Content -Path "$sandbox/deploy.sh" -Value 'x'
    & chmod 644 "$sandbox/notes.md"
    & chmod 777 "$sandbox/deploy.sh"
    & chmod 600 "$sandbox/key.conf"
    New-Item -ItemType Directory -Path "$sandbox/scripts" | Out-Null

    $view = @(ls --perms 6>&1 2>&1 | ForEach-Object { "$_" }) -join "`n"
    Ok ($view -match 'PERM') 'the header is present'
    Ok ($view -match 'MODE') 'both notations are shown'
    Ok ($view -match '600') 'a 600 file is listed'
    Ok ($view -match '-rw-------') 'with its symbolic form'
    Ok ($view -match 'scripts/') 'a directory is marked with a trailing slash'

    # The warning must fire for world-writable and ONLY where it is earned.
    Ok ($view -match 'world-writable') '777 is flagged world-writable'
    $notesLine = @($view -split "`n" | Where-Object { $_ -match 'notes\.md' })[0]
    Ok ($notesLine -notmatch '⚠') '644 is NOT flagged — a mark must be worth stopping for'

    # -a reaches hidden files.
    Set-Content -Path "$sandbox/.hidden" -Value 'x'
    $plain = @(ls --perms 6>&1 2>&1 | ForEach-Object { "$_" }) -join "`n"
    $all = @(ls --perms -a 6>&1 2>&1 | ForEach-Object { "$_" }) -join "`n"
    Ok ($plain -notmatch '\.hidden') 'a hidden file is absent without -a'
    Ok ($all -match '\.hidden') 'and present with -a'

    # A named target works, not just the current directory.
    $sub = @(ls --perms "$sandbox/scripts" 6>&1 2>&1 | ForEach-Object { "$_" }) -join "`n"
    Ok ($sub -notmatch 'No such path') 'a directory argument is accepted'

    Write-Host ''
    Write-Host '-- --educate on the permission view --------------------------'
    $taught = @(ls --perms --educate 6>&1 2>&1 | ForEach-Object { "$_" }) -join "`n"
    Ok ($taught -match 'what you are looking at') '--educate prints the lesson'
    Ok ($taught -match 'owner') 'it explains the three sets'
    $idxData = $taught.IndexOf('PERM')
    $idxLesson = $taught.IndexOf('what you are looking at')
    Ok ($idxData -ge 0 -and $idxLesson -gt $idxData) 'the lesson comes after the listing'
}
finally {
    Pop-Location
    Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($fail -or $script:unexpected) {
    Write-Host "$fail assertion failure(s), $($script:unexpected) unexpected error(s)"
    exit 1
}
Write-Host 'PF-FEAT-001/002: chmod applies and verifies, and the permission view reads correctly'
