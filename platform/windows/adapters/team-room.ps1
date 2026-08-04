# ==============================================================================
# PowerFlow — Team Room Adapter (Windows)
# ==============================================================================
# Domain   : Platform / Windows
# File     : platform/windows/adapters/team-room.ps1
# Purpose  : Discover and control team-room agent watchers — the scheduled wake
#            connectors, the boot-scoped arm stamps, and the live wait watchers
# Contract : Get-TeamRoomState, Set-TeamRoomArm, Set-TeamRoomTask,
#            Stop-TeamRoomWatcher, Get-TeamRoomBootInstant
# Depends  : none
# ==============================================================================
#
# WHAT A "TEAM ROOM" ACTUALLY IS
#
# team-room (the teamchat toolkit) coordinates two AI agents over an append-only chat log.
# Nothing about it is a server, so there is no port to probe. It runs as THREE separate
# things, and a room can be half-on in any combination of them:
#
#   1. WAKE CONNECTOR  a Windows Scheduled Task named "TeamChat-<Agent>-<repo>", ticking
#                      every N minutes. Its config lives in a heartbeat state dir.
#   2. ARM STAMP       <repo>/team-room/state/armed.json. BOOT-SCOPED: it records
#                      bootInstantMs, and the connector treats the room as dormant unless
#                      that matches the current boot. It fails CLOSED across a restart.
#   3. WAIT WATCHER    a live `node teamchat-wait.js` process (the in-session watcher).
#                      One-shot: it exits when it fires, so it must be re-armed each turn.
#
# THE OFF SWITCH IS THE ARM STAMP, NOT THE TASK. Disarming leaves the task ticking but
# makes every tick a no-op, which is the design's own dormancy path and is instantly
# reversible. Disabling or unregistering the task is the heavier hammer, offered
# separately. This is why the command reports all three states rather than one "on/off".
# ==============================================================================

