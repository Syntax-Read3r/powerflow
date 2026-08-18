# ==============================================================================
# PF-UX-003 (b2) — word navigation, deletion and selection chords
# ==============================================================================
# The report: Ctrl+Left / Ctrl+Del / Ctrl+Shift+Arrow do not behave like a text editor.
#
# The investigation mattered more than the fix. PowerFlow binds exactly two chords (`!` and
# `$`) and never sets EditMode, so it was not breaking anything — and on Windows every chord
# in the report was ALREADY bound. The real gap is Emacs mode, which is the default on
# Linux, where word navigation and selection are unbound outright.
#
# Two things this file pins down, because both were wrong at some point while writing it:
#
#   1. PSReadLine NORMALISES modifier order when reporting a binding. `Ctrl+Shift+LeftArrow`
#      comes back as `Shift+Ctrl+LeftArrow`, so a raw string lookup reports an already-bound
#      chord as unbound — and then binds it a second time under the other spelling. That
#      produced a wrong "2 chords unbound" claim before it was caught.
#
#   2. Binding is ADDITIVE. A chord already bound to something else is left alone, because
#      it may well be deliberate. Only `--rebind` overrides, and only because the user typed
#      it.
# ==============================================================================

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

$fail = 0
function Ok([bool]$c, [string]$m, [string]$d = '') {
    if (-not $c) { $script:fail++ }
    Write-Host ("  {0} {1}{2}" -f $(if ($c) { 'ok  ' } else { 'FAIL' }), $m, $(if ($d) { "   $d" } else { '' }))
}

function Register-PFCommand { }
function Register-PFEducation { }
function Test-PFEducateRequested { return $false }
function Invoke-PFParamCommand { }

$text = Get-Content -LiteralPath (Join-Path $root 'components/shell/keys.ps1') -Raw
. (Join-Path $root 'components/shell/keys.ps1')

Write-Host 'PF-UX-003 (b2) line editing keys'

# ── 1. the spelling trap ─────────────────────────────────────────────────────
Write-Host ''
Write-Host '-- chords normalise to PSReadLine order ------------------------'
Ok ((ConvertTo-PFChordKey 'Ctrl+Shift+LeftArrow') -ceq 'Shift+Ctrl+LeftArrow') `
    'Ctrl+Shift+X normalises to Shift+Ctrl+X, the order PSReadLine reports'
Ok ((ConvertTo-PFChordKey 'Shift+Ctrl+LeftArrow') -ceq 'Shift+Ctrl+LeftArrow') 'and is idempotent'
Ok ((ConvertTo-PFChordKey 'Ctrl+Alt+Shift+X') -ceq 'Shift+Ctrl+Alt+X') 'three modifiers order Shift, Ctrl, Alt'
Ok ((ConvertTo-PFChordKey 'Home') -ceq 'Home') 'an unmodified key is unchanged'
Ok ((ConvertTo-PFChordKey 'Ctrl+d') -ceq 'Ctrl+d') 'the key half keeps its case'

# THE assertion: every chord in the table must already be in normal form, or the binder
# writes one spelling and the report reads another.
foreach ($chord in (Get-PFEditingChords)) {
    Ok ((ConvertTo-PFChordKey $chord.Chord) -ceq $chord.Chord) `
        "'$($chord.Chord)' is stored in PSReadLine's normalised spelling"
}

# ── 2. the table is coherent ─────────────────────────────────────────────────
Write-Host ''
Write-Host '-- the chord table -----------------------------------------------'
$chords = @(Get-PFEditingChords)
Ok ($chords.Count -ge 8) 'the table covers the reported chords' "$($chords.Count) entries"
foreach ($wanted in @('Ctrl+LeftArrow', 'Ctrl+RightArrow', 'Ctrl+Delete', 'Ctrl+Backspace',
                      'Shift+Ctrl+LeftArrow', 'Shift+Ctrl+RightArrow')) {
    Ok (@($chords | Where-Object { $_.Chord -ceq $wanted }).Count -eq 1) "$wanted is in the table"
}
Ok (@($chords | Where-Object { -not $_.Does }).Count -eq 0) 'every chord says what it does'
$known = @(Get-PSReadLineKeyHandler -Bound -Unbound | ForEach-Object { "$($_.Function)" } | Sort-Object -Unique)
foreach ($chord in $chords) {
    Ok ($known -contains $chord.Function) "$($chord.Function) is a real PSReadLine function"
}

# ── 3. reporting is accurate against a live PSReadLine ───────────────────────
Write-Host ''
Write-Host '-- the report matches what is actually bound --------------------'
$state = Get-PFKeyBindingState
Ok ($state.Available) 'PSReadLine is available here'
Ok ([bool]$state.EditMode) 'the edit mode is reported' $state.EditMode
Ok (@($state.Rows).Count -eq $chords.Count) 'one row per chord'

