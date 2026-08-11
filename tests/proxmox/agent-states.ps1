# =============================================================================
# PF-UX-003 -- an agent state must name its cause
# =============================================================================
# `Agent unavailable` meant any of five materially different things:
#   the channel is not configured / configured but the VM is stopped / configured but nothing
#   answers inside the VM / the query was skipped because runtime status failed / the query
#   itself failed.
#
# So `pmx vm ip` was a dead end: it told you it had not worked and nothing about what to do.
# The fifth case no longer exists -- PF-BUG-004 removed the branch that refused to ask -- and
# the rest are now distinct states, each carrying a Reason the view prints.
# =============================================================================

. (Join-Path $PSScriptRoot 'test-helpers.ps1')

$root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$net  = Join-Path $root 'components/proxmox/network-read.ps1'
$view = Join-Path $root 'components/proxmox/network-view.ps1'

function Register-PFCommand { }
. (Join-Path $root 'components/proxmox/shared.ps1')

$ast = [System.Management.Automation.Language.Parser]::ParseFile($net, [ref]$null, [ref]$null)
foreach ($name in @('New-PmxNetworkAgentState', 'Get-PmxVmAgentFailureState')) {
    $fn = $ast.FindAll({
        $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $args[0].Name -eq $name }, $true)
    Assert-PmxTest ($fn.Count -eq 1) "could not extract $name"
    Invoke-Expression $fn[0].Extent.Text
}

# ---- each failure kind gets its OWN state, and a reason -------------------------------
$cases = @(
    @{ Kind = 'timeout';           Status = 'timed-out' }
    @{ Kind = 'unsupported';       Status = 'unsupported' }
    @{ Kind = 'agent-unavailable'; Status = 'not-responding' }
    @{ Kind = 'something-else';    Status = 'query-failed' }
    @{ Kind = '';                  Status = 'query-failed' }
)
foreach ($case in $cases) {
    $state = Get-PmxVmAgentFailureState ([pscustomobject]@{ FailureKind = $case.Kind })
    Assert-PmxTest ($state.Status -ceq $case.Status) `
        "failure kind '$($case.Kind)' should map to '$($case.Status)', got '$($state.Status)'"
    Assert-PmxTest ([bool]$state.Reason) `
        "state '$($state.Status)' must carry a Reason - a bare state is what made this a dead end"
    Assert-PmxTest (-not $state.Available) "a failure state must not report Available"
}

# The two former aliases of one word must now be genuinely different.
$notResponding = Get-PmxVmAgentFailureState ([pscustomobject]@{ FailureKind = 'agent-unavailable' })
$queryFailed   = Get-PmxVmAgentFailureState ([pscustomobject]@{ FailureKind = 'transport-boom' })
Assert-PmxTest ($notResponding.Status -cne $queryFailed.Status) `
    'a non-responding agent and a failed query must not share one state'
Assert-PmxTest ($notResponding.Reason -cne $queryFailed.Reason) 'their reasons must differ too'

# A configured-but-silent agent should point at the actual likely cause.
Assert-PmxTest ($notResponding.Reason -match 'qemu-guest-agent') `
    'not-responding should name qemu-guest-agent, which is nearly always the cause'
# A failed query should point at the evidence added for PF-BUG-002.
Assert-PmxTest ($queryFailed.Reason -match '--explain') `
    'query-failed should point at --explain, where the transport and parser evidence lives'

# ---- the source vocabulary ------------------------------------------------------------
$text = Get-Content -LiteralPath $net -Raw
$code = @($text -split "`r?`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"

Assert-PmxTest ($code -match "'not-configured'") "an unconfigured channel must say 'not-configured'"
Assert-PmxTest ($code -notmatch "New-PmxNetworkAgentState[^\r\n]*'disabled'") `
    "'disabled' implies something was turned off; the channel was never enabled"

# The config-unread model must not assert anything about the agent.
$unavailFn = [regex]::Match($text, '(?ms)^function New-PmxUnavailableVmNetworkModel \{.*?^\}').Value
Assert-PmxTest ($unavailFn -match "'unknown'") `
    'when the VM CONFIG could not be read, the agent state is unknown - not unavailable'

# ---- the view must print the reason, not just the state -------------------------------
$viewText = Get-Content -LiteralPath $view -Raw
$agentField = [regex]::Match($viewText, "(?s)\`$agentText = .*?Write-PmxField 'Agent'").Value
Assert-PmxTest ($agentField.Length -gt 0) 'the Agent field should build its text before printing'
Assert-PmxTest ($agentField -match '\$Model\.Agent\.Reason') `
    'the Agent field must include the Reason, or the cause stays invisible'
Assert-PmxTest ($agentField -match '-not \$Model\.Agent\.Available') `
    'the reason should be appended only when the agent is NOT available - success needs no excuse'

Write-PmxTestPass 'PF-UX-003: agent states are distinct and each names its cause'
