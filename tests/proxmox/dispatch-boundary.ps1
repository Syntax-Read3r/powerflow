# ==============================================================================
# PF-BUG-001 — an unspecified VM must mean "ask me", never a binding exception
# ==============================================================================
# `pmx disk list` with no VM produced:
#
#   Show-PmxManagedVmDisks: .../command.ps1:218
#   Cannot bind argument to parameter 'Arguments' because it is an empty array.
#
# Get-PmxCommandTail deliberately returns ,@() when nothing follows the verb, and a
# Mandatory [object[]] rejects an empty array BEFORE the function body runs. Every affected
# body already handled the case correctly — Resolve-PmxManagedVm opens a picker on an empty
# selector — so the parameter contract was refusing to let the implementation do its job.
#
# The reported command was one of THREE with this defect. The others were never filed:
#   pmx vm show     -> Show-PmxManagedVm
#   pmx vm start    -> Invoke-PmxVmLifecycleChange (via Invoke-PmxVmStart, default @())
#   pmx vm shutdown -> Invoke-PmxVmLifecycleChange (via Invoke-PmxVmShutdown, default @())
#
# This file guards the CLASS, not the three instances: any router-reachable function whose
# Arguments parameter is Mandatory must also allow an empty collection.
# ==============================================================================

. (Join-Path $PSScriptRoot 'test-helpers.ps1')

$root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

# ---- 1. the tail helper really can produce an empty array -----------------------------
# Only Get-PmxCommandTail is extracted rather than dot-sourcing command.ps1, which calls
# Register-PFCommand at load time and would need the whole help registry present.
$commandText = Get-Content -LiteralPath (Join-Path $root 'components/proxmox/command.ps1') -Raw
$tailHelper = [regex]::Match($commandText, '(?ms)^function Get-PmxCommandTail \{.*?^\}').Value
Assert-PmxTest ($tailHelper.Length -gt 0) 'could not extract Get-PmxCommandTail'
Invoke-Expression $tailHelper

$tail = Get-PmxCommandTail -Arguments @('list') -Start 1
Assert-PmxTest ($null -ne $tail -and @($tail).Count -eq 0) `
    'Get-PmxCommandTail should return an EMPTY array when nothing follows the verb.'
$tail2 = Get-PmxCommandTail -Arguments @() -Start 1
Assert-PmxTest (@($tail2).Count -eq 0) 'Get-PmxCommandTail should return empty for an empty input.'

# ---- 2. every Mandatory Arguments parameter must allow an empty collection ------------
# Source-level, because binding is what fails and it fails before any body executes.
$files = @('vm-read.ps1', 'vm-change.ps1', 'network-read.ps1', 'disk-grow.ps1',
           'snapshots.ps1', 'host.ps1', 'config.ps1', 'command.ps1') |
         ForEach-Object { Join-Path $root "components/proxmox/$_" } |
         Where-Object { Test-Path -LiteralPath $_ }

$offenders = @()
foreach ($file in $files) {
    $text  = Get-Content -LiteralPath $file -Raw
    $lines = $text -split "`r?`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        # Only the DISPATCH-TAIL class. `-Arguments` is the parameter the router fills from
        # Get-PmxCommandTail, which is the one that can legitimately arrive empty.
        #
        # Deliberately NOT every Mandatory array parameter. Show-PmxGrowableDiskChoices -Disks
        # is Mandatory without AllowEmptyCollection and that is CORRECT: disk-grow.ps1 returns
        # early when the disk list is empty, and only calls it when the count is 2 or more, so
        # "never empty" is a real invariant worth enforcing. Widening this scan would pressure
        # someone into weakening a good contract to silence a test.
        if ($line -notmatch 'Parameter\(Mandatory\)\]\[(object|string)\[\]\]\$(Arguments)\b') { continue }
        $paramName = $matches[2]
        if ($line -match 'AllowEmptyCollection') { continue }

        # Which function does this parameter belong to?
        $owner = '(unknown)'
        for ($j = $i; $j -ge 0; $j--) {
            if ($lines[$j] -match '^function\s+([A-Za-z][\w-]*)') { $owner = $matches[1]; break }
        }
        $offenders += "$owner -$paramName ($(Split-Path $file -Leaf):$($i + 1))"
    }
}

Assert-PmxTest ($offenders.Count -eq 0) @"
Mandatory array parameter(s) without [AllowEmptyCollection()] — each is a raw
ParameterBindingException waiting for a user who omits the optional tail:
  $($offenders -join "`n  ")
"@

# ---- 3. the three reported/found entry points bind with an empty tail -----------------
# Binding is tested for real. The bodies are NOT executed — they would need a live Proxmox —
# so each is shadowed by a probe carrying the SAME parameter contract, extracted from source.
foreach ($target in @(
    @{ File = 'vm-read.ps1';   Function = 'Show-PmxManagedVmDisks'; Command = 'pmx disk list' }
    @{ File = 'vm-read.ps1';   Function = 'Show-PmxManagedVm';      Command = 'pmx vm show' }
    @{ File = 'vm-change.ps1'; Function = 'Invoke-PmxVmLifecycleChange'; Command = 'pmx vm start' }
)) {
    # The AST, not a regex: param blocks here are preceded by comment blocks and contain
    # nested parentheses ([Parameter(Mandatory)]), so no sane regex extracts them reliably.
    $path = Join-Path $root "components/proxmox/$($target.File)"
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
    $found = $ast.FindAll({
        $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $args[0].Name -eq $target.Function
    }, $true)
    Assert-PmxTest ($found.Count -eq 1) "Expected exactly one definition of $($target.Function); found $($found.Count)."
    $paramBlock = $found[0].Body.ParamBlock
    Assert-PmxTest ($null -ne $paramBlock) "$($target.Function) has no param block."

    # Rebuild just the contract, with a body that only reports that it was reached.
    $probeName = "Probe-$($target.Function)"
    Invoke-Expression "function $probeName {`n$($paramBlock.Extent.Text)`n  return 'bound' }"

    $bound = $null
    $failure = ''
    try {
        $bound = if ($target.Function -eq 'Invoke-PmxVmLifecycleChange') {
            & $probeName -Arguments @() -Action 'start'
        } else {
            & $probeName -Arguments @()
        }
    } catch { $failure = $_.Exception.Message }

    Assert-PmxTest ($bound -eq 'bound') @"
$($target.Command) cannot bind with no VM specified, so the user gets a raw
ParameterBindingException instead of a VM picker. $failure
"@
}

# ---- 4. the lifecycle wrappers really do pass an empty default through ----------------
# This is what made `pmx vm start` fail without anyone filing it.
$changeText = Get-Content -LiteralPath (Join-Path $root 'components/proxmox/vm-change.ps1') -Raw
foreach ($wrapper in @('Invoke-PmxVmStart', 'Invoke-PmxVmShutdown')) {
    $line = [regex]::Match($changeText, "(?m)^function $wrapper .*$").Value
    Assert-PmxTest ($line -match '\$Arguments\s*=\s*@\(\)') `
        "$wrapper should default Arguments to @() — if that changed, re-check this test's premise."
    Assert-PmxTest ($line -match '-Arguments \$Arguments') `
        "$wrapper should forward Arguments to the shared lifecycle function."
}

Write-PmxTestPass 'PF-BUG-001: an unspecified VM binds to the picker path, not a binding exception'
