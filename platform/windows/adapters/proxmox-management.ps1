# ==============================================================================
# PowerFlow — Proxmox Management Adapter (Windows)
# ==============================================================================
# Domain   : Platform / Windows
# File     : platform/windows/adapters/proxmox-management.ps1
# Purpose  : Allow-listed SSH Proxmox VM-management operations
# Functions: Test-ProxmoxManagementTransport, Invoke-ProxmoxManagementQuery,
#            Invoke-ProxmoxManagementChange
# Depends  : none
# ==============================================================================

function New-PmxManagementResult {
    param(
        [bool]$Success,
        $Data,
        [string]$ErrorMessage,
        $ExitCode,
        [string]$NativeCommand,
        [string]$FailureKind = ''
    )

    return [pscustomobject]@{
        Success       = $Success
        Data          = $Data
        Error         = $ErrorMessage
        ExitCode      = $ExitCode
        NativeCommand = $NativeCommand
        FailureKind   = $FailureKind
    }
}

function Get-PmxManagementConnectionValue {
    param($Connection, [Parameter(Mandatory)][string]$Name)

    if ($null -eq $Connection) { return $null }
    if ($Connection -is [System.Collections.IDictionary]) {
        if ($Connection.Contains($Name)) { return $Connection[$Name] }
        return $null
    }
    $property = $Connection.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function ConvertTo-PmxManagementBoundedInt {
    param($Value, [int]$Minimum, [int]$Maximum)

    $text = "$Value"
    if ($text -notmatch '^[0-9]+$') { return $null }
    $number = 0
    if (-not [int]::TryParse($text, [ref]$number)) { return $null }
    if ($number -lt $Minimum -or $number -gt $Maximum) { return $null }
    return $number
}

function Test-PmxManagementSshTarget {
    param([string]$Target)

    if (-not $Target -or $Target.Length -gt 286) { return $false }
    $user = '(?:[A-Za-z_][A-Za-z0-9._-]{0,31}@)?'
    $dnsOrAlias = '[A-Za-z0-9](?:[A-Za-z0-9._-]{0,251}[A-Za-z0-9])?'
    $bracketedIpv6 = '\[[0-9A-Fa-f:]{2,45}\]'
    return [bool]($Target -match "^$user(?:$dnsOrAlias|$bracketedIpv6)$")
}

function Resolve-PmxManagementAdapterConnection {
    param($Connection)

    if ($null -eq $Connection) {
        return [pscustomobject]@{ Success = $false; Data = $null; Error = 'A Proxmox connection is required.' }
    }

    $transport = "$(Get-PmxManagementConnectionValue $Connection 'Transport')"
    if ([string]::IsNullOrWhiteSpace($transport)) {
        return [pscustomobject]@{ Success = $false; Data = $null; Error = 'Connection.Transport must be local or ssh.' }
    }
    $transport = $transport.ToLowerInvariant()

    $timeoutValue = Get-PmxManagementConnectionValue $Connection 'TimeoutSeconds'
    if ($null -eq $timeoutValue -or "$timeoutValue" -eq '') { $timeoutValue = 60 }
    $timeout = ConvertTo-PmxManagementBoundedInt $timeoutValue 1 600
    if ($null -eq $timeout) {
        return [pscustomobject]@{ Success = $false; Data = $null; Error = 'Connection.TimeoutSeconds must be from 1 through 600.' }
    }

    if ([string]::Equals($transport, 'local', [StringComparison]::Ordinal)) {
        return [pscustomobject]@{ Success = $false; Data = $null; Error = 'Local Proxmox management is unavailable on Windows; use SSH transport.' }
    }
    if (-not [string]::Equals($transport, 'ssh', [StringComparison]::Ordinal)) {
        return [pscustomobject]@{ Success = $false; Data = $null; Error = 'Connection.Transport must be local or ssh.' }
    }

    $target = "$(Get-PmxManagementConnectionValue $Connection 'Target')"
    if (-not (Test-PmxManagementSshTarget $target)) {
        return [pscustomobject]@{ Success = $false; Data = $null; Error = 'Connection.Target is not a safe SSH alias or user@host target.' }
    }
    $portValue = Get-PmxManagementConnectionValue $Connection 'Port'
    if ($null -eq $portValue -or "$portValue" -eq '') { $portValue = 22 }
    $port = ConvertTo-PmxManagementBoundedInt $portValue 1 65535
    if ($null -eq $port) {
        return [pscustomobject]@{ Success = $false; Data = $null; Error = 'Connection.Port must be from 1 through 65535.' }
    }
    $ssh = Get-Command 'ssh' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $ssh) {
        return [pscustomobject]@{ Success = $false; Data = $null; Error = 'SSH transport requires the ssh application.' }
    }

    return [pscustomobject]@{
        Success = $true
        Error   = ''
        Data    = [pscustomobject]@{
            Transport      = 'ssh'
            Label          = "$(Get-PmxManagementConnectionValue $Connection 'Label')"
            Target         = $target
            Port           = $port
            TimeoutSeconds = $timeout
            SshPath        = $ssh.Source
            PveshPath      = ''
            QmPath         = ''
        }
    }
}

