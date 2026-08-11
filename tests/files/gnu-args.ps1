# ==============================================================================
# DECISIONS 1.1 — a single-dash WORD must never be shredded into flag letters
# ==============================================================================
# `Split-GnuArgs` is the argument parser behind rm, mv, rmdir, touch and mkdir — every
# destructive file command in PowerFlow — and it had no tests at all.
#
# It used to explode ANY single-dash token into its characters, which made the spelling of
# a word set flags nobody asked for. Measured on the real parser before the fix:
#
#   rm -force  x        -> c e f o r    -> recursive AND force   (the "r" in fo-r-ce)
#   rm -verbose x       -> b e o r s v  -> recursive
#   rm -interactive x   -> a c e i n r t v -> recursive
#
# So `-force`, the flag people reach for most reflexively, performed `rm -rf`, and the
# safest-sounding word of the three also switched on recursion. `ls` teaches single-dash
# words as the PowerFlow-friendly spelling, so the style the tree teaches was the unsafe one.
# ==============================================================================

$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
}
function Assert-Equal($Expected, $Actual, [string]$Message) {
    if ("$Expected" -cne "$Actual") { throw "FAIL: $Message`n  expected: $Expected`n  actual:   $Actual" }
}

$root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$assertions = 0

# Load ONLY the parser. The surrounding commands delete things; the parser is pure.
$source = Get-Content -LiteralPath (Join-Path $root 'components/files/operations.ps1') -Raw
$parser = [regex]::Match($source, '(?ms)^function Split-GnuArgs \{.*?^\}').Value
Assert-True ($parser.Length -gt 0) 'could not extract Split-GnuArgs'
Invoke-Expression $parser
$assertions++

# rm's real map, copied from its call site.
$rmMap = @{ 'recursive' = 'r'; 'force' = 'f'; 'verbose' = 'v'; 'interactive' = 'i'; 'dir' = 'd' }

function Get-Flags {
    param([string]$Token, [hashtable]$Map = $rmMap)
    $p = Split-GnuArgs -Argv @($Token, 'target') -LongMap $Map
    return [pscustomobject]@{
        Keys      = (($p.Flags.Keys | Sort-Object) -join '')
        Recursive = ($p.Flags.ContainsKey('r') -or $p.Flags.ContainsKey('R'))
        Force     = $p.Flags.ContainsKey('f')
        Unknown   = @($p.Unknown)
        Paths     = @($p.Paths)
    }
}

# ---- THE REGRESSION: a word must not imply flags its letters happen to contain --------
foreach ($case in @(
    @{ Token = '-force';        Recursive = $false; Force = $true;  Why = 'the r in "fo-r-ce" must not mean recursive' }
    @{ Token = '-verbose';      Recursive = $false; Force = $false; Why = 'the r in "ve-r-bose" must not mean recursive' }
    @{ Token = '-interactive';  Recursive = $false; Force = $false; Why = 'the safest-sounding word must not switch on recursion' }
)) {
    $r = Get-Flags $case.Token
    Assert-Equal $case.Recursive $r.Recursive "$($case.Token): $($case.Why)"
    Assert-Equal $case.Force     $r.Force     "$($case.Token): force flag wrong"
    $assertions += 2
}

# ---- a single-dash word must mean what the LONG form means ----------------------------
foreach ($pair in @(
    @{ Short = '-force';   Long = '--force' }
    @{ Short = '-verbose'; Long = '--verbose' }
)) {
    $s = Get-Flags $pair.Short
    $l = Get-Flags $pair.Long
    Assert-Equal $l.Keys $s.Keys "$($pair.Short) must set exactly what $($pair.Long) sets"
    $assertions++
}

# ---- real GNU bundles must still work ------------------------------------------------
$rf = Get-Flags '-rf'
Assert-True ($rf.Recursive -and $rf.Force) '-rf must still mean recursive AND force'
Assert-Equal 'fr' $rf.Keys '-rf should set exactly f and r'
$assertions += 2

foreach ($single in @(
    @{ Token = '-f'; Keys = 'f' }, @{ Token = '-r'; Keys = 'r' },
    @{ Token = '-i'; Keys = 'i' }, @{ Token = '-v'; Keys = 'v' }, @{ Token = '-R'; Keys = 'R' }
)) {
    Assert-Equal $single.Keys (Get-Flags $single.Token).Keys "$($single.Token) should set exactly $($single.Keys)"
    $assertions++
}

# ---- an unrecognised token is REFUSED, and sets nothing -------------------------------
# This is the seatbelt: a token the parser does not understand can no longer set a
# destructive flag as a side effect of how it is spelled.
foreach ($bad in @('-zz', '-recurse', '-nope', '-xyzzy')) {
    $r = Get-Flags $bad
    Assert-Equal '' $r.Keys "$bad must set NO flags"
    Assert-True ($r.Unknown -contains $bad) "$bad must be reported as an unknown option"
    Assert-True (-not $r.Recursive) "$bad must not imply recursive"
    Assert-True (-not $r.Force) "$bad must not imply force"
    $assertions += 4
}

# ---- long forms and paths still behave ------------------------------------------------
Assert-Equal 'r' (Get-Flags '--recursive').Keys '--recursive should set r'
Assert-Equal 'f' (Get-Flags '--force').Keys '--force should set f'
$unknownLong = Get-Flags '--not-a-flag'
Assert-True ($unknownLong.Unknown -contains '--not-a-flag') 'an unknown long option must be reported'
Assert-Equal '' $unknownLong.Keys 'an unknown long option must set no flags'
$assertions += 4

# `--` ends flag parsing, and a lone `-` is a path by stdin convention.
$after = Split-GnuArgs -Argv @('--', '-rf') -LongMap $rmMap
Assert-Equal '-rf' ($after.Paths -join ',') 'everything after -- must be a path'
Assert-Equal '' (($after.Flags.Keys | Sort-Object) -join '') 'nothing after -- may set a flag'
$dash = Split-GnuArgs -Argv @('-') -LongMap $rmMap
Assert-Equal '-' ($dash.Paths -join ',') 'a lone dash is a path, not a flag'
$assertions += 3

# ---- the other commands that share this parser ---------------------------------------
# mv, rmdir, touch and mkdir each pass a different map, so each has a different valid
# bundle alphabet. The rule must hold for all of them.
$maps = @{
    mv    = @{ 'force' = 'f'; 'no-clobber' = 'n'; 'verbose' = 'v'; 'interactive' = 'i' }
    rmdir = @{ 'parents' = 'p'; 'verbose' = 'v' }
    touch = @{ 'no-create' = 'c'; 'verbose' = 'v' }
    mkdir = @{ 'parents' = 'p'; 'verbose' = 'v' }
}
foreach ($name in $maps.Keys) {
    $map = $maps[$name]
    foreach ($word in $map.Keys) {
        $r = Get-Flags "-$word" $map
        Assert-Equal $map[$word] $r.Keys "$name -$word must set exactly '$($map[$word])'"
        $assertions++
    }
    # A word this command does not declare must be refused, not shredded.
    $r = Get-Flags '-recursive' $map
    if (-not $map.ContainsKey('recursive')) {
        Assert-Equal '' $r.Keys "$name -recursive is not declared and must set no flags"
        $assertions++
    }
}

Write-Host "  GNU argument parser: $assertions assertions passed" -ForegroundColor Green
