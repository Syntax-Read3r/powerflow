$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-helpers.ps1')

$root = Get-RepoRoot
$componentPath = Join-Path $root 'components/containers/containers.ps1'
$assertions = 0

$script:Registered = @()
function Register-PFCommand {
    param([string]$Name, [string]$Synopsis, [string]$Section, [string]$Example,
          [string[]]$Aliases, [string]$Platform)
    $script:Registered += [pscustomobject]@{ Name = $Name; Section = $Section
        Synopsis = $Synopsis; Example = $Example; Aliases = @($Aliases) }
}
function Get-DependencyInstallHint { param([string]$Name) return "install $Name" }

New-EngineShim -Name 'docker'
New-EngineShim -Name 'podman'
. (Get-ContainerAdapterPath 'linux')
. $componentPath

$componentText = Get-Content -LiteralPath $componentPath -Raw

# ---------------------------------------------------------------------------------
# Both entry points exist, and each pins its own engine. The command NAME is the engine
# selector — that is why there is no --engine flag.
# ---------------------------------------------------------------------------------
foreach ($pair in @(@{ Command = 'dkr'; Engine = 'docker' }, @{ Command = 'pman'; Engine = 'podman' })) {
    Assert-True ([bool](Get-Command $pair.Command -ErrorAction SilentlyContinue)) "$($pair.Command) is not defined"
    $body = [regex]::Match($componentText, "(?m)^function $($pair.Command) \{.*$").Value
    Assert-True ($body -match "-EngineName '$($pair.Engine)'") `
        "$($pair.Command) must pin the engine to $($pair.Engine) - got: $body"
    # A param() block would bind -a and -f as parameter NAMES and reject the rest.
    Assert-True ($body -notmatch '\bparam\s*\(') "$($pair.Command) must not declare a param() block"
    $assertions += 3
}

# Neither entry point may name the other engine's binary — that would defeat the split.
$dkrLine = [regex]::Match($componentText, '(?m)^function dkr \{.*$').Value
$pmanLine = [regex]::Match($componentText, '(?m)^function pman \{.*$').Value
Assert-True ($dkrLine -notmatch 'podman') 'dkr must not reference podman'
Assert-True ($pmanLine -notmatch 'docker') 'pman must not reference docker'
$assertions += 2

# ---------------------------------------------------------------------------------
# There must be exactly ONE implementation. Two copies would drift, which is the defect
# the naming audit found all over the git family.
# ---------------------------------------------------------------------------------
$implCount = @([regex]::Matches($componentText, '(?m)^function Invoke-PFContainerCommand')).Count
Assert-Equal 1 $implCount 'there must be exactly one shared implementation'
$assertions++

# ---------------------------------------------------------------------------------
# Column formatting: gutter reserved, fixed width. Same class as the storage bug.
# ---------------------------------------------------------------------------------
foreach ($sample in @('Up 3 days', 'Exited (137) 3 hours ago', 'Restarting (1) 40 seconds', '', 'x',
                      'a-very-long-container-name-that-overflows')) {
    $cell = Format-ContainerCell $sample 26
    Assert-Equal 26 $cell.Length "cell '$sample' is not exactly the column width"
    Assert-True ($cell.EndsWith(' ')) "cell '$sample' fills its column and leaves no gutter"
    $assertions += 2
}

Assert-Equal '8989' (Format-ContainerPorts '0.0.0.0:8989->8989/tcp, :::8989->8989/tcp') 'IPv6 duplicate not collapsed'
Assert-Equal '-'    (Format-ContainerPorts '') 'no ports should render as a dash'
Assert-Equal '80 443' (Format-ContainerPorts '0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp') 'both ports should appear'
$assertions += 3

# ---------------------------------------------------------------------------------
# Name resolution, against the real fixture through the real adapter.
# ---------------------------------------------------------------------------------
$engine = New-TestEngine -Name 'docker'
$containers = @(Get-ContainerList -Engine $engine -All)
Assert-Equal 4 $containers.Count 'fixture should yield 4 containers'
$assertions++

Assert-Equal 'sonarr' (Resolve-ContainerTargets -Containers $containers -Names @('sonarr')).Matched[0].Name `
    'exact name should match'
Assert-Equal 2 (Resolve-ContainerTargets -Containers $containers -Names @('media')).Matched.Count `
    'a project name should select all of its services'
Assert-Equal 'qbittorrent' (Resolve-ContainerTargets -Containers $containers -Names @('qbit')).Matched[0].Name `
    'substring should match as a last resort'
Assert-Equal 2 (Resolve-ContainerTargets -Containers $containers -Names @('media', 'sonarr')).Matched.Count `
    'overlapping selectors must de-duplicate'
$missing = Resolve-ContainerTargets -Containers $containers -Names @('plex')
Assert-Equal 0 $missing.Matched.Count 'a non-existent name must match nothing'
Assert-Equal 'plex' $missing.Missing[0] 'a non-existent name must be reported missing'
$assertions += 6

# A stopped compose project must still resolve — the only time anyone types `up`.
$projects = @(Get-ContainerComposeProjects -Engine $engine)
$stopped = Resolve-ContainerComposeProject -Name 'archive' -Containers $containers -Projects $projects
Assert-True ($null -ne $stopped) 'a fully stopped compose project must resolve'
Assert-Equal '/srv/docker/archive/docker-compose.yml' $stopped.ConfigFile 'wrong config file for a stopped project'
$scoped = Resolve-ContainerComposeProject -Name 'sonarr' -Containers $containers -Projects $projects
Assert-Equal 'media' $scoped.Name 'a service name should resolve to its project'
Assert-Equal 'sonarr' ($scoped.Services -join ',') 'a service name should scope to itself'
Assert-True ($null -eq (Resolve-ContainerComposeProject -Name 'nope' -Containers $containers -Projects $projects)) `
    'an unknown name must not resolve'
$assertions += 5

# ---------------------------------------------------------------------------------
# The engine-mismatch warning. Podman on Windows can own the standard docker pipe, so
# `dkr` may in fact be driving podman — measured on a real host. Silently mislabelling the
# engine is the exact confusion two commands exist to prevent.
# ---------------------------------------------------------------------------------
Assert-True ($componentText -match '\$engine\.Mismatched') 'the component must surface an engine mismatch'
$mismatchBlock = [regex]::Match($componentText, '(?s)if \(\$engine\.Mismatched\) \{.*?\n    \}').Value
Assert-True ($mismatchBlock -match 'ServedBy') 'the mismatch notice must name which engine actually answered'
Assert-True ($mismatchBlock -match 'to be explicit') 'the mismatch notice must point at the other command'
$assertions += 3

# `down` is the one verb that destroys anything, so it must confirm, and only `down`.
$composeView = [regex]::Match($componentText, '(?s)function Invoke-ContainerComposeView \{.*?\n\}').Value
Assert-True ($composeView -match 'Read-Host') 'down must ask before removing containers'
Assert-True ($composeView -match "\`$Action -eq 'down' -and -not \`$Yes") 'the confirmation must be scoped to down'
$assertions += 2

# ---------------------------------------------------------------------------------
# Architecture — a component may not touch an OS API, a native binary, or the OS name.
# ---------------------------------------------------------------------------------
$code = @($componentText -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
Assert-True ($code -notmatch '&\s*\$?\w*(docker|podman)\b|&\s*sudo\b') `
    'the component must invoke an engine only through the adapter'
Assert-True ($code -notmatch '\$env:(TEMP|USERPROFILE|LOCALAPPDATA|APPDATA)') `
    'the component must not read environment variables directly'
Assert-True ($code -notmatch '\$script:PowerFlowOS') `
    'the component must not branch on the OS - the adapter owns platform knowledge'
$assertions += 3

# Automatic variables as locals — the bug class this repo has hit five or more times.
foreach ($file in @($componentPath, (Get-ContainerAdapterPath 'linux'), (Get-ContainerAdapterPath 'windows'))) {
    $text = Get-Content -LiteralPath $file -Raw
    foreach ($auto in @('args', 'input', 'matches', 'PSItem', 'this')) {
        Assert-True ($text -notmatch "(?m)^\s*\`$$auto\s*=") `
            "$(Split-Path $file -Leaf) assigns to the automatic variable `$$auto"
        $assertions++
    }
}

