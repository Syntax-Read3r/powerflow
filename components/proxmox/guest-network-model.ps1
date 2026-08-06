# ==============================================================================
# PowerFlow — Proxmox VM-Reported Network Model
# ==============================================================================
# Domain   : Proxmox
# File     : components/proxmox/guest-network-model.ps1
# Purpose  : Normalize VM-reported interfaces, addresses, stats, and MAC matches
# Functions: Get-PmxNetworkAddressRecord, Get-PmxVmReportedNetworkInterfaces,
#            Select-PmxNetworkAddresses, Join-PmxNetworkAdapters,
#            Get-PmxPrimaryAddressSelection
# Depends  : shared.ps1, network-config-model.ps1
# ==============================================================================

function Get-PmxNullableInt64 {
    param($Value)

    if ($null -eq $Value -or "$Value" -eq '') { return $null }
    $number = 0L
    if (-not [long]::TryParse("$Value", [ref]$number) -or $number -lt 0) { return $null }
    return $number
}

function Get-PmxNetworkAddressRecord {
    param(
        [Parameter(Mandatory)]$Address,
        $Prefix = $null
    )

    $text = "$(ConvertTo-PmxDisplayText $Address)"
    $parsedAddress = $null
    if (-not [Net.IPAddress]::TryParse($text, [ref]$parsedAddress)) {
        return [pscustomobject][ordered]@{
            Address = $text; Prefix = $null; Cidr = $text; Type = 'unknown'; Scope = 'invalid'
            Valid = $false; SortKey = "9-$text"
        }
    }

    $type = if ($parsedAddress.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork) { 'IPv4' } else { 'IPv6' }
    $maximumPrefix = if ($type -eq 'IPv4') { 32 } else { 128 }
    $prefixNumber = $null
    if ($null -ne $Prefix -and "$Prefix" -ne '') {
        $candidate = 0
        if ([int]::TryParse("$Prefix", [ref]$candidate) -and $candidate -ge 0 -and $candidate -le $maximumPrefix) {
            $prefixNumber = $candidate
        }
    }
    $bytes = $parsedAddress.GetAddressBytes()
    $scope = if ($type -eq 'IPv4') {
        if ($bytes[0] -eq 0 -and $bytes[1] -eq 0 -and $bytes[2] -eq 0 -and $bytes[3] -eq 0) { 'unspecified' }
        elseif ($bytes[0] -eq 127) { 'loopback' }
        elseif ($bytes[0] -eq 169 -and $bytes[1] -eq 254) { 'link-local' }
        elseif ($bytes[0] -eq 10 -or ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) -or
            ($bytes[0] -eq 192 -and $bytes[1] -eq 168)) { 'private' }
        elseif ($bytes[0] -ge 224 -and $bytes[0] -le 239) { 'multicast' }
        else { 'global' }
    }
    else {
        $allZero = -not @($bytes | Where-Object { $_ -ne 0 }).Count
        if ($allZero) { 'unspecified' }
        elseif ($parsedAddress.Equals([Net.IPAddress]::IPv6Loopback)) { 'loopback' }
        elseif ($bytes[0] -eq 0xFF) { 'multicast' }
        elseif ($bytes[0] -eq 0xFE -and (($bytes[1] -band 0xC0) -eq 0x80)) { 'link-local' }
        elseif (($bytes[0] -band 0xFE) -eq 0xFC) { 'unique-local' }
        else { 'global' }
    }
    $canonical = $parsedAddress.ToString()
    $hex = @($bytes | ForEach-Object { $_.ToString('X2') }) -join ''
    return [pscustomobject][ordered]@{
        Address = $canonical
        Prefix  = $prefixNumber
        Cidr    = if ($null -ne $prefixNumber) { "$canonical/$prefixNumber" } else { $canonical }
        Type    = $type
        Scope   = $scope
        Valid   = $true
        SortKey = "$(if ($type -eq 'IPv4') { 0 } else { 1 })-$hex-$(if ($null -ne $prefixNumber) { '{0:D3}' -f $prefixNumber } else { '999' })"
    }
}

function Get-PmxVmReportedNetworkInterfaces {
    param($Data)

    $rows = @()
    foreach ($item in @($Data)) {
        if ($null -eq $item) { continue }
        $name = ConvertTo-PmxDisplayText (Get-PmxObjectProperty $item 'name' '')
        $rawMac = ConvertTo-PmxDisplayText (Get-PmxObjectProperty $item 'hardware-address' '')
        $addresses = @()
        foreach ($address in @(Get-PmxObjectProperty $item 'ip-addresses' @())) {
            $addresses += Get-PmxNetworkAddressRecord `
                -Address (Get-PmxObjectProperty $address 'ip-address' '') `
                -Prefix (Get-PmxObjectProperty $address 'prefix' $null)
        }
        $statistics = Get-PmxObjectProperty $item 'statistics' $null
        $stats = if ($null -eq $statistics) { $null } else {
            [pscustomobject][ordered]@{
                RxBytes   = Get-PmxNullableInt64 (Get-PmxObjectProperty $statistics 'rx-bytes' $null)
                RxPackets = Get-PmxNullableInt64 (Get-PmxObjectProperty $statistics 'rx-packets' $null)
                RxErrors  = Get-PmxNullableInt64 (Get-PmxObjectProperty $statistics 'rx-errs' $null)
                RxDropped = Get-PmxNullableInt64 (Get-PmxObjectProperty $statistics 'rx-dropped' $null)
                TxBytes   = Get-PmxNullableInt64 (Get-PmxObjectProperty $statistics 'tx-bytes' $null)
                TxPackets = Get-PmxNullableInt64 (Get-PmxObjectProperty $statistics 'tx-packets' $null)
                TxErrors  = Get-PmxNullableInt64 (Get-PmxObjectProperty $statistics 'tx-errs' $null)
                TxDropped = Get-PmxNullableInt64 (Get-PmxObjectProperty $statistics 'tx-dropped' $null)
            }
        }
        $rows += [pscustomobject][ordered]@{
            Name           = $name
            MacAddress     = ConvertTo-PmxNormalizedMac $rawMac
            RawMacAddress  = if ($rawMac) { $rawMac } else { $null }
            MatchedAdapter = $null
            Addresses      = @($addresses | Sort-Object SortKey)
            Stats          = $stats
        }
    }
    return @($rows | Sort-Object Name, MacAddress)
}

