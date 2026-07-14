# ==============================================================================
# PowerFlow — Bash History Expansion
# ==============================================================================
# Domain   : Shell
# File     : components/shell/history.ps1
# Purpose  : !! and !$ history expansion, and a bash-shaped `history` command
# Functions: history, Get-LastCommand, Get-LastArg
# Depends  : PSReadLine (ships with PowerShell)
# ==============================================================================
#
# `sudo !!` is pure muscle memory — you type it before you think. PowerShell has no
# history expansion at all, so it fails with a parser error.
#
# It CANNOT be done as a function: `!!` is expanded by bash's PARSER, before any
# command runs. PowerShell's parser has no such hook. The honest solution is a
# PSReadLine key handler that rewrites the line IN PLACE as you type it — so you see
# exactly what will run before you press Enter. That is arguably better than bash,
# where `!!` expands invisibly.
# ==============================================================================

# The last command actually typed (skipping the expansion itself).
function Get-LastCommand {
    $h = Get-History | Where-Object { $_.CommandLine -notmatch '^\s*!' } | Select-Object -Last 1
    if ($h) { return $h.CommandLine }
    return $null
}

# The last ARGUMENT of the last command — bash's `!$`.
function Get-LastArg {
    $last = Get-LastCommand
    if (-not $last) { return $null }

    $tokens = [System.Management.Automation.PSParser]::Tokenize($last, [ref]$null) |
              Where-Object { $_.Type -in 'CommandArgument', 'String', 'Number' }
    if ($tokens) { return $tokens[-1].Content }
    return $null
}

# ── PSReadLine handlers ───────────────────────────────────────────────────────
# Rewrite `!!` and `!$` in the buffer the moment they are completed, so the real
# command is visible before Enter is pressed.
if (Get-Module -ListAvailable PSReadLine) {

    # `!` twice -> expand to the previous command line.
    Set-PSReadLineKeyHandler -Chord '!' -ScriptBlock {
        $line = $null; $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

        # A '!' directly after another '!' means the user typed the second bang.
        if ($cursor -gt 0 -and $line[$cursor - 1] -eq '!') {
            $prev = Get-LastCommand
            if ($prev) {
                # Replace the first '!' too.
                [Microsoft.PowerShell.PSConsoleReadLine]::Replace($cursor - 1, 1, $prev)
                return
            }
        }

        [Microsoft.PowerShell.PSConsoleReadLine]::Insert('!')
    }

    # `!$` -> the last argument of the previous command.
    Set-PSReadLineKeyHandler -Chord '$' -ScriptBlock {
        $line = $null; $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

        if ($cursor -gt 0 -and $line[$cursor - 1] -eq '!') {
            $arg = Get-LastArg
            if ($arg) {
                [Microsoft.PowerShell.PSConsoleReadLine]::Replace($cursor - 1, 1, $arg)
                return
            }
        }

        [Microsoft.PowerShell.PSConsoleReadLine]::Insert('$')
    }
}

# ── history ───────────────────────────────────────────────────────────────────
<#
.SYNOPSIS
    history [n]  — the last n commands, numbered, bash-style.
.EXAMPLE
    history          # last 25
    history 100      # last 100
    history | grep git
#>
if (Test-Path Alias:\history) { Remove-Item Alias:\history -Force }

function history {
    param([int]$Count = 25)

    $all = Get-History
    if (-not $all) { Write-Host "ℹ️  No history yet." -ForegroundColor DarkGray; return }

    $all | Select-Object -Last $Count | ForEach-Object {
        "{0,5}  {1}" -f $_.Id, $_.CommandLine
    }
}
