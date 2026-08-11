# =============================================================================
# PF-UX-004 -- pmx vm config, and a hint instead of a dead end
# =============================================================================
# `qm config 103` is native muscle memory, so `pmx config 103` is a predictable mistake. It used
# to answer "Unknown config action '103'", which is accurate and useless.
#
# The namespace is DEFENDED, not overloaded: `pmx config` owns PMX settings, and quietly
# reinterpreting a VMID there would only get more ambiguous as settings grow. So the error names
# the command the user actually wanted, and `pmx vm config` exists as another door to the view
# PowerFlow already had.
# =============================================================================

. (Join-Path $PSScriptRoot 'test-helpers.ps1')

$root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$pmx  = Join-Path $root 'components/proxmox'

# ---- 1. `pmx vm config` routes to the same view as `pmx vm show` ----------------------
$command = Get-Content -LiteralPath (Join-Path $pmx 'command.ps1') -Raw
$showLine   = [regex]::Match($command, "(?m)^\s*'show'\s*\{.*$").Value
$configLine = [regex]::Match($command, "(?m)^\s*'config'\s*\{.*$").Value
Assert-PmxTest ($showLine -match 'Show-PmxManagedVm') "'show' should call Show-PmxManagedVm"
Assert-PmxTest ($configLine -match 'Show-PmxManagedVm') `
    "'config' must route to Show-PmxManagedVm, so it is the same view rather than a second one"
# Same arguments, or the alias diverges under some flag.
Assert-PmxTest ($configLine -match '-Arguments \$rest') "'config' must forward the same argument tail"
Assert-PmxTest ($configLine -notmatch 'StatusOnly') "'config' is the full view, not the status-only one"

# ---- 2. `pmx config <vmid>` must HINT, never reinterpret ------------------------------
$config = Get-Content -LiteralPath (Join-Path $pmx 'config.ps1') -Raw
# config.ps1 has SEVERAL `default {` branches (value parsing, property lookup, the router), so
# the router's is identified by the message only it produces rather than by position.
$anchor = $config.IndexOf('Unknown config action')
Assert-PmxTest ($anchor -gt 0) 'could not find the config router default branch'
$start = $config.LastIndexOf('default {', $anchor)
# Extend PAST the anchor so the plain-error line is inside the window being asserted on.
$end = [Math]::Min($config.Length, $anchor + 200)
$default = $config.Substring($start, $end - $start)
Assert-PmxTest ($default -match 'Test-PmxVmId') `
    'the default branch should recognise a VM-shaped argument'
Assert-PmxTest ($default -match 'pmx vm config') 'the hint must name pmx vm config'
Assert-PmxTest ($default -match 'pmx vm show') 'the hint should also name the canonical command'

# CRITICAL: it must not actually run the VM view from the config namespace.
Assert-PmxTest ($default -notmatch 'Show-PmxManagedVm') @"
`pmx config <vmid>` must NOT be silently reinterpreted as VM configuration. That overloads an
established namespace and gets worse as PMX settings grow — the report was explicit about it.
Hint, do not act.
"@

# A non-VM-shaped unknown action must still get the ordinary error.
Assert-PmxTest ($default -match 'Unknown config action') `
    'a genuinely unknown action must still produce the plain error'

# ---- 3. the alias must be discoverable in the help catalogue -------------------------
# An alias nobody can find is not an alias. Someone reaching for the native spelling should
# find it rather than conclude PowerFlow lacks it.
$help = Get-Content -LiteralPath (Join-Path $pmx 'help.ps1') -Raw
Assert-PmxTest ($help -match "\`$topics\['vm config'\]") 'pmx vm config needs its own help topic'
$topic = [regex]::Match($help, "(?s)\`$topics\['vm config'\] = \[pscustomobject\]@\{.*?\n    \}").Value
Assert-PmxTest ($topic -match 'Alias for pmx vm show') 'the topic must say it is an alias, and of what'
Assert-PmxTest ($topic -match 'qm config') 'the topic should name the native command it mirrors'
Assert-PmxTest ($topic -match 'Read only') 'the topic must state its safety class like every other'
# The blanked-out text bug: a Purpose ending in "for ." means a backtick was eaten.
Assert-PmxTest ($topic -notmatch "Alias for \.") 'the topic Purpose lost its text'

Write-PmxTestPass 'PF-UX-004: pmx vm config routes to the same view, and pmx config <vmid> hints without reinterpreting'
