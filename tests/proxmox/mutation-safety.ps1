. (Join-Path $PSScriptRoot 'test-helpers.ps1')
. (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' 'shared.ps1')
. (Join-Path $PSScriptRoot '..' '..' 'components' 'proxmox' 'vm-change.ps1')

$session = [pscustomobject]@{
    Connection = [pscustomobject]@{ Label = 'fixture'; Transport = 'ssh' }
    Config = [pscustomobject]@{ ShowNative = $false }
}
$fields = [ordered]@{ VM = '101 app-01'; Requested = 'start' }
$script:confirm = $false
$script:previewCalls = 0
$script:mutationCalls = 0
$script:audit = @()

function Confirm-PmxAmberPlan {
    param([string]$Title, [System.Collections.IDictionary]$Fields, [string]$NativeCommand,
        [string[]]$Warnings, [switch]$DryRun)
    return $script:confirm
}
function Write-PmxAuditRecord {
    param([string]$Operation, [string]$Target, [string]$Outcome, [string]$Message, [string]$VmId,
        [switch]$DryRun, $Config)
    $script:audit += [pscustomobject]@{ Operation = $Operation; Target = $Target; Outcome = $Outcome; Message = $Message; VmId = $VmId }
}
function Invoke-ProxmoxManagementChange {
    param([string]$Operation, $Connection, [hashtable]$Parameters, [switch]$Preview)
    if ($Preview) { $script:previewCalls++; return [pscustomobject]@{ Success = $true; NativeCommand = 'qm start 101'; Error = '' } }
    $script:mutationCalls++
    return [pscustomobject]@{ Success = $true; NativeCommand = 'qm start 101'; Error = '' }
}

$never = { throw 'This callback must not run.' }
$dry = Invoke-PmxAmberMutation -Session $session -Operation vm-start -Parameters @{ Vmid = 101 } `
    -Title 'START VM' -Fields $fields -Options @{ DryRun = $true } -Revalidate $never -Verify $never -VmId '101'
Assert-PmxTest ($dry.Success -and -not $dry.Executed -and $script:mutationCalls -eq 0) `
    'Dry run reached the mutation adapter.'
Assert-PmxTest ($script:audit[-1].Outcome -ceq 'dry-run') 'Dry run did not write the expected audit outcome.'

$cancel = Invoke-PmxAmberMutation -Session $session -Operation vm-start -Parameters @{ Vmid = 101 } `
    -Title 'START VM' -Fields $fields -Revalidate $never -Verify $never -VmId '101'
Assert-PmxTest (-not $cancel.Success -and -not $cancel.Executed -and $script:mutationCalls -eq 0) `
    'Declined confirmation reached the mutation adapter.'

$script:confirm = $true
$changed = { [pscustomobject]@{ Success = $false; Error = 'state changed after confirmation' } }
$refused = Invoke-PmxAmberMutation -Session $session -Operation vm-start -Parameters @{ Vmid = 101 } `
    -Title 'START VM' -Fields $fields -Revalidate $changed -Verify $never -VmId '101'
Assert-PmxTest (-not $refused.Success -and -not $refused.Executed -and $script:mutationCalls -eq 0) `
    'Failed state revalidation reached the mutation adapter.'

$fresh = { [pscustomobject]@{ Success = $true; Error = ''; Parameters = @{ Vmid = 101 } } }
$verified = { [pscustomobject]@{ Success = $true; Error = ''; Message = 'VM 101 is running.' } }
$done = Invoke-PmxAmberMutation -Session $session -Operation vm-start -Parameters @{ Vmid = 101 } `
    -Title 'START VM' -Fields $fields -Revalidate $fresh -Verify $verified -VmId '101'
Assert-PmxTest ($done.Success -and $done.Executed -and $script:mutationCalls -eq 1) `
    'Confirmed, revalidated operation did not execute exactly once.'
Assert-PmxTest ($script:audit[-1].Outcome -ceq 'verified') 'Verified mutation did not write the expected audit outcome.'
Write-PmxTestPass 'dry-run, cancellation, revalidation, execution, verification, and audit boundaries'
