$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'data-paths.ps1')
& (Join-Path $PSScriptRoot 'anchors.ps1')
& (Join-Path $PSScriptRoot 'outcomes.ps1')

Write-Host 'Navigation regression suite passed.'
