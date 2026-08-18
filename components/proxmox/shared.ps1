# ==============================================================================
# PowerFlow — Proxmox Shared Helpers
# ==============================================================================
# Domain   : Proxmox
# File     : components/proxmox/shared.ps1
# Purpose  : Shared formatting, strict argument parsing, and safety helpers
# Functions: Get-PmxObjectProperty, Format-PmxBytes, Format-PmxUptime,
#            Write-PmxField, Test-PmxReady,
#            ConvertTo-PmxDisplayText, ConvertFrom-PmxArguments,
#            ConvertFrom-PmxSize, ConvertFrom-PmxProxmoxSize,
#            Get-PmxOutputMode, Confirm-PmxAmberPlan,
#            Test-PmxCanPick, New-PmxCancelledResult, Write-PmxResolveFailure
# Depends  : Proxmox adapter contract (platform/<os>/adapters/proxmox.ps1)
# ==============================================================================

function Get-PmxObjectProperty {
    param($Object, [Parameter(Mandatory)][string]$Name, $Default = $null)
    if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name) {
        return $Object.$Name
    }
    return $Default
}

function Format-PmxBytes {
    param([long]$Bytes)
    # PowerShell's KB/MB/GB/TB constants are powers of 1024. Label them with IEC
    # units so the display contract says exactly which arithmetic was used.
    if ($Bytes -ge 1TB) { return $(if ($Bytes % 1TB -eq 0) { '{0:N0} TiB' -f ($Bytes / 1TB) } else { '{0:N1} TiB' -f ($Bytes / 1TB) }) }
    if ($Bytes -ge 1GB) { return $(if ($Bytes % 1GB -eq 0) { '{0:N0} GiB' -f ($Bytes / 1GB) } else { '{0:N1} GiB' -f ($Bytes / 1GB) }) }
    if ($Bytes -ge 1MB) { return ('{0:N0} MiB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} KiB' -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

function Format-PmxUptime {
    param([long]$Seconds)
    $span = [TimeSpan]::FromSeconds([math]::Max(0, $Seconds))
    if ($span.Days -gt 0) { return "$($span.Days)d $($span.Hours)h" }
    if ($span.Hours -gt 0) { return "$($span.Hours)h $($span.Minutes)m" }
    return "$($span.Minutes)m"
}

function Write-PmxField {
    param([string]$Label, [string]$Value, [ConsoleColor]$Color = 'White')
    # The trailing space is load-bearing. `{0,-13}` is a MINIMUM width — .NET never
    # truncates — so a label at or over the width emitted no padding and no separator, and
    # 'Capacity test' (13) rendered as "Capacity testblocked — mounted at /" on every
    # `pmx disk` view. An explicit space keeps a longer label readable instead of merged.
    Write-Host ('  {0,-13} ' -f $Label) -NoNewline -ForegroundColor DarkGray
    Write-Host $Value -ForegroundColor $Color
}

function Test-PmxReady {
    if (Test-ProxmoxSupport) { return $true }
    Write-Host '❌ pmx only runs inside a Proxmox VE host.' -ForegroundColor Red
    Write-Host '   Connect first (for example: srv proxmox), then run pmx in that PowerFlow session.' -ForegroundColor DarkGray
    return $false
}

function ConvertTo-PmxDisplayText {
    param($Value)

    if ($null -eq $Value) { return '' }
    $text = "$Value"
    # Remote names and models are untrusted terminal input. Remove CSI/OSC decoration,
    # C0 controls, DEL, and invisible format characters before Write-Host sees them.
    $text = $text -replace "$([char]27)\[[0-?]*[ -/]*[@-~]", ''
    $text = $text -replace "$([char]27)\][^$([char]7)]*$([char]7)", ''
    $text = $text -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F\u00AD\u200B-\u200D\u2060\uFEFF]', ''
    return $text.Trim()
}

function Get-PmxGlobalSwitchMap {
    return @{
        'help'        = 'Help'
        'explain'     = 'Explain'
        'dry-run'     = 'DryRun'
        'show-native' = 'ShowNative'
        'json'        = 'Json'
        'table'       = 'Table'
    }
}

function ConvertFrom-PmxArguments {
    param(
        [object[]]$Arguments = @(),
        [hashtable]$ValueOptions = @{},
        [hashtable]$SwitchOptions = @{},
        [int]$MinPositionals = 0,
        [int]$MaxPositionals = 0
    )

    $options = @{}
    $positionals = @()
    $seen = @{}
    $endOfOptions = $false
    $argv = @($Arguments | ForEach-Object { "$_" })

    for ($index = 0; $index -lt $argv.Count; $index++) {
        $token = $argv[$index]
        if ($token -match '[\x00-\x1F\x7F\u00AD\u200B-\u200D\u2060\uFEFF]') {
            return [pscustomobject]@{ Success = $false; Options = @{}; Positionals = @(); Error = 'arguments may not contain control or invisible format characters' }
        }
        if ($endOfOptions) { $positionals += $token; continue }
        if ($token -ceq '--') { $endOfOptions = $true; continue }

        if ($token.StartsWith('--', [StringComparison]::Ordinal)) {
            $body = $token.Substring(2)
            $equals = $body.IndexOf('=')
            $name = if ($equals -ge 0) { $body.Substring(0, $equals) } else { $body }
            $inline = if ($equals -ge 0) { $body.Substring($equals + 1) } else { $null }

            if (-not $name -or $name -cnotmatch '^[a-z][a-z0-9-]*$') {
                return [pscustomobject]@{ Success = $false; Options = @{}; Positionals = @(); Error = "invalid option '$token'; long options are lowercase and exact" }
            }
            if ($seen.ContainsKey($name)) {
                return [pscustomobject]@{ Success = $false; Options = @{}; Positionals = @(); Error = "option '--$name' was supplied more than once" }
            }

            if ($ValueOptions.ContainsKey($name)) {
                $destination = "$($ValueOptions[$name])"
                if ($options.ContainsKey($destination)) {
                    return [pscustomobject]@{ Success = $false; Options = @{}; Positionals = @(); Error = "option '--$name' duplicates another spelling of the same value" }
                }
                $value = $inline
                if ($null -eq $value) {
                    if ($index + 1 -ge $argv.Count -or $argv[$index + 1].StartsWith('-', [StringComparison]::Ordinal)) {
                        return [pscustomobject]@{ Success = $false; Options = @{}; Positionals = @(); Error = "option '--$name' requires a value" }
                    }
                    $index++
                    $value = $argv[$index]
                }
                if ([string]::IsNullOrWhiteSpace($value)) {
                    return [pscustomobject]@{ Success = $false; Options = @{}; Positionals = @(); Error = "option '--$name' requires a non-empty value" }
                }
                if ($value.StartsWith('-', [StringComparison]::Ordinal)) {
                    return [pscustomobject]@{ Success = $false; Options = @{}; Positionals = @(); Error = "value for '--$name' may not begin with '-'" }
                }
                if ($value -match '[\x00-\x1F\x7F\u00AD\u200B-\u200D\u2060\uFEFF]') {
                    return [pscustomobject]@{ Success = $false; Options = @{}; Positionals = @(); Error = "value for '--$name' contains a control or invisible format character" }
                }
                $options[$destination] = $value
                $seen[$name] = $true
                continue
            }

            if ($SwitchOptions.ContainsKey($name)) {
                $destination = "$($SwitchOptions[$name])"
                if ($options.ContainsKey($destination)) {
                    return [pscustomobject]@{ Success = $false; Options = @{}; Positionals = @(); Error = "option '--$name' duplicates another spelling of the same switch" }
                }
                if ($equals -ge 0) {
                    return [pscustomobject]@{ Success = $false; Options = @{}; Positionals = @(); Error = "switch '--$name' does not take a value" }
                }
                $options[$destination] = $true
                $seen[$name] = $true
                continue
            }

            return [pscustomobject]@{ Success = $false; Options = @{}; Positionals = @(); Error = "unknown option '--$name'" }
        }

        if ($token.StartsWith('-', [StringComparison]::Ordinal) -and $token -cne '-') {
            return [pscustomobject]@{ Success = $false; Options = @{}; Positionals = @(); Error = "unknown option '$token'; use the documented --long-name exactly" }
        }
        $positionals += $token
    }

    if ($positionals.Count -lt $MinPositionals) {
        return [pscustomobject]@{ Success = $false; Options = $options; Positionals = $positionals; Error = "expected at least $MinPositionals positional value(s)" }
    }
    if ($MaxPositionals -ge 0 -and $positionals.Count -gt $MaxPositionals) {
        return [pscustomobject]@{ Success = $false; Options = $options; Positionals = $positionals; Error = "expected at most $MaxPositionals positional value(s)" }
    }
    return [pscustomobject]@{ Success = $true; Options = $options; Positionals = $positionals; Error = '' }
}

function ConvertFrom-PmxSize {
    param(
        # AllowEmptyString so an empty size reaches THIS function's own validation and comes
        # back as a readable "must be a whole number and a unit" error. Without it, a Mandatory
        # [string] refuses '' at binding time and `pmx disk grow 101 ""` threw a raw
        # ParameterBindingException at the user — the flag forms (--size "") were already
        # guarded upstream, but the positional form was not. Fixing it here covers every caller.
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value,
        [ValidateSet('memory', 'disk')][string]$Kind = 'disk'
    )

    $text = $Value.Trim()
    # Accept the unit people actually type. The original pattern demanded MiB/GiB/TiB or
    # MB/GB/TB and was case-SENSITIVE, so `pmx disk grow 101 50G` — the obvious invocation,
    # and the one `qm resize` itself takes — was rejected with a lecture about IEC units.
    # Bare M/G/T and any casing are now accepted; the value is still a positive WHOLE number,
    # because every size here is converted to exact bytes and a decimal would invite rounding
    # into a disk-growth plan.
    if ($text -notmatch '(?i)^([1-9][0-9]*)\s*(M|MB|MIB|G|GB|GIB|T|TB|TIB)$') {
        return [pscustomobject]@{ Success = $false; Bytes = 0L; MiB = 0L; Canonical = ''
            Error = "size '$Value' must be a whole number and a unit — for example 512M, 8G or 2T (MB/MiB, GB/GiB, TB/TiB also work)" }
    }
    $amount = 0L
    if (-not [long]::TryParse($matches[1], [ref]$amount)) {
        return [pscustomobject]@{ Success = $false; Bytes = 0L; MiB = 0L; Canonical = ''; Error = "size '$Value' is too large" }
    }
    $unit = $matches[2].ToLowerInvariant()
    $multiplier = switch ($unit) {
        { $_ -in @('m', 'mib', 'mb') } { 1MB }
        { $_ -in @('g', 'gib', 'gb') } { 1GB }
        { $_ -in @('t', 'tib', 'tb') } { 1TB }
    }
    $product = [decimal]$amount * [decimal]$multiplier
    if ($product -gt [long]::MaxValue) {
        return [pscustomobject]@{ Success = $false; Bytes = 0L; MiB = 0L; Canonical = ''; Error = "size '$Value' is too large" }
    }
    $bytes = [long]$product
    $mib = [long]($bytes / 1MB)
    if ($Kind -eq 'memory' -and ($bytes % 1MB -ne 0 -or $mib -lt 16)) {
        return [pscustomobject]@{ Success = $false; Bytes = 0L; MiB = 0L; Canonical = ''; Error = 'memory must be at least 16 MiB' }
    }
    return [pscustomobject]@{
        Success   = $true
        Bytes     = $bytes
        MiB       = $mib
        Canonical = if ($bytes % 1GB -eq 0) { "$([long]($bytes / 1GB)) GiB" } else { "$mib MiB" }
        Error     = ''
    }
}

function ConvertFrom-PmxProxmoxSize {
    param($Value)

    $text = "$Value".Trim()
    if ($text -notmatch '^([0-9]+(?:\.[0-9]+)?)([KMGT])(?:i?B)?$') {
        return [pscustomobject]@{ Success = $false; Bytes = 0L; Error = "unrecognised Proxmox size '$Value'" }
    }
    $amount = [decimal]0
    if (-not [decimal]::TryParse($matches[1], [Globalization.NumberStyles]::AllowDecimalPoint,
        [Globalization.CultureInfo]::InvariantCulture, [ref]$amount)) {
        return [pscustomobject]@{ Success = $false; Bytes = 0L; Error = "unrecognised Proxmox size '$Value'" }
    }
    $multiplier = switch ($matches[2]) {
        'K' { 1KB }
        'M' { 1MB }
        'G' { 1GB }
        'T' { 1TB }
    }
    $product = [decimal]$amount * [decimal]$multiplier
    if ($product -gt [long]::MaxValue) {
        return [pscustomobject]@{ Success = $false; Bytes = 0L; Error = "Proxmox size '$Value' is too large" }
    }
    if ($product % 1 -ne 0) {
        return [pscustomobject]@{ Success = $false; Bytes = 0L; Error = "Proxmox size '$Value' does not resolve to a whole byte" }
    }
    return [pscustomobject]@{ Success = $true; Bytes = [long]$product; Error = '' }
}

function Get-PmxOutputMode {
    param(
        [hashtable]$Options = @{},
        $Config = (Get-PmxConfig)
    )

    if ($Options.ContainsKey('Json') -and $Options.ContainsKey('Table')) {
        return [pscustomobject]@{ Success = $false; Mode = ''; Error = 'choose either --json or --table, not both' }
    }
    if ($Options.ContainsKey('Json')) { return [pscustomobject]@{ Success = $true; Mode = 'json'; Error = '' } }
    if ($Options.ContainsKey('Table')) { return [pscustomobject]@{ Success = $true; Mode = 'table'; Error = '' } }
    return [pscustomobject]@{ Success = $true; Mode = "$($Config.Output)"; Error = '' }
}

function Write-PmxJson {
    param([Parameter(Mandatory)]$Data)
    Write-Output ($Data | ConvertTo-Json -Depth 16)
}

function Test-PmxVmId {
    param($Value)
    if ("$Value" -cnotmatch '^[1-9][0-9]{2,8}$') { return $false }
    $number = 0
    return ([int]::TryParse("$Value", [ref]$number) -and $number -ge 100 -and $number -le 999999999)
}

function Test-PmxGuestName {
    param($Value)
    return ("$Value" -cmatch '^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$')
}

function Confirm-PmxAmberPlan {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Fields,
        # [AllowEmptyString()] is LOAD-BEARING, and its absence was a live defect.
        #
        # The guarded-mutation path deliberately passes '' when native display is off:
        #   $native = if ($showNative) { "$($preview.NativeCommand)" } else { '' }
        # and the body below already treats the field as optional (`if ($NativeCommand)`).
        # So the parameter contract contradicted the implementation, and PowerShell rejected
        # the intentionally-empty string BEFORE the confirmation could run.
        #
        # This stayed hidden while ShowNative defaulted to $true — the string was never empty.
        # Flipping that default to $false made it fire on EVERY guarded mutation: vm start,
        # shutdown, cpu, memory, clone. The fix belongs here, not in the default: hiding the
        # native command is deliberate PowerFlow behaviour and must stay.
        [AllowEmptyString()][string]$NativeCommand = '',
        [string[]]$Warnings = @(),
        [switch]$DryRun
    )

    Write-Host ''
    Write-Host "⚠️  $Title" -ForegroundColor Yellow
    Write-Host '──────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
    foreach ($key in $Fields.Keys) {
        Write-PmxField (ConvertTo-PmxDisplayText $key) (ConvertTo-PmxDisplayText $Fields[$key])
    }
    if ($NativeCommand) { Write-PmxField 'Native' (ConvertTo-PmxDisplayText $NativeCommand) DarkGray }
    foreach ($warning in @($Warnings)) { Write-Host "  ⚠ $((ConvertTo-PmxDisplayText $warning))" -ForegroundColor Yellow }

    if ($DryRun) {
        Write-Host '  ✅ Dry run complete — no Proxmox state was changed.' -ForegroundColor Green
        return $false
    }
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        Write-Host '  ❌ Refused: this change requires an interactive terminal.' -ForegroundColor Red
        return $false
    }
    $answer = Read-Host 'Proceed? [y/N]'
    return [string]::Equals($answer, 'y', [StringComparison]::OrdinalIgnoreCase)
}

