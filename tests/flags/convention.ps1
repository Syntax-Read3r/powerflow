# ==============================================================================
# The flag convention: one dash for a letter, two for a word
# ==============================================================================
# Adopted in docs/plan/ethos/DECISIONS.md Part 2 (Option A, GNU-strict) and written up in
# docs/plan/ethos/ETHOS.md. Before it, a user carrying one habit between commands was wrong
# more often than right: `help` had four spellings across seven commands, `-f` meant three
# different things, "skip the prompt" had six spellings (two silently ignored), and 54 of 301
# dashed tokens were never implemented at all.
#
# Two facts make the implementation non-obvious, and both are asserted here because both were
# discovered the hard way:
#
#   1. A param() block does not merely fail to bind `--word` — it MISBINDS it into the next
#      value parameter. `T --name bob` gives Name='--name' and drops 'bob'. So a command with
#      a param() block cannot be left alone; it needs the shim.
#   2. Splatting an ARRAY passes every element positionally, so rewriting tokens and splatting
#      cannot bind anything by name. The parser must build a HASHTABLE, which means it has to
#      know which flags consume a value.
# ==============================================================================

$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$assertions = 0
function Ok([bool]$c, [string]$m) {
    if (-not $c) { throw "FAIL: $m" }
    $script:assertions++
}

function Register-PFCommand { }
# educate.ps1 first: Invoke-PFParamCommand calls Split-PFEducateFlag to strip the
# cross-cutting --educate flag, so the real dependency is exercised rather than stubbed.
. (Join-Path $root 'components/shared/educate.ps1')
. (Join-Path $root 'components/shared/flags.ps1')

# ── the parser, against a target with one of each kind of parameter ───────────
function Test-PFFlagTarget {
    param([switch]$Status, [switch]$DryRun, [string]$Name, [int]$Depth, [switch]$a)
    return [pscustomobject]@{ Status = [bool]$Status; DryRun = [bool]$DryRun; Name = $Name; Depth = $Depth; A = [bool]$a }
}
function pf-flagdemo { Invoke-PFParamCommand -Target 'Test-PFFlagTarget' -Command 'pf-flagdemo' -Argv $args }

# canonical long form binds
$r = pf-flagdemo --status
Ok ($r.Status) '--status should bind the switch'
$r = pf-flagdemo --dry-run
Ok ($r.DryRun) '--dry-run should reach the PascalCase parameter DryRun'
$r = pf-flagdemo --name bob
Ok ($r.Name -ceq 'bob') '--name should consume the following token as its value'
$r = pf-flagdemo --depth 3
Ok ($r.Depth -eq 3) '--depth should bind a typed value'

# the =value form, which GNU tools accept
$r = pf-flagdemo --name=alice
Ok ($r.Name -ceq 'alice') '--name=value should bind'

# a one-letter flag keeps ONE dash — that is the whole point of the rule
$r = pf-flagdemo -a
Ok ($r.A) '-a should still bind with a single dash'

# an unambiguous prefix resolves, matching what param() does for the single-dash form
$r = pf-flagdemo --dry
Ok ($r.DryRun) 'an unambiguous long prefix should resolve'

# the legacy single-dash word still binds — nothing is broken by the migration
$r = pf-flagdemo -status
Ok ($r.Status) 'the legacy single-dash word must keep working'

# ...and says so exactly once per session, so a daily driver is not lectured every run
$first = @(pf-flagdemo -dry-run 6>&1 | ForEach-Object { "$_" }) -join ' '
Ok ($first -clike '*is now --dry-run*') 'the legacy spelling should be reported once'
$second = @(pf-flagdemo -dry-run 6>&1 | ForEach-Object { "$_" }) -join ' '
Ok ($second -cnotlike '*is now --dry-run*') 'the report must not repeat within a session'

