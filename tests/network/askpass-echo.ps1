# ==============================================================================
# PF-BUG-006 — the password prompt must not echo what you type
# ==============================================================================
# Reported from a real connection:
#
#     ❯ srv web-prod
#     Password for 'web-prod': hunter2
#     ********
#
# Both lines are real, and together they name the cause exactly. A Windows console handle
# arrives with ENABLE_ECHO_INPUT and ENABLE_LINE_INPUT already ON:
#
#   * ENABLE_ECHO_INPUT — the CONSOLE prints each keystroke itself. That is line one, in
#     cleartext, and therefore in scrollback, in screenshots, and in any recorded session.
#   * ENABLE_LINE_INPUT — ReadConsole blocks until Enter, so the helper's own per-character
#     '*' writes all arrive afterwards. That is line two, on its own.
#
# The helper masked visibly and per character, which is why it read as careful code. The
# defect was not a missing feature but an unstated assumption: that a console handle starts
# in raw mode. It does not.
#
# The Linux sibling was always correct — `stty -g` to save, `stty -echo` to clear, restore
# from an EXIT/HUP/INT/TERM trap — so this pins BOTH helpers to the same three properties.
#
# WHY THIS IS A SOURCE TEST. The behaviour needs a real console: a redirected or piped stdin
# is not a console handle, GetConsoleMode fails against it, and the whole path under test is
# skipped. A test that ran green in CI against a pipe would assert nothing at all. So this
# asserts on the source, and says so rather than implying more coverage than it has.
# ==============================================================================

$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$assertions = 0
function Ok([bool]$c, [string]$m) {
    if (-not $c) { throw "FAIL: $m" }
    $script:assertions++
}

# ── Windows: the C# helper ────────────────────────────────────────────────────
$winPath = Join-Path $root 'platform/windows/helpers/powerflow-ssh-askpass.cs'
Ok (Test-Path $winPath) 'the Windows askpass helper should exist'
$win = Get-Content -LiteralPath $winPath -Raw

# Strip // and /* */ comments so the explanatory prose above the code cannot satisfy a check.
# Three tests in this tree have already passed on their own comments.
$winCode = [regex]::Replace($win, '(?s)/\*.*?\*/', '')
$winCode = [regex]::Replace($winCode, '(?m)^\s*//.*$', '')

Ok ($winCode -match 'GetConsoleMode') 'must read the current console mode before changing it'
Ok ($winCode -match 'SetConsoleMode') 'must set the console mode'
Ok ($winCode -match 'EnableEchoInput\s*=\s*0x0004') 'ENABLE_ECHO_INPUT must be the real constant 0x0004'
Ok ($winCode -match 'EnableLineInput\s*=\s*0x0002') 'ENABLE_LINE_INPUT must be the real constant 0x0002'

# The clear itself: both flags, removed together.
Ok ($winCode -match 'originalMode\s*&\s*~\(\s*EnableEchoInput\s*\|\s*EnableLineInput\s*\)') `
    'both flags must be cleared from the saved mode'

# ORDER MATTERS THREE TIMES, and each ordering is a separate way to reintroduce the bug.
$idxGet     = $winCode.IndexOf('GetConsoleMode(input, out originalMode)')
$idxClear   = $winCode.IndexOf('originalMode & ~')
$idxPrompt  = $winCode.IndexOf('WriteTerminal(output, "Password for')
$idxRestore = $winCode.IndexOf('if (modeSaved) SetConsoleMode(input, originalMode);')
$idxClose   = if ($idxRestore -ge 0) { $winCode.IndexOf('CloseHandle(input);', $idxRestore) } else { -1 }

Ok ($idxGet -ge 0 -and $idxGet -lt $idxClear) 'the mode must be SAVED before it is changed'
Ok ($idxClear -ge 0 -and $idxClear -lt $idxPrompt) `
    'echo must be cleared BEFORE the prompt is printed, or the first keystrokes still echo'
Ok ($idxRestore -ge 0) 'the original mode must be restored'
Ok ($idxClose -gt $idxRestore) 'the restore must happen BEFORE the handle is closed'

# The restore must be in `finally`, so the Ctrl+C, Ctrl+D and failed-read paths all reach it.
# Leaving a console with echo disabled looks like a dead terminal — worse than the original bug.
$finallyIdx = $winCode.LastIndexOf('finally')
Ok ($finallyIdx -ge 0 -and $idxRestore -gt $finallyIdx) `
    'the restore must sit in the finally block so every exit path reaches it'

# Guarded on the save having worked: restoring an uncaptured mode would set the console to 0.
Ok ($winCode -match 'bool modeSaved = GetConsoleMode') 'the restore must be guarded by whether the save succeeded'
Ok ($winCode -match 'if \(modeSaved\)') 'the clear must also be guarded'

# The secret must still never be held longer than needed, or the fix has cost something.
Ok ($winCode -match 'Array\.Clear\(secret') 'the secret buffer must still be cleared'
Ok ($winCode -match "password\[i\] = '\\0'") 'the character list must still be scrubbed'

# ── Linux: the shell helper, same three properties ───────────────────────────
# Included so the pair cannot drift: this one was already right, and a regression here would
# be invisible from Windows.
$linPath = Join-Path $root 'platform/linux/helpers/powerflow-ssh-askpass.sh'
Ok (Test-Path $linPath) 'the Linux askpass helper should exist'
$lin = Get-Content -LiteralPath $linPath -Raw
$linCode = [regex]::Replace($lin, '(?m)^\s*#.*$', '')

Ok ($linCode -match 'stty -g') 'Linux: must save the terminal state'
Ok ($linCode -match 'stty -echo') 'Linux: must disable echo'
Ok ($linCode -match 'trap .*EXIT') 'Linux: must restore from a trap, not only on the happy path'
Ok ($linCode -match 'HUP|INT|TERM') 'Linux: the trap must cover signals, not just a clean exit'

# stdout is OpenSSH's private pipe; the prompt must go to the terminal instead, or the
# password prompt itself would be fed back to ssh as if it were the answer.
Ok ($linCode -match '/dev/tty') 'Linux: human-facing text must go to the terminal, not to the askpass pipe'

# ── neither helper may print the secret ──────────────────────────────────────
foreach ($pair in @(@{ N = 'Windows'; C = $winCode }, @{ N = 'Linux'; C = $linCode })) {
    Ok ($pair.C -notmatch '(?i)Write-Host.*\$password|echo .*\$password\b') `
        "$($pair.N): must never print the collected password"
}

Write-Host "  askpass echo (PF-BUG-006): $assertions assertions passed" -ForegroundColor Green
