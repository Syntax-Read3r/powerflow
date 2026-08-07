# ==============================================================================
# PowerFlow — Proxmox Management Configuration
# ==============================================================================
# Domain   : Proxmox
# File     : components/proxmox/config.ps1
# Purpose  : Persist non-secret PMX policy and resolve local or saved-SSH targets
# Functions: Get-PmxConfigDefaults, Get-PmxConfig, Save-PmxConfig,
#            Set-PmxConfigSetting, Reset-PmxConfigSetting,
#            Test-PmxConfigValues, Resolve-PmxManagementConnection,
#            Resolve-PmxManagementNode, Get-PmxManagementSession,
#            Show-PmxConfigView, Invoke-PmxConfigCommand, Write-PmxAuditRecord
# Depends  : Get-PowerFlowConfigPath, Get-PowerFlowDataPath (locations adapter),
#            Get-PFServers (components/network/servers.ps1), Proxmox management adapter
# ==============================================================================

function Get-PmxConfigDefaults {
    return [ordered]@{
        Host           = 'proxmox'
        Node           = 'auto'
        Transport      = 'auto'
        Output         = 'table'
        # OFF by default. The whole point of --show-native is that a user ASKS for the
        # translated `qm`/`pvesh` command; defaulting it to $true meant native vocabulary —
        # including `qm ... --digest <sha1>` — reached people who never asked for it, which is
        # the exact inversion of the rule the flag exists to enforce. Turn it on per-invocation
        # with --show-native, or permanently with `pmx config set show-native true`.
        ShowNative     = $false
        Explain        = $true
        VmidPolicy     = 'auto'
        CloneMode      = 'full'
        Confirmation   = 'risk-based'
        AuditLog       = $true
        TimeoutSeconds = 60
    }
}

function Get-PmxConfigSettingMap {
    return [ordered]@{
        'host'            = 'Host'
        'node'            = 'Node'
        'transport'       = 'Transport'
        'output'          = 'Output'
        'show-native'     = 'ShowNative'
        'explain'         = 'Explain'
        'vmid-policy'     = 'VmidPolicy'
        'clone-mode'      = 'CloneMode'
        'confirmation'    = 'Confirmation'
        'audit-log'       = 'AuditLog'
        'timeout-seconds' = 'TimeoutSeconds'
    }
}

function Get-PmxConfigFile {
    return (Join-Path (Get-PowerFlowConfigPath) 'pmx.json')
}

function Get-PmxAuditFile {
    return (Join-Path (Get-PowerFlowDataPath) 'pmx-audit.jsonl')
}

function ConvertTo-PmxBooleanSetting {
    param([Parameter(Mandatory)]$Value)

    if ($Value -is [bool]) {
        return [pscustomobject]@{ Success = $true; Value = [bool]$Value; Error = '' }
    }

    switch ("$Value".Trim().ToLowerInvariant()) {
        { $_ -in @('true', 'on', 'yes', '1') } {
            return [pscustomobject]@{ Success = $true; Value = $true; Error = '' }
        }
        { $_ -in @('false', 'off', 'no', '0') } {
            return [pscustomobject]@{ Success = $true; Value = $false; Error = '' }
        }
        default {
            return [pscustomobject]@{ Success = $false; Value = $null; Error = "expected true or false, got '$Value'" }
        }
    }
}

