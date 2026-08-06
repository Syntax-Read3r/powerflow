# ==============================================================================
# PowerFlow — Proxmox Command Router
# ==============================================================================
# Domain   : Proxmox
# File     : components/proxmox/command.ps1
# Purpose  : Thin, collision-aware pmx command router and help registration
# Functions: Get-PmxCommandTail, Invoke-PmxLegacyDiskCommand,
#            Invoke-PmxVmCommand, Invoke-PmxSnapshotCommand, pmx
# Depends  : all ordered components/proxmox modules, components/help/registry.ps1
# ==============================================================================

function Get-PmxCommandTail {
    param([object[]]$Arguments, [int]$Start)
    if ($null -eq $Arguments -or $Arguments.Count -le $Start) { return @() }
    return @($Arguments[$Start..($Arguments.Count - 1)])
}

function Invoke-PmxLegacyDiskCommand {
    param([object[]]$Arguments = @())

    $allowedFlags = @('-full', '-write', '-destroy')
    $positionals = @()
    $flags = @{}
    foreach ($argument in @($Arguments)) {
        $token = "$argument"
        if ($token.StartsWith('-', [StringComparison]::Ordinal)) {
            $lower = $token.ToLowerInvariant()
            if ($lower -notin $allowedFlags) {
                Write-Host "❌ Unknown physical-disk option '$token'. Run: pmx help" -ForegroundColor Red
                return
            }
            if ($flags.ContainsKey($lower)) {
                Write-Host "❌ Option '$token' was supplied more than once." -ForegroundColor Red
                return
            }
            $flags[$lower] = $true
        }
        else { $positionals += $token }
    }
    if ($positionals.Count -gt 3) {
        Write-Host '❌ Too many physical-disk arguments. Run: pmx help' -ForegroundColor Red
        return
    }

    $selector = if ($positionals.Count -ge 1) { $positionals[0] } else { '' }
    $action = if ($positionals.Count -ge 2) { $positionals[1].ToLowerInvariant() } else { '' }
    $option = if ($positionals.Count -ge 3) { $positionals[2] } else { '' }
    if (-not (Test-PmxReady)) { return }
    $disk = Resolve-PmxDisk -Selector $selector -Interactive
    if (-not $disk) {
        if (-not $selector) { Show-PmxDisks }
        return
    }

    switch ($action) {
        ''              { Show-PmxDisk -Disk $disk -Full:$flags.ContainsKey('-full') }
        'smart'         { Show-PmxDisk -Disk $disk -Full:$flags.ContainsKey('-full') }
        'test'          { Invoke-PmxSmartTest -Disk $disk -Kind $option }
        'report'        { Show-PmxEvidence -Disk $disk -Write:$flags.ContainsKey('-write') }
        'evidence'      { Show-PmxEvidence -Disk $disk -Write:$flags.ContainsKey('-write') }
        'capacity-test' { Invoke-PmxCapacityTest -Disk $disk -Destroy:$flags.ContainsKey('-destroy') }
        default         { Write-Host "❌ Unknown physical-disk action '$action'. Run: pmx help" -ForegroundColor Red }
    }
}

function Invoke-PmxVmCommand {
    param([object[]]$Arguments = @())

    $action = if ($Arguments.Count) { "$($Arguments[0])".ToLowerInvariant() } else { 'list' }
    $rest = Get-PmxCommandTail -Arguments $Arguments -Start 1
    switch ($action) {
        'list'       { Show-PmxManagedVmList -Arguments $rest }
        'show'       { Show-PmxManagedVm -Arguments $rest }
        'status'     { Show-PmxManagedVm -Arguments $rest -StatusOnly }
        'next-id'    { Show-PmxNextVmId -Arguments $rest }
        'clone'      { Invoke-PmxVmClone -Arguments $rest }
        'start'      { Invoke-PmxVmStart -Arguments $rest }
        'shutdown'   { Invoke-PmxVmShutdown -Arguments $rest }
        'set-cpu'    { Invoke-PmxVmCpuSet -Arguments $rest }
        'set-memory' { Invoke-PmxVmMemorySet -Arguments $rest }
        'cpu' {
            $subaction = if ($rest.Count) { "$($rest[0])".ToLowerInvariant() } else { '' }
            if ($subaction -ne 'set') {
                Write-Host '❌ Use: pmx vm cpu set --vm <vm> --cores <number>' -ForegroundColor Red
                return
            }
            Invoke-PmxVmCpuSet -Arguments (Get-PmxCommandTail -Arguments $rest -Start 1)
        }
        'memory' {
            $subaction = if ($rest.Count) { "$($rest[0])".ToLowerInvariant() } else { '' }
            if ($subaction -ne 'set') {
                Write-Host '❌ Use: pmx vm memory set --vm <vm> --size <size>' -ForegroundColor Red
                return
            }
            Invoke-PmxVmMemorySet -Arguments (Get-PmxCommandTail -Arguments $rest -Start 1)
        }
        default { Write-Host "❌ Unknown VM action '$action'. Run: pmx help" -ForegroundColor Red }
    }
}

function Invoke-PmxSnapshotCommand {
    param([object[]]$Arguments = @())

    $action = if ($Arguments.Count) { "$($Arguments[0])".ToLowerInvariant() } else { 'list' }
    $rest = Get-PmxCommandTail -Arguments $Arguments -Start 1
    switch ($action) {
        'list'   { Show-PmxSnapshots -Arguments $rest }
        'create' { Invoke-PmxSnapshotCreate -Arguments $rest }
        default  { Write-Host "❌ Unknown snapshot action '$action'. Run: pmx help snapshot list" -ForegroundColor Red }
    }
}

