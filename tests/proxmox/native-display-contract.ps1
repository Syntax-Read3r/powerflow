# ==============================================================================
# PF-BUG-005 — guarded PMX mutations must work when native display is HIDDEN
# ==============================================================================
# Hiding the native command is deliberate PowerFlow behaviour, so the guarded path passes
# an empty string on purpose:
#
#     $native = if ($showNative) { "$($preview.NativeCommand)" } else { '' }
#     Confirm-PmxAmberPlan ... -NativeCommand $native
#
# `Confirm-PmxAmberPlan` declared that parameter [Parameter(Mandatory)][string] WITHOUT
# [AllowEmptyString()], so PowerShell rejected the intentionally-empty value before the
# function could run — taking out vm start, shutdown, cpu, memory, clone, disk-grow and
# snapshot-create, every mutation routed through the shared helper.
#
# WHY THE EXISTING SUITE DID NOT CATCH IT
#
# tests/proxmox/mutation-safety.ps1 replaces Confirm-PmxAmberPlan with a permissive stub
# (`[string]$NativeCommand`, no Mandatory), so it exercised a working copy of the very
# function that was broken. This file therefore loads the REAL implementation and binds
# against the REAL parameter contract. Do not stub Confirm-PmxAmberPlan here.
# ==============================================================================

. (Join-Path $PSScriptRoot 'test-helpers.ps1')
. (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' 'shared.ps1')

$fields = [ordered]@{ VM = '103 web-prod'; Requested = 'start' }

# ---- 1. the real function must accept the deliberately-empty native command ----------
$threw = $false
try {
    # -DryRun returns before any prompt, so this exercises parameter BINDING only.
    $null = Confirm-PmxAmberPlan -Title 'START VM' -Fields $fields -NativeCommand '' -DryRun
} catch { $threw = $true; $script:bindError = $_.Exception.Message }
Assert-PmxTest (-not $threw) `
    "Confirm-PmxAmberPlan rejected an empty -NativeCommand, so every guarded mutation fails when ShowNative is false. $($script:bindError)"

# ---- 2. omitting it entirely must also bind ------------------------------------------
$threw = $false
try { $null = Confirm-PmxAmberPlan -Title 'START VM' -Fields $fields -DryRun }
catch { $threw = $true }
Assert-PmxTest (-not $threw) 'Confirm-PmxAmberPlan must tolerate -NativeCommand being omitted.'

# ---- 3. and a populated one still binds, so the fix did not invert the contract -------
$threw = $false
try { $null = Confirm-PmxAmberPlan -Title 'START VM' -Fields $fields -NativeCommand 'qm start 103' -DryRun }
catch { $threw = $true }
Assert-PmxTest (-not $threw) 'Confirm-PmxAmberPlan must still accept a populated -NativeCommand.'

# ---- 4. the attribute is present, not merely tolerated by a default -------------------
$parameter = (Get-Command Confirm-PmxAmberPlan).Parameters['NativeCommand']
Assert-PmxTest ($parameter.Attributes.TypeId.Name -contains 'AllowEmptyStringAttribute') `
    'NativeCommand must carry [AllowEmptyString()] explicitly - a default alone still rejects an explicit empty string.'

# ---- 5. hiding the native command must be the ONLY difference ------------------------
# The report's required invariant: shown and hidden runs differ only in display.
$shown  = Confirm-PmxAmberPlan -Title 'T' -Fields $fields -NativeCommand 'qm start 103' -DryRun
$hidden = Confirm-PmxAmberPlan -Title 'T' -Fields $fields -NativeCommand '' -DryRun
Assert-PmxTest ($shown -eq $hidden) `
    'A dry run must reach the same decision whether or not the native command is displayed.'

# ---- 6. the default must stay FALSE -------------------------------------------------
# The fix belongs in the parameter contract, not in the default. Turning native display
# back on would mask the defect rather than repair it.
$configText = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' 'config.ps1') -Raw
Assert-PmxTest ($configText -match 'ShowNative\s*=\s*\$false') `
    'ShowNative must default to $false - hiding the native command is deliberate. Fix the contract, not the default.'

# ---- 7. the same bug class must not exist on the other guarded-path parameters -------
# Any Mandatory [string] fed by an `if (...) { x } else { '' }` expression is the same trap.
$sharedText   = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' 'shared.ps1') -Raw
$vmChangeText = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' 'vm-change.ps1') -Raw

# Collect every variable in vm-change.ps1 assigned a possibly-empty conditional...
$maybeEmpty = @()
foreach ($m in [regex]::Matches($vmChangeText, '(?m)^\s*\$(\w+)\s*=\s*if\s*\(.*?\)\s*\{.*?\}\s*else\s*\{\s*''''\s*\}')) {
    $maybeEmpty += $m.Groups[1].Value
}
# ...and confirm each one is only ever passed to a parameter that allows an empty string.
foreach ($name in $maybeEmpty) {
    foreach ($call in [regex]::Matches($vmChangeText, "-(\w+)\s+\`$$name\b")) {
        $target = $call.Groups[1].Value
        $declaration = [regex]::Match($sharedText, "(?s)\[[^\]]*\]\[string\]\`$$target\b")
        if (-not $declaration.Success) { continue }
        $window = $sharedText.Substring([Math]::Max(0, $declaration.Index - 400), [Math]::Min(400, $declaration.Index))
        $mandatoryNoAllow = ($declaration.Value -match 'Mandatory') -and ($window -notmatch 'AllowEmptyString')
        Assert-PmxTest (-not $mandatoryNoAllow) `
            "-$target is passed a possibly-empty `$$name but is declared Mandatory without [AllowEmptyString()] - same defect as PF-BUG-005."
    }
}

Write-PmxTestPass 'PF-BUG-005: guarded mutations bind correctly with native display hidden'