# Where the connector keeps per-room config. It prefers a D: drive when present (that is
# what teamchat-codex-wake.js does), else ~/.codex.
function Get-TeamRoomStateRoots {
    $roots = @()
    if (Test-Path -LiteralPath 'D:\') { $roots += 'D:\CodexData\teamchat-heartbeat' }
    $roots += (Join-Path $env:USERPROFILE '.codex\teamchat-heartbeat')
    return @($roots | Where-Object { Test-Path -LiteralPath $_ })
}

# The identity of the current boot, in the same terms teamchat uses: now minus uptime.
# Both move together across a clock change, so it names a boot session without trusting
# wall time. Tolerance below matches teamchat's ARM_TOLERANCE_MS (3 minutes).
function Get-TeamRoomBootInstant {
    try {
        $boot = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime
        return [int64]([DateTimeOffset]::new($boot.ToUniversalTime(), [TimeSpan]::Zero).ToUnixTimeMilliseconds())
    } catch { return 0 }
}

function Get-TeamRoomArmState {
    param([Parameter(Mandatory)][string]$RepoRoot)

    $file = Join-Path $RepoRoot 'team-room\state\armed.json'
    $out = [pscustomobject]@{ Armed = $false; Reason = 'never-armed-this-boot'; File = $file; ArmedAt = $null; ArmedBy = $null; DriftMs = $null }
    if (-not (Test-Path -LiteralPath $file)) { return $out }
    try { $stamp = Get-Content -LiteralPath $file -Raw -ErrorAction Stop | ConvertFrom-Json }
    catch { $out.Reason = 'unreadable-arm-stamp'; return $out }

    if ($null -eq $stamp.bootInstantMs) { $out.Reason = 'malformed-arm-stamp'; return $out }
    $out.ArmedAt = $stamp.armedAt
    $out.ArmedBy = $stamp.armedBy
    $drift = [math]::Abs((Get-TeamRoomBootInstant) - [int64]$stamp.bootInstantMs)
    $out.DriftMs = $drift
    # 3 minutes, matching ARM_TOLERANCE_MS in teamchat-codex-wake.js.
    if ($drift -gt 180000) { $out.Reason = 'armed-in-previous-boot'; return $out }
    $out.Armed = $true; $out.Reason = 'armed'
    return $out
}

# Live in-session watchers. Matched on the SCRIPT name in the command line, not on the
# process name — they are plain `node`, indistinguishable from any other node process.
function Get-TeamRoomWatchers {
    $out = @()
    try {
        $procs = @(Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction Stop |
                   Where-Object { $_.CommandLine -match 'teamchat-wait' })
    } catch { return @() }

    foreach ($p in $procs) {
        $cmd = "$($p.CommandLine)"
        # --me tells us which agent identity the watcher is listening for.
        $me = if ($cmd -match '--me\s+"?([^"\s]+)') { $matches[1] } else { '' }
        $started = $null
        try { $started = $p.CreationDate } catch { }
        # Is the SCRIPT argument absolute? A rooted script names its repo; a relative one
        # ("team-room/bin/teamchat-wait.js") only makes sense against the launcher's cwd.
        $scriptToken = @(($cmd -split '\s+') | Where-Object { $_ -match 'teamchat-wait' }) | Select-Object -First 1
        $rooted = [bool]("$scriptToken" -match '^([A-Za-z]:[\\/]|[\\/])')

        $out += [pscustomobject]@{
            Pid           = [int]$p.ProcessId
            Me            = $me
            CommandLine   = ($cmd -replace '\s+', ' ').Trim()
            Started       = $started
            ScriptIsRooted= $rooted
            RepoRoot      = ''   # filled in by the caller when a room's path matches
        }
    }
    return @($out)
}

function Get-TeamRoomTasks {
    $out = @()
    try { $tasks = @(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskName -like 'TeamChat*' }) }
    catch { return @() }

    foreach ($t in $tasks) {
        $info = $null
        try { $info = Get-ScheduledTaskInfo -TaskName $t.TaskName -ErrorAction Stop } catch { }
        $out += [pscustomobject]@{
            TaskName   = $t.TaskName
            State      = "$($t.State)"
            LastRun    = if ($info) { $info.LastRunTime } else { $null }
            LastResult = if ($info) { $info.LastTaskResult } else { $null }
            NextRun    = if ($info) { $info.NextRunTime } else { $null }
        }
    }
    return @($out)
}

<#
.SYNOPSIS
    Every team room this machine knows about, with its three live states.
.DESCRIPTION
    Rooms are discovered from the MACHINE, not from the current repo: a connector config
    or a scheduled task means a room exists whether or not you are standing in it. A room
    whose task was uninstalled but whose config survives is still listed — that is exactly
    the "previously activated, not deleted" case that can be re-armed.