function Get-PmxManagementUnexpectedParameter {
    param([hashtable]$Parameters, [string[]]$Allowed)

    foreach ($key in @($Parameters.Keys)) {
        if ("$key" -notin $Allowed) { return "$key" }
    }
    return ''
}

function Get-PmxManagementRequiredParameter {
    param([hashtable]$Parameters, [Parameter(Mandatory)][string]$Name)

    if (-not $Parameters.ContainsKey($Name) -or $null -eq $Parameters[$Name] -or "$($Parameters[$Name])" -eq '') {
        return [pscustomobject]@{ Success = $false; Value = $null; Error = "Parameter '$Name' is required." }
    }
    return [pscustomobject]@{ Success = $true; Value = $Parameters[$Name]; Error = '' }
}

function ConvertTo-PmxManagementVmid {
    param($Value)

    $text = "$Value"
    if ($text -notmatch '^[1-9][0-9]{2,8}$') { return $null }
    $vmid = 0
    if (-not [int]::TryParse($text, [ref]$vmid) -or $vmid -gt 999999999) { return $null }
    return "$vmid"
}

function Get-PmxManagementNode {
    param([hashtable]$Parameters)

    $node = if ($Parameters.ContainsKey('Node')) { "$($Parameters['Node'])" } else { 'localhost' }
    if ($node -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9._-]{0,61}[A-Za-z0-9])?$') {
        return [pscustomobject]@{ Success = $false; Value = ''; Error = "Parameter 'Node' is invalid." }
    }
    return [pscustomobject]@{ Success = $true; Value = $node; Error = '' }
}

function New-PmxManagementTokenResult {
    param([bool]$Success, [string[]]$Tokens, [string]$ErrorMessage)
    return [pscustomobject]@{ Success = $Success; Tokens = @($Tokens); Error = $ErrorMessage }
}

