$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
}

function Assert-Equal($Expected, $Actual, [string]$Message) {
    if ("$Expected" -cne "$Actual") { throw "FAIL: $Message`n  expected: $Expected`n  actual:   $Actual" }
}

function Get-RepoRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
}

function Get-ContainerAdapterPath {
    param([Parameter(Mandatory)][ValidateSet('linux', 'windows')][string]$Platform)
    $path = Join-Path (Get-RepoRoot) "platform/$Platform/adapters/container.ps1"
    Assert-True (Test-Path -LiteralPath $path) "adapter missing: $path"
    return $path
}

<#
.SYNOPSIS
    Fixture rows in the exact shape the adapter's go-template produces.
.DESCRIPTION
    Tab-delimited, field order Names·ID·Image·Status·State·Ports·Labels — NOT JSON. The
    adapter deliberately does not use `--format '{{json .}}'`, because that is the one part
    of the surface where docker and podman genuinely diverge (podman returns Names as an
    array, Labels as an object, Ports as an array of objects, and keys the id `Id`).

    Row four carries a label value containing a LITERAL TAB, which is the case the
    seven-field split cap exists for. If the cap regresses, that row's columns shift and
    the assertions catch it.
#>
function Get-ContainerPsFixture {
    $mediaLabels = 'com.docker.compose.project={0},com.docker.compose.service={1},' +
                   'com.docker.compose.project.working_dir=/srv/docker/media,' +
                   'com.docker.compose.project.config_files=/srv/docker/media/docker-compose.yml'
    $t = "`t"
    return @(
        ('sonarr{0}aaaaaaaaaaaa1111{0}linuxserver/sonarr{0}Up 3 days{0}running{0}0.0.0.0:8989->8989/tcp, :::8989->8989/tcp{0}{1}' -f
            $t, ($mediaLabels -f 'media', 'sonarr')),
        ('radarr{0}bbbbbbbbbbbb2222{0}linuxserver/radarr{0}Up 3 days{0}running{0}0.0.0.0:7878->7878/tcp, :::7878->7878/tcp{0}{1}' -f
            $t, ($mediaLabels -f 'media', 'radarr')),
        ('qbittorrent{0}cccccccccccc3333{0}linuxserver/qbittorrent{0}Up 8 hours{0}running{0}0.0.0.0:8080->8080/tcp{0}' -f $t),
        ('jellyfin{0}dddddddddddd4444{0}jellyfin/jellyfin{0}Exited (0) 2 hours ago{0}exited{0}{0}description=has a{0}tab in it' -f $t)
    )
}

<#
.SYNOPSIS
    Fixture for `compose ls --all --format json`, optionally wrapped in podman's noise.
.DESCRIPTION
    Podman delegates compose to an external provider and announces it, ANSI-wrapped, on
    every call — measured on a real host. Left in place the JSON is unparseable and the
    failure is SILENT, because the leading byte stops being '['.
#>
function Get-ComposeLsFixture {
    param([switch]$WithPodmanNoise)

    $json = (@(
        @{ Name = 'media';   Status = 'running(2)'; ConfigFiles = '/srv/docker/media/docker-compose.yml' },
        @{ Name = 'archive'; Status = 'exited(3)';  ConfigFiles = '/srv/docker/archive/docker-compose.yml' }
    ) | ConvertTo-Json -Compress)

    if (-not $WithPodmanNoise) { return @($json) }

    $esc = [char]27
    return @(
        "$esc[4m>>>> Executing external compose provider ""/usr/bin/docker-compose"". Please see podman-compose(1) for how to disable this message. <<<<",
        "$esc[0m$json"
    )
}

# Calls are stored as space-joined STRINGS. Nested arrays look tidier but are a trap:
# returning a one-element array whose element is an array makes PowerShell unroll it, so a
# single five-argument call reads back as five calls.
$global:PFEngineCalls = [System.Collections.Generic.List[string]]::new()

function Get-RecordedEngineCalls  { return @($global:PFEngineCalls.ToArray()) }
function Clear-RecordedEngineCalls { $global:PFEngineCalls.Clear() }

# The engine descriptor the adapter passes around. Built by hand so tests can exercise
# podman's behaviour on a Windows host and vice versa.
function New-TestEngine {
    param(
        [ValidateSet('docker', 'podman')][string]$Name = 'docker',
        [switch]$NeedsSudo,
        [switch]$ComposeNoisy,
        [string]$ServedBy = '',
        [switch]$Mismatched
    )
    return [pscustomobject]@{
        Name = $Name; Binary = $Name; State = 'ready'; Version = '99.9'
        NeedsSudo = [bool]$NeedsSudo; Compose = 'plugin'
        ComposeNoisy = [bool]($ComposeNoisy -or $Name -eq 'podman')
        Error = ''; ServedBy = $ServedBy; Mismatched = [bool]$Mismatched
    }
}

<#
.SYNOPSIS
    Shim docker and podman as functions so the adapter's real body runs without an engine.
.DESCRIPTION
    PowerShell resolves `& docker` to a FUNCTION before a native binary, so the adapter
    under test is the genuine article rather than a reimplementation — which is what lets
    the Linux adapter be exercised on Windows, and both engines be exercised anywhere.
#>
function New-EngineShim {
    param([Parameter(Mandatory)][string]$Name)
    $body = {
        $call = @($args | ForEach-Object { "$_" })
        $global:PFEngineCalls.Add(($MyInvocation.MyCommand.Name + ' ' + ($call -join ' ')).Trim())
        $global:LASTEXITCODE = 0
        if ($call -contains 'ps') { return (Get-ContainerPsFixture) }
        if ($call -contains 'ls') {
            $noisy = $MyInvocation.MyCommand.Name -eq 'podman'
            return (Get-ComposeLsFixture -WithPodmanNoise:$noisy)
        }
        if ($call -contains 'version') { return '99.9' }
        return @()
    }
    Set-Item -Path "function:global:$Name" -Value $body
}

function Remove-EngineShims {
    foreach ($name in @('docker', 'podman', 'sudo')) {
        if (Test-Path "function:global:$name") { Remove-Item "function:global:$name" -Force }
    }
}

# sudo forwards to the shim, minus its own leading tokens.
function New-SudoShim {
    Set-Item -Path 'function:global:sudo' -Value {
        $forwarded = @($args | ForEach-Object { "$_" })
        while ($forwarded.Count -and $forwarded[0] -eq '-n') { $forwarded = @($forwarded | Select-Object -Skip 1) }
        if (-not $forwarded.Count) { return @() }
        $binary = $forwarded[0]
        $rest   = @($forwarded | Select-Object -Skip 1)
        return (& $binary @rest)
    }
}