#>
function Get-TeamRoomState {
    $tasks    = @(Get-TeamRoomTasks)
    $watchers = @(Get-TeamRoomWatchers)
    $rooms    = @{}

    # 1. Rooms that have a connector config on disk.
    foreach ($root in (Get-TeamRoomStateRoots)) {
        foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
            $cfgPath = Join-Path $dir.FullName 'config.json'
            if (-not (Test-Path -LiteralPath $cfgPath)) { continue }
            try { $cfg = Get-Content -LiteralPath $cfgPath -Raw -ErrorAction Stop | ConvertFrom-Json } catch { continue }
            $key = "$($cfg.repoRoot)".ToLower()
            if (-not $key) { continue }
            $rooms[$key] = [pscustomobject]@{
                Name      = if ($cfg.repoRoot) { Split-Path $cfg.repoRoot -Leaf } else { $dir.Name }
                RepoRoot  = "$($cfg.repoRoot)"
                Agent     = "$($cfg.agent)"
                TaskName  = "$($cfg.taskName)"
                StateDir  = $dir.FullName
                ConfigPath= $cfgPath
                Installed = $true
            }
        }
    }

    # 2. Tasks with no config dir. These are real, tick on schedule, and the teamchat CLI
    #    cannot status or uninstall them (every one of those verbs needs --config). They
    #    must still be visible and stoppable, or they are invisible background activity.
    foreach ($t in $tasks) {
        $known = @($rooms.Values | Where-Object { $_.TaskName -eq $t.TaskName })
        if ($known.Count) { continue }
        $rooms["task:$($t.TaskName)".ToLower()] = [pscustomobject]@{
            Name      = ($t.TaskName -replace '^TeamChat-[^-]+-', '')
            RepoRoot  = ''
            Agent     = if ($t.TaskName -match '^TeamChat-([^-]+)-') { $matches[1] } else { '' }
            TaskName  = $t.TaskName
            StateDir  = ''
            ConfigPath= ''
            Installed = $false     # orphan: a task with no config to drive it
        }
    }

    # 3. A repo can be armed with no task at all (armed, but nothing will fire). Watchers
    #    launched with an ABSOLUTE path name their repo directly.
    foreach ($w in $watchers) {
        if ($w.CommandLine -match '([A-Za-z]:\\[^"]*?)[\\/]team-room[\\/]bin') {
            $repo = $matches[1]
            $key = $repo.ToLower()
            if (-not $rooms.ContainsKey($key)) {
                $rooms[$key] = [pscustomobject]@{
                    Name = (Split-Path $repo -Leaf); RepoRoot = $repo; Agent = ''
                    TaskName = ''; StateDir = ''; ConfigPath = ''; Installed = $false
                }
            }
        }
    }

    # 4. The repo we are standing in, if it has a team-room. Without this, a room that is
    #    armed but has no connector config and no task is invisible — and that is a real
    #    state: the arm stamp is a plain file, so any repo can be armed on its own.
    $cwd = (Get-Location).Path
    if ((Test-Path -LiteralPath (Join-Path $cwd 'team-room')) -and -not $rooms.ContainsKey($cwd.ToLower())) {
        $rooms[$cwd.ToLower()] = [pscustomobject]@{
            Name = (Split-Path $cwd -Leaf); RepoRoot = $cwd; Agent = ''
            TaskName = ''; StateDir = ''; ConfigPath = ''; Installed = $false
        }
    }

    $claimed = @{}
    $out = foreach ($r in $rooms.Values) {
        $task = @($tasks | Where-Object { $_.TaskName -eq $r.TaskName }) | Select-Object -First 1
        $arm  = if ($r.RepoRoot) { Get-TeamRoomArmState -RepoRoot $r.RepoRoot }
                else { [pscustomobject]@{ Armed = $false; Reason = 'no-repo-path'; File = ''; ArmedAt = $null; ArmedBy = $null; DriftMs = $null } }
        # A watcher belongs to this room if its command line names the repo path, OR names
        # the repo's leaf, OR — for a watcher launched with a RELATIVE script path, which is
        # the common case — if this is the repo we are standing in.
        $mine = @($watchers | Where-Object {
            $r.RepoRoot -and (
                $_.CommandLine -match [regex]::Escape($r.RepoRoot) -or
                $_.CommandLine -match [regex]::Escape((Split-Path $r.RepoRoot -Leaf)) -or
                # A watcher launched as `node team-room/bin/teamchat-wait.js` names no repo
                # at all. Testing the whole command line for a drive letter does NOT detect
                # that — the node.exe path is absolute even when the SCRIPT argument is not —
                # so the script token itself is what must be checked.
                ((-not $_.ScriptIsRooted) -and $r.RepoRoot -ieq (Get-Location).Path)
            )
        })
        foreach ($m in $mine) { $claimed[$m.Pid] = $true }

        [pscustomobject]@{
            Name        = $r.Name
            RepoRoot    = $r.RepoRoot
            Agent       = $r.Agent
            TaskName    = $r.TaskName
            TaskState   = if ($task) { $task.State } else { '' }
            TaskLastRun = if ($task) { $task.LastRun } else { $null }
            TaskResult  = if ($task) { $task.LastResult } else { $null }
            TaskNextRun = if ($task) { $task.NextRun } else { $null }
            HasTask     = [bool]$task
            Installed   = $r.Installed
            Armed       = $arm.Armed
            ArmReason   = $arm.Reason
            ArmedAt     = $arm.ArmedAt
            ArmedBy     = $arm.ArmedBy
            ArmFile     = $arm.File
            StateDir    = $r.StateDir
            ConfigPath  = $r.ConfigPath
            Watchers    = @($mine)
            # "Live" means something will actually happen: a ticking task that is armed,
            # or a watcher process sitting in a blocking read. Either alone is not enough
            # for the connector — an armed room with no task fires nothing, and a ticking
            # task with no arm stamp is a deliberate no-op.
            Live        = (($arm.Armed -and $task -and $task.State -ne 'Disabled') -or ($mine.Count -gt 0))
        }
    }

    # A running watcher that no room claimed is still a live agent waker. Hiding it would
    # reproduce the exact problem this command exists to solve, so it gets its own row and
    # can be stopped like any other.
    $out = @($out)
    $orphanWatchers = @($watchers | Where-Object { -not $claimed.ContainsKey($_.Pid) })
    if ($orphanWatchers.Count) {
        $out += [pscustomobject]@{
            Name        = 'unattached'
            RepoRoot    = ''
            Agent       = (@($orphanWatchers.Me | Where-Object { $_ } | Sort-Object -Unique) -join ',')
            TaskName    = ''; TaskState = ''; TaskLastRun = $null; TaskResult = $null; TaskNextRun = $null
            HasTask     = $false
            Installed   = $false
            Armed       = $false
            ArmReason   = 'watcher could not be traced to a repo'
            ArmedAt     = $null; ArmedBy = $null; ArmFile = ''
            StateDir    = ''; ConfigPath = ''
            Watchers    = @($orphanWatchers)
            Live        = $true
        }
    }
    return @($out | Sort-Object @{ Expression = 'Live'; Descending = $true }, Name)
}

