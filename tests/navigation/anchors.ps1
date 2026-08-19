$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
}

# ==============================================================================
# The anchor layer, executed rather than asserted about.
#
# roots.ps1 reaches the OS only through adapters, so the whole file runs anywhere once
# that contract is defined as stubs -- the technique COMPONENTS.md records for the pmx
# component. Get-HomePath is stubbed FIRST because $script:NavAnchorsFile is computed
# from it at dot-source time, which is what keeps this test off the real ~/.nav_anchors.json.
# ==============================================================================

$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('pf-anchors-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $sandbox -Force | Out-Null

$script:PowerFlowOS = 'windows'
function Get-HomePath           { return $sandbox }
function Get-PowerFlowConfigPath { return (Join-Path $sandbox 'config') }
function Get-TempPath           { return (Join-Path $sandbox 'tmp') }
function Get-UserFolderPath     { param($Name, $Prefer) return '' }
$script:StorageVolumes = @()
function Get-StorageVolume      { return @($script:StorageVolumes) }

. (Join-Path $repo 'components/navigation/roots.ps1')

$anchorsFile = Join-Path $sandbox '.nav_anchors.json'

# Directories the anchors will point at.
$projects = Join-Path $sandbox 'Projects'
$devtools = Join-Path $sandbox 'DevTools'
$homeDir  = Join-Path $sandbox 'home'
$doomed   = Join-Path $sandbox 'Doomed'
foreach ($d in @($projects, $devtools, $homeDir, $doomed)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }

try {
    # ---- the old flat file is still readable ---------------------------------
    # Anyone upgrading keeps the anchors they already had. A migration that runs at
    # profile load would be a startup failure mode; reading both shapes is four lines.
    '{"mon":"' + ($projects -replace '\\', '\\') + '"}' | Set-Content -LiteralPath $anchorsFile -Encoding UTF8
    Assert-True ((Get-PFUserAnchors).Contains('mon')) 'a flat name->path anchor file is still read'
    Assert-True ((Get-PFUserAnchors)['mon'] -eq $projects) 'the flat form keeps its path'
    Assert-True ((Resolve-PFRootAlias '-mon') -eq 'mon') 'a legacy anchor still resolves'
    Remove-Item -LiteralPath $anchorsFile -Force

    # ---- the folder names itself ---------------------------------------------
    Add-PFAnchor -Path $projects | Out-Null
    Assert-True ((Get-PFUserAnchors).Contains('projects')) 'an anchor takes its own folder name with no second argument'
    Assert-True ((Resolve-PFRootAlias '-projects') -eq 'projects') 'the folder-derived spelling resolves'

    # ---- a supplied word is an EXTRA spelling, not a replacement -------------
    Add-PFAnchor -Path $projects -Name 'pro' | Out-Null
    $table = Get-PFUserAnchorTable
    Assert-True ($table.Contains('projects')) 'the folder name stays canonical'
    Assert-True (@($table['projects'].Aliases) -contains 'pro') 'the supplied word is kept as an alias'
    Assert-True ((Resolve-PFRootAlias '-pro') -eq 'projects') 'the alias resolves to the canonical anchor'
    Assert-True ((Resolve-PFRootAlias '-projects') -eq 'projects') 'and the canonical spelling still works'

    # A single alias survives the ConvertTo-Json round trip. A one-element array serialises
    # as a bare string, which is the trap Save-NavSearchRoots already documents.
    Assert-True (@((Get-PFUserAnchorTable)['projects'].Aliases).Count -eq 1) 'one alias round-trips as a list, not a scalar'

    # ---- several spellings at once -------------------------------------------
    Add-PFAnchor -Path $devtools -Aliases @('devt', 'devtool') | Out-Null
    foreach ($spelling in @('devtools', 'devt', 'devtool')) {
        Assert-True ((Resolve-PFRootAlias "-$spelling") -eq 'devtools') "-$spelling reaches the devtools anchor"
    }

    # ---- built-ins are protected ---------------------------------------------
    # A saved anchor must never change what -docs or -home already mean.
    Add-PFAnchor -Path $projects -Name 'pro' -Aliases @('docs') 3>$null | Out-Null
    Assert-True (-not (@((Get-PFUserAnchorTable)['projects'].Aliases) -contains 'docs')) 'an alias that shadows a built-in is dropped'
    Assert-True ((Resolve-PFRootAlias '-docs') -ne 'projects') '-docs still means the built-in'

    # A folder whose own name is a built-in falls back to the word the user gave.
    Add-PFAnchor -Path $homeDir -Name 'lab' | Out-Null
    Assert-True (-not (Get-PFUserAnchorTable).Contains('home')) 'a folder named after a built-in does not claim that name'
    Assert-True ((Get-PFUserAnchorTable).Contains('lab')) 'it uses the supplied word as its canonical name instead'

    # ---- one anchor cannot steal another's spelling --------------------------
    Add-PFAnchor -Path $devtools -Name 'pro' 3>$null | Out-Null
    Assert-True ((Resolve-PFRootAlias '-pro') -eq 'projects') 'an alias already owned by another anchor is refused'

    # ---- removal works by ANY spelling ---------------------------------------
    Assert-True ((Get-PFUserAnchorTable).Contains('devtools')) 'devtools anchor exists before removal'
    Remove-PFAnchor -Name 'devt' | Out-Null
    Assert-True (-not (Get-PFUserAnchorTable).Contains('devtools')) 'removing by an alias removes the whole anchor'
    Assert-True ((Resolve-PFRootAlias '-devtool') -eq '') 'its other spellings go with it'

    # ---- an anchor whose directory is gone is not offered --------------------
    # A starting point that resolves nowhere reads as "your files vanished".
    Add-PFAnchor -Path $doomed | Out-Null
    Assert-True ((Get-PFUserAnchorTable).Contains('doomed')) 'the anchor exists while its directory does'
    Remove-Item -LiteralPath $doomed -Recurse -Force
    Assert-True (-not (Get-PFUserAnchorTable).Contains('doomed')) 'an anchor pointing at a deleted directory is not offered'

    # ---- candidate discovery prefers a non-system volume ---------------------
    $script:StorageVolumes = @(
        [pscustomobject]@{ Name = 'C:'; Root = (Join-Path $sandbox 'sys') + [IO.Path]::DirectorySeparatorChar; IsSystem = $true }
        [pscustomobject]@{ Name = 'D:'; Root = $sandbox; IsSystem = $false }
    )
    $candidates = @(Get-PFCodeRootCandidate)
    Assert-True ($candidates.Count -gt 0) 'candidates are discovered from a non-system volume'
    Assert-True ($candidates[0].OffSystem) 'a non-system volume is offered first'
    $names = @($candidates | ForEach-Object { Split-Path -Leaf $_.Path })
    Assert-True ($names -contains 'Projects') 'a directory on the second drive is offered'
    # "Projects" is a name people actually use for code, so it outranks a sibling that is not.
    $projectsIdx = [array]::IndexOf($names, 'Projects')
    $devtoolsIdx = [array]::IndexOf($names, 'DevTools')
    Assert-True ($projectsIdx -lt $devtoolsIdx) 'a likely code folder sorts above an unlikely sibling'
}
finally {
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'OK - anchors carry several spellings, folders name themselves, built-ins stay protected.'
