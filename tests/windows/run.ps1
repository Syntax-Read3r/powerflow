$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'scoop-root-resolution.ps1')
& (Join-Path $PSScriptRoot 'font-prerequisite.ps1')
& (Join-Path $PSScriptRoot 'uninstall-scoop-safety.ps1')
& (Join-Path $PSScriptRoot 'install-prerequisite-roundtrip.ps1')

Write-Host 'Windows prerequisite regression suite passed.'
