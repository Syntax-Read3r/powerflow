# ==============================================================================
# PowerFlow — Flag Spelling
# ==============================================================================
# Domain   : Shared
# File     : components/shared/flags.ps1
# Purpose  : One canonical flag spelling across the whole shell, and one place that
#            enforces it
# Functions: Invoke-PFParamCommand, ConvertTo-PFCanonicalFlags, Write-PFFlagDeprecation,
#            Resolve-PFFlagName, Test-PFFlagIsSwitch, ConvertTo-PFKebab,
#            Get-PFFlagSuggestion
# Depends  : none (loads early — every command may use it)
# ==============================================================================
#
# THE RULE (see docs/plan/ethos/ETHOS.md):
#
#     -x  -xy       one dash, one or two letters  short form
#     --word        two dashes, a word            long form, kebab-case
#     -xvf          a bundle of short flags       ONLY on commands that impersonate a
#                                                 GNU tool, and only known letters
#
# A single-dash WORD (`-force`, `-status`) is the legacy spelling. It still works, and
# says once per session that it moved.
#
# ── why this file has to exist ────────────────────────────────────────────────
#
# A PowerShell `param()` block CANNOT BIND `--word`. It is not merely unsupported — it
# actively misbinds. Measured:
#
#     function T { param([switch]$Force, [string]$Path) }
#     T --force            ->  Force=False, Path='--force'
#     T --name bob         ->  Name='--name',  and 'bob' falls into $args
#
# So a `--long` flag on a param() command does not fail loudly; it lands in whichever
# value parameter is positionally next and takes the real value's place. Declaring the
# alias `[Alias('-force')]` does not help either — that was tested, and `--force` still
# arrives as a positional string.
#
# The alternative was converting 12 commands into hand-parsers. That was rejected: a hand
# parser gets no case-insensitivity and no prefix matching, so `-Stat` and `-status` and
# `-STATUS` would all stop working, and each parser would have to reimplement the
# forgiveness that param() gives away for free.
#
# Instead the spelling is translated AT THE DOOR and param() still does the binding. The
# shell gains one spelling; the commands keep every bit of PowerShell's tolerance.
# ==============================================================================

# Flags already reported this session, so the notice teaches once instead of nagging.
$script:PF_FlagNoticeSeen = [System.Collections.Generic.HashSet[string]]::new()

<#
.SYNOPSIS
    Say once, quietly, that a single-dash word has a new spelling.
.DESCRIPTION
    Once per session per command+flag. A daily driver should not be lectured every time it
    runs, and the old spelling still works — this is a signpost, not an error.
#>
function Write-PFFlagDeprecation {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string]$Old,
        [Parameter(Mandatory)][string]$New
    )

    $key = "$Command $Old"
    if (-not $script:PF_FlagNoticeSeen.Add($key)) { return }
    Write-Host "   note: $Command $Old is now $New (one dash is for short forms). Both still work." -ForegroundColor DarkGray
}

<#
.SYNOPSIS
    Suggest the closest real flag for one that does not exist.
.DESCRIPTION
    Refusing an unknown flag is only helpful if it points somewhere. Matches on a shared
    prefix first, then on a single-character edit, which covers the ordinary typo.
#>
function Get-PFFlagSuggestion {
    param([Parameter(Mandatory)][string]$Attempt, [string[]]$Known = @())

    $needle = $Attempt.TrimStart('-').ToLowerInvariant() -replace '-', ''
    if (-not $needle) { return '' }

    foreach ($k in $Known) {
        $flat = $k.ToLowerInvariant()
        if ($flat.StartsWith($needle) -or $needle.StartsWith($flat)) { return (ConvertTo-PFKebab $k) }
    }
    # One wrong letter, or one transposition of adjacent letters. Transposition needs its own
    # case: it produces TWO differing positions, so a plain "at most one difference" test
    # misses the single most common typo there is — `--stauts` for `--status`.
    foreach ($k in $Known) {
        $flat = $k.ToLowerInvariant()
        if ($flat.Length -ne $needle.Length) { continue }

        $differing = @()
        for ($i = 0; $i -lt $flat.Length; $i++) {
            if ($flat[$i] -ne $needle[$i]) { $differing += $i }
        }
        if ($differing.Count -eq 0 -or $differing.Count -eq 1) { return (ConvertTo-PFKebab $k) }
        if ($differing.Count -eq 2) {
            $a, $b = $differing
            if (($b - $a) -eq 1 -and $flat[$a] -eq $needle[$b] -and $flat[$b] -eq $needle[$a]) {
                return (ConvertTo-PFKebab $k)
            }
        }
    }
    return ''
}

