$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
}

$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $root 'platform/windows/adapters/packages.ps1')

# The safe/default "no" path must not display the destructive warning.
$noOutput = @(& { Confirm-PackageManagerRemoval -ReadResponse { param($Prompt) 'n' } } 6>&1)
Assert-True (@($noOutput -match 'EVERY application').Count -eq 0) 'risk warning is hidden until the user answers yes'
Assert-True ($noOutput[-1] -eq $false) 'no keeps Scoop'

# After yes, display the risks and require another answer before handing off to
# Scoop's own final confirmation.
$script:testRemovalAnswers = [Collections.Generic.Queue[string]]::new()
$script:testRemovalAnswers.Enqueue('yes')
$script:testRemovalAnswers.Enqueue('no')
$warningOutput = @(& {
    Confirm-PackageManagerRemoval -ReadResponse {
        param($Prompt)
        return $script:testRemovalAnswers.Dequeue()
    }
} 6>&1)
Assert-True (@($warningOutput -match 'EVERY application managed by Scoop').Count -gt 0) 'yes displays all-applications warning'
Assert-True (@($warningOutput -match 'unrelated commands and workflows').Count -gt 0) 'yes explains unrelated-workflow risk'
Assert-True ($warningOutput[-1] -eq $false) 'second no keeps Scoop'

$script:testRemovalAnswers.Enqueue('yes')
$script:testRemovalAnswers.Enqueue('yes')
$confirmOutput = @(& {
    Confirm-PackageManagerRemoval -ReadResponse {
        param($Prompt)
        return $script:testRemovalAnswers.Dequeue()
    }
} 6>&1)
Assert-True ($confirmOutput[-1] -eq $true) 'two yes answers permit Scoop handoff'

# Integration: -Yes is non-interactive and must keep Scoop without ever invoking
# its uninstaller. All filesystem changes stay inside a disposable test root.
$testRoot = Join-Path ([IO.Path]::GetTempPath()) "powerflow-uninstall-scoop-$([guid]::NewGuid().ToString('N'))"
$profileDir = Join-Path $testRoot 'profile'
$adapterDir = Join-Path $profileDir 'platform/windows/adapters'
$profilePath = Join-Path $profileDir 'Microsoft.PowerShell_profile.ps1'
$markerPath = Join-Path $testRoot 'PACKAGE_MANAGER_REMOVAL_WAS_CALLED'
try {
    New-Item -ItemType Directory -Path $adapterDir -Force | Out-Null
    Set-Content -LiteralPath $profilePath -Value '# disposable profile'
    @'
function Test-PackageManager { return $true }
function Uninstall-Dependency { return $true }
function Confirm-PackageManagerRemoval { throw 'interactive Scoop prompt must not run under -Yes' }
function Uninstall-PackageManager {
    Set-Content -LiteralPath '__MARKER__' -Value 'called'
    return $true
}
'@.Replace('__MARKER__', ($markerPath -replace "'", "''")) |
        Set-Content -LiteralPath (Join-Path $adapterDir 'packages.ps1')

    $manifest = [ordered]@{
        version = 'test'
        platform = 'windows'
        installedAt = 'test'
        installRoot = $profileDir
        profilePath = $profilePath
        files = @($profilePath)
        dependencies = @()
        backup = $null
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $profileDir '.powerflow-manifest.json')

    $escapedProfile = $profilePath -replace "'", "''"
    $escapedUninstaller = (Join-Path $root 'uninstall.ps1') -replace "'", "''"
    $childScript = "`$PROFILE = '$escapedProfile'; & '$escapedUninstaller' -Yes"
    $uninstallOutput = @(& pwsh -NoLogo -NoProfile -Command $childScript 2>&1)
    Assert-True ($LASTEXITCODE -eq 0) '-Yes sandbox uninstall succeeds'
    Assert-True (-not (Test-Path -LiteralPath $markerPath)) '-Yes never invokes Scoop removal'
    Assert-True (@($uninstallOutput -match 'Scoop will be kept').Count -gt 0) '-Yes reports that Scoop is kept'
}
finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

Write-Host 'OK - Scoop removal is separately warned, confirmed, and automation-safe.'
