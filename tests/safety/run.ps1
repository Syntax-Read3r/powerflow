$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'decisions-safety.ps1')

Write-Host 'Safety regression suite passed.'