# ---------------------------------------------------------------------------------
# Help registration — CI fails the release on an unregistered kebab-named command.
# ---------------------------------------------------------------------------------
foreach ($command in @('dkr', 'pman')) {
    foreach ($verb in @('', ' logs', ' shell', ' up', ' down', ' restart', ' stop', ' start')) {
        $name  = "$command$verb"
        $entry = $script:Registered | Where-Object { $_.Name -eq $name }
        Assert-True ($null -ne $entry) "'$name' is not registered for pwsh-h"
        Assert-Equal '🐳 CONTAINERS' $entry.Section "'$name' is in the wrong help section"
        Assert-True ([bool]$entry.Synopsis) "'$name' has no synopsis"
        $assertions += 3
    }
}

# The section must exist in the registry, and be reachable from a chapter.
$registryText = Get-Content -LiteralPath (Join-Path $root 'components/help/registry.ps1') -Raw
Assert-True ($registryText -match "'🐳 CONTAINERS'") 'the CONTAINERS section is not declared in PF_HelpSections'
Assert-True ($registryText -match "Sections = @\([^)]*🐳 CONTAINERS") 'the CONTAINERS section is in no chapter'
Assert-True ($registryText -notmatch '🐳 DOCKER') 'the old DOCKER section should be gone'
$assertions += 3