function ConvertTo-PmxConfigValue {
    param(
        [Parameter(Mandatory)][string]$Property,
        [Parameter(Mandatory)]$Value
    )

    $text = "$Value".Trim()
    switch ($Property) {
        'Host' {
            if ($text -notmatch '^[a-z0-9][a-z0-9_-]{0,63}$') {
                return [pscustomobject]@{ Success = $false; Value = $null; Error = 'host must be a saved srv alias using lowercase letters, digits, dashes, or underscores' }
            }
            return [pscustomobject]@{ Success = $true; Value = $text; Error = '' }
        }
        'Node' {
            if ($text -ne 'auto' -and $text -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]{0,63}$') {
                return [pscustomobject]@{ Success = $false; Value = $null; Error = 'node must be auto or a Proxmox node name' }
            }
            return [pscustomobject]@{ Success = $true; Value = $text; Error = '' }
        }
        'Transport' {
            if ($text -notin @('auto', 'local', 'ssh')) {
                return [pscustomobject]@{ Success = $false; Value = $null; Error = 'transport must be auto, local, or ssh' }
            }
            return [pscustomobject]@{ Success = $true; Value = $text; Error = '' }
        }
        'Output' {
            if ($text -notin @('table', 'json')) {
                return [pscustomobject]@{ Success = $false; Value = $null; Error = 'output must be table or json' }
            }
            return [pscustomobject]@{ Success = $true; Value = $text; Error = '' }
        }
        { $_ -in @('ShowNative', 'Explain', 'AuditLog') } {
            return (ConvertTo-PmxBooleanSetting -Value $Value)
        }
        'VmidPolicy' {
            if ($text -ne 'auto') {
                return [pscustomobject]@{ Success = $false; Value = $null; Error = 'vmid-policy currently supports only auto' }
            }
            return [pscustomobject]@{ Success = $true; Value = $text; Error = '' }
        }
        'CloneMode' {
            if ($text -ne 'full') {
                return [pscustomobject]@{ Success = $false; Value = $null; Error = 'clone-mode currently supports only full' }
            }
            return [pscustomobject]@{ Success = $true; Value = $text; Error = '' }
        }
        'Confirmation' {
            if ($text -ne 'risk-based') {
                return [pscustomobject]@{ Success = $false; Value = $null; Error = 'confirmation currently supports only risk-based' }
            }
            return [pscustomobject]@{ Success = $true; Value = $text; Error = '' }
        }
        'TimeoutSeconds' {
            $seconds = 0
            if (-not [int]::TryParse($text, [ref]$seconds) -or $seconds -lt 5 -or $seconds -gt 600) {
                return [pscustomobject]@{ Success = $false; Value = $null; Error = 'timeout-seconds must be an integer from 5 to 600' }
            }
            return [pscustomobject]@{ Success = $true; Value = $seconds; Error = '' }
        }
        default {
            return [pscustomobject]@{ Success = $false; Value = $null; Error = "unknown configuration property '$Property'" }
        }
    }
}

function Get-PmxConfig {
    $defaults = Get-PmxConfigDefaults
    $values = [ordered]@{}
    foreach ($key in $defaults.Keys) { $values[$key] = $defaults[$key] }

    $loadError = ''
    $path = Get-PmxConfigFile
    if (Test-Path -LiteralPath $path) {
        try {
            $saved = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            foreach ($key in $defaults.Keys) {
                if ($saved.PSObject.Properties.Name -contains $key) {
                    $converted = ConvertTo-PmxConfigValue -Property $key -Value $saved.$key
                    if (-not $converted.Success) {
                        throw "invalid $key value: $($converted.Error)"
                    }
                    $values[$key] = $converted.Value
                }
            }
        }
        catch {
            $loadError = "could not read PMX configuration: $($_.Exception.Message)"
        }
    }

    $config = [pscustomobject]$values
    $config | Add-Member -NotePropertyName LoadError -NotePropertyValue $loadError
    return $config
}

function Save-PmxConfig {
    param([Parameter(Mandatory)]$Config)

    $validation = Test-PmxConfigValues -Config $Config
    if (-not $validation.Success) {
        return [pscustomobject]@{ Success = $false; Error = $validation.Error; Path = Get-PmxConfigFile }
    }

    $path = Get-PmxConfigFile
    $parent = Split-Path -Parent $path
    try {
        if (-not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
        }
        $out = [ordered]@{}
        foreach ($key in (Get-PmxConfigDefaults).Keys) { $out[$key] = $Config.$key }
        $json = ([pscustomobject]$out | ConvertTo-Json -Depth 4) + [Environment]::NewLine
        [IO.File]::WriteAllText($path, $json, [Text.UTF8Encoding]::new($false))
        return [pscustomobject]@{ Success = $true; Error = ''; Path = $path }
    }
    catch {
        return [pscustomobject]@{ Success = $false; Error = $_.Exception.Message; Path = $path }
    }
}

