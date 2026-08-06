$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
}

$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testRoot = Join-Path $tempRoot "powerflow-scoop-prereq-$([guid]::NewGuid().ToString('N'))"
$profileDir = Join-Path $testRoot 'PowerShell'
$profilePath = Join-Path $profileDir 'Microsoft.PowerShell_profile.ps1'

try {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null

    $escapedProfile = $profilePath -replace "'", "''"
    $escapedRoot = $root -replace "'", "''"
    $installScript = "`$PROFILE = '$escapedProfile'; & '$escapedRoot\install.ps1' -Yes -NoDeps -Prefix '$escapedRoot' -Platform windows"
    $installOutput = @(& pwsh -NoLogo -NoProfile -Command $installScript 2>&1)
    Assert-True ($LASTEXITCODE -eq 0) 'isolated installer succeeds'
    Assert-True (@($installOutput -match 'Scoop \((already present)\)|Scoop installed and active').Count -gt 0) 'installer verifies or installs Scoop under -NoDeps'
    Assert-True (Test-Path -LiteralPath (Join-Path $profileDir '.powerflow-manifest.json')) 'installer writes manifest'

    $uninstaller = Join-Path $profileDir 'uninstall.ps1'
    $escapedUninstaller = $uninstaller -replace "'", "''"
    $uninstallScript = "`$PROFILE = '$escapedProfile'; & '$escapedUninstaller' -Yes"
    $uninstallOutput = @(& pwsh -NoLogo -NoProfile -Command $uninstallScript 2>&1)
    Assert-True ($LASTEXITCODE -eq 0) 'isolated automated uninstall succeeds'
    Assert-True (@($uninstallOutput -match 'Scoop will be kept').Count -gt 0) 'automated uninstall keeps Scoop'
}
finally {
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    if ($resolvedTestRoot.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path $resolvedTestRoot -Leaf) -like 'powerflow-scoop-prereq-*' -and
        (Test-Path -LiteralPath $resolvedTestRoot)) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}

Write-Host 'OK - isolated installer enforces Scoop under -NoDeps and automated uninstall keeps it.'
