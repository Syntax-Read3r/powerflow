$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'convention.ps1')

Write-Host 'Flag convention suite passed.'