<#
.SYNOPSIS
    PascalCase -> kebab-case, for display.
.DESCRIPTION
    `DryRun` -> `dry-run`. Long flags are kebab-case, because that is what every other
    command-line tool a user has ever met does, and `--dryrun` reads badly.
#>
function ConvertTo-PFKebab {
    param([Parameter(Mandatory)][string]$Name)
    if ($Name -cmatch '^[a-z0-9-]+$') { return $Name }
    return (($Name -creplace '(?<!^)([A-Z])', '-$1').ToLowerInvariant())
}

<#
.SYNOPSIS
    Resolve a flag word to the parameter name it means, or $null.
.DESCRIPTION
    Matches ignoring case AND hyphens, so `--dry-run` finds `DryRun`. An unambiguous prefix
    resolves too, matching what param() already does for the single-dash form; ambiguity is
    refused rather than guessed at.

    Top-level with explicit parameters rather than nested inside the parser. Nested functions
    reach their caller's variables by dynamic scoping, which is both re-created on every call
    and invisible to any tool that scans for `^function` — the release gate flagged exactly
    that. Explicit inputs also make this testable on its own.
#>
function Resolve-PFFlagName {
    param(
        [Parameter(Mandatory)][string]$Word,
        [Parameter(Mandatory)][hashtable]$ByFlatName
    )

    $flat = $Word.ToLowerInvariant() -replace '-', ''
    if ($ByFlatName.ContainsKey($flat)) { return $ByFlatName[$flat] }
    $hits = @($ByFlatName.Keys | Where-Object { $_.StartsWith($flat) })
    if ($hits.Count -eq 1) { return $ByFlatName[$hits[0]] }
    return $null
}

<#
.SYNOPSIS
    Is this parameter a switch (takes no value) or a value parameter?
.DESCRIPTION
    Compare the TYPE, not its string form. Interpolating a [Type] in PowerShell yields the
    type ACCELERATOR — `"$([switch])"` is `switch`, not
    `System.Management.Automation.SwitchParameter` — so a `-match` on the full name is always
    false, and every switch would be mistaken for a value parameter and swallow the next token.
#>
function Test-PFFlagIsSwitch {
    param([Parameter(Mandatory)][string]$Name, $Parameters)

    if (-not $Parameters -or -not $Parameters.ContainsKey($Name)) { return $false }
    return ($Parameters[$Name].ParameterType -eq [switch])
}

<#
.SYNOPSIS
    Split an argument list into named parameters and positional values.
.DESCRIPTION
    Returns a hashtable of resolved parameter names and an array of positional values, ready
    to splat at the target.

    A HASHTABLE is required, not an array. Splatting an array passes every element
    POSITIONALLY — a leading dash is not interpreted as a parameter name — so the obvious
    "rewrite the tokens and splat the array" approach silently binds `-Status` as the *value*
    of whatever value parameter comes first. Only `@hashtable` binds by name, which means
    this parser must know which flags consume a following value. It reads that from the
    target's own parameter types, so there is no list to maintain here.

    Unknown long flags are REFUSED rather than passed along. That refusal matters as much as
    the translation: `pwsh-font --status` used to install a font, because the unbindable
    token vanished into $args, the switch stayed false, and the command ran its default
    action. A flag aimed at a command must never be quietly dropped by it.
.PARAMETER Parameters
    The target's real parameter dictionary (name -> ParameterMetadata), so switches can be
    told from value parameters.
