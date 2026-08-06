$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'public-output.ps1')
& (Join-Path $PSScriptRoot 'authenticated-info.ps1')
& (Join-Path $PSScriptRoot 'adapter-contract.ps1')

Write-Host 'SRV privacy regression suite passed.'
