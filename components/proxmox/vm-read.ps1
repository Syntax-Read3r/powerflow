# ==============================================================================
# PowerFlow — Proxmox VM Queries
# ==============================================================================
# Domain   : Proxmox
# File     : components/proxmox/vm-read.ps1
# Purpose  : Resolve and render virtual machines, status, next IDs, and VM disks
# Functions: Get-PmxManagedVmRows, Resolve-PmxManagedVm,
#            Get-PmxManagedVmDetails,
#            Show-PmxManagedVmList, Show-PmxManagedVm,
#            Show-PmxNextVmId, Show-PmxManagedVmDisks
# Depends  : shared.ps1, disk-model.ps1, config.ps1, Proxmox management adapter
# ==============================================================================

function Get-PmxManagedVmRows {
    param([Parameter(Mandatory)]$Session)

    $result = Invoke-ProxmoxManagementQuery -Operation 'vm-list' -Connection $Session.Connection
    if (-not $result.Success) {
        return [pscustomobject]@{ Success = $false; Vms = @(); Error = $result.Error; Result = $result }
    }
    $rows = @($result.Data | Where-Object { "$($_.type)" -eq 'qemu' } | ForEach-Object {
        [pscustomobject]@{
            VmId        = [int](Get-PmxObjectProperty $_ 'vmid' 0)
            Name        = ConvertTo-PmxDisplayText (Get-PmxObjectProperty $_ 'name' '')
            Node        = ConvertTo-PmxDisplayText (Get-PmxObjectProperty $_ 'node' '')
            Status      = ConvertTo-PmxDisplayText (Get-PmxObjectProperty $_ 'status' 'unknown')
            Template    = ((Get-PmxObjectProperty $_ 'template' 0) -eq 1 -or (Get-PmxObjectProperty $_ 'template' $false) -eq $true)
            CpuUsage    = [double](Get-PmxObjectProperty $_ 'cpu' 0.0)
            CpuCount    = [int](Get-PmxObjectProperty $_ 'maxcpu' 0)
            MemoryBytes = [long](Get-PmxObjectProperty $_ 'mem' 0)
            MaxMemory   = [long](Get-PmxObjectProperty $_ 'maxmem' 0)
            DiskBytes   = [long](Get-PmxObjectProperty $_ 'disk' 0)
            MaxDisk     = [long](Get-PmxObjectProperty $_ 'maxdisk' 0)
            Uptime      = [long](Get-PmxObjectProperty $_ 'uptime' 0)
        }
    } | Sort-Object VmId)
    return [pscustomobject]@{ Success = $true; Vms = $rows; Error = ''; Result = $result }
}

