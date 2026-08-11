# ==============================================================================
# PowerFlow — Container Engine Adapter (Linux)
# ==============================================================================
# Domain   : Platform / Linux
# File     : platform/linux/adapters/container.ps1
# Purpose  : Every docker/podman invocation for `dkr` and `pman`. Components render only.
# Contract : Get-ContainerEngineNames, Get-ContainerEngineInfo, Get-ContainerList,
#            Invoke-ContainerLifecycle, Get-ContainerLogCommand, Get-ContainerShellCommand,
#            Invoke-ContainerInteractive, Get-ContainerComposeProjects,
#            Invoke-ContainerCompose, Get-ContainerEngineIdentity,
#            Get-ContainerEngineConnections, Get-ContainerStoreCount,
#            Get-ContainerResourceNames, Get-ContainerStoreResource,
#            Get-ContainerStoreInventory, Get-ContainerMachines,
#            Resolve-ContainerConnectionMachine
# Depends  : none
# ==============================================================================
#
# WHY ONE ADAPTER SERVES BOTH ENGINES
#
# Podman is a deliberate drop-in for the docker CLI, and this was MEASURED rather than
# assumed — probed against podman 6.0.2 and Docker Desktop on the same host. The whole
# go-template surface renders byte-identically:
#
#   {{.Names}} {{.ID}} {{.Labels}} {{.Ports}} {{.Status}} {{.State}}
#
# So there is one body, parameterised by an engine descriptor. Only four things differ
# per engine: the binary name, the elevation policy, whether compose output carries
# noise, and what "not usable" means.
#
# WHY NOT `--format '{{json .}}'`
#
# That is the one place the two engines genuinely diverge, and it would have broken
# silently. Measured on podman 6.0.2 versus docker:
#
#   field    docker                       podman
#   id       "ID"                         "Id"            <- different KEY
#   Names    "web"           (string)     ["web"]         (array)
#   Labels   "a=b,c=d"       (string)     {"a":"b"}       (object)
#   Ports    "0.0.0.0:80->80/tcp"         [{host_port:80,…}]  (array of objects)
#
# The explicit tab-delimited template below sidesteps all four, and is better anyway:
# it states exactly which fields are consumed instead of parsing whatever arrives.
#
# LABELS ARE LAST IN THE TEMPLATE, DELIBERATELY
#
# A label VALUE is arbitrary user text and may contain a tab. Splitting with a cap of 7
# lets the final field absorb any stray tabs instead of shifting every later column —
# the same off-by-one class as the storage gutter bug, arriving through data instead of
# formatting.
# ==============================================================================

# Field order is load-bearing: it must match the split in Get-ContainerList, and Labels
# must stay last.
# \t, NOT `t. PowerShell does not expand escapes inside single quotes, so a backtick-t
# reaches the engine as a literal backtick followed by 't' — measured against BOTH engines:
# zero real tabs emitted, and the parser below would then skip every container. A
# backslash-t passes through untouched and is expanded by the engine's own Go template
# layer, which is the form docker's own documentation uses. Verified byte-identical on
# docker and podman 6.0.2.
$script:PF_ContainerTemplate =
    '{{.Names}}\t{{.ID}}\t{{.Image}}\t{{.Status}}\t{{.State}}\t{{.Ports}}\t{{.Labels}}'

# Engines in preference order. `dkr` and `pman` each name one explicitly, so this exists
# only to answer "what else is on this box?" when the requested engine is missing.
function Get-ContainerEngineNames { return @('docker', 'podman') }

<#
.SYNOPSIS
    Resolve an engine name to a usable descriptor, or explain why it is not usable.
.DESCRIPTION
    Four states, because each needs different advice:
      missing      the CLI is not installed
      unreachable  CLI present, engine not responding (dockerd down / podman machine off)
      needs-sudo   DOCKER ONLY — the socket is not readable by this user
      ready        usable as-is

    `needs-sudo` is deliberately unreachable for podman. Podman is rootless by design and
    `sudo podman ps` queries ROOT'S SEPARATE CONTAINER STORE — a different set of
    containers, not the same ones with more rights. Retrying under sudo the way the docker
    path does would show the wrong containers and report success, which is worse than
    failing. So podman never elevates here.
