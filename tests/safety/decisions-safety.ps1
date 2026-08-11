# ==============================================================================
# The safety fixes from docs/plan/ethos/DECISIONS.md, pinned
# ==============================================================================
# Seven defects that shared one shape: a command did something more destructive than its name,
# its help text, or its parameter contract implied. Each is now fixed; this file stops each one
# coming back.
#
# 1.1 rm -force performed rm -rf              (tests/files/gnu-args.ps1)
# 1.2 git-bd force-deleted; safe one dead     here
# 1.3 git-a-plus -a amended the last commit   here
# 1.4 pwsh-font --status installed a font     here
# 1.5 three synopses described safer commands here
# 1.6 pwsh-recovery deleted $PROFILE unbacked here
# 1.7 the CI gate was blind to case collisions (.github/workflows/release-validate.yml)
# ==============================================================================

$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
}
function Get-Body {
    param([string]$Path, [string]$Function)
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        (Resolve-Path $Path).Path, [ref]$null, [ref]$null)
    $found = $ast.FindAll({
        $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $args[0].Name -eq $Function }, $true)
    if ($found.Count -ne 1) { throw "FAIL: expected exactly one $Function, found $($found.Count) in $Path" }
    return $found[0].Extent.Text
}

$root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$assertions = 0

# ---------------------------------------------------------------------------------
# 1.2  git-bd must be the SAFE delete, and the force variant must not differ only by case
# ---------------------------------------------------------------------------------
# PowerShell function names are case-INSENSITIVE, so `git-bD` and `git-bd` were one name and
# the force-delete (defined second) won. Typing the documented-safe name destroyed unmerged work.
$branches = Join-Path $root 'components/git/branches.ps1'

# -cmatch throughout. A case-INSENSITIVE check cannot test a case bug: `-match 'branch -D'`
# happily matches 'branch -d', which is how a first pass at this test reported a false pass.
$safeBody = Get-Body $branches 'git-bd'
Assert-True ($safeBody -cmatch 'git branch -d\b') 'git-bd must use `git branch -d` (refuses unmerged)'
Assert-True (-not ($safeBody -cmatch 'git branch -D\b')) 'git-bd must NOT force-delete'
$assertions += 2

$forceBody = Get-Body $branches 'git-bd-force'
Assert-True ($forceBody -cmatch 'git branch -D\b') 'git-bd-force must be the one that force-deletes'
$assertions++

$branchText = Get-Content -LiteralPath $branches -Raw
Assert-True (-not ($branchText -cmatch '(?m)^function git-bD\b')) `
    'git-bD must not exist: it is the same name as git-bd and would silently replace it'
# It must not come back as an "alias" either — that describes a distinction the language cannot make.
Assert-True (-not ($branchText -match "-Aliases\s+@\('git-bD'\)")) `
    'git-bD must not be declared an alias of git-bd; PowerShell cannot tell them apart'
Assert-True ($branchText -match "Register-PFCommand -Name 'git-bd-force'") 'git-bd-force must be registered for pwsh-h'
$assertions += 3

# The safe command's own hint must point somewhere that exists.
Assert-True ($safeBody -match 'git-bd-force') 'git-bd should point at git-bd-force, not a name identical to itself'
$assertions++

# ---------------------------------------------------------------------------------
# 1.3  `-a` must not reach -AmendLast  —  CLOSED BY DELETION
# ---------------------------------------------------------------------------------
# The hazard: `-a` is git's own "stage everything", and PowerShell binds unambiguous
# PREFIXES, so on `git-a-plus` it bound -AmendLast and ran `git commit --amend` behind
# nothing but an fzf message box, with no abort path if the user escaped it.
#
# It was originally fixed by declaring a second A-parameter (-AddAll) so that `-a` errors as
# ambiguous instead of binding. That guard is gone now, and so is the command: the owner
# pruned `git-a-plus` and its four one-line wrappers ("git-a is enough, those other ones have
# never been used").
#
# So this section now asserts the STRONGER property. A guard can be removed by someone who
# does not know what it was for — the ambiguity trick looks like a redundant switch. A
# deleted command cannot be mis-bound at all, and the only way to reintroduce the hazard is
# to reintroduce the command, which this catches.
$commit = Join-Path $root 'components/git/commit.ps1'
$commitText = Get-Content -LiteralPath $commit -Raw

foreach ($gone in @('git-a-plus', 'git-aa', 'git-aq', 'git-ad', 'git-am')) {
    Assert-True ($commitText -cnotmatch "(?m)^function $([regex]::Escape($gone))(?![\w-])") `
        "$gone was pruned and must not come back with an -AmendLast prefix hazard"
    Assert-True ($commitText -cnotmatch "Register-PFCommand -Name '$gone'") `
        "$gone must not be registered in pwsh-h after being pruned"
    $assertions += 2
}

# git-a itself must survive the prune — it is the command the others delegated to conceptually,
# and deleting it would take the whole add-commit-push workflow with it.
Assert-True ($commitText -cmatch '(?m)^function git-a(?![\w-])') 'git-a must still exist'
$assertions++

