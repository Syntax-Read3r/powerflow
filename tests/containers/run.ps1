$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'adapter-contract.ps1')
& (Join-Path $PSScriptRoot 'behaviour.ps1')
& (Join-Path $PSScriptRoot 'log-view.ps1')

Write-Host 'Containers (dkr / pman) suite passed.'
