. (Join-Path $PSScriptRoot 'test-helpers.ps1')
. (Join-Path $PSScriptRoot '..' '..' 'platform' 'linux' 'adapters' 'proxmox.ps1')

$tree = @'
{
  "name": "/dev/sdg",
  "type": "disk",
  "maj:min": "8:96",
  "children": [
    {
      "name": "/dev/sdg1",
      "type": "part",
      "maj:min": "8:97",
      "children": [
        { "name": "/dev/mapper/vmdata", "type": "lvm", "maj:min": "253:4" }
      ]
    }
  ]
}
'@ | ConvertFrom-Json
$descendants = @(Get-PmxBlockDescendants $tree)
Assert-PmxTest ($descendants.Count -eq 2) 'Nested partition/mapped descendants were not both retained.'
Assert-PmxEqual @('8:97', '253:4') @($descendants | ForEach-Object { Get-PmxBlockMajorMinor $_ }) `
    'Descendant major:minor identities were not parsed from lsblk JSON.'

function Test-Path { param([string]$LiteralPath); return ($LiteralPath -ceq '/proc') }
function Get-ChildItem {
    param([string]$LiteralPath, [switch]$Directory, $ErrorAction)
    if ($LiteralPath -ceq '/proc') { return [pscustomobject]@{ Name = '4321'; FullName = '/proc/4321' } }
    return @()
}
function Get-Content {
    param([string]$LiteralPath, [switch]$Raw, $ErrorAction)
    $normalPath = $LiteralPath -replace '\\', '/'
    if ($normalPath -ceq '/proc/4321/mountinfo') {
        return @(
            '41 29 8:97 / /mnt/data rw,relatime - ext4 /dev/sdg1 rw',
            '42 29 253:4 / /mnt/vmdata rw,relatime - ext4 /dev/mapper/vmdata rw'
        )
    }
    return @()
}

$namespace = Get-PmxMountNamespaceCheck -MajorMinor @('8:96', '8:97', '253:4')
Assert-PmxTest ($namespace.Success -and $namespace.References.Count -eq 2) `
    'Mount-namespace check did not match partition and mapped descendant identities.'
Assert-PmxTest (-not (Get-PmxMountNamespaceCheck -MajorMinor @('8:96', 'bad')).Success) `
    'Malformed descendant identity did not fail closed.'
Assert-PmxTest (-not (Get-PmxOpenHandleCheck -DevicePath @('/dev/sdg', 'not-a-device')).Success) `
    'Malformed descendant path did not fail closed before invoking fuser.'
Write-PmxTestPass 'physical-disk descendant identities and fail-closed namespace/handle model'
