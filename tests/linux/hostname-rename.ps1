# ==============================================================================
# PF-FEAT-005 — pc-name: rename the host WITHOUT breaking name resolution
# ==============================================================================
# The bug this replaces is not hypothetical. `hostnamectl set-hostname web-prod` alone
# leaves /etc/hosts naming the old host, and the very next sudo prints:
#
#     sudo: unable to resolve host web-prod: Name or service not known
#
# It still works — sudo falls back after a timeout — but every elevated command is slower
# and noisier until somebody edits the file by hand.
#
# Runs INSIDE a Linux container, because /etc/hosts and the rewrite are what is under test.
# The container is disposable, so this writes a REAL /etc/hosts rather than a fixture: the
# thing being asserted is that the adapter reads and rewrites the real file correctly.
#
#   podman run --rm -v "${PWD}:/pf:ro" mcr.microsoft.com/powershell:latest \
#       pwsh -File /pf/tests/linux/hostname-rename.ps1
# ==============================================================================

$ErrorActionPreference = 'Continue'

$profileCandidates = @(
    '/pf/Microsoft.PowerShell_profile.ps1'
    (Join-Path $HOME '.config/powershell/Microsoft.PowerShell_profile.ps1')
    (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Microsoft.PowerShell_profile.ps1')
)
$profilePath = $profileCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $profilePath) {
    Write-Host 'could not find a PowerFlow profile in any of:'
    $profileCandidates | ForEach-Object { Write-Host "   $_" }
    exit 1
}
Write-Host "using profile: $profilePath"

$fail = 0
function Ok([bool]$c, [string]$m, [string]$d = '') {
    if (-not $c) { $script:fail++ }
    Write-Host ("  {0} {1}{2}" -f $(if ($c) { 'ok  ' } else { 'FAIL' }), $m, $(if ($d) { "   $d" } else { '' }))
}

# An unexpected terminating error must not be able to reach the bottom of this file and
# print SUCCESS. A previous test in this directory did exactly that.
$unexpected = 0
trap { $script:unexpected++; Write-Host "  FAIL unexpected error: $_"; continue }

. $profilePath *> $null

$current = "$(hostname)".Trim()
Write-Host "current hostname: $current"

# ── the name validator ───────────────────────────────────────────────────────
Write-Host ''
Write-Host '-- names are validated BEFORE anything is changed --------------'
Ok ((Test-HostNameValid -Name 'web-prod').Valid) 'a normal hostname is accepted'
Ok ((Test-HostNameValid -Name 'db1').Valid) 'digits inside a name are fine'
Ok (-not (Test-HostNameValid -Name 'web_prod').Valid) 'underscores are refused' 'legal on Windows, illegal in DNS'
Ok ((Test-HostNameValid -Name 'web_prod').Error -match 'underscore') 'and the refusal SAYS underscore, not just "invalid"'
Ok (-not (Test-HostNameValid -Name '-web').Valid) 'a leading hyphen is refused'
Ok (-not (Test-HostNameValid -Name 'web-').Valid) 'a trailing hyphen is refused'
Ok (-not (Test-HostNameValid -Name '').Valid) 'an empty name is refused'
Ok (-not (Test-HostNameValid -Name '10').Valid) 'an all-digit name is refused' 'resolvers read it as an address'
Ok (-not (Test-HostNameValid -Name ('a' * 64)).Valid) 'a 64-character label is refused' 'RFC 1123 caps a label at 63'
Ok ((Test-HostNameValid -Name ('a' * 63)).Valid) 'a 63-character label is accepted'

# ── the plan, against a real /etc/hosts ──────────────────────────────────────
Write-Host ''
Write-Host '-- the plan reads the real /etc/hosts --------------------------'

$hostsBackup = "/tmp/hosts.testbackup"
Copy-Item /etc/hosts $hostsBackup -Force -ErrorAction SilentlyContinue

# A Debian-shaped file: a loopback line, the local-host line, an operator's own static
# entry, a comment, and the IPv6 boilerplate. Only ONE of these may be rewritten.
$fixture = @(
    '127.0.0.1	localhost'
    "127.0.1.1	$current.example.lan $current"
    '# a comment naming ' + $current + ' that must not be touched'
    '10.0.0.5	buildbox'
    '::1	localhost ip6-localhost ip6-loopback'
)
Set-Content -Path /etc/hosts -Value $fixture -Encoding utf8

