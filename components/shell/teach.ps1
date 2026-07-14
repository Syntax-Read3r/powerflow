# ==============================================================================
# PowerFlow — Linux Teaching Layer
# ==============================================================================
# Domain   : Shell
# File     : components/shell/teach.ps1
# Purpose  : Explain Linux permissions while you use them, then get out of the way
# Functions: linux-lessons, Show-PermissionBreakdown, Format-ModeColons,
#            Get-LessonMode, Show-Lesson, perms
# Depends  : Get-FileMode, Test-PermsSupported (platform/<os>/adapters/perms.ps1)
# ==============================================================================
#
# Three levels, because "beginner" is a moving target:
#
#   full   column diagram + numeric + the real command + tips   (default on Linux)
#   hint   one line: "🐧 real linux command: chmod u+w ward-a"
#   off    nothing. Byte-identical to GNU.
#
# Persisted to config/PowerFlow.settings.ps1, so it survives restarts.
# ==============================================================================

function Get-LessonMode {
    if ($script:LINUX_LESSON_MODE) { return $script:LINUX_LESSON_MODE }
    # Nobody on Windows is learning chmod.
    return $(if ($script:PowerFlowOS -eq 'linux') { 'full' } else { 'off' })
}

<#
.SYNOPSIS
    linux-lessons full|hint|off  — how much Linux teaching to show.
.EXAMPLE
    linux-lessons          # show the current mode
    linux-lessons full     # column diagrams + numeric + tips
    linux-lessons hint     # one-line reminders only
    linux-lessons off      # nothing. Identical to GNU.
#>
function linux-lessons {
    param([ValidateSet('full', 'hint', 'off', '')][string]$Mode = '')

    if (-not $Mode) {
        $current = Get-LessonMode
        Write-Host ""
        Write-Host "  🎓 Linux lessons: " -NoNewline -ForegroundColor Cyan
        Write-Host $current -ForegroundColor Yellow
        Write-Host ""
        Write-Host "     full   column diagrams + numeric + real command + tips" -ForegroundColor DarkGray
        Write-Host "     hint   one-line reminder of the real Linux command" -ForegroundColor DarkGray
        Write-Host "     off    nothing — identical to GNU output" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "     linux-lessons off" -ForegroundColor Yellow
        Write-Host ""
        return
    }

    $script:LINUX_LESSON_MODE = $Mode

    # Persist, so it survives a restart.
    $settings = Join-Path $script:PowerFlowRoot 'config/PowerFlow.settings.ps1'
    if (Test-Path $settings) {
        $raw = Get-Content $settings -Raw
        if ($raw -match '\$script:LINUX_LESSON_MODE\s*=\s*"[^"]*"') {
            $raw = $raw -replace '\$script:LINUX_LESSON_MODE\s*=\s*"[^"]*"',
                                 "`$script:LINUX_LESSON_MODE = `"$Mode`""
        } else {
            $raw = $raw.TrimEnd() + "`n`n# How much Linux teaching to show: full | hint | off`n" +
                   "`$script:LINUX_LESSON_MODE = `"$Mode`"`n"
        }
        Set-Content $settings $raw -Encoding UTF8
    }

    Write-Host "🎓 Linux lessons: $Mode" -ForegroundColor Green
    if ($Mode -eq 'off') {
        Write-Host "   Turn them back on any time:  linux-lessons full" -ForegroundColor DarkGray
    }
}

# ── The colon format ──────────────────────────────────────────────────────────
# drwxr-xr-x  ->  d : rwx : r-x : r-x
# The three triads are the entire point, and the conventional form runs them together.
function Format-ModeColons {
    param([Parameter(Mandatory)][string]$Symbolic)

    if ($Symbolic.Length -lt 10) { return $Symbolic }

    $type   = $Symbolic.Substring(0, 1)
    $owner  = $Symbolic.Substring(1, 3)
    $group  = $Symbolic.Substring(4, 3)
    $others = $Symbolic.Substring(7, 3)

    return "$type : $owner : $group : $others"
}

# Turn "rwx" into "read + write + enter" (or "+ execute" for a file).
function Expand-Triad {
    param([string]$Triad, [switch]$IsDirectory)

    $parts = @()
    if ($Triad[0] -eq 'r') { $parts += 'read' }
    if ($Triad[1] -eq 'w') { $parts += 'write' }
    if ($Triad[2] -eq 'x') { $parts += $(if ($IsDirectory) { 'enter' } else { 'execute' }) }

    if ($parts.Count -eq 0) { return 'nothing' }
    return ($parts -join ' + ')
}

<#
.SYNOPSIS
    The annotated permission breakdown for a path.
.DESCRIPTION
    The teaching centrepiece. Shows WHICH COLUMN IS WHICH — the thing that is genuinely
    hard to remember when you first meet `drwxr-xr-x 2 munya media`.
