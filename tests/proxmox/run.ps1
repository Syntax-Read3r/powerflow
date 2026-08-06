$ErrorActionPreference = 'Stop'

Write-Host 'PMX regression suite'
foreach ($test in @('parser-routing.ps1', 'config-transport.ps1', 'adapter-contract.ps1', 'vm-model.ps1', 'mutation-safety.ps1', 'physical-disk-safety-model.ps1')) {
    & (Join-Path $PSScriptRoot $test)
}
Write-Host 'PMX regression suite passed.'
