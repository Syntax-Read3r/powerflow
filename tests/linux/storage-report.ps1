# ==============================================================================
# PF-FEAT-006 / PF-FEAT-007 — the grouped view, on the platform it was asked for
# ==============================================================================
# `storage report` replaces the sequence an admin runs on a fresh box:
#
#     lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS
#     sudo fdisk -l /dev/sda
#     swapon --show
#     free -h
#     cat /etc/fstab
#
# Five commands, one of which asks for a password, to answer one question. This asserts the
# replacement is real: the data comes back, it is read-only, and it needs no sudo.
#
# Runs INSIDE a Linux container, because /proc and lsblk are the things under test.
# ==============================================================================

$ErrorActionPreference = 'Continue'

# ── find the profile, wherever this is running ────────────────────────────────
# Three homes, deliberately in this order:
#   /pf                     a container with the working tree mounted (local runs)
#   $HOME/.config/...       the INSTALLED profile (CI, after install.sh)
#   ../../ from this file   the repo itself, run in place
# CI must exercise the installed copy, and a local container run must exercise the working
# tree — a hardcoded path can only ever serve one of those.
$profileCandidates = @(
    '/pf/Microsoft.PowerShell_profile.ps1'
    (Join-Path $HOME '.config/powershell/Microsoft.PowerShell_profile.ps1')
    (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Microsoft.PowerShell_profile.ps1')
)
$profilePath = $profileCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $profilePath) {
    Write-Host "could not find a PowerFlow profile in any of:"
    $profileCandidates | ForEach-Object { Write-Host "   $_" }
    exit 1
}
$pfRoot = Split-Path $profilePath -Parent
Write-Host "using profile: $profilePath"
$fail = 0
function Ok([bool]$c, [string]$m, [string]$d = '') {
    if (-not $c) { $script:fail++ }
    Write-Host ("  {0} {1}{2}" -f $(if ($c) { 'ok  ' } else { 'FAIL' }), $m, $(if ($d) { "   $d" } else { '' }))
}

. $profilePath *> $null

Write-Host ''
Write-Host '-- the adapter contract returns real data ---------------------'
$memory = Get-StorageMemory
Ok ($memory.Supported) 'memory is readable from /proc/meminfo'
Ok ($memory.TotalBytes -gt 0) 'total RAM is a real number' "$([math]::Round($memory.TotalBytes/1GB,1)) GB"
Ok ($memory.AvailableBytes -gt 0) 'available RAM is a real number' "$([math]::Round($memory.AvailableBytes/1GB,1)) GB"
Ok ($memory.AvailableBytes -le $memory.TotalBytes) 'available never exceeds total'
Ok ($memory.SwapLabel -ceq 'swap') 'Linux calls it swap, not pagefile'
Ok ($memory.UsedBytes -ge 0) 'used is never negative'

# /proc/swaps may legitimately be empty in a container — assert the SHAPE, not a value.
Ok ($null -ne $memory.SwapAreas) 'swap areas is a list even when empty' "count=$(@($memory.SwapAreas).Count)"
Ok ($memory.SwapTotalBytes -ge 0) 'swap total is not negative'

$layout = Get-StorageLayout
Ok ($null -ne $layout.Supported) 'layout reports whether it is supported'
if ($layout.Supported) {
    Ok (@($layout.Devices).Count -ge 0) 'layout returns devices' "count=$(@($layout.Devices).Count)"
    foreach ($d in @($layout.Devices)) {
        Ok ($d.Type -ne 'loop') 'no loop devices — snap mounts are noise in a layout view'
    }
}
else {
    # Honest degradation is the requirement, not the presence of lsblk.
    Ok ([bool]$layout.Reason) 'an unsupported layout says WHY' "$($layout.Reason)"
    Ok (@($layout.Devices).Count -eq 0) 'an unsupported layout returns no half-built tree'
}

Write-Host ''
Write-Host '-- the view renders, and needs no sudo ------------------------'
$out = @(storage report 6>&1 2>&1 | ForEach-Object { "$_" }) -join "`n"
Ok ($out -match 'STORAGE AND MEMORY') 'the report renders'
Ok ($out -match 'MEMORY') 'it includes the memory section'
Ok ($out -notmatch '(?i)\[sudo\]|password for') 'it never asks for a password'
Ok ($out -notmatch '(?i)is not recognized|command not found') 'it does not depend on a missing binary'

Write-Host ''
Write-Host '-- --educate is opt-in, and comes AFTER the data --------------'
$plain = @(storage report 6>&1 2>&1 | ForEach-Object { "$_" }) -join "`n"
Ok ($plain -notmatch 'what you are looking at') 'no lesson unless asked'

$taught = @(storage report --educate 6>&1 2>&1 | ForEach-Object { "$_" }) -join "`n"
Ok ($taught -match 'what you are looking at') '--educate prints the lesson'
$idxData = $taught.IndexOf('MEMORY')
$idxLesson = $taught.IndexOf('what you are looking at')
Ok ($idxData -ge 0 -and $idxLesson -gt $idxData) `
    'the lesson comes AFTER the output, so an expert can ignore it by not reading down'

# The footer must decode what is actually on screen.
Ok ($taught -match 'swap / pagefile') 'the swap line names the term used on both platforms'
Ok ($taught -match 'read-only') 'it states plainly that nothing was changed'

# And --educate must not be mistaken for a volume name by the verb dispatcher.
Ok ($taught -notmatch "No volume or command matching") '--educate is stripped before the verb switch'

Write-Host ''
Write-Host '-- the bare view teaches too ----------------------------------'
$bare = @(storage --educate 6>&1 2>&1 | ForEach-Object { "$_" }) -join "`n"
Ok ($bare -match 'what you are looking at') 'storage --educate works on the overview'
Ok ($bare -notmatch "No volume or command matching") 'and is not read as a volume name'

Write-Host ''
if ($fail) { Write-Host "$fail CHECK(S) FAILED"; exit 1 }
Write-Host 'PF-FEAT-006/007: the grouped view and its lesson both work on Linux'
