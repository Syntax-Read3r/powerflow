# ==============================================================================
# PF-UX-002 — escaping a picker is a decision, not a failure
# ==============================================================================
# `pmx disk list`, Escape, and the command ended with:
#
#     ❌ cancelled
#
# in red. The red marker is the one piece of output that has to stay trustworthy; spending
# it on a user who simply changed their mind teaches them to scan past it, and the next
# time it means something they will.
#
# Five outcomes reach the same renderer and only ONE of them is neutral:
#
#     Esc pressed        →  neutral
#     no VMs / no disks  →  a state worth reporting
#     fzf unavailable    →  an instruction
#     invalid selector   →  an error
#     ambiguous selector →  an error
#
# So the assertions below are mostly about telling those five apart, not about the one
# string that changed. `fzf` is shimmed as a FUNCTION — PowerShell resolves a function
# ahead of a native binary, which is the same mechanism `components/` is forbidden from
# using by accident (see the coreutil rule) and exactly what makes it useful here.
# ==============================================================================

. (Join-Path $PSScriptRoot 'test-helpers.ps1')

$root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

function Register-PFCommand { }
function Register-PFEducation { }
. (Join-Path $root 'components/proxmox/shared.ps1')

# ── the fzf shim ─────────────────────────────────────────────────────────────
# Escape from fzf produces NO stdout and a non-zero exit. Returning nothing is therefore
# a faithful stand-in, and is what the resolvers actually test for.
# Whether a picker MAY open is its own predicate now (Test-PmxCanPick), which is the only
# reason this file can test the interactive path at all: a test harness always runs with
# output redirected, so the real check would refuse before fzf was ever reached.
# Keep a handle on the REAL one before shadowing it, so the last check below can exercise
# the shipped predicate rather than the mock standing in for it.
$realCanPick = (Get-Command Test-PmxCanPick).ScriptBlock

$script:CanPick = $true
function Test-PmxCanPick { return $script:CanPick }

$script:FzfMode = 'cancel'
$script:FzfCalls = 0
function fzf {
    $script:FzfCalls++
    $rows = @($input)
    switch ($script:FzfMode) {
        'cancel' { return }                       # Esc
        'first'  { return $rows[0] }              # a selection
        'absent' { throw 'fzf should not have been invoked' }
    }
}

# ── stand in for the adapter ─────────────────────────────────────────────────
$script:Disks = @(
    [pscustomobject]@{ Name = 'sda'; SizeBytes = 500GB; Rotational = $false; Model = 'SAMSUNG'; Serial = 'S1'; Path = '/dev/sda'; StableId = '/dev/disk/by-id/ata-S1'; StableIds = @('/dev/disk/by-id/ata-S1') }
    [pscustomobject]@{ Name = 'sdb'; SizeBytes = 2TB;   Rotational = $true;  Model = 'WDC';     Serial = 'S2'; Path = '/dev/sdb'; StableId = '/dev/disk/by-id/ata-S2'; StableIds = @('/dev/disk/by-id/ata-S2') }
)
function Get-ProxmoxDisks { return $script:Disks }
function Show-PmxDisks { Write-Host 'THE-FULL-DISK-LIST' }

# Load only Resolve-PmxDisk: the rest of physical-disks.ps1 registers commands and pulls in
# the whole adapter surface, none of which is under test here.
$text = Get-Content -LiteralPath (Join-Path $root 'components/proxmox/physical-disks.ps1') -Raw
$ast  = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$null)
$fn   = $ast.FindAll({
    $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $args[0].Name -eq 'Resolve-PmxDisk' }, $true)
Assert-PmxTest ($fn.Count -eq 1) 'could not extract Resolve-PmxDisk'
Invoke-Expression $fn[0].Extent.Text

Write-Host 'PF-UX-002 picker cancellation'

# ── 1. the renderer: what actually reaches the screen ────────────────────────
function Get-Rendered {
    param([Parameter(Mandatory)]$Resolved)
    return (@(Write-PmxResolveFailure -Resolved $Resolved 6>&1 | ForEach-Object { "$_" }) -join "`n")
}

