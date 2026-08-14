$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'release-setup.ps1')

Write-Host 'Git suite passed.'
