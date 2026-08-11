$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
}
function Assert-Equal($Expected, $Actual, [string]$Message) {
    if ("$Expected" -cne "$Actual") { throw "FAIL: $Message`n  expected: $Expected`n  actual:   $Actual" }
}

$root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$assertions = 0

# ---------------------------------------------------------------------------------
# Contract parity. A storage function on one platform only would satisfy CI's regex and
# then explode at runtime on the other, so the files are compared to each other.
# ---------------------------------------------------------------------------------
$contract = @('Get-StorageVolume', 'Resolve-StorageVolume', 'Get-StorageNativeCommand')
$defined = @{}
foreach ($platform in @('linux', 'windows')) {
    $path = Join-Path $root "platform/$platform/adapters/apps.ps1"
    Assert-True (Test-Path -LiteralPath $path) "missing adapter: $path"
    $text = Get-Content -LiteralPath $path -Raw
    $found = @([regex]::Matches($text, '(?m)^function\s+([A-Za-z][\w-]*)') | ForEach-Object { $_.Groups[1].Value })
    $defined[$platform] = $found
    foreach ($name in $contract) {
        Assert-True ($found -contains $name) "$platform adapter is missing $name"
        $assertions++
    }
}

# ---------------------------------------------------------------------------------
# Selector resolution. Pure logic — volumes are injected, so this runs on either OS and
# tests the REAL adapter body rather than a reimplementation of it.
# ---------------------------------------------------------------------------------

# --- Windows ---------------------------------------------------------------------
. (Join-Path $root 'platform/windows/adapters/apps.ps1')

$winVolumes = @(
    [pscustomobject]@{ Name = 'C:'; Root = 'C:\'; Label = 'OS & Programs'; FileSystem = 'NTFS'
        SizeBytes = 999000000000; FreeBytes = 85000000000; IsSystem = $true;  DriveType = 'Fixed' }
    [pscustomobject]@{ Name = 'D:'; Root = 'D:\'; Label = 'Games';         FileSystem = 'NTFS'
        SizeBytes = 999000000000; FreeBytes = 190000000000; IsSystem = $false; DriveType = 'Fixed' }
    [pscustomobject]@{ Name = 'E:'; Root = 'E:\'; Label = 'My Passport';   FileSystem = 'NTFS'
        SizeBytes = 2000000000000; FreeBytes = 497000000000; IsSystem = $false; DriveType = 'Removable' }
)