# ── an unknown flag is REFUSED, never dropped ────────────────────────────────
# This is DECISIONS 1.4 generalised. `pwsh-font --status` installed a font because the
# unbindable token fell into $args, the switch stayed false, and the default action ran.
$refusal = @(pf-flagdemo --stauts 6>&1 | ForEach-Object { "$_" }) -join ' '
Ok ($refusal -clike '*unknown option*') 'an unknown long flag must be refused'
Ok ($refusal -clike '*did you mean --status*') 'the refusal should suggest the nearest real flag'
Ok ($refusal -clike '*accepts:*') 'the refusal should list what the command does take'

# The command must NOT have run. Proven by return value: a refusal returns nothing.
$result = pf-flagdemo --stauts 6>$null
Ok ($null -eq $result) 'a refused invocation must not reach the implementation'

# A one-letter flag is offered as -a, not --a: the message that teaches the rule must not
# break it.
Ok ($refusal -clike '*-a*' -and $refusal -cnotlike '*--a *') 'a single-letter flag should be offered with one dash'

# ── positional values survive, including ones that look like flags ───────────
$r = pf-flagdemo --name -5
Ok ($r.Name -ceq '-5') 'a value parameter should consume the next token whatever it looks like'

# A long flag that expects a value and gets nothing is an error, not an empty bind.
$dangling = @(pf-flagdemo --name 6>&1 | ForEach-Object { "$_" }) -join ' '
Ok ($dangling -clike '*expects a value*') 'a value flag with nothing after it must be reported'

# ── PARAMETER ALIASES are part of the surface ────────────────────────────────
# `git-rl -h` is documented, and `h` is an [Alias()] on -ShowSetupPrompt rather than a
# parameter name. Reading only $Parameters.Keys made `-h` unresolvable: it fell through to the
# positional list, was array-splatted, and arrived at the implementation as the STRING '-h'.
# The documented command silently stopped doing what it said. Short forms are usually declared
# as aliases, so a parser that ignores them breaks exactly the spellings people type most.
function Test-PFAliasTarget {
    param([Alias('h', 'help', '?')][switch]$ShowSetupPrompt, [string]$Topic)
    return [pscustomobject]@{ Show = [bool]$ShowSetupPrompt; Topic = $Topic }
}
$aliasSurface = (Get-Command Test-PFAliasTarget).Parameters
foreach ($form in @('-h', '--help', '-help', '--show-setup-prompt', '-ShowSetupPrompt')) {
    $p = ConvertTo-PFCanonicalFlags -Argv @($form) -Parameters $aliasSurface
    Ok ($p.Named.ContainsKey('ShowSetupPrompt')) "$form should resolve to ShowSetupPrompt"
    Ok (@($p.Positional).Count -eq 0) "$form must not leak into the positional list"
    Ok (@($p.Unknown).Count -eq 0) "$form must not be reported unknown"
}

# ── a single-letter flag resolves into the NAMED set, not positionally ───────
# This matters because dispatch goes through an ARRAY splat, and an array splat binds every
# element POSITIONALLY — a leading dash is not read as a parameter name. Measured: splatting
# @('-a') at a function with `[switch]$a` sets the first positional STRING parameter to '-a'
# and leaves the switch false. So a flag left in the positional list does not merely lose its
# shorthand; it silently becomes a value.
$short = ConvertTo-PFCanonicalFlags -Argv @('-a') -Parameters (Get-Command Test-PFFlagTarget).Parameters
Ok ($short.Named.ContainsKey('a')) '-a must be resolved into the named set, not left positional'
Ok (@($short.Positional).Count -eq 0) '-a must not be left in the positional list'

