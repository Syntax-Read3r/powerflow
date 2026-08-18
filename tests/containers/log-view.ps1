# ==============================================================================
# PF-FEAT-005 (b2) — readable logs, and a lifecycle view without Go templates
# ==============================================================================
# The native sequence being replaced:
#
#   podman logs --tail 30 --timestamps web-test
#   podman inspect web-test --format 'Exit={{.State.ExitCode}} Finished={{.State.FinishedAt}}'
#   podman inspect web-test --format 'StopSignal={{.Config.StopSignal}}'
#
# The risky half is the tidying. A log view that collapses lines is making a claim about
# which lines do not matter, and the one time it is wrong it hides the line somebody was
# reading the log to find. So most of this file is about what the cleaner must NEVER touch:
# errors, warnings, non-zero exits, OOM, auth failures, HTTP lines, signals and stack
# traces — however often they repeat.
#
# And one claim that must not be made: the configured stop signal is reported as CONFIGURED.
# Podman does not tell us which signal actually stopped the container, so "SIGQUIT stopped
# it" would be a causal link invented out of a default.
# ==============================================================================

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

$fail = 0
function Ok([bool]$c, [string]$m, [string]$d = '') {
    if (-not $c) { $script:fail++ }
    Write-Host ("  {0} {1}{2}" -f $(if ($c) { 'ok  ' } else { 'FAIL' }), $m, $(if ($d) { "   $d" } else { '' }))
}

# Load only the log layer: containers.ps1 registers commands and probes for an engine.
$text = Get-Content -LiteralPath (Join-Path $root 'components/containers/containers.ps1') -Raw
$ast  = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$null)
foreach ($name in @('Split-PFContainerLogLine', 'Compress-PFContainerLog', 'Get-PFLogLineColour',
                    'Format-PFContainerTime', 'Test-PFContainerCanPick')) {
    $fn = $ast.FindAll({
        $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $args[0].Name -eq $name }, $true)
    if ($fn.Count -ne 1) { Write-Host "could not extract $name"; exit 1 }
    Invoke-Expression $fn[0].Extent.Text
}
# The never-collapse list is script-scoped data, not a function.
$listAst = $ast.FindAll({
    $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] -and
    "$($args[0].Left)" -match 'PF_LogNeverCollapse' }, $true)
if ($listAst.Count -ne 1) { Write-Host 'could not extract the never-collapse list'; exit 1 }
Invoke-Expression $listAst[0].Extent.Text

Write-Host 'PF-FEAT-005 (b2) container logs'

# ── 1. the line parser ───────────────────────────────────────────────────────
Write-Host ''
Write-Host '-- timestamps and service prefixes are fields, not text ---------'
$e = Split-PFContainerLogLine '2026-08-18T10:26:20.123456789Z nginx 1.31.3 starting'
Ok ($null -ne $e.Time) 'an RFC3339 stamp is parsed'
Ok ($e.Message -ceq 'nginx 1.31.3 starting') 'and removed from the message' "'$($e.Message)'"
Ok ($e.Service -ceq '') 'a plain container line has no service'

$e = Split-PFContainerLogLine 'web-1  | 2026-08-18T10:26:20Z GET / 200'
Ok ($e.Service -ceq 'web-1') 'a compose service prefix is captured'
Ok ($e.Message -ceq 'GET / 200') 'and the message is what remains'
Ok ($null -ne $e.Time) 'with the timestamp still parsed'

# A line the parser does not understand is still evidence.
$e = Split-PFContainerLogLine 'some line with no timestamp at all'
Ok ($null -eq $e.Time) 'an unstamped line has no time'
Ok ($e.Message -ceq 'some line with no timestamp at all') 'and is returned whole, not mangled'

$e = Split-PFContainerLogLine '2026-13-45T99:99:99Z broken stamp'
Ok ($e.Message -match 'broken stamp') 'an unparseable stamp does not lose the message'

# ── 2. collapsing, and only where it is safe ─────────────────────────────────
Write-Host ''
Write-Host '-- identical adjacent noise collapses --------------------------'
$rows = @(Compress-PFContainerLog -Entries @(
    (Split-PFContainerLogLine '2026-08-18T10:00:00Z worker started')
    (Split-PFContainerLogLine '2026-08-18T10:00:01Z worker started')
    (Split-PFContainerLogLine '2026-08-18T10:00:02Z worker started')
))
Ok ($rows.Count -eq 1) 'three identical lines become one row' "got $($rows.Count)"
Ok ($rows[0].Repeats -eq 3) 'with an honest count' "x$($rows[0].Repeats)"

# Never across a different line: order is evidence.
$rows = @(Compress-PFContainerLog -Entries @(
    (Split-PFContainerLogLine '2026-08-18T10:00:00Z worker started')
    (Split-PFContainerLogLine '2026-08-18T10:00:01Z something else')
    (Split-PFContainerLogLine '2026-08-18T10:00:02Z worker started')
))
Ok ($rows.Count -eq 3) 'a non-adjacent repeat is NOT merged with the first' "got $($rows.Count)"

