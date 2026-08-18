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
    # Unary comma keeps PowerShell from enumerating a one-item array into a scalar string.
    # Nested routers index token zero, so returning "set" as a scalar would make [0] be 's'.
    if ($null -eq $Arguments -or $Arguments.Count -le $Start) { return ,@() }
    return ,@($Arguments[$Start..($Arguments.Count - 1)])
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

            # `--full`, `--write`, `--destroy` are the canonical spellings: these are words, and
            # a word takes two dashes (docs/plan/ethos/ETHOS.md). The allow-list is kept in the
            # single-dash form because that is the key the switches below test, so a canonical
            # token is normalised down to it. The single-dash word still binds and says once
            # where it moved.
            if ($lower.StartsWith('--', [StringComparison]::Ordinal)) {
                $lower = $lower.Substring(1)
            }
            elseif ($lower.Length -gt 3) {
                Write-PFFlagDeprecation -Command 'pmx disk' -Old $lower -New "-$lower"
            }

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
    $resolvedDisk = Resolve-PmxDisk -Selector $selector -Interactive
    if (-not $resolvedDisk.Success) {
        # Escaping the picker ends the command quietly. Only the no-picker case falls
        # through to the list — re-printing it after the user closed a picker of the same
        # rows is noise, and reads as though the Escape did not register.
        if ($resolvedDisk.Cancelled) { Write-PmxResolveFailure -Resolved $resolvedDisk; return }
        if ($resolvedDisk.Error) { Write-PmxResolveFailure -Resolved $resolvedDisk; return }
        if (-not $selector) { Show-PmxDisks }
        return
    }
    $disk = $resolvedDisk.Disk

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

# Accepts every reasonable spelling of a single-value VM setting and normalises it to the
# canonical `<vm> --<option> <value>` form the setter already understands:
#
#   pmx vm memory 101 8G                 short — what people type
#   pmx vm memory set 101 8G             with the optional `set`
#   pmx vm memory set 101 --size 8G      the original long form (unchanged)
#   pmx vm memory 101 --size 8G          any mixture
#
# Flags such as --dry-run pass through untouched wherever they appear.
function Invoke-PmxVmScalarSet {
    param(
        [object[]]$Rest = @(),
        [Parameter(Mandatory)][string]$Option,
        [Parameter(Mandatory)][string]$Setter,
        [Parameter(Mandatory)][string]$Usage
    )

    $tokens = @($Rest | ForEach-Object { "$_" })
    if ($tokens.Count -and $tokens[0].ToLowerInvariant() -eq 'set') {
        $tokens = @($tokens | Select-Object -Skip 1)
    }
    # NOTE: no early return on an empty tail. The router's job is to ROUTE — the setter owns
    # its own argument validation and error text, and a routing test asserts the handler is
    # reached even with no arguments. Returning here silently broke that contract.

    # Split the leading positionals from anything flag-shaped, so --dry-run et al survive.
    $positional = @(); $passthrough = @(); $seenFlag = $false
    for ($i = 0; $i -lt $tokens.Count; $i++) {
        if ($tokens[$i] -like '-*') { $seenFlag = $true }
        if ($seenFlag) { $passthrough += $tokens[$i] } else { $positional += $tokens[$i] }
    }

    # <vm> <value> — promote the bare value to its flag. If the value was already supplied as
    # a flag, $positional holds only the VM and there is nothing to promote.
    if ($positional.Count -ge 2) {
        $argv = @($positional[0], "--$Option", $positional[1]) + @($positional | Select-Object -Skip 2) + $passthrough
    } else {
        $argv = @($positional) + $passthrough
    }
    & $Setter -Arguments $argv
}