$plan = Get-HostRenamePlan -NewName 'web-prod'
Ok ($plan.Valid) 'a valid rename produces a plan'
Ok ($plan.Current -eq $current) 'the plan reports the CURRENT name' $plan.Current
Ok ($plan.New -eq 'web-prod') 'and the new one'
Ok ($plan.LineNumber -eq 2) 'it finds the local-host line' "line $($plan.LineNumber)"
Ok ($plan.Before -eq $fixture[1]) 'the before-line is the real line, character for character'
Ok ($plan.After -match 'web-prod') 'the after-line carries the new name'
Ok ($plan.After -notmatch [regex]::Escape($current)) 'and no longer carries the old one'
Ok ($plan.After -match '^127\.0\.1\.1') 'the address is preserved'
Ok ($plan.After -match 'web-prod\.example\.lan') 'the domain suffix survives the rename' $plan.Fqdn
Ok ($plan.Fqdn -eq 'web-prod.example.lan') 'the FQDN is reported back'

Write-Host ''
Write-Host '-- the plan changes nothing ------------------------------------'
$afterPlan = @(Get-Content /etc/hosts)
Ok (($afterPlan -join "`n") -eq ($fixture -join "`n")) 'building a plan is read-only'

Write-Host ''
Write-Host '-- refusals are refusals, not plans ----------------------------'
$same = Get-HostRenamePlan -NewName $current
Ok (-not $same.Valid) 'renaming to the current name is refused'
Ok ($same.Error -match 'already') 'and says why'
$bad = Get-HostRenamePlan -NewName 'web_prod'
Ok (-not $bad.Valid) 'an invalid name never reaches a plan'
Ok ($bad.LineNumber -eq 0 -and -not $bad.Before) 'a refused plan carries no edit'

# ── only the matching line is targeted ───────────────────────────────────────
Write-Host ''
Write-Host '-- a host with no local-host entry is not given one ------------'
Set-Content -Path /etc/hosts -Value @(
    '127.0.0.1	localhost'
    '10.0.0.5	buildbox'
) -Encoding utf8
$none = Get-HostRenamePlan -NewName 'web-prod'
Ok ($none.Valid) 'the rename is still valid'
Ok (-not $none.Before) 'but there is no line to rewrite' 'no entry is invented'
Ok ($none.LineNumber -eq 0) 'and no line number is claimed'

Write-Host ''
Write-Host '-- a comment naming the host is not an entry -------------------'
Set-Content -Path /etc/hosts -Value @(
    "# 127.0.1.1	$current is what this used to be"
    '127.0.0.1	localhost'
) -Encoding utf8
$commented = Get-HostRenamePlan -NewName 'web-prod'
Ok (-not $commented.Before) 'a commented-out line is skipped'

# ── the failure path: hostnamectl cannot run here, and that must be safe ─────
# A plain container has no systemd, so hostnamectl fails. That is not a gap in the test —
# it is the most important case: when the rename fails, /etc/hosts must be untouched.
Write-Host ''
Write-Host '-- a failed rename leaves /etc/hosts alone ---------------------'
Set-Content -Path /etc/hosts -Value $fixture -Encoding utf8
$before = @(Get-Content /etc/hosts) -join "`n"

$result = Set-HostRename -NewName 'web-prod' -HostsBefore $fixture[1] -HostsAfter '127.0.1.1	web-prod.example.lan web-prod'
$after = @(Get-Content /etc/hosts) -join "`n"

if ($result.Success) {
    # A privileged container CAN rename. Then the edit must have landed, exactly once.
    Ok ($result.HostnameSet) 'the hostname was set'
    Ok ($after -match 'web-prod') '/etc/hosts was updated'
    Ok ($after -notmatch '10\.0\.0\.5\s+buildbox-') 'the operator static entry is untouched'
    Ok (($after -split "`n" | Where-Object { $_ -match '^10\.0\.0\.5' }).Count -eq 1) 'exactly one static entry remains'
    Ok ($after -match '# a comment naming') 'the comment survives'
    Ok ([bool]$result.BackupPath -and (Test-Path $result.BackupPath)) 'a backup was written first' $result.BackupPath
    Ok ((Get-Content $result.BackupPath -Raw).Contains($fixture[1])) 'and the backup holds the ORIGINAL line'
}
else {
    Ok (-not $result.HostnameSet) 'the hostname was not set'
    Ok ($after -eq $before) '/etc/hosts is byte-identical after a failed rename'
    Ok ([bool]$result.Error) 'and the failure says something' $result.Error
    Ok ($result.Error -notmatch 'Exception|System\.') 'in words, not a stack trace'
    Ok (-not $result.HostsUpdated) 'it does not claim a sync that never happened'
}

# ── a stale preview must not be applied ──────────────────────────────────────
Write-Host ''
Write-Host '-- an edit nobody previewed is never written -------------------'
Set-Content -Path /etc/hosts -Value $fixture -Encoding utf8
$stale = Set-HostRename -NewName 'other-host' -HostsBefore '127.0.1.1	a-line-that-is-not-there' -HostsAfter '127.0.1.1	other-host'
$afterStale = @(Get-Content /etc/hosts) -join "`n"
Ok (-not $stale.HostsUpdated) 'a before-line that no longer matches is not applied'
Ok ($afterStale -notmatch 'other-host') 'and nothing was written'