$cancelled = New-PmxCancelledResult -Kind 'Vm'
$rendered = Get-Rendered $cancelled
Assert-PmxTest ($rendered -match '↩') 'a cancellation renders the return marker'
Assert-PmxTest ($rendered -match 'Cancelled') 'a cancellation says it was cancelled'
Assert-PmxTest ($rendered -notmatch '❌') 'a cancellation carries NO red error marker'
Write-PmxTestPass 'Esc renders as a neutral cancellation, not an error'

# The old string must not survive anywhere the user can see it.
Assert-PmxTest ($rendered -notmatch '(?i)^cancelled$') 'the bare "cancelled" string is not the output'
Assert-PmxTest ($cancelled.Error -eq '') 'a cancellation carries no error text to be printed by accident'
Write-PmxTestPass 'cancellation carries no error string'

$failed = [pscustomobject]@{ Success = $false; Cancelled = $false; Vm = $null; Error = "VM 'nope' was not found" }
$rendered = Get-Rendered $failed
Assert-PmxTest ($rendered -match '❌') 'a real failure KEEPS the red marker'
Assert-PmxTest ($rendered -match 'was not found') 'and says what went wrong'
Assert-PmxTest ($rendered -notmatch 'Cancelled') 'and is not softened into a cancellation'
Write-PmxTestPass 'a real failure is still an error'

# The distinction has to survive a result that predates the field entirely.
$legacy = [pscustomobject]@{ Success = $false; Vm = $null; Error = 'transport failed' }
$rendered = Get-Rendered $legacy
Assert-PmxTest ($rendered -match '❌') 'a result with no Cancelled field is treated as a failure'
Write-PmxTestPass 'absent Cancelled field defaults to error, not to silence'

# ── 2. the shape of a cancelled envelope ─────────────────────────────────────
foreach ($kind in @('Vm', 'Disk')) {
    $c = New-PmxCancelledResult -Kind $kind
    Assert-PmxTest (-not $c.Success) "$kind cancellation is not a success"
    Assert-PmxTest ([bool]$c.Cancelled) "$kind cancellation is flagged"
    Assert-PmxTest ($c.PSObject.Properties.Name -contains $kind) "$kind cancellation still exposes the .$kind field"
    Assert-PmxTest ($null -eq $c.$kind) "$kind cancellation carries no half-built object"
}
Write-PmxTestPass 'both resolvers cancel with the same shape'

# ── 3. Escape from the disk picker ───────────────────────────────────────────
$script:FzfMode = 'cancel'; $script:FzfCalls = 0
$result = Resolve-PmxDisk -Selector '' -Interactive
Assert-PmxTest ($script:FzfCalls -eq 1) 'the picker opened'
Assert-PmxTest (-not $result.Success) 'Escape does not resolve a disk'
Assert-PmxTest ([bool]$result.Cancelled) 'Escape is reported as a cancellation'
Assert-PmxTest ($result.Error -eq '') 'and carries no error text'
Write-PmxTestPass 'Escape from the disk picker cancels'

$script:FzfMode = 'first'
$result = Resolve-PmxDisk -Selector '' -Interactive
Assert-PmxTest ($result.Success) 'a selection resolves'
Assert-PmxTest (-not $result.Cancelled) 'a selection is not a cancellation'
Assert-PmxTest ($result.Disk.Name -eq 'sda') 'and returns the picked disk'
Write-PmxTestPass 'picking a disk still works'

# ── 3b. Escape from the VM picker ────────────────────────────────────────────
# The other resolver, which is where the reported "❌ cancelled" actually came from. It
# needs an inventory rather than a disk list, so it is stood up separately.
$script:Vms = @(
    [pscustomobject]@{ VmId = 100; Name = 'web-01'; Status = 'running'; Node = 'pve'; Template = $false }
    [pscustomobject]@{ VmId = 101; Name = 'db-01';  Status = 'stopped'; Node = 'pve'; Template = $false }
)
function Get-PmxManagedVmRows { param($Session) return [pscustomobject]@{ Success = $true; Vms = $script:Vms; Error = '' } }

