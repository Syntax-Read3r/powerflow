# ==============================================================================
# PowerFlow — Project Version Files
# ==============================================================================
# Domain   : Git
# File     : components/git/version-files.ps1
# Purpose  : Detect, read and write a project's NATIVE version file, whatever the
#            language. Lets git-rl work in any repository, not just PowerFlow's.
# Functions: Get-ProjectVersionSource, Get-ProjectVersion, Set-ProjectVersion,
#            Update-ProjectVersion, Test-VersionDrift
# Depends  : none (pure text handling — platform-agnostic)
# ==============================================================================
#
# WHY THIS EXISTS
#
# git-rl used to read ONE hardcoded location:
#
#     config/PowerFlow.settings.ps1  ->  $script:POWERFLOW_VERSION = "X.Y.Z"
#
# In any other project it silently fell back to the latest git tag and rewrote
# nothing — so a Node project's package.json was never bumped. The old setup guide
# worked around this by telling Node developers to create a PowerShell file in their
# repo and then add a CI check to stop it drifting from package.json. That is a
# workaround for a limitation, not a design.
#
# The version already lives somewhere in every project. Read THAT.
#
# If several version files exist, ALL of them are updated together — which removes
# version drift at the source instead of asking CI to catch it afterwards.
# ==============================================================================

# Every version source PowerFlow understands.
#
# `Section` (TOML only) anchors the match so a `version = "..."` under
# [dependencies] is never mistaken for the project's own version.
function Get-VersionFileDefinition {
    return @(
        [pscustomobject]@{
            Type = 'powerflow'; Label = 'config/PowerFlow.settings.ps1'
            File = 'config/PowerFlow.settings.ps1'
            Read = '\$script:POWERFLOW_VERSION\s*=\s*"([^"]+)"'
            Section = $null
        }
        [pscustomobject]@{
            Type = 'node'; Label = 'package.json'
            File = 'package.json'
            Read = '"version"\s*:\s*"([^"]+)"'
            Section = $null
        }
        [pscustomobject]@{
            Type = 'python'; Label = 'pyproject.toml'
            File = 'pyproject.toml'
            Read = '(?m)^\s*version\s*=\s*"([^"]+)"'
            Section = '(?:project|tool\.poetry)'
        }
        [pscustomobject]@{
            Type = 'rust'; Label = 'Cargo.toml'
            File = 'Cargo.toml'
            Read = '(?m)^\s*version\s*=\s*"([^"]+)"'
            Section = 'package'
        }
        [pscustomobject]@{
            Type = 'gradle'; Label = 'build.gradle'
            File = 'build.gradle'
            Read = "(?m)^\s*version\s*=\s*['`"]([^'`"]+)['`"]"
            Section = $null
        }
        [pscustomobject]@{
            Type = 'gradle'; Label = 'build.gradle.kts'
            File = 'build.gradle.kts'
            Read = "(?m)^\s*version\s*=\s*['`"]([^'`"]+)['`"]"
            Section = $null
        }
        [pscustomobject]@{
            Type = 'plain'; Label = 'VERSION'
            File = 'VERSION'
            Read = '^\s*v?([0-9]+\.[0-9]+\.[0-9]+[^\s]*)\s*$'
            Section = $null
        }
    )
}

# Pull the version out of a TOML file, anchored to the correct section.
# A naive `^version = "..."` would happily match the first dependency it found.
function Read-TomlSectionVersion {
    param(
        [Parameter(Mandatory)][string]$Raw,
        [Parameter(Mandatory)][string]$Section
    )

    # Match: the section header, then anything that is NOT a new section header,
    # up to the first `version = "..."`.
    #
    # Built by CONCATENATION, not interpolation. In a double-quoted PowerShell string
    # the regex `$(?:` is parsed as a subexpression `$(...)` and the whole file fails to
    # parse. Single-quoted fragments keep the regex literal.
    $pattern = '(?ms)^\[' + $Section + '\]\s*$(?:(?!^\[).)*?^\s*version\s*=\s*"([^"]+)"'

    if ($Raw -match $pattern) { return $matches[1] }
    return $null
}

<#
.SYNOPSIS
    Find every version file in a repository.
.DESCRIPTION
    Returns one object per version file found, each carrying its current version.
    Empty when the project has no version file — the caller should then fall back to
    the latest git tag.
#>
function Get-ProjectVersionSource {
    param([Parameter(Mandatory)][string]$RepoRoot)

    $found = [System.Collections.Generic.List[object]]::new()

    foreach ($def in (Get-VersionFileDefinition)) {
        $path = Join-Path $RepoRoot $def.File
        if (-not (Test-Path -LiteralPath $path)) { continue }

        $raw     = Get-Content -LiteralPath $path -Raw -ErrorAction SilentlyContinue
        if (-not $raw) { continue }

        $version = if ($def.Section) {
            Read-TomlSectionVersion -Raw $raw -Section $def.Section
        }
        elseif ($raw -match $def.Read) {
            $matches[1]
        }
        else { $null }

        if (-not $version) { continue }

        $found.Add([pscustomobject]@{
            Type    = $def.Type
            Label   = $def.Label
            Path    = $path
            Version = $version
            Read    = $def.Read
            Section = $def.Section
        })
    }

    # .NET projects: the version lives in a *.csproj, whose name varies.
    Get-ChildItem -LiteralPath $RepoRoot -Filter '*.csproj' -File -ErrorAction SilentlyContinue |
        ForEach-Object {
            $raw = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue
            if ($raw -match '<Version>\s*([^<\s]+)\s*</Version>') {
                $found.Add([pscustomobject]@{
                    Type    = 'dotnet'
                    Label   = $_.Name
                    Path    = $_.FullName
                    Version = $matches[1]
                    Read    = '<Version>\s*([^<\s]+)\s*</Version>'
                    Section = $null
                })
            }
        }

    return $found
}