function New-PmxManagementQueryTokens {
    param([string]$Operation, [hashtable]$Parameters)

    $name = "$Operation".ToLowerInvariant()
    $allowed = switch ($name) {
        'version'       { @() }
        'node-list'     { @() }
        'node-status'   { @('Node') }
        'storage-list'  { @('Node') }
        'bridge-list'   { @('Node') }
        'vm-list'       { @() }
        'vm-config'     { @('Vmid', 'Node', 'Current') }
        'vm-status'     { @('Vmid', 'Node') }
        'vm-guest-network' { @('Vmid', 'Node') }
        'next-id'       { @('Vmid') }
        'snapshot-list' { @('Vmid', 'Node') }
        default { return New-PmxManagementTokenResult $false @() "Unsupported Proxmox query operation '$Operation'." }
    }
    $unexpected = Get-PmxManagementUnexpectedParameter $Parameters $allowed
    if ($unexpected) {
        return New-PmxManagementTokenResult $false @() "Parameter '$unexpected' is not valid for query operation '$name'."
    }

    switch ($name) {
        'version' {
            return New-PmxManagementTokenResult $true @('pvesh', 'get', '/version', '--output-format', 'json') ''
        }
        'node-list' {
            return New-PmxManagementTokenResult $true @('pvesh', 'get', '/nodes', '--output-format', 'json') ''
        }
        'node-status' {
            $node = Get-PmxManagementNode $Parameters
            if (-not $node.Success) { return New-PmxManagementTokenResult $false @() $node.Error }
            return New-PmxManagementTokenResult $true @('pvesh', 'get', "/nodes/$($node.Value)/status", '--output-format', 'json') ''
        }
        'storage-list' {
            $node = Get-PmxManagementNode $Parameters
            if (-not $node.Success) { return New-PmxManagementTokenResult $false @() $node.Error }
            return New-PmxManagementTokenResult $true @('pvesh', 'get', "/nodes/$($node.Value)/storage", '--content', 'images', '--enabled', '1', '--output-format', 'json') ''
        }
        'bridge-list' {
            $node = Get-PmxManagementNode $Parameters
            if (-not $node.Success) { return New-PmxManagementTokenResult $false @() $node.Error }
            return New-PmxManagementTokenResult $true @('pvesh', 'get', "/nodes/$($node.Value)/network", '--type', 'any_bridge', '--output-format', 'json') ''
        }
        'vm-list' {
            return New-PmxManagementTokenResult $true @('pvesh', 'get', '/cluster/resources', '--type', 'vm', '--output-format', 'json') ''
        }
        'next-id' {
            $arguments = @('pvesh', 'get', '/cluster/nextid')
            if ($Parameters.ContainsKey('Vmid')) {
                $vmid = ConvertTo-PmxManagementVmid $Parameters['Vmid']
                if ($null -eq $vmid) { return New-PmxManagementTokenResult $false @() "Parameter 'Vmid' must be from 100 through 999999999." }
                $arguments += @('--vmid', $vmid)
            }
            $arguments += @('--output-format', 'json')
            return New-PmxManagementTokenResult $true $arguments ''
        }
        'vm-guest-network' {
            $required = Get-PmxManagementRequiredParameter $Parameters 'Vmid'
            if (-not $required.Success) { return New-PmxManagementTokenResult $false @() $required.Error }
            $vmid = ConvertTo-PmxManagementVmid $required.Value
            if ($null -eq $vmid) { return New-PmxManagementTokenResult $false @() "Parameter 'Vmid' must be from 100 through 999999999." }
            $node = Get-PmxManagementNode $Parameters
            if (-not $node.Success) { return New-PmxManagementTokenResult $false @() $node.Error }
            return New-PmxManagementTokenResult $true @('qm', 'guest', 'cmd', $vmid, 'network-get-interfaces') ''
        }
        { $_ -in @('vm-config', 'vm-status', 'snapshot-list') } {
            $required = Get-PmxManagementRequiredParameter $Parameters 'Vmid'
            if (-not $required.Success) { return New-PmxManagementTokenResult $false @() $required.Error }
            $vmid = ConvertTo-PmxManagementVmid $required.Value
            if ($null -eq $vmid) { return New-PmxManagementTokenResult $false @() "Parameter 'Vmid' must be from 100 through 999999999." }
            $node = Get-PmxManagementNode $Parameters
            if (-not $node.Success) { return New-PmxManagementTokenResult $false @() $node.Error }
            $path = switch ($name) {
                'vm-config'     { "/nodes/$($node.Value)/qemu/$vmid/config" }
                'vm-status'     { "/nodes/$($node.Value)/qemu/$vmid/status/current" }
                'snapshot-list' { "/nodes/$($node.Value)/qemu/$vmid/snapshot" }
            }
            $arguments = @('pvesh', 'get', $path)
            if ($name -eq 'vm-config') {
                $current = $true
                if ($Parameters.ContainsKey('Current')) {
                    if ($Parameters['Current'] -isnot [bool]) {
                        return New-PmxManagementTokenResult $false @() "Parameter 'Current' must be Boolean."
                    }
                    $current = [bool]$Parameters['Current']
                }
                if ($current) { $arguments += @('--current', '1') }
            }
            $arguments += @('--output-format', 'json')
            return New-PmxManagementTokenResult $true $arguments ''
        }
    }
}

function Test-PmxManagementFullCloneValue {
    param($Value)
    if ($Value -is [bool]) { return [bool]$Value }
    return ("$Value" -eq '1' -or [string]::Equals("$Value", 'true', [StringComparison]::OrdinalIgnoreCase))
}