function Test-PmxConfigValues {
    param([Parameter(Mandatory)]$Config)

    if ($Config.LoadError) {
        return [pscustomobject]@{ Success = $false; Error = "$($Config.LoadError)" }
    }
    foreach ($key in (Get-PmxConfigDefaults).Keys) {
        if ($Config.PSObject.Properties.Name -notcontains $key) {
            return [pscustomobject]@{ Success = $false; Error = "configuration is missing $key" }
        }
        $converted = ConvertTo-PmxConfigValue -Property $key -Value $Config.$key
        if (-not $converted.Success) {
            return [pscustomobject]@{ Success = $false; Error = "${key}: $($converted.Error)" }
        }
    }
    return [pscustomobject]@{ Success = $true; Error = '' }
}

function Set-PmxConfigSetting {
    param(
        [Parameter(Mandatory)][string]$Setting,
        [Parameter(Mandatory)]$Value
    )

    $map = Get-PmxConfigSettingMap
    $name = $Setting.Trim().ToLowerInvariant()
    if (-not $map.Contains($name)) {
        return [pscustomobject]@{ Success = $false; Error = "unknown setting '$Setting'"; Config = Get-PmxConfig }
    }
    $property = $map[$name]
    $converted = ConvertTo-PmxConfigValue -Property $property -Value $Value
    if (-not $converted.Success) {
        return [pscustomobject]@{ Success = $false; Error = $converted.Error; Config = Get-PmxConfig }
    }

    $config = Get-PmxConfig
    if ($config.LoadError) {
        return [pscustomobject]@{ Success = $false; Error = $config.LoadError; Config = $config }
    }
    $config.$property = $converted.Value
    $saved = Save-PmxConfig -Config $config
    return [pscustomobject]@{ Success = $saved.Success; Error = $saved.Error; Config = $config; Path = $saved.Path }
}

function Reset-PmxConfigSetting {
    param([Parameter(Mandatory)][string]$Setting)

    $defaults = Get-PmxConfigDefaults
    if ($Setting.Trim().ToLowerInvariant() -eq 'all') {
        $config = [pscustomobject]$defaults
        $config | Add-Member -NotePropertyName LoadError -NotePropertyValue ''
        $saved = Save-PmxConfig -Config $config
        return [pscustomobject]@{ Success = $saved.Success; Error = $saved.Error; Config = $config; Path = $saved.Path }
    }

    $map = Get-PmxConfigSettingMap
    $name = $Setting.Trim().ToLowerInvariant()
    if (-not $map.Contains($name)) {
        return [pscustomobject]@{ Success = $false; Error = "unknown setting '$Setting'"; Config = Get-PmxConfig }
    }
    $property = $map[$name]
    $config = Get-PmxConfig
    if ($config.LoadError) {
        return [pscustomobject]@{ Success = $false; Error = $config.LoadError; Config = $config }
    }
    $config.$property = $defaults[$property]
    $saved = Save-PmxConfig -Config $config
    return [pscustomobject]@{ Success = $saved.Success; Error = $saved.Error; Config = $config; Path = $saved.Path }
}

