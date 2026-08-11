$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
}
function Assert-Equal($Expected, $Actual, [string]$Message) {
    if ("$Expected" -cne "$Actual") { throw "FAIL: $Message`n  expected: $Expected`n  actual:   $Actual" }
}

$root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$componentPath = Join-Path $root 'components/system/storage.ps1'
$assertions = 0

$script:Registered = @()
function Register-PFCommand {
    param([string]$Name, [string]$Synopsis, [string]$Section, [string]$Example,
          [string[]]$Aliases, [string]$Platform)
    $script:Registered += [pscustomobject]@{ Name = $Name; Section = $Section
        Synopsis = $Synopsis; Example = $Example }
}
$script:PowerFlowOS = 'windows'

. (Join-Path $root 'platform/windows/adapters/apps.ps1')
. $componentPath

# ---------------------------------------------------------------------------------
# Size formatting. The unit has to shift, because a storage table is read by eye and
# "1,863.0 GB" is measurably worse than "1.8 TB" for the one judgement being made.
# ---------------------------------------------------------------------------------
Assert-Equal '1.8 TB' (Format-StorageSize 2000000000000) 'terabyte-scale should render as TB'
Assert-Equal '85.1 GB' (Format-StorageSize 91400000000)  'gigabyte-scale should render as GB'
Assert-Equal '512 MB'  (Format-StorageSize 536870912)    'megabyte-scale should render as MB'
Assert-Equal '4 KB'    (Format-StorageSize 4096)         'kilobyte-scale should render as KB'
Assert-Equal '512 B'   (Format-StorageSize 512)          'byte-scale should render as B'
Assert-Equal '0 B'     (Format-StorageSize 0)            'zero should render, not blank'
$assertions += 6

# The unit boundaries are exact, which is where an off-by-one would hide.
Assert-Equal '1.0 TB' (Format-StorageSize 1TB) 'exactly 1TB should be TB, not 1024 GB'
Assert-Equal '1.0 GB' (Format-StorageSize 1GB) 'exactly 1GB should be GB, not 1024 MB'
Assert-True ((Format-StorageSize (1GB - 1)) -like '*MB') 'one byte under 1GB should still be MB'
$assertions += 3

# ---------------------------------------------------------------------------------
# The bar. Fixed width regardless of input, including out-of-range values — a bar that
# grows past its column would break the table the way the dkr status column did.
# ---------------------------------------------------------------------------------
foreach ($fraction in @(0, 0.001, 0.5, 0.999, 1, 1.5, -0.2)) {
    $bar = Format-StorageBar -UsedFraction $fraction
    Assert-Equal 18 $bar.Length "the bar must be exactly 18 wide for fraction $fraction"
    $assertions++
}
Assert-Equal ('.' * 18) (Format-StorageBar -UsedFraction 0) 'an empty volume should show an empty bar'
Assert-Equal ('#' * 18) (Format-StorageBar -UsedFraction 1) 'a full volume should show a full bar'
$assertions += 2

# ---------------------------------------------------------------------------------
# Headroom colouring. A percentage alone is the wrong signal: 10% of a 4 TB disk is
# 400 GB and fine, while 10% of a 128 GB SSD is trouble. BOTH a ratio and an absolute
# floor must be crossed before it warns.
# ---------------------------------------------------------------------------------
Assert-Equal 'Red' (Get-StorageColour -UsedFraction 0.96 -FreeBytes 5GB) `
    'nearly full with almost no headroom should be red'
Assert-Equal 'Green' (Get-StorageColour -UsedFraction 0.93 -FreeBytes 400GB) `
    '93% of a very large disk still has 400GB of headroom and must NOT alarm'
Assert-Equal 'Green' (Get-StorageColour -UsedFraction 0.20 -FreeBytes 10GB) `
    'a small but mostly empty volume is not a problem'
Assert-Equal 'Yellow' (Get-StorageColour -UsedFraction 0.87 -FreeBytes 30GB) `
    'getting tight on both measures should warn'
$assertions += 4

# ---------------------------------------------------------------------------------
# `storage` must NOT have a param() block. With one, PowerShell binds -a as a parameter
# NAME, and its PREFIX matching makes a single-letter switch ambiguous with every longer
# parameter sharing that letter — which is precisely why the volume is positional.
# ---------------------------------------------------------------------------------
$componentText = Get-Content -LiteralPath $componentPath -Raw
$storageBody = [regex]::Match($componentText, '(?ms)^function storage \{.*?^\}').Value
Assert-True ($storageBody.Length -gt 0) 'could not locate the storage function body'
Assert-True ($storageBody -notmatch '(?m)^\s*param\s*\(') 'storage must hand-parse $args, not declare param()'
$assertions += 2

