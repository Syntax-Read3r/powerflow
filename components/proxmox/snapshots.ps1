# ==============================================================================
# PowerFlow — Proxmox VM Snapshots
# ==============================================================================
# Domain   : Proxmox
# File     : components/proxmox/snapshots.ps1
# Purpose  : List and create VM snapshots through guarded, allow-listed operations
# Functions: Get-PmxSnapshots, Show-PmxSnapshots, Invoke-PmxSnapshotCreate
# Depends  : shared.ps1, config.ps1, vm-read.ps1, vm-change.ps1, management adapter
# ==============================================================================

function Get-PmxSnapshots {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)]$Vm
    )
    $result = Invoke-ProxmoxManagementQuery -Operation 'snapshot-list' -Connection $Session.Connection `
        -Parameters @{ Vmid = [int]$Vm.VmId; Node = "$($Vm.Node)" }
    if (-not $result.Success) {
        return [pscustomobject]@{ Success = $false; Snapshots = @(); Error = $result.Error; Result = $result }
    }
    $snapshots = @($result.Data | Where-Object { "$(Get-PmxObjectProperty $_ 'name' '')" -cne 'current' } | ForEach-Object {
        [pscustomobject]@{
            Name        = ConvertTo-PmxDisplayText (Get-PmxObjectProperty $_ 'name' '')
            Description = ConvertTo-PmxDisplayText (Get-PmxObjectProperty $_ 'description' '')
            Parent      = ConvertTo-PmxDisplayText (Get-PmxObjectProperty $_ 'parent' '')
            Running     = ((Get-PmxObjectProperty $_ 'running' 0) -eq 1)
            SnapshotTime = [long](Get-PmxObjectProperty $_ 'snaptime' 0)
        }
    } | Sort-Object SnapshotTime, Name)
    return [pscustomobject]@{ Success = $true; Snapshots = $snapshots; Error = ''; Result = $result }
}

function Get-PmxSnapshotInvocation {
    param(
        [object[]]$Arguments,
        [switch]$RequireName
    )

    $valueOptions = @{ 'vm' = 'Vm' }
    if ($RequireName) { $valueOptions['name'] = 'Name' }
    $max = if ($RequireName) { 2 } else { 1 }
    $parsed = ConvertFrom-PmxArguments -Arguments $Arguments -ValueOptions $valueOptions `
        -SwitchOptions (Get-PmxGlobalSwitchMap) -MaxPositionals $max
    if (-not $parsed.Success) { return $parsed }

    if ($parsed.Positionals.Count) {
        $expected = if ($RequireName) { 2 } else { 1 }
        if ($parsed.Positionals.Count -ne $expected -or $parsed.Options.ContainsKey('Vm') -or
            ($RequireName -and $parsed.Options.ContainsKey('Name'))) {
            return [pscustomobject]@{ Success = $false; Options = $parsed.Options; Positionals = $parsed.Positionals; Error = 'use named options, or the documented positional form, but not both' }
        }
        $parsed.Options.Vm = $parsed.Positionals[0]
        if ($RequireName) { $parsed.Options.Name = $parsed.Positionals[1] }
    }
    if (-not $parsed.Options.ContainsKey('Vm') -or ($RequireName -and -not $parsed.Options.ContainsKey('Name'))) {
        return [pscustomobject]@{ Success = $false; Options = $parsed.Options; Positionals = $parsed.Positionals; Error = $(if ($RequireName) { '--vm and --name are required' } else { '--vm is required' }) }
    }
    return $parsed
}

function Show-PmxSnapshots {
    param([object[]]$Arguments = @())

    if (@($Arguments | Where-Object { "$_" -eq '--help' }).Count) { Show-PmxTopicHelp 'snapshot list'; return }
    $parsed = Get-PmxSnapshotInvocation -Arguments $Arguments
    if (-not $parsed.Success) { Write-Host "❌ $($parsed.Error)" -ForegroundColor Red; return }
    $session = Get-PmxManagementSession
    if (-not $session.Success) { Write-PmxDisconnectedState -Session $session; return }
    $resolved = Resolve-PmxManagedVm -Selector "$($parsed.Options.Vm)" -Session $session
    if (-not $resolved.Success) { Write-PmxResolveFailure -Resolved $resolved; return }
    $result = Get-PmxSnapshots -Session $session -Vm $resolved.Vm
    if (-not $result.Success) { Write-PmxQueryFailure -Message $result.Error -Diagnostics $result.Diagnostics -Options $parsed.Options; return }
    $mode = Get-PmxOutputMode -Options $parsed.Options -Config $session.Config
    if (-not $mode.Success) { Write-Host "❌ $($mode.Error)" -ForegroundColor Red; return }
    if ($mode.Mode -eq 'json') { Write-PmxJson $result.Snapshots; return }

    Write-Host ''
    Write-Host "📸 SNAPSHOTS — VM $($resolved.Vm.VmId) $((ConvertTo-PmxDisplayText $resolved.Vm.Name))" -ForegroundColor Cyan
    Write-Host '────────────────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
    if (-not $result.Snapshots.Count) { Write-Host '  No snapshots.' -ForegroundColor DarkGray; Write-Host ''; return }
    Write-Host ('  {0,-24} {1,-20} {2,-8} {3}' -f 'NAME', 'CREATED', 'STATE', 'DESCRIPTION') -ForegroundColor DarkGray
    foreach ($snapshot in $result.Snapshots) {
        $created = if ($snapshot.SnapshotTime -gt 0) { [DateTimeOffset]::FromUnixTimeSeconds($snapshot.SnapshotTime).LocalDateTime.ToString('yyyy-MM-dd HH:mm') } else { 'unknown' }
        Write-Host ('  {0,-24} {1,-20} {2,-8} {3}' -f $snapshot.Name, $created,
            $(if ($snapshot.Running) { 'running' } else { 'stopped' }), $snapshot.Description) -ForegroundColor White
    }
    Write-Host ''
}

