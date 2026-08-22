$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
}
function Assert-Equal($Expected, $Actual, [string]$Message) {
    if ("$Expected" -cne "$Actual") {
        throw "FAIL: $Message`n  expected: $Expected`n  actual:   $Actual"
    }
}

# The adapters own environment access; shared navigation components only consume the
# cross-platform contract. An unset override must preserve the legacy ~/.nav_* location.
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('pf-nav-data-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$previousDataHome = $env:POWERFLOW_DATA_HOME

try {
    $env:POWERFLOW_DATA_HOME = $null
    . (Join-Path $repo 'platform/windows/adapters/locations.ps1')
    Assert-Equal (Get-HomePath) (Get-PowerFlowNavigationDataPath) `
        'Windows falls back to the legacy home location when no override is set'

    $windowsOverride = Join-Path $sandbox 'windows-data'
    $env:POWERFLOW_DATA_HOME = $windowsOverride
    Assert-Equal $windowsOverride (Get-PowerFlowNavigationDataPath) `
        'Windows honours POWERFLOW_DATA_HOME exactly'

    $env:POWERFLOW_DATA_HOME = $null
    . (Join-Path $repo 'platform/linux/adapters/locations.ps1')
    Assert-Equal (Get-HomePath) (Get-PowerFlowNavigationDataPath) `
        'Linux falls back to the legacy home location when no override is set'

    $linuxOverride = Join-Path $sandbox 'linux-data'
    $env:POWERFLOW_DATA_HOME = $linuxOverride
    Assert-Equal $linuxOverride (Get-PowerFlowNavigationDataPath) `
        'Linux honours POWERFLOW_DATA_HOME exactly'

    # Exercise real persistence code against a destination that does not exist yet.
    # This catches the failure mode introduced when the old parent ($HOME) was replaced:
    # Set-Content cannot create its parent directory for us.
    $dataHome = Join-Path $sandbox 'component-data'
    $legacyHome = Join-Path $sandbox 'legacy-home'
    New-Item -ItemType Directory -Path $legacyHome -Force | Out-Null
    function Get-HomePath { return $legacyHome }
    function Get-PowerFlowNavigationDataPath { return $dataHome }
    function Get-PowerFlowConfigPath { return (Join-Path $sandbox 'config') }
    $script:PowerFlowOS = 'windows'

    . (Join-Path $repo 'components/navigation/roots.ps1')
    . (Join-Path $repo 'components/navigation/bookmarks.ps1')

    $expectedRootsFile = Join-Path $dataHome '.nav_roots.json'
    $expectedBookmarkFile = Join-Path $dataHome '.nav_bookmarks.json'
    Assert-Equal $expectedRootsFile $script:NavRootsFile 'search roots bind to the configured data home'
    Assert-Equal $expectedBookmarkFile $script:BookmarkFile 'bookmarks bind to the configured data home'

    $liveRoot = Join-Path $sandbox 'Projects'
    New-Item -ItemType Directory -Path $liveRoot -Force | Out-Null
    Save-NavSearchRoots @($liveRoot)
    Assert-True (Test-Path -LiteralPath $expectedRootsFile) 'saving roots creates the new data directory and file'
    Assert-Equal $liveRoot (@(Get-NavSearchRoots)[0]) 'saved roots round-trip from the configured data home'

    Assert-True (Save-Bookmarks @{ work = $liveRoot }) 'saving bookmarks succeeds in a fresh data directory'
    Assert-True (Test-Path -LiteralPath $expectedBookmarkFile) 'saving bookmarks writes only beneath the data home'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $legacyHome '.nav_roots.json'))) `
        'roots do not leak back into the legacy home when an override is configured'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $legacyHome '.nav_bookmarks.json'))) `
        'bookmarks do not leak back into the legacy home when an override is configured'
}
finally {
    $env:POWERFLOW_DATA_HOME = $previousDataHome
    if (Test-Path -LiteralPath $sandbox) {
        Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host 'OK - navigation data follows POWERFLOW_DATA_HOME with legacy cross-platform fallback.'