# The volume must never be reachable as a flag — that is the decision this command exists
# to embody, and a later edit adding -D would silently undo it.
Assert-True ($componentText -notmatch "'-[A-Za-z]:'") 'a drive letter must not appear as a flag literal'
Assert-True ($storageBody -notmatch "\-in @\('-[c-fC-F]'") 'drive letters must not be parsed as flags'
$assertions += 2

# ---------------------------------------------------------------------------------
# Architecture — a component may not reach an OS API or a native binary directly.
# ---------------------------------------------------------------------------------
$code = @($componentText -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
Assert-True ($code -notmatch '\$env:(TEMP|USERPROFILE|LOCALAPPDATA|APPDATA|SystemRoot|SystemDrive)') `
    'the component must not read environment variables directly - that is the adapter''s job'
Assert-True ($code -notmatch 'Get-Volume|Get-PSDrive|Get-CimInstance|DriveInfo') `
    'the component must not enumerate volumes itself - it must call Get-StorageVolume'
# Branching on the OS is the same violation in a subtler form: it means the component holds
# platform knowledge even when it only uses it to print a string.
Assert-True ($code -notmatch '\$script:PowerFlowOS') `
    'the component must not branch on the OS - ask the adapter (Get-StorageNativeCommand)'
Assert-True ($code -notmatch '&\s*findmnt|&\s*df\b|&\s*lsblk|&\s*docker\b') `
    'the component must not invoke a native binary'
$assertions += 3

# ---------------------------------------------------------------------------------
# Automatic variables as locals — the bug class this repo has hit five or more times.
# ---------------------------------------------------------------------------------
foreach ($file in @($componentPath,
                    (Join-Path $root 'platform/windows/adapters/apps.ps1'),
                    (Join-Path $root 'platform/linux/adapters/apps.ps1'))) {
    $text = Get-Content -LiteralPath $file -Raw
    foreach ($auto in @('args', 'input', 'matches', 'PSItem', 'this')) {
        Assert-True ($text -notmatch "(?m)^\s*\`$$auto\s*=") `
            "$(Split-Path $file -Leaf) assigns to the automatic variable `$$auto"
        $assertions++
    }
}

# ---------------------------------------------------------------------------------
# The verbs must not collide with volume resolution, and vice versa. `storage apps` has to
# reach the verb even on a machine where some volume is labelled "apps".
# ---------------------------------------------------------------------------------
Assert-True ($storageBody -match "switch \(\`$verb\.ToLowerInvariant\(\)\)") `
    'verbs should be dispatched before falling through to volume resolution'
$verbSwitchIndex = $storageBody.IndexOf('switch ($verb.ToLowerInvariant())')
$resolveIndex    = $storageBody.IndexOf('Resolve-StorageVolume')
Assert-True ($verbSwitchIndex -ge 0 -and $resolveIndex -gt $verbSwitchIndex) `
    'volume resolution must come AFTER verb dispatch, or a verb could be eaten as a volume name'
$assertions += 2

# It must delegate rather than reimplement: two size-band browsers would drift apart.
Assert-True ($code -match 'installed-apps') 'storage apps should delegate to installed-apps'
Assert-True ($code -match 'disk-big') 'storage big should delegate to disk-big'
$assertions += 2

# ---------------------------------------------------------------------------------
# Help registration — CI fails the release on an unregistered kebab-named command.
# ---------------------------------------------------------------------------------
foreach ($expected in @('storage', 'storage apps', 'storage big', 'storage docker')) {
    $entry = $script:Registered | Where-Object { $_.Name -eq $expected }
    Assert-True ($null -ne $entry) "'$expected' is not registered for pwsh-h"
    Assert-Equal '🗄️ DISK RECLAIM' $entry.Section "'$expected' is in the wrong help section"
    Assert-True ([bool]$entry.Synopsis) "'$expected' has no synopsis"
    $assertions += 3
}

# The bootloader must load it, and AFTER apps.ps1 whose commands it delegates to.
$profileText = Get-Content -LiteralPath (Join-Path $root 'Microsoft.PowerShell_profile.ps1') -Raw
$appsAt    = $profileText.IndexOf('components\system\apps.ps1')
$storageAt = $profileText.IndexOf('components\system\storage.ps1')
Assert-True ($storageAt -gt 0) 'storage.ps1 is not loaded by the bootloader'
Assert-True ($appsAt -gt 0 -and $storageAt -gt $appsAt) `
    'storage.ps1 must load AFTER system/apps.ps1 - it delegates to installed-apps and disk-big'
$assertions += 2

Write-Host "  storage behaviour: $assertions assertions passed" -ForegroundColor Green
