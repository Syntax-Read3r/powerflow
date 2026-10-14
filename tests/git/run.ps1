$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'release-setup.ps1')
& (Join-Path $PSScriptRoot 'release-command.ps1')

Write-Host 'Git suite passed.'