function Invoke-PmxSnapshotCreate {
    param([object[]]$Arguments = @())

    if (@($Arguments | Where-Object { "$_" -eq '--help' }).Count) { Show-PmxTopicHelp 'snapshot create'; return }
    $parsed = Get-PmxSnapshotInvocation -Arguments $Arguments -RequireName
    if (-not $parsed.Success) { Write-Host "❌ $($parsed.Error)" -ForegroundColor Red; return }
    $name = "$($parsed.Options.Name)"
    if ($name -cnotmatch '^[A-Za-z][A-Za-z0-9_-]{0,39}$' -or
        [string]::Equals($name, 'current', [StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($name, 'pending', [StringComparison]::OrdinalIgnoreCase)) {
        Write-Host '❌ Snapshot names must start with a letter, use letters/digits/_/-, be at most 40 characters, and not be current or pending.' -ForegroundColor Red
        return
    }
    $session = Get-PmxManagementSession
    if (-not $session.Success) { Write-PmxDisconnectedState -Session $session; return }
    $resolved = Resolve-PmxManagedVm -Selector "$($parsed.Options.Vm)" -Session $session
    if (-not $resolved.Success) { Write-PmxResolveFailure -Resolved $resolved; return }
    if ($resolved.Vm.Template) { Write-Host '❌ Create snapshots on a VM, not on its template.' -ForegroundColor Red; return }
    $existing = Get-PmxSnapshots -Session $session -Vm $resolved.Vm
    if (-not $existing.Success) { Write-Host "❌ $($existing.Error)" -ForegroundColor Red; return }
    if (@($existing.Snapshots | Where-Object { [string]::Equals($_.Name, $name, [StringComparison]::Ordinal) }).Count) {
        Write-Host "❌ Snapshot '$name' already exists." -ForegroundColor Red; return
    }

    $snapshot = $resolved.Vm
    $parameters = @{ Vmid = $snapshot.VmId; Name = $name }
    $revalidate = {
        $freshVm = Resolve-PmxManagedVm -Selector "$($snapshot.VmId)" -Session $session
        if (-not $freshVm.Success -or -not (Test-PmxVmSnapshotIdentity $snapshot $freshVm.Vm)) { return [pscustomobject]@{ Success = $false; Error = 'VM identity changed after confirmation' } }
        $freshSnapshots = Get-PmxSnapshots -Session $session -Vm $freshVm.Vm
        if (-not $freshSnapshots.Success) { return [pscustomobject]@{ Success = $false; Error = $freshSnapshots.Error } }
        if (@($freshSnapshots.Snapshots | Where-Object { [string]::Equals($_.Name, $name, [StringComparison]::Ordinal) }).Count) { return [pscustomobject]@{ Success = $false; Error = "snapshot '$name' appeared after confirmation" } }
        return [pscustomobject]@{ Success = $true; Error = ''; Parameters = $parameters }
    }.GetNewClosure()
    $verify = {
        $fresh = Get-PmxSnapshots -Session $session -Vm $snapshot
        if (-not $fresh.Success -or -not @($fresh.Snapshots | Where-Object { [string]::Equals($_.Name, $name, [StringComparison]::Ordinal) }).Count) { return [pscustomobject]@{ Success = $false; Error = "snapshot '$name' was not returned" } }
        return [pscustomobject]@{ Success = $true; Error = ''; Message = "Created snapshot '$name' for VM $($snapshot.VmId)." }
    }.GetNewClosure()
    $fields = [ordered]@{ VM = "$($snapshot.VmId) $($snapshot.Name)"; Snapshot = $name; 'VM state' = $snapshot.Status }
    $null = Invoke-PmxAmberMutation -Session $session -Operation 'snapshot-create' -Parameters $parameters `
        -Title 'CREATE VM SNAPSHOT' -Fields $fields -Options $parsed.Options -Revalidate $revalidate -Verify $verify -VmId "$($snapshot.VmId)"
}
