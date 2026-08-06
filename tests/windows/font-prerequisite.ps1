$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
}

$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $root 'platform/windows/adapters/packages.ps1')
. (Join-Path $root 'platform/windows/adapters/fonts.ps1')

Assert-True (Test-NerdFontRegistryName 'FiraCode Nerd Font Mono (TrueType)') 'spaced family label is detected'
Assert-True (Test-NerdFontRegistryName 'FiraCodeNerdFontMono-Regular (TrueType)') 'Scoop registry label is detected'
Assert-True (-not (Test-NerdFontRegistryName 'FiraCode Nerd Font Propo')) 'Propo variant is rejected'
Assert-True (-not (Test-NerdFontRegistryName 'FiraCode Nerd Font')) 'non-Mono variant is rejected'

# Exercise pwsh-font's standalone prerequisite bootstrap without touching real
# Scoop, registry, or font state. Functions override cmdlets only in this process.
$script:testFontInstalled = $false
$script:testManagerReady = $false
$script:testBootstrapCalls = 0
$script:testScoopCalls = @()
function Test-NerdFont { return $script:testFontInstalled }
function Test-PackageManager { return $script:testManagerReady }
function Install-PackageManager {
    $script:testBootstrapCalls++
    $script:testManagerReady = $true
    return $true
}
function scoop {
    $script:testScoopCalls += (, @($args))
    if ($args[0] -eq 'install') { $script:testFontInstalled = $true }
}

Assert-True (Install-NerdFont) 'font install succeeds after prerequisite bootstrap'
Assert-True ($script:testBootstrapCalls -eq 1) 'Scoop bootstrap is requested exactly once'
Assert-True ($script:testScoopCalls.Count -eq 2) 'bucket and package commands both execute'
Assert-True ($script:testScoopCalls[0][0] -eq 'bucket') 'nerd-fonts bucket is configured first'
Assert-True ($script:testScoopCalls[1][0] -eq 'install') 'font package is installed second'

# A failed prerequisite must fail closed with a truthful hint.
$script:testFontInstalled = $false
$script:testManagerReady = $false
function Install-PackageManager { return $false }
Assert-True (-not (Install-NerdFont)) 'font install fails when Scoop bootstrap fails'
Assert-True ((Get-NerdFontInstallHint) -match 'could not install its Scoop prerequisite') 'hint preserves prerequisite failure'

Write-Host 'OK - Scoop prerequisite bootstrap and Windows Nerd Font detection.'
