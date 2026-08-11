# ==============================================================================
# PF-BUG-004 — inventory status and runtime status are separate facts
# ==============================================================================
# One view stated both of these at once:
#
#   Status        running
#   Agent         unavailable
#   ⚠ Current VM status could not be read; VM-reported network data was not queried.
#
# Three defects in one place:
#
#   1. TWO SOURCES, ONE FIELD. `$status` was seeded from the inventory (`pmx vm` / `qm list`)
#      and only overwritten on a successful runtime query. When that query failed the
#      inventory value survived AND the "could not be read" warning fired, so the view
#      contradicted itself.
#   2. A DISPLAY STRING USED AS A GATE. $shouldReadRuntime required $statusNative — the
#      --show-native text for the status query. Null on failure, so the guest-agent query was
#      skipped and `pmx vm ip 102` found no addresses on a VM that was demonstrably running.
#   3. AGENT STATE INFERRED FROM THE WRONG FACT. A branch reported the AGENT as unavailable
#      because the STATUS query had failed, and short-circuited ahead of the query, so the
#      agent was never actually asked.
# ==============================================================================

. (Join-Path $PSScriptRoot 'test-helpers.ps1')

$root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$rawSource = Get-Content -LiteralPath (Join-Path $root 'components/proxmox/network-read.ps1') -Raw

# CODE ONLY. The fix is documented in comments that quote the old strings verbatim — including
# the warning text this file asserts is gone — so scanning raw source would match the
# explanation of the bug and report the bug as still present.
$source = @($rawSource -split "`r?`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"

# ---- 1. the gate must not depend on the native display string -------------------------
$gate = [regex]::Match($source, '(?m)^\s*\$shouldReadRuntime\s*=.*$').Value
Assert-PmxTest ($gate.Length -gt 0) 'could not find the $shouldReadRuntime assignment'
Assert-PmxTest ($gate -notmatch '\$statusNative') @"
`$shouldReadRuntime must NOT depend on `$statusNative. That is the --show-native display
string; gating the guest-agent query on it means a failed status read silently stops
`pmx vm ip` from finding addresses. Gate: $gate
"@
Assert-PmxTest ($gate -match "\`$status -eq 'running'") 'the gate should still require a running VM'
Assert-PmxTest ($gate -match '\$agentConfig\.Configured') 'the gate should still require a configured agent channel'

# ---- 2. the two sources must be tracked separately ------------------------------------
Assert-PmxTest ($source -match '\$inventoryStatus\s*=') `
    'the inventory status must be held in its own variable, not folded into $status'
Assert-PmxTest ($source -match '\$statusSource\s*=') `
    'the model must record WHICH source the status came from'
Assert-PmxTest ($source -match 'StatusSource\s*=\s*\$statusSource') `
    'StatusSource must reach the VM model so the view can attribute the value'

# ---- 3. the self-contradicting warning must be gone ----------------------------------
Assert-PmxTest ($source -notmatch 'Current VM status could not be read') @"
The warning "Current VM status could not be read; VM-reported network data was not queried"
must not survive: it fired while the view was simultaneously displaying a status, and it
claimed the agent was not queried in a code path that now does query it.
"@

# The replacement must name the fallback rather than claim ignorance.
Assert-PmxTest ($source -match 'showing the inventory status') `
    'the fallback warning should say it is showing the inventory status, not that the status is unknown'

# ---- 4. agent state must not be inferred from the status query's success -------------
Assert-PmxTest ($source -notmatch "elseif \(-not \`$statusAvailable\) \{") @"
The branch that reported the AGENT as unavailable because the STATUS query failed must be
gone. Those are unrelated facts, and it short-circuited ahead of the agent query.
"@
Assert-PmxTest ($source -notmatch 'Current VM status could not be verified') `
    'the "status could not be verified" agent reason belonged to the removed branch'

# ---- 5. an unknown status must not be reported as stopped ----------------------------
# Order matters: the empty-status branch has to precede the "not running" branch, or a VM
# whose status is unknown is confidently described as stopped.
$unknownIdx = $source.IndexOf('elseif (-not $status) {')
$stoppedIdx = $source.IndexOf("elseif (`$status -ne 'running') {")
Assert-PmxTest ($unknownIdx -ge 0) 'there should be an explicit branch for an undeterminable status'
Assert-PmxTest ($stoppedIdx -ge 0) 'the not-running branch should still exist'
Assert-PmxTest ($unknownIdx -lt $stoppedIdx) `
    'the unknown-status branch must come BEFORE the not-running branch, or unknown reads as stopped'

# ---- 6. the agent-state vocabulary the view depends on is intact ---------------------
# PF-UX-003 has since refined this vocabulary on purpose: 'disabled' became 'not-configured'
# (nothing was turned off — the channel was never enabled), and the single overloaded
# 'unavailable' split into 'not-responding' and 'query-failed'. The state that used to mean
# "skipped because runtime status could not be read" is gone entirely, because PF-BUG-004
# removed the branch that refused to ask.
foreach ($state in @('not-queried', 'not-requested', 'template', 'stopped',
                     'not-configured', 'not-responding', 'query-failed', 'available')) {
    Assert-PmxTest ($source -match "'$state'") "the agent state '$state' disappeared from the model"
}
# The overloaded name must NOT come back as an agent outcome.
$agentStates = @([regex]::Matches($source, "New-PmxNetworkAgentState[^\r\n]*?'([a-z-]+)'") |
                 ForEach-Object { $_.Groups[1].Value })
Assert-PmxTest ($agentStates -notcontains 'disabled') `
    "'disabled' should have become 'not-configured' - nothing was turned off"

Write-PmxTestPass 'PF-BUG-004: inventory and runtime status are distinct, and a failed status read no longer blocks the agent query'
