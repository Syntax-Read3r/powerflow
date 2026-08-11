# ==============================================================================
# PF-BUG-002 — "malformed JSON" must say WHICH failure it was, and leak nothing
# ==============================================================================
# The report supplied a clean reproduction (`pmx disk list --vm 102 --table` on a VM that
# `qm config` shows is healthy) and no root cause, because the error collapsed at least
# eight distinct failures into one sentence:
#
#   contaminated stdout · stderr merged into stdout · empty response · two JSON documents
#   concatenated · native text where JSON was expected · encoding/newline · local vs ssh
#   transport difference · a genuinely malformed payload
#
# Two things were ruled out first, so this file does not re-test them:
#   * The invocation parser is NOT at fault. Get-PmxReadInvocation was run over
#     `--vm 102`, `--vm 102 --table`, `--table`, `102 --table` and `--table --vm 102`;
#     every case consumed --table as a switch and resolved the selector to 102. So an output
#     flag does not influence the request, which was the report's own leading hypothesis.
#   * The CD-ROM complaint is already fixed: disk-model.ps1:40 skips media=cdrom and
#     cloudinit, so `ide2: none,media=cdrom` is not offered as a growable disk.
# ==============================================================================

. (Join-Path $PSScriptRoot 'test-helpers.ps1')

$root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

# Load the adapter for THIS platform, and the other one's helpers for parity checks.
$platform = if ($IsLinux) { 'linux' } else { 'windows' }
. (Join-Path $root "platform/$platform/adapters/proxmox-management.ps1")

# ---- 1. a clean payload must parse strictly, with no "stripped" note -----------------
$clean = ConvertFrom-PmxJsonPayload -Json '{"data":[{"vmid":102,"name":"docker-host"}]}'
Assert-PmxTest $clean.Success 'a clean JSON payload must parse'
Assert-PmxTest ($clean.Note -eq '') 'a clean payload must not be reported as contaminated'
Assert-PmxTest ("$($clean.Data.data[0].name)" -ceq 'docker-host') 'the parsed payload is wrong'

# ---- 2. each failure class produces a DISTINCT note ----------------------------------
$empty = ConvertFrom-PmxJsonPayload -Json ''
Assert-PmxTest (-not $empty.Success) 'an empty response must not be reported as success'
Assert-PmxTest ($empty.Note -ceq 'empty response') "empty response note wrong: '$($empty.Note)'"

$noJson = ConvertFrom-PmxJsonPayload -Json 'qm: command not found'
Assert-PmxTest (-not $noJson.Success) 'native text must not parse as JSON'
Assert-PmxTest ($noJson.Note -match 'no JSON document') "no-JSON note wrong: '$($noJson.Note)'"

$broken = ConvertFrom-PmxJsonPayload -Json '{"data":[{"vmid":102,'
Assert-PmxTest (-not $broken.Success) 'a truncated document must not parse'
Assert-PmxTest ($broken.Note -match 'malformed') "malformed note wrong: '$($broken.Note)'"

