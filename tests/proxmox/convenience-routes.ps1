# =============================================================================
# PF-UX-001 / PF-UX-002 -- convenience routes that never weaken the safety chain
# =============================================================================
# `pmx start 101` answered "Unknown pmx command 'start'" and `pmx vm disks 102` did not exist.
# Neither was a parser bug; both were convenience gaps against what a hand reaches for.
#
# The rule these must obey: a shortcut buys typing, never a weaker guarantee. Each forwards into
# the SAME function as its canonical form, so there is no second implementation to drift and no
# second safety path to audit.
# =============================================================================

. (Join-Path $PSScriptRoot 'test-helpers.ps1')

$root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$command = Get-Content -LiteralPath (Join-Path $root 'components/proxmox/command.ps1') -Raw

# ---- PF-UX-001: top-level lifecycle shortcuts ----------------------------------------
$router = [regex]::Match($command, '(?s)switch \(\$group\) \{.*?\n    \}').Value
Assert-PmxTest ($router.Length -gt 0) 'could not find the top-level router'

foreach ($pair in @(
    @{ Group = 'start';    Function = 'Invoke-PmxVmStart' }
    @{ Group = 'shutdown'; Function = 'Invoke-PmxVmShutdown' }
)) {
    $line = [regex]::Match($router, "(?m)^\s*'$($pair.Group)'\s*\{.*$").Value
    Assert-PmxTest ($line.Length -gt 0) "top-level '$($pair.Group)' should be routed"
    Assert-PmxTest ($line -match [regex]::Escape($pair.Function)) `
        "'$($pair.Group)' must forward to $($pair.Function) - the same function `pmx vm $($pair.Group)` uses, so the guarded path is identical"
    Assert-PmxTest ($line -match '-Arguments \$tail') "'$($pair.Group)' must forward the whole argument tail"
}

# The shortcut must NOT reimplement the mutation. If it called the adapter directly it would
# bypass validate -> confirm -> revalidate -> verify.
foreach ($group in @('start', 'shutdown')) {
    $line = [regex]::Match($router, "(?m)^\s*'$group'\s*\{.*$").Value
    Assert-PmxTest ($line -notmatch 'Invoke-ProxmoxManagementChange') `
        "'$group' must not call the adapter directly - that would skip the confirm/revalidate/verify chain"
    Assert-PmxTest ($line -notmatch 'Invoke-PmxAmberMutation') `
        "'$group' should go through the lifecycle function, not assemble its own mutation"
}

# Only those two. Every extra top-level word narrows the namespace for future groups.
$lifecycleGroups = @([regex]::Matches($router, "(?m)^\s*'(start|shutdown|stop|reboot|reset|destroy|delete)'") |
                     ForEach-Object { $_.Groups[1].Value })
Assert-PmxTest (@($lifecycleGroups | Sort-Object -Unique) -join ',' -ceq 'shutdown,start') `
    "only start and shutdown should be promoted to the top level; found: $($lifecycleGroups -join ', ')"

# ---- PF-UX-002: `pmx vm disks [vm]` --------------------------------------------------
$vmRouter = [regex]::Match($command, '(?s)function Invoke-PmxVmCommand \{.*?\n\}').Value
Assert-PmxTest ($vmRouter.Length -gt 0) 'could not find the vm router'

foreach ($action in @('disks', 'disk')) {
    $line = [regex]::Match($vmRouter, "(?m)^\s*'$action'\s*\{.*$").Value
    Assert-PmxTest ($line.Length -gt 0) "'pmx vm $action' should be routed"
    Assert-PmxTest ($line -match 'Show-PmxManagedVmDisks') `
        "'pmx vm $action' must reach Show-PmxManagedVmDisks - the same function `pmx disk list` uses"
    Assert-PmxTest ($line -match '-Arguments \$rest') "'pmx vm $action' must forward the argument tail"
}

# The canonical script form must still exist and still work.
$diskGroup = [regex]::Match($router, "(?s)'disk'\s*\{.*?\n        \}").Value
Assert-PmxTest ($diskGroup -match 'Show-PmxManagedVmDisks') `
    '`pmx disk list` must remain the canonical route, not be replaced by the convenience one'

# Bare `pmx vm disks` must inherit the picker rather than error. That works because the target
# function treats an unspecified VM as "ask me" — asserted properly in dispatch-boundary.ps1;
# here we only check the route does not pre-empt it with its own argument check.
$disksLine = [regex]::Match($vmRouter, "(?m)^\s*'disks'\s*\{.*$").Value
Assert-PmxTest ($disksLine -notmatch 'takes no arguments|Count') `
    'pmx vm disks must not reject an empty tail - an unspecified VM means "ask me"'

Write-PmxTestPass 'PF-UX-001/002: convenience routes share the canonical functions and the same guarded path'