function Get-PmxManagementDigestTokens {
    param([hashtable]$Parameters)

    if (-not $Parameters.ContainsKey('Digest')) { return New-PmxManagementTokenResult $true @() '' }
    $digest = "$($Parameters['Digest'])"
    if ($digest -notmatch '^[0-9A-Fa-f]{40}$') {
        return New-PmxManagementTokenResult $false @() "Parameter 'Digest' must be a 40-character SHA1 configuration digest."
    }
    return New-PmxManagementTokenResult $true @('--digest', $digest.ToLowerInvariant()) ''
}

function New-PmxManagementChangeTokens {
    param([string]$Operation, [hashtable]$Parameters)

    $name = "$Operation".ToLowerInvariant()
    $allowed = switch ($name) {
        'vm-clone'      { @('SourceVmid', 'NewVmid', 'Name', 'Full') }
        'vm-set-cpu'    { @('Vmid', 'Cores', 'Digest') }
        'vm-set-memory' { @('Vmid', 'MemoryMiB', 'Digest') }
        'vm-disk-grow'  { @('Vmid', 'Disk', 'Size', 'Digest') }
        'vm-start'      { @('Vmid') }
        'vm-shutdown'   { @('Vmid') }
        'snapshot-create' { @('Vmid', 'Name') }
        default { return New-PmxManagementTokenResult $false @() "Unsupported Proxmox change operation '$Operation'." }
    }
    $unexpected = Get-PmxManagementUnexpectedParameter $Parameters $allowed
    if ($unexpected) {
        return New-PmxManagementTokenResult $false @() "Parameter '$unexpected' is not valid for change operation '$name'."
    }

    if ($name -eq 'vm-clone') {
        $sourceValue = Get-PmxManagementRequiredParameter $Parameters 'SourceVmid'
        $newValue = Get-PmxManagementRequiredParameter $Parameters 'NewVmid'
        $vmNameValue = Get-PmxManagementRequiredParameter $Parameters 'Name'
        if (-not $sourceValue.Success) { return New-PmxManagementTokenResult $false @() $sourceValue.Error }
        if (-not $newValue.Success) { return New-PmxManagementTokenResult $false @() $newValue.Error }
        if (-not $vmNameValue.Success) { return New-PmxManagementTokenResult $false @() $vmNameValue.Error }
        $sourceVmid = ConvertTo-PmxManagementVmid $sourceValue.Value
        $newVmid = ConvertTo-PmxManagementVmid $newValue.Value
        if ($null -eq $sourceVmid) { return New-PmxManagementTokenResult $false @() "Parameter 'SourceVmid' must be from 100 through 999999999." }
        if ($null -eq $newVmid) { return New-PmxManagementTokenResult $false @() "Parameter 'NewVmid' must be from 100 through 999999999." }
        if ($sourceVmid -eq $newVmid) { return New-PmxManagementTokenResult $false @() 'SourceVmid and NewVmid must be different.' }
        $vmName = "$($vmNameValue.Value)"
        if ($vmName -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$') {
            return New-PmxManagementTokenResult $false @() "Parameter 'Name' must be a 1-63 character VM name containing letters, digits, or internal hyphens."
        }
        if ($Parameters.ContainsKey('Full') -and -not (Test-PmxManagementFullCloneValue $Parameters['Full'])) {
            return New-PmxManagementTokenResult $false @() 'Only independent full clones are supported.'
        }
        return New-PmxManagementTokenResult $true @('qm', 'clone', $sourceVmid, $newVmid, '--name', $vmName, '--full', '1') ''
    }

    $vmidValue = Get-PmxManagementRequiredParameter $Parameters 'Vmid'
    if (-not $vmidValue.Success) { return New-PmxManagementTokenResult $false @() $vmidValue.Error }
    $vmid = ConvertTo-PmxManagementVmid $vmidValue.Value
    if ($null -eq $vmid) { return New-PmxManagementTokenResult $false @() "Parameter 'Vmid' must be from 100 through 999999999." }

    switch ($name) {
        'vm-set-cpu' {
            $value = Get-PmxManagementRequiredParameter $Parameters 'Cores'
            if (-not $value.Success) { return New-PmxManagementTokenResult $false @() $value.Error }
            $cores = ConvertTo-PmxManagementBoundedInt $value.Value 1 8192
            if ($null -eq $cores) { return New-PmxManagementTokenResult $false @() "Parameter 'Cores' must be from 1 through 8192." }
            $digest = Get-PmxManagementDigestTokens $Parameters
            if (-not $digest.Success) { return $digest }
            return New-PmxManagementTokenResult $true (@('qm', 'set', $vmid, '--cores', "$cores") + @($digest.Tokens)) ''
        }
        'vm-set-memory' {
            $value = Get-PmxManagementRequiredParameter $Parameters 'MemoryMiB'
            if (-not $value.Success) { return New-PmxManagementTokenResult $false @() $value.Error }
            $memory = ConvertTo-PmxManagementBoundedInt $value.Value 16 4194304
            if ($null -eq $memory) { return New-PmxManagementTokenResult $false @() "Parameter 'MemoryMiB' must be from 16 through 4194304." }
            $digest = Get-PmxManagementDigestTokens $Parameters
            if (-not $digest.Success) { return $digest }
            return New-PmxManagementTokenResult $true (@('qm', 'set', $vmid, '--memory', "$memory") + @($digest.Tokens)) ''
        }
        'vm-disk-grow' {
            $diskValue = Get-PmxManagementRequiredParameter $Parameters 'Disk'
            $sizeValue = Get-PmxManagementRequiredParameter $Parameters 'Size'
            if (-not $diskValue.Success) { return New-PmxManagementTokenResult $false @() $diskValue.Error }
            if (-not $sizeValue.Success) { return New-PmxManagementTokenResult $false @() $sizeValue.Error }
            $disk = "$($diskValue.Value)".ToLowerInvariant()
            if ($disk -notmatch '^(?:ide[0-3]|sata[0-5]|scsi(?:[0-9]|[12][0-9]|30)|virtio(?:[0-9]|1[0-5]))$') {
                return New-PmxManagementTokenResult $false @() "Parameter 'Disk' is not a supported virtual-disk slot."
            }
            $size = "$($sizeValue.Value)".ToUpperInvariant()
            if ($size -notmatch '^\+[1-9][0-9]{0,12}[KMGT]$') {
                return New-PmxManagementTokenResult $false @() "Parameter 'Size' must be a positive growth such as +70G."
            }
            $digest = Get-PmxManagementDigestTokens $Parameters
            if (-not $digest.Success) { return $digest }
            return New-PmxManagementTokenResult $true (@('qm', 'disk', 'resize', $vmid, $disk, $size) + @($digest.Tokens)) ''
        }
        'vm-start' {
            return New-PmxManagementTokenResult $true @('qm', 'start', $vmid) ''
        }
        'vm-shutdown' {
            return New-PmxManagementTokenResult $true @('qm', 'shutdown', $vmid) ''
        }
        'snapshot-create' {
            $snapshotValue = Get-PmxManagementRequiredParameter $Parameters 'Name'
            if (-not $snapshotValue.Success) { return New-PmxManagementTokenResult $false @() $snapshotValue.Error }
            $snapshot = "$($snapshotValue.Value)"
            if ($snapshot -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9_-]{0,38}[A-Za-z0-9])?$') {
                return New-PmxManagementTokenResult $false @() "Parameter 'Name' must be a 1-40 character snapshot name containing letters, digits, underscores, or internal hyphens."
            }
            return New-PmxManagementTokenResult $true @('qm', 'snapshot', $vmid, $snapshot) ''
        }
    }
}