# ── 3. THE list. Nothing here may ever be collapsed. ─────────────────────────
Write-Host ''
Write-Host '-- the never-collapse list -------------------------------------'
$protected = @(
    @{ Line = 'ERROR connection refused';                     Why = 'an error' }
    @{ Line = 'WARN disk nearly full';                        Why = 'a warning' }
    @{ Line = 'FATAL cannot bind port';                       Why = 'a fatal' }
    @{ Line = 'panic: runtime error: index out of range';     Why = 'a panic' }
    @{ Line = 'java.lang.NullPointerException: boom';         Why = 'an exception' }
    @{ Line = '    at com.example.Thing.run(Thing.java:42)';  Why = 'a stack frame' }
    @{ Line = 'Traceback (most recent call last):';           Why = 'a python traceback' }
    @{ Line = 'Out of memory: killed process 1234';           Why = 'an OOM kill' }
    @{ Line = 'authentication failure for user admin';        Why = 'an auth failure' }
    @{ Line = 'permission denied opening /etc/shadow';        Why = 'a permission denial' }
    @{ Line = 'process exited with code 137';                 Why = 'a non-zero exit' }
    @{ Line = 'SIGTERM received';                             Why = 'a signal' }
    @{ Line = 'GET /favicon.ico HTTP/1.1 404';                Why = 'an HTTP request line' }
    @{ Line = 'upstream returned 503';                        Why = 'a 5xx status' }
)
foreach ($case in $protected) {
    $entries = @(1..4 | ForEach-Object { Split-PFContainerLogLine "2026-08-18T10:00:0${_}Z $($case.Line)" })
    $rows = @(Compress-PFContainerLog -Entries $entries)
    Ok ($rows.Count -eq 4) "$($case.Why) is never collapsed, however often it repeats" "'$($case.Line)'"
}

# A clean exit is NOT on the list — only a non-zero one is. Otherwise "exited 0" repeated
# forty times is noise the view is supposed to tidy.
$entries = @(1..3 | ForEach-Object { Split-PFContainerLogLine "2026-08-18T10:00:0${_}Z process exited with code 0" })
Ok ((@(Compress-PFContainerLog -Entries $entries)).Count -eq 1) 'a repeated CLEAN exit may collapse'

# ── 4. a protected line never absorbs its neighbour ──────────────────────────
Write-Host ''
Write-Host '-- a protected line stands alone -------------------------------'
$rows = @(Compress-PFContainerLog -Entries @(
    (Split-PFContainerLogLine '2026-08-18T10:00:00Z worker started')
    (Split-PFContainerLogLine '2026-08-18T10:00:01Z ERROR boom')
    (Split-PFContainerLogLine '2026-08-18T10:00:02Z worker started')
    (Split-PFContainerLogLine '2026-08-18T10:00:03Z worker started')
))
Ok ($rows.Count -eq 3) 'the error splits the run rather than being swallowed'
Ok ($rows[1].Message -match 'ERROR') 'and keeps its position in order'
Ok ($rows[2].Repeats -eq 2) 'the run after it collapses on its own'

