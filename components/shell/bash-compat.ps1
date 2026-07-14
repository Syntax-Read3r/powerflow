# ==============================================================================
# PowerFlow — Bash Compatibility
# ==============================================================================
# Domain   : Shell
# File     : components/shell/bash-compat.ps1
# Purpose  : The bash builtins PowerShell lacks, so you never have to leave PowerFlow
# Functions: export, unset, source, alias, unalias, jobs, fg, bg, bash-h
# Depends   : none
# ==============================================================================
#
# WHAT ALREADY WORKS IN POWERSHELL 7 (do not reinvent):
#   &&  ||  |  >  >>  2>  $( )  globbing  &  (background)
#
# WHAT DOES NOT, AND IS BUILT HERE:
#   export VAR=value      PowerShell wants  $env:VAR = 'value'
#   alias ll='ls -la'     Set-Alias CANNOT carry arguments — a real limitation
#   unset VAR             no equivalent
#   source file           PowerShell uses  . file
#   jobs / fg / bg        PowerShell has Get-Job/Receive-Job with different names
#
# WHAT CANNOT BE FIXED HERE (they are parser-level, not commands):
#   brace expansion {1..5}, {a,b}      · heredocs <<EOF
#   Use PowerShell's own: 1..5  ·  @('a','b')  ·  @' ... '@
# ==============================================================================

# ── export ────────────────────────────────────────────────────────────────────
<#
.SYNOPSIS
    export VAR=value  — set an environment variable, bash-style.
.EXAMPLE
    export EDITOR=vim
    export PATH="$PATH:/opt/bin"
    export                      # list all, like bash
