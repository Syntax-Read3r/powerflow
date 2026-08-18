# ==============================================================================
# PowerFlow — `--educate`
# ==============================================================================
# Domain   : Shared
# File     : components/shared/educate.ps1
# Purpose  : One flag that explains what you are looking at, in plain words
# Functions: Register-PFEducation, Write-PFEducation, Split-PFEducateFlag,
#            Test-PFEducationTopic, Get-PFEducationTopics
# Depends  : none (loads early — any command may register a topic)
# ==============================================================================
#
# THE SHAPE, taken from a walkthrough the owner wrote for `ss -tulpn`:
#
#     In the hospital picture, we are checking which service windows are open
#     before we declare the ward ready for production.
#
#     ss  shows network sockets.
#     -t  shows TCP connections.
#     -u  shows UDP connections.
#     -l  shows only services that are LISTENING for incoming traffic.
#
# Two halves, and both earn their place:
#
#   1. AN ANALOGY, first and once. Not decoration — it gives somebody a place to put the
#      facts before the facts arrive. "Which service windows are open" is a thing a person
#      can already picture; "listening sockets" is not, until it has somewhere to go.
#   2. ONE LINE PER ELEMENT, each naming a thing actually on screen. Not a paragraph about
#      networking: a decode of the column, flag or number in front of them.
#
# RULES THIS FILE ENFORCES, because the point is a reliable teaching voice rather than
# occasional prose:
#
#   * The footer comes AFTER the output, never before. Someone who already knows the
#     material must be able to ignore it by not reading down; making them scroll past a
#     lesson to reach their data would tax the expert to help the beginner.
#   * It is opt-in. No command prints it unasked.
#   * Every line is one sentence, ending in a full stop, under ~90 characters. A wall of
#     text is not a lesson, and the width is what keeps it scannable.
#   * It explains what is ON SCREEN. A topic that drifts into general theory has stopped
#     being a footer and become documentation, which belongs in `lesson`.
#
# `lesson <command>` remains the long form for learning a command you are NOT currently
# running. `--educate` is for the output you are looking at right now.
# ==============================================================================

$script:PF_Education = @{}

<#
.SYNOPSIS
    Register the explanation for one view.
.DESCRIPTION
    Beside the command that produces the view, the same way Register-PFCommand sits beside
    its function — so the explanation moves when the code moves, instead of rotting in a
    documentation file nobody edits in the same commit.
.PARAMETER Analogy
    One sentence giving the reader somewhere to put the facts. Omit rather than force one:
    a laboured metaphor is worse than none.
.PARAMETER Lines
    One per element on screen. Each is @{ Term = 'SWAP'; Means = 'what it is, plainly.' }.
#>
function Register-PFEducation {
    param(
        [Parameter(Mandatory)][string]$Topic,
        [string]$Analogy = '',
        [Parameter(Mandatory)][hashtable[]]$Lines,
        [string]$Footer = ''
    )

    $script:PF_Education[$Topic] = [pscustomobject]@{
        Topic   = $Topic
        Analogy = $Analogy
        Lines   = $Lines
        Footer  = $Footer
    }
}

function Get-PFEducationTopics { return @($script:PF_Education.Keys | Sort-Object) }

function Test-PFEducationTopic {
    param([Parameter(Mandatory)][string]$Topic)
    return $script:PF_Education.ContainsKey($Topic)
}

<#
.SYNOPSIS
    Pull `--educate` out of an argument list.
.DESCRIPTION
    Returns the remaining arguments and whether the flag was present, so a hand-parsed
    command can strip it before its own parsing runs — otherwise `--educate` reaches a
    verb switch and is reported as an unknown command, which is exactly the "unbindable
    token" failure the flag convention exists to prevent.

    `-educate` (one dash) is accepted as the legacy spelling for consistency with every
    other word flag, and reported once by the same notice.
#>
function Split-PFEducateFlag {
    param([object[]]$Argv = @(), [string]$Command = '')

    $rest = @()
    $wanted = $false
    foreach ($argument in $Argv) {
        $token = "$argument"
        if ($token -ceq '--educate') { $wanted = $true; continue }
        if ($token -ceq '-educate') {
            $wanted = $true
            if ($Command -and (Get-Command Write-PFFlagDeprecation -ErrorAction SilentlyContinue)) {
                Write-PFFlagDeprecation -Command $Command -Old '-educate' -New '--educate'
            }
            continue
        }
        $rest += $argument
    }

    return [pscustomobject]@{ Argv = $rest; Educate = $wanted }
}

<#
.SYNOPSIS
    Print the explanation for a view, after the view.
.DESCRIPTION
    Silent for an unregistered topic rather than erroring: a missing explanation should
    never break the command whose output the reader actually wanted.
#>
function Write-PFEducation {
    param([Parameter(Mandatory)][string]$Topic)

    if (-not $script:PF_Education.ContainsKey($Topic)) { return }
    $entry = $script:PF_Education[$Topic]

    Write-Host ''
    Write-Host '  ─── what you are looking at ─────────────────────────────────' -ForegroundColor DarkGray

    if ($entry.Analogy) {
        Write-Host "  $($entry.Analogy)" -ForegroundColor Gray
        Write-Host ''
    }

    # The term column is measured, not guessed: a hardcoded width silently misaligns the
    # moment a longer term is added, and a ragged lesson reads as an afterthought.
    $width = 0
    foreach ($line in $entry.Lines) {
        if ($line.Term -and $line.Term.Length -gt $width) { $width = $line.Term.Length }
    }

    foreach ($line in $entry.Lines) {
        $term = if ($line.Term) { $line.Term } else { '' }
        Write-Host ("  {0}  " -f $term.PadRight($width)) -NoNewline -ForegroundColor Cyan
        Write-Host $line.Means -ForegroundColor Gray
    }

    if ($entry.Footer) {
        Write-Host ''
        Write-Host "  $($entry.Footer)" -ForegroundColor DarkGray
    }
    Write-Host ''
}
