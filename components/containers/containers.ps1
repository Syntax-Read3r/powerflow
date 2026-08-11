# ==============================================================================
# PowerFlow — Containers (dkr · pman)
# ==============================================================================
# Domain   : Containers
# File     : components/containers/containers.ps1
# Purpose  : The daily container loop, for docker and podman alike.
# Depends  : platform adapters (container.ps1), help/registry.ps1
# ==============================================================================
#
# WHAT THIS IS FOR
#
# The command this replaces, typed several times a day:
#
#     sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
#     sudo docker stop qbittorrent radarr sonarr jellyfin
#
# `dkr` is that table. With fzf present it then lets you MARK containers with Tab and
# pick one action for all of them, so the second line becomes four keystrokes.
#
# TWO COMMANDS, ONE IMPLEMENTATION
#
#     dkr  ->  docker          pman  ->  podman
#
# Both are thin entry points into Invoke-PFContainerCommand. Podman is a deliberate
# drop-in for the docker CLI, so there is nothing to duplicate — the adapter takes an
# engine descriptor and everything below is engine-agnostic.
#
# The command NAME is the engine selector, which is why there is no `--engine` flag to
# remember. That is the same reasoning as `storage <volume>` being a word rather than
# `-D`: a refinement is a word, and flags are for modifiers only.
#
# WHY NOT ONE SWITCHABLE ALIAS
#
# Because it would make `dkr` mean different things on different machines, so help text,
# documentation and muscle memory would all become machine-dependent. Someone with docker
# at work and podman at home wants both names present, each meaning exactly one thing.
#
# NO param() BLOCK — DO NOT ADD ONE
#
# PowerShell would bind `-a` and `-f` as PARAMETER NAMES and reject everything else, and
# its prefix matching would make single letters ambiguous with every longer parameter
# sharing them. $args is hand-parsed instead.
# ==============================================================================

$script:ContainerActions = @('logs', 'restart', 'stop', 'start', 'shell')

# String.Format's {0,-N} is a MINIMUM width — it pads but never truncates, so one long
# value silently shoves every later column out of alignment. Truncate explicitly, and
# reserve the last character as a gutter: filling the full width makes a maximal value
# butt against the next column and the two read as one word.
function Format-ContainerCell {
    param([string]$Text, [int]$Width)
    $value = "$Text"
    $room  = $Width - 1
    if ($value.Length -gt $room) { $value = $value.Substring(0, $room - 1) + '.' }
    return $value.PadRight($Width)
}

# Ports arrive as "0.0.0.0:8080->80/tcp, :::8080->80/tcp" — the IPv6 half restates the
# same binding, and the container-internal port is rarely what you want.
function Format-ContainerPorts {
    param([string]$Ports)
    if (-not $Ports) { return '-' }
    $seen = [ordered]@{}
    foreach ($chunk in ($Ports -split ',')) {
        if ($chunk.Trim() -match '(?::|^)(\d+)->') { $seen[$Matches[1]] = $true }
    }
    if ($seen.Count -eq 0) { return '-' }
    return (($seen.Keys) -join ' ')
}

function Get-ContainerStateColour {
    param([string]$State)
    switch -Regex ($State) {
        'running'    { return 'Green' }
        'restarting' { return 'Yellow' }
        # podman emits `stopping` mid-shutdown; docker has no equivalent state.
        'stopping'   { return 'Yellow' }
        'paused'     { return 'Yellow' }
        default      { return 'DarkGray' }
    }
}

<#
.SYNOPSIS
    Print the container table, grouped by compose stack.
.DESCRIPTION
    Stopped containers are shown greyed rather than hidden: "it is not in the list" and
    "it is dead" look identical when the list holds only running containers, and the
    second is the one worth knowing about.
