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
    }
    Save-PFServers $servers
    function Test-ServerOnline { return 'online' }
    function Test-PFServerInteractiveAuth { return $true }

    $script:sshExit = 255
    $script:sshCalls = @()
    function ssh {
        $script:sshCalls += (, @($args))
        $global:LASTEXITCODE = $script:sshExit
        if ($script:sshExit -ne 0) { Write-Output 'fixture connection failed' }
    }

    $failedText = ConvertTo-TestText @(& { srv lab info } 6>&1)
    Assert-PrivateEndpointAbsent $failedText
    Assert-True ($failedText -match 'details remain hidden') 'failed authentication says details remain hidden'
    Assert-True (($script:sshCalls[0] -join '|') -eq '-p|22445|-o|LogLevel=ERROR|-o|RequestTTY=no|fixture-admin@endpoint.example.invalid|exit 0') 'authentication probe uses fixed native tokens'

    $script:sshExit = 0
    $successText = ConvertTo-TestText @(& { srv lab info } 6>&1)
    Assert-True ($successText -match 'authenticated connection info') 'success labels authenticated view'
    Assert-True ($successText -match 'fixture-admin@endpoint\.example\.invalid:22445') 'success reveals saved SSH endpoint'
    Assert-True ($successText -match 'Status\s+:.*online') 'success retains live state'

    function Test-PFServerInteractiveAuth { return $false }
    $redirectedText = ConvertTo-TestText @(& { srv lab info } 6>&1)
    Assert-PrivateEndpointAbsent $redirectedText
    Assert-True ($redirectedText -match 'requires interactive SSH authentication') 'non-interactive info fails closed'
    Assert-True ($script:sshCalls.Count -eq 2) 'non-interactive refusal never invokes SSH'
}
finally {
    Remove-TestRoot $testHome
}

Write-Host 'OK - srv info reveals endpoints only after successful SSH authentication.'