function Select-PmxNetworkAddresses {
    param(
        [object[]]$Interfaces = @(),
        [switch]$IPv4,
        [switch]$IPv6,
        [switch]$IncludeLoopback,
        [switch]$All
    )

    $filtered = @()
    foreach ($interface in @($Interfaces)) {
        $addresses = @($interface.Addresses | Where-Object {
            $row = $_
            $familyAllowed = if ($IPv4 -or $IPv6) {
                ($IPv4 -and $row.Type -eq 'IPv4') -or ($IPv6 -and $row.Type -eq 'IPv6')
            } else { $true }
            $scopeAllowed = if ($All) { $true } elseif ($row.Scope -eq 'loopback') { [bool]$IncludeLoopback } else { $row.Scope -ne 'unspecified' }
            $familyAllowed -and $scopeAllowed
        })
        $filtered += [pscustomobject][ordered]@{
            Name           = $interface.Name
            MacAddress     = $interface.MacAddress
            RawMacAddress  = $interface.RawMacAddress
            MatchedAdapter = $interface.MatchedAdapter
            Addresses      = $addresses
            Stats          = $interface.Stats
        }
    }
    return $filtered
}

function Join-PmxNetworkAdapters {
    param(
        [object[]]$Adapters = @(),
        [object[]]$Interfaces = @()
    )

    $warnings = @()
    foreach ($adapter in @($Adapters)) { $adapter.MatchedInterfaces = @() }
    foreach ($interface in @($Interfaces)) { $interface.MatchedAdapter = $null }
    $macs = @(@($Adapters.MacAddress) + @($Interfaces.MacAddress) | Where-Object { $_ } | Sort-Object -Unique)
    foreach ($mac in $macs) {
        $adapterMatches = @($Adapters | Where-Object { $_.MacAddress -ceq $mac })
        $interfaceMatches = @($Interfaces | Where-Object { $_.MacAddress -ceq $mac })
        if ($adapterMatches.Count -eq 1 -and $interfaceMatches.Count -eq 1) {
            $adapterMatches[0].MatchedInterfaces = @($interfaceMatches[0].Name)
            $interfaceMatches[0].MatchedAdapter = $adapterMatches[0].Adapter
        }
        elseif ($adapterMatches.Count -and $interfaceMatches.Count) {
            $warnings += "MAC $mac is ambiguous and was not used to match an adapter to a VM interface."
        }
    }
    return [pscustomobject][ordered]@{ Adapters = @($Adapters); Interfaces = @($Interfaces); Warnings = @($warnings) }
}

function Get-PmxPrimaryAddressSelection {
    param(
        [object[]]$Interfaces = @(),
        [switch]$IPv4,
        [switch]$IPv6
    )

    $ranked = @()
    foreach ($interface in @($Interfaces)) {
        foreach ($address in @($interface.Addresses)) {
            if (-not $address.Valid -or $address.Scope -in @('loopback', 'unspecified', 'multicast', 'invalid')) { continue }
            if ($IPv4 -and -not $IPv6 -and $address.Type -ne 'IPv4') { continue }
            if ($IPv6 -and -not $IPv4 -and $address.Type -ne 'IPv6') { continue }
            $familyRank = if (-not $IPv4 -and -not $IPv6 -and $address.Type -eq 'IPv6') { 1 } else { 0 }
            $scopeRank = if ($address.Scope -in @('private', 'global', 'unique-local')) { 0 } else { 1 }
            $adapterRank = if ($interface.MatchedAdapter -ceq 'net0') { 0 } else { 1 }
            $rankKey = "$familyRank-$scopeRank-$adapterRank"
            $ranked += [pscustomobject][ordered]@{
                Address = $address.Address; Cidr = $address.Cidr; Type = $address.Type
                Scope = $address.Scope; Interface = $interface.Name; Adapter = $interface.MatchedAdapter
                RankKey = $rankKey
            }
        }
    }
    $ordered = @($ranked | Sort-Object RankKey, Address, Interface)
    if (-not $ordered.Count) {
        return [pscustomobject][ordered]@{ PrimaryCandidate = $null; Candidates = @(); Inferred = $true; Reason = 'no eligible address was reported' }
    }
    $bestRank = $ordered[0].RankKey
    $best = @($ordered | Where-Object RankKey -ceq $bestRank)
    $candidateRows = @($best | ForEach-Object {
        [pscustomobject][ordered]@{
            address = $_.Address; cidr = $_.Cidr; type = $_.Type; scope = $_.Scope
            interface = $_.Interface; adapter = $_.Adapter
        }
    })
    $reason = if ($best.Count -eq 1) {
        'best address by family, scope, and configured-adapter match'
    } else { 'multiple addresses share the best rank' }
    return [pscustomobject][ordered]@{
        PrimaryCandidate = if ($best.Count -eq 1) { $best[0].Address } else { $null }
        Candidates       = $candidateRows
        Inferred         = $true
        Reason           = $reason
    }
}
