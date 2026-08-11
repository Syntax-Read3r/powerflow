# ==============================================================================
# Nothing in components/ may be named after a GNU coreutil
# ==============================================================================
# PowerShell resolves a bare name as  Alias -> Function -> Cmdlet -> native binary.
# So a FUNCTION beats a native binary and an ALIAS beats a function, which means a
# function named `rm` in components/ hides /usr/bin/rm on Linux — silently, and with
# different semantics, since PowerFlow's delete drives an fzf picker and its move treats
# one argument as a CUT rather than a move.
#
# This used to be solved backwards. components/ claimed rm/mv/cp/cat/mkdir/touch, and
# platform/linux/bindings.ps1 unpicked every one of them afterwards. That is fail-
# dangerous: the shadowing was unconditional and the undo conditional, so anything that
# stopped the undo from running handed a Linux user an `rm` that did something else. The
# deleted file's own header recorded that this had already shipped once.
#
# The rule is now structural — never claim the name — and these assertions are what keep
# it true. They are deliberately mostly STATIC, so the Linux-side property is provable from
# Windows without a container.
#
# That COMPLEMENTS the runtime check rather than replacing it: CI's release-validate-linux.yml
# already installs PowerFlow on an Alpine/Arch matrix and asserts these names resolve to real
# binaries. The value of also doing it statically is WHERE it fails — on the offending name, in
# the file that defines it, before anything is installed.
#
# NOTE ON ABSENCE ASSERTIONS: every "must not contain" check below runs against
# comment-stripped source. Three separate tests in this tree have passed or failed on
# their own explanatory prose instead of on code, so a scan that includes comments is not
# evidence of anything.
# ==============================================================================

$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
}

$root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$assertions = 0
function Ok([bool]$c, [string]$m) { Assert-True $c $m; $script:assertions++ }

# Blank out every comment, leaving the code at its ORIGINAL spacing.
#
# The obvious implementation — filter the comment tokens out and re-join the rest with a
# space — silently changes the thing under test: `@('del', 'rm')` comes back as
# `@( 'del' , 'rm' )`, so any pattern written to match real source fails for a reason that
# has nothing to do with the code. Overwriting the comment spans in place keeps every other
# character exactly where the author put it.
function Get-CodeOnly {
    param([string]$Path)
    $tokens = $null
    $text = [IO.File]::ReadAllText($Path)
    $null = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$null)
    $sb = [System.Text.StringBuilder]::new($text)
    foreach ($token in @($tokens | Where-Object { $_.Kind -eq 'Comment' })) {
        for ($i = $token.Extent.StartOffset; $i -lt $token.Extent.EndOffset; $i++) {
            if ($sb[$i] -ne "`n" -and $sb[$i] -ne "`r") { $sb[$i] = ' ' }
        }
    }
    return $sb.ToString()
}

# ── 1. the structural rule, over every component ──────────────────────────────
# Kept in step with the "Coreutil names are not shadowed" gate in release-validate.yml.
$coreutils = @(
    'rm', 'mv', 'cp', 'cat', 'mkdir', 'touch', 'rmdir', 'which', 'grep', 'less', 'pwd',
    'head', 'tail', 'wc', 'ln', 'chmod', 'chown', 'df', 'du', 'ps', 'kill', 'sed', 'awk',
    'find', 'sort', 'uniq', 'tar', 'date', 'echo', 'env', 'id', 'man', 'mount', 'sleep',
    'tee', 'diff', 'file', 'stat', 'seq', 'tr', 'cut', 'basename', 'dirname', 'realpath',
    'readlink', 'truncate', 'link', 'unlink', 'mktemp', 'nproc', 'printf', 'whoami',
    'hostname', 'uname', 'free', 'top', 'ls'
)
# `ls`/`la`/`ll` are the ONE deliberate override: the pretty listing is the whole point of
# the command, it accepts GNU flags, and it degrades to Get-ChildItem when lsd is absent.
$allowed = @('ls', 'la', 'll')

$offenders = @()
foreach ($file in (Get-ChildItem (Join-Path $root 'components') -Recurse -Filter *.ps1)) {
    foreach ($pattern in @('^function ([a-z][\w\.-]*)\b', '^Set-Alias(?: -Name)? ([a-z][\w\.-]*)')) {
        # -CaseSensitive is load-bearing: PowerShell regex is case-insensitive by default,
        # so a bare [a-z] would also match every Verb-Noun helper in the tree.
        $offenders += Select-String -CaseSensitive -Path $file.FullName -Pattern $pattern | ForEach-Object {
            $name = $_.Matches[0].Groups[1].Value
            if (($name -cin $coreutils) -and ($name -cnotin $allowed)) { "$name ($($file.Name):$($_.LineNumber))" }
        }
    }
}
Ok ($offenders.Count -eq 0) "components/ must claim no coreutil name; found: $($offenders -join ', ')"