#>
function Show-PermissionBreakdown {
    param(
        [Parameter(Mandatory)]$Mode,
        [string]$RealCommand
    )

    $isDir  = $Mode.Type -eq 'd'
    $colons = Format-ModeColons $Mode.Symbolic
    $size   = if ($Mode.Size -ge 1GB) { '{0:N1}G' -f ($Mode.Size/1GB) }
              elseif ($Mode.Size -ge 1MB) { '{0:N1}M' -f ($Mode.Size/1MB) }
              elseif ($Mode.Size -ge 1KB) { '{0:N1}K' -f ($Mode.Size/1KB) }
              else { "$($Mode.Size)" }
    $when = $Mode.Modified.ToString('MMM dd HH:mm')

    Write-Host ""
    Write-Host "  $colons" -NoNewline -ForegroundColor Cyan
    Write-Host ("   {0}   {1}   {2}   {3}   {4}   {5}" -f `
                $Mode.Links, $Mode.User, $Mode.GroupName, $size, $when, $Mode.Name) -ForegroundColor White

    # The column ruler. This is the bit that actually teaches.
    Write-Host "  ╷    ╷     ╷     ╷    ╷     ╷       ╷" -ForegroundColor DarkGray
    Write-Host "  │    │     │     │    │     │       └── GROUP  · members of '$($Mode.GroupName)'" -ForegroundColor DarkGray
    Write-Host "  │    │     │     │    │     └── OWNER  · the user who owns it" -ForegroundColor DarkGray
    Write-Host "  │    │     │     │    └── hard links" -ForegroundColor DarkGray

    $typeName = switch ($Mode.Type) {
        'd' { 'directory' } '-' { 'file' } 'l' { 'symlink' }
        'c' { 'char device' } 'b' { 'block device' }
        's' { 'socket' } 'p' { 'named pipe' } default { 'unknown' }
    }

    Write-Host "  │    │     │     └── others · $($Mode.Others) = $(Expand-Triad $Mode.Others -IsDirectory:$isDir)" -ForegroundColor DarkGray
    Write-Host "  │    │     └── group  · $($Mode.Group) = $(Expand-Triad $Mode.Group -IsDirectory:$isDir)" -ForegroundColor DarkGray
    Write-Host "  │    └── owner  · $($Mode.Owner) = $(Expand-Triad $Mode.Owner -IsDirectory:$isDir)" -ForegroundColor DarkGray
    Write-Host "  └── type · $($Mode.Type) = $typeName" -ForegroundColor DarkGray

    Write-Host ""
    Write-Host "  🔢 numeric : $($Mode.Numeric)" -NoNewline -ForegroundColor Yellow
    Write-Host "          chmod $($Mode.Numeric) $($Mode.Name)" -ForegroundColor DarkGray

    if ($RealCommand) {
        Write-Host "  🐧 real linux command : " -NoNewline -ForegroundColor Green
        Write-Host $RealCommand -ForegroundColor White
    }

    if ($isDir) {
        Write-Host "  💡 On a DIRECTORY, x means 'may enter', not 'may run'." -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "  (hide these:  linux-lessons off)" -ForegroundColor DarkGray
    Write-Host ""
}

<#
.SYNOPSIS
    perms <path>  — show, and explain, a path's permissions.
.EXAMPLE
    perms ward-a
    perms /etc/passwd
#>
function perms {
    param([Parameter(Position = 0)][string]$Path = '.')

    if (-not (Test-PermsSupported)) {
        Write-Host ""
        Write-Host "  ℹ️  Windows has no POSIX permissions." -ForegroundColor Yellow
        Write-Host "     It uses ACLs — a different, richer model. There is no honest" -ForegroundColor DarkGray
        Write-Host "     mapping from rwxr-xr-x to an ACL, so PowerFlow will not invent one." -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "     Windows equivalent :  icacls `"$Path`"" -ForegroundColor Cyan
        Write-Host "     Learn the Linux model anyway :  lesson chmod" -ForegroundColor Cyan
        Write-Host ""
        return
    }

    $mode = Get-FileMode -Path $Path
    if (-not $mode) {
        Write-Host "❌ No such file or directory: $Path" -ForegroundColor Red
        return
    }

    $lesson = Get-LessonMode
    if ($lesson -eq 'off') {
        Write-Host ("{0}  {1}  {2}  {3}  {4}" -f $mode.Symbolic, $mode.Links, $mode.User, $mode.GroupName, $mode.Name)
        return
    }
    if ($lesson -eq 'hint') {
        Write-Host ("  {0}   {1}   {2}   {3}   {4}" -f `
            (Format-ModeColons $mode.Symbolic), $mode.User, $mode.GroupName, $mode.Numeric, $mode.Name) -ForegroundColor White
        Write-Host "  🐧 real linux command : ls -ld $Path" -ForegroundColor DarkGray
        return
    }

    Show-PermissionBreakdown -Mode $mode -RealCommand "ls -ld $Path"
}
