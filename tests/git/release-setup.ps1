# ==============================================================================
# git-rl in a project that was never set up: report and point, never write, never lie
# ==============================================================================
# Reported from a real machine. Running `git-rl` in a repo with no version file and no
# v* tag printed a small warning, dropped into the bump-type picker anyway, and — when the
# user escaped a release that could never have worked — reported "❌ Release cancelled".
# That is false twice: no release was possible, so nothing was cancelled, and the message
# blamed the user for backing out.
#
# The correct behaviour, per the owner: say the project is not set up and point at
# `git-rl -h`, which already owns delivering the walkthrough AND asks "are you in your
# project folder?" before writing a byte. A first fix wrote the guide straight into the
# current repo; that was rejected because bare `git-rl` may be run in any repo — a clone,
# a scratch checkout — and creating files there as the side effect of a status query
# assumes it is the project the user wants a pipeline in.
#
# Three tripwires hold that shape: the picker must not open, nothing may prompt, and
# nothing may be written.
# ==============================================================================

$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
}
$assertions = 0
function Ok([bool]$c, [string]$m) { Assert-True $c $m; $script:assertions++ }

$root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

# ── stubs, defined AFTER the real file so they win ────────────────────────────
function Register-PFCommand { }
. (Join-Path $root 'components/shared/flags.ps1')
. (Join-Path $root 'components/git/release.ps1')

$script:POWERFLOW_REPO = 'example/powerflow'

# No version file, no tag — the exact state the report came from.
function Get-ProjectVersion { param($RepoRoot)
    return [pscustomobject]@{ Version = '0.0.0'; Sources = @(); From = 'default' } }

# The guide content, canned: no test may depend on the network.
function Get-GitReleaseDocs {
    return [pscustomobject]@{ Prompt = 'CANNED SETUP PROMPT'; Manual = 'CANNED MANUAL' } }
$script:clipboard = $null
function Copy-ToClipboard { param($Text) $script:clipboard = $Text }

# Defined before EVERY section: an unexpected prompt must fail loudly, not hang a headless
# run waiting for input that will never come.
function Read-Host { param($Prompt) throw "TRIPWIRE: nothing may prompt ($Prompt)" }

# ══════════════════════════════════════════════════════════════════════════════
#  A · `git-rl -h`, answered "yes": deliver, and SAY the delivery already happened
# ══════════════════════════════════════════════════════════════════════════════
# Second field report on this command. The guide was written correctly, but the
# clipboard-led messaging ("paste the prompt into your AI assistant") read as though some
# paste step was still needed to get the file into the repo — when selecting "yes" had
# already put it there. The message must now lead with that fact, put the nothing-to-paste
# in-repo assistant route first, and spell out that "paste" means Ctrl+V.
#
# fzf is stubbed to pick the first choice — the "yes" row — so the interactive flow runs
# headless with the REAL Write-GitReleaseGuide underneath.
function fzf { $input | Select-Object -First 1 }

$sandboxA = Join-Path ([IO.Path]::GetTempPath()) "pf-rl-h-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $sandboxA | Out-Null
Push-Location $sandboxA
try {
    git init --quiet 2>$null
    $out = @(Show-GitReleaseSetupPrompt 6>&1 2>&1 | ForEach-Object { "$_" }) -join "`n"

    Ok (Test-Path (Join-Path $sandboxA 'docs/git-release-help.md')) `
        'answering yes must write docs/git-release-help.md'
    Ok ($script:clipboard -eq 'CANNED SETUP PROMPT') 'the AI prompt must land on the clipboard'

    Ok ($out -match 'walkthrough is in your project') `
        'the message must lead with the fact the file is ALREADY in the project'
    Ok ($out -match 'nothing to paste') `
        'the in-repo assistant route must say nothing needs pasting'
    Ok ($out -match 'Claude Code|IN this repo') 'the in-repo assistant route must come first and be named'
    Ok ($out -match 'Ctrl\+V') '"paste" must be spelled out as Ctrl+V for the web-chat route'
    Ok ($out -match 'git-rl') 'must end by pointing back at git-rl for the first release'
    Ok ($out -notmatch 'paste it into your assistant now') `
        'the old instruction-shaped clipboard line must not come back'
}
finally {
    Pop-Location
    Remove-Item $sandboxA -Recurse -Force -ErrorAction SilentlyContinue
}

