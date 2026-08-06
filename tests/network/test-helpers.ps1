$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
}

function ConvertTo-TestText {
    param([object[]]$Value)
    return (@($Value | ForEach-Object { "$_" }) -join "`n")
}

function Assert-PrivateEndpointAbsent {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [string[]]$Sentinels = @('fixture-admin', 'endpoint.example.invalid', '22445')
    )
    foreach ($sentinel in $Sentinels) {
        Assert-True (-not $Text.Contains($sentinel, [StringComparison]::OrdinalIgnoreCase)) "ordinary output exposed '$sentinel'"
    }
}

function Remove-TestRoot {
    param([Parameter(Mandatory)][string]$Path)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $resolved = [IO.Path]::GetFullPath($Path)
    if ($resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path $resolved -Leaf) -like 'powerflow-srv-test-*' -and
        (Test-Path -LiteralPath $resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