# Everything a Windows user might plausibly type for the D drive.
foreach ($spelling in @('D', 'd', 'D:', 'd:', 'D:\', 'D:/')) {
    $hit = Resolve-StorageVolume -Selector $spelling -Volumes $winVolumes
    Assert-True ($null -ne $hit) "windows: '$spelling' should resolve to a volume"
    Assert-Equal 'D:' $hit.Name "windows: '$spelling' resolved to the wrong volume"
    $assertions += 2
}

# The label is a legitimate selector — it is what is printed in the overview.
$byLabel = Resolve-StorageVolume -Selector 'My Passport' -Volumes $winVolumes
Assert-Equal 'E:' $byLabel.Name 'windows: a volume label should resolve'
$assertions++

# A miss must return $null rather than guessing — acting on the wrong volume is the one
# outcome worse than an error.
foreach ($miss in @('Z', 'Z:', 'nope', '')) {
    Assert-True ($null -eq (Resolve-StorageVolume -Selector $miss -Volumes $winVolumes)) `
        "windows: '$miss' must not resolve to any volume"
    $assertions++
}

# A verb must never be swallowed as a volume; `storage apps` has to reach the verb.
foreach ($verb in @('apps', 'big', 'docker', 'help')) {
    Assert-True ($null -eq (Resolve-StorageVolume -Selector $verb -Volumes $winVolumes)) `
        "windows: the verb '$verb' must not resolve as a volume name"
    $assertions++
}

# --- Linux -----------------------------------------------------------------------
. (Join-Path $root 'platform/linux/adapters/apps.ps1')

$linuxVolumes = @(
    [pscustomobject]@{ Name = '/';          Root = '/';          Label = '/dev/sda2'; FileSystem = 'ext4'
        SizeBytes = 500000000000; FreeBytes = 40000000000;  IsSystem = $true;  DriveType = 'Fixed' }
    [pscustomobject]@{ Name = '/mnt/data';  Root = '/mnt/data';  Label = '/dev/sdb1'; FileSystem = 'ext4'
        SizeBytes = 4000000000000; FreeBytes = 900000000000; IsSystem = $false; DriveType = 'Fixed' }
    [pscustomobject]@{ Name = '/srv';       Root = '/srv';       Label = '/dev/sdc1'; FileSystem = 'xfs'
        SizeBytes = 2000000000000; FreeBytes = 100000000000; IsSystem = $false; DriveType = 'Fixed' }
)

foreach ($spelling in @('/mnt/data', '/mnt/data/')) {
    $hit = Resolve-StorageVolume -Selector $spelling -Volumes $linuxVolumes
    Assert-True ($null -ne $hit) "linux: '$spelling' should resolve"
    Assert-Equal '/mnt/data' $hit.Name "linux: '$spelling' resolved wrongly"
    $assertions += 2
}

# The trailing directory name is what someone types when they cannot recall the full path.
$byLeaf = Resolve-StorageVolume -Selector 'data' -Volumes $linuxVolumes
Assert-Equal '/mnt/data' $byLeaf.Name 'linux: a trailing directory name should resolve'
$assertions++

# The device is a legitimate selector too — it is what lsblk and findmnt print.
$byDevice = Resolve-StorageVolume -Selector '/dev/sdc1' -Volumes $linuxVolumes
Assert-Equal '/srv' $byDevice.Name 'linux: a device path should resolve to its mount'
$assertions++

# `/` must not be reachable by a bare empty string, and must not swallow other mounts.
Assert-Equal '/' (Resolve-StorageVolume -Selector '/' -Volumes $linuxVolumes).Name 'linux: / should resolve to itself'
Assert-True ($null -eq (Resolve-StorageVolume -Selector '' -Volumes $linuxVolumes)) 'linux: empty selector must not resolve'
$assertions += 2

foreach ($verb in @('apps', 'big', 'docker', 'help')) {
    Assert-True ($null -eq (Resolve-StorageVolume -Selector $verb -Volumes $linuxVolumes)) `
        "linux: the verb '$verb' must not resolve as a mount"
    $assertions++
}

# ---------------------------------------------------------------------------------
# The pseudo-filesystem filter — the load-bearing part of the Linux adapter.
#
# An unfiltered mount list on a modern desktop is mostly noise: one squashfs loop per
# installed snap (often dozens), a tmpfs per user session, plus the kernel's own
# pseudo-filesystems. If any of these leak through, the two mounts that matter are buried.
# ---------------------------------------------------------------------------------
$mustFilter = @('proc', 'sysfs', 'devtmpfs', 'devpts', 'tmpfs', 'ramfs', 'cgroup', 'cgroup2',
                'squashfs', 'overlay', 'autofs', 'debugfs', 'tracefs', 'efivarfs', 'bpf',
                'configfs', 'mqueue', 'hugetlbfs', 'pstore', 'securityfs', 'binfmt_misc', 'nsfs')
foreach ($fs in $mustFilter) {
    Assert-True ($script:PF_PseudoFilesystems -contains $fs) `
        "the pseudo-filesystem filter is missing '$fs' — it would appear as real storage"
    $assertions++
}

# Real filesystems must NOT be filtered, or the volume the user cares about disappears.
foreach ($fs in @('ext4', 'xfs', 'btrfs', 'zfs', 'ntfs', 'vfat', 'exfat', 'f2fs')) {
    Assert-True ($script:PF_PseudoFilesystems -notcontains $fs) `
        "'$fs' is a REAL filesystem and must not be filtered out"
    $assertions++
}

# --- findmnt parsing, exercised through the real parser ----------------------------
# The fixture is the shape `findmnt -J -l -o TARGET,SOURCE,FSTYPE,SIZE,AVAIL` emits on a
# desktop with one data disk and a handful of snaps.
$findmntJson = (@{ filesystems = @(
        @{ target = '/';           source = '/dev/sda2';   fstype = 'ext4';     size = '500G'; avail = '40G' },
        @{ target = '/mnt/data';   source = '/dev/sdb1';   fstype = 'ext4';     size = '4T';   avail = '900G' },
        @{ target = '/proc';       source = 'proc';        fstype = 'proc';     size = '0';    avail = '0' },
        @{ target = '/run';        source = 'tmpfs';       fstype = 'tmpfs';    size = '3G';   avail = '3G' },
        @{ target = '/snap/core/1'; source = '/dev/loop0'; fstype = 'squashfs'; size = '128M'; avail = '0' },
        @{ target = '/sys/fs/cgroup'; source = 'cgroup2';  fstype = 'cgroup2';  size = '0';    avail = '0' }
    ) } | ConvertTo-Json -Depth 5 -Compress)

$candidates = @(ConvertFrom-PFFindmntJson $findmntJson)
Assert-Equal 6 $candidates.Count 'findmnt JSON should parse every row before filtering'
$assertions++

$realOnes = @($candidates | Where-Object { $_.FsType -notin $script:PF_PseudoFilesystems })
Assert-Equal 2 $realOnes.Count "the filter should leave exactly the 2 real mounts, got: $(@($realOnes | ForEach-Object { $_.Target }) -join ', ')"
Assert-True (@($realOnes | ForEach-Object { $_.Target }) -contains '/mnt/data') 'the data mount must survive the filter'
Assert-True (@($realOnes | ForEach-Object { $_.Target }) -contains '/') 'the root mount must survive the filter'
$assertions += 3

# Malformed or absent output must yield nothing rather than throwing — findmnt is missing on
# minimal images, and a storage command that dies is worse than one that says nothing.
foreach ($bad in @('', '   ', 'not json', '<xml/>', '{')) {
    Assert-Equal 0 (@(ConvertFrom-PFFindmntJson $bad)).Count "malformed findmnt output '$bad' should yield no candidates"
    $assertions++
}

Write-Host "  storage volume contracts: $assertions assertions passed" -ForegroundColor Green