# ── 2. the Linux bindings file must stay gone ─────────────────────────────────
# Its return would mean the hazard was recreated somewhere, since undoing is the only
# thing it ever did.
Ok (-not (Test-Path (Join-Path $root 'platform/linux/bindings.ps1'))) `
    'platform/linux/bindings.ps1 must not exist — fix the name in components/ instead of unbinding it on one platform'

# ── 3. operations.ps1 owns del/mvf and claims neither rm nor mv ───────────────
$opsPath = Join-Path $root 'components/files/operations.ps1'
$ops = Get-CodeOnly $opsPath
Ok ($ops -cmatch 'function del(?![\w-])')  'operations.ps1 should define del'
Ok ($ops -cmatch 'function mvf(?![\w-])')  'operations.ps1 should define mvf'
Ok ($ops -cnotmatch 'function rm(?![\w-])') 'operations.ps1 must not define rm'
Ok ($ops -cnotmatch 'function mv(?![\w-])') 'operations.ps1 must not define mv (mv-t / mv-c are their own names)'
Ok ($ops -cmatch 'function mv-t\b')  'mv-t stays — it is a PowerFlow name, not a coreutil'
Ok ($ops -cmatch 'function mv-c\b')  'mv-c stays'

# The three clones left for windows-only/.
foreach ($gone in @('mkdir', 'touch', 'rmdir')) {
    Ok ($ops -cnotmatch "function $gone(?![\w-])") "operations.ps1 must not define $gone — it moved to windows-only/coreutils.ps1"
}

# It may clear the built-in del aliases (del/erase/rd/ri are Remove-Item and would outrank
# the function), but it must NOT clear rm/mv/rmdir — those names have to keep resolving to
# the coreutils on Linux.
foreach ($mustNotClear in @('rm', 'mv', 'rmdir')) {
    Ok ($ops -cnotmatch "Alias:$mustNotClear\b") `
        "operations.ps1 must not remove the '$mustNotClear' alias — on Linux that name belongs to the GNU tool"
}

# ── 4. both commands report the name they were INVOKED as ─────────────────────
# Windows binds `rm` -> `del`, so a message reading "del:" after the user typed `rm` would
# name a command they never ran.
Ok ($ops -cmatch 'MyInvocation\.InvocationName') 'del/mvf should report the invoked name'
# ...but only when it IS one of their names. InvocationName echoes whatever the caller
# wrote: `& $cmd ...` reports "&", and an indirect call can report an empty string.
Ok ($ops -cmatch "notin @\('del', 'rm'\)")   'del must fall back to its canonical name for anything it cannot have been typed as'
Ok ($ops -cmatch "notin @\('mvf', 'mv'\)")   'mvf must do the same'
Ok ($ops -cmatch 'Invoke-GnuMove -Paths \$paths -Self \$self') 'the invoked name must reach Invoke-GnuMove, which prints its own errors'

# ── 5. listing.ps1 no longer aliases cat/cp ──────────────────────────────────
# PowerShell ships both on Windows already, so PowerFlow's versions added nothing there
# while hiding the real tools on Linux.
$listing = Get-CodeOnly (Join-Path $root 'components/files/listing.ps1')
Ok ($listing -cnotmatch 'Set-Alias cat\b') 'listing.ps1 must not alias cat'
Ok ($listing -cnotmatch 'Set-Alias cp\b')  'listing.ps1 must not alias cp'
Ok ($listing -cmatch 'function ls(?![\w-])')      'ls stays — the deliberate override'

# ── 6. windows-only/coreutils.ps1 holds the clones, with alias hygiene ───────
$coreutilsPath = Join-Path $root 'windows-only/coreutils.ps1'
Ok (Test-Path $coreutilsPath) 'windows-only/coreutils.ps1 should exist'
$clones = Get-CodeOnly $coreutilsPath
foreach ($fn in @('mkdir', 'touch', 'rmdir')) {
    Ok ($clones -cmatch "function $fn(?![\w-])") "windows-only/coreutils.ps1 should define $fn"
}
# `rmdir` is a built-in ALIAS for Remove-Item, and an alias outranks a function — without
# this the moved function is simply unreachable. That regressed once already, between the
# move and the first end-to-end load.
Ok ($clones -cmatch "'rmdir'") 'the Windows clones must clear the rmdir alias, or the function is unreachable'
Ok ($clones -cmatch 'Remove-Item "Alias:') 'the clones file should clear the aliases that outrank it'
Ok ($clones -cmatch "-Platform 'Windows'") 'the clones must register as Windows-only, or pwsh-h advertises them on Linux'

