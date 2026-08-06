# ==============================================================================
# PowerFlow — Proxmox Shared Helpers
# ==============================================================================
# Domain   : Proxmox
# File     : components/proxmox/shared.ps1
# Purpose  : Shared formatting, strict argument parsing, and safety helpers
# Functions: Format-PmxBytes, Format-PmxUptime, Write-PmxField, Test-PmxReady,
#            ConvertTo-PmxDisplayText, ConvertFrom-PmxArguments,
#            ConvertFrom-PmxSize, ConvertFrom-PmxProxmoxSize,
#            Get-PmxOutputMode, Confirm-PmxAmberPlan
# Depends  : Proxmox adapter contract (platform/<os>/adapters/proxmox.ps1)
# ==============================================================================

function Format-PmxBytes {
    param([long]$Bytes)
    if ($Bytes -ge 1TB) { return ('{0:N1} TB' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:N1} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N0} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
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
                    if ($index + 1 -ge $argv.Count -or $argv[$index + 1].StartsWith('--', [StringComparison]::Ordinal)) {
                        return [pscustomobject]@{ Success = $false; Options = @{}; Positionals = @(); Error = "option '--$name' requires a value" }
                    }
                    $index++
                    $value = $argv[$index]
                }
                if ([string]::IsNullOrWhiteSpace($value)) {
                    return [pscustomobject]@{ Success = $false; Options = @{}; Positionals = @(); Error = "option '--$name' requires a non-empty value" }
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
        [Parameter(Mandatory)][string]$Value,
        [ValidateSet('memory', 'disk')][string]$Kind = 'disk'
    )

    $text = $Value.Trim()
    if ($text -notmatch '^([1-9][0-9]*)(MiB|GiB|TiB|MB|GB|TB)$') {
        return [pscustomobject]@{ Success = $false; Bytes = 0L; MiB = 0L; Canonical = ''; Error = "size '$Value' must be a positive whole number with MiB, GiB, or TiB" }
    }
    $amount = 0L
    if (-not [long]::TryParse($matches[1], [ref]$amount)) {
        return [pscustomobject]@{ Success = $false; Bytes = 0L; MiB = 0L; Canonical = ''; Error = "size '$Value' is too large" }
    }
    $unit = $matches[2].ToLowerInvariant()
    $multiplier = switch ($unit) {
        { $_ -in @('mib', 'mb') } { 1MB }
        { $_ -in @('gib', 'gb') } { 1GB }
        { $_ -in @('tib', 'tb') } { 1TB }
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
    $amount = 0.0
    if (-not [double]::TryParse($matches[1], [Globalization.NumberStyles]::AllowDecimalPoint,
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
        [Parameter(Mandatory)][string]$NativeCommand,
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