# Bootloader loads the component, and the old paths are gone.
$profileText = Get-Content -LiteralPath (Join-Path $root 'Microsoft.PowerShell_profile.ps1') -Raw
Assert-True ($profileText -match 'components\\containers\\containers\.ps1') 'containers.ps1 is not loaded by the bootloader'
Assert-True ($profileText -notmatch 'components\\docker\\dkr\.ps1') 'the bootloader still references the removed dkr.ps1'
$assertions += 2

foreach ($gone in @('components/docker', 'platform/linux/adapters/docker.ps1',
                    'platform/windows/adapters/docker.ps1', 'tests/docker')) {
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $root $gone))) "superseded path still exists: $gone"
    $assertions++
}

Remove-EngineShims
Write-Host "  containers behaviour: $assertions assertions passed" -ForegroundColor Green

# ---------------------------------------------------------------------------------
# Zero containers must not be asserted as fact when the engine may have died. Measured
# on podman: it prints its CLIENT version to stdout and exits 125 when unreachable, so a
# version probe alone can pass and the ps call still return nothing. Claiming "no
# containers on this host" then reads as a definitive answer about the host and hides the
# real advisory.
# ---------------------------------------------------------------------------------
$implBody = [regex]::Match($componentText, '(?s)function Invoke-PFContainerCommand \{.*').Value
$zeroIdx    = $implBody.IndexOf('$containers.Count -eq 0')
$recheckIdx = $implBody.IndexOf('$recheck = Get-ContainerEngineInfo')
# The claim is scoped to the STORE, not the host. A podman machine exposes a rootless and a
# rootful store holding different containers, so "no containers on this host" was itself a
# confident wrong answer — measured on a real machine with 9 in one store and 5 in the other.
$claimIdx   = $implBody.IndexOf('No containers in the active')
$hintIdx    = $implBody.IndexOf('Show-ContainerStoreHint')
Assert-True ($zeroIdx -ge 0) 'could not find the zero-container branch'
Assert-True ($recheckIdx -gt $zeroIdx) 'the zero-container branch must re-probe engine health'
Assert-True ($claimIdx -gt $recheckIdx) `
    'the empty-store claim must come AFTER the health re-probe, never before it'
Assert-True ($hintIdx -gt $recheckIdx) `
    'an empty active store must check the OTHER stores before the user is left thinking they have nothing'