#>
function Get-ContainerEngineInfo {
    param([Parameter(Mandatory)][ValidateSet('docker', 'podman')][string]$Engine)

    $descriptor = [pscustomobject]@{
        Name = $Engine; Binary = $Engine; State = 'missing'; Version = ''
        NeedsSudo = $false; Compose = ''; ComposeNoisy = $false; Error = ''
        ServedBy = ''; Mismatched = $false
    }

    if (-not (Get-Command $Engine -CommandType Application -ErrorAction SilentlyContinue)) {
        $descriptor.Error = "the $Engine CLI is not installed"
        return $descriptor
    }

    # $LASTEXITCODE is read IMMEDIATELY, before any pipeline, and BOTH halves of that matter:
    #
    #   1. Podman prints its CLIENT version to stdout even when the server is unreachable,
    #      then exits 125. Measured: `podman --url tcp://127.0.0.1:1 version
    #      --format '{{.Server.Version}}'` emits "6.0.2" and exits 125. Trusting stdout alone
    #      reports state=ready for a stopped machine, and every later call then fails for no
    #      visible reason.
    #   2. `| Select-Object -First 1` SHORT-CIRCUITS the pipeline and leaves $LASTEXITCODE at
    #      0. Measured on the same command: piped -> 0, unpiped -> 125. So piping here would
    #      throw away the only reliable failure signal.
    $version = ''
    try {
        $probeOut = & $Engine version --format '{{.Server.Version}}' 2>$null
        if ($LASTEXITCODE -eq 0) { $version = "$(@($probeOut)[0])".Trim() }
    } catch { }

    if (-not $version) {
        $probe = (& $Engine version --format '{{.Server.Version}}' 2>&1 | Out-String)

        # Only docker has a shared socket whose permissions can be the problem. Podman
        # rootless talks to its own user-owned service, so a failure here is the service
        # being down, never a permission question.
        if ($Engine -eq 'docker' -and $probe -match 'permission denied|dial unix') {
            if (Get-Command sudo -CommandType Application -ErrorAction SilentlyContinue) {
                # Same rule as above: exit code before any pipeline.
                try {
                    $sudoOut = & sudo -n docker version --format '{{.Server.Version}}' 2>$null
                    if ($LASTEXITCODE -eq 0) { $version = "$(@($sudoOut)[0])".Trim() }
                } catch { }
            }
            if ($version) { $descriptor.NeedsSudo = $true }
            else {
                $descriptor.State = 'needs-sudo'
                $descriptor.Error = 'the docker socket is not readable by this user'
                return $descriptor
            }
        }
        else {
            $descriptor.State = 'unreachable'
            $descriptor.Error = if ($Engine -eq 'podman') {
                'the podman service is not responding'
            } else {
                'the docker daemon is not responding'
            }
            return $descriptor
        }
    }

    $descriptor.State   = 'ready'
    $descriptor.Version = "$version".Trim()

    # Which engine ACTUALLY answered. On a host where podman owns the docker pipe, asking
    # the docker CLI gets you podman — so this is recorded rather than assumed, and the
    # component surfaces it instead of silently mislabelling the engine.
    $descriptor.ServedBy   = Get-ContainerEngineIdentity -Binary $descriptor.Binary
    $descriptor.Mismatched = ([bool]$descriptor.ServedBy -and $descriptor.ServedBy -ne $Engine)

    # Compose v2 is a CLI plugin; v1 is a separate binary. Podman may delegate to either,
    # and when it delegates it prints a provider banner that has to be stripped.
    try { if ((& $Engine compose version 2>$null)) { $descriptor.Compose = 'plugin' } } catch { }
    if (-not $descriptor.Compose) {
        foreach ($standalone in @("$Engine-compose", 'docker-compose')) {
            if (Get-Command $standalone -CommandType Application -ErrorAction SilentlyContinue) {
                $descriptor.Compose = 'standalone'; break
            }
        }
    }
    if ($Engine -eq 'podman') { $descriptor.ComposeNoisy = $true }

    return $descriptor
}

