# ==============================================================================
# PowerFlow — Line Editing Keys
# ==============================================================================
# Domain   : Shell
# File     : components/shell/keys.ps1
# Purpose  : Restore standard word navigation / selection chords, and show what is bound
# Functions: Get-PFEditingChords, ConvertTo-PFChordKey, Get-PFKeyBindingState,
#            Set-PFEditingKeys, Show-PFKeyBindings, Invoke-PFKeyCommand
# Depends  : PSReadLine (ships with PowerShell)
# ==============================================================================
#
# PF-UX-003 (b2). The report was that `Ctrl+Left`, `Ctrl+Del` and `Ctrl+Shift+Arrow` do not
# behave like every other text editor, and that only `Fn+Arrow` navigates — far too coarse
# for editing a command line.
#
# The first thing to establish was whether PowerFlow was breaking them. **It was not.**
# PowerFlow binds exactly two chords (`!` and `$`, in history.ps1) and never sets `EditMode`,
# so everything else is PSReadLine's default. Measured:
#
#   chord              EditMode Windows     EditMode Emacs (the DEFAULT on Linux)
#   Ctrl+Left          BackwardWord         UNBOUND
#   Ctrl+Right         NextWord             UNBOUND
#   Ctrl+Del           KillWord             UNBOUND
#   Ctrl+Backspace     BackwardKillWord     BackwardDeleteChar  (a CHARACTER, not a word)
#   Shift+Ctrl+Left    SelectBackwardWord   UNBOUND
#   Shift+Ctrl+Right   SelectNextWord       UNBOUND
#
# **On Windows every chord in the report is already bound.** On Linux almost none are. So
# there are two different problems wearing one bug report:
#
#   1. Genuinely unbound chords — THE LINUX HALF. Emacs mode leaves word navigation, word
#      deletion and word selection unbound. PowerFlow fills those in, below.
#
#   2. Chords the terminal never delivers — THE WINDOWS HALF. If `Ctrl+Left` is bound and
#      still does nothing, the key never reached the line editor: some terminals and
#      keyboard layouts emit no distinct sequence for a modified arrow. No remap can fix
#      that, and installing one anyway is the "risky global remap" the item explicitly
#      warns against. `pwsh-keys` exists so that case is diagnosable instead of guessed at.
#
# ONE SPELLING TRAP, and it produced a wrong answer here before it was caught. PSReadLine
# NORMALISES modifier order when it reports a binding: write `Ctrl+Shift+LeftArrow` and
# `Get-PSReadLineKeyHandler` lists it back as `Shift+Ctrl+LeftArrow`. Looking it up under
# the spelling you wrote finds nothing — so a naive check calls an already-bound chord
# "unbound", tells the user so, and then binds it a SECOND time under the other spelling.
# Every lookup here goes through ConvertTo-PFChordKey.
#
# The rule this file follows: BIND ONLY WHAT IS UNBOUND. The worst failure of adding a
# binding is a convenience that was already there. The worst failure of replacing one is
# taking away something someone relies on — so that needs `--rebind`, asked for explicitly.

<#
.SYNOPSIS
    The editing chords this file cares about, and what each should do.
.DESCRIPTION
    Data, not code, so the diagnostic and the binder cannot disagree about the list. A
    report showing a different set from the one actually bound is worse than no report.
#>
function Get-PFEditingChords {
    return @(
        [pscustomobject]@{ Chord = 'Ctrl+LeftArrow';        Function = 'BackwardWord';       Does = 'move to the previous word' }
        [pscustomobject]@{ Chord = 'Ctrl+RightArrow';       Function = 'NextWord';           Does = 'move to the next word' }
        [pscustomobject]@{ Chord = 'Ctrl+Delete';           Function = 'KillWord';           Does = 'delete the word ahead' }
        [pscustomobject]@{ Chord = 'Ctrl+Backspace';        Function = 'BackwardKillWord';   Does = 'delete the word behind' }
        [pscustomobject]@{ Chord = 'Shift+Ctrl+LeftArrow';  Function = 'SelectBackwardWord'; Does = 'select one word left' }
        [pscustomobject]@{ Chord = 'Shift+Ctrl+RightArrow'; Function = 'SelectNextWord';     Does = 'select one word right' }
        [pscustomobject]@{ Chord = 'Shift+LeftArrow';       Function = 'SelectBackwardChar'; Does = 'select one character left' }
        [pscustomobject]@{ Chord = 'Shift+RightArrow';      Function = 'SelectForwardChar';  Does = 'select one character right' }
        [pscustomobject]@{ Chord = 'Home';                  Function = 'BeginningOfLine';    Does = 'go to the start of the line' }
        [pscustomobject]@{ Chord = 'End';                   Function = 'EndOfLine';          Does = 'go to the end of the line' }
    )
}