function ConvertTo-PmxManagementSafeText {
    param($Value)

    $text = "$Value"
    $text = [regex]::Replace($text, "$([char]27)\[[0-?]*[ -/]*[@-~]", '')
    $text = [regex]::Replace($text, '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', '?')
    if ($text.Length -gt 2000) { return $text.Substring(0, 2000) }
    return $text
}

function Format-PmxManagementNativeCommand {
    param($Connection, [string[]]$Tokens)

    if ($Connection.Transport -eq 'local') { return ($Tokens -join ' ') }
    $label = "$(Get-PmxManagementConnectionValue $Connection 'Label')"
    if ($label -notmatch '^[a-z0-9][a-z0-9_-]{0,63}$') { $label = 'saved-server' }
    return (@('ssh', $label, '--') + $Tokens) -join ' '
}

function Get-PmxManagementRemoteFailure {
    param($Run)

    $diagnostic = "$($Run.Error)".ToLowerInvariant()
    if ($diagnostic -match 'permission denied|authentication failed|no supported authentication') {
        return [pscustomobject]@{ Kind = 'authentication-required'; Message = 'SSH authentication is required.' }
    }
    if ($diagnostic -match 'host key verification failed|remote host identification has changed') {
        return [pscustomobject]@{ Kind = 'host-key'; Message = 'SSH host-key verification failed.' }
    }
    if ($diagnostic -match 'timed out|connection refused|no route to host|could not resolve|name or service not known|network is unreachable') {
        return [pscustomobject]@{ Kind = 'unreachable'; Message = 'The saved Proxmox server is unreachable over SSH.' }
    }
    return [pscustomobject]@{ Kind = 'connection-failed'; Message = 'The Proxmox SSH command did not complete.' }
}