Assert-True ($implBody -notmatch 'No containers on this host') `
    'the claim must be about the active store, not the host - the host may have containers in another store'
$assertions += 5

# The bare table must also mention other stores: an accurate table can still mislead.
$bareIdx = $implBody.IndexOf('Show-ContainerTable -Containers $containers')
Assert-True ($bareIdx -ge 0) 'could not find the bare-table render'
Assert-True (@([regex]::Matches($implBody, 'Show-ContainerStoreHint')).Count -ge 2) `
    'the store hint should fire both on an empty store AND alongside a populated table'
$assertions += 2

# The version probe must gate on the exit code, not on stdout being non-empty — podman
# populates stdout on the failure path by design.
foreach ($platform in @('linux', 'windows')) {
    $adapterText = Get-Content -LiteralPath (Get-ContainerAdapterPath $platform) -Raw
    Assert-True ($adapterText -match 'if \(\$LASTEXITCODE -eq 0\) \{ \$version =') `
        "$platform : the version probe must gate on the exit code"
    Assert-True ($adapterText -notmatch "version --format '\{\{\.Server\.Version\}\}' 2>\`$null \| Select-Object") `
        "$platform : the version probe must not pipe - Select-Object -First 1 discards `$LASTEXITCODE"
    $assertions += 2
}

Write-Host "  containers hardening: $assertions assertions total" -ForegroundColor Green