function Resolve-PmxManagementConnection {
    param($Config = (Get-PmxConfig))

    $valid = Test-PmxConfigValues -Config $Config
    if (-not $valid.Success) {
        return [pscustomobject]@{ Success = $false; Connection = $null; Config = $Config; Error = $valid.Error }
    }

    $transport = "$($Config.Transport)"
    if ($transport -eq 'auto') {
        $transport = if (Test-ProxmoxSupport) { 'local' } else { 'ssh' }
    }

    if ($transport -eq 'local') {
        if (-not (Test-ProxmoxSupport)) {
            return [pscustomobject]@{ Success = $false; Connection = $null; Config = $Config; Error = 'local transport requires a Proxmox VE host; use transport ssh elsewhere' }
        }
        $connection = [pscustomobject]@{
            Transport      = 'local'
            Label          = 'local Proxmox node'
            Target         = ''
            Port           = 0
            TimeoutSeconds = [int]$Config.TimeoutSeconds
            Node           = "$($Config.Node)"
        }
        return [pscustomobject]@{ Success = $true; Connection = $connection; Config = $Config; Error = '' }
    }

    if (-not (Get-Command Get-PFServers -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ Success = $false; Connection = $null; Config = $Config; Error = 'the srv component is unavailable' }
    }
    $servers = Get-PFServers
    if (-not $servers.ContainsKey("$($Config.Host)")) {
        return [pscustomobject]@{ Success = $false; Connection = $null; Config = $Config; Error = "saved server '$($Config.Host)' was not found; add it with: srv add $($Config.Host) <user@host>" }
    }

    $server = $servers["$($Config.Host)"]
    $user = "$($server.user)"
    $serverHost = "$($server.host)"
    $port = 0
    if ($user -notmatch '^[A-Za-z_][A-Za-z0-9._-]{0,63}$' -or
        $serverHost -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$' -or
        -not [int]::TryParse("$($server.port)", [ref]$port) -or $port -lt 1 -or $port -gt 65535) {
        return [pscustomobject]@{ Success = $false; Connection = $null; Config = $Config; Error = "saved server '$($Config.Host)' has an invalid SSH target" }
    }

    $connection = [pscustomobject]@{
        Transport      = 'ssh'
        Label          = "$($Config.Host)"
        Target         = "$user@$serverHost"
        Port           = $port
        TimeoutSeconds = [int]$Config.TimeoutSeconds
        Node           = "$($Config.Node)"
    }
    return [pscustomobject]@{ Success = $true; Connection = $connection; Config = $Config; Error = '' }
}

function Resolve-PmxManagementNode {
    param(
        [Parameter(Mandatory)]$Connection,
        [Parameter(Mandatory)]$Config
    )

    $result = Invoke-ProxmoxManagementQuery -Operation 'node-list' -Connection $Connection
    if (-not $result.Success) {
        return [pscustomobject]@{ Success = $false; Node = ''; Nodes = @(); Error = $result.Error; Result = $result }
    }
    $nodes = @($result.Data)
    if (-not $nodes.Count) {
        return [pscustomobject]@{ Success = $false; Node = ''; Nodes = @(); Error = 'Proxmox returned no nodes'; Result = $result }
    }

    if ("$($Config.Node)" -ne 'auto') {
        $selected = @($nodes | Where-Object { "$($_.node)" -eq "$($Config.Node)" })
        if ($selected.Count -ne 1) {
            return [pscustomobject]@{ Success = $false; Node = ''; Nodes = $nodes; Error = "configured node '$($Config.Node)' was not found uniquely"; Result = $result }
        }
        return [pscustomobject]@{ Success = $true; Node = "$($selected[0].node)"; Nodes = $nodes; Error = ''; Result = $result }
    }

    $online = @($nodes | Where-Object { "$($_.status)" -eq 'online' })
    if ($online.Count -eq 1) {
        return [pscustomobject]@{ Success = $true; Node = "$($online[0].node)"; Nodes = $nodes; Error = ''; Result = $result }
    }
    if ($nodes.Count -eq 1) {
        return [pscustomobject]@{ Success = $true; Node = "$($nodes[0].node)"; Nodes = $nodes; Error = ''; Result = $result }
    }
    return [pscustomobject]@{ Success = $false; Node = ''; Nodes = $nodes; Error = 'more than one Proxmox node is available; set one with: pmx config set node <name>'; Result = $result }
}