function Invoke-PmxVmCommand {
    param([object[]]$Arguments = @())

    $action = if ($Arguments.Count) { "$($Arguments[0])".ToLowerInvariant() } else { 'list' }
    $rest = Get-PmxCommandTail -Arguments $Arguments -Start 1
    switch ($action) {
        'list'       { Show-PmxManagedVmList -Arguments $rest }
        'show'       { Show-PmxManagedVm -Arguments $rest }
        # `qm config <vmid>` is native muscle memory, so `pmx vm config` opens the same view.
        # `show` remains canonical internally — this is another door, not a second room.
        'config'     { Show-PmxManagedVm -Arguments $rest }
        # `pmx vm disks [vm]` — the operator workflow is "show VMs, choose one, show its disks",
        # and this is the third step. `pmx disk list --vm <id>` remains the canonical script
        # form; both reach the same function, so there is no second implementation to drift.
        # A bare `pmx vm disks` inherits the VM picker, because an unspecified VM already means
        # "ask me" everywhere else.
        'disks'      { Show-PmxManagedVmDisks -Arguments $rest }
        'disk'       { Show-PmxManagedVmDisks -Arguments $rest }
        'status'     { Show-PmxManagedVm -Arguments $rest -StatusOnly }
        'next-id'    { Show-PmxNextVmId -Arguments $rest }
        'network'    { Invoke-PmxVmNetworkCommand -Arguments $rest }
        'net'        { Invoke-PmxVmNetworkCommand -Arguments $rest }
        'nic'        { Show-PmxVmNetwork -Arguments $rest -View adapters }
        'ip'         { Show-PmxVmNetwork -Arguments $rest -View addresses }
        'clone'      { Invoke-PmxVmClone -Arguments $rest }
        'start'      { Invoke-PmxVmStart -Arguments $rest }
        'shutdown'   { Invoke-PmxVmShutdown -Arguments $rest }
        'set-cpu'    { Invoke-PmxVmCpuSet -Arguments $rest }
        'set-memory' { Invoke-PmxVmMemorySet -Arguments $rest }
        # `set` is OPTIONAL, and the value may be positional. `pmx disk grow 101 50G` already
        # reads this way, so `pmx vm memory set 101 --size 8G` was the odd one out — same kind
        # of operation, twice the ceremony. Both spellings work; the long form is untouched.
        'cpu'    { Invoke-PmxVmScalarSet -Rest $rest -Option 'cores' -Setter 'Invoke-PmxVmCpuSet'    -Usage 'pmx vm cpu <vm> <cores>' }
        'memory' { Invoke-PmxVmScalarSet -Rest $rest -Option 'size'  -Setter 'Invoke-PmxVmMemorySet' -Usage 'pmx vm memory <vm> <size>' }
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

    # `--help` ANYWHERE means "explain this command", never "run it". Previously it was
    # honoured only at token zero, so `pmx vm show --help` fell through to the command, whose
    # own help check sits BELOW its parse-failure gate (vm-read.ps1) — meaning asking for help
    # failed arity validation first and answered "❌ supply one VM name or VMID after the
    # action". Nine to ten advertised paths behaved that way, each with a different unrelated
    # error. Hoisting it here makes `pmx vm show --help` ≡ `pmx help vm show` for every path,
    # including ones with no per-function scan at all (`pmx disks --help`, `pmx vm --help`).
    # Only literal help tokens trigger this; -Full/-Write/-Destroy are untouched.
    if (@($argv | Where-Object { "$_".ToLowerInvariant() -in @('--help', '-h', '/?') }).Count) {
        $topic = @($argv | Where-Object { -not "$_".StartsWith('-', [StringComparison]::Ordinal) -and "$_" -ne '/?' })
        Show-PmxHelp -TopicParts $topic
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
        # Top-level lifecycle shortcuts. `pmx vm start` remains canonical; these forward into
        # the identical guarded mutation path, so a shortcut never means a weaker safety chain.
        # Deliberately only start/shutdown: those are the two that get typed reflexively, and
        # every additional top-level word narrows the namespace for future groups.
        'start'    { Invoke-PmxVmStart -Arguments $tail }
        'shutdown' { Invoke-PmxVmShutdown -Arguments $tail }
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

# ONE entry, not eleven. The ten sub-route registrations (pmx config / discover / vm / disk /
# snapshot / vm network / …) were listed in pwsh-h on EVERY machine, including boxes with no
# Proxmox at all — where each one answers "not connected". That is a menu of things that error.
# `pmx help` already owns the full 31-topic catalogue and works everywhere (it is reachable
# before the Proxmox gate), so pwsh-h names the family once and hands off. pwsh-h is a command
# reference, not a mirror of every route.
Register-PFCommand -Name 'pmx' -Section '⚡ PROXMOX VE' -Platform 'Both' -Synopsis 'Proxmox host, disk, VM and snapshot workflows — pmx help lists them all' -Example 'pmx help · pmx vm list · pmx vm ip <name>'
