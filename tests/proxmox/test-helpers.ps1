$ErrorActionPreference = 'Stop'

function Assert-PmxTest {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) { throw $Message }
}

function Assert-PmxEqual {
    param($Expected, $Actual, [Parameter(Mandatory)][string]$Message)

    $expectedJson = ConvertTo-Json @($Expected) -Compress -Depth 12
    $actualJson = ConvertTo-Json @($Actual) -Compress -Depth 12
    if ($expectedJson -cne $actualJson) {
        throw "$Message`nExpected: $expectedJson`nActual:   $actualJson"
    }
}

function Write-PmxTestPass {
    param([Parameter(Mandatory)][string]$Name)
    Write-Host "  OK  $Name"
}