# ── 7. pwsh-h tells the truth on each platform ───────────────────────────────
# `del` is registered twice on purpose: components/ registers it for both platforms, and
# platform/windows/bindings.ps1 re-registers it with -Aliases @('rm') -Platform 'Windows'.
# Register-PFCommand assigns by name, so on Windows the later one wins and pwsh-h mentions
# `rm`; on Linux the bindings file never loads and the plain entry stands. That IS
# load-order dependent, which is why it is asserted rather than left as a comment.
$winBindings = Get-CodeOnly (Join-Path $root 'platform/windows/bindings.ps1')
Ok ($winBindings -cmatch 'Set-Alias rm del')  'Windows should bind rm -> del'
Ok ($winBindings -cmatch 'Set-Alias mv mvf')  'Windows should bind mv -> mvf'
Ok ($winBindings -cmatch "-Aliases @\('rm'\)")  'pwsh-h should show rm as a Windows alias of del'
Ok ($winBindings -cmatch "-Aliases @\('mv'\)")  'pwsh-h should show mv as a Windows alias of mvf'
Ok ($winBindings -cnotmatch 'Remove-Item "?Alias:') `
    'the Windows bindings file must only ADD names — removing one is how the old Linux file worked, and that is the arrangement being retired'

$profileText = Get-CodeOnly (Join-Path $root 'Microsoft.PowerShell_profile.ps1')
# _pf_path warns when a file is missing, and on Linux the missing bindings file is now the
# NORMAL case — so loading it through _pf_path would print a warning on every shell start.
Ok ($profileText -cmatch 'bindings\.ps1"\s*\)?\s*$|bindings\.ps1"') 'the profile should still look for a platform bindings file'
Ok ($profileText -cnotmatch '_pf_path "platform\\\$script:PowerFlowOS\\bindings\.ps1"') `
    'the profile must not load the bindings file through _pf_path — it warns, and absence is now normal on Linux'

# ── 8. behaviour: the invoked name reaches the message ────────────────────────
# Run in a CHILD SHELL's global scope, not this script's scope.
#
# `del` ships as an AllScope alias for Remove-Item, and an alias outranks a function. The
# clearing in operations.ps1 therefore only changes resolution when it runs at global scope
# — dot-sourcing the file from inside a test script leaves `del` still pointing at
# Remove-Item, and the assertion would be measuring the harness rather than the code. That
# is not a defect in either place; it is why this one check needs its own shell.
#
# A nonexistent target is deliberate: the unknown-option message prints before any
# filesystem work, so nothing is created or removed.
$pwshExe = (Get-Process -Id $PID).Path
foreach ($case in @(
    @{ Invoke = 'del'; Expect = 'del:' }
    @{ Invoke = 'mvf'; Expect = 'mvf:' }
)) {
    # Invoked by NAME, not through `& $var`: the call operator makes InvocationName report
    # "&", which would exercise a path no user can take.
    $script = "function Register-PFCommand { }; . '$opsPath'; " +
              "$($case.Invoke) --definitely-not-a-flag pf-nonexistent-target-xyz"
    $out = (@(& $pwshExe -NoProfile -Command $script 2>&1 | ForEach-Object { "$_" }) -join ' ')
    Ok ($out -clike "*$($case.Expect)*") "$($case.Invoke) should introduce itself as '$($case.Expect)'; got: $out"
}

# And the fallback: reached through the call operator, InvocationName is "&", which must not
# be echoed back at the user as though it were a command.
$fallback = (@(& $pwshExe -NoProfile -Command (
    "function Register-PFCommand { }; . '$opsPath'; " +
    "`$c = 'del'; & `$c --definitely-not-a-flag pf-nonexistent-target-xyz") 2>&1 |
    ForEach-Object { "$_" }) -join ' ')
Ok ($fallback -clike '*del:*') "an indirect call must still say 'del:', not '&:'; got: $fallback"
Ok ($fallback -cnotlike '*&:*') "the call operator must never be reported as the command name; got: $fallback"

Write-Host "  command names: $assertions assertions passed" -ForegroundColor Green