<#
.SYNOPSIS
    Which engine actually answered, regardless of which CLI was used to ask.
.DESCRIPTION
    THIS IS NOT PARANOIA — it was measured on the author's own machine. Podman on Windows
    can register its API on the standard docker pipe (npipe:////./pipe/docker_engine), so
    the `docker` CLI's default context resolves to PODMAN. `docker version` then reports
    Server 6.0.2 on platform "linux/amd64/fedora-44" — a version Docker has never shipped
    and an OS it does not run on.

    Without this check, `dkr` would print "docker 6.0.2" and act on podman's containers
    while claiming to be docker. That is precisely the confusion two commands exist to
    prevent.

    The signal is the engine's own first component name, which the docker CLI faithfully
    reports from whatever is on the other end:

        docker version --format '{{(index .Server.Components 0).Name}}'
          real Docker  -> "Engine"
          podman       -> "Podman Engine"

    The podman CLI does not expose .Server.Components at all (it errors), so the query is
    only meaningful for the docker CLI — which is exactly where the ambiguity lives.
#>
function Get-ContainerEngineIdentity {
    param([Parameter(Mandatory)][string]$Binary)

    if ($Binary -ne 'docker') { return $Binary }
    try {
        $raw = & docker version --format '{{(index .Server.Components 0).Name}}' 2>$null
        if ($LASTEXITCODE -ne 0) { return '' }
        $component = "$(@($raw)[0])"
    } catch { return '' }

    $text = "$component".Trim()
    if (-not $text) { return '' }
    if ($text -match 'podman') { return 'podman' }
    return 'docker'
}
# Every engine call goes through here, so elevation is decided in exactly one place.
function Invoke-PFContainerEngine {
    param(
        [Parameter(Mandatory)]$Engine,
        [Parameter(Mandatory)][string[]]$EngineArgs
    )
    if ($Engine.NeedsSudo) { return (& sudo $Engine.Binary @EngineArgs 2>&1) }
    return (& $Engine.Binary @EngineArgs 2>&1)
}

# Podman prints an ANSI-wrapped provider banner before compose output when it delegates:
#   ESC[4m>>>> Executing external compose provider "docker-compose" … <<<<  ESC[0m[]
# Left in place it makes the JSON unparseable, and the failure is SILENT — the leading
# byte simply is not '[' any more, so a naive guard returns "no projects" for a host full
# of them.
function Clear-PFComposeNoise {
    param([string[]]$Lines)
    $clean = @()
    foreach ($line in $Lines) {
        $text = ("$line" -replace "`e\[[0-9;]*[A-Za-z]", '').Trim()
        if (-not $text) { continue }
        if ($text -match '^>+\s*Executing external compose provider') { continue }
        if ($text -match 'Please see podman-compose\(1\)') { continue }
        $clean += $text
    }
    return $clean
}

<#
.SYNOPSIS
    Every container, with its compose project and service when it has one.
.DESCRIPTION
    The compose labels are what let a container be acted on compose-correctly from ANY
    directory, which is compose's biggest friction otherwise.
#>
function Get-ContainerList {
    param([Parameter(Mandatory)]$Engine, [switch]$All)

    $engineArgs = @('ps', '--no-trunc', '--format', $script:PF_ContainerTemplate)
    if ($All) { $engineArgs += '--all' }
    $raw = @(Invoke-PFContainerEngine -Engine $Engine -EngineArgs $engineArgs)

    $out = @()
    foreach ($line in $raw) {
        # Strip ONLY the line ending, never trailing whitespace. A container with no labels
        # produces a line whose LAST field is empty, so it ends in a tab — and TrimEnd()
        # would eat that tab, leaving six fields instead of seven and silently DROPPING the
        # container. Every plain `run` container without compose labels would vanish from
        # the table, which is invisible until someone has one.
        $text = "$line" -replace '[\r\n]+$', ''
        if (-not $text -or $text -notmatch "`t") { continue }

        # Cap at 7 so a tab inside a label value cannot shift the other columns.
        $parts = $text -split "`t", 7
        if ($parts.Count -lt 7) { continue }

        $labels = @{}
        foreach ($pair in ($parts[6] -split ',')) {
            $eq = $pair.IndexOf('=')
            if ($eq -gt 0) { $labels[$pair.Substring(0, $eq).Trim()] = $pair.Substring($eq + 1) }
        }

        $out += [pscustomobject]@{
            Name       = $parts[0]
            Id         = $parts[1].Substring(0, [Math]::Min(12, $parts[1].Length))
            Image      = $parts[2]
            Status     = $parts[3]
            State      = $parts[4]
            Ports      = $parts[5]
            Project    = "$($labels['com.docker.compose.project'])"
            Service    = "$($labels['com.docker.compose.service'])"
            WorkingDir = "$($labels['com.docker.compose.project.working_dir'])"
            ConfigFile = "$($labels['com.docker.compose.project.config_files'])"
            Engine     = $Engine.Name
        }
    }
    return @($out)
}

<#
.SYNOPSIS
    start / stop / restart, compose-correct when the container belongs to a project.
.DESCRIPTION
    Plain `restart` on a compose-managed container restarts the CONTAINER but ignores a
    changed compose file — the classic "I edited the yml and nothing happened".
#>
function Invoke-ContainerLifecycle {
    param(
        [Parameter(Mandatory)]$Engine,
        [Parameter(Mandatory)][ValidateSet('start', 'stop', 'restart')][string]$Action,
        [Parameter(Mandatory)][object[]]$Containers,
        [switch]$WhatIf
    )

    $results = @()
    $grouped = @($Containers | Group-Object -Property { "$($_.Project)|$($_.ConfigFile)" })
    foreach ($group in $grouped) {
        $first = $group.Group[0]
        $names = @($group.Group | ForEach-Object { $_.Name })
        if ($first.Project -and $first.ConfigFile) {
            $services = @($group.Group | ForEach-Object { $_.Service } | Where-Object { $_ })
            $engineArgs = @('compose', '-f', $first.ConfigFile, '-p', $first.Project, $Action) + $services
        }
        else {
            $engineArgs = @($Action) + $names
        }
        $native = "$($Engine.Binary) " + ($engineArgs -join ' ')
        if ($WhatIf) {
            $results += [pscustomobject]@{ Success = $true; Names = $names; Native = $native; Output = @(); WhatIf = $true }
            continue
        }
        $output = @(Invoke-PFContainerEngine -Engine $Engine -EngineArgs $engineArgs)
        if ($Engine.ComposeNoisy) { $output = @(Clear-PFComposeNoise -Lines $output) }
        $results += [pscustomobject]@{ Success = ($LASTEXITCODE -eq 0); Names = $names
            Native = $native; Output = @($output); WhatIf = $false }
    }
    return @($results)
}

# Returned rather than run: logs and shells are INTERACTIVE and must inherit the real
# terminal. Capturing them would break --follow and TTY allocation.
function Get-ContainerLogCommand {
    param([Parameter(Mandatory)]$Engine, [Parameter(Mandatory)]$Container,
          [int]$Tail = 200, [switch]$Follow)

    if ($Container.Project -and $Container.ConfigFile) {
        $engineArgs = @('compose', '-f', $Container.ConfigFile, '-p', $Container.Project, 'logs', '--tail', "$Tail")
        if ($Follow) { $engineArgs += '--follow' }
        if ($Container.Service) { $engineArgs += $Container.Service }
    }
    else {
        $engineArgs = @('logs', '--tail', "$Tail")
        if ($Follow) { $engineArgs += '--follow' }
        $engineArgs += $Container.Name
    }
    return [pscustomobject]@{
        File = $(if ($Engine.NeedsSudo) { 'sudo' } else { $Engine.Binary })
        Arguments = $(if ($Engine.NeedsSudo) { @($Engine.Binary) + $engineArgs } else { $engineArgs })
        Native = "$($Engine.Binary) " + ($engineArgs -join ' ')
    }
}

# `exec -it <c> bash` fails on Alpine-based images, which is most of the self-hosting
# ecosystem; `sh` works nearly everywhere. Probed rather than assumed, so nobody has to
# remember which image ships which shell.
function Get-ContainerShellCommand {
    param([Parameter(Mandatory)]$Engine, [Parameter(Mandatory)]$Container)

    $shell = 'sh'
    try {
        $found = @(Invoke-PFContainerEngine -Engine $Engine `
            -EngineArgs @('exec', $Container.Name, 'sh', '-c', 'command -v bash'))
        if ($LASTEXITCODE -eq 0 -and ($found -join '') -match '/bash') { $shell = 'bash' }
    } catch { }

    $engineArgs = @('exec', '-it', $Container.Name, $shell)
    return [pscustomobject]@{
        File = $(if ($Engine.NeedsSudo) { 'sudo' } else { $Engine.Binary })
        Arguments = $(if ($Engine.NeedsSudo) { @($Engine.Binary) + $engineArgs } else { $engineArgs })
        Shell = $shell; Native = "$($Engine.Binary) " + ($engineArgs -join ' ')
    }
}

# Kept in the adapter so no component ever invokes a native binary. Output is deliberately
# NOT captured — following logs and `exec -it` must inherit the real terminal.
function Invoke-ContainerInteractive {
    param([Parameter(Mandatory)]$Command)
    & $Command.File @($Command.Arguments)
}

<#
.SYNOPSIS
    Every compose project on the host, including ones with nothing running.
.DESCRIPTION
    `ps` cannot answer this: a stack that has been brought down has no containers and is
    invisible there. `compose ls --all` is the only primitive that pairs a project with
    the config file it was created from, which is what makes `up <stack>` work when
    nothing of that stack is running — the only time anyone types it.
#>
function Get-ContainerComposeProjects {
    param([Parameter(Mandatory)]$Engine)

    $raw = @(Invoke-PFContainerEngine -Engine $Engine `
        -EngineArgs @('compose', 'ls', '--all', '--format', 'json'))
    if ($Engine.ComposeNoisy) { $raw = @(Clear-PFComposeNoise -Lines $raw) }

    $text = ($raw -join '').Trim()
    if (-not $text -or $text[0] -ne '[') { return @() }
    try { $rows = $text | ConvertFrom-Json } catch { return @() }

    $out = @()
    foreach ($row in @($rows)) {
        # ConfigFiles is comma-separated when a project was created with several -f files;
        # the first is the one to address it by.
        $config = "$($row.ConfigFiles)".Split(',')[0].Trim()
        $out += [pscustomobject]@{ Name = "$($row.Name)"; Status = "$($row.Status)"; ConfigFile = $config }
    }
    return @($out)
}

<#
.SYNOPSIS
    Bring a compose project up or down.
.DESCRIPTION
    `up` is always `-d`: an attached compose session inside a profile function would hold
    the terminal and die with it. `down` is NEVER given -v. Verified against Compose
    v5.3.1: plain `down` removes containers and networks but leaves named volumes alone,
    and -v is what deletes them — so the destructive flag is not reachable from here.
#>
function Invoke-ContainerCompose {
    param(
        [Parameter(Mandatory)]$Engine,
        [Parameter(Mandatory)][ValidateSet('up', 'down')][string]$Action,
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$ConfigFile,
        [string[]]$Services = @(),
        [switch]$WhatIf
    )

    $engineArgs = @('compose', '-f', $ConfigFile, '-p', $Project, $Action)
    if ($Action -eq 'up') { $engineArgs += '-d' }
    if ($Services.Count) { $engineArgs += $Services }

    $native = "$($Engine.Binary) " + ($engineArgs -join ' ')
    if ($WhatIf) {
        return [pscustomobject]@{ Success = $true; Native = $native; Output = @(); WhatIf = $true }
    }
    $output = @(Invoke-PFContainerEngine -Engine $Engine -EngineArgs $engineArgs)
    if ($Engine.ComposeNoisy) { $output = @(Clear-PFComposeNoise -Lines $output) }
    return [pscustomobject]@{ Success = ($LASTEXITCODE -eq 0); Native = $native
        Output = @($output); WhatIf = $false }
}

# ==============================================================================
# CONTAINER STORES — the "two toy boxes" problem
# ==============================================================================
# A podman machine exposes TWO stores, not one: a rootless store owned by your user and a
# rootful store owned by root. They hold DIFFERENT containers. Exactly one connection is the
# default, and every plain `podman ps` looks only at that one. Podman Desktop has the same
# limitation — it can show one or the other, never both at once.
#
# Measured on the author's machine, which has two machines and therefore FOUR stores:
#
#   podman-machine-default        rootless   belief-index-dev/prod  (5 containers)
#   podman-machine-default-root   rootful    the Hutano docker-* stack   <- was the default
#   zavoya-build / -root          second machine on another drive, not running
#
# So `pman` could truthfully report "no containers on this host" while five of them sat one
# connection away. That is the same confident-wrong-answer defect as PF-BUG-004, arriving
# through a different door.
#
# THE FIX IS NOT TO MAKE THE USER SWITCH.
#
# `podman machine set --rootful=true|false` changes the default, and that is a real thing a
# user may want — but it is the wrong answer to "where are my containers?". Every store can be
# read WITHOUT changing anything, by naming the connection explicitly:
#
#   podman --connection <name> ps
#
# That is read-only and leaves the default untouched, so PowerFlow can simply look in all of
# them and say where things are. Nobody has to remember a flag or move a camera.
#
# Docker has the same concept under a different name — contexts — so this is one contract.
# ==============================================================================

<#
.SYNOPSIS
    Every store this engine can see, and which one is currently the default.
.DESCRIPTION
    Rootful-ness is read from the connection URI (ssh://root@ versus ssh://user@) rather than
    the name suffix, because the name is only a convention and can be anything.

    A store that cannot be reached is reported as unreachable, NOT as empty. An unreachable
    machine and a machine with no containers are different facts, and collapsing them is how a
    tool ends up confidently telling you that you have nothing.
#>
function Get-ContainerEngineConnections {
    param([Parameter(Mandatory)]$Engine)

    if ($Engine.Name -eq 'podman') {
        $raw = @(Invoke-PFContainerEngine -Engine $Engine `
            -EngineArgs @('system', 'connection', 'ls', '--format', 'json'))
        $text = ($raw -join '').Trim()
        if (-not $text -or $text[0] -ne '[') { return @() }
        try { $rows = $text | ConvertFrom-Json } catch { return @() }

        return @($rows | ForEach-Object {
            $uri = "$($_.URI)"
            [pscustomobject]@{
                Name      = "$($_.Name)"
                Uri       = $uri
                IsDefault = [bool]$_.Default
                IsRootful = ($uri -match '://root@')
                Engine    = 'podman'
            }
        })
    }

    # Docker calls them contexts. `--format json` emits one object per line, not an array.
    $raw = @(Invoke-PFContainerEngine -Engine $Engine -EngineArgs @('context', 'ls', '--format', 'json'))
    $out = @()
    foreach ($line in $raw) {
        $text = "$line".Trim()
        if (-not $text -or $text[0] -ne '{') { continue }
        try { $row = $text | ConvertFrom-Json } catch { continue }
        $out += [pscustomobject]@{
            Name      = "$($row.Name)"
            Uri       = "$($row.DockerEndpoint)"
            IsDefault = [bool]$row.Current
            IsRootful = $false          # docker has no rootless/rootful split of this kind
            Engine    = 'docker'
        }
    }
    return @($out)
}

<#
.SYNOPSIS
    Count the containers in a store WITHOUT making it the default.
.DESCRIPTION
    Naming the connection is read-only, which is the whole point: the question "where are my
    containers?" must never require changing which store you are pointed at.

    Returns -1 for an unreachable store so the caller can distinguish "nothing here" from
    "could not look", and say so.
#>
function Get-ContainerStoreCount {
    param([Parameter(Mandatory)]$Engine, [Parameter(Mandatory)][string]$Connection)

    $selector = if ($Engine.Name -eq 'podman') { @('--connection', $Connection) } else { @('--context', $Connection) }
    $raw = @(Invoke-PFContainerEngine -Engine $Engine -EngineArgs ($selector + @('ps', '--all', '--format', '{{.Names}}')))
    if ($LASTEXITCODE -ne 0) { return -1 }

    $names = @($raw | ForEach-Object { "$_".Trim() } | Where-Object { $_ -and $_ -notmatch 'Cannot connect|connection refused|no such host' })
    return $names.Count
}

# ==============================================================================
# STORE INVENTORY — everything a store owns, not just its containers
# ==============================================================================
# Containers are the least of it. Each store keeps its OWN images, volumes, networks and
# (podman only) pods, and none of them are shared with the other store. So "where did my
# volume go?" has the same answer as "where did my container go?", and needs the same view.
#
# There is no built-in combined rootful+rootless inventory in either CLI. It is assembled
# here by asking each connection in turn — read-only, because naming a connection never
# changes which one is default.
#
# PODS ARE PODMAN-ONLY. Docker has no equivalent, so the count is $null rather than 0 and the
# column is omitted for docker. Reporting 0 would imply docker has pods and you have none.
# ==============================================================================

# Resource -> the argument list that lists it, and whether both engines have it.
# --format is used so a count is a line count rather than a parse of a decorated table.
$script:PF_ContainerResources = [ordered]@{
    containers = @{ Args = @('ps', '--all', '--format', '{{.Names}}');  Engines = @('docker', 'podman') }
    images     = @{ Args = @('images', '--format', '{{.Repository}}:{{.Tag}}'); Engines = @('docker', 'podman') }
    volumes    = @{ Args = @('volume', 'ls', '--format', '{{.Name}}'); Engines = @('docker', 'podman') }
    networks   = @{ Args = @('network', 'ls', '--format', '{{.Name}}'); Engines = @('docker', 'podman') }
    pods       = @{ Args = @('pod', 'ls', '--format', '{{.Name}}');    Engines = @('podman') }
}

function Get-ContainerResourceNames { return @($script:PF_ContainerResources.Keys) }

<#
.SYNOPSIS
    List one resource in one store, without changing which store is default.
.DESCRIPTION
    Returns $null for a resource the engine does not have (pods on docker) and $null for an
    unreachable store, so the caller can distinguish "not applicable", "cannot look" and
    "genuinely empty" — three different facts that all render as an empty list otherwise.
#>
function Get-ContainerStoreResource {
    param(
        [Parameter(Mandatory)]$Engine,
        [Parameter(Mandatory)][string]$Connection,
        [Parameter(Mandatory)][string]$Resource
    )

    $spec = $script:PF_ContainerResources[$Resource]
    if (-not $spec) { return $null }
    if ($Engine.Name -notin $spec.Engines) { return $null }

    $selector = if ($Engine.Name -eq 'podman') { @('--connection', $Connection) } else { @('--context', $Connection) }
    $raw = @(Invoke-PFContainerEngine -Engine $Engine -EngineArgs ($selector + $spec.Args))
    if ($LASTEXITCODE -ne 0) { return $null }

    return @($raw |
        ForEach-Object { "$_".Trim() } |
        Where-Object { $_ -and $_ -notmatch 'Cannot connect|connection refused|no such host|is not running' })
}

<#
.SYNOPSIS
    Counts for every resource in one store, in a single pass.
.DESCRIPTION
    Reachability is probed once with the cheapest query, and the rest are skipped when it
    fails — a stopped machine otherwise costs one timeout per resource type.
#>
function Get-ContainerStoreInventory {
    param([Parameter(Mandatory)]$Engine, [Parameter(Mandatory)][string]$Connection)

    $inventory = [ordered]@{}
    $containers = Get-ContainerStoreResource -Engine $Engine -Connection $Connection -Resource 'containers'
    if ($null -eq $containers) {
        # Unreachable. Do not pay a timeout for each remaining resource to learn the same thing.
        foreach ($name in (Get-ContainerResourceNames)) { $inventory[$name] = $null }
        return [pscustomobject]@{ Connection = $Connection; Reachable = $false; Counts = $inventory }
    }

    $inventory['containers'] = $containers.Count
    foreach ($name in (Get-ContainerResourceNames)) {
        if ($name -eq 'containers') { continue }
        $rows = Get-ContainerStoreResource -Engine $Engine -Connection $Connection -Resource $name
        $inventory[$name] = if ($null -eq $rows) { $null } else { $rows.Count }
    }
    return [pscustomobject]@{ Connection = $Connection; Reachable = $true; Counts = $inventory }
}

# ==============================================================================
# MACHINES — the layer above stores
# ==============================================================================
# Three concepts, and conflating any two of them produces a misleading inventory:
#
#   MACHINE      a small Linux VM. Linux containers need Linux underneath them, so on
#                Windows and macOS podman runs one. It can be running or stopped.
#   STORE        what podman owns INSIDE a machine. Each machine has TWO — a rootless store
#                and a rootful store — holding different containers, images, volumes and pods.
#   CONNECTION   the address the CLI uses to reach one store of one machine. Not the machine,
#                not the store: the route to them.
#
# So two machines means FOUR stores, reached through four connections:
#
#   machine A ── rootless store ← connection A
#             └─ rootful  store ← connection A-root
#   machine B ── rootless store ← connection B
#             └─ rootful  store ← connection B-root
#
# WHY THIS LAYER MATTERS FOR THE INVENTORY
#
# Without it, a stopped machine's stores are reported as "unreachable" with no reason, which
# is honest but unhelpful — the user is told a fact and left to guess the cause. With it, the
# same store reads "machine stopped", and the fix is one named command away. That is the
# difference between not lying and actually helping.
#
# CONNECTIONS ARE MATCHED TO MACHINES BY PORT, NOT BY NAME.
#
# The obvious mapping is to strip a "-root" suffix off the connection name, and it would work
# today. But a connection name is a convention the user can change, while the SSH port in the
# connection URI and the Port in the machine record are the same fact reported twice. Matching
# on the fact rather than the convention is the same reasoning that makes rootful-ness come
# from the URI rather than the name suffix.
# ==============================================================================

<#
.SYNOPSIS
    Every podman machine, with whether it is actually running.
.DESCRIPTION
    Returns an empty list for docker: Docker Desktop is a single implicit VM with no
    user-visible machine layer, so there is nothing to group by and nothing to start.
#>
function Get-ContainerMachines {
    param([Parameter(Mandatory)]$Engine)

    if ($Engine.Name -ne 'podman') { return @() }

    $raw = @(Invoke-PFContainerEngine -Engine $Engine -EngineArgs @('machine', 'ls', '--format', 'json'))
    $text = ($raw -join '').Trim()
    if (-not $text -or $text[0] -ne '[') { return @() }
    try { $rows = $text | ConvertFrom-Json } catch { return @() }

    return @($rows | ForEach-Object {
        [pscustomobject]@{
            Name        = "$($_.Name)"
            Running     = [bool]$_.Running
            Starting    = [bool]$_.Starting
            VMType      = "$($_.VMType)"
            Cpus        = $_.CPUs
            MemoryBytes = [int64]("0" + "$($_.Memory)")
            DiskBytes   = [int64]("0" + "$($_.DiskSize)")
            Port        = $_.Port
        }
    })
}

<#
.SYNOPSIS
    Which machine a connection reaches, matched on the SSH port.
.DESCRIPTION
    The port appears in the connection URI (ssh://user@127.0.0.1:62206/...) and again as the
    machine's Port, so it is the same fact reported twice — unlike the name, which is a
    convention. Falls back to a name-prefix match only if no port is available.
#>
function Resolve-ContainerConnectionMachine {
    param([Parameter(Mandatory)]$Connection, [object[]]$Machines)

    if (-not $Machines -or -not $Machines.Count) { return $null }

    if ("$($Connection.Uri)" -match ':(\d+)/') {
        $port = [int]$Matches[1]
        $hit = @($Machines | Where-Object { [int]("0" + "$($_.Port)") -eq $port })
        if ($hit.Count) { return $hit[0] }
    }

    # Name fallback: strip the rootful suffix. Only reached when the URI carries no port.
    $stem = "$($Connection.Name)" -replace '-root$', ''
    $hit = @($Machines | Where-Object { $_.Name -ieq $stem })
    if ($hit.Count) { return $hit[0] }
    return $null
}