# ...and a short form must NOT be reported as a legacy spelling. `-a` has not moved; telling
# someone it is "now --a" would teach the opposite of the rule.
$noteOut = @(ConvertTo-PFCanonicalFlags -Argv @('-a') `
    -Parameters (Get-Command Test-PFFlagTarget).Parameters -Command 'pf-flagdemo' 6>&1 |
    ForEach-Object { "$_" }) -join ' '
Ok ($noteOut -cnotlike '*is now*') 'a one-letter flag must not be reported as a renamed spelling'

$twoOut = @(ConvertTo-PFCanonicalFlags -Argv @('-sh') `
    -Parameters (Get-Command Test-PFAliasTarget).Parameters -Command 'x' 6>&1 |
    ForEach-Object { "$_" }) -join ' '
Ok ($twoOut -cnotlike '*is now*') 'a two-letter short form must not be reported as renamed either'

# ── every shimmed command's real surface accepts its documented short flags ──
# Against the REAL parameter metadata, so a rename in an implementation shows up here.
$realCases = @(
    @{ Impl = 'Show-PFHelpMenu';            Forms = @('-a', '--advanced', '--all') }
    @{ Impl = 'Install-PFNerdFontCommand';  Forms = @('--status') }
    @{ Impl = 'Show-PFMachineHealth';       Forms = @('--power', '--crashes', '--bios', '--ram', '--export') }
    @{ Impl = 'Show-PFInstalledApps';       Forms = @('--overview', '--measure') }
    @{ Impl = 'Invoke-PFTeamRoom';          Forms = @('--all') }
    @{ Impl = 'Set-PFPathEntry';            Forms = @('--system') }
    @{ Impl = 'Invoke-PFSelfUpdate';        Forms = @('--yes') }
    @{ Impl = 'Invoke-GitReleaseCommand';   Forms = @('-h', '--help') }
)
# The param block is lifted out of the source and rebuilt as a probe function, rather than
# loading the components that define these. Loading them would drag in their whole dependency
# chain (adapters, the registry, the prompt) for information the AST already has — and the
# param block IS the surface under test.
$probeIndex = 0
foreach ($case in $realCases) {
    $found = $null
    foreach ($file in (Get-ChildItem (Join-Path $root 'components') -Recurse -Filter *.ps1)) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
        $fn = @($ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $args[0].Name -ceq $case.Impl }, $true))
        if ($fn.Count -eq 1) { $found = $fn[0]; break }
    }
    Ok ([bool]$found) "$($case.Impl) should be defined exactly once under components/"
    if (-not $found -or -not $found.Body.ParamBlock) { continue }

    $probeIndex++
    $probeName = "Probe-PFFlagSurface$probeIndex"
    Invoke-Expression "function $probeName {`n$($found.Body.ParamBlock.Extent.Text)`n}"
    $cmd = Get-Command $probeName -CommandType Function

    $common = @([System.Management.Automation.PSCmdlet]::CommonParameters) +
              @([System.Management.Automation.PSCmdlet]::OptionalCommonParameters)
    $surface = @{}
    foreach ($e in $cmd.Parameters.GetEnumerator()) { if ($e.Key -notin $common) { $surface[$e.Key] = $e.Value } }

    foreach ($form in $case.Forms) {
        $p = ConvertTo-PFCanonicalFlags -Argv @($form) -Parameters $surface
        Ok (@($p.Unknown).Count -eq 0 -and $p.Named.Count -ge 1) `
            "$($case.Impl) should accept $form (unknown=[$($p.Unknown -join ',')] named=[$($p.Named.Keys -join ',')])"
    }
}

# ── kebab conversion ────────────────────────────────────────────────────────
Ok ((ConvertTo-PFKebab 'DryRun') -ceq 'dry-run')       'DryRun -> dry-run'
Ok ((ConvertTo-PFKebab 'ShowSetupPrompt') -ceq 'show-setup-prompt') 'ShowSetupPrompt -> show-setup-prompt'
Ok ((ConvertTo-PFKebab 'status') -ceq 'status')        'an already-lowercase name is unchanged'
Ok ((ConvertTo-PFKebab 'a') -ceq 'a')                  'a single letter is unchanged'

# ── the structural rule: no user-facing command may keep a bare param() block ─
# A kebab-named function with a param() block cannot bind --long, and misbinds it. Any such
# command is a latent instance of the defect above, so the gate is structural rather than a
# matter of remembering.
$offenders = @()
foreach ($file in (Get-ChildItem (Join-Path $root 'components'), (Join-Path $root 'windows-only') -Recurse -Filter *.ps1)) {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
    foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        if ($fn.Name -cnotmatch '^[a-z][\w\.-]*$') { continue }      # Verb-Noun = internal helper
        if (-not $fn.Body.ParamBlock) { continue }                    # hand-parsed, owns its own spelling
        $params = @($fn.Body.ParamBlock.Parameters)
        if (-not $params.Count) { continue }

        # Only multi-character SWITCHES count. That distinction is the whole judgement here:
        #
        #   * A switch is something a user types WITH A DASH — `--dry-run`, `--status`. If it
        #     is word-length and the command has a bare param() block, `--word` misbinds. That
        #     is the defect, and it must be routed through the shim.
        #
        #   * A value parameter on these commands is POSITIONAL — `lesson grep`,
        #     `git-bd my-branch`, `history 20`. Nobody types `lesson --name grep`, and
        #     demanding a shim for every command that takes an argument would be churn with no
        #     user-visible benefit. They remain bindable by name (`-Count 5`) exactly as
        #     PowerShell users expect, and `--count 5` on them is a latent, lower-grade version
        #     of the same problem: worth fixing if one of them ever grows a real flag, not
        #     worth 29 shims today.
        $switchWords = @($params | Where-Object {
            $_.Name.VariablePath.UserPath.Length -gt 1 -and
            @($_.Attributes | Where-Object {
                $_ -is [System.Management.Automation.Language.TypeConstraintAst] -and
                "$($_.TypeName)" -match '^switch$' }).Count -gt 0
        })
        if (-not $switchWords.Count) { continue }

        $offenders += "$($fn.Name) ($($file.Name)) [$(($switchWords | ForEach-Object { $_.Name.VariablePath.UserPath }) -join ', ')]"
    }
}
Ok ($offenders.Count -eq 0) (
    "these user-facing commands still declare param() with word-length parameters, so --long " +
    "cannot bind and would misbind into a value parameter — route them through " +
    "Invoke-PFParamCommand: $($offenders -join '; ')")

# ── the shims are shaped correctly ───────────────────────────────────────────
# A shim that declares param() of its own defeats the whole thing: $args would no longer hold
# the line, so nothing would reach the parser.
$shimFiles = Get-ChildItem (Join-Path $root 'components'), (Join-Path $root 'windows-only') -Recurse -Filter *.ps1
$shimCount = 0
foreach ($file in $shimFiles) {
    $text = Get-Content -LiteralPath $file.FullName -Raw
    foreach ($m in [regex]::Matches($text, '(?m)^function ([a-z][\w\.-]*) \{ Invoke-PFParamCommand -Target ''([^'']+)'' -Command ''([^'']+)'' -Argv \$args \}')) {
        $shimCount++
        Ok ($m.Groups[1].Value -ceq $m.Groups[3].Value) `
            "the shim for $($m.Groups[1].Value) passes -Command '$($m.Groups[3].Value)' — they must match, or the messages name the wrong command"
        # The implementation must exist in the same file, and must not be kebab-named itself
        # (or the help gate would demand a registration for an internal helper).
        Ok ($text -cmatch "(?m)^function $([regex]::Escape($m.Groups[2].Value))\b") `
            "$($m.Groups[2].Value) should be defined in $($file.Name) alongside its shim"
        Ok ($m.Groups[2].Value -cmatch '^[A-Z]') `
            "$($m.Groups[2].Value) should be Verb-Noun so pwsh-h treats it as internal"
    }
}
Ok ($shimCount -ge 10) "expected at least 10 migrated commands, found $shimCount"

Write-Host "  flag convention: $assertions assertions passed" -ForegroundColor Green
