# ==============================================================================
# PowerFlow — Team Room Adapter (Linux)
# ==============================================================================
# Domain   : Platform / Linux
# File     : platform/linux/adapters/team-room.ps1
# Purpose  : Discover and control team-room agent watchers on Linux
# Contract : Get-TeamRoomState, Set-TeamRoomArm, Set-TeamRoomTask,
#            Stop-TeamRoomWatcher, Get-TeamRoomBootInstant
# Depends  : none
# ==============================================================================
#
# WHAT EXISTS ON LINUX, AND WHAT DOES NOT
#
# team-room has two layers. Only one of them is cross-platform:
#
#   WAIT WATCHER    a `node teamchat-wait.js` process. Pure Node, works anywhere. Fully
#                   supported here — discovered from /proc and stoppable.
#   WAKE CONNECTOR  teamchat-codex-wake.js registers a WINDOWS Scheduled Task, via
#                   powershell.exe and Register-ScheduledTask. There is no Linux
#                   implementation in the toolkit at all — not a cron job, not a systemd
#                   timer. So Set-TeamRoomTask reports honestly rather than pretending.
#
# The ARM STAMP is just a JSON file in the repo, so it is fully supported on both.
# ==============================================================================

function Get-TeamRoomBootInstant {
    # Same definition teamchat uses: now minus uptime. Both move together across a clock
    # change, so the value names a boot session without trusting wall time.
    if (-not (Test-Path -LiteralPath '/proc/uptime')) { return 0 }
    try {
        $uptimeSeconds = [double](((Get-Content -LiteralPath '/proc/uptime' -Raw) -split '\s+')[0])
        return [int64]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - ($uptimeSeconds * 1000))
    } catch { return 0 }
}

function Get-TeamRoomArmState {
    param([Parameter(Mandatory)][string]$RepoRoot)

    $file = Join-Path $RepoRoot 'team-room/state/armed.json'
    $out = [pscustomobject]@{ Armed = $false; Reason = 'never-armed-this-boot'; File = $file; ArmedAt = $null; ArmedBy = $null; DriftMs = $null }
    if (-not (Test-Path -LiteralPath $file)) { return $out }
    try { $stamp = Get-Content -LiteralPath $file -Raw -ErrorAction Stop | ConvertFrom-Json }
    catch { $out.Reason = 'unreadable-arm-stamp'; return $out }

    if ($null -eq $stamp.bootInstantMs) { $out.Reason = 'malformed-arm-stamp'; return $out }
    $out.ArmedAt = $stamp.armedAt
    $out.ArmedBy = $stamp.armedBy
    $drift = [math]::Abs((Get-TeamRoomBootInstant) - [int64]$stamp.bootInstantMs)
    $out.DriftMs = $drift
    if ($drift -gt 180000) { $out.Reason = 'armed-in-previous-boot'; return $out }   # ARM_TOLERANCE_MS
    $out.Armed = $true; $out.Reason = 'armed'
    return $out
}

# Watchers are plain `node`, so they are found by their SCRIPT name in /proc/<pid>/cmdline
# (NUL-separated argv), never by process name.
function Get-TeamRoomWatchers {
    $out = @()
    foreach ($proc in @(Get-ChildItem -LiteralPath '/proc' -Directory -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -match '^\d+$' })) {
        $f = Join-Path $proc.FullName 'cmdline'
        if (-not (Test-Path -LiteralPath $f)) { continue }
        try {
            $raw = [IO.File]::ReadAllBytes($f)
            if (-not $raw.Length) { continue }
            $cmd = ([Text.Encoding]::UTF8.GetString($raw) -replace "`0", ' ').Trim()
        } catch { continue }
        if ($cmd -notmatch 'teamchat-wait') { continue }

        $me = if ($cmd -match '--me\s+"?([^"\s]+)') { $matches[1] } else { '' }
        $started = $null
        try { $started = (Get-Item -LiteralPath $proc.FullName -Force).CreationTime } catch { }
        $out += [pscustomobject]@{
            Pid = [int]$proc.Name; Me = $me
            CommandLine = ($cmd -replace '\s+', ' ').Trim()
            Started = $started; RepoRoot = ''
        }
    }
    return @($out)
}

