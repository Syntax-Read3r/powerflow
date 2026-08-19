$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'volume-contracts.ps1')
& (Join-Path $PSScriptRoot 'storage-behaviour.ps1')
& (Join-Path $PSScriptRoot 'root-report.ps1')

Write-Host 'Storage (storage) suite passed.'
