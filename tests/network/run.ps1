$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'public-output.ps1')
& (Join-Path $PSScriptRoot 'authenticated-info.ps1')
& (Join-Path $PSScriptRoot 'adapter-contract.ps1')
& (Join-Path $PSScriptRoot 'askpass-echo.ps1')

Write-Host 'SRV privacy + askpass regression suite passed.'