function Resolve-PmxManagedVm {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Selector,
        [Parameter(Mandatory)]$Session
    )

    if ($Selector -match '[\x00-\x1F\x7F\u00AD\u200B-\u200D\u2060\uFEFF]') {
        return [pscustomobject]@{ Success = $false; Vm = $null; Error = 'VM selector contains a control or invisible format character' }
    }
    $inventory = Get-PmxManagedVmRows -Session $Session
    if (-not $inventory.Success) {
        return [pscustomobject]@{ Success = $false; Vm = $null; Error = $inventory.Error }
    }

    # NO SELECTOR? PICK ONE. Thirteen VM-taking commands answered a missing name with a usage
    # line while a working fzf picker sat forty lines away, wired to physical disks only \u2014
    # `pmx disk` opens one, `pmx vm show` did not. Refusing where a picker would do is the
    # house anti-pattern (srv, start-folder and pc-whoami --ram all pick).
    #
    # Doing it HERE rather than per-command means every caller gains it at once, and the
    # safety path is untouched: whatever is picked still goes through the same validate \u2192
    # confirm \u2192 revalidate \u2192 verify chain, and Confirm-PmxAmberPlan already refuses
    # non-interactive sessions outright.
    if (-not $Selector) {
        if ([Console]::IsOutputRedirected -or -not (Get-Command fzf -ErrorAction SilentlyContinue)) {
            return [pscustomobject]@{ Success = $false; Vm = $null
                Error = 'name a VM, or run this in a terminal with fzf to pick one' }
        }
        $rows = @($inventory.Vms)
        if (-not $rows.Count) {
            return [pscustomobject]@{ Success = $false; Vm = $null; Error = 'this node has no VMs' }
        }
        $tab = [char]9
        $lines = $rows | ForEach-Object {
            $mark = if ($_.Template) { 'template' } else { "$($_.Status)" }
            '{0}{1}{2}{1}{3}{1}{4}' -f $_.VmId, $tab, (ConvertTo-PmxDisplayText $_.Name), $mark, $_.Node
        }
        $picked = $lines | fzf --height=60% --layout=reverse --border=rounded --delimiter="$tab" `
            --with-nth=1.. --prompt='\uD83D\uDDA5\uFE0F  VM: ' `
            --header="$($rows.Count) VMs \u00B7 type to filter \u00B7 Enter selects \u00B7 Esc cancels" --header-first
        if (-not $picked) { return [pscustomobject]@{ Success = $false; Vm = $null; Error = 'cancelled' } }
        $Selector = ("$picked" -split "$tab", 2)[0]
    }

    $hits = if (Test-PmxVmId $Selector) {
        @($inventory.Vms | Where-Object { "$($_.VmId)" -ceq "$Selector" })
    }
    else {
        @($inventory.Vms | Where-Object { [string]::Equals("$($_.Name)", $Selector, [StringComparison]::OrdinalIgnoreCase) })
    }

    if ($hits.Count -eq 1) {
        return [pscustomobject]@{ Success = $true; Vm = $hits[0]; Error = '' }
    }
    if ($hits.Count -gt 1) {
        return [pscustomobject]@{ Success = $false; Vm = $null; Error = "VM name '$Selector' is ambiguous; use a VMID" }
    }
    return [pscustomobject]@{ Success = $false; Vm = $null; Error = "VM '$Selector' was not found" }
}

function Get-PmxManagedVmDetails {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)]$Vm
    )

    $parameters = @{ Vmid = [int]$Vm.VmId; Node = "$($Vm.Node)" }
    # Diagnostics is carried through, not dropped. The adapter attaches scrubbed evidence to a
    # parse failure (PF-BUG-002), and re-wrapping the result without it is how "malformed JSON"
    # reached the user with nothing to act on. Losing it here is the same information leak the
    # response boundary suffers everywhere else — see PF-INVESTIGATE-001.
    $configResult = Invoke-ProxmoxManagementQuery -Operation 'vm-config' -Connection $Session.Connection -Parameters $parameters
    if (-not $configResult.Success) {
        return [pscustomobject]@{ Success = $false; Vm = $Vm; Config = $null; Status = $null; Disks = @()
            Error = $configResult.Error; Diagnostics = $configResult.Diagnostics }
    }
    $statusResult = Invoke-ProxmoxManagementQuery -Operation 'vm-status' -Connection $Session.Connection -Parameters $parameters
    if (-not $statusResult.Success) {
        return [pscustomobject]@{ Success = $false; Vm = $Vm; Config = $configResult.Data; Status = $null; Disks = @()
            Error = $statusResult.Error; Diagnostics = $statusResult.Diagnostics }
    }
    $disks = @(Get-PmxVirtualDisksFromConfig -Config $configResult.Data)
    return [pscustomobject]@{
        Success = $true
        Vm      = $Vm
        Config  = $configResult.Data
        Status  = $statusResult.Data
        Disks   = $disks
        Error   = ''
        Diagnostics = $null
    }
}


