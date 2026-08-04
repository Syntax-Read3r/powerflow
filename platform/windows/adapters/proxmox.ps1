# ==============================================================================
# PowerFlow — Proxmox Adapter (Windows)
# ==============================================================================
# Domain   : Platform / Windows
# File     : platform/windows/adapters/proxmox.ps1
# Purpose  : Safe unsupported implementation of the Proxmox adapter contract
# Functions: Test-ProxmoxSupport, Get-ProxmoxNodeSummary, Get-ProxmoxDisks,
#            Get-ProxmoxStorage, Get-ProxmoxZfsPools, Get-ProxmoxGuests,
#            Get-ProxmoxUpdates, Get-ProxmoxSmartInfo, Get-ProxmoxSmartReport,
#            Start-ProxmoxSmartTest, Get-ProxmoxDiskSafety,
#            Invoke-ProxmoxCapacityProbe
# Depends  : none
# ==============================================================================

function Test-ProxmoxSupport { return $false }
function Get-ProxmoxNodeSummary { return $null }
function Get-ProxmoxDisks { return @() }
function Get-ProxmoxStorage { return @() }
function Get-ProxmoxZfsPools { return @() }
function Get-ProxmoxGuests { return @() }
function Get-ProxmoxUpdates { return @() }

function Get-ProxmoxSmartInfo {
    param([string]$DevicePath)
    return [pscustomobject]@{ Available = $false; Error = 'Proxmox disk inspection is Linux-only.' }
}

function Get-ProxmoxSmartReport {
    param([string]$DevicePath)
    return @('Proxmox disk inspection is Linux-only.')
}

function Start-ProxmoxSmartTest {
    param([string]$DevicePath, [ValidateSet('short', 'long')][string]$Kind)
    return [pscustomobject]@{ Success = $false; Message = 'Proxmox SMART tests are Linux-only.'; Output = @() }
}

function Get-ProxmoxDiskSafety {
    param([string]$StablePath)
    return [pscustomobject]@{
        Safe    = $false
        Disk    = $null
        Reasons = @('Proxmox capacity testing is Linux-only.')
    }
}

function Get-ProxmoxDiskEvidence {
    param($Disk, [int]$KernelHours = 24)
    return $null
}

function Invoke-ProxmoxCapacityProbe {
    param(
        [string]$StablePath,
        [string]$ExpectedSerial,
        [long]$ExpectedSizeBytes,
        [string]$ExpectedMajorMinor,
        [string]$ExpectedDiskSeq,
        [string]$ExpectedWwn,
        [string]$Confirmation
    )
    return [pscustomobject]@{ Success = $false; Message = 'Proxmox capacity testing is Linux-only.' }
}