$live = @{}
foreach ($h in @(Get-PSReadLineKeyHandler -Bound)) { $live[(ConvertTo-PFChordKey $h.Key)] = "$($h.Function)" }
foreach ($row in @($state.Rows)) {
    $key = ConvertTo-PFChordKey $row.Chord
    $actual = if ($live.ContainsKey($key)) { $live[$key] } else { '' }
    Ok ($row.Current -ceq $actual) "$($row.Chord) is reported as what PSReadLine really has" "'$actual'"
    if (-not $actual) { Ok ($row.Source -ceq 'unbound') "$($row.Chord) with no binding reads 'unbound'" }
}
Ok (@($state.Rows | Where-Object { $_.Source -notin @('default', 'PowerFlow', 'other', 'unbound') }).Count -eq 0) `
    'every row carries one of the four documented sources'

# ── 4. Emacs mode — the case the report is actually about ────────────────────
# Emacs is the default on Linux, and it is where the chords are genuinely missing. Switching
# modes here changes only this process.
Write-Host ''
Write-Host '-- Emacs mode: the gap is real, and gets filled -----------------'
$originalMode = (Get-PSReadLineOption).EditMode
try {
    Set-PSReadLineOption -EditMode Emacs
    $script:PF_BoundChords = @{}

    $before = @{}
    foreach ($h in @(Get-PSReadLineKeyHandler -Bound)) { $before[(ConvertTo-PFChordKey $h.Key)] = "$($h.Function)" }
    $wasUnbound = @((Get-PFEditingChords) | Where-Object { -not $before.ContainsKey((ConvertTo-PFChordKey $_.Chord)) })
    Ok ($wasUnbound.Count -gt 0) 'Emacs mode really does leave editing chords unbound' "$($wasUnbound.Count) of $($chords.Count)"

    # Something bound to a DIFFERENT function must survive untouched.
    $differing = @((Get-PFEditingChords) | Where-Object {
        $k = ConvertTo-PFChordKey $_.Chord
        $before.ContainsKey($k) -and $before[$k] -cne $_.Function })

    Set-PFEditingKeys

    $after = @{}
    foreach ($h in @(Get-PSReadLineKeyHandler -Bound)) { $after[(ConvertTo-PFChordKey $h.Key)] = "$($h.Function)" }

    foreach ($chord in $wasUnbound) {
        $k = ConvertTo-PFChordKey $chord.Chord
        Ok ($after.ContainsKey($k)) "$($chord.Chord) was unbound and is now bound"
        Ok ($after[$k] -ceq $chord.Function) "...to $($chord.Function)" "'$($after[$k])'"
    }
    foreach ($chord in $differing) {
        $k = ConvertTo-PFChordKey $chord.Chord
        Ok ($after[$k] -ceq $before[$k]) `
            "$($chord.Chord) was bound to something else and was LEFT ALONE" "'$($after[$k])'"
    }

    # Nothing that was already correct changed.
    $clobbered = @()
    foreach ($k in $before.Keys) {
        if ($after.ContainsKey($k) -and $after[$k] -cne $before[$k]) { $clobbered += "$k ($($before[$k]) -> $($after[$k]))" }
    }
    Ok ($clobbered.Count -eq 0) 'no existing binding anywhere was replaced' "$($clobbered -join '; ')"

    # And the report now attributes them to PowerFlow, not to the defaults.
    $state = Get-PFKeyBindingState
    $ours = @($state.Rows | Where-Object { $_.Source -ceq 'PowerFlow' })
    Ok ($ours.Count -eq $wasUnbound.Count) 'the report attributes exactly the filled-in chords to PowerFlow' "$($ours.Count)"

    # ── 5. --rebind is the ONLY way a bound chord is replaced ────────────────
    if ($differing.Count) {
        Write-Host ''
        Write-Host '-- --rebind overrides, and only then ---------------------------'
        Set-PFEditingKeys -Force
        $forced = @{}
        foreach ($h in @(Get-PSReadLineKeyHandler -Bound)) { $forced[(ConvertTo-PFChordKey $h.Key)] = "$($h.Function)" }
        foreach ($chord in $differing) {
            $k = ConvertTo-PFChordKey $chord.Chord
            Ok ($forced[$k] -ceq $chord.Function) "-Force takes over $($chord.Chord)" "'$($forced[$k])'"
        }
    }
}
finally {
    Set-PSReadLineOption -EditMode $originalMode
}

# ── 6. load-time binding is never forced ─────────────────────────────────────
Write-Host ''
Write-Host '-- the load-time call is additive ------------------------------'
$tokens = $null
$null = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$null)
$builder = [Text.StringBuilder]::new($text)
foreach ($token in @($tokens | Where-Object { $_.Kind -eq 'Comment' })) {
    $start = $token.Extent.StartOffset
    $length = $token.Extent.EndOffset - $start
    $null = $builder.Remove($start, $length).Insert($start, (' ' * $length))
}
$clean = $builder.ToString()
$calls = @([regex]::Matches($clean, 'Set-PFEditingKeys[^\r\n]*') | ForEach-Object { $_.Value.Trim() })
$loadCall = @($calls | Where-Object { $_ -notmatch 'function|param' } | Select-Object -Last 1)
Ok ($loadCall.Count -eq 1) 'there is a load-time call'
Ok ($loadCall[0] -notmatch '-Force') 'and it does NOT force' "'$($loadCall[0])'"
Ok ($clean -match 'Set-PFEditingKeys -Force') '-Force exists, reachable only from the rebind path'

# PowerFlow must not silently change the edit mode out from under the user.
Ok ($clean -notmatch 'Set-PSReadLineOption\s+-EditMode') `
    'PowerFlow never sets EditMode — that is the user''s or the platform''s choice'

Write-Host ''
if ($fail) { Write-Host "$fail CHECK(S) FAILED"; exit 1 }
Write-Host 'PF-UX-003 (b2): unbound chords get filled in, bound ones are left alone, and the report is accurate.'