function Get-PmxReadInvocation {
    param(
        [object[]]$Arguments,
        [switch]$RequireSelector,
        [switch]$PositionalSelectorOnly
    )

    $valueOptions = if ($PositionalSelectorOnly) { @{} } else { @{ 'vm' = 'Vm' } }
    $parsed = ConvertFrom-PmxArguments -Arguments $Arguments -ValueOptions $valueOptions `
        -SwitchOptions (Get-PmxGlobalSwitchMap) -MinPositionals 0 -MaxPositionals $(if ($RequireSelector) { 1 } else { 0 })
    if (-not $parsed.Success) { return $parsed }
    if ($RequireSelector) {
        # A MISSING selector is no longer an error — it becomes an empty one, and
        # Resolve-PmxManagedVm opens a picker. Supplying BOTH forms is still an error,
        # because that is genuinely ambiguous rather than merely unspecified.
        if ($PositionalSelectorOnly) {
            if ($parsed.Positionals.Count -gt 1) {
                return [pscustomobject]@{ Success = $false; Options = $parsed.Options; Positionals = $parsed.Positionals; Error = 'name one VM, not several' }
            }
            $parsed.Options['Selector'] = if ($parsed.Positionals.Count -eq 1) { "$($parsed.Positionals[0])" } else { '' }
            return $parsed
        }
        $hasOption = $parsed.Options.ContainsKey('Vm')
        $hasPosition = $parsed.Positionals.Count -eq 1
        if ($hasOption -and $hasPosition) {
            return [pscustomobject]@{ Success = $false; Options = $parsed.Options; Positionals = $parsed.Positionals; Error = 'supply one VM as a positional value or with --vm, but not both' }
        }
        $parsed.Options['Selector'] = if ($hasOption) { "$($parsed.Options.Vm)" }
                                      elseif ($hasPosition) { "$($parsed.Positionals[0])" }
                                      else { '' }
    }
    return $parsed
}

function Show-PmxManagedVmList {
    param([object[]]$Arguments = @())

    $parsed = Get-PmxReadInvocation -Arguments $Arguments
    if (-not $parsed.Success) { Write-Host "❌ $($parsed.Error)" -ForegroundColor Red; return }
    if ($parsed.Options.Help) { Show-PmxTopicHelp 'vm list'; return }
    $session = Get-PmxManagementSession
    if (-not $session.Success) { Write-PmxDisconnectedState -Session $session; return }
    $inventory = Get-PmxManagedVmRows -Session $session
    if (-not $inventory.Success) { Write-Host "❌ $($inventory.Error)" -ForegroundColor Red; return }
    $mode = Get-PmxOutputMode -Options $parsed.Options -Config $session.Config
    if (-not $mode.Success) { Write-Host "❌ $($mode.Error)" -ForegroundColor Red; return }
    if ($mode.Mode -eq 'json') { Write-PmxJson $inventory.Vms; return }

    Write-Host ''
    Write-Host "🧱 PROXMOX VMS — $(@($inventory.Vms | Where-Object Status -eq 'running').Count) running of $($inventory.Vms.Count)" -ForegroundColor Cyan
    Write-Host '────────────────────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
    Write-Host ('  {0,-7} {1,-27} {2,-10} {3,-10} {4,6} {5,11}' -f 'VMID', 'NAME', 'NODE', 'STATUS', 'CPU', 'MEMORY') -ForegroundColor DarkGray
    foreach ($vm in $inventory.Vms) {
        $type = if ($vm.Template) { 'template' } else { $vm.Status }
        $color = if ($vm.Status -eq 'running') { 'White' } elseif ($vm.Template) { 'Cyan' } else { 'DarkGray' }
        Write-Host ('  {0,-7} {1,-27} {2,-10} {3,-10} {4,5} {5,11}' -f $vm.VmId,
            (ConvertTo-PmxDisplayText $vm.Name), (ConvertTo-PmxDisplayText $vm.Node), $type,
            $vm.CpuCount, (Format-PmxBytes $vm.MaxMemory)) -ForegroundColor $color
    }
    Write-Host ''
    # Every srv and pc-whoami view ends by naming what to do next; pmx views ended in silence,
    # leaving the user to go back to `pmx help` to find the obvious follow-up.
    Write-Host '  pmx vm show <name>  ·  pmx vm ip <name>  ·  pmx snapshot list <name>' -ForegroundColor DarkGray
    Write-Host ''
}

function Show-PmxManagedVm {
    param(
        # Same reason as Show-PmxManagedVmDisks below: `pmx vm show` with no VM arrives as an
        # empty tail, and the body already resolves an empty selector through the picker.
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Arguments,
        [switch]$StatusOnly
    )

    $parsed = Get-PmxReadInvocation -Arguments $Arguments -RequireSelector -PositionalSelectorOnly
    if (-not $parsed.Success) { Write-Host "❌ $($parsed.Error)" -ForegroundColor Red; return }
    if ($parsed.Options.Help) { Show-PmxTopicHelp $(if ($StatusOnly) { 'vm status' } else { 'vm show' }); return }
    $session = Get-PmxManagementSession
    if (-not $session.Success) { Write-PmxDisconnectedState -Session $session; return }
    $resolved = Resolve-PmxManagedVm -Selector $parsed.Options.Selector -Session $session
    if (-not $resolved.Success) { Write-Host "❌ $($resolved.Error)" -ForegroundColor Red; return }
    $details = Get-PmxManagedVmDetails -Session $session -Vm $resolved.Vm
    if (-not $details.Success) { Write-PmxQueryFailure -Message $details.Error -Diagnostics $details.Diagnostics -Options $parsed.Options; return }
    $mode = Get-PmxOutputMode -Options $parsed.Options -Config $session.Config
    if (-not $mode.Success) { Write-Host "❌ $($mode.Error)" -ForegroundColor Red; return }
    if ($mode.Mode -eq 'json') {
        if ($StatusOnly) { Write-PmxJson $details.Status } else { Write-PmxJson $details }
        return
    }

    $vm = $details.Vm
    $status = $details.Status
    Write-Host ''
    Write-Host "🧱 VM $($vm.VmId) — $((ConvertTo-PmxDisplayText $vm.Name))" -ForegroundColor Cyan
    Write-Host '──────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
    Write-PmxField 'Node' (ConvertTo-PmxDisplayText $vm.Node)
    Write-PmxField 'Status' (ConvertTo-PmxDisplayText (Get-PmxObjectProperty $status 'status' $vm.Status)) $(if ((Get-PmxObjectProperty $status 'status' $vm.Status) -eq 'running') { 'Green' } else { 'Yellow' })
    Write-PmxField 'Type' $(if ($vm.Template) { 'Template' } else { 'Virtual machine' })
    $cores = [int](Get-PmxObjectProperty $details.Config 'cores' $vm.CpuCount)
    $memoryMiB = [long](Get-PmxObjectProperty $details.Config 'memory' 0)
    Write-PmxField 'CPU' "$cores core(s)"
    Write-PmxField 'Memory' (Format-PmxBytes ($memoryMiB * 1MB))
    Write-PmxField 'Uptime' (Format-PmxUptime ([long](Get-PmxObjectProperty $status 'uptime' 0)))
    if (-not $StatusOnly) {
        Write-PmxField 'Template' $(if ($vm.Template) { 'yes' } else { 'no' })
        Write-PmxField 'Autostart' $(if ((Get-PmxObjectProperty $details.Config 'onboot' 0) -eq 1) { 'enabled' } else { 'disabled' })
        Write-PmxField 'Protection' $(if ((Get-PmxObjectProperty $details.Config 'protection' 0) -eq 1) { 'enabled' } else { 'disabled' })
        if ($details.Disks.Count) {
            Write-PmxField 'Disks' (@($details.Disks | ForEach-Object { "$($_.Disk) $($_.SizeDisplay)" }) -join ' · ')
        }
    }
    Write-Host ''
}

function Show-PmxNextVmId {
    param([object[]]$Arguments = @())

    $parsed = Get-PmxReadInvocation -Arguments $Arguments
    if (-not $parsed.Success) { Write-Host "❌ $($parsed.Error)" -ForegroundColor Red; return }
    if ($parsed.Options.Help) { Show-PmxTopicHelp 'vm next-id'; return }
    $session = Get-PmxManagementSession
    if (-not $session.Success) { Write-PmxDisconnectedState -Session $session; return }
    $result = Invoke-ProxmoxManagementQuery -Operation 'next-id' -Connection $session.Connection
    if (-not $result.Success -or -not (Test-PmxVmId $result.Data)) {
        $why = if ($result.Error) { $result.Error } else { 'Proxmox returned an invalid next VMID' }
        Write-Host "❌ $why" -ForegroundColor Red
        return
    }
    $mode = Get-PmxOutputMode -Options $parsed.Options -Config $session.Config
    if (-not $mode.Success) { Write-Host "❌ $($mode.Error)" -ForegroundColor Red; return }
    if ($mode.Mode -eq 'json') { Write-PmxJson ([pscustomobject]@{ vmid = [int]$result.Data }); return }
    Write-Host "Next available VMID: $($result.Data)" -ForegroundColor Green
}

function Show-PmxManagedVmDisks {
    # [AllowEmptyCollection()] is LOAD-BEARING. `pmx disk list` with no VM routes through
    # Get-PmxCommandTail, which deliberately returns ,@() when there is nothing after the
    # verb — and PowerShell rejects an empty array for a Mandatory [object[]] BEFORE the
    # body runs. The user saw a raw ParameterBindingException instead of a VM picker.
    #
    # The body below already does the right thing: Resolve-PmxManagedVm opens a picker on an
    # empty selector, and falls back to a clear "use --vm <name>" message when the terminal
    # is not interactive. So an unspecified VM was always meant to mean "ask me" — the
    # contract simply refused to let the body find out.
    #
    # Same defect as PF-BUG-005 in one dimension over: Mandatory rejecting a deliberately
    # empty value at a dispatch boundary.
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Arguments)

    $parsed = Get-PmxReadInvocation -Arguments $Arguments -RequireSelector
    if (-not $parsed.Success) { Write-Host "❌ $($parsed.Error)" -ForegroundColor Red; return }
    if ($parsed.Options.Help) { Show-PmxTopicHelp 'disk list'; return }
    $session = Get-PmxManagementSession
    if (-not $session.Success) { Write-PmxDisconnectedState -Session $session; return }
    $resolved = Resolve-PmxManagedVm -Selector $parsed.Options.Selector -Session $session
    if (-not $resolved.Success) { Write-Host "❌ $($resolved.Error)" -ForegroundColor Red; return }
    $details = Get-PmxManagedVmDetails -Session $session -Vm $resolved.Vm
    if (-not $details.Success) {
        Write-PmxQueryFailure -Message $details.Error -Diagnostics $details.Diagnostics -Options $parsed.Options
        return
    }
    $mode = Get-PmxOutputMode -Options $parsed.Options -Config $session.Config
    if (-not $mode.Success) { Write-Host "❌ $($mode.Error)" -ForegroundColor Red; return }
    if ($mode.Mode -eq 'json') { Write-PmxJson $details.Disks; return }

    Write-Host ''
    Write-Host "💽 VM DISKS — $($resolved.Vm.VmId) $((ConvertTo-PmxDisplayText $resolved.Vm.Name))" -ForegroundColor Cyan
    Write-Host '────────────────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
    if (-not $details.Disks.Count) { Write-Host '  No resizable VM disks found.' -ForegroundColor DarkGray; return }
    Show-PmxVirtualDiskTable -Disks $details.Disks
    Write-Host ''
}
