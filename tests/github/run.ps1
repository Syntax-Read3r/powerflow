$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'repository-review.ps1')
Write-Host 'GitHub repository review suite passed.'