#>
function Show-ContainerTable {
    param([object[]]$Containers, [string]$Header)

    if (-not $Containers -or $Containers.Count -eq 0) {
        Write-Host 'No containers.' -ForegroundColor Yellow
        return
    }

    if ($Header) { Write-Host $Header -ForegroundColor DarkGray }
    Write-Host ''
    Write-Host ('  ' + (Format-ContainerCell 'NAME' 24) + (Format-ContainerCell 'STATUS' 26) + 'PORTS') -ForegroundColor DarkGray
    Write-Host ('  ' + ('-' * 66)) -ForegroundColor DarkGray

    foreach ($group in @($Containers | Group-Object -Property Project | Sort-Object Name)) {
        $label = if ($group.Name) { $group.Name } else { 'standalone' }
        Write-Host ''
        Write-Host "  > $label" -ForegroundColor Cyan
        foreach ($container in ($group.Group | Sort-Object Name)) {
            Write-Host ('    ' + (Format-ContainerCell $container.Name 22) +
                                 (Format-ContainerCell $container.Status 26) +
                                 (Format-ContainerPorts $container.Ports)) `
                       -ForegroundColor (Get-ContainerStateColour $container.State)
        }
    }
    Write-Host ''
}

<#
.SYNOPSIS
    Resolve user-typed names via compose labels as well as container names.
.DESCRIPTION
    Matching goes name -> service -> project -> substring, so `dkr restart sonarr` works
    whether the container is called sonarr, media-sonarr-1, or whatever compose invented.
#>
function Resolve-ContainerTargets {
    param([object[]]$Containers, [string[]]$Names)

    $matched = @(); $missing = @()
    foreach ($name in $Names) {
        $hit = @($Containers | Where-Object { $_.Name -ieq $name })
        if (-not $hit.Count) { $hit = @($Containers | Where-Object { $_.Service -ieq $name }) }
        if (-not $hit.Count) { $hit = @($Containers | Where-Object { $_.Project -ieq $name }) }
        if (-not $hit.Count) { $hit = @($Containers | Where-Object { $_.Name -ilike "*$name*" -or $_.Service -ilike "*$name*" }) }
        if ($hit.Count) { $matched += $hit } else { $missing += $name }
    }
    return [pscustomobject]@{ Matched = @($matched | Sort-Object Name -Unique); Missing = @($missing) }
}

function Show-ContainerMissing {
    param([string[]]$Missing, [object[]]$Containers)
    foreach ($name in $Missing) {
        Write-Host "[X] No container matching '$name'." -ForegroundColor Red
        $stem = $name.Substring(0, [Math]::Min(3, $name.Length))
        $near = @($Containers | Where-Object { $_.Name -match "^$([regex]::Escape($stem))" } |
                  Select-Object -First 4 -ExpandProperty Name)
        if ($near.Count) { Write-Host "    Did you mean: $($near -join ', ')" -ForegroundColor DarkGray }
    }
}

# One fzf invocation, --multi so Tab marks several at once. This is the whole reason the
# command exists: stopping four services should not be four names typed by hand.
function Select-ContainerTargets {
    param([object[]]$Containers, [string]$Prompt = 'Containers: ', [string]$Query = '')

    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) { return @() }

    $map = [ordered]@{}
    foreach ($container in ($Containers | Sort-Object Project, Name)) {
        $stack = if ($container.Project) { $container.Project } else { 'standalone' }
        $display = (Format-ContainerCell $container.Name 22) + (Format-ContainerCell $container.State 12) + $stack
        if (-not $map.Contains($display)) { $map[$display] = $container }
    }
    if ($map.Count -eq 0) { return @() }

    $picked = $map.Keys | fzf `
        --multi --query $Query --exit-0 --reverse --border=rounded --height=60% `
        --prompt=$Prompt `
        --header="PowerFlow  $($map.Count) containers - Tab to mark several, Enter to confirm, Esc to cancel"

    if (-not $picked) { return @() }
    return @($picked | ForEach-Object { $map[$_] })
}

function Select-ContainerAction {
    param([int]$Count)
    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) { return '' }
    $noun = if ($Count -eq 1) { 'container' } else { "$Count containers" }
    $choice = $script:ContainerActions | fzf `
        --reverse --border=rounded --height=40% --prompt='Action: ' `
        --header="Apply to $noun - Enter to run, Esc to cancel"
    return "$choice".Trim()
}

function Show-ContainerNative {
    param([string]$Command)
    Write-Host "  $Command" -ForegroundColor DarkGray
}

<#
.SYNOPSIS
    Every store this engine can see, with how many containers each holds.
.DESCRIPTION
    A podman machine exposes TWO stores — a rootless one owned by your user and a rootful one
    owned by root — and they hold DIFFERENT containers. Only one is the default, and a plain
    `podman ps` sees only that one. Docker has the same idea as contexts.
#>
function Get-ContainerStoreKind {
    param([Parameter(Mandatory)]$Engine, [Parameter(Mandatory)]$Connection)
    if ($Engine.Name -ne 'podman') { return 'context' }
    if ($Connection.IsRootful) { return 'rootful' }
    return 'rootless'
}

<#
.SYNOPSIS
    Every store, and everything each one owns.
.DESCRIPTION
    Containers are the least of it: each store keeps its OWN images, volumes, networks and
    pods, none of them shared. So "where did my volume go?" needs the same answer as "where
    did my container go?", and gets it here.

    One screen instead of a loop over `podman --connection <name> ps` for every resource, and
    read-only throughout — naming a connection never changes which one is default.
#>
function Show-ContainerStores {
    param([Parameter(Mandatory)]$Engine)

    $connections = @(Get-ContainerEngineConnections -Engine $Engine)
    if (-not $connections.Count) {
        Write-Host "No separate stores reported by $($Engine.Name)." -ForegroundColor Yellow
        return
    }

    # Pods are podman-only, so the column is omitted entirely for docker rather than printed
    # as zero — a 0 would imply docker has pods and you happen to have none.
    $resources = @(Get-ContainerResourceNames | Where-Object {
        $_ -ne 'pods' -or $Engine.Name -eq 'podman' })

    # Machines are the layer ABOVE stores: a machine is a small Linux VM, and each one holds a
    # rootless and a rootful store. Grouping by machine is what turns a bare "unreachable" into
    # "that machine is stopped", which is the difference between not lying and actually helping.
    $machines = @(Get-ContainerMachines -Engine $Engine)

    Write-Host ''
    Write-Host "$($Engine.Name) stores" -ForegroundColor Cyan

    $header = '   ' + (Format-ContainerCell 'STORE' 30) + (Format-ContainerCell 'KIND' 10)
    foreach ($resource in $resources) { $header += (Format-ContainerCell $resource.ToUpperInvariant() 12) }

    # Group connections under their machine. Docker has no machine layer, so everything falls
    # into one unnamed group and the output degrades to the flat table it was before.
    $groups = [ordered]@{}
    foreach ($connection in $connections) {
        $machine = Resolve-ContainerConnectionMachine -Connection $connection -Machines $machines
        $key = if ($machine) { $machine.Name } else { '' }
        if (-not $groups.Contains($key)) { $groups[$key] = [pscustomobject]@{ Machine = $machine; Connections = @() } }
        $groups[$key].Connections += $connection
    }

    foreach ($key in $groups.Keys) {
        $group = $groups[$key]
        $machine = $group.Machine

        Write-Host ''
        if ($machine) {
            $state = if ($machine.Starting) { 'starting' } elseif ($machine.Running) { 'running' } else { 'stopped' }
            $colour = if ($machine.Running) { 'Cyan' } else { 'Yellow' }
            $spec = "$($machine.VMType), $($machine.Cpus) cpu, $([Math]::Round($machine.MemoryBytes / 1GB, 1)) GB"
            Write-Host "  machine $($machine.Name)  [$state]  $spec" -ForegroundColor $colour
        }
        elseif ($key -eq '' -and $groups.Count -eq 1) {
            # Docker: no machine layer to report.
        }
        else {
            Write-Host '  (no machine matched)' -ForegroundColor DarkGray
        }

        Write-Host $header -ForegroundColor DarkGray
        Write-Host ('   ' + ('-' * ($header.Length - 3))) -ForegroundColor DarkGray

        foreach ($connection in $group.Connections) {
            $marker = if ($connection.IsDefault) { ' *' } else { '  ' }
            $line = $marker + (Format-ContainerCell $connection.Name 30) +
                              (Format-ContainerCell (Get-ContainerStoreKind -Engine $Engine -Connection $connection) 10)

            # A stopped machine cannot answer, so do not even ask — and say WHY rather than
            # leaving "unreachable" as a fact with no cause.
            if ($machine -and -not $machine.Running -and -not $machine.Starting) {
                Write-Host ($line + 'machine stopped') -ForegroundColor DarkGray
                continue
            }

            $inventory = Get-ContainerStoreInventory -Engine $Engine -Connection $connection.Name
            if (-not $inventory.Reachable) {
                # Unreachable is not empty. Saying 0 here is a confident wrong answer about
                # someone's data — the defect this whole command exists to prevent.
                Write-Host ($line + 'unreachable') -ForegroundColor DarkGray
                continue
            }
            foreach ($resource in $resources) {
                $count = $inventory.Counts[$resource]
                $line += (Format-ContainerCell $(if ($null -eq $count) { 'n/a' } else { "$count" }) 12)
            }
            Write-Host $line -ForegroundColor $(if ($connection.IsDefault) { 'Green' } else { 'White' })
        }
    }

    $command = if ($Engine.Name -eq 'podman') { 'pman' } else { 'dkr' }
    Write-Host ''
    Write-Host '   * the active store - the only one a bare command looks at' -ForegroundColor DarkGray
    Write-Host "   $command stores <$($resources -join '|')>   list one of them, per store" -ForegroundColor DarkGray

    # Name the fix for every stopped machine, rather than describing the problem.
    foreach ($machine in ($machines | Where-Object { -not $_.Running -and -not $_.Starting })) {
        Write-Host "   podman machine start $($machine.Name)   to reach its two stores" -ForegroundColor DarkGray
    }
    if ($Engine.Name -eq 'podman') {
        Write-Host '   podman machine set --rootful=true|false   change which store is active' -ForegroundColor DarkGray
        Write-Host '   Nothing is moved or deleted - only which store is the default changes.' -ForegroundColor DarkGray
    }
    Write-Host ''
}

<#
.SYNOPSIS
    List ONE resource across every store, grouped by store.
.DESCRIPTION
    The drill-down behind the count matrix. Answers "which store has that volume?" directly,
    which is the question the matrix only hints at.
#>
function Show-ContainerStoreResource {
    param([Parameter(Mandatory)]$Engine, [Parameter(Mandatory)][string]$Resource)

    $known = @(Get-ContainerResourceNames)
    if ($Resource -notin $known) {
        Write-Host "[X] Unknown resource '$Resource'." -ForegroundColor Red
        Write-Host "    Try: $($known -join ', ')" -ForegroundColor DarkGray
        return
    }

    $connections = @(Get-ContainerEngineConnections -Engine $Engine)
    if (-not $connections.Count) {
        Write-Host "No separate stores reported by $($Engine.Name)." -ForegroundColor Yellow
        return
    }

    Write-Host ''
    Write-Host "$($Engine.Name) $Resource, by store" -ForegroundColor Cyan

    foreach ($connection in $connections) {
        $kind = Get-ContainerStoreKind -Engine $Engine -Connection $connection
        $marker = if ($connection.IsDefault) { ' (active)' } else { '' }
        Write-Host ''
        Write-Host "  > $($connection.Name)  [$kind]$marker" -ForegroundColor Cyan

        $rows = Get-ContainerStoreResource -Engine $Engine -Connection $connection.Name -Resource $Resource
        if ($null -eq $rows) {
            # $null covers two different facts, and they must not read the same.
            if ($Engine.Name -eq 'docker' -and $Resource -eq 'pods') {
                Write-Host '      docker has no pods' -ForegroundColor DarkGray
            } else {
                Write-Host '      unreachable' -ForegroundColor DarkGray
            }
            continue
        }
        if (-not $rows.Count) { Write-Host '      none' -ForegroundColor DarkGray; continue }
        foreach ($row in ($rows | Sort-Object)) { Write-Host "      $row" }
    }
    Write-Host ''
}

<#
.SYNOPSIS
    If the active store looks empty, say where the containers actually are.
.DESCRIPTION
    This is the difference between "you have no containers" and "you are looking in the wrong
    box". Measured on a real machine: the active store held the Hutano stack while five Belief
    Index containers sat in the rootless store one connection away. Reporting "no containers on
    this host" there is true only of the store, and false of the host.
#>
function Show-ContainerStoreHint {
    param([Parameter(Mandatory)]$Engine, [int]$ActiveCount)

    $connections = @(Get-ContainerEngineConnections -Engine $Engine)
    if ($connections.Count -le 1) { return }

    $elsewhere = @()
    foreach ($connection in $connections) {
        if ($connection.IsDefault) { continue }
        $count = Get-ContainerStoreCount -Engine $Engine -Connection $connection.Name
        if ($count -gt 0) { $elsewhere += [pscustomobject]@{ Name = $connection.Name; Count = $count; Rootful = $connection.IsRootful } }
    }
    if (-not $elsewhere.Count) { return }

    $command = if ($Engine.Name -eq 'podman') { 'pman' } else { 'dkr' }
    Write-Host ''
    foreach ($store in $elsewhere) {
        $kind = if ($store.Rootful) { 'rootful' } else { 'rootless' }
        Write-Host "  $($store.Count) container(s) live in another store: $($store.Name) ($kind)" -ForegroundColor Yellow
    }
    Write-Host "  $command stores   to see them all" -ForegroundColor DarkGray
    if ($Engine.Name -eq 'podman') {
        $target = if ($elsewhere[0].Rootful) { 'true' } else { 'false' }
        Write-Host "  podman machine set --rootful=$target   to make that store the active one" -ForegroundColor DarkGray
    }
    Write-Host ''
}

function Invoke-ContainerLifecycleView {
    param(
        [Parameter(Mandatory)]$Engine,
        [Parameter(Mandatory)][ValidateSet('start', 'stop', 'restart')][string]$Action,
        [Parameter(Mandatory)][object[]]$Targets,
        [switch]$ShowNative
    )

    $verb = @{ start = 'Starting'; stop = 'Stopping'; restart = 'Restarting' }[$Action]
    $plural = if ($Targets.Count -ne 1) { 's' } else { '' }
    Write-Host "$verb $($Targets.Count) container$plural..." -ForegroundColor Cyan

    if ($ShowNative) {
        foreach ($plan in (Invoke-ContainerLifecycle -Engine $Engine -Action $Action -Containers $Targets -WhatIf)) {
            Show-ContainerNative $plan.Native
        }
    }

    foreach ($result in (Invoke-ContainerLifecycle -Engine $Engine -Action $Action -Containers $Targets)) {
        if ($result.Success) { Write-Host "  [OK] $($result.Names -join ', ')" -ForegroundColor Green }
        else {
            Write-Host "  [X] $($result.Names -join ', ')" -ForegroundColor Red
            foreach ($line in $result.Output) { Write-Host "      $line" -ForegroundColor DarkGray }
        }
    }
}

function Invoke-ContainerLogsView {
    param([Parameter(Mandatory)]$Engine, [Parameter(Mandatory)]$Container,
          [int]$Tail = 200, [switch]$Follow, [switch]$ShowNative)

    $command = Get-ContainerLogCommand -Engine $Engine -Container $Container -Tail $Tail -Follow:$Follow
    if ($ShowNative) { Show-ContainerNative $command.Native }
    $note = if ($Follow) { ', following (Ctrl-C to stop)' } else { '' }
    Write-Host "$($Container.Name) - last $Tail lines$note" -ForegroundColor Cyan
    Write-Host ''
    Invoke-ContainerInteractive -Command $command
}

function Invoke-ContainerShellView {
    param([Parameter(Mandatory)]$Engine, [Parameter(Mandatory)]$Container, [switch]$ShowNative)

    if ($Container.State -ne 'running') {
        Write-Host "[X] $($Container.Name) is not running ($($Container.State)) - cannot open a shell." -ForegroundColor Red
        Write-Host "    Start it first:  $($Engine.Name -replace 'docker', 'dkr' -replace 'podman', 'pman') start $($Container.Name)" -ForegroundColor DarkGray
        return
    }
    $command = Get-ContainerShellCommand -Engine $Engine -Container $Container
    if ($ShowNative) { Show-ContainerNative $command.Native }
    Write-Host "$($Container.Name) - $($command.Shell) (type exit to leave)" -ForegroundColor Cyan
    Invoke-ContainerInteractive -Command $command
}

<#
.SYNOPSIS
    Explain why an engine is not usable, and name the other one if it IS.
.DESCRIPTION
    Naming the alternative is the convenience that matters: on a box with only podman,
    `dkr` should say "use pman" rather than leaving the user to guess.
#>
function Show-ContainerEngineProblem {
    param([Parameter(Mandatory)]$Engine)

    Write-Host "[X] $($Engine.Error)." -ForegroundColor Red

    switch ($Engine.State) {
        'missing' {
            Write-Host "    $(Get-DependencyInstallHint $Engine.Name)" -ForegroundColor DarkGray
        }
        'unreachable' {
            if ($Engine.Name -eq 'podman') {
                Write-Host '    Start it:  podman machine start' -ForegroundColor DarkGray
            }
            else {
                Write-Host '    Start Docker Desktop, or on Linux:  sudo systemctl start docker' -ForegroundColor DarkGray
            }
        }
        'needs-sudo' {
            Write-Host '    Either run with sudo, or join the docker group:' -ForegroundColor DarkGray
            Write-Host '      sudo usermod -aG docker $USER && newgrp docker' -ForegroundColor DarkGray
            Write-Host '    Note: docker group membership is root-equivalent on this host.' -ForegroundColor DarkGray
        }
    }

    # The other engine may be sitting right there.
    foreach ($other in (Get-ContainerEngineNames)) {
        if ($other -eq $Engine.Name) { continue }
        $alt = Get-ContainerEngineInfo -Engine $other
        if ($alt.State -eq 'ready') {
            $command = if ($other -eq 'podman') { 'pman' } else { 'dkr' }
            Write-Host ''
            Write-Host "    $other $($alt.Version) IS running on this machine - try:  $command" -ForegroundColor Yellow
        }
    }
}

function Show-ContainerHelp {
    param([string]$Command, [string]$EngineName)
    Write-Host ''
    Write-Host "$Command - $EngineName, without the flags" -ForegroundColor Cyan
    Write-Host ''
    Write-Host "  $Command                     the table: every container, grouped by stack" -ForegroundColor White
    Write-Host '                          with fzf: Tab to mark several, then pick an action' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host "  $Command logs [name]         last 200 lines           (no name -> picker)" -ForegroundColor White
    Write-Host "  $Command logs <name> -f      ...and follow" -ForegroundColor White
    Write-Host "  $Command shell [name]        open a shell inside it   (bash if present, else sh)" -ForegroundColor White
    Write-Host "  $Command up [stack]          bring a compose stack up  (no name -> compose file here)" -ForegroundColor White
    Write-Host "  $Command down [stack]        take it down; asks first, keeps named volumes" -ForegroundColor White
    Write-Host "  $Command restart [names...]  compose-correct - picks up an edited compose file" -ForegroundColor White
    Write-Host "  $Command stop [names...]     stop" -ForegroundColor White
    Write-Host "  $Command start [names...]    start" -ForegroundColor White
    Write-Host ''
    Write-Host '  Names match the container, the compose service, or the stack - so' -ForegroundColor DarkGray
    Write-Host "  ``$Command restart sonarr`` works from any directory." -ForegroundColor DarkGray
    Write-Host ''
    Write-Host "  $command stores            every store, with what each one holds" -ForegroundColor White
    Write-Host "  $command stores volumes    or containers / images / networks / pods, per store" -ForegroundColor White
    Write-Host ''
    Write-Host '  --show-native           print the real command it runs' -ForegroundColor White
    Write-Host '  -a                      include stopped containers in pickers' -ForegroundColor White
    Write-Host '  -y                      skip the confirmation on down' -ForegroundColor White
    Write-Host ''
    Write-Host '  dkr drives docker · pman drives podman. The command name is the engine,' -ForegroundColor DarkGray
    Write-Host '  so there is no --engine flag to remember.' -ForegroundColor DarkGray
    Write-Host ''
}

<#
.SYNOPSIS
    Find the compose project a word refers to, whether or not it is running.
#>
function Resolve-ContainerComposeProject {
    param([string]$Name, [object[]]$Containers, [object[]]$Projects)

    if ($Name) {
        $hit = @($Projects | Where-Object { $_.Name -ieq $Name })
        if (-not $hit.Count) { $hit = @($Projects | Where-Object { $_.Name -ilike "*$Name*" }) }
        if ($hit.Count -and $hit[0].ConfigFile) {
            return [pscustomobject]@{ Name = $hit[0].Name; ConfigFile = $hit[0].ConfigFile; Services = @() }
        }
        $svc = @($Containers | Where-Object { ($_.Service -ieq $Name -or $_.Name -ieq $Name) -and $_.Project })
        if ($svc.Count) {
            return [pscustomobject]@{ Name = $svc[0].Project; ConfigFile = $svc[0].ConfigFile
                Services = @($svc | ForEach-Object { $_.Service } | Where-Object { $_ }) }
        }
        return $null
    }

    foreach ($candidate in @('compose.yaml', 'compose.yml', 'docker-compose.yaml', 'docker-compose.yml')) {
        $path = Join-Path $PWD.Path $candidate
        if (Test-Path -LiteralPath $path) {
            return [pscustomobject]@{ Name = (Split-Path $PWD.Path -Leaf); ConfigFile = $path; Services = @() }
        }
    }
    return $null
}

function Invoke-ContainerComposeView {
    param(
        [Parameter(Mandatory)]$Engine,
        [Parameter(Mandatory)][ValidateSet('up', 'down')][string]$Action,
        [Parameter(Mandatory)]$Target,
        [switch]$ShowNative, [switch]$Yes
    )

    # `down` removes containers and networks. It leaves named volumes alone (verified
    # against Compose v5.3.1 — only -v deletes those, and -v is not reachable from here),
    # but it is still the one verb here that destroys something, so it asks first.
    if ($Action -eq 'down' -and -not $Yes) {
        Write-Host "Stop and remove the containers of '$($Target.Name)'?" -ForegroundColor Yellow
        Write-Host '  Named volumes are NOT removed - your data stays.' -ForegroundColor DarkGray
        if ((Read-Host '  [y/N]') -notmatch '^(y|yes)$') {
            Write-Host 'Cancelled.' -ForegroundColor DarkGray
            return
        }
    }

    if ($ShowNative) {
        $plan = Invoke-ContainerCompose -Engine $Engine -Action $Action -Project $Target.Name `
            -ConfigFile $Target.ConfigFile -Services $Target.Services -WhatIf
        Show-ContainerNative $plan.Native
    }

    Write-Host "$(if ($Action -eq 'up') { 'Starting' } else { 'Stopping' }) stack '$($Target.Name)'..." -ForegroundColor Cyan
    $result = Invoke-ContainerCompose -Engine $Engine -Action $Action -Project $Target.Name `
        -ConfigFile $Target.ConfigFile -Services $Target.Services
    foreach ($line in $result.Output) { Write-Host "  $line" -ForegroundColor DarkGray }
    if ($result.Success) { Write-Host "  [OK] $($Target.Name)" -ForegroundColor Green }
    else { Write-Host "  [X] $($Target.Name) - see above" -ForegroundColor Red }
}

<#
.SYNOPSIS
    The shared implementation behind `dkr` and `pman`.
#>
function Invoke-PFContainerCommand {
    param(
        [Parameter(Mandatory)][ValidateSet('docker', 'podman')][string]$EngineName,
        [object[]]$Arguments = @()
    )

    $command    = if ($EngineName -eq 'podman') { 'pman' } else { 'dkr' }
    $showNative = $false; $follow = $false; $includeAll = $false; $assumeYes = $false
    $words      = @()

    foreach ($argument in $Arguments) {
        $token = "$argument"
        if (-not $token) { continue }
        if ($token -eq '--show-native') { $showNative = $true; continue }
        if ($token -in @('-f', '--follow')) { $follow = $true; continue }
        if ($token -in @('-a', '--all')) { $includeAll = $true; continue }
        if ($token -in @('-y', '--yes')) { $assumeYes = $true; continue }
        if ($token -in @('-h', '--help')) { Show-ContainerHelp -Command $command -EngineName $EngineName; return }
        $words += $token
    }

    $verb = if ($words.Count) { $words[0].ToLowerInvariant() } else { '' }
    if ($verb -eq 'help') { Show-ContainerHelp -Command $command -EngineName $EngineName; return }

    $engine = Get-ContainerEngineInfo -Engine $EngineName
    if ($engine.State -ne 'ready') { Show-ContainerEngineProblem -Engine $engine; return }

    # Podman on Windows can own the standard docker pipe, so `dkr` may in fact be driving
    # podman. Saying so is the whole point of having two commands — silently mislabelling
    # the engine is the confusion this is meant to prevent.
    if ($engine.Mismatched) {
        Write-Host "Note: $command is talking to $($engine.ServedBy), not $EngineName." -ForegroundColor Yellow
        Write-Host "      The active $EngineName endpoint is served by $($engine.ServedBy)." -ForegroundColor DarkGray
        $other = if ($engine.ServedBy -eq 'podman') { 'pman' } else { 'dkr' }
        Write-Host "      Use  $other  to be explicit about which engine you mean." -ForegroundColor DarkGray
        Write-Host ''
    }

    $containers = @(Get-ContainerList -Engine $engine -All)
    if ($containers.Count -eq 0 -and $verb -notin @('up', 'down')) {
        # Zero rows is ambiguous: it means "this host has no containers" OR "the engine
        # stopped answering between the version probe and now". Saying the first when the
        # second is true is a confident WRONG answer — it reads as a fact about the host and
        # suppresses the advisory that would have told the user their machine is down. One
        # extra probe, only in the zero case, buys an honest message.
        $recheck = Get-ContainerEngineInfo -Engine $EngineName
        if ($recheck.State -ne 'ready') { Show-ContainerEngineProblem -Engine $recheck; return }
        # "No containers" is true of the STORE, not necessarily of the host. A podman machine
        # exposes a rootless and a rootful store holding DIFFERENT containers, and only one is
        # active — so the other stores are checked before any claim is made about the machine.
        # Measured on a real host: the active store held one stack while five containers sat in
        # the rootless store, one connection away.
        Write-Host "No containers in the active $EngineName store." -ForegroundColor Yellow
        Show-ContainerStoreHint -Engine $engine -ActiveCount 0
        return
    }

    $names    = @($words | Select-Object -Skip 1)
    $pickPool = if ($includeAll) { $containers } else { @($containers | Where-Object { $_.State -eq 'running' }) }
    if ($pickPool.Count -eq 0) { $pickPool = $containers }

    # ---- bare command: the table, then act on what you mark -------------------------
    if (-not $verb) {
        $servedNote = if ($engine.Mismatched) { " (served by $($engine.ServedBy))" } else { '' }
        Show-ContainerTable -Containers $containers -Header "$EngineName $($engine.Version)$servedNote"
        if ($showNative) { Show-ContainerNative "$($engine.Binary) ps --all --format <template>" }
        # Say so when containers exist in a store this command is not looking at. Without
        # this, the table is accurate and still misleading.
        Show-ContainerStoreHint -Engine $engine -ActiveCount $containers.Count
        if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
            Write-Host "    Install fzf to act on these from here: $(Get-DependencyInstallHint 'fzf')" -ForegroundColor DarkGray
            return
        }
        $picked = @(Select-ContainerTargets -Containers $pickPool)
        if (-not $picked.Count) { return }
        $action = Select-ContainerAction -Count $picked.Count
        if (-not $action) { return }

        switch ($action) {
            'logs'  { Invoke-ContainerLogsView  -Engine $engine -Container $picked[0] -Follow:$follow -ShowNative:$showNative }
            'shell' { Invoke-ContainerShellView -Engine $engine -Container $picked[0] -ShowNative:$showNative }
            default { Invoke-ContainerLifecycleView -Engine $engine -Action $action -Targets $picked -ShowNative:$showNative }
        }
        return
    }

    # ---- compose verbs -------------------------------------------------------------
    if ($verb -in @('stores', 'store')) {
        # Refinement is a WORD, not a flag: `pman stores volumes`, not `pman stores --volumes`.
        if ($names.Count) { Show-ContainerStoreResource -Engine $engine -Resource $names[0].ToLowerInvariant() }
        else { Show-ContainerStores -Engine $engine }
        return
    }

    if ($verb -in @('up', 'down')) {
        $projects = @(Get-ContainerComposeProjects -Engine $engine)
        $wanted   = if ($names.Count) { $names[0] } else { '' }
        $target   = Resolve-ContainerComposeProject -Name $wanted -Containers $containers -Projects $projects

        if (-not $target) {
            if ($wanted) { Write-Host "[X] No compose project or service matching '$wanted'." -ForegroundColor Red }
            else {
                Write-Host '[X] No compose file in this directory, and no project named.' -ForegroundColor Red
                Write-Host "    Try:  $command $verb <project>" -ForegroundColor DarkGray
            }
            if ($projects.Count) {
                Write-Host "    Projects on this host: $(@($projects | ForEach-Object { $_.Name }) -join ', ')" -ForegroundColor DarkGray
            }
            return
        }
        Invoke-ContainerComposeView -Engine $engine -Action $verb -Target $target -ShowNative:$showNative -Yes:$assumeYes
        return
    }

    # ---- lifecycle verbs -----------------------------------------------------------
    if ($verb -in @('start', 'stop', 'restart')) {
        $targets = @()
        if ($names.Count) {
            $resolved = Resolve-ContainerTargets -Containers $containers -Names $names
            if ($resolved.Missing.Count) { Show-ContainerMissing -Missing $resolved.Missing -Containers $containers }
            $targets = @($resolved.Matched)
        }
        else {
            $pool = if ($verb -eq 'start') { @($containers | Where-Object { $_.State -ne 'running' }) } else { $pickPool }
            if (-not $pool.Count) { Write-Host "Nothing to $verb." -ForegroundColor Yellow; return }
            $targets = @(Select-ContainerTargets -Containers $pool -Prompt "$verb`: ")
        }
        if (-not $targets.Count) { return }
        Invoke-ContainerLifecycleView -Engine $engine -Action $verb -Targets $targets -ShowNative:$showNative
        return
    }

    if ($verb -eq 'logs') {
        $target = $null
        if ($names.Count) {
            $resolved = Resolve-ContainerTargets -Containers $containers -Names @($names[0])
            if ($resolved.Missing.Count) { Show-ContainerMissing -Missing $resolved.Missing -Containers $containers; return }
            $target = $resolved.Matched[0]
        }
        else {
            $picked = @(Select-ContainerTargets -Containers $pickPool -Prompt 'Logs: ')
            if (-not $picked.Count) { return }
            $target = $picked[0]
        }
        Invoke-ContainerLogsView -Engine $engine -Container $target -Follow:$follow -ShowNative:$showNative
        return
    }

    if ($verb -in @('shell', 'sh')) {
        $target = $null
        if ($names.Count) {
            $resolved = Resolve-ContainerTargets -Containers $containers -Names @($names[0])
            if ($resolved.Missing.Count) { Show-ContainerMissing -Missing $resolved.Missing -Containers $containers; return }
            $target = $resolved.Matched[0]
        }
        else {
            $running = @($containers | Where-Object { $_.State -eq 'running' })
            if (-not $running.Count) { Write-Host 'No running containers to shell into.' -ForegroundColor Yellow; return }
            $picked = @(Select-ContainerTargets -Containers $running -Prompt 'Shell: ')
            if (-not $picked.Count) { return }
            $target = $picked[0]
        }
        Invoke-ContainerShellView -Engine $engine -Container $target -ShowNative:$showNative
        return
    }

    # An unknown first word is far more likely a container name than a typo'd verb.
    $resolved = Resolve-ContainerTargets -Containers $containers -Names @($verb)
    if ($resolved.Matched.Count) {
        Show-ContainerTable -Containers $resolved.Matched -Header "matching '$verb'"
        return
    }
    Write-Host "[X] Unknown command or container: '$verb'" -ForegroundColor Red
    Write-Host "    $command help" -ForegroundColor DarkGray
}

<#
.SYNOPSIS
    Docker containers without the flags.
#>
function dkr { Invoke-PFContainerCommand -EngineName 'docker' -Arguments $args }

<#
.SYNOPSIS
    Podman containers without the flags.
#>
function pman { Invoke-PFContainerCommand -EngineName 'podman' -Arguments $args }

# The two entry points are registered with LITERAL names, one line each, because the help
# gate finds registrations by matching -Name '<literal>' in the source. Built from a loop
# variable they are invisible to it, and both commands read as defined-but-unregistered —
# which is exactly how they failed the release gate once.
Register-PFCommand -Name 'dkr'  -Section '🐳 CONTAINERS' `
    -Synopsis 'docker container table; mark several in fzf and act on them' -Example 'dkr'
Register-PFCommand -Name 'pman' -Section '🐳 CONTAINERS' `
    -Synopsis 'podman container table; mark several in fzf and act on them' -Example 'pman'

# The sub-verbs stay generated: they are registry entries rather than definitions, so no
# static check needs to see them, and spelling out sixteen near-identical lines would
# invite the two engines to drift apart.
foreach ($c in @('dkr', 'pman')) {
    Register-PFCommand -Name "$c logs" -Section '🐳 CONTAINERS' `
        -Synopsis 'Tail a container log; -f follows, no name opens a picker' -Example "$c logs jellyfin -f"
    Register-PFCommand -Name "$c shell" -Section '🐳 CONTAINERS' `
        -Synopsis 'Shell into a container, bash if present else sh' -Example "$c shell sonarr" -Aliases @("$c sh")
    Register-PFCommand -Name "$c up" -Section '🐳 CONTAINERS' `
        -Synopsis 'Bring a compose stack up; no name uses the compose file here' -Example "$c up media"
    Register-PFCommand -Name "$c down" -Section '🐳 CONTAINERS' `
        -Synopsis 'Take a compose stack down; confirms, keeps named volumes' -Example "$c down media"
    Register-PFCommand -Name "$c restart" -Section '🐳 CONTAINERS' `
        -Synopsis 'Restart containers, compose-correct from any directory' -Example "$c restart sonarr radarr"
    Register-PFCommand -Name "$c stop" -Section '🐳 CONTAINERS' `
        -Synopsis 'Stop containers; no name opens a multi-select picker' -Example "$c stop"
    Register-PFCommand -Name "$c start" -Section '🐳 CONTAINERS' `
        -Synopsis 'Start stopped containers; no name opens a picker' -Example "$c start qbittorrent"
    Register-PFCommand -Name "$c stores" -Section '🐳 CONTAINERS' `
        -Synopsis 'Every store this engine sees, and where containers actually live' -Example "$c stores"
}