# ── the command surface ──────────────────────────────────────────────────────
Write-Host ''
Write-Host '-- pc-name is wired up ----------------------------------------'
Ok ([bool](Get-Command pc-name -ErrorAction SilentlyContinue)) 'pc-name exists'
Ok ([bool](Get-Alias pc-hostname -ErrorAction SilentlyContinue)) 'pc-hostname is an alias for it'

$bare = @(pc-name 6>&1 2>&1 | ForEach-Object { "$_" }) -join "`n"
Ok ($bare -match 'This machine is called') 'bare pc-name reports, it does not rename'
Ok ($bare -notmatch '(?i)continue\?') 'and does not prompt'

$refused = @(pc-name web_prod 6>&1 2>&1 | ForEach-Object { "$_" }) -join "`n"
Ok ($refused -match 'not a valid hostname') 'an invalid name is refused at the surface'
Ok ($refused -notmatch '(?i)continue\?') 'without asking to confirm something impossible'

# Re-read: in a privileged container the block above really did rename this machine, so
# the name captured at the top of the file is no longer current. Asserting against the
# stale one would fail for the wrong reason.
$now = "$(hostname)".Trim()
$target = if ($now -eq 'app-server') { 'db-server' } else { 'app-server' }

$piped = @(pc-name $target 6>&1 2>&1 | ForEach-Object { "$_" }) -join "`n"
Ok ($piped -match 'RENAME HOST') 'a valid name shows the preview'
Ok ($piped -match [regex]::Escape($now)) 'the preview names the current host' $now
Ok ($piped -match [regex]::Escape($target)) 'and the new one'
Ok ("$(hostname)".Trim() -eq $now) 'a preview with stdin redirected renames nothing'
Ok ($piped -match '(?i)--force') 'and says how to proceed without a prompt'

# ── end to end, where the machine can actually be renamed ────────────────────
# Only in a privileged container. Everywhere else this would be asserting on a refusal
# already covered above, so it is skipped rather than faked.
if ($result.Success) {
    Write-Host ''
    Write-Host '-- end to end: pc-name --force ---------------------------------'
    Set-Content -Path /etc/hosts -Value @(
        '127.0.0.1	localhost'
        "127.0.1.1	$now"
        '10.0.0.5	buildbox'
    ) -Encoding utf8

    $out = @(pc-name $target --force 6>&1 2>&1 | ForEach-Object { "$_" }) -join "`n"
    Ok ($out -match 'Host renamed') 'it reports the rename'
    Ok ("$(hostname)".Trim() -eq $target) 'the machine really is renamed' "$(hostname)"
    Ok ((Get-Content /etc/hosts -Raw) -match "127\.0\.1\.1\s+$([regex]::Escape($target))") '/etc/hosts names it too'
    Ok ((Get-Content /etc/hosts -Raw) -match '10\.0\.0\.5\s+buildbox') 'other entries are still there'

    # The whole point: the new name resolves, so sudo does not stall.
    $res = Test-HostResolution -Name $target
    Ok ($res.Checked) 'resolution is checked, not assumed'
    Ok ($res.Resolves) 'and the new name RESOLVES' $res.Detail
    Ok ($out -match '(?i)resolution') 'the report shows the resolution result'

    $taught = @(pc-name 'taught-host' --force --educate 6>&1 2>&1 | ForEach-Object { "$_" }) -join "`n"
    Ok ($taught -match 'what you are looking at') '--educate prints the lesson'
    $idxData = $taught.IndexOf('Host renamed')
    $idxLesson = $taught.IndexOf('what you are looking at')
    Ok ($idxData -ge 0 -and $idxLesson -gt $idxData) 'the lesson comes AFTER the report'
}

# ── restore ──────────────────────────────────────────────────────────────────
# This test really renames the machine when it can, so it really has to put it back. A CI
# job left with a hostname its /etc/hosts does not know inherits the exact sudo stall this
# feature exists to prevent, and every later step pays for it.
if (Test-Path $hostsBackup) { Copy-Item $hostsBackup /etc/hosts -Force; Remove-Item $hostsBackup -Force }
if ("$(hostname)".Trim() -ne $current) {
    $null = Set-MachineHostName -NewName $current
    Ok ("$(hostname)".Trim() -eq $current) 'the machine was restored to its original name' $current
}
Get-ChildItem /etc -Filter 'hosts.powerflow-*' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

Write-Host ''
if ($unexpected) { Write-Host "$unexpected UNEXPECTED ERROR(S)"; exit 1 }
if ($fail) { Write-Host "$fail CHECK(S) FAILED"; exit 1 }
Write-Host 'PF-FEAT-005: the rename previews both changes, backs up, and never touches a line it did not show you'
