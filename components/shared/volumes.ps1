# ==============================================================================
# PowerFlow — Volume Eligibility
# ==============================================================================
# Domain   : Shared
# File     : components/shared/volumes.ps1
# Purpose  : Which volumes could hold things that grow, and why the others could not
# Functions: Test-PFPathWritable, Get-PFStorageCandidate
# Depends  : adapters Get-StorageVolume, Get-DiskInfo
# ==============================================================================
#
# WHY THIS IS SHARED RATHER THAN LIVING WITH `storage`
#
# Two commands ask the same question. `storage root` asks it about volumes, to report
# where what grows could live. `nav setup` asks it about directories, to avoid offering a
# code root on a disk that can be unplugged. Both had their own copy of the answer, and
# two copies of a rule about hardware is exactly the drift this repository has been bitten
# by before — a hand-maintained list that fell five names behind the real one.
#
# It cannot live in `components/system/storage.ps1`, because the bootloader loads
# `navigation` BEFORE `system`. Function bodies resolve at call time so it would have
# worked, but a dependency that runs backwards through the load order is a trap for whoever
# next reorders it. `shared/` loads before both, which makes the direction honest.
#
# WHY IT IS NOT AN ADAPTER
#
# Every part of it is composed of adapter answers — Get-StorageVolume for the volumes,
# Get-DiskInfo for the bus, a write probe for permission. Nothing here touches an OS API,
# so by the architecture rule it belongs in components/. Only the per-OS knowledge of
# WHERE tools park their data (Get-StorageStraggler) needed an adapter.
# ==============================================================================

<#
.SYNOPSIS
    Can PowerFlow actually create files here? Probed, never inferred.
.DESCRIPTION
    A create-and-delete probe rather than mode-bit or ACL arithmetic. On Linux a mount can
    be read-only, or root-owned with no user write access; on Windows a volume can carry an
    ACL that no attribute reflects. In both cases the permission bits can look perfectly
    fine while a write fails, so the only honest test is to try it.
#>
function Test-PFPathWritable {
    param([Parameter(Mandatory)][string]$Path)

    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $false }
    $probe = Join-Path $Path ('.pf-write-probe-' + [System.IO.Path]::GetRandomFileName())
    try {
        New-Item -ItemType File -Path $probe -Force -ErrorAction Stop | Out-Null
        return $true
    }
    catch { return $false }
    finally { if (Test-Path -LiteralPath $probe) { Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue } }
}

<#
.SYNOPSIS
    Every volume, annotated with whether it could hold what grows — and why not.
.DESCRIPTION
    DRIVE TYPE IS NOT A SAFETY SIGNAL. Windows reports a USB-attached external disk as
    DriveType='Fixed'. Measured on a real WD My Passport: 481 GB free, IsSystem false —
    indistinguishable from an ideal second drive to any check based on IsSystem alone.

    The bus lives on the DISK, not the volume, so eligibility takes a join against
    Get-DiskInfo. Its Letters field is space-joined and holds drive letters on Windows and
    mount points on Linux, which is why one join serves both platforms.

    Nothing is hidden. A rejected volume still comes back, carrying the REASON it failed,
    because a drive silently missing from a list is a puzzle while a drive labelled
    "removable disk" is an answer.
#>
function Get-PFStorageCandidate {
    $external = @{}
    try {
        foreach ($disk in @(Get-DiskInfo)) {
            if (-not $disk.External) { continue }
            foreach ($letter in @("$($disk.Letters)" -split '\s+' | Where-Object { $_ })) {
                $external[$letter.ToLowerInvariant()] = $true
            }
        }
    } catch { }

    $out = @()
    foreach ($volume in @(Get-StorageVolume)) {
        $isExternal = [bool]($external["$($volume.Name)".ToLowerInvariant()] -or
                             $external["$($volume.Root)".TrimEnd('\', '/').ToLowerInvariant()])
        $writable = Test-PFPathWritable -Path $volume.Root

        $why = @()
        if ($volume.IsSystem) { $why += 'system volume' }
        if ($isExternal)      { $why += 'removable disk' }
        if (-not $writable)   { $why += 'not writable' }

        $out += [pscustomobject]@{
            Name      = $volume.Name
            Root      = $volume.Root
            Label     = "$($volume.Label)"
            SizeBytes = [int64]$volume.SizeBytes
            FreeBytes = [int64]$volume.FreeBytes
            IsSystem  = [bool]$volume.IsSystem
            External  = $isExternal
            Writable  = $writable
            Eligible  = (-not $volume.IsSystem -and -not $isExternal -and $writable)
            Reason    = ($why -join ', ')
        }
    }
    return @($out | Sort-Object -Property @{ Expression = 'Eligible'; Descending = $true },
                                           @{ Expression = 'FreeBytes'; Descending = $true })
}
