$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
}

# ==============================================================================
# Where PowerFlow thinks Scoop is, and what it puts on PATH as a result.
#
# Two layers, both exercised against the real shipped files rather than a copy of their
# logic -- a test that reimplements a rule cannot catch the rule changing:
#
#   Get-PackageManagerRoot   platform/windows/adapters/packages.ps1
#   Initialize-PFScoopPath   config/paths.windows.ps1
#
# Get-HomePath is stubbed so the root_path lookup reads a sandboxed config file instead of
# the real profile. That is precisely why the adapter calls Get-HomePath rather than
# [Environment]::GetFolderPath('UserProfile'), which ignores $env:USERPROFILE and cannot be
# redirected at all.
# ==============================================================================

$repo    = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$adapter = Join-Path $repo 'platform/windows/adapters/packages.ps1'
$config  = Join-Path $repo 'config/paths.windows.ps1'
foreach ($f in @($adapter, $config)) { Assert-True (Test-Path -LiteralPath $f) "$f exists" }

$tmp       = Join-Path ([IO.Path]::GetTempPath()) ('pf-scoop-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$relocated = Join-Path $tmp 'DevTools\Scoop'
$notNamed  = Join-Path $tmp 'DevTools\Tools'
$noShims   = Join-Path $tmp 'DevTools\Fresh'
$recorded  = Join-Path $tmp 'DevTools\Recorded'
$decoy     = Join-Path $tmp 'Projects\scooper\bin'
$fakeHome  = Join-Path $tmp 'home'
foreach ($d in @((Join-Path $relocated 'shims'), (Join-Path $notNamed 'shims'), $noShims,
                 (Join-Path $recorded 'shims'), $decoy, (Join-Path $fakeHome '.config\scoop'))) {
    New-Item -ItemType Directory -Path $d -Force | Out-Null
}
$scoopConfig = Join-Path $fakeHome '.config\scoop\config.json'

# Run a snippet in a child pwsh with the adapter loaded, a stubbed home, and a controlled
# environment. Nothing leaks into this session, and the controlled PATH contains neither
# starship nor zoxide so those initialisation blocks in paths.windows.ps1 skip on their own.
function Invoke-InChild {
    param([string]$Scoop, [string]$Path, [string]$Body)
    $script = @"
`$env:SCOOP = '$Scoop'
`$env:PATH  = '$Path'
function Get-HomePath { return '$fakeHome' }
. '$adapter'
$Body
"@
    $out = & pwsh -NoProfile -Command $script
    if ($LASTEXITCODE -ne 0) { throw "child pwsh failed: $out" }
    return $out
}

function Get-Root {
    param([string]$Scoop = '', [string]$Path = 'C:\Windows')
    return "$(Invoke-InChild -Scoop $Scoop -Path $Path -Body 'Get-PackageManagerRoot')".Trim()
}

function Invoke-PathsWindows {
    param([string]$Scoop, [string]$Path)
    $body = ". '$config'`n[pscustomobject]@{ Scoop = `"`$env:SCOOP`"; Path = `"`$env:PATH`" } | ConvertTo-Json -Compress"
    return (Invoke-InChild -Scoop $Scoop -Path $Path -Body $body | ConvertFrom-Json)
}

function Test-OnPath([string]$Path, [string]$Entry) {
    return [bool](@($Path -split ';' | Where-Object { $_ } | Where-Object {
        [string]::Equals($_.TrimEnd('\'), $Entry.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)
    }).Count)
}

$base = 'C:\Windows;C:\Windows\System32'

try {
    # ══ Layer 1 — Get-PackageManagerRoot ═════════════════════════════════════
    # THE VARIABLE IS NOT WHERE SCOOP KEEPS THE ANSWER. Relocating with the installer's
    # -ScoopDir records root_path in Scoop's own config and sets no variable at all, so a
    # resolver that reads only $env:SCOOP reports a relocated Scoop as missing.
    Remove-Item -LiteralPath $scoopConfig -Force -ErrorAction SilentlyContinue
    Assert-True ((Get-Root) -eq (Join-Path $fakeHome 'scoop')) 'with nothing configured, the root is ~\scoop'
    Assert-True ((Get-Root -Scoop $relocated) -eq $relocated) 'the environment variable wins when set'

    (@{ root_path = $recorded; last_update = 'x' } | ConvertTo-Json) | Set-Content -LiteralPath $scoopConfig -Encoding UTF8
    Assert-True ((Get-Root) -eq $recorded) "Scoop's own root_path is honoured when no variable is set"
    Assert-True ((Get-Root -Scoop $relocated) -eq $relocated) 'the variable still outranks root_path'

    # The upstream installer writes root_path ONLY when no User-scope SCOOP exists, so the
    # two are alternatives. Both must resolve, and neither may shadow the other silently.
    'this is not json {' | Set-Content -LiteralPath $scoopConfig -Encoding UTF8
    Assert-True ((Get-Root) -eq (Join-Path $fakeHome 'scoop')) 'a corrupt config degrades to the default instead of throwing'

    (@{ other_setting = 1 } | ConvertTo-Json) | Set-Content -LiteralPath $scoopConfig -Encoding UTF8
    Assert-True ((Get-Root) -eq (Join-Path $fakeHome 'scoop')) 'a config without root_path degrades to the default'

    # A root on an unmounted drive is reported as-is. Agreeing with Scoop about where Scoop
    # is matters more than reporting something reachable -- quietly answering ~\scoop would
    # have PowerFlow acting on a different installation from the one the user has.
    (@{ root_path = 'Q:\NotMounted\Scoop' } | ConvertTo-Json) | Set-Content -LiteralPath $scoopConfig -Encoding UTF8
    Assert-True ((Get-Root) -eq 'Q:\NotMounted\Scoop') 'a recorded root that does not exist is still reported'
    Remove-Item -LiteralPath $scoopConfig -Force

    # ══ Layer 2 — Initialize-PFScoopPath ═════════════════════════════════════
    # 1. THE REGRESSION. A persisted root reaches a new shell before the PATH update does,
    #    and that is exactly when the old code overwrote it with a C: path.
    $r = Invoke-PathsWindows -Scoop $relocated -Path $base
    Assert-True ($r.Scoop -eq $relocated) 'a relocated Scoop root is never reassigned'
    Assert-True (Test-OnPath $r.Path (Join-Path $relocated 'shims')) 'its shim directory is added'

    # 2. The root's FOLDER NAME is irrelevant. The old guard only ever protected a root that
    #    happened to be called "scoop", which was luck rather than logic.
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

    # 7. The two layers agree: a root recorded ONLY in Scoop's config still reaches PATH.
    #    This is the case PowerFlow was blind to, end to end.
    (@{ root_path = $recorded } | ConvertTo-Json) | Set-Content -LiteralPath $scoopConfig -Encoding UTF8
    $r = Invoke-PathsWindows -Scoop '' -Path $base
    Assert-True (Test-OnPath $r.Path (Join-Path $recorded 'shims')) 'a root known only from root_path still puts its shims on PATH'
    Assert-True ([string]::IsNullOrEmpty($r.Scoop)) 'and reading root_path still does not invent the variable'
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'OK - Scoop root resolves through env then root_path, is never written, and shims match exactly.'
