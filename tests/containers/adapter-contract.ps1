$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-helpers.ps1')

$assertions = 0

# ---------------------------------------------------------------------------------
# Contract parity. A function present on only one OS satisfies CI's regex and then
# explodes at runtime on the other, so the two files are compared to each other.
# ---------------------------------------------------------------------------------
$contract = @('Get-ContainerEngineNames', 'Get-ContainerEngineInfo', 'Get-ContainerEngineIdentity',
              'Get-ContainerList', 'Invoke-ContainerLifecycle', 'Get-ContainerLogCommand',
              'Get-ContainerShellCommand', 'Invoke-ContainerInteractive',
              'Get-ContainerComposeProjects', 'Invoke-ContainerCompose',
              'Invoke-PFContainerEngine', 'Clear-PFComposeNoise')

$signatures = @{}
foreach ($platform in @('linux', 'windows')) {
    $text  = Get-Content -LiteralPath (Get-ContainerAdapterPath $platform) -Raw
    $found = @([regex]::Matches($text, '(?m)^function\s+([A-Za-z][\w-]*)') | ForEach-Object { $_.Groups[1].Value })
    $signatures[$platform] = $found
    foreach ($name in $contract) {
        Assert-True ($found -contains $name) "$platform adapter is missing $name"
        $assertions++
    }
}
$onlyLinux   = @($signatures['linux']   | Where-Object { $signatures['windows'] -notcontains $_ })
$onlyWindows = @($signatures['windows'] | Where-Object { $signatures['linux']   -notcontains $_ })
Assert-True ($onlyLinux.Count -eq 0)   "functions only in the Linux container adapter: $($onlyLinux -join ', ')"
Assert-True ($onlyWindows.Count -eq 0) "functions only in the Windows container adapter: $($onlyWindows -join ', ')"
$assertions += 2

