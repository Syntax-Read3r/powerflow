$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'anchors.ps1')

Write-Host 'Navigation anchor regression suite passed.'