function Get-PmxManagementSession {
    $resolved = Resolve-PmxManagementConnection
    if (-not $resolved.Success) {
        return [pscustomobject]@{ Success = $false; Connection = $null; Config = $resolved.Config; Node = ''; Probe = $null; Error = $resolved.Error }
    }

    $probe = Test-ProxmoxManagementTransport -Connection $resolved.Connection
    $probeSuccess = if ($probe -is [bool]) { [bool]$probe } else { [bool]$probe.Success }
    if (-not $probeSuccess) {
        $why = if ($probe -is [bool]) { 'Proxmox management transport is unavailable' } elseif ($probe.Error) { "$($probe.Error)" } else { 'Proxmox management transport is unavailable' }
        $kind = if ($probe -isnot [bool] -and $probe.FailureKind) { "$($probe.FailureKind)" } else { 'connection-failed' }
        $safe = ConvertTo-PmxSessionFailure -Connection $resolved.Connection -ErrorMessage $why -FailureKind $kind
        return [pscustomobject]@{ Success = $false; Connection = $resolved.Connection; Config = $resolved.Config; Node = ''; Probe = $probe; Error = $safe.Message; FailureKind = $safe.FailureKind }
    }

    $nodeResult = Resolve-PmxManagementNode -Connection $resolved.Connection -Config $resolved.Config
    if (-not $nodeResult.Success) {
        $kind = if ($nodeResult.Result -and $nodeResult.Result.FailureKind) { "$($nodeResult.Result.FailureKind)" } else { '' }
        $safe = ConvertTo-PmxSessionFailure -Connection $resolved.Connection -ErrorMessage $nodeResult.Error -FailureKind $kind
        return [pscustomobject]@{ Success = $false; Connection = $resolved.Connection; Config = $resolved.Config; Node = ''; Probe = $probe; Error = $safe.Message; FailureKind = $safe.FailureKind }
    }
    $resolved.Connection.Node = $nodeResult.Node
    return [pscustomobject]@{
        Success    = $true
        Connection = $resolved.Connection
        Config     = $resolved.Config
        Node       = $nodeResult.Node
        Nodes      = $nodeResult.Nodes
        Probe      = $probe
        Error      = ''
        FailureKind = ''
    }
}