#>
function ConvertTo-PFCanonicalFlags {
    param(
        [object[]]$Argv = @(),
        $Parameters = $null,
        [string]$Command = ''
    )

    $names = @()
    if ($Parameters) { $names = @($Parameters.Keys) }

    # Match a declared parameter ignoring case AND hyphens, so --dry-run finds DryRun.
    #
    # PARAMETER ALIASES ARE INCLUDED, and that is not a nicety. `git-rl -h` is documented, and
    # `h` is an [Alias()] on -ShowSetupPrompt, not a parameter name — reading only
    # $Parameters.Keys made `-h` unresolvable, so it fell through to the positional list and
    # arrived at the implementation as a *string*. The documented command silently stopped
    # working. Aliases are how short forms are usually declared, so they are part of the
    # surface, not decoration.
    $byFlat = @{}
    foreach ($n in $names) {
        $byFlat[($n.ToLowerInvariant() -replace '-', '')] = $n
        foreach ($alias in @($Parameters[$n].Aliases)) {
            if ($alias) { $byFlat[($alias.ToLowerInvariant() -replace '-', '')] = $n }
        }
    }

    $named = @{}
    $positional = @()
    $unknown = @()
    $passThrough = $false

    for ($i = 0; $i -lt $Argv.Count; $i++) {
        $token = "$($Argv[$i])"

        # A bare `--` ends option parsing: everything after it is a value, even if dashed.
        #
        # Interactively this almost never fires, because POWERSHELL EATS `--` ITSELF before
        # $args is populated — measured: `f -- --status` reaches the function as a single
        # argument `--status`. So the guard is here for callers that pass an argument ARRAY
        # directly (scripts, tests), not for something a user can type. A dash-leading value
        # typed at the prompt has to arrive as the value of a named flag — `--name -weird`
        # works, since a value parameter consumes the next token whatever it looks like.
        if ($passThrough) { $positional += $Argv[$i]; continue }
        if ($token -ceq '--') { $passThrough = $true; continue }

        $word = $null
        $inlineValue = $null
        $legacy = $false

        # SINGLE-CHARACTER tokens are matched too (`{0,}`, not `{1,}`). They must be resolved
        # here rather than left for PowerShell, because this dispatches through an ARRAY splat
        # and an array splat binds EVERY element POSITIONALLY — a leading dash is not read as a
        # parameter name. Measured: splatting @('-a') at a function with a `[switch]$a` sets the
        # first positional STRING parameter to '-a' and leaves the switch false. So anything not
        # resolved into the named hashtable does not merely lose its shorthand, it silently
        # becomes a value.
        if ($token -cmatch '^--([A-Za-z][\w-]*)=(.*)$') { $word = $Matches[1]; $inlineValue = $Matches[2] }
        elseif ($token -cmatch '^--([A-Za-z][\w-]*)$')  { $word = $Matches[1] }
        elseif ($token -cmatch '^-([A-Za-z][\w-]*)=(.*)$') { $word = $Matches[1]; $inlineValue = $Matches[2]; $legacy = $true }
        elseif ($token -cmatch '^-([A-Za-z][\w-]*)$')      { $word = $Matches[1]; $legacy = $true }

        # A one- or two-letter single-dash token is the CANONICAL short form, not a legacy
        # spelling — `-f`, `-a`, `-sh`. Only a single-dash WORD has moved, so only a word earns
        # the notice. Telling someone that `-a` is now `--a` would be teaching the opposite of
        # the rule.
        if ($legacy -and $word.Length -le 2) { $legacy = $false }

        if (-not $word) { $positional += $Argv[$i]; continue }

        $resolved = Resolve-PFFlagName -Word $word -ByFlatName $byFlat
        if (-not $resolved) {
            # A legacy single-dash word that names nothing might genuinely be a value (a
            # negative number, an odd filename), but it cannot be told apart from a typo —
            # and guessing wrong on a destructive command is the expensive direction. Refuse.
            $unknown += $token
            continue
        }

        if ($legacy -and $Command) {
            Write-PFFlagDeprecation -Command $Command -Old "-$word" -New "--$(ConvertTo-PFKebab $resolved)"
        }

        if (Test-PFFlagIsSwitch -Name $resolved -Parameters $Parameters) {
            # `--force=false` is accepted because a script may want to pass it through.
            if ($null -ne $inlineValue) { $named[$resolved] = [bool]::Parse($inlineValue) }
            else { $named[$resolved] = $true }
            continue
        }

        if ($null -ne $inlineValue) { $named[$resolved] = $inlineValue; continue }

        # A value parameter consumes the NEXT token. Running off the end is a real mistake
        # (`--name` with nothing after it) and is reported rather than bound to empty.
        if ($i + 1 -ge $Argv.Count) {
            $unknown += "$token (expects a value)"
            continue
        }
        $i++
        $named[$resolved] = $Argv[$i]
    }

    return [pscustomobject]@{
        Named      = $named
        Positional = @($positional)
        Unknown    = @($unknown)
        Names      = @($names)
    }
}

<#
.SYNOPSIS
    Run a param()-based command through the canonical flag spelling.