function Get-PmxManagementVmAgentFailure {
    param($Run)

    $diagnostic = "$($Run.Error)".ToLowerInvariant()
    if ($diagnostic -match 'timed out|timeout') {
        return [pscustomobject]@{ Kind = 'timeout'; Message = 'The VM agent request timed out.' }
    }
    if ($diagnostic -match 'not supported|unsupported|unknown command|not been implemented') {
        return [pscustomobject]@{ Kind = 'unsupported'; Message = 'VM agent network reporting is unsupported.' }
    }
    if ($diagnostic -match 'guest agent is not running|qemu guest agent is not running|guest-agent.*not running|not connected') {
        return [pscustomobject]@{ Kind = 'agent-unavailable'; Message = 'The VM agent is unavailable.' }
    }
    return $null
}

function Invoke-PmxManagementNative {
    param($Connection, [string[]]$Tokens)

    $nativeCommand = Format-PmxManagementNativeCommand $Connection $Tokens
    if ($Connection.Transport -eq 'local') {
        $executable = if ($Tokens[0] -eq 'pvesh') { $Connection.PveshPath } else { $Connection.QmPath }
        $arguments = @($Tokens | Select-Object -Skip 1)
    } else {
        $executable = $Connection.SshPath
        $arguments = @(
            '-o', 'BatchMode=yes', '-o', "ConnectTimeout=$($Connection.TimeoutSeconds)",
            '-p', "$($Connection.Port)", $Connection.Target
        ) + @($Tokens)
    }

    $oldPreference = $ErrorActionPreference
    $nativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
    if ($nativePreference) { $oldNativePreference = $nativePreference.Value }
    try {
        $ErrorActionPreference = 'Continue'
        if ($nativePreference) { $PSNativeCommandUseErrorActionPreference = $false }
        $output = @(& $executable @arguments 2>&1)
        $code = $LASTEXITCODE
    } catch {
        return [pscustomobject]@{
            Success       = $false
            Output        = @()
            StdOut        = @()
            StdErr        = @()
            Error         = ConvertTo-PmxManagementSafeText $_.Exception.Message
            ExitCode      = $null
            NativeCommand = $nativeCommand
        }
    } finally {
        $ErrorActionPreference = $oldPreference
        if ($nativePreference) { $PSNativeCommandUseErrorActionPreference = $oldNativePreference }
    }

    # Native stderr redirected into the success stream remains an ErrorRecord. Keep it
    # separate: pvesh stdout is the JSON document and a warning must not corrupt it.
    $stdout = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } |
        ForEach-Object { ConvertTo-PmxManagementSafeText $_ })
    $stderr = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } |
        ForEach-Object { ConvertTo-PmxManagementSafeText $_ })
    $errorText = if ($stderr.Count) { $stderr -join [Environment]::NewLine } else { $stdout -join [Environment]::NewLine }
    return [pscustomobject]@{
        Success       = ($code -eq 0)
        Output        = @($stdout + $stderr)
        StdOut        = $stdout
        StdErr        = $stderr
        Error         = if ($code -eq 0) { '' } else { $errorText }
        ExitCode      = $code
        NativeCommand = $nativeCommand
    }
}

