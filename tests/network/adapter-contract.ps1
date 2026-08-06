. (Join-Path $PSScriptRoot 'test-helpers.ps1')

$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$windowsAdapter = Get-Content -LiteralPath (Join-Path $root 'platform/windows/adapters/ssh-session.ps1') -Raw
$linuxAdapter = Get-Content -LiteralPath (Join-Path $root 'platform/linux/adapters/ssh-session.ps1') -Raw
$windowsHelper = Get-Content -LiteralPath (Join-Path $root 'platform/windows/helpers/powerflow-ssh-askpass.cs') -Raw
$linuxHelper = Get-Content -LiteralPath (Join-Path $root 'platform/linux/helpers/powerflow-ssh-askpass.sh') -Raw

foreach ($source in @($windowsAdapter, $linuxAdapter)) {
    Assert-True ($source -match 'function Invoke-PFPrivateSshSession') 'private SSH invocation adapter is missing'
    Assert-True ($source -match 'function Get-PFPrivateSshSessionResult') 'private SSH result adapter is missing'
    Assert-True ($source -match 'HostKeyAlias=\$Name') 'OpenSSH host-key display is not alias-bound'
    Assert-True ($source -match 'SSH_ASKPASS_REQUIRE') 'private SSH adapter does not force askpass'
    Assert-True ($source -match "StrictHostKeyChecking=accept-new") 'new host keys are not handled without endpoint prompts'
}
foreach ($helper in @($windowsHelper, $linuxHelper)) {
    Assert-True ($helper -match "Password for '") 'askpass helper does not use the alias-only prompt'
    Assert-PrivateEndpointAbsent $helper
}

Assert-True ($windowsAdapter -notmatch 'Permission denied') 'Windows adapter embeds a raw SSH authentication diagnostic'
Assert-True ($linuxAdapter -notmatch 'Permission denied') 'Linux adapter embeds a raw SSH authentication diagnostic'
Assert-True ($linuxAdapter -match 'chmod 700') 'Linux askpass cache is not restricted to its owner'

Write-Host 'OK - private SSH adapters keep credential prompts alias-only on both platforms.'
