$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'gnu-args.ps1')
& (Join-Path $PSScriptRoot 'silent-failure.ps1')
& (Join-Path $PSScriptRoot 'command-names.ps1')

Write-Host 'File operations suite passed.'
