$ErrorActionPreference = 'Stop'

Write-Host 'PMX regression suite'
foreach ($test in @('parser-routing.ps1', 'help-surface.ps1', 'config-transport.ps1', 'adapter-contract.ps1', 'connection-privacy.ps1', 'vm-model.ps1', 'network-contracts.ps1', 'mutation-safety.ps1', 'output-contracts.ps1', 'physical-disk-safety-model.ps1')) {
    & (Join-Path $PSScriptRoot $test)
}
Write-Host 'PMX regression suite passed.'
