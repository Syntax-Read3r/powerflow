# ==============================================================================
# PowerFlow — Proxmox Configured Network Adapter Model
# ==============================================================================
# Domain   : Proxmox
# File     : components/proxmox/network-config-model.ps1
# Purpose  : Parse configured VM adapters and agent-channel state without I/O
# Functions: ConvertTo-PmxNormalizedMac, Get-PmxConfiguredNetworkAdapters,
#            Get-PmxVmAgentConfiguration
# Depends  : shared.ps1
# ==============================================================================

function ConvertTo-PmxNormalizedMac {
    param($Value)

    $text = "$(ConvertTo-PmxDisplayText $Value)".Trim()
    if ($text -notmatch '^(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$') { return $null }
    return (($text -replace '-', ':').ToUpperInvariant())
}

function Get-PmxConfiguredNetworkAdapters {
    param([Parameter(Mandatory)]$Config)

    $rows = @()
    foreach ($property in @($Config.PSObject.Properties | Where-Object { $_.Name -cmatch '^net([0-9]+)$' })) {
        $slotNumber = [int]([regex]::Match($property.Name, '[0-9]+').Value)
        $raw = "$(ConvertTo-PmxDisplayText $property.Value)"
        $parts = @($raw -split ',')
        $values = @{}
        $model = ''
        $rawMac = ''
        $partIndex = 0
        foreach ($part in $parts) {
            $pair = $part -split '=', 2
            if ($pair.Count -ne 2) { $partIndex++; continue }
            $key = $pair[0].Trim().ToLowerInvariant()
            $value = "$(ConvertTo-PmxDisplayText $pair[1])"
            # Proxmox places the adapter model/MAC pair first. Treat that position as
            # authoritative so new model names do not silently lose their identity.
            if ($partIndex -eq 0 -and $key -notin @('bridge', 'firewall', 'tag', 'link_down', 'rate', 'mtu', 'queues', 'trunks')) {
                if (-not $model) { $model = $key }
                if (-not $rawMac) { $rawMac = $value }
            }
            else { $values[$key] = $value }
            $partIndex++
        }

        $firewall = $null
        if ($values.ContainsKey('firewall')) { $firewall = ($values['firewall'] -eq '1') }
        $linkDown = $false
        if ($values.ContainsKey('link_down')) { $linkDown = ($values['link_down'] -eq '1') }
        $vlan = $null
        if ($values.ContainsKey('tag')) {
            $number = 0
            if ([int]::TryParse($values['tag'], [ref]$number)) { $vlan = $number }
        }
        $rate = $null
        if ($values.ContainsKey('rate')) {
            $number = [decimal]0
            if ([decimal]::TryParse($values['rate'], [Globalization.NumberStyles]::Number,
                [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) { $rate = $number }
        }
        $mtu = $null
        if ($values.ContainsKey('mtu')) {
            $number = 0
            if ([int]::TryParse($values['mtu'], [ref]$number)) { $mtu = $number }
        }

        $rows += [pscustomobject][ordered]@{
            Adapter          = $property.Name.ToLowerInvariant()
            AdapterNumber    = $slotNumber
            Model            = if ($model) { $model } else { $null }
            Bridge           = if ($values.ContainsKey('bridge')) { $values['bridge'] } else { $null }
            MacAddress       = ConvertTo-PmxNormalizedMac $rawMac
            RawMacAddress    = if ($rawMac) { $rawMac } else { $null }
            Firewall         = $firewall
            Vlan             = $vlan
            Link             = if ($linkDown) { 'down' } else { 'configured-up' }
            RateLimitMbps    = $rate
            Mtu              = $mtu
            MatchedInterfaces = @()
            Raw              = $raw
        }
    }
    return @($rows | Sort-Object AdapterNumber)
}

function Get-PmxVmAgentConfiguration {
    param([Parameter(Mandatory)]$Config)

    $value = Get-PmxObjectProperty $Config 'agent' $null
    if ($null -eq $value -or "$value" -eq '') {
        return [pscustomobject][ordered]@{ Configured = $false; Value = $null }
    }
    if ($value -is [bool]) {
        return [pscustomobject][ordered]@{ Configured = [bool]$value; Value = "$value" }
    }
    $text = "$(ConvertTo-PmxDisplayText $value)".Trim().ToLowerInvariant()
    $enabled = if ($text -match '(?:^|,)enabled=([01])(?:,|$)') {
        $matches[1] -eq '1'
    }
    elseif ($text -match '^([01])(?:,|$)') { $matches[1] -eq '1' }
    else { $true }
    return [pscustomobject][ordered]@{ Configured = $enabled; Value = $text }
}
