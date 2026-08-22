$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
}

# ==============================================================================
# nav's THREE outcomes must stay three.
#
# THE BUG THIS EXISTS FOR. `nav` piped its candidates to fzf with --select-1 --exit-0 and
# then tested only whether the result string was empty:
#
#     if ($selected) { ... } else { Write-Host "❌ Cancelled" }
#
# fzf exits 0 on a selection, 1 when NOTHING MATCHED, and 130 on Escape. Two opposite
# outcomes therefore reached one branch, and the branch printed the message written for the
# other one: a mistyped directory name -- `nav zovoya` for `zavoya` -- was reported to the
# user as a cancellation they never made. Reported from real use.
#
# The suggester is exercised for real. The exit-code branching is asserted against the
# SOURCE, which is weaker and says so: driving it would need a pty for fzf to raise 130 on,
# and a test that fakes the thing under test proves nothing about it. The same trade-off,
# for the same reason, as tests/network/askpass-echo.ps1.
# ==============================================================================

$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$navFile = Join-Path $repo 'components/navigation/nav.ps1'
Assert-True (Test-Path -LiteralPath $navFile) 'nav.ps1 exists'

# Lift the pure function out rather than loading nav.ps1, which would pull in bookmarks,
# roots, projects and the whole adapter contract for the sake of one string comparison.
$src = Get-Content -LiteralPath $navFile -Raw
$fn = [regex]::Match($src, '(?s)function Get-PFNearestName \{.*?\n\}').Value
Assert-True ([bool]$fn) 'Get-PFNearestName is present in nav.ps1'
Invoke-Expression $fn

$dirs = @('zavoya', 'powerflow', 'Hutano-360', 'AI', 'Apps', 'Games', 'Utils', 'Worktrees')

# ---- the reported typo ------------------------------------------------------
Assert-True ((Get-PFNearestName -Attempt 'zovoya' -Known $dirs) -eq 'zavoya') 'the reported typo suggests the real directory'

# ---- a half-typed name is the commonest miss, so prefixes win first ---------
Assert-True ((Get-PFNearestName -Attempt 'powerflo' -Known $dirs) -eq 'powerflow') 'a prefix suggests the full name'
Assert-True ((Get-PFNearestName -Attempt 'Hutano' -Known $dirs) -eq 'Hutano-360') 'a prefix works across a dash'

# ---- DASHES ARE PART OF A DIRECTORY NAME -----------------------------------
# Get-PFFlagSuggestion strips them before comparing, which is right for --dry-run and wrong
# here: removing the dash from Hutano-360 invents a different word. That is why this is a
# separate function rather than a reuse.
Assert-True ((Get-PFNearestName -Attempt 'Hutano-350' -Known $dirs) -eq 'Hutano-360') 'a dashed name matches on its real characters'

# ---- case must not matter --------------------------------------------------
# Deliberately a case-different TYPO, not a case-different exact match: 'ZAVOYA' would have
# been found by fzf's own case-insensitive matching and never reached the suggester at all.
Assert-True ((Get-PFNearestName -Attempt 'ZOVOYA' -Known $dirs) -eq 'zavoya') 'a typo matches case-insensitively'
Assert-True ((Get-PFNearestName -Attempt 'ZAVOYA' -Known $dirs) -eq '') 'a case-different exact match is still an exact match, not a near miss'

# ---- silence beats a confident wrong guess ---------------------------------
# A name three edits away is not a suggestion, it is a guess, and it sends someone to check
# a directory that was never the one.
Assert-True ((Get-PFNearestName -Attempt 'zzzzzz' -Known $dirs) -eq '') 'nothing close enough suggests nothing'
Assert-True ((Get-PFNearestName -Attempt 'completely-unrelated' -Known $dirs) -eq '') 'a long unrelated word suggests nothing'
Assert-True ((Get-PFNearestName -Attempt 'zavoya' -Known $dirs) -eq '') 'an exact match is not a near miss'
Assert-True ((Get-PFNearestName -Attempt 'anything' -Known @()) -eq '') 'no candidates suggests nothing'
Assert-True ((Get-PFNearestName -Attempt '' -Known $dirs) -eq '') 'an empty attempt suggests nothing'

# ---- the three branches, asserted on the source ----------------------------
Assert-True ($src -match '\$fzfExit\s*=\s*\$LASTEXITCODE') 'the fzf exit code is captured, not discarded'
Assert-True ($src -match '\$fzfExit\s*-eq\s*130') 'Escape (130) is handled as its own outcome'
Assert-True ($src -match '↩ Cancelled\.') 'a cancellation uses the house marker, not a red cross'
Assert-True ($src -match "Nothing matching '\`$query'") 'a no-match says nothing matched, naming what was typed'
Assert-True ($src -match 'Get-PFNearestName -Attempt \$query') 'a no-match offers the nearest real name'

# $LASTEXITCODE is clobbered by the next command that sets it, including Write-Host in some
# hosts, so capturing it late would reintroduce the bug in a form that is harder to see.
$after = [regex]::Match($src, '(?s)\| fzf.*?\$fzfExit\s*=\s*\$LASTEXITCODE').Value
Assert-True ([bool]$after) 'the capture follows the fzf call'
# Comments are stripped first: the explanation between the two lines mentions Write-Host by
# name, and a check that trips on its own prose is a check that will be deleted rather than
# understood.
$code = @($after -split "`n" | Where-Object { $_.Trim() -and $_.Trim() -notmatch '^#' })
Assert-True (($code | Where-Object { $_ -match 'Write-Host|Write-Output' }).Count -eq 0) 'nothing runs between fzf and the capture that could clobber the exit code'

# The old message must not come back.
#
# Against COMMENT-STRIPPED source, and the reason is a lesson this repo has already paid for
# three times over -- the adapter-parity gate records it in as many words: "a name mentioned
# only in prose is not a call, and three tests in this repo have already been fooled by
# matching their own explanatory comments." nav.ps1 quotes the old message while explaining
# why it was wrong, so a naive scan of the raw file fails on the very comment documenting
# the fix.
$codeOnly = (@($src -split "`n" | Where-Object { $_.Trim() -notmatch '^#' }) -join "`n")
Assert-True ($codeOnly -notmatch '❌ Cancelled') 'the red-cross cancellation message is gone from the code'
Assert-True ($src -match '❌ Cancelled') 'and survives in a comment, so the reason it was wrong is not lost'

Write-Host 'OK - nav separates selection, cancellation and no-match, and names the near miss.'
