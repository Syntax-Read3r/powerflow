$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
}

# ==============================================================================
# `storage root` -- eligibility classification and the straggler view.
#
# Executed rather than asserted about: the real Get-PFStorageCandidate runs against a
# faked adapter contract, which is the technique COMPONENTS.md records for pmx.
#
# THE REGRESSION THIS EXISTS FOR: Windows reports a USB-attached external disk as
# DriveType='Fixed'. A check based on IsSystem alone therefore offers a drive you can
# unplug as somewhere to keep a development tree -- measured on a real WD My Passport
# showing 481 GB free. Eligibility must come from the DISK's bus, not the volume type.
# ==============================================================================

$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('pf-root-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$writable   = Join-Path $sandbox 'writable'
$unwritable = Join-Path $sandbox 'unwritable'
New-Item -ItemType Directory -Path $writable -Force | Out-Null

function Register-PFCommand {
    param([string]$Name, [string]$Synopsis, [string]$Section, [string]$Example,
          [string[]]$Aliases, [string]$Platform)
}
$script:PowerFlowOS = 'windows'

# educate.ps1 is SOURCED, not stubbed, for the reason storage-behaviour.ps1 records:
# storage.ps1 registers its --educate topics at LOAD time, so a stub would let a malformed
# topic pass a test the real runtime would reject. This file adds a topic, so that matters.
. (Join-Path $repo 'components/shared/educate.ps1')

# The adapter contract, faked. Defined before the component so nothing reaches a real disk.
$script:Volumes    = @()
$script:Disks      = @()
$script:Stragglers = @()
function Get-StorageVolume    { return @($script:Volumes) }
function Get-DiskInfo         { return @($script:Disks) }
function Get-StorageStraggler { return @($script:Stragglers) }

. (Join-Path $repo 'components/shared/volumes.ps1')
. (Join-Path $repo 'components/system/storage.ps1')

try {
    # ---- the write probe is a probe, not arithmetic ---------------------------
    Assert-True (Test-PFPathWritable -Path $writable) 'a writable directory probes writable'
    Assert-True (-not (Test-PFPathWritable -Path $unwritable)) 'a path that does not exist is not writable'
    Assert-True (@(Get-ChildItem $writable -Force).Count -eq 0) 'the probe leaves nothing behind'

    # ---- classification -------------------------------------------------------
    $script:Volumes = @(
        [pscustomobject]@{ Name = 'C:'; Root = $writable; Label = 'OS';          SizeBytes = 900GB; FreeBytes = 100GB; IsSystem = $true }
        [pscustomobject]@{ Name = 'D:'; Root = $writable; Label = 'Data';        SizeBytes = 900GB; FreeBytes = 800GB; IsSystem = $false }
        [pscustomobject]@{ Name = 'E:'; Root = $writable; Label = 'My Passport'; SizeBytes = 1.8TB; FreeBytes = 481GB; IsSystem = $false }
        [pscustomobject]@{ Name = 'Z:'; Root = $unwritable; Label = 'Gone';      SizeBytes = 100GB; FreeBytes = 50GB;  IsSystem = $false }
    )
    # E: is on disk 2, which is USB. Letters is SPACE-JOINED on both platforms.
    $script:Disks = @(
        [pscustomobject]@{ Id = 0; External = $false; Letters = 'C: D:' }
        [pscustomobject]@{ Id = 2; External = $true;  Letters = 'E:' }
    )

    $c = @(Get-PFStorageCandidate)
    $by = @{}; foreach ($row in $c) { $by[$row.Name] = $row }

    Assert-True ($by['D:'].Eligible) 'an internal, writable, non-system volume is eligible'
    Assert-True ($by['D:'].Reason -eq '') 'an eligible volume carries no reason'

    Assert-True (-not $by['C:'].Eligible) 'the system volume is not eligible'
    Assert-True ($by['C:'].Reason -match 'system volume') 'and says so'

    # THE REGRESSION. DriveType said nothing; the bus did.
    Assert-True (-not $by['E:'].Eligible) 'a volume on a USB disk is not eligible despite ample free space'
    Assert-True ($by['E:'].Reason -match 'removable disk') 'and names the reason as removable'
    Assert-True ($by['E:'].External) 'the external flag comes from the disk, not the volume'

    Assert-True (-not $by['Z:'].Eligible) 'a volume that cannot be written to is not eligible'
    Assert-True ($by['Z:'].Reason -match 'not writable') 'and says so'

    # Nothing is hidden: a rejected volume still appears, because a drive missing from a
    # list is a puzzle while a drive labelled "removable disk" is an answer.
    Assert-True ($c.Count -eq 4) 'every volume is reported, including the rejected ones'
    Assert-True ($c[0].Name -eq 'D:') 'the eligible volume sorts first'

    # Reasons accumulate rather than reporting only the first failure.
    $script:Disks = @([pscustomobject]@{ Id = 0; External = $true; Letters = 'C: D: E: Z:' })
    $multi = @(Get-PFStorageCandidate) | Where-Object { $_.Name -eq 'C:' }
    Assert-True ($multi.Reason -match 'system volume' -and $multi.Reason -match 'removable disk') 'multiple disqualifications are all reported'

    # ---- the straggler view ---------------------------------------------------
    # Restore the realistic disk table: the rendered output is asserted below to still
    # carry the removable verdict, so the fixture has to keep a removable disk in it.
    $script:Disks = @(
        [pscustomobject]@{ Id = 0; External = $false; Letters = 'C: D:' }
        [pscustomobject]@{ Id = 2; External = $true;  Letters = 'E:' }
    )
    $script:Stragglers = @(
        [pscustomobject]@{ Name = 'npm cache';  Path = 'C:\u\.npm';    SizeBytes = 200MB; Variable = 'NPM_CONFIG_CACHE'; Redirect = ''; Redirected = $false }
        [pscustomobject]@{ Name = 'Maven';      Path = 'C:\u\.m2';     SizeBytes = 50MB;  Variable = '';                 Redirect = ''; Redirected = $false }
        [pscustomobject]@{ Name = 'VS Code';    Path = 'C:\u\.vscode'; SizeBytes = 1.2GB; Variable = '';                 Redirect = ''; Redirected = $true  }
    )
    $out = (Show-StorageRoot 6>&1 | Out-String)

    Assert-True ($out -match 'npm cache')  'an unmoved directory is listed'
    Assert-True ($out -match 'NPM_CONFIG_CACHE') 'the variable that would move it is named'
    # A tool with no variable cannot be moved by setting one, and saying "needs a link"
    # is the difference between a report and a to-do nobody can action.
    Assert-True ($out -match 'needs a link') 'a directory with no variable says what it would take instead'

    # ALREADY-REDIRECTED IS NOT A FINDING. A junctioned path still exists on the system
    # drive and still measures the same size through the link, so a naive scan reports
    # finished work as outstanding.
    Assert-True ($out -match 'ALREADY REDIRECTED') 'redirected paths get their own section'
    $unmovedBlock = ($out -split 'ALREADY REDIRECTED')[0]
    Assert-True ($unmovedBlock -notmatch 'VS Code') 'a redirected path is not counted as still on the system drive'

    Assert-True ($out -match 'removable disk') 'the volume table reaches the rendered output'
    Assert-True ($out -match 'moves nothing') 'the view states that it is read-only'
}
finally {
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'OK - storage root classifies by disk bus, probes writability, and separates finished work.'