# ---------------------------------------------------------------------------------
# CONTAINER STORES — the "two toy boxes" problem
#
# A podman machine exposes TWO stores, a rootless one and a rootful one, holding DIFFERENT
# containers; only one is the default and a plain `podman ps` sees only that one. Measured on
# a real host with two machines and therefore four stores: the active store held 9 containers
# while 5 more sat in the rootless store one connection away. So `pman` could truthfully report
# an empty store and leave the user thinking their containers were gone.
#
# The fix must NOT be "tell the user to switch". Naming a connection is read-only
# (`podman --connection <name> ps`), so every store can be inspected without changing which is
# default — that is what makes this answerable rather than a setting to flip.
# ---------------------------------------------------------------------------------
$adapterText = Get-Content -LiteralPath (Get-ContainerAdapterPath 'linux') -Raw
$adapterCode = @($adapterText -split "`r?`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"

# Reading another store must be read-only: no `machine set`, no context switching.
Assert-True ($adapterCode -notmatch 'machine\s+set') `
    'the adapter must never change which store is default - that is the user''s decision'
Assert-True ($adapterCode -notmatch "'context'\s*,\s*'use'") `
    'the adapter must not switch docker contexts either'
$assertions += 2

# It must select a store by NAMING it, which is the read-only route.
Assert-True ($adapterCode -match "'--connection'") 'podman stores must be read via --connection'
Assert-True ($adapterCode -match "'--context'") 'docker contexts must be read via --context'
$assertions += 2

# Rootful-ness comes from the URI, not the name: the name is only a convention.
Assert-True ($adapterCode -match "IsRootful\s*=\s*\(\`$uri -match '://root@'\)") `
    'rootful must be detected from the connection URI, not a name suffix which can be anything'
$assertions++

# An unreachable store must be distinguishable from an empty one.
Assert-True ($adapterCode -match 'return -1') `
    'Get-ContainerStoreCount must signal "could not read" separately from "zero containers"'
$storeFn = [regex]::Match($adapterText, '(?ms)^function Get-ContainerStoreCount \{.*?^\}').Value
Assert-True ($storeFn -match 'LASTEXITCODE -ne 0') 'an unreachable store must be detected by exit code'
$assertions += 2

# The component must render "unreachable" rather than "none" for that case.
Assert-True ($componentText -match "unreachable") `
    'the stores table must be able to say unreachable - reporting 0 would be a confident wrong answer'
$assertions++

# Both entry points expose the verb, and it is registered for pwsh-h.
foreach ($command in @('dkr', 'pman')) {
    $entry = $script:Registered | Where-Object { $_.Name -eq "$command stores" }
    Assert-True ($null -ne $entry) "'$command stores' is not registered for pwsh-h"
    $assertions++
}
Assert-True ($componentText -match "\`$verb -in @\('stores', 'store'\)") `
    'both the plural and singular spelling should route, since either is a reasonable guess'
$assertions++

Write-Host "  container stores: $assertions assertions total" -ForegroundColor Green

# ---------------------------------------------------------------------------------
# STORE INVENTORY — containers are the least of what a store owns
#
# Each store keeps its OWN images, volumes, networks and pods, none shared with the other.
# Measured on a real host: the rootless store held 5 containers / 15 images / 6 volumes /
# 3 networks / 2 pods, the rootful one 9 / 23 / 9 / 4 / 1 — and two volumes existed in BOTH.
# So "where did my volume go?" needs the same answer as "where did my container go?".
# ---------------------------------------------------------------------------------
Assert-True ($adapterCode -match '\$script:PF_ContainerResources') `
    'the resource list should be declared once, not repeated per call site'

# Every resource must declare which engines have it, so a docker-only gap is explicit.
foreach ($resource in @('containers', 'images', 'volumes', 'networks', 'pods')) {
    Assert-True ($adapterCode -match "(?m)^\s*$resource\s*=\s*@\{") "the resource '$resource' is not declared"
    $assertions++
}

# PODS ARE PODMAN-ONLY. Reporting 0 for docker would imply docker has pods and you have none.
$podLine = [regex]::Match($adapterCode, '(?m)^\s*pods\s*=\s*@\{.*$').Value
Assert-True ($podLine -match "Engines\s*=\s*@\('podman'\)") `
    'pods must be declared podman-only, so the docker column is omitted rather than shown as 0'
Assert-True ($componentText -match 'docker has no pods') `
    'the drill-down must distinguish "docker has no pods" from "unreachable"'
$assertions += 2

# Unreachable must short-circuit: a stopped machine should not cost one timeout per resource.
$invFn = [regex]::Match($adapterText, '(?ms)^function Get-ContainerStoreInventory \{.*?^\}').Value
Assert-True ($invFn -match 'Reachable\s*=\s*\$false') 'the inventory must report reachability explicitly'
Assert-True ($invFn -match 'do not pay a timeout|Do not pay a timeout') `
    'an unreachable store should skip the remaining resource queries'
$assertions += 2

# Three distinct outcomes must stay distinguishable: n/a, unreachable, and genuinely empty.
Assert-True ($componentText -match "'n/a'") 'a resource the engine lacks must render as n/a, not 0'
Assert-True ($componentText -match 'unreachable') 'an unreadable store must render as unreachable, not 0'
Assert-True ($componentText -match "'none'|      none") 'a genuinely empty resource must render as none'
$assertions += 3

# The drill-down is a WORD, not a flag — the same rule as `storage <volume>`.
#
# NOTE FOR FUTURE ASSERTIONS: any "this string must NOT appear" check has to scan the
# COMMENT-STRIPPED source. This codebase documents its decisions by quoting the rejected form
# verbatim ("`pman stores volumes`, not `pman stores --volumes`"), so scanning raw text makes the
# explanation of a rule look like a violation of it. That has now caught three tests of mine.
Assert-True ($componentText -match "Show-ContainerStoreResource -Engine \`$engine -Resource \`$names\[0\]") `
    'stores <resource> must take the resource as a positional word, not a flag'
Assert-True ($code -notmatch '--volumes|--images|--networks') `
    'resources must not become flags - refinement is a word'
$assertions += 2

Write-Host "  store inventory: $assertions assertions total" -ForegroundColor Green