function Test-ProxmoxManagementTransport {
    param($Connection)

    return [bool](Resolve-PmxManagementAdapterConnection $Connection).Success
}

function Invoke-ProxmoxManagementQuery {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [Parameter(Mandatory)]$Connection,
        [hashtable]$Parameters = @{}
    )

    $tokens = New-PmxManagementQueryTokens $Operation $Parameters
    if (-not $tokens.Success) { return New-PmxManagementResult $false $null $tokens.Error $null '' }
    $resolved = Resolve-PmxManagementAdapterConnection $Connection
    if (-not $resolved.Success) { return New-PmxManagementResult $false $null $resolved.Error $null '' }

    $run = Invoke-PmxManagementNative $resolved.Data $tokens.Tokens
    if (-not $run.Success) {
        if ($resolved.Data.Transport -eq 'ssh') {
            $failure = Get-PmxManagementRemoteFailure $run
            if ($failure.Kind -ne 'connection-failed') {
                return New-PmxManagementResult $false $null $failure.Message $run.ExitCode $run.NativeCommand $failure.Kind
            }
        }
        if ($Operation.ToLowerInvariant() -eq 'vm-guest-network') {
            $agentFailure = Get-PmxManagementVmAgentFailure $run
            if ($agentFailure) {
                return New-PmxManagementResult $false $null $agentFailure.Message $run.ExitCode $run.NativeCommand $agentFailure.Kind
            }
        }
        if ($resolved.Data.Transport -eq 'ssh') {
            $failure = Get-PmxManagementRemoteFailure $run
            return New-PmxManagementResult $false $null $failure.Message $run.ExitCode $run.NativeCommand $failure.Kind
        }
        $message = if ($run.Error) { $run.Error } else { "Proxmox query exited with code $($run.ExitCode)." }
        return New-PmxManagementResult $false $null $message $run.ExitCode $run.NativeCommand 'command-failed'
    }
    $json = $run.StdOut -join [Environment]::NewLine
    if (-not $json) {
        return New-PmxManagementResult $false $null 'Proxmox returned no JSON data.' $run.ExitCode $run.NativeCommand
    }
    try {
        $data = $json | ConvertFrom-Json
    } catch {
        return New-PmxManagementResult $false $null 'Proxmox returned malformed JSON.' $run.ExitCode $run.NativeCommand
    }
    $warning = if ($resolved.Data.Transport -eq 'ssh') { '' } else { $run.StdErr -join [Environment]::NewLine }
    return New-PmxManagementResult $true $data $warning $run.ExitCode $run.NativeCommand
}

function Invoke-ProxmoxManagementChange {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [Parameter(Mandatory)]$Connection,
        [hashtable]$Parameters = @{},
        [switch]$Preview
    )

    $tokens = New-PmxManagementChangeTokens $Operation $Parameters
    if (-not $tokens.Success) { return New-PmxManagementResult $false $null $tokens.Error $null '' }
    $resolved = Resolve-PmxManagementAdapterConnection $Connection
    if (-not $resolved.Success) { return New-PmxManagementResult $false $null $resolved.Error $null '' }
    $nativeCommand = Format-PmxManagementNativeCommand $resolved.Data $tokens.Tokens
    if ($Preview) {
        return New-PmxManagementResult $true ([pscustomobject]@{ Preview = $true }) '' $null $nativeCommand
    }

    $run = Invoke-PmxManagementNative $resolved.Data $tokens.Tokens
    if (-not $run.Success) {
        if ($resolved.Data.Transport -eq 'ssh') {
            $failure = Get-PmxManagementRemoteFailure $run
            return New-PmxManagementResult $false $null $failure.Message $run.ExitCode $run.NativeCommand $failure.Kind
        }
        $message = if ($run.Error) { $run.Error } else { "Proxmox change exited with code $($run.ExitCode)." }
        return New-PmxManagementResult $false $null $message $run.ExitCode $run.NativeCommand 'command-failed'
    }
    $warning = if ($resolved.Data.Transport -eq 'ssh') { '' } else { $run.StdErr -join [Environment]::NewLine }
    return New-PmxManagementResult $true @($run.StdOut) $warning $run.ExitCode $run.NativeCommand
}