# Nothing is ever dropped: every input line is accounted for by the counts.
$entries = @(
    (Split-PFContainerLogLine '2026-08-18T10:00:00Z a'), (Split-PFContainerLogLine '2026-08-18T10:00:01Z a')
    (Split-PFContainerLogLine '2026-08-18T10:00:02Z b'), (Split-PFContainerLogLine '2026-08-18T10:00:03Z ERROR x')
    (Split-PFContainerLogLine '2026-08-18T10:00:04Z ERROR x')
)
$rows = @(Compress-PFContainerLog -Entries $entries)
Ok ((@($rows | Measure-Object -Property Repeats -Sum).Sum) -eq $entries.Count) `
    'the counts add back up to every input line — nothing is silently dropped'

# Different services never merge, even with an identical message.
$rows = @(Compress-PFContainerLog -Entries @(
    (Split-PFContainerLogLine 'web-1  | 2026-08-18T10:00:00Z ready')
    (Split-PFContainerLogLine 'api-1  | 2026-08-18T10:00:01Z ready')
))
Ok ($rows.Count -eq 2) 'two services saying the same thing stay two lines'

# ── 5. colour marks severity, and only where earned ──────────────────────────
Write-Host ''
Write-Host '-- severity colouring ------------------------------------------'
Ok ((Get-PFLogLineColour 'ERROR nope') -ceq 'Red') 'an error is red'
Ok ((Get-PFLogLineColour 'upstream 502') -ceq 'Red') 'a 5xx is red'
Ok ((Get-PFLogLineColour 'WARN slow') -ceq 'Yellow') 'a warning is yellow'
Ok ((Get-PFLogLineColour 'GET /x 404') -ceq 'Yellow') 'a 4xx is yellow'
Ok ((Get-PFLogLineColour 'SIGTERM received') -ceq 'Magenta') 'a signal stands out'
Ok ((Get-PFLogLineColour 'nginx starting') -ceq 'White') 'an ordinary line is not decorated'

# ── 6. times ─────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '-- the never-finished sentinel is not printed as a time ---------'
Ok ((Format-PFContainerTime '0001-01-01T00:00:00Z') -ceq '') 'a zero year renders as nothing, not as a date'
Ok ((Format-PFContainerTime '') -ceq '') 'an absent value renders as nothing'
Ok ((Format-PFContainerTime '2026-08-18T12:39:06Z') -match '^\d{2}:\d{2}:\d{2}$') 'a real time renders as a clock time'
Ok ((Format-PFContainerTime 'not-a-date') -ceq 'not-a-date') 'an unparseable value is shown as-is rather than swallowed'

# ── 7. the claims the view must not make ─────────────────────────────────────
Write-Host ''
Write-Host '-- no invented causation, no premature verdict -----------------'
function Remove-PSComment {
    param([string]$Source)
    $tokens = $null
    $null = [System.Management.Automation.Language.Parser]::ParseInput($Source, [ref]$tokens, [ref]$null)
    $builder = [Text.StringBuilder]::new($Source)
    foreach ($token in @($tokens | Where-Object { $_.Kind -eq 'Comment' })) {
        $start = $token.Extent.StartOffset
        $length = $token.Extent.EndOffset - $start
        $null = $builder.Remove($start, $length).Insert($start, (' ' * $length))
    }
    return $builder.ToString()
}
$clean = Remove-PSComment $text
$lifecycle = [regex]::Match($clean, '(?s)function Show-PFContainerLifecycle \{.*?\n\}').Value
Ok ($lifecycle.Length -gt 0) 'found the lifecycle view'
Ok ($lifecycle -match '\(configured\)') 'the stop signal is labelled CONFIGURED'
Ok ($lifecycle -notmatch '(?i)stopped by|caused|because of') `
    'it never claims the configured signal caused anything in the log'

# "0 · clean" is a verdict about a finished container. A RUNNING container also has
# ExitCode 0, and reporting that as a clean exit describes something that has not happened.
Ok ($lifecycle -match "notin @\('running'") 'a clean-exit verdict is gated on the container having finished'

# ── 8. follow is streamed, never grouped ─────────────────────────────────────
Write-Host ''
Write-Host '-- follow mode does not buffer ---------------------------------'
$logsView = [regex]::Match($clean, '(?s)function Invoke-ContainerLogsView \{.*?\n\}').Value
Ok ($logsView.Length -gt 0) 'found the logs view'
$followBranch = [regex]::Match($logsView, '(?s)if \(\$Follow\) \{.*?\n    \}').Value
Ok ($followBranch -match 'Invoke-ContainerInteractive') 'follow streams through the terminal'
Ok ($followBranch -notmatch 'Compress-PFContainerLog') `
    'and is never passed through the grouper — timing and order are the evidence while tailing'

# ── 9. the tail default, and the shorthand that must not exist ───────────────
Write-Host ''
Write-Host '-- tail grammar ------------------------------------------------'
Ok ($logsView -match '\[int\]\$Tail = 30') 'the default tail is 30, not a screenful and a half'
$dispatch = [regex]::Match($clean, "(?s)if \(\`$verb -eq 'logs'\) \{.*?\n    \}").Value
Ok ($dispatch -match 'SkipLast 1') 'a trailing integer is accepted as the tail'
# Podman's own `logs -n` means --names. Borrowing it would build a habit that silently
# means something else natively.
Ok ($clean -notmatch "'-n'\s*,\s*'--tail'" -and $clean -notmatch "-n', '--tail") `
    "-n is NOT bound to --tail (podman's -n means --names)"

# ── 10. a redirected session never opens a picker ────────────────────────────
Write-Host ''
Write-Host '-- no picker in a pipe -----------------------------------------'
Ok ([Console]::IsOutputRedirected) 'precondition: this harness runs redirected'
Ok (-not (Test-PFContainerCanPick)) 'so the picker predicate refuses'
Ok ($dispatch -match 'Test-PFContainerCanPick') 'and the logs verb consults it before picking'
$inspectDispatch = [regex]::Match($clean, "(?s)if \(\`$verb -in @\('inspect', 'show'\)\) \{.*?\n    \}").Value
Ok ($inspectDispatch.Length -gt 0) 'found the inspect verb'
Ok ($inspectDispatch -match 'Test-PFContainerCanPick') 'and inspect consults it too'

Write-Host ''
if ($fail) { Write-Host "$fail CHECK(S) FAILED"; exit 1 }
Write-Host 'PF-FEAT-005 (b2): logs are tidied without losing evidence, and inspect claims only what it knows.'