# ==============================================================================
# THE MANAGED-RESPONSE BOUNDARY (PF-INVESTIGATE-001)
# ==============================================================================
# Every PMX read used to print its own generic error, so a failure looked identical whether the
# transport was down, the payload was truncated, the JSON was malformed, or the VM simply did
# not exist. That is why PF-BUG-002 could be reproduced but not diagnosed.
#
# This lives in shared.ps1 because every PMX component loads it first, so ONE reporter serves
# all of them and there is no second copy to drift.
#
# The adapter already owns the rest of the boundary: execution, stdout/stderr separation,
# exit-code capture, privacy scrubbing (Protect-PmxDiagnosticText), JSON validation
# (ConvertFrom-PmxJsonPayload) and the debug record (Get-PmxParseDiagnostics). What was missing
# was a single place to REPORT it, and wrappers that stop dropping the evidence on the way up.
# ==============================================================================
<#
.SYNOPSIS
    Report a failed managed query, with scrubbed evidence when --explain is set.
.DESCRIPTION
    Ordinary output stays one line, because that is the right amount of noise for a user who
    just wants to know it did not work. `--explain` adds the evidence the adapter collected:
    command class, transport, exit code, byte counts, and a preview of what actually arrived.
    That preview is what separates "stdout had a banner in front of the JSON" from "the
    payload is genuinely broken" — eight failure classes previously collapsed into one
    sentence, which is why PF-BUG-002 could be reproduced but not diagnosed.

    Every previewed byte has been through Protect-PmxDiagnosticText in the adapter, so an
    address, a user@host or a token cannot reach the terminal. That matters here more than
    usual: PowerFlow's contract is that ordinary output names a saved alias, never an endpoint.
