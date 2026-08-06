# Regression test for authenticated, retrying Linux dependency release lookups.
# Runs without Pester so the release workflow can execute it on a clean runner.

$ErrorActionPreference = 'Stop'
$adapter = Join-Path $PSScriptRoot '..' '..' 'platform' 'linux' 'adapters' 'packages.ps1'
. (Resolve-Path $adapter)

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) { throw $Message }
}

$originalToken = $env:GITHUB_TOKEN

try {
    $env:GITHUB_TOKEN = 'powerflow-regression-token'
    $script:requestCount = 0
    $script:observedHeaders = $null

    function Invoke-RestMethod {
        param(
            [string]$Uri,
            [hashtable]$Headers,
            [int]$TimeoutSec,
            [System.Management.Automation.ActionPreference]$ErrorAction
        )

        $script:requestCount++
        $script:observedHeaders = $Headers

        if ($script:requestCount -eq 1) { throw 'simulated transient GitHub failure' }
        return [pscustomobject]@{ assets = @() }
    }

    function Start-Sleep { param([int]$Seconds) }

    $null = Invoke-GitHubApiRequest -Uri 'https://api.github.test/repos/example/tool/releases/latest' `
        -MaxAttempts 2

    Assert-True ($script:requestCount -eq 2) 'GitHub API request was not retried.'
    Assert-True ($script:observedHeaders.Authorization -eq 'Bearer powerflow-regression-token') `
        'GITHUB_TOKEN was not sent as a Bearer authorization header.'
    Assert-True ($script:observedHeaders.Accept -eq 'application/vnd.github+json') `
        'GitHub API media type header is missing.'

    Remove-Item Env:GITHUB_TOKEN
    $headersWithoutToken = Get-GitHubApiHeaders
    Assert-True (-not $headersWithoutToken.ContainsKey('Authorization')) `
        'Anonymous installs must not send an empty authorization header.'

    Write-Host 'OK - GitHub release requests authenticate when possible and retry transient failures.'
}
finally {
    if ($null -eq $originalToken) { Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue }
    else { $env:GITHUB_TOKEN = $originalToken }
}