# Recorded so the diagnostic can attribute a binding honestly, rather than showing a chord
# as "default" when this file set it.
$script:PF_BoundChords = @{}

<#
.SYNOPSIS
    A chord in PSReadLine's own normalised spelling, so lookups actually match.
.DESCRIPTION
    PSReadLine reports modifiers in a fixed order — Shift, then Ctrl, then Alt — whatever
    order they were written in. Comparing raw strings therefore misses real bindings; see
    the spelling trap in the header.
#>
function ConvertTo-PFChordKey {
    param([string]$Chord)

    $parts = @("$Chord" -split '\+' | Where-Object { $_ })
    if ($parts.Count -le 1) { return "$Chord" }
    $key = $parts[-1]
    $modifiers = @($parts | Select-Object -SkipLast 1)
    $order = @('Shift', 'Ctrl', 'Alt')
    $sorted = @($order | Where-Object { $m = $_; @($modifiers | Where-Object { $_ -ieq $m }).Count })
    $unknown = @($modifiers | Where-Object { $_ -notin $order })
    return ((@($sorted) + @($unknown) + @($key)) -join '+')
}

<#
.SYNOPSIS
    What each editing chord is bound to right now, and who bound it.
#>
function Get-PFKeyBindingState {
    if (-not (Get-Module PSReadLine) -and -not (Get-Module -ListAvailable PSReadLine)) {
        return [pscustomobject]@{ Available = $false; EditMode = ''; Rows = @()
            Reason = 'PSReadLine is not loaded, so there is no line editor to report on' }
    }

    $bound = @{}
    foreach ($handler in @(Get-PSReadLineKeyHandler -Bound)) {
        $bound[(ConvertTo-PFChordKey $handler.Key)] = "$($handler.Function)"
    }

    $rows = @()
    foreach ($chord in (Get-PFEditingChords)) {
        $key = ConvertTo-PFChordKey $chord.Chord
        $current = if ($bound.ContainsKey($key)) { $bound[$key] } else { '' }
        # 'other', not 'yours'. A binding that differs from PowerFlow's choice may be the
        # user's, or it may be a PSReadLine default that simply disagrees — Emacs binds
        # Ctrl+Backspace to delete a CHARACTER. Without a baseline those are
        # indistinguishable, and calling a default "yours" would be a confident wrong claim.
        $source = if (-not $current) { 'unbound' }
                  elseif ($script:PF_BoundChords.ContainsKey($key)) { 'PowerFlow' }
                  elseif ($current -ceq $chord.Function) { 'default' }
                  else { 'other' }
        $rows += [pscustomobject]@{
            Chord = $chord.Chord; Does = $chord.Does
            Wanted = $chord.Function; Current = $current; Source = $source
        }
    }
    return [pscustomobject]@{
        Available = $true
        EditMode  = "$((Get-PSReadLineOption).EditMode)"
        Rows      = @($rows)
        Reason    = ''
    }
}

<#
.SYNOPSIS
    Bind the editing chords that are UNBOUND. Never replace one that works.
.DESCRIPTION
    Called once at load, and silent by design: a profile that narrates its own key bindings
    on every start is noise, and `pwsh-keys` is there for anyone who wants to know.

    -Force is the ONLY path that replaces a bound chord, and it exists because the user
    asked for it by name (`pwsh-keys --rebind`). Load-time binding never passes it.
#>
function Set-PFEditingKeys {
    param([switch]$Force)

    if (-not (Get-Module -ListAvailable PSReadLine)) { return }

    $bound = @{}
    try { foreach ($handler in @(Get-PSReadLineKeyHandler -Bound)) { $bound[(ConvertTo-PFChordKey $handler.Key)] = $true } }
    catch { return }

    foreach ($chord in (Get-PFEditingChords)) {
        $key = ConvertTo-PFChordKey $chord.Chord
        if (-not $Force -and $bound.ContainsKey($key)) { continue }
        try {
            Set-PSReadLineKeyHandler -Chord $chord.Chord -Function $chord.Function -ErrorAction Stop
            $script:PF_BoundChords[$key] = $chord.Function
        }
        catch {
            # A chord this PSReadLine build will not accept, or a function it does not have.
            # Not worth a message on shell start; `pwsh-keys` shows it as unbound, which is
            # the truth.
        }
    }
}

function Get-PFKeySourceColour {
    param([string]$Source)
    switch ($Source) {
        'default'   { 'Gray' }
        'PowerFlow' { 'Green' }
        'other'     { 'Cyan' }
        default     { 'Yellow' }
    }
}