#>
function export {
    if (-not $args -or $args.Count -eq 0) {
        Get-ChildItem Env: | Sort-Object Name | ForEach-Object {
            Write-Host "declare -x " -NoNewline -ForegroundColor DarkGray
            Write-Host "$($_.Name)=" -NoNewline -ForegroundColor Cyan
            Write-Host "`"$($_.Value)`"" -ForegroundColor White
        }
        return
    }

    foreach ($a in $args) {
        $pair = [string]$a
        if ($pair -notmatch '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
            Write-Host "❌ export: not a valid assignment: $pair" -ForegroundColor Red
            Write-Host "   usage: export NAME=value" -ForegroundColor DarkGray
            continue
        }

        $name  = $matches[1]
        $value = $matches[2].Trim('"').Trim("'")

        # Set-Item on the Env: drive, NOT [Environment]::SetEnvironmentVariable.
        # The latter is banned in components/ because its User/Machine scopes are
        # registry-backed on Windows — that is what the env adapter is for. This is a
        # plain process-scoped variable, and Env: is the platform-agnostic way to set it.
        Set-Item -Path "Env:\$name" -Value $value
        Write-Verbose "export $name=$value"
    }
}

# ── unset ─────────────────────────────────────────────────────────────────────
function unset {
    foreach ($a in $args) {
        $name = [string]$a
        if (Test-Path "Env:\$name") {
            Remove-Item "Env:\$name" -Force
        }
        elseif (Test-Path "Variable:\$name") {
            Remove-Variable $name -Scope Global -Force -ErrorAction SilentlyContinue
        }
    }
}

# ── source ────────────────────────────────────────────────────────────────────
<#
.SYNOPSIS
    source file  — run a script in the CURRENT scope (bash's `source` / `.`).
.DESCRIPTION
    Sourcing a .sh file cannot work: PowerShell cannot execute bash syntax. But a
    .sh that only contains KEY=value lines (a .env file, in effect) is by far the most
    common case, so those are parsed and exported rather than failing outright.
#>
function source {
    param([Parameter(Mandatory)][string]$File)

    if (-not (Test-Path -LiteralPath $File)) {
        Write-Host "❌ source: no such file: $File" -ForegroundColor Red
        return
    }

    if ($File -match '\.ps1$') {
        . $File
        return
    }

    # A .sh / .env full of KEY=value. Parse what we safely can.
    $set = 0
    foreach ($line in (Get-Content -LiteralPath $File)) {
        $l = $line.Trim()
        if (-not $l -or $l.StartsWith('#')) { continue }
        $l = $l -replace '^export\s+', ''
        if ($l -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
            $v = $matches[2].Trim().Trim('"').Trim("'")
            Set-Item -Path "Env:\$($matches[1])" -Value $v
            $set++
        }
    }

    if ($set -gt 0) {
        Write-Host "✅ sourced $set variable(s) from $File" -ForegroundColor Green
    } else {
        Write-Host "⚠️  source: nothing to import from $File" -ForegroundColor Yellow
        Write-Host "   PowerShell cannot execute bash syntax — only KEY=value lines are read." -ForegroundColor DarkGray
    }
}

# ── alias / unalias ───────────────────────────────────────────────────────────
#
# THE REASON THIS EXISTS: PowerShell's Set-Alias maps one name to one COMMAND. It
# cannot carry arguments, so `Set-Alias ll 'ls -la'` is impossible — the single most
# common thing anyone does with an alias in bash.
#
# So bash-style aliases are compiled into FUNCTIONS, which can.
$script:PF_BashAliases = @{}

<#
.SYNOPSIS
    alias name='command args'  — a bash alias, arguments and all.
.EXAMPLE
    alias ll='ls -la'
    alias gs='git status'
    alias                       # list all
#>
function alias {
    if (-not $args -or $args.Count -eq 0) {
        if ($script:PF_BashAliases.Count -eq 0) {
            Write-Host "ℹ️  No aliases defined." -ForegroundColor DarkGray
            return
        }
        $script:PF_BashAliases.GetEnumerator() | Sort-Object Name | ForEach-Object {
            Write-Host "alias " -NoNewline -ForegroundColor DarkGray
            Write-Host "$($_.Key)=" -NoNewline -ForegroundColor Cyan
            Write-Host "'$($_.Value)'" -ForegroundColor White
        }
        return
    }

    # Rejoin: PowerShell splits `alias ll='ls -la'` on the spaces inside the quotes.
    $spec = ($args -join ' ')

    if ($spec -notmatch "^([A-Za-z_][\w\-\.]*)=(.+)$") {
        Write-Host "❌ alias: usage: alias name='command args'" -ForegroundColor Red
        return
    }

    $name = $matches[1]
    $body = $matches[2].Trim().Trim('"').Trim("'")

    if ($name -in @('rm','mv','cp','cat','ls','chmod','chown','sudo')) {
        Write-Host "⚠️  Refusing to alias '$name' — it would shadow a core command." -ForegroundColor Yellow
        return
    }

    # Compile to a function so arguments actually work, and forward @args so
    # `ll /tmp` becomes `ls -la /tmp`.
    $script:PF_BashAliases[$name] = $body
    $fn = "function global:$name { $body @args }"
    Invoke-Expression $fn

    Write-Host "✅ alias $name=" -NoNewline -ForegroundColor Green
    Write-Host "'$body'" -ForegroundColor White
}

function unalias {
    foreach ($a in $args) {
        $name = [string]$a
        if ($script:PF_BashAliases.ContainsKey($name)) {
            $script:PF_BashAliases.Remove($name)
            Remove-Item "Function:\global:$name" -Force -ErrorAction SilentlyContinue
            Write-Host "✅ unalias $name" -ForegroundColor Green
        }
        elseif (Test-Path "Alias:\$name") {
            Remove-Item "Alias:\$name" -Force
            Write-Host "✅ unalias $name" -ForegroundColor Green
        }
        else {
            Write-Host "❌ unalias: $name not found" -ForegroundColor Red
        }
    }
}

# ── jobs / fg / bg ────────────────────────────────────────────────────────────
#
# PowerShell 7 supports `command &` to background a job — it just calls the result a
# PSJob and gives you different verbs. Map bash's names onto them.
function jobs {
    $all = Get-Job
    if (-not $all) { Write-Host "ℹ️  No jobs." -ForegroundColor DarkGray; return }

    Write-Host ""
    Write-Host "  ID   STATE       COMMAND" -ForegroundColor DarkGray
    foreach ($j in $all) {
        $colour = switch ($j.State) {
            'Running'   { 'Yellow' }
            'Completed' { 'Green' }
            'Failed'    { 'Red' }
            default     { 'DarkGray' }
        }
        Write-Host ("  {0,-4} {1,-11} {2}" -f $j.Id, $j.State, $j.Command) -ForegroundColor $colour
    }
    Write-Host ""
    Write-Host "  fg <id>   bring to foreground (wait + show output)" -ForegroundColor DarkGray
    Write-Host "  bg <id>   leave running in the background" -ForegroundColor DarkGray
    Write-Host ""
}

<#
.SYNOPSIS
    fg [id]  — bring a background job to the foreground and wait for it.
#>
function fg {
    param([int]$Id)

    $job = if ($Id) { Get-Job -Id $Id -ErrorAction SilentlyContinue }
           else     { Get-Job | Where-Object { $_.State -eq 'Running' } | Select-Object -Last 1 }

    if (-not $job) { Write-Host "❌ fg: no such job" -ForegroundColor Red; return }

    Write-Host "▶️  $($job.Command)" -ForegroundColor Cyan
    Receive-Job -Job $job -Wait -AutoRemoveJob
}

<#
.SYNOPSIS
    bg [id]  — report a job left running in the background.
#>
function bg {
    param([int]$Id)

    $job = if ($Id) { Get-Job -Id $Id -ErrorAction SilentlyContinue }
           else     { Get-Job | Select-Object -Last 1 }

    if (-not $job) { Write-Host "❌ bg: no such job" -ForegroundColor Red; return }

    Write-Host "⏸️  [$($job.Id)] $($job.Command) — running in the background" -ForegroundColor Yellow
    Write-Host "   fg $($job.Id)  to bring it back" -ForegroundColor DarkGray
}