#>
# ── PF-UX-002: escaping a picker is a decision, not a failure ────────────────
#
# Every resolver here returns the same envelope, and callers all rendered a falsy
# .Success the same way:
#
#     ❌ cancelled
#
# in red. Pressing Escape is the user saying "not this one" — marking it as an error
# teaches them to distrust the red marker, which is the one piece of output that has to
# stay trustworthy. Five outcomes, and they are NOT all the same:
#
#     Esc pressed        →  neutral. Nothing to fix.
#     no VMs exist       →  a state worth reporting
#     fzf unavailable    →  an instruction: name one, or install fzf
#     transport failed   →  an error
#     invalid selector   →  an error
#
# The middle three are actionable and the last two are faults; only the first is neither.
# Fixed here rather than at each call site because there are nine of those, and a
# convention enforced in nine places is a convention that will drift in one of them.

<#
.SYNOPSIS
    May this session open an interactive picker at all?
.DESCRIPTION
    One predicate rather than the same two conditions spelled slightly differently in each
    resolver. Both halves matter and for different reasons: with output redirected the
    picker would draw into a pipe and block forever, and without fzf there is nothing to
    draw with.

    A refusal here is NOT a cancellation. Nobody was asked, so nobody declined — and
    reporting it as one would tell a script author their pipeline was cancelled by a user
    who is not there.
