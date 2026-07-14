# ==============================================================================
# PowerFlow — Brother Commands
# ==============================================================================
# Domain   : Shell
# File     : components/shell/brothers.ps1
# Purpose  : Full-word twins of cryptic Linux commands. Same flags, same result —
#            but they always tell you the real command, so you learn it as you go.
# Functions: changemode, changeowner, changegroup, defaultmode, listfiles, makelink,
#            fileinfo, firstlines, lastlines, dirsize, diskfree, listdisks, listports,
#            findtext, findfile, whoamifull, mygroups, lookupentry, listprocs,
#            stopproc, service, systemlogs, archive, removefile
# Depends  : Show-Lesson (lessons.ps1), Get-LessonMode (teach.ps1),
#            Get-Umask / Set-Umask (perms adapter)
# ==============================================================================
#
# A brother is NOT a dumbed-down version. It takes the SAME flags and produces the
# SAME result — it simply also prints the real command. You build muscle memory for
# `chmod` while typing `changemode`, and one day you just type `chmod`.
#
# Every brother supports -lesson, which prints the lesson and does nothing else — always
# safe, even on a command that would otherwise delete things. `lesson <command>` does the
# same for ANY command, real name included:  lesson chmod  ·  lesson grep  ·  l rm
# ==============================================================================

# Shared plumbing. Runs the real command and, unless lessons are off, says what it was.
function Invoke-Brother {
    param(
        [Parameter(Mandatory)][string]$Real,     # the real Linux command
        [string[]]$Arguments = @()
    )

    # -lesson (or --lesson): teach, do nothing else.
    if ($Arguments | Where-Object { $_ -match '^--?lesson$' }) {
        Show-Lesson -Command $Real
        return
    }

    if (-not (Get-Command $Real -CommandType Application -ErrorAction SilentlyContinue)) {
        Write-Host "❌ '$Real' is not available on this system." -ForegroundColor Red
        if ($script:PowerFlowOS -ne 'linux') {
            Write-Host "   This is a Linux command. The lesson still works:" -ForegroundColor DarkGray
            Write-Host "   lesson $Real" -ForegroundColor Cyan
        }
        return
    }

    & $Real @Arguments

    $mode = Get-LessonMode
    if ($mode -ne 'off') {
        $shown = ($Arguments -join ' ').Trim()
        Write-Host "  🐧 real linux command: " -NoNewline -ForegroundColor DarkGray
        Write-Host "$Real $shown".Trim() -ForegroundColor Cyan
    }

    # Deliberately return NOTHING. Returning $LASTEXITCODE would emit a bare `0` into
    # the pipeline after every successful command, which pollutes the output and would
    # corrupt anything piping a brother's result onward.
}

# ── Permissions ───────────────────────────────────────────────────────────────
function changemode  { Invoke-Brother -Real 'chmod'  -Arguments $args }
function changeowner { Invoke-Brother -Real 'chown'  -Arguments $args }
function changegroup { Invoke-Brother -Real 'chgrp'  -Arguments $args }

<#
.SYNOPSIS
    defaultmode [mask]  — the umask: which permissions are WITHHELD from new files.
.DESCRIPTION
    umask is NOT a binary — it is a shell builtin, so there is no /usr/bin/umask to run
    and Invoke-Brother cannot handle it. Shelling out to `sh -c 'umask 022'` would set the
    umask of a subshell that then exits, changing nothing. It must be done in-process,
    which is what the perms adapter's Get-Umask / Set-Umask do.
.EXAMPLE
    defaultmode          # show it
    defaultmode 022      # new files 644, new dirs 755
    defaultmode 027      # ...and nothing for "others"
#>
function defaultmode {
    param([string]$Mask)

    if ($args -contains '-lesson' -or $Mask -match '^--?lesson$') {
        Show-Lesson -Command 'umask'
        return
    }

    $current = Get-Umask
    if ($null -eq $current) {
        Write-Host "❌ umask is a POSIX concept — Windows has no equivalent." -ForegroundColor Red
        Write-Host "   New files inherit their ACL from the parent folder instead." -ForegroundColor DarkGray
        Write-Host "   Learn the Linux model anyway:  lesson umask" -ForegroundColor Cyan
        return
    }

    # No argument: report.
    if (-not $Mask) {
        Write-Host "  umask " -NoNewline -ForegroundColor DarkGray
        Write-Host $current -NoNewline -ForegroundColor Cyan
        Write-Host "   → new files $(Get-UmaskResult $current '666'), new dirs $(Get-UmaskResult $current '777')" -ForegroundColor DarkGray
        if ((Get-LessonMode) -ne 'off') {
            Write-Host "  🐧 real linux command: " -NoNewline -ForegroundColor DarkGray
            Write-Host "umask" -ForegroundColor Cyan
        }
        return
    }

    if ($Mask -notmatch '^[0-7]{3,4}$') {
        Write-Host "❌ umask takes an octal mask, e.g. 022 or 027 — got '$Mask'" -ForegroundColor Red
        Write-Host "   lesson umask" -ForegroundColor DarkGray
        return
    }

    $prev = Set-Umask -Mask $Mask
    if ($null -eq $prev) {
        Write-Host "❌ Could not set the umask." -ForegroundColor Red
        return
    }

    Write-Host "  umask " -NoNewline -ForegroundColor DarkGray
    Write-Host $prev -NoNewline -ForegroundColor DarkGray
    Write-Host " → " -NoNewline -ForegroundColor DarkGray
    Write-Host (Get-Umask) -NoNewline -ForegroundColor Green
    Write-Host "   new files $(Get-UmaskResult $Mask '666'), new dirs $(Get-UmaskResult $Mask '777')" -ForegroundColor DarkGray

    if ((Get-LessonMode) -ne 'off') {
        Write-Host "  🐧 real linux command: " -NoNewline -ForegroundColor DarkGray
        Write-Host "umask $Mask" -ForegroundColor Cyan
        Write-Host "  ⚠️  This lasts for THIS shell only. To make it permanent, put it in your profile." -ForegroundColor DarkGray
    }
}

