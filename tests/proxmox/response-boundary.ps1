# =============================================================================
# PF-INVESTIGATE-001 -- one managed-response boundary, and nothing drops the evidence
# =============================================================================
# Every PMX read used to print its own generic error, so a failure looked identical whether the
# transport was down, the payload was truncated mid-token, the JSON was malformed, or the VM did
# not exist. That is exactly why PF-BUG-002 could be reproduced but not diagnosed.
#
# The adapter already owns execution, stream separation, exit-code capture, privacy scrubbing,
# JSON validation and the debug record. The two things missing were a single REPORTER, and
# wrappers that stop dropping Diagnostics on the way up. Both are asserted here.
# =============================================================================

. (Join-Path $PSScriptRoot 'test-helpers.ps1')

$root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$pmx  = Join-Path $root 'components/proxmox'

# ---- 1. exactly ONE reporter, and it lives in the shared file -------------------------
# shared.ps1 loads before every other PMX component, so one copy serves all of them. A second
# copy is how the per-command errors grew in the first place.
$definitions = @(Get-ChildItem $pmx -Filter *.ps1 |
    Select-String -Pattern '(?m)^function Write-PmxQueryFailure\b')
Assert-PmxTest ($definitions.Count -eq 1) `
    "Write-PmxQueryFailure must be defined exactly once; found $($definitions.Count)"
Assert-PmxTest ((Split-Path $definitions[0].Path -Leaf) -ceq 'shared.ps1') `
    "the reporter must live in shared.ps1 so every component can reach it; found in $(Split-Path $definitions[0].Path -Leaf)"

# ---- 2. no managed read prints a raw error any more -----------------------------------
# Local config-file writes are excluded on purpose: Set-PmxConfigSetting and
# Reset-PmxConfigSetting never touch the transport, so they carry no diagnostics and must not
# pretend to.
$rawPrints = @()
foreach ($file in (Get-ChildItem $pmx -Filter *.ps1)) {
    $lines = Get-Content -LiteralPath $file.FullName
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch 'Write-Host "\u274c \$\(\$(\w*[Rr]esult|details)\.Error\)"') { continue }
        # Is this a managed query? Look back for the adapter call that produced the variable.
        $back = ($lines[[Math]::Max(0, $i - 6)..$i]) -join "`n"
        if ($back -match 'Invoke-ProxmoxManagement(Query|Change)|Get-PmxManagedVmDetails|Get-PmxVmNetworkModel') {
            $rawPrints += "$($file.Name):$($i + 1): $($lines[$i].Trim())"
        }
    }
}
Assert-PmxTest ($rawPrints.Count -eq 0) @"
These managed reads still print a raw error instead of routing through Write-PmxQueryFailure,
so their scrubbed evidence never reaches the user:
  $($rawPrints -join "`n  ")
"@

# ---- 3. every wrapper carries Diagnostics up ------------------------------------------
# A wrapper that re-shapes an adapter result must not silently narrow it. Get-PmxManagedVmDetails
# did exactly that, which is how "malformed JSON" arrived with nothing to act on.
foreach ($wrapper in @(
    @{ File = 'vm-read.ps1';      Function = 'Get-PmxManagedVmDetails' }
    @{ File = 'network-read.ps1'; Function = 'Get-PmxVmNetworkModel' }
)) {
    $text = Get-Content -LiteralPath (Join-Path $pmx $wrapper.File) -Raw
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$null)
    $fn = $ast.FindAll({
        $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $args[0].Name -eq $wrapper.Function }, $true)
    Assert-PmxTest ($fn.Count -eq 1) "could not find $($wrapper.Function)"
    $body = $fn[0].Extent.Text

    # Each early return that carries an .Error must also carry .Diagnostics.
    $errorReturns = @([regex]::Matches($body, 'return \[pscustomobject\]@\{[^}]*?Error\s*=\s*\$\w+\.Error[^}]*?\}'))
    Assert-PmxTest ($errorReturns.Count -gt 0) "$($wrapper.Function) should have at least one error return"
    foreach ($ret in $errorReturns) {
        Assert-PmxTest ($ret.Value -match 'Diagnostics') @"
$($wrapper.Function) returns an adapter error WITHOUT its Diagnostics, so the scrubbed evidence
is lost between the adapter and the user:
  $($ret.Value -replace '\s+', ' ')
"@
    }
}

# ---- 4. the reporter must not require options it may not be given ---------------------
# A reporter that only works where parsed options happen to be in scope is the reason each
# command grew its own.
$sharedText = Get-Content -LiteralPath (Join-Path $pmx 'shared.ps1') -Raw
$reporter = [regex]::Match($sharedText, '(?ms)^function Write-PmxQueryFailure \{.*?^\}').Value
Assert-PmxTest ($reporter -match '\$Options\s*=\s*\$null') '-Options must be optional'
Assert-PmxTest ($reporter -notmatch 'Parameter\(Mandatory\)') 'nothing about reporting a failure should be mandatory'

# ---- 5. it must degrade to one line when there is nothing more to say -----------------
# Ordinary output stays quiet; --explain is where the evidence goes.
Assert-PmxTest ($reporter -match 'if \(-not \$Diagnostics\)') `
    'with no diagnostics, the reporter must print one line and stop'
Assert-PmxTest ($reporter -match 'Explain') 'the evidence must be gated behind --explain'
Assert-PmxTest ($reporter -match 'Run again with --explain') `
    'when evidence exists but was not asked for, the reporter should say it is available'

Write-PmxTestPass 'PF-INVESTIGATE-001: one reporter, and no wrapper drops the evidence'
