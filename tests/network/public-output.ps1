. (Join-Path $PSScriptRoot 'test-helpers.ps1')

$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$testHome = Join-Path ([IO.Path]::GetTempPath()) "powerflow-srv-test-$([guid]::NewGuid().ToString('N'))"
try {
    New-Item -ItemType Directory -Path $testHome -Force | Out-Null
    function Get-HomePath { return $testHome }
    function Register-PFCommand {}
    . (Join-Path $root 'components/network/server-privacy.ps1')
    . (Join-Path $root 'components/network/servers.ps1')

    $servers = @{
        lab = [pscustomobject]@{ host='endpoint.example.invalid'; user='fixture-admin'; port=22445; addedAt='2026-01-01T00:00:00Z'; lastSeen=$null }
        spare = [pscustomobject]@{ host='spare.example.invalid'; user='spare-admin'; port=22; addedAt='2026-01-01T00:00:00Z'; lastSeen=$null }
    }
    Save-PFServers $servers

    function Test-ServerOnline { return 'online' }
    function Get-PFServerStatuses {
        param([hashtable]$Servers)
        $map=@{}; foreach($name in $Servers.Keys){$map[$name]='online'}; return $map
    }
    $script:sshCalls = @()
    function ssh {
        $script:sshCalls += (, @($args))
        $global:LASTEXITCODE = 0
    }

    $listText = ConvertTo-TestText @(& { srv list } 6>&1)
    Assert-PrivateEndpointAbsent $listText
    Assert-True ($listText -match 'lab' -and $listText -match 'online') 'list keeps alias and status'

    $row = Format-PFServerPublicRow -Name 'lab' -State online -Server $servers.lab
    Assert-PrivateEndpointAbsent $row
    Assert-True ($row -eq "lab`t✅ online") 'picker row is alias and status only'

    $connectText = ConvertTo-TestText @(& { srv lab } 6>&1)
    Assert-PrivateEndpointAbsent $connectText
    Assert-True ($script:sshCalls.Count -eq 1) 'direct alias connects once'
    Assert-True (($script:sshCalls[0] -join '|') -eq '-p|22445|fixture-admin@endpoint.example.invalid') 'native SSH receives exact stored target tokens'

    $duplicateText = ConvertTo-TestText @(& { srv add lab replacement@replacement.example.invalid:22999 } 6>&1)
    Assert-PrivateEndpointAbsent $duplicateText @('fixture-admin','endpoint.example.invalid','22445','replacement','replacement.example.invalid','22999')

    $renameText = ConvertTo-TestText @(& { srv rename lab spare } 6>&1)
    Assert-PrivateEndpointAbsent $renameText @('fixture-admin','endpoint.example.invalid','22445','spare-admin','spare.example.invalid')

    $script:readPrompts = @()
    function Read-Host { param([string]$Prompt); $script:readPrompts += $Prompt; return 'n' }
    $removeText = ConvertTo-TestText @(& { srv rm lab } 6>&1)
    Assert-PrivateEndpointAbsent ($removeText + "`n" + ($script:readPrompts -join "`n"))

    $saveText = ConvertTo-TestText @(& { srv add fresh new-admin@new-endpoint.example.invalid:22555 } 6>&1)
    Assert-PrivateEndpointAbsent $saveText @('new-admin','new-endpoint.example.invalid','22555')
    Assert-True ($saveText -match 'Saved: fresh' -and $saveText -match 'online') 'save confirmation is alias/status only'
}
finally {
    Remove-TestRoot $testHome
}

Write-Host 'OK - ordinary srv output and native connection tokens stay separated.'
