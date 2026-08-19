$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
}

$root       = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$configFile = Join-Path $root 'config/paths.windows.ps1'
Assert-True (Test-Path -LiteralPath $configFile) 'config/paths.windows.ps1 exists'

# Fixtures: a relocated root with shims, one whose folder is NOT named "scoop", a root
# with no shims yet, and a decoy whose path merely CONTAINS "scoop" -- the exact shape
# that defeated the old `$env:PATH -like "*scoop*"` guard.
$tmp       = Join-Path ([IO.Path]::GetTempPath()) ('pf-scoop-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$relocated = Join-Path $tmp 'DevTools\Scoop'
$notNamed  = Join-Path $tmp 'DevTools\Tools'
$noShims   = Join-Path $tmp 'DevTools\Fresh'
$decoy     = Join-Path $tmp 'Projects\scooper\bin'
foreach ($d in @((Join-Path $relocated 'shims'), (Join-Path $notNamed 'shims'), $noShims, $decoy)) {
    New-Item -ItemType Directory -Path $d -Force | Out-Null
}

# Load the REAL file in a child process. The controlled PATH contains neither starship nor
# zoxide, so those initialisation blocks skip on their own, and nothing leaks into this
# session. Asserting on the shipped file rather than a copy of its logic is the point:
# a test that reimplements the rule cannot catch the rule being changed.
function Invoke-PathsWindows {
    param([string]$Scoop, [string]$Path)
    $childScript = @"
`$env:SCOOP = '$Scoop'
`$env:PATH  = '$Path'
. '$configFile'
[pscustomobject]@{ Scoop = "`$env:SCOOP"; Path = "`$env:PATH" } | ConvertTo-Json -Compress
"@
    $json = & pwsh -NoProfile -Command $childScript
    if ($LASTEXITCODE -ne 0) { throw "child pwsh failed: $json" }
    return ($json | ConvertFrom-Json)
}

function Test-OnPath([string]$Path, [string]$Entry) {
    return [bool](@($Path -split ';' | Where-Object { $_ } | Where-Object {
        [string]::Equals($_.TrimEnd('\'), $Entry.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)
    }).Count)
}

$base = 'C:\Windows;C:\Windows\System32'

try {
    # 1. THE REGRESSION. A persisted SCOOP reaches a new shell before the PATH update
    #    does, and that is precisely when the old code overwrote it with a C: path.
    $r = Invoke-PathsWindows -Scoop $relocated -Path $base
    Assert-True ($r.Scoop -eq $relocated) 'a relocated Scoop root is never reassigned'
    Assert-True (Test-OnPath $r.Path (Join-Path $relocated 'shims')) 'its shim directory is added'

    # 2. The root's FOLDER NAME is irrelevant. The old guard only ever protected a root
    #    that happened to be called "scoop", which was luck rather than logic.
    $r = Invoke-PathsWindows -Scoop $notNamed -Path $base
    Assert-True ($r.Scoop -eq $notNamed) 'a root not named "scoop" is preserved'
    Assert-True (Test-OnPath $r.Path (Join-Path $notNamed 'shims')) 'its shim directory is added too'

    # 3. An unrelated entry containing "scoop" must not suppress the real wiring.
    $r = Invoke-PathsWindows -Scoop $relocated -Path "$decoy;$base"
    Assert-True ($r.Scoop -eq $relocated) 'a decoy *scoop* entry does not disturb the root'
    Assert-True (Test-OnPath $r.Path (Join-Path $relocated 'shims')) 'real shims are still added past a decoy'

    # 4. NEVER ASSIGN. With no root configured the variable stays unset, whatever this
    #    machine's own ~/scoop happens to look like.
    $r = Invoke-PathsWindows -Scoop '' -Path $base
    Assert-True ([string]::IsNullOrEmpty($r.Scoop)) 'an unset SCOOP is left unset, never invented'

    # 5. A root whose shims do not exist yet adds nothing: that is a fresh install before
    #    Scoop is bootstrapped, and Add-ScoopShimToCurrentPath covers it in-session.
    $r = Invoke-PathsWindows -Scoop $noShims -Path $base
    Assert-True ($r.Scoop -eq $noShims) 'a root without shims is still preserved'
    Assert-True (-not (Test-OnPath $r.Path (Join-Path $noShims 'shims'))) 'a non-existent shim directory never reaches PATH'

    # 6. Idempotent -- a shell that loads the profile twice must not grow its PATH.
    $shims = Join-Path $relocated 'shims'
    $r = Invoke-PathsWindows -Scoop $relocated -Path "$shims;$base"
    $hits = @($r.Path -split ';' | Where-Object {
        [string]::Equals($_.TrimEnd('\'), $shims.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)
    }).Count
    Assert-True ($hits -eq 1) 'an already-present shim directory is not appended again'
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'OK - Scoop root is read never written, and shim entries are matched exactly.'
