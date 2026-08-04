# ==============================================================================
# PowerFlow — Team Room
# ==============================================================================
# Domain   : System
# File     : components/system/team-room.ps1
# Purpose  : team-room — see which agent watchers are live, stop them, and re-arm
#            a room that was set up earlier
# Functions: team-room, Show-TeamRoomList, Show-TeamRoomDetail, Invoke-TeamRoomAction
# Depends  : team-room adapter (platform/<os>/adapters/team-room.ps1)
# ==============================================================================
#
# WHY THIS EXISTS
#
# team-room wakes AI agents in the background: a scheduled connector that ticks every few
# minutes, and one-shot watcher processes. Both are invisible from the shell. Until now the
# only way to stop one was to ASK AN AGENT to stop it — which means the off switch depended
# on the very thing being switched off.
#
# On the machine this was built against, four connector tasks and a live watcher were
# running with no way to see or stop them from a prompt.
#
# THREE STATES, NOT ONE
#
# A room is not simply on or off. It has:
#   armed    the boot-scoped stamp the connector checks (fails closed after a reboot)
#   task     the scheduled connector — Ready / Disabled / Running / absent
#   watcher  a live one-shot `node teamchat-wait.js` process
#
# Any combination is possible and each means something different, so all three are shown.
# Armed with no task fires nothing. A task with no arm stamp ticks and deliberately does
# nothing. The command says which, rather than collapsing it into a lie.
#
# DISARM IS THE OFF SWITCH. It is the toolkit's own dormancy path and is instantly
# reversible; disabling the task is offered separately as the heavier hammer.
# ==============================================================================

function Format-TeamRoomAge {
    param($When)
    if (-not $When) { return '' }
    try { $span = (Get-Date) - [datetime]$When } catch { return '' }
    if ($span.Ticks -lt 0) { return '' }
    if ($span.TotalDays -ge 1)  { return ('{0}d ago' -f [int][math]::Floor($span.TotalDays)) }
    if ($span.TotalHours -ge 1) { return ('{0}h ago' -f [int][math]::Floor($span.TotalHours)) }
    return ('{0}m ago' -f [int][math]::Floor($span.TotalMinutes))
}