# ══════════════════════════════════════════════════════════════════════════════
#  B · bare `git-rl` in a project that was never set up
# ══════════════════════════════════════════════════════════════════════════════
# TRIPWIRES. Reaching any of these is a regression:
#   fzf                  -> the bump picker opened for an impossible release
#   Read-Host            -> something prompted during a status report
#   Write-GitReleaseGuide -> bare git-rl wrote into a repo nobody confirmed as the target
function fzf { throw 'TRIPWIRE: the bump picker must not open in a project that is not set up' }
function Read-Host { param($Prompt) throw "TRIPWIRE: nothing may prompt ($Prompt)" }
function Write-GitReleaseGuide { param($ProjectRoot)
    throw 'TRIPWIRE: bare git-rl must not write the guide — only git-rl -h may, after asking' }

# ── a real, empty git repo ────────────────────────────────────────────────────
$sandbox = Join-Path ([IO.Path]::GetTempPath()) "pf-rl-setup-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $sandbox | Out-Null
Push-Location $sandbox
try {
    git init --quiet 2>$null

    # ── no guide present: report, and point at git-rl -h ──────────────────────
    $out = @(Invoke-GitReleaseCommand 6>&1 2>&1 | ForEach-Object { "$_" }) -join "`n"

    Ok ($out -notmatch 'Release cancelled') 'must not claim a release was cancelled'
    Ok ($out -match "isn't set up for git-rl") 'must say plainly that the project is not set up'
    Ok ($out -match 'version source') 'must name what a release needs'
    Ok ($out -match 'git-rl -h') 'must point at git-rl -h, the flow that asks before writing'

    # NOTHING may have been created. The first fix made a docs/ directory and a guide file
    # in whatever repo the user stood in; both are asserted away.
    Ok (-not (Test-Path (Join-Path $sandbox 'docs'))) 'must not create a docs/ directory'
    Ok (@(Get-ChildItem $sandbox -Force | Where-Object { $_.Name -ne '.git' }).Count -eq 0) `
        'must not create any file in the repo — this is a status report, not a delivery'

    # ── guide already present (delivered by git-rl -h earlier): point at IT ───
    New-Item -ItemType Directory -Path (Join-Path $sandbox 'docs') | Out-Null
    Set-Content -Path (Join-Path $sandbox 'docs/git-release-help.md') -Value 'existing guide'
    $before = (Get-Item (Join-Path $sandbox 'docs/git-release-help.md')).LastWriteTimeUtc

    $again = @(Invoke-GitReleaseCommand 6>&1 2>&1 | ForEach-Object { "$_" }) -join "`n"

    Ok ($again -match 'already in this project') 'with the guide present, point at the file'
    Ok ($again -notmatch 'git-rl -h') 'must not send the user to rewrite a guide they already have'
    Ok ($again -notmatch 'Release cancelled') 'still no cancellation claim'
    Ok (((Get-Item (Join-Path $sandbox 'docs/git-release-help.md')).LastWriteTimeUtc) -eq $before) `
        'the existing guide must not be touched'
}
finally {
    Pop-Location
    Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

# ── and a set-up project must NOT get the walkthrough treatment ───────────────
# From 'files' means a version source exists; the command must proceed toward the picker.
# The fzf tripwire doubles as the success signal: reaching it proves the setup branch was
# correctly skipped, without this test having to drive a real release.
#
# Test-VersionDrift lives in version-files.ps1, which this test deliberately does not load
# (it would drag the real Get-ProjectVersion in with it). One source cannot drift.
function Test-VersionDrift { param($Sources) return $false }
function Get-ProjectVersion { param($RepoRoot)
    return [pscustomobject]@{
        Version = '1.2.3'
        Sources = @([pscustomobject]@{ Label = 'VERSION'; Version = '1.2.3'; Path = 'VERSION' })
        From = 'files'
    } }

$sandbox2 = Join-Path ([IO.Path]::GetTempPath()) "pf-rl-setup2-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $sandbox2 | Out-Null
Push-Location $sandbox2
try {
    git init --quiet 2>$null
    $reachedPicker = $false
    try { $null = Invoke-GitReleaseCommand 6>$null 2>$null }
    catch { $reachedPicker = ($_.Exception.Message -match 'bump picker') }
    Ok $reachedPicker 'a set-up project must proceed to the bump picker, not the walkthrough'
}
finally {
    Pop-Location
    Remove-Item $sandbox2 -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "  git-rl setup path: $assertions assertions passed" -ForegroundColor Green