$vmText = Get-Content -LiteralPath (Join-Path $root 'components/proxmox/vm-read.ps1') -Raw
$vmAst  = [System.Management.Automation.Language.Parser]::ParseInput($vmText, [ref]$null, [ref]$null)
$vmFn   = $vmAst.FindAll({
    $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $args[0].Name -eq 'Resolve-PmxManagedVm' }, $true)
Assert-PmxTest ($vmFn.Count -eq 1) 'could not extract Resolve-PmxManagedVm'
Invoke-Expression $vmFn[0].Extent.Text

$script:CanPick = $true; $script:FzfMode = 'cancel'; $script:FzfCalls = 0
$vmCancel = Resolve-PmxManagedVm -Selector '' -Session 'fake'
Assert-PmxTest ($script:FzfCalls -eq 1) 'the VM picker opened'
Assert-PmxTest (-not $vmCancel.Success) 'Escape does not resolve a VM'
Assert-PmxTest ([bool]$vmCancel.Cancelled) 'Escape from the VM picker is a cancellation'
Assert-PmxTest ($vmCancel.Error -eq '') 'and carries no error text'
Assert-PmxTest ((Get-Rendered $vmCancel) -notmatch '❌') 'and renders with no red marker'
Write-PmxTestPass 'Escape from the VM picker cancels'

$script:FzfMode = 'first'
$vmPicked = Resolve-PmxManagedVm -Selector '' -Session 'fake'
Assert-PmxTest ($vmPicked.Success) 'picking a VM resolves'
Assert-PmxTest (-not $vmPicked.Cancelled) 'a picked VM is not a cancellation'
Assert-PmxTest ($vmPicked.Vm.VmId -eq 100) 'and returns the picked VM'
Write-PmxTestPass 'picking a VM still works'

# The other four outcomes, each of which must stay an error.
$script:FzfMode = 'absent'
$vmMissing = Resolve-PmxManagedVm -Selector 'nope' -Session 'fake'
Assert-PmxTest (-not $vmMissing.Cancelled -and $vmMissing.Error -match 'not found') 'an unknown VM is an error'

$script:Vms = @(
    [pscustomobject]@{ VmId = 100; Name = 'dup'; Status = 'running'; Node = 'pve'; Template = $false }
    [pscustomobject]@{ VmId = 101; Name = 'dup'; Status = 'running'; Node = 'pve'; Template = $false }
)
$vmAmbiguous = Resolve-PmxManagedVm -Selector 'dup' -Session 'fake'
Assert-PmxTest (-not $vmAmbiguous.Cancelled -and $vmAmbiguous.Error -match 'ambiguous') 'an ambiguous name is an error'

$script:Vms = @()
$script:CanPick = $true
$vmNone = Resolve-PmxManagedVm -Selector '' -Session 'fake'
Assert-PmxTest (-not $vmNone.Cancelled) 'an empty node is not a cancellation'
Assert-PmxTest ($vmNone.Error -match 'no VMs') 'an empty node reports a state'

$script:CanPick = $false
$vmNoPicker = Resolve-PmxManagedVm -Selector '' -Session 'fake'
Assert-PmxTest (-not $vmNoPicker.Cancelled) 'no picker is not a cancellation'
Assert-PmxTest ($vmNoPicker.Error -match 'name a VM') 'no picker gives an instruction'
Write-PmxTestPass 'the other four VM outcomes stay errors'
$script:CanPick = $true

# ── 4. no-result vs cancellation ─────────────────────────────────────────────
# The one the report singled out: these two must not render the same way.
$script:Disks = @()
$script:FzfMode = 'absent'
$empty = Resolve-PmxDisk -Selector '' -Interactive
Assert-PmxTest (-not $empty.Success) 'no disks is not a success'
Assert-PmxTest (-not $empty.Cancelled) 'no disks is NOT a cancellation'
Assert-PmxTest ([bool]$empty.Error) 'no disks reports a state'
Assert-PmxTest ((Get-Rendered $empty) -match '❌') 'and keeps the error marker'
Write-PmxTestPass 'an empty host is a reportable state, not a cancellation'
$script:Disks = @(
    [pscustomobject]@{ Name = 'sda'; SizeBytes = 500GB; Rotational = $false; Model = 'SAMSUNG'; Serial = 'S1'; Path = '/dev/sda'; StableId = '/dev/disk/by-id/ata-S1'; StableIds = @('/dev/disk/by-id/ata-S1') }
    [pscustomobject]@{ Name = 'sdb'; SizeBytes = 2TB;   Rotational = $true;  Model = 'WDC';     Serial = 'S2'; Path = '/dev/sdb'; StableId = '/dev/disk/by-id/ata-S2'; StableIds = @('/dev/disk/by-id/ata-S2') }
)