# Write or clear the boot-scoped arm stamp. Writing uses the CURRENT boot instant, which
# is what makes the room active now; clearing is the reversible off switch.
function Set-TeamRoomArm {
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][bool]$On, [string]$By = 'powerflow')

    $dir  = Join-Path $RepoRoot 'team-room\state'
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
            # LF + trailing newline: the file is read by Node, and matching teamchat's own
            # atomicJson output keeps a diff clean if the repo tracks it.
            [IO.File]::WriteAllText($file, (($stamp | ConvertTo-Json -Compress) + "`n"))
        } else {
            if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force -ErrorAction Stop }
        }
        return $true
    } catch {
        Write-Host "   $($_.Exception.Message)" -ForegroundColor DarkGray
        return $false
    }
}

# Enable / disable the scheduled task. Deliberately NOT unregister: disabling is
# reversible and keeps the room in the "previously activated, not deleted" set.
function Set-TeamRoomTask {
    param([Parameter(Mandatory)][string]$TaskName, [Parameter(Mandatory)][bool]$Enabled)
    try {
        if ($Enabled) { Enable-ScheduledTask  -TaskName $TaskName -ErrorAction Stop | Out-Null }
        else          { Disable-ScheduledTask -TaskName $TaskName -ErrorAction Stop | Out-Null }
        return $true
    } catch {
        Write-Host "   $($_.Exception.Message)" -ForegroundColor DarkGray
        return $false
    }
}

function Stop-TeamRoomWatcher {
    param([Parameter(Mandatory)][int]$ProcessId)
    try {
        $p = Get-Process -Id $ProcessId -ErrorAction Stop
        # Verify it is still a teamchat watcher before killing: PIDs are reused, and this
        # runs after a confirmation prompt the user may have taken time over.
        $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction SilentlyContinue).CommandLine
        if ("$cmd" -notmatch 'teamchat-wait') { return $false }
        Stop-Process -Id $ProcessId -Force -ErrorAction Stop
        return $true
    } catch { return $false }
}