# And nothing anywhere may still call a pruned name: a dangling call is a runtime error that
# only shows up when someone reaches that branch.
foreach ($file in (Get-ChildItem (Join-Path $root 'components'), (Join-Path $root 'windows-only') -Recurse -Filter *.ps1)) {
    $tokens = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$null)
    $code = (($tokens | Where-Object { $_.Kind -ne 'Comment' } | ForEach-Object { $_.Text }) -join ' ')
    foreach ($gone in @('git-a-plus', 'git-aa', 'git-aq', 'git-ad', 'git-am')) {
        Assert-True ($code -cnotmatch "(?<![\w-])$([regex]::Escape($gone))(?![\w-])") `
            "$($file.Name) still references the pruned command $gone"
        $assertions++
    }
}

# ---------------------------------------------------------------------------------
# 1.4  pwsh-font must not install when handed something it cannot bind
# ---------------------------------------------------------------------------------
# The command is now in two parts, and BOTH must hold. `pwsh-font` is a thin shim over
# `Install-PFNerdFontCommand` so that `--status` can bind at all (a param() block cannot bind
# a double-dash flag — it misbinds it into the next value parameter). The unknown-flag refusal
# therefore lives centrally in Invoke-PFParamCommand, and the implementation keeps its own
# guard for unbindable POSITIONAL junk.
#
# Both are asserted deliberately. Either one alone would let the original defect back: without
# the central refusal an unknown `--flag` reaches the body and falls into $args; without the
# body's guard a stray positional reaches the install path.
$fonts = Join-Path $root 'components/system/fonts.ps1'
$fontsText = Get-Content -LiteralPath $fonts -Raw
$fontBody = Get-Body $fonts 'Install-PFNerdFontCommand'

Assert-True ($fontsText -match "function pwsh-font \{ Invoke-PFParamCommand -Target 'Install-PFNerdFontCommand'") `
    'pwsh-font must be a shim onto Invoke-PFParamCommand, or --status cannot bind at all'
$assertions++

# The refusal must come BEFORE any install can be reached, or it is decoration.
$guardIdx   = $fontBody.IndexOf('$unknown = @($args')
$installIdx = $fontBody.IndexOf('Install-NerdFont')
Assert-True ($guardIdx -ge 0) 'the implementation must still collect and inspect unbound arguments'
Assert-True ($installIdx -gt $guardIdx) 'the unknown-argument guard must precede any install path'
Assert-True ($fontBody -match 'return') 'the guard must return rather than fall through'
$assertions += 3

# Behavioural proof, with the install shimmed so nothing is installed by the test.
$script:installed = $false
function Get-NerdFontName { 'TestFont' }
function Test-NerdFont { $false }
function Install-NerdFont { $script:installed = $true; return $true }
function Get-NerdFontInstallHint { 'hint' }
function Get-NerdFontInstructions { 'instructions' }
function Register-PFCommand { }
. (Join-Path $root 'components/shared/flags.ps1')
Invoke-Expression $fontBody
# Rebuild the shim too, so the test drives the real two-part command rather than calling the
# implementation directly and skipping the layer that does the flag translation.
Invoke-Expression "function pwsh-font { Invoke-PFParamCommand -Target 'Install-PFNerdFontCommand' -Command 'pwsh-font' -Argv `$args }"

$script:installed = $false
pwsh-font --status *> $null
Assert-True (-not $script:installed) '`pwsh-font --status` must NOT install a font'
$assertions++

$script:installed = $false
pwsh-font -status *> $null
Assert-True (-not $script:installed) '`pwsh-font -status` must remain read-only'
$assertions++

# And the real install path must still work, or the guard has broken the command.
$script:installed = $false
pwsh-font *> $null
Assert-True $script:installed 'bare `pwsh-font` must still install'
$assertions++

# ---------------------------------------------------------------------------------
# 1.5  a synopsis must not describe something safer than the body
# ---------------------------------------------------------------------------------
# pwsh-h is generated from the registry, so a wrong synopsis is a wrong manual.
$reset = Get-Content -LiteralPath (Join-Path $root 'components/git/reset.ps1') -Raw
$interactive = Get-Content -LiteralPath (Join-Path $root 'components/git/interactive.ps1') -Raw

$gitFSyn = [regex]::Match($reset, "Register-PFCommand -Name 'git-f'[^\r\n]*").Value
Assert-True ($gitFSyn -notmatch 'fetch and fast-forward') `
    'git-f must not be advertised as "fetch and fast-forward"; it runs reset --hard + clean -fdx'
Assert-True ($gitFSyn -match 'DESTRUCTIVE') 'git-f must be labelled destructive'
$assertions += 2

$gitNextSyn = [regex]::Match($reset, "Register-PFCommand -Name 'git-next'[^\r\n]*").Value
Assert-True ($gitNextSyn -notmatch 'jump forward one commit') `
    'git-next must not be advertised as a history walk; it deletes node_modules and the lockfile'
Assert-True ($gitNextSyn -match 'DESTRUCTIVE') 'git-next must be labelled destructive'
$assertions += 2

$gitShSyn = [regex]::Match($interactive, "Register-PFCommand -Name 'git-sh'[^\r\n]*").Value
Assert-True ($gitShSyn -notmatch 'show a commit') 'git-sh is a git-stash shorthand, not a commit viewer'
Assert-True ($gitShSyn -match 'stash') 'git-sh should be described as the stash shorthand it is'
$assertions += 2

# ---------------------------------------------------------------------------------
# 1.6  a recovery tool must not be the thing that loses the file
# ---------------------------------------------------------------------------------
$recovery = Get-Content -LiteralPath (Join-Path $root 'components/core/recovery.ps1') -Raw
$removeIdx = $recovery.IndexOf('Remove-Item $PROFILE -Force')
Assert-True ($removeIdx -gt 0) 'could not find the profile delete'
$window = $recovery.Substring([Math]::Max(0, $removeIdx - 900), [Math]::Min(900, $removeIdx))
Assert-True ($window -match 'Copy-Item') 'the profile must be copied before it is deleted'
Assert-True ($window -match 'backup') 'the backup must be named as such so the user knows where it went'
Assert-True ($window -match 'nothing was removed') `
    'if the backup cannot be written, the delete must be refused rather than proceeding'
$assertions += 3

Write-Host "  DECISIONS safety fixes: $assertions assertions passed" -ForegroundColor Green