# The template must use \t, not `t. PowerShell does not expand escapes in single quotes, so
# a backtick-t reaches the engine literally, no real tabs are emitted, and the parser then
# skips every container. Measured against both engines — this is a regression guard.
foreach ($platform in @('linux', 'windows')) {
    $text = Get-Content -LiteralPath (Get-ContainerAdapterPath $platform) -Raw
    $line = [regex]::Match($text, "(?m)^\s*'\{\{\.Names\}\}.*\{\{\.Labels\}\}'").Value
    Assert-True ($line.Length -gt 0) "$platform : could not find the container template"
    Assert-True ($line.Contains('\t')) "$platform : template must use \t so the ENGINE expands the tab"
    Assert-True (-not $line.Contains('`t')) "$platform : template must not use ``t - PowerShell leaves it literal in single quotes"
    Assert-True ($line.IndexOf('{{.Labels}}') -gt $line.IndexOf('{{.Ports}}')) `
        "$platform : Labels must be LAST so a tab inside a label value cannot shift other columns"
    $assertions += 4
}

# ---------------------------------------------------------------------------------
# Behaviour, per platform AND per engine.
# ---------------------------------------------------------------------------------
New-EngineShim -Name 'docker'
New-EngineShim -Name 'podman'
New-SudoShim

foreach ($platform in @('linux', 'windows')) {
    . (Get-ContainerAdapterPath $platform)

    foreach ($engineName in @('docker', 'podman')) {
        $tag    = "$platform/$engineName"
        $engine = New-TestEngine -Name $engineName
        Clear-RecordedEngineCalls

        # --- parsing ----------------------------------------------------------------
        $containers = @(Get-ContainerList -Engine $engine -All)
        Assert-Equal 4 $containers.Count "$tag : expected 4 containers from the fixture"
        $assertions++

        $sonarr = $containers | Where-Object { $_.Name -eq 'sonarr' }
        Assert-Equal 'media'   $sonarr.Project "$tag : compose project not read from labels"
        Assert-Equal 'sonarr'  $sonarr.Service "$tag : compose service not read from labels"
        Assert-Equal '/srv/docker/media/docker-compose.yml' $sonarr.ConfigFile "$tag : config_files label not read"
        Assert-Equal 'running' $sonarr.State   "$tag : state not parsed"
        Assert-Equal 'Up 3 days' $sonarr.Status "$tag : status not parsed"
        Assert-Equal $engineName $sonarr.Engine "$tag : the row should record which engine produced it"
        $assertions += 6

        # The engine's own binary must be the one invoked — this is what makes `pman` podman.
        # @() at the call site is load-bearing: a one-element result unrolls to a scalar
        # string, and [0] would then index its first CHARACTER.
        $calls = @(Get-RecordedEngineCalls)
        Assert-True ($calls.Count -gt 0) "$tag : the adapter made no engine call at all"
        Assert-True ($calls[0].StartsWith($engineName)) `
            "$tag : the adapter called the wrong binary: $($calls[0])"
        $assertions += 2

        # A stopped container must survive parsing — hiding it is what makes "missing" and
        # "dead" indistinguishable, which is the thing this command exists to fix.
        $jellyfin = $containers | Where-Object { $_.Name -eq 'jellyfin' }
        Assert-True ($null -ne $jellyfin) "$tag : exited container dropped during parsing"
        Assert-Equal 'exited' $jellyfin.State "$tag : exited state not preserved"
        $assertions += 2

        # THE TAB-IN-A-LABEL CASE. jellyfin's label value contains a literal tab; the
        # seven-field split cap must absorb it rather than shifting the other columns.
        Assert-Equal 'Exited (0) 2 hours ago' $jellyfin.Status "$tag : a tab inside a label shifted the STATUS column"
        Assert-Equal '' $jellyfin.Ports "$tag : a tab inside a label shifted the PORTS column"
        $assertions += 2

        # A standalone container has no compose labels and must not invent any.
        $qbit = $containers | Where-Object { $_.Name -eq 'qbittorrent' }
        Assert-Equal '' $qbit.Project "$tag : standalone container was given a compose project"
        $assertions++

        # --- compose correctness -----------------------------------------------------
        $media = @($containers | Where-Object { $_.Project -eq 'media' })
        $plan  = @(Invoke-ContainerLifecycle -Engine $engine -Action 'restart' -Containers $media -WhatIf)
        Assert-Equal 1 $plan.Count "$tag : compose services were not grouped into one command"
        Assert-True ($plan[0].Native -like "$engineName compose -f /srv/docker/media/docker-compose.yml -p media restart *") `
            "$tag : not compose-correct - got '$($plan[0].Native)'"
        Assert-True ($plan[0].Native -like '*sonarr*' -and $plan[0].Native -like '*radarr*') `
            "$tag : both services should appear in the one command"
        $assertions += 3

        $plainPlan = @(Invoke-ContainerLifecycle -Engine $engine -Action 'stop' -Containers @($qbit) -WhatIf)
        Assert-Equal "$engineName stop qbittorrent" $plainPlan[0].Native "$tag : standalone lifecycle should not use compose"
        $assertions++

        Clear-RecordedEngineCalls
        $null = @(Invoke-ContainerLifecycle -Engine $engine -Action 'restart' -Containers $media -WhatIf)
        Assert-Equal 0 (Get-RecordedEngineCalls).Count "$tag : -WhatIf issued an engine call"
        $assertions++

        # --- compose projects, including podman's provider banner ---------------------
        $projects = @(Get-ContainerComposeProjects -Engine $engine)
        Assert-Equal 2 $projects.Count "$tag : expected 2 compose projects (banner stripping may have failed)"
        $stopped = $projects | Where-Object { $_.Name -eq 'archive' }
        Assert-True ($null -ne $stopped) "$tag : a fully stopped project must still be listed"
        Assert-Equal '/srv/docker/archive/docker-compose.yml' $stopped.ConfigFile "$tag : project config file not read"
        $assertions += 3

        # --- up is detached; down can never reach -v ---------------------------------
        $up = Invoke-ContainerCompose -Engine $engine -Action 'up' -Project 'media' `
            -ConfigFile '/srv/docker/media/docker-compose.yml' -WhatIf
        Assert-Equal "$engineName compose -f /srv/docker/media/docker-compose.yml -p media up -d" $up.Native `
            "$tag : up must be detached"
        $down = Invoke-ContainerCompose -Engine $engine -Action 'down' -Project 'media' `
            -ConfigFile '/srv/docker/media/docker-compose.yml' -WhatIf
        Assert-Equal "$engineName compose -f /srv/docker/media/docker-compose.yml -p media down" $down.Native `
            "$tag : down command wrong"
        Assert-True ($down.Native -notmatch '(^|\s)(-v|--volumes)(\s|$)') `
            "$tag : down must never pass -v - that is what deletes named volumes"
        $assertions += 3

        # --- log and shell commands ---------------------------------------------------
        $log = Get-ContainerLogCommand -Engine $engine -Container $sonarr -Tail 200
        Assert-True ($log.Native -like "$engineName compose -f *-p media logs --tail 200*sonarr") `
            "$tag : compose log command wrong - got '$($log.Native)'"
        Assert-True ($log.Native -notlike '*--follow*') "$tag : logs followed without being asked to"
        $followed = Get-ContainerLogCommand -Engine $engine -Container $sonarr -Tail 50 -Follow
        Assert-True ($followed.Native -like '*--tail 50*' -and $followed.Native -like '*--follow*') `
            "$tag : -Follow/-Tail not honoured"
        $plainLog = Get-ContainerLogCommand -Engine $engine -Container $qbit -Tail 200
        Assert-Equal "$engineName logs --tail 200 qbittorrent" $plainLog.Native "$tag : standalone log command wrong"
        $assertions += 4

        $shell = Get-ContainerShellCommand -Engine $engine -Container $sonarr
        Assert-Equal 'sh' $shell.Shell "$tag : should fall back to sh when bash is absent"
        Assert-Equal "$engineName exec -it sonarr sh" $shell.Native "$tag : shell command wrong"
        Assert-True ($log.Arguments -is [array])   "$tag : log arguments must be an array"
        Assert-True ($shell.Arguments -is [array]) "$tag : shell arguments must be an array"
        $assertions += 4
    }

    # --- podman must NEVER be elevated ------------------------------------------------
    # `sudo podman ps` queries ROOT'S SEPARATE container store — different containers, not
    # the same ones with more rights. Elevating would show the wrong set and call it success.
    $text = Get-Content -LiteralPath (Get-ContainerAdapterPath $platform) -Raw
    $sudoLines = @([regex]::Matches($text, '(?m)^.*&\s*sudo.*$') | ForEach-Object { $_.Value })
    foreach ($line in $sudoLines) {
        Assert-True ($line -notmatch 'podman') "$platform : found an elevated podman call: $($line.Trim())"
        $assertions++
    }
    Assert-True ($text -match "Engine -eq 'docker' -and") `
        "$platform : the sudo/permission path must be gated to docker only"
    $assertions++
}

# ---------------------------------------------------------------------------------
# Windows never elevates, for either engine.
# ---------------------------------------------------------------------------------
$windowsText = Get-Content -LiteralPath (Get-ContainerAdapterPath 'windows') -Raw
Assert-True ($windowsText -notmatch '&\s*sudo') 'the Windows container adapter must never invoke sudo'
$assertions++

# ---------------------------------------------------------------------------------
# The compose-noise stripper, directly.
# ---------------------------------------------------------------------------------
$esc = [char]27
$noisy = @(
    "$esc[4m>>>> Executing external compose provider ""/usr/bin/docker-compose"". Please see podman-compose(1) for how to disable this message. <<<<",
    "$esc[0m[{""Name"":""media""}]"
)
$clean = @(Clear-PFComposeNoise -Lines $noisy)
Assert-Equal 1 $clean.Count 'the banner line should be dropped entirely'
Assert-True ($clean[0].StartsWith('[')) "after stripping, the JSON must start with '[' - got '$($clean[0])'"
Assert-True ($clean[0] -notmatch "$esc") 'ANSI escapes must be removed'
$assertions += 3

Remove-EngineShims
Write-Host "  container adapter contract: $assertions assertions passed" -ForegroundColor Green