# What a umask actually produces: the base mode with the mask's bits cleared.
# Files start from 666 and directories from 777, then AND-NOT the mask — a umask is
# SUBTRACTIVE, not a permission, which is the thing everyone gets wrong.
#
# $Base is an OCTAL STRING ('666'), not an int. Passing 666 as a number would be 666
# DECIMAL — a completely different bit pattern (0o1232) — and the arithmetic would be
# quietly, plausibly wrong.
function Get-UmaskResult {
    param([string]$Mask, [string]$Base)
    $m = [Convert]::ToInt32($Mask, 8)
    $b = [Convert]::ToInt32($Base, 8)
    return ([Convert]::ToString(($b -band (-bnot $m)) -band 0x1FF, 8)).PadLeft(3, '0')
}

# ── Identity ──────────────────────────────────────────────────────────────────
function whoamifull  { Invoke-Brother -Real 'id'     -Arguments $args }
function mygroups    { Invoke-Brother -Real 'groups' -Arguments $args }
function lookupentry { Invoke-Brother -Real 'getent' -Arguments $args }

# ── Files ─────────────────────────────────────────────────────────────────────
function findfile    { Invoke-Brother -Real 'find'   -Arguments $args }
function findtext    { Invoke-Brother -Real 'grep'   -Arguments $args }
function removefile  { Invoke-Brother -Real 'rm'     -Arguments $args }
function archive     { Invoke-Brother -Real 'tar'    -Arguments $args }

function makelink    { Invoke-Brother -Real 'ln'     -Arguments $args }
function fileinfo    { Invoke-Brother -Real 'stat'   -Arguments $args }

# ── Text ──────────────────────────────────────────────────────────────────────
function firstlines  { Invoke-Brother -Real 'head'   -Arguments $args }
function lastlines   { Invoke-Brother -Real 'tail'   -Arguments $args }

# ── Disk ──────────────────────────────────────────────────────────────────────
function dirsize     { Invoke-Brother -Real 'du'     -Arguments $args }
function diskfree    { Invoke-Brother -Real 'df'     -Arguments $args }
function listdisks   { Invoke-Brother -Real 'lsblk'  -Arguments $args }

# ── Network ───────────────────────────────────────────────────────────────────
function listports   { Invoke-Brother -Real 'ss'     -Arguments $args }

# ── Processes ─────────────────────────────────────────────────────────────────
function listprocs   { Invoke-Brother -Real 'ps'         -Arguments $args }
function stopproc    { Invoke-Brother -Real 'kill'       -Arguments $args }
function service     { Invoke-Brother -Real 'systemctl'  -Arguments $args }
function systemlogs  { Invoke-Brother -Real 'journalctl' -Arguments $args }

# ── listfiles: the one exception ──────────────────────────────────────────────
# `ls` IS PowerFlow's own (pretty, lsd-backed, GNU-flag-compatible), so listfiles
# routes to it rather than shelling out to /bin/ls.
function listfiles {
    if ($args | Where-Object { $_ -match '^--?lesson$' }) {
        Show-Lesson -Command 'ls'
        return
    }
    ls @args
}

# ── PowerFlow DOES NOT WRAP THE REAL COMMAND NAMES. That is deliberate. ───────
#
# An earlier version defined a function for each real command (`chmod`, `grep`, `tar`, …)
# so that `chmod -lesson` would work. It was removed, because a PowerShell function is not
# a transparent stand-in for a binary:
#
#   • It does not forward stdin, so `cat access.log | grep ERROR` would start the native
#     grep with no input and hang on the console — a hang, not an error.
#   • grep/rm/cp/cat therefore had to be denylisted, which meant the commands a beginner
#     most needs were precisely the ones that could not have a lesson.
#   • It needed a CI backstop to catch anyone reintroducing one.
#
# `lesson <command>` (lessons.ps1) replaces all of it. It shadows nothing, so it works for
# every command — grep and rm included — and there is no failure mode to guard.
#
# Brothers keep -lesson, because a brother name is not a real command and shadows nothing:
#   changemode -lesson   ·   findtext -lesson
#
# If you are ever tempted to add `function chmod { ... }` here: don't. Add a lesson to
# $script:PF_Lessons instead and `lesson chmod` picks it up for free.