#>
function Test-PmxCanPick {
    if ([Console]::IsOutputRedirected) { return $false }
    return [bool](Get-Command fzf -ErrorAction SilentlyContinue)
}

<#
.SYNOPSIS
    The envelope a resolver returns when the user escaped the picker.
#>
function New-PmxCancelledResult {
    param([string]$Kind = 'Vm')
    $result = [pscustomobject]@{ Success = $false; Cancelled = $true; Error = '' }
    # Callers read .Vm or .Disk by name; the field has to exist and be empty rather than
    # be absent, so `$resolved.Vm` is $null instead of throwing under StrictMode.
    Add-Member -InputObject $result -NotePropertyName $Kind -NotePropertyValue $null
    return $result
}

<#
.SYNOPSIS
    Render a failed resolve — quietly if it was a cancellation, red if it was not.
#>
function Write-PmxResolveFailure {
    param([Parameter(Mandatory)][AllowNull()]$Resolved)

    if ($null -eq $Resolved) { Write-Host '❌ nothing was resolved' -ForegroundColor Red; return }
    if ($Resolved.Cancelled) {
        # Dim and unadorned. The user already knows what they did; this only confirms the
        # command ended on purpose rather than silently dying.
        Write-Host '↩ Cancelled.' -ForegroundColor DarkGray
        return
    }
    Write-Host "❌ $($Resolved.Error)" -ForegroundColor Red
}