.DESCRIPTION
    The user-facing kebab name becomes a one-line shim over the real implementation:

        function pwsh-font { Invoke-PFParamCommand -Target 'Install-PFNerdFont' -Command 'pwsh-font' -Argv $args }

    The shim must NOT declare param() of its own, or $args will not hold the whole line.
.PARAMETER Target
    The Verb-Noun function holding the param() block. Its parameters are read directly, so
    adding a switch there needs no change here.
#>
function Invoke-PFParamCommand {
    param(
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$Command,
        [object[]]$Argv = @()
    )

    # NOT `$target = ...`. PowerShell variable names are case-insensitive, so $target and
    # $Target are one variable — and `param([string]$Target)` puts a TYPE CONSTRAINT on it,
    # so assigning a CommandInfo silently coerces it back to its own name as a string. The
    # parameter list then reads as empty and every flag is refused as unknown. Same family as
    # the automatic-variable rule the release gate enforces: a constrained variable is not
    # scratch space.
    $targetCmd = Get-Command $Target -CommandType Function -ErrorAction SilentlyContinue
    if (-not $targetCmd) {
        Write-Host "❌ $Command is not wired up correctly: '$Target' does not exist." -ForegroundColor Red
        return
    }

    # PowerShell's own common parameters are not part of the command's surface; offering
    # --error-action in a suggestion list would be noise.
    $common = @([System.Management.Automation.PSCmdlet]::CommonParameters) +
              @([System.Management.Automation.PSCmdlet]::OptionalCommonParameters)
    $surface = @{}
    foreach ($entry in $targetCmd.Parameters.GetEnumerator()) {
        if ($entry.Key -in $common) { continue }
        $surface[$entry.Key] = $entry.Value
    }

    # --educate is CROSS-CUTTING: it belongs to every command, so no command declares it as a
    # parameter and every command would otherwise reject it as unknown. Strip it here, record
    # the request, and let the target decide WHICH topic to print — a command like pc-whoami
    # has several views and each wants a different explanation, so the choice is the view's,
    # not the dispatcher's.
    # Guarded so this file still works dot-sourced on its own. If educate.ps1 is absent,
    # --educate is simply not a feature and falls through to the unknown-option path — which
    # is the HONEST outcome, and better than silently swallowing a flag the user typed.
    $educateArgv = $Argv
    if (Get-Command Split-PFEducateFlag -ErrorAction SilentlyContinue) {
        $educated = Split-PFEducateFlag -Argv $Argv -Command $Command
        $educateArgv = $educated.Argv
        Set-PFEducateRequested $educated.Educate
    }

    try {
        $parsed = ConvertTo-PFCanonicalFlags -Argv $educateArgv -Parameters $surface -Command $Command

    if ($parsed.Unknown.Count) {
        foreach ($bad in $parsed.Unknown) {
            Write-Host "❌ ${Command}: unknown option '$bad'" -ForegroundColor Red
            $hint = Get-PFFlagSuggestion -Attempt $bad -Known @($surface.Keys)
            if ($hint) { Write-Host "   did you mean --$hint ?" -ForegroundColor DarkGray }
        }
        # Spell the offer the way the rule says to type it: one dash for a short form (one or
        # two letters), two
        # for a word. Listing `--a` would advertise a spelling the convention forbids, from
        # the very message whose job is to teach the convention.
        $offer = @(@($surface.Keys) | Sort-Object | ForEach-Object {
            if ($_.Length -le 2) { "-$_" } else { "--$(ConvertTo-PFKebab $_)" }
        }) -join '  '
        if ($offer) { Write-Host "   accepts: $offer" -ForegroundColor DarkGray }
        # Refuse the whole invocation. Running on with the flag dropped is precisely what
        # made `pwsh-font --status` install a font.
        return
    }

        # Two splats: the hashtable binds by NAME, the array supplies what is left positionally.
        $named = $parsed.Named
        $rest = @($parsed.Positional)
        if ($rest.Count) { & $targetCmd @named @rest }
        else { & $targetCmd @named }
    }
    finally {
        # ALWAYS cleared. A leaked flag would make the next command print a lesson nobody
        # asked for, which is a worse failure than never printing one — and it would be
        # blamed on the innocent command.
        if (Get-Command Set-PFEducateRequested -ErrorAction SilentlyContinue) {
            Set-PFEducateRequested $false
        }
    }
}
