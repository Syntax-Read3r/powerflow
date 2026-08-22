$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'timerange.ps1')
& (Join-Path $PSScriptRoot 'editing-keys.ps1')

Write-Host 'Shell suite passed.'