function Get-TeamRoomState {
    $watchers = @(Get-TeamRoomWatchers)
    $rooms = @{}

    # On Linux a room is discovered from a live watcher's own command line, since there is
    # no scheduled-task registry to enumerate.
    foreach ($w in $watchers) {
        if ($w.CommandLine -match '(/[^ ]*?)/team-room/bin') {
            $repo = $matches[1]
            $rooms[$repo.ToLower()] = [pscustomobject]@{
                Name = (Split-Path $repo -Leaf); RepoRoot = $repo
            }
        }
    }
    # …plus the repo we are standing in, if it has a team-room. A room armed with nothing
    # watching is precisely the state the owner could not previously see.
    $cwd = (Get-Location).Path
    if (Test-Path -LiteralPath (Join-Path $cwd 'team-room')) {
        $rooms[$cwd.ToLower()] = [pscustomobject]@{ Name = (Split-Path $cwd -Leaf); RepoRoot = $cwd }
    }

    $out = foreach ($r in $rooms.Values) {
        $arm  = Get-TeamRoomArmState -RepoRoot $r.RepoRoot
        $mine = @($watchers | Where-Object { $_.CommandLine -match [regex]::Escape($r.RepoRoot) -or
                                             $_.CommandLine -match [regex]::Escape((Split-Path $r.RepoRoot -Leaf)) })
        [pscustomobject]@{
            Name        = $r.Name
            RepoRoot    = $r.RepoRoot
            Agent       = ''
            TaskName    = ''
            TaskState   = ''
            TaskLastRun = $null
            TaskResult  = $null
            TaskNextRun = $null
            HasTask     = $false          # the wake connector is Windows-only
            Installed   = $false
            Armed       = $arm.Armed
            ArmReason   = $arm.Reason
            ArmedAt     = $arm.ArmedAt
            ArmedBy     = $arm.ArmedBy
            ArmFile     = $arm.File
            StateDir    = ''
            ConfigPath  = ''
            Watchers    = @($mine)
            # Without a connector task, only a live watcher makes a room actually do anything.
            Live        = ($mine.Count -gt 0)
        }
    }
    return @($out | Sort-Object @{ Expression = 'Live'; Descending = $true }, Name)
}

function Set-TeamRoomArm {
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][bool]$On, [string]$By = 'powerflow')

    $dir  = Join-Path $RepoRoot 'team-room/state'
    $file = Join-Path $dir 'armed.json'
    try {
        if ($On) {
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null }
            $stamp = [ordered]@{
                version      = 1
                armedAt      = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
                bootInstantMs= (Get-TeamRoomBootInstant)
                armedBy      = $By
            }
            [IO.File]::WriteAllText($file, (($stamp | ConvertTo-Json -Compress) + "`n"))
        } elseif (Test-Path -LiteralPath $file) {
            Remove-Item -LiteralPath $file -Force -ErrorAction Stop
        }
        return $true
    } catch {
        Write-Host "   $($_.Exception.Message)" -ForegroundColor DarkGray
        return $false
    }
}

# There is no Linux wake connector to enable or disable. Saying so beats silently
# returning success for something that did not happen.
function Set-TeamRoomTask {
    param([Parameter(Mandatory)][string]$TaskName, [Parameter(Mandatory)][bool]$Enabled)
    Write-Host '   The wake connector is a Windows Scheduled Task; team-room ships no Linux equivalent.' -ForegroundColor DarkGray
    return $false
}

function Stop-TeamRoomWatcher {
    param([Parameter(Mandatory)][int]$ProcessId)
    try {
        # Re-verify identity before signalling: PIDs are reused, and this runs after a
        # confirmation the user may have taken time over.
        $f = "/proc/$ProcessId/cmdline"
        if (-not (Test-Path -LiteralPath $f)) { return $false }
        $cmd = ([Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($f)) -replace "`0", ' ')
        if ($cmd -notmatch 'teamchat-wait') { return $false }
        Stop-Process -Id $ProcessId -Force -ErrorAction Stop
        return $true
    } catch { return $false }
}