function Write-PmxQueryFailure {
    param(
        [AllowEmptyString()][string]$Message,
        $Diagnostics,
        # Optional: not every call site has parsed options in scope, and a reporter that only
        # works where they happen to exist is the reason each command grew its own.
        $Options = $null
    )

    Write-Host "❌ $Message" -ForegroundColor Red

    if (-not $Diagnostics) {
        # Only advertise --explain when there is actually something more to show.
        return
    }
    if (-not ($Options -and $Options.Explain)) {
        Write-Host '   Run again with --explain for the transport and parser evidence.' -ForegroundColor DarkGray
        return
    }

    Write-Host ''
    Write-Host '   EVIDENCE' -ForegroundColor DarkGray
    foreach ($field in @('CommandClass', 'Transport', 'Parser', 'ExitCode',
                         'StdOutBytes', 'StdErrBytes', 'StdOutLines', 'LooksLikeJson', 'Note')) {
        if ($null -eq $Diagnostics.$field) { continue }
        Write-Host ("     {0,-14} {1}" -f $field, $Diagnostics.$field) -ForegroundColor DarkGray
    }
    if ($Diagnostics.StdOutPreview) {
        Write-Host '     stdout       ' -NoNewline -ForegroundColor DarkGray
        Write-Host $Diagnostics.StdOutPreview -ForegroundColor DarkGray
    }
    if ($Diagnostics.StdErrPreview) {
        Write-Host '     stderr       ' -NoNewline -ForegroundColor DarkGray
        Write-Host $Diagnostics.StdErrPreview -ForegroundColor DarkGray
    }
    Write-Host ''
}
