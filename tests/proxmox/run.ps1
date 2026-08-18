$ErrorActionPreference = 'Stop'

Write-Host 'PMX regression suite'
foreach ($test in @('parser-routing.ps1', 'help-surface.ps1', 'config-transport.ps1', 'adapter-contract.ps1', 'connection-privacy.ps1', 'vm-model.ps1', 'network-contracts.ps1', 'mutation-safety.ps1', 'output-contracts.ps1', 'physical-disk-safety-model.ps1')) {
    & (Join-Path $PSScriptRoot $test)
}
Write-Host 'PMX regression suite passed.'

& (Join-Path $PSScriptRoot 'native-display-contract.ps1')
& (Join-Path $PSScriptRoot 'dispatch-boundary.ps1')
& (Join-Path $PSScriptRoot 'parse-diagnostics.ps1')
& (Join-Path $PSScriptRoot 'status-sources.ps1')
& (Join-Path $PSScriptRoot 'payload-integrity.ps1')
& (Join-Path $PSScriptRoot 'resolution-invariance.ps1')
& (Join-Path $PSScriptRoot 'agent-states.ps1')
& (Join-Path $PSScriptRoot 'response-boundary.ps1')
& (Join-Path $PSScriptRoot 'vm-config-route.ps1')
& (Join-Path $PSScriptRoot 'convenience-routes.ps1')
& (Join-Path $PSScriptRoot 'picker-cancellation.ps1')
