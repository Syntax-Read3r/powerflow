# ==============================================================================
# git-rl in a project that was never set up: deliver the walkthrough, don't lie
# ==============================================================================
# Reported from a real machine. Running `git-rl` in a repo with no version file and no
# v* tag printed a small warning, dropped into the bump-type picker anyway, and — when the
# user escaped a release that could never have worked — reported "❌ Release cancelled".
# That is false twice: no release was possible, so nothing was cancelled, and the message
# blamed the user for backing out.
#
# The walkthrough for setting a project up already existed (`git-rl -h` writes it). The fix
# routes the not-set-up state to it: write docs/git-release-help.md into the repo, say so,
# and stop. These assertions hold that behaviour, including the two tripwires that matter:
# the picker must never open, and nothing may prompt.
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
$script:clipboard = $null

# No version file, no tag — the exact state the report came from.
function Get-ProjectVersion { param($RepoRoot)
    return [pscustomobject]@{ Version = '0.0.0'; Sources = @(); From = 'default' } }

# The guide content, canned: the test must not depend on the network.
function Get-GitReleaseDocs {
    return [pscustomobject]@{ Prompt = 'CANNED SETUP PROMPT'; Manual = 'CANNED MANUAL' } }

function Copy-ToClipboard { param($Text) $script:clipboard = $Text }

# TRIPWIRES. Reaching either one is the old behaviour coming back.
function fzf { throw 'TRIPWIRE: the bump picker must not open in a project that is not set up' }
function Read-Host { param($Prompt) throw "TRIPWIRE: nothing may prompt ($Prompt)" }

# ── a real, empty git repo ────────────────────────────────────────────────────
$sandbox = Join-Path ([IO.Path]::GetTempPath()) "pf-rl-setup-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $sandbox | Out-Null
Push-Location $sandbox
try {
    git init --quiet 2>$null

    # ── first run: writes the walkthrough and says so ─────────────────────────
    $out = @(Invoke-GitReleaseCommand 6>&1 2>&1 | ForEach-Object { "$_" }) -join "`n"

    Ok ($out -notmatch 'Release cancelled') 'must not claim a release was cancelled'
    Ok ($out -match "isn't set up for git-rl") 'must say plainly that the project is not set up'
    Ok ($out -match 'version source') 'must name what a release needs'
    Ok ($out -match 'walkthrough .* has been written|has been written to docs/git-release-help\.md') `
        'must inform the user the walkthrough was written'

    $guide = Join-Path $sandbox 'docs/git-release-help.md'
    Ok (Test-Path $guide) 'docs/git-release-help.md must exist in the project'
    $guideText = Get-Content $guide -Raw
    Ok ($guideText -match 'CANNED SETUP PROMPT') 'the guide must contain the AI setup prompt'
    Ok ($guideText -match 'CANNED MANUAL') 'the guide must contain the manual'
    Ok ($script:clipboard -eq 'CANNED SETUP PROMPT') 'the AI prompt must land on the clipboard'

    # ── second run: points at the existing file, rewrites nothing, asks nothing ──
    $before = (Get-Item $guide).LastWriteTimeUtc
    $again = @(Invoke-GitReleaseCommand 6>&1 2>&1 | ForEach-Object { "$_" }) -join "`n"

    Ok ($again -match 'already in this project') 'second run should point at the existing walkthrough'
    Ok ($again -notmatch 'Release cancelled') 'second run must not claim a cancellation either'
    Ok (((Get-Item $guide).LastWriteTimeUtc) -eq $before) 'second run must not rewrite the guide'
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
