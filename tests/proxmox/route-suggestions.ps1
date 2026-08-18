# ==============================================================================
# PF-UX-001 (b2) — `pmx list` / `pmx status`, and a typo that says what you meant
# ==============================================================================
# `qm list` muscle memory reaches for `pmx list`, which answered:
#
#     ❌ Unknown pmx command 'list'. Run: pmx help
#
# Two separate things here, and the second is the one with teeth:
#
#   1. The two routes. Both must call the SAME function as their canonical spelling —
#      another door into one view, not a second view that can drift from it.
#
#   2. The suggestion engine. A suggestion is a promise that the thing suggested exists;
#      a wrong one sends someone to type a command that does not run and teaches them to
#      distrust the tool rather than the typo. So the assertions below spend most of their
#      effort on the two ways it could lie: suggesting a route the router does not answer,
#      and suggesting anything at all when it has no business guessing.
#
# It never RUNS a suggestion. There is no "did you mean … [Y/n]", which is what makes a
# near-miss on a destructive word safe: `pmx destory` can print a suggestion precisely
# because printing is all it can do.
# ==============================================================================

. (Join-Path $PSScriptRoot 'test-helpers.ps1')

$root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$command = Get-Content -LiteralPath (Join-Path $root 'components/proxmox/command.ps1') -Raw

function Register-PFCommand { }
. (Join-Path $root 'components/proxmox/help.ps1')

Write-Host 'PF-UX-001 (b2) routes and suggestions'

# ── 1. the two routes reuse the canonical implementation ─────────────────────
$router = [regex]::Match($command, '(?s)switch \(\$group\) \{.*?\n    \}').Value
Assert-PmxTest ($router.Length -gt 0) 'could not find the top-level router'

foreach ($pair in @(
    @{ Group = 'list';   Function = 'Show-PmxManagedVmList';     Canonical = 'pmx vm list' }
    @{ Group = 'status'; Function = 'Show-PmxManagedNodeStatus'; Canonical = 'pmx node status' }
)) {
    $line = [regex]::Match($router, "(?m)^\s*'$($pair.Group)'\s*\{.*$").Value
    Assert-PmxTest ($line.Length -gt 0) "top-level '$($pair.Group)' should be routed"
    Assert-PmxTest ($line -match [regex]::Escape($pair.Function)) `
        "'$($pair.Group)' must call $($pair.Function) — the same function $($pair.Canonical) uses"
    Assert-PmxTest ($line -match '-Arguments \$tail') `
        "'$($pair.Group)' must forward the whole tail, so --json/--table work identically"
}
Write-PmxTestPass 'pmx list and pmx status are routes into the existing views'

# The canonical spellings must still exist — a shortcut that replaced its own long form
# would be a rename wearing a shortcut's clothes.
Assert-PmxTest ($command -match "'list'\s*\{\s*Show-PmxManagedVmList -Arguments \`$rest") `
    'pmx vm list must still route'
Assert-PmxTest ($router -match "'node'") 'pmx node status must still route'
Write-PmxTestPass 'the canonical spellings are untouched'

# ── 2. the catalogue backs the suggestions ───────────────────────────────────
$routes = @(Get-PmxKnownRoutes)
Assert-PmxTest ($routes.Count -gt 20) "the catalogue looks empty ($($routes.Count) routes)"
foreach ($expected in @('list', 'status', 'start', 'shutdown', 'vm', 'node', 'config', 'vm list', 'node status')) {
    Assert-PmxTest ($routes -contains $expected) "'$expected' should be a known route"
}
Write-PmxTestPass 'the route catalogue includes the convenience routes'

# THE assertion that keeps the engine honest: every single-word route it is willing to
# suggest must actually be answered by the router. A suggestion for a non-command is the
# one bug that makes suggestions worse than no suggestions.
$routerGroups = @([regex]::Matches($router, "(?m)^\s{8}'([a-z-]+)'") | ForEach-Object { $_.Groups[1].Value })
Assert-PmxTest ($routerGroups.Count -gt 10) "could not read the router groups (found $($routerGroups.Count))"
$phantom = @($routes | Where-Object { $_ -notmatch '\s' } | Where-Object { $_ -notin $routerGroups })
Assert-PmxTest ($phantom.Count -eq 0) `
    "these would be suggested but the router does not answer them: $($phantom -join ', ')"
Write-PmxTestPass 'every suggestible route is a route the router answers'

