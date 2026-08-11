# =============================================================================
# PF-BUG-002 root cause -- a JSON payload must never be truncated
# =============================================================================
# ConvertTo-PmxManagementSafeText applied a flat 2000-character cap to every line of every
# stream, including the stdout PAYLOAD. `pvesh --output-format json` emits one compact
# single-line document, so any response over 2000 characters was cut mid-token before
# ConvertFrom-Json saw it, and surfaced as "Proxmox returned malformed JSON".
#
# Measured: a running VM's status/current is ~3.8 KB on one line -- blockstat for every block
# device plus ballooninfo. Truncated at 2000 it fails with "Unterminated string ... position
# 2000". A STOPPED VM omits blockstat, which is why stopped VMs worked and running ones did not.
#
# It also produced PF-BUG-004: the "Current VM status could not be read" warning came from this
# same failed vm-status query. One truncation, two separately-filed bugs.
#
# The salvage path added for PF-BUG-002 cannot rescue this -- it strips LEADING noise, and this
# document is cut at the END. That is why the cap itself had to change.
# =============================================================================

. (Join-Path $PSScriptRoot 'test-helpers.ps1')

$root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$platform = if ($IsLinux) { 'linux' } else { 'windows' }
. (Join-Path $root "platform/$platform/adapters/proxmox-management.ps1")

# Build a realistic single-line status/current document.
$blockstat = (1..14 | ForEach-Object {
    '"blockstat_scsi{0}":{{"rd_bytes":1234567890,"wr_bytes":9876543210,"rd_operations":424242,' -f $_ +
    '"wr_operations":242424,"flush_operations":13131,"rd_total_time_ns":555555555,' +
    '"wr_total_time_ns":666666666,"flush_total_time_ns":777777,"rd_merged":0,"wr_merged":0}'
}) -join ','
$payload = '{"data":{"status":"running","vmid":102,"name":"docker-host","uptime":864000,' +
           '"maxmem":8589934592,"cpus":4,' + $blockstat +
           ',"ballooninfo":{"actual":8589934592,"free_mem":4294967296}}}'

Assert-PmxTest ($payload.Length -gt 2000) "the fixture must exceed the old 2000-char cap to be meaningful (is $($payload.Length))"
Assert-PmxTest ($payload -notmatch "`n") 'the fixture must be a SINGLE line, which is what pvesh emits'

# ---- the payload survives the sanitiser at the payload ceiling ----------------------
$safe = ConvertTo-PmxManagementSafeText $payload -MaxLength $script:PF_PmxPayloadMaxLength
Assert-PmxTest ($safe.Length -eq $payload.Length) `
    "a legitimate payload must not be shortened (was $($payload.Length), now $($safe.Length))"
$parsedOk = $true
try { $null = $safe | ConvertFrom-Json } catch { $parsedOk = $false }
Assert-PmxTest $parsedOk 'the sanitised payload must still parse as JSON'

# ---- and the old behaviour really did break it, so the test has teeth ---------------
$truncated = ConvertTo-PmxManagementSafeText $payload -MaxLength 2000
Assert-PmxTest ($truncated.Length -eq 2000) 'an explicit small cap should still truncate'
$brokeAsExpected = $false
try { $null = $truncated | ConvertFrom-Json } catch { $brokeAsExpected = $true }
Assert-PmxTest $brokeAsExpected `
    'the fixture must genuinely fail to parse when cut at 2000, or it does not reproduce the bug'

# ---- the ceiling is generous but still bounded --------------------------------------
Assert-PmxTest ($script:PF_PmxPayloadMaxLength -ge 262144) 'the payload ceiling must comfortably exceed any real pvesh document'
Assert-PmxTest ($script:PF_PmxPayloadMaxLength -le 8388608) 'the payload ceiling must still bound a runaway response'

# ---- control-character stripping is unconditional, and cannot corrupt JSON ----------
# Those bytes are not legal inside a JSON document, so removing them is always safe.
$withControls = "{`"a`":`"b`"}" + [char]7 + [char]27 + '[31m'
$cleaned = ConvertTo-PmxManagementSafeText $withControls -MaxLength $script:PF_PmxPayloadMaxLength
Assert-PmxTest ($cleaned -notmatch [char]27) 'ANSI escapes must still be stripped from a payload'
Assert-PmxTest ($cleaned -match '^\{"a":"b"\}') 'stripping must not disturb the JSON itself'

# ---- stderr keeps the tight default, because it is only ever displayed --------------
$longErr = 'x' * 5000
Assert-PmxTest ((ConvertTo-PmxManagementSafeText $longErr).Length -eq 2000) `
    'displayed text should still default to a 2000-character cap'

# ---- the payload ceiling is actually WIRED to the stdout stream ---------------------
# The fix is worthless if the call site still uses the default.
foreach ($p in @('linux', 'windows')) {
    $text = Get-Content -LiteralPath (Join-Path $root "platform/$p/adapters/proxmox-management.ps1") -Raw
    $code = @($text -split "`r?`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
    Assert-PmxTest ($code -match '\$stdout = @\([\s\S]{0,400}?PF_PmxPayloadMaxLength') `
        "$p : the stdout stream must be sanitised with the PAYLOAD ceiling, not the display default"
    Assert-PmxTest ($code -notmatch 'Substring\(0, 2000\)') `
        "$p : no flat 2000-character truncation should remain"
}

Write-PmxTestPass 'PF-BUG-002 root cause: a single-line JSON payload survives sanitisation intact'