<#
.SYNOPSIS
    `pwsh-keys` — what the editing chords are bound to, and what to do if one still does nothing.
#>
function Show-PFKeyBindings {
    $state = Get-PFKeyBindingState

    Write-Host ''
    Write-Host '  ⌨️  LINE EDITING KEYS' -ForegroundColor Cyan
    Write-Host '  ──────────────────────────────────────────────────────────────────' -ForegroundColor DarkGray

    if (-not $state.Available) {
        Write-Host "  $($state.Reason)" -ForegroundColor Yellow
        Write-Host ''
        return
    }

    Write-Host ("  {0,-11} {1}" -f 'Edit mode', $state.EditMode) -ForegroundColor White
    Write-Host ''
    Write-Host ('  {0,-23} {1,-28} {2}' -f 'CHORD', 'DOES', 'BOUND BY') -ForegroundColor DarkGray
    foreach ($row in @($state.Rows)) {
        Write-Host ('  {0,-23} {1,-28} ' -f $row.Chord, $row.Does) -NoNewline -ForegroundColor White
        $label = if ($row.Source -ceq 'other') { "other ($($row.Current))" } else { $row.Source }
        Write-Host $label -ForegroundColor (Get-PFKeySourceColour $row.Source)
    }

    $unbound = @($state.Rows | Where-Object { $_.Source -ceq 'unbound' })
    $other = @($state.Rows | Where-Object { $_.Source -ceq 'other' })
    Write-Host ''
    if ($unbound.Count) {
        Write-Host "  $($unbound.Count) chord(s) this PSReadLine build would not accept." -ForegroundColor Yellow
    }
    else {
        Write-Host '  Every editing chord above is bound.' -ForegroundColor Green
    }
    if ($other.Count) {
        Write-Host "  $($other.Count) chord(s) are bound to something else, and were left alone." -ForegroundColor Cyan
        Write-Host '  To take them over:  pwsh-keys --rebind' -ForegroundColor DarkGray
    }

    # The half PowerFlow cannot fix, said plainly rather than left as a mystery.
    Write-Host ''
    Write-Host '  If a chord above is bound and still does nothing, your TERMINAL is not' -ForegroundColor DarkGray
    Write-Host '  sending it — some terminals and keyboard layouts emit no distinct sequence' -ForegroundColor DarkGray
    Write-Host '  for a modified arrow, and no key remap here can fix that. Change it in the' -ForegroundColor DarkGray
    Write-Host '  terminal: Windows Terminal → Settings → Actions; VS Code → Keyboard Shortcuts.' -ForegroundColor DarkGray
    Write-Host ''

    if (Test-PFEducateRequested) {
        $shown = @('Edit mode', 'default', 'PowerFlow', 'unbound')
        if ($other.Count) { $shown += 'other' }
        Write-PFEducation -Topic 'line-keys' -Only $shown
    }
}

Register-PFEducation -Topic 'line-keys' `
    -Analogy 'Pressing a key is like posting a letter. The terminal has to put it in the postbox, and the line editor has to know what to do when it arrives. Either one can drop it.' `
    -Lines @(
        @{ Term = 'Edit mode'; Means = 'Which keyboard tradition the editor follows. Windows on Windows, Emacs on Linux.' }
        @{ Term = 'default';   Means = 'PSReadLine set this one. PowerFlow did not touch it.' }
        @{ Term = 'PowerFlow'; Means = 'It was unbound, so PowerFlow filled it in. It never replaces a working one.' }
        @{ Term = 'other';     Means = 'Bound to something different. Left alone, because it may well be deliberate.' }
        @{ Term = 'unbound';   Means = 'Nothing happens on this key. Nothing claimed it.' }
    ) `
    -Footer 'Bound but still silent means the terminal never sent the key — fix that in the terminal, not here.'

function Invoke-PFKeyCommand {
    param([switch]$rebind)

    if ($rebind) {
        # Explicit consent to overwrite. Also the right move after changing EditMode, since
        # the defaults change with it.
        Set-PFEditingKeys -Force
        Write-Host ''
        Write-Host '  Rebound every editing chord to PowerFlow''s mapping.' -ForegroundColor Green
    }
    Show-PFKeyBindings
}

function pwsh-keys { Invoke-PFParamCommand -Target 'Invoke-PFKeyCommand' -Command 'pwsh-keys' -Argv $args }

Register-PFCommand -Name 'pwsh-keys' -Section '⚙️ CONFIGURATION & SETTINGS' `
    -Synopsis 'show what the word-navigation and selection keys are bound to' `
    -Example 'pwsh-keys · pwsh-keys --rebind'

# Bind at load, after the chord table exists. Additive only.
Set-PFEditingKeys