# ── 5. a bad selector is an error, and never a cancellation ──────────────────
$script:FzfMode = 'absent'; $script:FzfCalls = 0
$missing = Resolve-PmxDisk -Selector 'sdz'
Assert-PmxTest (-not $missing.Success) 'an unknown disk does not resolve'
Assert-PmxTest (-not $missing.Cancelled) 'an unknown disk is not a cancellation'
Assert-PmxTest ($missing.Error -match 'sdz') 'and names what was not found'
Assert-PmxTest ($script:FzfCalls -eq 0) 'a named selector never opens a picker'
Write-PmxTestPass 'an unknown selector is an error'

$exact = Resolve-PmxDisk -Selector 'sdb'
Assert-PmxTest ($exact.Success -and $exact.Disk.Name -eq 'sdb') 'a named disk resolves without a picker'
Write-PmxTestPass 'a named disk resolves directly'

# ── 6. non-interactive sessions never invoke fzf ─────────────────────────────
# Two separate reasons to refuse, and neither may be reported as a cancellation: the user
# was never asked, so they cannot have declined.
$script:FzfMode = 'absent'; $script:FzfCalls = 0
$noninteractive = Resolve-PmxDisk -Selector ''          # no -Interactive
Assert-PmxTest ($script:FzfCalls -eq 0) 'a non-interactive call never opens a picker'
Assert-PmxTest (-not $noninteractive.Success) 'and does not resolve'
Assert-PmxTest (-not $noninteractive.Cancelled) 'and is not a cancellation - nobody was asked'
Write-PmxTestPass 'non-interactive never invokes fzf'

$script:CanPick = $false; $script:FzfCalls = 0
$noFzf = Resolve-PmxDisk -Selector '' -Interactive
Assert-PmxTest ($script:FzfCalls -eq 0) 'a session that cannot pick never opens a picker'
Assert-PmxTest (-not $noFzf.Success) 'no picker means no resolution'
Assert-PmxTest (-not $noFzf.Cancelled) 'an unavailable picker is not a cancellation'
Write-PmxTestPass 'an unavailable picker is not mistaken for Escape'

# And the SHIPPED predicate, not the mock: a test harness always runs with output
# redirected, so this asserts the real refusal on the real condition.
Assert-PmxTest ([Console]::IsOutputRedirected) 'precondition: this harness runs redirected'
Assert-PmxTest (-not (& $realCanPick)) 'the real predicate refuses a redirected session'
Write-PmxTestPass 'the shipped predicate refuses when output is redirected'
$script:CanPick = $true

# ── 7. the call sites all route through the renderer ─────────────────────────
# A convention enforced in nine places drifts in one of them, so this asserts the nine are
# gone rather than trusting that they were all edited.
$offenders = @()
foreach ($file in (Get-ChildItem (Join-Path $root 'components/proxmox') -Filter '*.ps1')) {
    $src = Get-Content -LiteralPath $file.FullName -Raw
    if ($src -match '\$resolved\.Success\)\s*\{\s*Write-Host\s*"❌\s*\$\(\$resolved\.Error\)') {
        $offenders += $file.Name
    }
}
Assert-PmxTest ($offenders.Count -eq 0) "these still render a resolve failure by hand: $($offenders -join ', ')"
Write-PmxTestPass 'every resolve failure goes through Write-PmxResolveFailure'

Write-Host 'PF-UX-002: Escape is neutral, and the five outcomes stay distinguishable.'
