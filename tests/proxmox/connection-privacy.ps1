. (Join-Path $PSScriptRoot 'test-helpers.ps1')

$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$adapter = Join-Path $root 'platform/windows/adapters/proxmox-management.ps1'
. $adapter

$privateTarget = 'fixture-admin@endpoint.example.invalid'
$connection = [pscustomobject]@{
    Transport = 'ssh'; Label = 'proxmox'; Target = $privateTarget
    Port = 22445; TimeoutSeconds = 10; Node = 'auto'
}

$preview = Invoke-ProxmoxManagementChange -Operation vm-start -Connection $connection `
    -Parameters @{ Vmid = 101 } -Preview
Assert-PmxTest $preview.Success 'Remote PMX preview did not build.'
Assert-PmxTest ($preview.NativeCommand -ceq 'ssh proxmox -- qm start 101') `
    'Remote PMX preview did not use the saved alias.'
Assert-PmxTest (-not $preview.NativeCommand.Contains($privateTarget, [StringComparison]::OrdinalIgnoreCase)) `
    'Remote PMX preview exposed the saved SSH target.'
Assert-PmxTest (-not $preview.NativeCommand.Contains('22445', [StringComparison]::OrdinalIgnoreCase)) `
    'Remote PMX preview exposed the saved SSH port.'

function Invoke-PmxManagementNative {
    param($Connection, [string[]]$Tokens)
    return [pscustomobject]@{
        Success = $false; Error = "$privateTarget`: Permission denied (publickey,password)."
        StdOut = @(); StdErr = @(); ExitCode = 255
        NativeCommand = Format-PmxManagementNativeCommand $Connection $Tokens
    }
}
$failure = Invoke-ProxmoxManagementQuery -Operation version -Connection $connection
Assert-PmxTest (-not $failure.Success -and $failure.FailureKind -ceq 'authentication-required') `
    'Remote SSH authentication failure was not categorized.'
$adapterText = "$($failure.Error)`n$($failure.NativeCommand)"
Assert-PmxTest (-not $adapterText.Contains($privateTarget, [StringComparison]::OrdinalIgnoreCase)) `
    'Remote PMX adapter returned an endpoint-bearing failure.'
Assert-PmxTest ($failure.Error -ceq 'SSH authentication is required.') `
    'Remote PMX adapter did not return the safe authentication message.'

. (Join-Path $root 'components/proxmox/shared.ps1')
. (Join-Path $root 'components/proxmox/connection-state.ps1')
. (Join-Path $root 'components/proxmox/host.ps1')

$script:failedSession = [pscustomobject]@{
    Success = $false; Connection = $connection; Config = $null; Node = ''; Probe = $true
    Error = "Not connected to Proxmox server 'proxmox'."; FailureKind = 'authentication-required'
}
function Get-PmxManagementSession { return $script:failedSession }
$dashboardText = (@(& { Show-PmxManagedNodeStatus } 6>&1) | ForEach-Object { "$_" }) -join "`n"
Assert-PmxTest ($dashboardText -match "Not connected to Proxmox server 'proxmox'") `
    'Bare managed PMX view did not render the alias-only disconnected state.'
Assert-PmxTest ($dashboardText -match 'srv proxmox' -and $dashboardText -match 'inside that Proxmox session') `
    'Disconnected PMX view omitted sign-in guidance.'
Assert-PmxTest (-not $dashboardText.Contains($privateTarget, [StringComparison]::OrdinalIgnoreCase)) `
    'Disconnected PMX view exposed the saved SSH target.'

Write-PmxTestPass 'alias-only PMX previews, failures, and disconnected dashboard'