# ── 3. the reported typo, and its neighbours ─────────────────────────────────
foreach ($case in @(
    @{ Typo = 'lis';      Expect = 'list';     Why = 'the case from the report' }
    @{ Typo = 'stat';     Expect = 'status';   Why = 'a prefix of the new route' }
    @{ Typo = 'nod';      Expect = 'node';     Why = 'a dropped last letter' }
    @{ Typo = 'confg';    Expect = 'config';   Why = 'a dropped middle letter' }
    @{ Typo = 'discovr';  Expect = 'discover'; Why = 'a dropped vowel' }
    @{ Typo = 'snapshto'; Expect = 'snapshot'; Why = 'transposed letters' }
    @{ Typo = 'strat';    Expect = 'start';    Why = 'transposed letters in a short word' }
    @{ Typo = 'shutdow';  Expect = 'shutdown'; Why = 'a truncated long word' }
)) {
    $got = @(Get-PmxRouteSuggestions -Attempted $case.Typo)
    Assert-PmxTest ($got -contains $case.Expect) `
        "'$($case.Typo)' should suggest '$($case.Expect)' ($($case.Why)); got: $($got -join ', ')"
    Assert-PmxTest ($got.Count -le 3) "'$($case.Typo)' returned $($got.Count) suggestions; at most 3"
}
Write-PmxTestPass 'plausible typos get a bounded, correct suggestion'

# ── 4. silence is a valid answer ─────────────────────────────────────────────
# A guess offered with no confidence is noise wearing the costume of help.
foreach ($nonsense in @('zzzz', 'x', 'qqqqqqqqqq', 'aaaa-bbbb', '')) {
    $got = @(Get-PmxRouteSuggestions -Attempted $nonsense)
    Assert-PmxTest ($got.Count -eq 0) "'$nonsense' should suggest nothing; got: $($got -join ', ')"
}
Write-PmxTestPass 'nonsense gets no suggestion at all'

# A single character is a prefix of far too much to mean anything.
$got = @(Get-PmxRouteSuggestions -Attempted 's')
Assert-PmxTest ($got.Count -eq 0) "a single letter should not fan out; got: $($got -join ', ')"
Write-PmxTestPass 'one letter is not treated as a prefix'

# An exact route is never suggested back to the user.
foreach ($exact in @('list', 'vm', 'config')) {
    Assert-PmxTest (@(Get-PmxRouteSuggestions -Attempted $exact) -notcontains $exact) `
        "'$exact' should never be suggested as a correction for itself"
}
Write-PmxTestPass 'a route is never offered as a correction for itself'

# ── 5. the rendered message ──────────────────────────────────────────────────
function Get-Rendered {
    param([string]$Attempted)
    return (@(Write-PmxUnknownCommand -Attempted $Attempted 6>&1 | ForEach-Object { "$_" }) -join "`n")
}

$out = Get-Rendered 'lis'
Assert-PmxTest ($out -match "Unknown pmx command 'lis'") 'the message echoes the input EXACTLY as typed'
Assert-PmxTest ($out -match 'Did you mean') 'and offers the suggestion'
Assert-PmxTest ($out -match 'pmx list') 'spelled as a runnable command, not a bare word'
Write-PmxTestPass 'a near-miss shows the exact input and a runnable suggestion'

$out = Get-Rendered 'zzzz'
Assert-PmxTest ($out -match "Unknown pmx command 'zzzz'") 'nonsense still echoes the input'
Assert-PmxTest ($out -notmatch 'Did you mean') 'and offers nothing'
Assert-PmxTest ($out -match 'pmx help') 'falling back to help, as before'
Write-PmxTestPass 'no close match still points at pmx help'

# Odd input must not be normalised away — the character that caused the miss is the one
# worth seeing.
$out = Get-Rendered 'LiS'
Assert-PmxTest ($out -match "'LiS'") 'the input keeps its original case in the message'
Write-PmxTestPass 'input is echoed unmodified'

# ── 6. nothing here executes ─────────────────────────────────────────────────
# The suggestion policy's one hard rule. Read the source rather than trusting behaviour:
# a future edit that added an "apply it for you" prompt would still pass a behavioural test
# written before the prompt existed.
$helpSrc = Get-Content -LiteralPath (Join-Path $root 'components/proxmox/help.ps1') -Raw
$engine = [regex]::Match($helpSrc, '(?s)function Write-PmxUnknownCommand \{.*?\n\}').Value
Assert-PmxTest ($engine.Length -gt 0) 'could not find Write-PmxUnknownCommand'
foreach ($forbidden in @('Invoke-Expression', 'Invoke-PmxCommand', '& \$', 'Read-Host', 'Confirm-')) {
    Assert-PmxTest ($engine -notmatch $forbidden) `
        "the unknown-command path must not $forbidden — a suggestion is printed, never run"
}
Write-PmxTestPass 'a suggestion is printed and never executed'

Write-Host 'PF-UX-001 (b2): pmx list/status route into the existing views, and typos suggest without running.'
