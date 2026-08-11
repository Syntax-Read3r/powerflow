# ==============================================================================
# PF-BUG-003 — output format must never change WHICH VM is resolved
# ==============================================================================
# The report observed `pmx disk list` crashing while `pmx disk list --table` resolved a VM
# successfully, and reasonably concluded that an output flag was altering target resolution.
#
# It was the same defect as PF-BUG-001 seen from another angle: the bare form died at
# PARAMETER BINDING because Get-PmxCommandTail returns an empty array, and ANY flag — including
# an output flag — makes the tail non-empty, so the binder let it through. Resolution itself was
# never format-dependent; reachability was.
#
# That matters for how this is tested. A fix verified only through `--table` or `--json` would
# have looked green while the bare form stayed broken, which is exactly the trap the original
# regression list fell into. So the matrix below always includes the bare form.
#
# The invariant the report asked for, locked: selectors and format flags are parsed
# separately, and the resolved selector depends only on the selector.
# ==============================================================================

. (Join-Path $PSScriptRoot 'test-helpers.ps1')

$root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

function Register-PFCommand { }
. (Join-Path $root 'components/proxmox/shared.ps1')
. (Join-Path $root 'components/proxmox/config.ps1')

# Extract only the invocation parser: vm-read.ps1 registers commands at load.
$text = Get-Content -LiteralPath (Join-Path $root 'components/proxmox/vm-read.ps1') -Raw
$ast  = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$null)
$fn   = $ast.FindAll({
    $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $args[0].Name -eq 'Get-PmxReadInvocation' }, $true)
Assert-PmxTest ($fn.Count -eq 1) 'could not extract Get-PmxReadInvocation'
Invoke-Expression $fn[0].Extent.Text

# ---- the matrix from the report ------------------------------------------------------
# Every row that names VM 100 must resolve to 100. Every row that names none must resolve to
# the empty selector, which downstream means "ask me" via the picker.
$cases = @(
    @{ Argv = @();                             Selector = '';    Why = 'bare - the form that used to crash at binding' }
    @{ Argv = @('--table');                    Selector = '';    Why = 'output flag alone must not invent a target' }
    @{ Argv = @('--json');                     Selector = '';    Why = 'output flag alone must not invent a target' }
    @{ Argv = @('--vm', '100');                Selector = '100'; Why = 'explicit --vm' }
    @{ Argv = @('--vm', '100', '--table');     Selector = '100'; Why = 'explicit --vm, table' }
    @{ Argv = @('--vm', '100', '--json');      Selector = '100'; Why = 'explicit --vm, json' }
    @{ Argv = @('100');                        Selector = '100'; Why = 'positional' }
    @{ Argv = @('100', '--table');             Selector = '100'; Why = 'positional, table' }
    @{ Argv = @('100', '--json');              Selector = '100'; Why = 'positional, json' }
    @{ Argv = @('--table', '--vm', '100');     Selector = '100'; Why = 'flag BEFORE the selector' }
    @{ Argv = @('--json', '100');              Selector = '100'; Why = 'flag before a positional' }
    @{ Argv = @('--vm', '100', '--show-native'); Selector = '100'; Why = 'a non-output modifier must not interfere either' }
)

foreach ($case in $cases) {
    $parsed = Get-PmxReadInvocation -Arguments $case.Argv -RequireSelector
    Assert-PmxTest $parsed.Success `
        "'pmx disk list $($case.Argv -join ' ')' should parse ($($case.Why)): $($parsed.Error)"
    Assert-PmxTest ("$($parsed.Options.Selector)" -ceq $case.Selector) @"
Output format changed target resolution — the PF-BUG-003 invariant.
  command:  pmx disk list $($case.Argv -join ' ')
  expected: selector '$($case.Selector)'
  actual:   selector '$($parsed.Options.Selector)'
  reason:   $($case.Why)
"@
}

# ---- the format flag must still be RECORDED, just not confused with the target --------
Assert-PmxTest ((Get-PmxReadInvocation -Arguments @('--vm', '100', '--table') -RequireSelector).Options.Table -eq $true) `
    '--table must still be captured as an output option'
Assert-PmxTest ((Get-PmxReadInvocation -Arguments @('--vm', '100', '--json') -RequireSelector).Options.Json -eq $true) `
    '--json must still be captured as an output option'

# ---- an output flag must never become a positional -----------------------------------
# This is the mechanism by which a format could ever affect resolution, so it is asserted
# directly rather than only through the selector.
foreach ($flag in @('--table', '--json', '--show-native', '--explain')) {
    $parsed = Get-PmxReadInvocation -Arguments @($flag) -RequireSelector
    Assert-PmxTest ($parsed.Positionals.Count -eq 0) `
        "$flag leaked into the positionals, which is how a format flag becomes a VM name"
}

# ---- genuine ambiguity must STILL be an error ---------------------------------------
# Relaxing "missing selector" to "unspecified" must not have relaxed "two selectors".
foreach ($ambiguous in @(@('100', '--vm', '101'), @('--vm', '101', '100'))) {
    $parsed = Get-PmxReadInvocation -Arguments $ambiguous -RequireSelector
    Assert-PmxTest (-not $parsed.Success) `
        "'$($ambiguous -join ' ')' names two VMs and must be refused, not silently resolved"
}
# ...and adding an output flag must not turn that error into a success.
foreach ($ambiguous in @(@('100', '--vm', '101', '--table'), @('--json', '100', '--vm', '101'))) {
    $parsed = Get-PmxReadInvocation -Arguments $ambiguous -RequireSelector
    Assert-PmxTest (-not $parsed.Success) `
        "'$($ambiguous -join ' ')' must stay ambiguous regardless of output format"
}

# ---- PositionalSelectorOnly commands obey the same invariant -------------------------
# `pmx vm show` takes its VM positionally and rejects --vm, but format flags must behave
# identically there.
foreach ($case in @(
    @{ Argv = @();                  Selector = '' }
    @{ Argv = @('--table');         Selector = '' }
    @{ Argv = @('101');             Selector = '101' }
    @{ Argv = @('101', '--json');   Selector = '101' }
    @{ Argv = @('--json', '101');   Selector = '101' }
)) {
    $parsed = Get-PmxReadInvocation -Arguments $case.Argv -RequireSelector -PositionalSelectorOnly
    Assert-PmxTest $parsed.Success "positional-only parse failed for '$($case.Argv -join ' ')': $($parsed.Error)"
    Assert-PmxTest ("$($parsed.Options.Selector)" -ceq $case.Selector) `
        "positional-only: '$($case.Argv -join ' ')' resolved '$($parsed.Options.Selector)', expected '$($case.Selector)'"
}

Write-PmxTestPass 'PF-BUG-003: target resolution is independent of output format, and ambiguity survives it'