<#
.SYNOPSIS
    Safe, educational Proxmox VE host and VM management.
.DESCRIPTION
    Existing host/disk inspection remains local to Proxmox. VM management resolves a saved
    srv target or local node, maps only documented actions to pvesh/qm, and places changes
    behind preview, confirmation, revalidation, and postcondition checks.
#>
function pmx {
    $argv = @($args | ForEach-Object { "$_" })
    if (-not $argv.Count) {
        if (Test-ProxmoxSupport) { Show-PmxDashboard } else { Show-PmxManagedNodeStatus }
        return
    }
    if ($argv[0] -match '[\x00-\x1F\x7F\u00AD\u200B-\u200D\u2060\uFEFF]') {
        Write-Host '❌ PMX command names may not contain control or invisible format characters.' -ForegroundColor Red
        return
    }

    $group = $argv[0].ToLowerInvariant()
    $tail = Get-PmxCommandTail -Arguments $argv -Start 1
    if ($group -in @('help', '-h', '--help', '/?')) {
        Show-PmxHelp -TopicParts $tail
        return
    }

    switch ($group) {
        'config'   { Invoke-PmxConfigCommand -Arguments $tail }
        'discover' { Show-PmxDiscovery -Arguments $tail }
        'node' {
            $action = if ($tail.Count) { "$($tail[0])".ToLowerInvariant() } else { 'status' }
            if ($action -ne 'status') {
                Write-Host "❌ Unknown node action '$action'. Use: pmx node status" -ForegroundColor Red
                return
            }
            Show-PmxManagedNodeStatus -Arguments (Get-PmxCommandTail -Arguments $tail -Start 1)
        }
        'storage' {
            if (-not $tail.Count -and (Test-ProxmoxSupport)) {
                Show-PmxPools
                return
            }
            $action = if ($tail.Count) { "$($tail[0])".ToLowerInvariant() } else { 'list' }
            if ($action -ne 'list') {
                Write-Host "❌ Unknown storage action '$action'. Use: pmx storage list" -ForegroundColor Red
                return
            }
            Show-PmxManagedStorage -Arguments (Get-PmxCommandTail -Arguments $tail -Start 1)
        }
        'vm'       { Invoke-PmxVmCommand -Arguments $tail }
        'snapshot' { Invoke-PmxSnapshotCommand -Arguments $tail }
        'disk' {
            $action = if ($tail.Count) { "$($tail[0])".ToLowerInvariant() } else { '' }
            if ($action -eq 'list') {
                Show-PmxManagedVmDisks -Arguments (Get-PmxCommandTail -Arguments $tail -Start 1)
                return
            }
            if ($action -eq 'grow') {
                Invoke-PmxVmDiskGrow -Arguments (Get-PmxCommandTail -Arguments $tail -Start 1)
                return
            }
            Invoke-PmxLegacyDiskCommand -Arguments $tail
        }
        'disks' {
            if ($tail.Count) { Write-Host '❌ pmx disks takes no arguments.' -ForegroundColor Red; return }
            if (Test-PmxReady) { Show-PmxDisks }
        }
        'pools' {
            if ($tail.Count) { Write-Host '❌ pmx pools takes no arguments.' -ForegroundColor Red; return }
            if (Test-PmxReady) { Show-PmxPools }
        }
        'guests' {
            if ($tail.Count) { Write-Host '❌ pmx guests takes no arguments.' -ForegroundColor Red; return }
            if (Test-PmxReady) { Show-PmxGuests }
        }
        'guest' {
            if ($tail.Count -gt 1) { Write-Host '❌ Use: pmx guest [id|name]' -ForegroundColor Red; return }
            if (Test-PmxReady) {
                if ($tail.Count) { Show-PmxGuests -Selector $tail[0] } else { Show-PmxGuests }
            }
        }
        'updates' {
            if ($tail.Count) { Write-Host '❌ pmx updates takes no arguments.' -ForegroundColor Red; return }
            if (Test-PmxReady) { Show-PmxUpdates }
        }
        default { Write-Host "❌ Unknown pmx command '$group'. Run: pmx help" -ForegroundColor Red }
    }
}

Register-PFCommand -Name 'pmx' -Section '⚡ PROXMOX VE' -Platform 'Both' -Synopsis 'safe Proxmox host, disk, VM and snapshot workflows' -Example 'pmx help · pmx discover · pmx vm list'
Register-PFCommand -Name 'pmx config' -Section '⚡ PROXMOX VE' -Platform 'Both' -Synopsis 'configure and validate a local or saved SSH target' -Example 'pmx config show'
Register-PFCommand -Name 'pmx discover' -Section '⚡ PROXMOX VE' -Platform 'Both' -Synopsis 'discover nodes, storage, bridges, VMIDs and templates'
Register-PFCommand -Name 'pmx vm' -Section '⚡ PROXMOX VE' -Platform 'Both' -Synopsis 'inspect, clone, size, start and shut down QEMU VMs' -Example 'pmx vm list'
Register-PFCommand -Name 'pmx disk' -Section '⚡ PROXMOX VE' -Platform 'Both' -Synopsis 'inspect physical disks locally or manage one VM disk' -Example 'pmx disk list --vm 102'
Register-PFCommand -Name 'pmx snapshot' -Section '⚡ PROXMOX VE' -Platform 'Both' -Synopsis 'list or create guarded VM snapshots' -Example 'pmx snapshot list --vm 102'