# ---- 3. leading noise is recovered, and the recovery is REPORTED ---------------------
# Quietly accepting contamination would turn a reportable defect into a permanent mystery,
# so a successful salvage still has to say what it stripped.
$banner = "WARNING: you are using a deprecated API`n{""data"":[{""vmid"":102}]}"
$salvaged = ConvertFrom-PmxJsonPayload -Json $banner
Assert-PmxTest $salvaged.Success 'a banner ahead of the JSON should still be recoverable'
Assert-PmxTest ($salvaged.Note -match 'stripped \d+ leading characters') `
    "a salvage must be reported, not silent. Note: '$($salvaged.Note)'"
Assert-PmxTest ("$($salvaged.Data.data[0].vmid)" -ceq '102') 'the salvaged payload is wrong'

# ---- 4. the diagnostics record carries what the report asked for ---------------------
$run = [pscustomobject]@{
    StdOut = @('WARNING: deprecated', '{"data":[]}')
    StdErr = @('some stderr text')
    ExitCode = 0
    NativeCommand = 'qm config 102'
}
$diag = Get-PmxParseDiagnostics -Operation 'managed-vm-disks' -Transport 'ssh' -Run $run -Note 'test'
foreach ($field in @('CommandClass', 'Transport', 'Parser', 'ExitCode', 'StdOutBytes', 'StdErrBytes')) {
    Assert-PmxTest ($null -ne $diag.$field) "the diagnostics record is missing $field"
}
Assert-PmxTest ($diag.CommandClass -ceq 'managed-vm-disks') 'CommandClass wrong'
Assert-PmxTest ($diag.Transport -ceq 'ssh') 'Transport wrong'
Assert-PmxTest ($diag.StdOutBytes -gt 0) 'StdOutBytes should be counted'
Assert-PmxTest (-not $diag.LooksLikeJson) 'a leading banner means the payload does not look like JSON'
Assert-PmxTest ($diag.FirstChar -ceq 'W') "FirstChar should expose the contaminating character, got '$($diag.FirstChar)'"

# A local transport must still be labelled, not left blank.
$localDiag = Get-PmxParseDiagnostics -Operation 'x' -Transport '' -Run $run
Assert-PmxTest ($localDiag.Transport -ceq 'local') 'an empty transport must be reported as local'

# ---- 5. PRIVACY: diagnostics must never leak an endpoint or a secret -----------------
# PowerFlow's contract is that ordinary output names a saved alias, never an endpoint. A raw
# payload preview is exactly where an address would escape, so the scrubber is load-bearing.
$hostile = [pscustomobject]@{
    StdOut = @('error connecting to root@pve.example.net (192.168.1.50:22)',
               'ipv6 fe80::1c2d:3e4f:5a6b:7c8d refused',
               'password: hunter2', 'token=abcdef123456')
    StdErr = @('ssh: connect to host 10.0.0.7 port 22: Connection refused')
    ExitCode = 255
    NativeCommand = 'qm config 102'
}
$hostileDiag = Get-PmxParseDiagnostics -Operation 'managed-vm-disks' -Transport 'ssh' -Run $hostile
$rendered = ($hostileDiag.PSObject.Properties | ForEach-Object { "$($_.Value)" }) -join "`n"

Assert-PmxTest ($rendered -notmatch '\b\d{1,3}(\.\d{1,3}){3}\b') `
    "diagnostics leaked an IPv4 address:`n$rendered"
Assert-PmxTest ($rendered -notmatch '[\w.+-]+@[\w.-]+') `
    "diagnostics leaked a user@host:`n$rendered"
Assert-PmxTest ($rendered -notmatch 'hunter2') "diagnostics leaked a password:`n$rendered"
Assert-PmxTest ($rendered -notmatch 'abcdef123456') "diagnostics leaked a token:`n$rendered"
Assert-PmxTest ($rendered -notmatch 'fe80::1c2d') "diagnostics leaked an IPv6 address:`n$rendered"

# user@host must collapse WHOLE, not leave the hostname behind.
Assert-PmxTest ((Protect-PmxDiagnosticText 'root@pve.example.net') -notmatch 'pve\.example\.net') `
    'scrubbing user@host must not leave the bare hostname behind'

# And the scrubber must tolerate empty input rather than throwing.
Assert-PmxTest ((Protect-PmxDiagnosticText '') -ceq '') 'the scrubber must accept an empty string'

# ---- 6. the result object carries Diagnostics ----------------------------------------
$result = New-PmxManagementResult $false $null 'msg' 1 'qm config 102' '' $hostileDiag
Assert-PmxTest ($null -ne $result.Diagnostics) 'a failed result must be able to carry diagnostics'
Assert-PmxTest ($result.Diagnostics.CommandClass -ceq 'managed-vm-disks') 'diagnostics did not survive onto the result'
# A successful result carries none, so nothing is printed on the happy path.
$ok = New-PmxManagementResult $true @{} '' 0 'qm config 102'
Assert-PmxTest ($null -eq $ok.Diagnostics) 'a successful result must not carry diagnostics'

# ---- 7. both adapters must expose the same helpers (CI parity) -----------------------
foreach ($p in @('linux', 'windows')) {
    $text = Get-Content -LiteralPath (Join-Path $root "platform/$p/adapters/proxmox-management.ps1") -Raw
    foreach ($fn in @('Protect-PmxDiagnosticText', 'Get-PmxParseDiagnostics', 'ConvertFrom-PmxJsonPayload')) {
        Assert-PmxTest ($text -match "(?m)^function $fn\b") "$p adapter is missing $fn"
    }
}

Write-PmxTestPass 'PF-BUG-002: parse failures are distinguishable, recoverable noise is reported, diagnostics leak nothing'