function Show-PmxConfigView {
    param([object[]]$Arguments = @())

    $parsed = ConvertFrom-PmxArguments -Arguments $Arguments -SwitchOptions (Get-PmxGlobalSwitchMap) -MaxPositionals 0
    if (-not $parsed.Success) { Write-Host "❌ $($parsed.Error)" -ForegroundColor Red; return }
    if ($parsed.Options.Help) { Show-PmxTopicHelp 'config show'; return }
    $config = Get-PmxConfig
    if ($config.LoadError) { Write-Host "❌ $($config.LoadError)" -ForegroundColor Red; return }
    $mode = Get-PmxOutputMode -Options $parsed.Options -Config $config
    if (-not $mode.Success) { Write-Host "❌ $($mode.Error)" -ForegroundColor Red; return }

    $out = [ordered]@{}
    foreach ($entry in (Get-PmxConfigSettingMap).GetEnumerator()) {
        $out[$entry.Key] = $config.($entry.Value)
    }
    if ($mode.Mode -eq 'json') { Write-PmxJson ([pscustomobject]$out); return }

    Write-Host ''
    Write-Host '⚙️  PMX CONFIGURATION' -ForegroundColor Cyan
    Write-Host '──────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
    foreach ($key in $out.Keys) { Write-PmxField $key "$($out[$key])" }
    Write-Host ''
    Write-Host "  Stored at: $(Get-PmxConfigFile)" -ForegroundColor DarkGray
    Write-Host '  The host value is an srv alias; PMX never stores SSH credentials.' -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-PmxConfigCommand {
    param([object[]]$Arguments = @())

    $argv = @($Arguments | ForEach-Object { "$_" })
    $action = if ($argv.Count) { $argv[0].ToLowerInvariant() } else { 'show' }
    $rest = if ($argv.Count -gt 1) { @($argv[1..($argv.Count - 1)]) } else { @() }

    switch ($action) {
        'show' { Show-PmxConfigView -Arguments $rest }
        'set' {
            $parsed = ConvertFrom-PmxArguments -Arguments $rest -SwitchOptions @{ 'help' = 'Help' } -MinPositionals 2 -MaxPositionals 2
            if (-not $parsed.Success) { Write-Host "❌ $($parsed.Error). Use: pmx config set <setting> <value>" -ForegroundColor Red; return }
            if ($parsed.Options.Help) { Show-PmxTopicHelp 'config set'; return }
            $result = Set-PmxConfigSetting -Setting $parsed.Positionals[0] -Value $parsed.Positionals[1]
            if (-not $result.Success) { Write-Host "❌ $($result.Error)" -ForegroundColor Red; return }
            Write-Host "✅ PMX setting '$($parsed.Positionals[0])' updated." -ForegroundColor Green
        }
        'reset' {
            $parsed = ConvertFrom-PmxArguments -Arguments $rest -SwitchOptions @{ 'help' = 'Help' } -MinPositionals 1 -MaxPositionals 1
            if (-not $parsed.Success) { Write-Host "❌ $($parsed.Error). Use: pmx config reset <setting|all>" -ForegroundColor Red; return }
            if ($parsed.Options.Help) { Show-PmxTopicHelp 'config reset'; return }
            $result = Reset-PmxConfigSetting -Setting $parsed.Positionals[0]
            if (-not $result.Success) { Write-Host "❌ $($result.Error)" -ForegroundColor Red; return }
            Write-Host "✅ PMX setting '$($parsed.Positionals[0])' reset." -ForegroundColor Green
        }
        'validate' {
            $parsed = ConvertFrom-PmxArguments -Arguments $rest -SwitchOptions @{ 'help' = 'Help' } -MaxPositionals 0
            if (-not $parsed.Success) { Write-Host "❌ $($parsed.Error)" -ForegroundColor Red; return }
            if ($parsed.Options.Help) { Show-PmxTopicHelp 'config validate'; return }
            $session = Get-PmxManagementSession
            if (-not $session.Success) { Write-PmxDisconnectedState -Session $session; return }
            Write-Host "✅ PMX configuration is valid; $($session.Connection.Transport) transport reached node $($session.Node)." -ForegroundColor Green
        }
        'discover' { Show-PmxDiscovery -Arguments $rest }
        default { Write-Host "❌ Unknown config action '$action'. Run: pmx help config" -ForegroundColor Red }
    }
}

function Write-PmxAuditRecord {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$Outcome,
        [string]$Message = '',
        [string]$VmId = '',
        [switch]$DryRun,
        $Config = (Get-PmxConfig)
    )

    if (-not $Config.AuditLog) { return }
    $path = Get-PmxAuditFile
    $parent = Split-Path -Parent $path
    try {
        if (-not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
        }
        $record = [ordered]@{
            timestamp = (Get-Date).ToUniversalTime().ToString('o')
            operation = $Operation
            target    = $Target
            vmid      = $VmId
            dryRun    = [bool]$DryRun
            outcome   = $Outcome
            message   = ($Message -replace '[\x00-\x1f\x7f]', ' ').Trim()
        }
        $line = ([pscustomobject]$record | ConvertTo-Json -Compress -Depth 4) + [Environment]::NewLine
        [IO.File]::AppendAllText($path, $line, [Text.UTF8Encoding]::new($false))
    }
    catch {
        Write-Warning "pmx: could not write the audit log: $($_.Exception.Message)"
    }
}