# Do the detected version files disagree with each other?
# This is the drift the old setup guide asked CI to police. Catch it before the bump.
function Test-VersionDrift {
    param([Parameter(Mandatory)][object[]]$Sources)

    if ($Sources.Count -lt 2) { return $false }
    $distinct = @($Sources.Version | Sort-Object -Unique)
    return ($distinct.Count -gt 1)
}

# The project's current version. Prefers a real version file; falls back to git tags.
function Get-ProjectVersion {
    param([Parameter(Mandatory)][string]$RepoRoot)

    $sources = @(Get-ProjectVersionSource -RepoRoot $RepoRoot)

    if ($sources.Count -gt 0) {
        return [pscustomobject]@{
            Version = $sources[0].Version
            Sources = $sources
            From    = 'files'
        }
    }

    $tag = git -C $RepoRoot describe --tags --abbrev=0 2>$null
    if ($tag -and $tag -match '^v?([0-9]+\.[0-9]+\.[0-9]+)') {
        return [pscustomobject]@{
            Version = $matches[1]
            Sources = @()
            From    = 'tag'
        }
    }

    return [pscustomobject]@{ Version = '0.0.0'; Sources = @(); From = 'default' }
}

# Rewrite ONE version file, preserving its formatting exactly.
#
# Deliberately regex-based, never a parse-and-reserialise. Round-tripping package.json
# through ConvertFrom-Json / ConvertTo-Json would reorder keys, change indentation and
# mangle the whole file — an unacceptable diff for a version bump.
function Set-ProjectVersion {
    param(
        [Parameter(Mandatory)]$Source,
        [Parameter(Mandatory)][string]$NewVersion
    )

    $raw = Get-Content -LiteralPath $Source.Path -Raw

    $updated = switch ($Source.Type) {

        'plain' { "$NewVersion`n" }

        'powerflow' {
            $raw -replace '\$script:POWERFLOW_VERSION\s*=\s*"[^"]+"',
                          "`$script:POWERFLOW_VERSION = `"$NewVersion`""
        }

        'dotnet' {
            $raw -replace '(<Version>\s*)[^<\s]+(\s*</Version>)', "`${1}$NewVersion`${2}"
        }

        default {
            # node / python / rust / gradle: replace only the FIRST occurrence of the
            # CURRENT version in its expected shape. Anchoring to the known current
            # value means a matching string elsewhere in the file cannot be hit.
            $escaped = [regex]::Escape($Source.Version)

            $pattern = switch ($Source.Type) {
                'node'   { '("version"\s*:\s*")' + $escaped + '(")' }
                'gradle' { "(version\s*=\s*['`"])" + $escaped + "(['`"])" }
                default  { '(version\s*=\s*")' + $escaped + '(")' }   # python / rust (TOML)
            }

            [regex]::new($pattern).Replace($raw, "`${1}$NewVersion`${2}", 1)
        }
    }

    # WriteAllText, not Set-Content: Set-Content appends a trailing newline, which would
    # add a spurious line to every version file on every release.
    [System.IO.File]::WriteAllText($Source.Path, $updated, [System.Text.UTF8Encoding]::new($false))

    # Verify rather than trust the regex.
    $check = Get-Content -LiteralPath $Source.Path -Raw
    $now   = if ($Source.Section) {
        Read-TomlSectionVersion -Raw $check -Section $Source.Section
    } elseif ($check -match $Source.Read) { $matches[1] } else { $null }

    return ($now -eq $NewVersion)
}

<#
.SYNOPSIS
    Bump every version file in the project to $NewVersion.
.DESCRIPTION
    Updating all of them together is what removes version drift. Returns the list of
    files it changed, so the caller can report exactly what moved.
#>
function Update-ProjectVersion {
    param(
        [Parameter(Mandatory)][object[]]$Sources,
        [Parameter(Mandatory)][string]$NewVersion
    )

    $updated = [System.Collections.Generic.List[object]]::new()

    foreach ($s in $Sources) {
        if (Set-ProjectVersion -Source $s -NewVersion $NewVersion) {
            Write-Host "   ✅ $($s.Label)  $($s.Version) → $NewVersion" -ForegroundColor Green
            $updated.Add($s)
        } else {
            Write-Host "   ❌ $($s.Label) — could not update" -ForegroundColor Red
        }
    }

    return $updated
}