function Show-TeamRoomList {
    param($Rooms)

    Write-Host ''
    $live = @($Rooms | Where-Object Live).Count
    Write-Host "🤝 TEAM ROOMS — $live live of $(@($Rooms).Count)" -ForegroundColor Cyan
    Write-Host '──────────────────────────────────────────────────────────────────────────' -ForegroundColor DarkGray

    if (-not @($Rooms).Count) {
        Write-Host '  No team rooms found on this machine.' -ForegroundColor DarkGray
        Write-Host '  A room appears once its wake connector is installed or a watcher runs.' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    $w = (@($Rooms).Name | Measure-Object -Maximum Length).Maximum + 2
    foreach ($r in $Rooms) {
        $dot = if ($r.Live) { '●' } else { '○' }
        Write-Host ('  {0} ' -f $dot) -NoNewline -ForegroundColor $(if ($r.Live) { 'Green' } else { 'DarkGray' })
        Write-Host ($r.Name.PadRight($w)) -NoNewline -ForegroundColor $(if ($r.Live) { 'White' } else { 'DarkGray' })

        # armed
        if ($r.Armed) { Write-Host 'armed    ' -NoNewline -ForegroundColor Green }
        else          { Write-Host ('{0,-9}' -f $r.ArmReason.Replace('never-armed-this-boot', 'disarmed')) -NoNewline -ForegroundColor DarkGray }

        # task
        if ($r.HasTask) {
            $tc = switch ($r.TaskState) { 'Running' { 'Yellow' } 'Disabled' { 'DarkGray' } default { 'White' } }
            Write-Host ('task:{0,-9}' -f $r.TaskState) -NoNewline -ForegroundColor $tc
        } else { Write-Host ('{0,-14}' -f 'no task') -NoNewline -ForegroundColor DarkGray }

        # watchers
        $wc = @($r.Watchers).Count
        if ($wc) { Write-Host ("{0} watcher{1}" -f $wc, $(if ($wc -eq 1) { '' } else { 's' })) -NoNewline -ForegroundColor Green }
        else     { Write-Host 'no watcher' -NoNewline -ForegroundColor DarkGray }

        if ($r.TaskLastRun) { Write-Host ("   ran {0}" -f (Format-TeamRoomAge $r.TaskLastRun)) -NoNewline -ForegroundColor DarkGray }
        Write-Host ''
    }

    Write-Host ''
    Write-Host '  ● live = something will actually happen · ○ = present but inert' -ForegroundColor DarkGray
    Write-Host '  team-room <name>        one room in detail' -ForegroundColor DarkGray
    Write-Host '  team-room stop <name>   disarm it (reversible) · -All also stops watchers' -ForegroundColor DarkGray
    Write-Host '  team-room start <name>  re-arm a room that is already set up' -ForegroundColor DarkGray
    Write-Host ''
}

function Show-TeamRoomDetail {
    param($Room)

    Write-Host ''
    Write-Host "🤝 $($Room.Name)" -ForegroundColor Cyan
    Write-Host '──────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
    Write-Host ('  {0,-12}' -f 'Repo') -NoNewline -ForegroundColor DarkGray
    Write-Host $(if ($Room.RepoRoot) { $Room.RepoRoot } else { '(unknown — task has no config)' }) -ForegroundColor White

    Write-Host ('  {0,-12}' -f 'Armed') -NoNewline -ForegroundColor DarkGray
    if ($Room.Armed) {
        Write-Host "yes — $($Room.ArmedAt) by $($Room.ArmedBy)" -ForegroundColor Green
    } else {
        Write-Host "no — $($Room.ArmReason)" -ForegroundColor Yellow
        if ($Room.ArmReason -eq 'armed-in-previous-boot') {
            Write-Host '               (the stamp is boot-scoped, so a reboot disarms it by design)' -ForegroundColor DarkGray
        }
    }

    Write-Host ('  {0,-12}' -f 'Connector') -NoNewline -ForegroundColor DarkGray
    if ($Room.HasTask) {
        Write-Host "$($Room.TaskName) — $($Room.TaskState)" -ForegroundColor White
        Write-Host ('  {0,-12}' -f 'Last run') -NoNewline -ForegroundColor DarkGray
        Write-Host "$($Room.TaskLastRun) (result $($Room.TaskResult)) · next $($Room.TaskNextRun)" -ForegroundColor DarkGray
        if (-not $Room.Installed) {
            Write-Host '               ⚠️  no config dir — the teamchat CLI cannot status or uninstall this task' -ForegroundColor Yellow
        }
    } else {
        Write-Host 'none registered' -ForegroundColor DarkGray
    }

    Write-Host ('  {0,-12}' -f 'Watchers') -NoNewline -ForegroundColor DarkGray
    if (@($Room.Watchers).Count) {
        Write-Host "$(@($Room.Watchers).Count) running" -ForegroundColor Green
        foreach ($wtch in @($Room.Watchers)) {
            Write-Host ("     PID {0,-8} as {1,-14} {2}" -f $wtch.Pid, $(if ($wtch.Me) { $wtch.Me } else { '?' }), (Format-TeamRoomAge $wtch.Started)) -ForegroundColor DarkGray
        }
    } else { Write-Host 'none' -ForegroundColor DarkGray }

    # The single most useful line: what will actually happen next.
    Write-Host ''
    if ($Room.Live) {
        Write-Host '  ● LIVE — this room can wake an agent.' -ForegroundColor Green
        Write-Host "     Stop it:  team-room stop $($Room.Name)" -ForegroundColor DarkGray
    } elseif ($Room.HasTask -and -not $Room.Armed) {
        Write-Host '  ○ Inert — the connector ticks but is disarmed, so every tick is a no-op.' -ForegroundColor DarkGray
        Write-Host "     Re-arm:   team-room start $($Room.Name)" -ForegroundColor DarkGray
    } elseif ($Room.Armed -and -not $Room.HasTask) {
        Write-Host '  ○ Armed, but no connector is registered — nothing will fire.' -ForegroundColor Yellow
    } else {
        Write-Host '  ○ Inert.' -ForegroundColor DarkGray
    }
    Write-Host ''
}

function Invoke-TeamRoomAction {
    param([Parameter(Mandatory)]$Room, [Parameter(Mandatory)][ValidateSet('start', 'stop')][string]$Action, [switch]$All)

    if ($Action -eq 'start') {
        if (-not $Room.RepoRoot) {
            Write-Host "❌ '$($Room.Name)' has no repo path — it is a task with no config, so there is nothing to arm." -ForegroundColor Red
            Write-Host ''
            return
        }
        Write-Host ''
        if (Set-TeamRoomArm -RepoRoot $Room.RepoRoot -On $true -By 'powerflow-team-room') {
            Write-Host "✅ $($Room.Name) armed for this boot." -ForegroundColor Green
            if (-not $Room.HasTask) {
                Write-Host '   Note: no wake connector is registered, so nothing will fire on a schedule.' -ForegroundColor Yellow
            } elseif ($Room.TaskState -eq 'Disabled') {
                Write-Host "   Note: the connector task is Disabled. Enable it with: team-room start $($Room.Name) -All" -ForegroundColor Yellow
            }
            if ($All -and $Room.HasTask -and $Room.TaskState -eq 'Disabled') {
                if (Set-TeamRoomTask -TaskName $Room.TaskName -Enabled $true) { Write-Host "   ✅ connector task enabled." -ForegroundColor Green }
            }
        } else { Write-Host "❌ Could not arm $($Room.Name)." -ForegroundColor Red }
        Write-Host ''
        return
    }

    # ── stop ──────────────────────────────────────────────────────────────────
    Write-Host ''
    Write-Host "🛑 Stopping $($Room.Name)" -ForegroundColor Yellow
    $did = @()

    if ($Room.Armed) {
        if (Set-TeamRoomArm -RepoRoot $Room.RepoRoot -On $false) {
            $did += 'disarmed (the connector will now no-op on every tick)'
        } else { Write-Host '   ⚠️  could not remove the arm stamp' -ForegroundColor Yellow }
    }

    foreach ($wtch in @($Room.Watchers)) {
        if (Stop-TeamRoomWatcher -ProcessId $wtch.Pid) { $did += "stopped watcher PID $($wtch.Pid)" }
        else { Write-Host "   ⚠️  could not stop PID $($wtch.Pid) (it may have already exited)" -ForegroundColor Yellow }
    }

    # -All is the heavier hammer: it also disables the scheduled connector. Kept separate
    # because disarming is enough to make a room inert, and is reversible in one command.
    if ($All -and $Room.HasTask -and $Room.TaskState -ne 'Disabled') {
        if (Set-TeamRoomTask -TaskName $Room.TaskName -Enabled $false) { $did += "disabled connector task $($Room.TaskName)" }
    }

    if ($did.Count) { foreach ($d in $did) { Write-Host "   ✅ $d" -ForegroundColor Green } }
    else { Write-Host '   Nothing to stop — it was already inert.' -ForegroundColor DarkGray }

    if (-not $All -and $Room.HasTask -and $Room.TaskState -ne 'Disabled') {
        Write-Host "   The connector task is still registered and ticking (harmlessly, while disarmed)." -ForegroundColor DarkGray
        Write-Host "   Disable it too:  team-room stop $($Room.Name) -All" -ForegroundColor DarkGray
    }
    Write-Host ''
}

<#
.SYNOPSIS
    team-room — see which agent watchers are live, stop them, and re-arm a room.
.DESCRIPTION
    team-room                 every room on this machine, with its three live states
    team-room <name>          one room in detail
    team-room start <name>    re-arm a room that is already set up (-All also enables its task)
    team-room stop <name>     disarm it and stop its watchers (-All also disables its task)

    Disarming is the reversible off switch: the connector keeps ticking but does nothing,
    which is team-room's own dormancy path.
#>
function team-room {
    param(
        [Parameter(Position = 0)][string]$Command,
        [Parameter(Position = 1)][string]$Name,
        [switch]$All
    )

    $rooms = @(Get-TeamRoomState)

    # `team-room <name>` with no verb is a detail view, so a room called "stop" cannot be
    # reached by accident — verbs are checked first and explicitly.
    $verb = $Command.ToLower()
    if ($verb -notin @('', 'start', 'stop', 'list', 'help', '-h', '--help')) {
        $Name = $Command; $verb = ''
    }

    if ($verb -in @('help', '-h', '--help')) {
        Write-Host ''
        Write-Host '🤝 team-room — control the agent watchers' -ForegroundColor Cyan
        Write-Host '  team-room                  every room, with armed / task / watcher state' -ForegroundColor White
        Write-Host '  team-room <name>           one room in detail' -ForegroundColor White
        Write-Host '  team-room start <name>     re-arm a room that is already set up' -ForegroundColor White
        Write-Host '  team-room stop <name>      disarm it and stop its watchers' -ForegroundColor White
        Write-Host '  -All                       also enable/disable the scheduled connector' -ForegroundColor White
        Write-Host ''
        return
    }

    if ($verb -in @('start', 'stop')) {
        if (-not $Name) {
            Write-Host "❌ Which room? e.g. team-room $verb $(if ($rooms.Count) { $rooms[0].Name } else { '<name>' })" -ForegroundColor Red
            return
        }
        $hits = @($rooms | Where-Object { $_.Name -ieq $Name })
        if ($hits.Count -ne 1) {
            if ($hits.Count -eq 0) { Write-Host "❌ No team room called '$Name'." -ForegroundColor Red }
            else { Write-Host "❌ '$Name' matches $($hits.Count) rooms." -ForegroundColor Red }
            Show-TeamRoomList $rooms
            return
        }
        Invoke-TeamRoomAction -Room $hits[0] -Action $verb -All:$All
        return
    }

    if ($Name) {
        $hits = @($rooms | Where-Object { $_.Name -ieq $Name })
        if ($hits.Count -eq 1) { Show-TeamRoomDetail $hits[0]; return }
        Write-Host "❌ No team room called '$Name'." -ForegroundColor Red
    }

    Show-TeamRoomList $rooms
}

Register-PFCommand -Name 'team-room' -Section '🖥️ MACHINE HEALTH' `
    -Synopsis 'see which agent watchers are live; stop or re-arm a room' `
    -Example 'team-room · team-room stop zavoya · team-room start zavoya'
