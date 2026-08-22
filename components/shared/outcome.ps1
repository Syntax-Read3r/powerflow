# ==============================================================================
# PowerFlow — Outcome Reporting
# ==============================================================================
# Domain   : Shared
# File     : components/shared/outcome.ps1
# Purpose  : One place that decides what a marker means, so the red cross stays worth reading
# Functions: Write-PFCancelled, Write-PFFailure, Write-PFWarning, Write-PFNothingFound,
#            Invoke-PFNativeStep
# Depends  : none
# ==============================================================================
#
# THE OUTCOME RULE
#
#   The message names the outcome that ACTUALLY happened, the marker names its severity, and
#   both are read from a signal the code is holding — never inferred from an empty value.
#
# That last clause is the one that keeps being broken. An empty result is not a failure, a
# non-zero exit is not always an error, and a cancelled picker is not a fault. An audit of
# this tree found 107 places where a message named something that had not happened; three of
# them printed a green banner over a file operation that had failed and lost data.
#
# THE MARKERS
#
#   ✅ Green     verified success — only after re-reading state, testing an exit code, or
#                -ErrorAction Stop. Never merely "the call returned".
#   ⚠️  Yellow    accepted but unverified, or partial. Say what could not be confirmed.
#   ↩  DarkGray  a USER DECISION: Escape, "n", a declined overwrite. No glyph, no cause.
#   ⭕ Yellow    a read-only query's truthful negative — looked, found nothing.
#   ❌ Red       a genuine failure, or a refused mutation. RED IS THE POINT: spend it on a
#                user who changed their mind and they learn to scan past it, and the next
#                time it matters, they will.
#
# Two mechanical corollaries the CI gate enforces:
#   - ❌ may only appear on a -ForegroundColor Red line.
#   - A glyph is never a literal beside a value it can contradict. `"✅ Profile Loaded: False"`
#     was real, at core/version.ps1:244.
#
# Derived from where this tree already gets it right: components/proxmox/shared.ps1's
# one-predicate/one-envelope/one-renderer boundary, and the container adapter's -1 sentinel
# that keeps "could not look" distinct from "nothing there".
# ==============================================================================

<#
.SYNOPSIS
    A user decided not to. Not an error, and it must not look like one.
#>
function Write-PFCancelled {
    param([string]$Detail = '')
    Write-Host '↩ Cancelled.' -ForegroundColor DarkGray
    if ($Detail) { Write-Host "   $Detail" -ForegroundColor DarkGray }
}

<#
.SYNOPSIS
    Something genuinely failed. Name it, and say what to do about it.
.DESCRIPTION
    -Detail carries the underlying tool's OWN message. Never paraphrase into a guessed cause:
    "could not connect" over an authentication failure sends someone to check a network that
    was never the problem.
#>
function Write-PFFailure {
    param([Parameter(Mandatory)][string]$Message, [string]$Detail = '', [string]$Hint = '')
    Write-Host "❌ $Message" -ForegroundColor Red
    if ($Detail) { Write-Host "   $Detail" -ForegroundColor DarkGray }
    if ($Hint)   { Write-Host "   $Hint"   -ForegroundColor Yellow }
}

<#
.SYNOPSIS
    It happened, but something about it could not be confirmed. Say WHICH part.
#>
function Write-PFWarning {
    param([Parameter(Mandatory)][string]$Message, [string]$Detail = '')
    Write-Host "⚠️  $Message" -ForegroundColor Yellow
    if ($Detail) { Write-Host "   $Detail" -ForegroundColor DarkGray }
}

<#
.SYNOPSIS
    A query ran and found nothing. A truthful negative is not a failure.
.DESCRIPTION
    Distinct from "could not look", which is a failure and takes Write-PFFailure. Collapsing
    the two is how a broken query becomes an empty list that everybody believes.
#>
function Write-PFNothingFound {
    param([Parameter(Mandatory)][string]$Message, [string]$Hint = '')
    Write-Host "⭕ $Message" -ForegroundColor Yellow
    if ($Hint) { Write-Host "   $Hint" -ForegroundColor DarkGray }
}

<#
.SYNOPSIS
    Run a native command and report truthfully whether it worked.
.DESCRIPTION
    $LASTEXITCODE IS CAPTURED ON THE VERY NEXT LINE, because anything else that runs — another
    native call, and in some hosts even a Write-Host — replaces it. Capturing late is the same
    bug as not capturing at all, only harder to see.

    Returns $true/$false so the caller can decide what to print. It deliberately does NOT
    print a success message itself: what success means differs per command, and a shared
    "done!" is exactly the kind of message that ends up lying.
#>
function Invoke-PFNativeStep {
    param(
        [Parameter(Mandatory)][scriptblock]$Do,
        [Parameter(Mandatory)][string]$What,
        [switch]$Quiet
    )

    & $Do
    $code = $LASTEXITCODE

    # A scriptblock that ran no native command at all leaves $LASTEXITCODE untouched from
    # whatever came before. Treat "no code" as success rather than inheriting a stale one.
    if ($null -eq $code) { return $true }
    if ($code -eq 0) { return $true }

    if (-not $Quiet) {
        Write-PFFailure -Message "$What failed (exit $code)." -Hint 'The command output above says why.'
    }
    return $false
}
