# ==============================================================================
# PowerFlow — Startup Entries Adapter (Windows)
# ==============================================================================
# Domain   : Platform / Windows
# File     : platform/windows/adapters/startup.ps1
# Purpose  : Enumerate and manage what runs at login — the Startup folders AND the
#            registry Run keys — for the start-folder command
# Contract : Get-StartupEntry, Set-StartupEntryState, Remove-StartupEntry,
#            Add-StartupEntry, Get-StartupFolderPath
# Depends  : Test-Admin, Invoke-ElevatedCommand (elevation.ps1),
#            Move-ToTrash, Test-TrashSupport (apps.ps1)
# ==============================================================================
#
# WHY NOT JUST THE FOLDER
#
# "The Startup folder" is the findable half of Windows autostart and usually the
# smaller one. On a real desktop it held ONE item while the Run keys held thirteen
# (Steam, Teams, Discord, Docker, Epic, …). A tool that showed only the folder would
# look broken, so start-folder merges every source into one list.
#
# THE STATE TRAP
#
# Task Manager does not delete entries when you disable them — it writes a flag under
# Explorer\StartupApproved. So an entry can be PRESENT in Run yet not run at all
# (Docker Desktop, on the machine this was built against). Reading Run alone would
# report it as starting up, i.e. the tool would lie. Every entry here is therefore
# joined against StartupApproved to get its REAL state.
#
# The flag is a 12-byte REG_BINARY. Byte 0 carries the state: bit 0 SET means disabled
# (observed 0x01 from an installer, 0x03 from Task Manager); enabled is 0x02/0x06.
# We test the bit rather than compare whole bytes so every writer's variant is read
# correctly, and we write Task Manager's own values.
# ==============================================================================

$script:PF_ApprovedEnabled  = [byte[]](0x02,0,0,0,0,0,0,0,0,0,0,0)
$script:PF_ApprovedDisabled = [byte[]](0x03,0,0,0,0,0,0,0,0,0,0,0)

# Where the Startup folders are. -Machine is the all-users one (needs admin to write).
function Get-StartupFolderPath {
    param([switch]$Machine)
    if ($Machine) { return [Environment]::GetFolderPath('CommonStartup') }
    return [Environment]::GetFolderPath('Startup')
}

# Read the StartupApproved flag for one entry. Absent flag = enabled (the common case:
# Windows only writes a value once something has toggled it).
function Get-ApprovedState {
    param([Parameter(Mandatory)][string]$Hive,      # 'HKCU' | 'HKLM'
          [Parameter(Mandatory)][string]$Bucket,    # 'Run' | 'StartupFolder'
          [Parameter(Mandatory)][string]$Name)

    $key = "${Hive}:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\$Bucket"
    if (-not (Test-Path $key)) { return 'enabled' }
    $val = (Get-ItemProperty -Path $key -Name $Name -ErrorAction SilentlyContinue).$Name
    if ($null -eq $val -or $val.Length -lt 1) { return 'enabled' }
    if ($val[0] -band 1) { return 'disabled' }
    return 'enabled'
}

# Resolve a .lnk to the thing it launches, so the list shows a real command rather than
# just a shortcut name. COM is the only way to read a shell link; if it fails we fall
# back to the file itself instead of dropping the row.
function Resolve-ShortcutTarget {
    param([Parameter(Mandatory)][string]$Path)
    if ($Path -notlike '*.lnk') { return $Path }
    try {
        $sh = New-Object -ComObject WScript.Shell
        $lnk = $sh.CreateShortcut($Path)
        $t = $lnk.TargetPath
        if ($lnk.Arguments) { $t = "$t $($lnk.Arguments)" }
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($sh)
        if ($t) { return $t }
    } catch { }
    return $Path
}

function Get-StartupEntry {
    $entries = [System.Collections.Generic.List[object]]::new()

    # ── the Startup folders ───────────────────────────────────────────────────
    foreach ($spec in @(
        @{ Path = (Get-StartupFolderPath);          Scope = 'user';    Hive = 'HKCU'; Label = 'Startup folder' }
        @{ Path = (Get-StartupFolderPath -Machine); Scope = 'machine'; Hive = 'HKLM'; Label = 'Startup folder (all users)' }
    )) {
        if (-not $spec.Path -or -not (Test-Path $spec.Path)) { continue }
        Get-ChildItem -LiteralPath $spec.Path -File -Force -ErrorAction SilentlyContinue |
            # desktop.ini is folder metadata, not a startup item — showing it is noise.
            Where-Object { $_.Name -ne 'desktop.ini' } |
            ForEach-Object {
                $entries.Add([pscustomobject]@{
                    Name     = [IO.Path]::GetFileNameWithoutExtension($_.Name)
                    Source   = $spec.Label
                    Scope    = $spec.Scope
                    State    = (Get-ApprovedState -Hive $spec.Hive -Bucket 'StartupFolder' -Name $_.Name)
                    Command  = (Resolve-ShortcutTarget $_.FullName)
                    Kind     = 'folder'
                    FilePath = $_.FullName
                    ApprovedHive   = $spec.Hive
                    ApprovedBucket = 'StartupFolder'
                    ApprovedName   = $_.Name
                })
            }
    }

    # ── the registry Run keys (where most autostart actually lives) ───────────
    foreach ($spec in @(
        @{ Key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';                Scope = 'user';    Hive = 'HKCU'; Label = 'Registry (HKCU Run)' }
        @{ Key = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run';                Scope = 'machine'; Hive = 'HKLM'; Label = 'Registry (HKLM Run)' }
        @{ Key = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run';    Scope = 'machine'; Hive = 'HKLM'; Label = 'Registry (HKLM Run, 32-bit)' }
    )) {
        if (-not (Test-Path $spec.Key)) { continue }
        $props = Get-ItemProperty -Path $spec.Key -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        $props.PSObject.Properties |
            Where-Object { $_.Name -notlike 'PS*' } |
            ForEach-Object {
                $entries.Add([pscustomobject]@{
                    Name     = $_.Name
                    Source   = $spec.Label
                    Scope    = $spec.Scope
                    State    = (Get-ApprovedState -Hive $spec.Hive -Bucket 'Run' -Name $_.Name)
                    Command  = [string]$_.Value
                    Kind     = 'registry'
                    RegPath  = $spec.Key
                    RegName  = $_.Name
                    ApprovedHive   = $spec.Hive
                    ApprovedBucket = 'Run'
                    ApprovedName   = $_.Name
                })
            }
    }

    return @($entries)
}

# Flip an entry between enabled and disabled — reversibly, the way Task Manager does.
# Nothing is deleted, so this is always undoable by toggling back.
function Set-StartupEntryState {
    param([Parameter(Mandatory)]$Entry, [Parameter(Mandatory)][bool]$Enabled)

    $key   = "$($Entry.ApprovedHive):\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\$($Entry.ApprovedBucket)"
    $bytes = if ($Enabled) { $script:PF_ApprovedEnabled } else { $script:PF_ApprovedDisabled }
    $hex   = ($bytes | ForEach-Object { $_.ToString() }) -join ','

    # HKLM is machine-wide → needs elevation; HKCU is the user's own and never does.
    if ($Entry.ApprovedHive -eq 'HKLM' -and -not (Test-Admin)) {
        $cmd = "if (-not (Test-Path '$key')) { New-Item -Path '$key' -Force | Out-Null }; " +
               "New-ItemProperty -Path '$key' -Name '$($Entry.ApprovedName -replace "'","''")' " +
               "-PropertyType Binary -Value ([byte[]]@($hex)) -Force | Out-Null"
        return (Invoke-ElevatedCommand -Command $cmd)
    }

    try {
        if (-not (Test-Path $key)) { New-Item -Path $key -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -Path $key -Name $Entry.ApprovedName -PropertyType Binary `
                         -Value $bytes -Force -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-Host "   $($_.Exception.Message)" -ForegroundColor DarkGray
        return $false
    }
}

# Delete an entry for good. A folder shortcut goes to the Recycle Bin (recoverable); a
# registry value cannot, which is why the component confirms and shows the command first.
function Remove-StartupEntry {
    param([Parameter(Mandatory)]$Entry)

    if ($Entry.Kind -eq 'folder') {
        if ($Entry.Scope -eq 'machine' -and -not (Test-Admin)) {
            $p = $Entry.FilePath -replace "'", "''"
            return (Invoke-ElevatedCommand -Command "Remove-Item -LiteralPath '$p' -Force")
        }
        try {
            if ((Get-Command Test-TrashSupport -ErrorAction SilentlyContinue) -and (Test-TrashSupport)) {
                return [bool](Move-ToTrash $Entry.FilePath)
            }
            Remove-Item -LiteralPath $Entry.FilePath -Force -ErrorAction Stop
            return $true
        } catch {
            Write-Host "   $($_.Exception.Message)" -ForegroundColor DarkGray
            return $false
        }
    }

    # registry
    if ($Entry.Scope -eq 'machine' -and -not (Test-Admin)) {
        $k = $Entry.RegPath -replace "'", "''"
        $n = $Entry.RegName -replace "'", "''"
        return (Invoke-ElevatedCommand -Command "Remove-ItemProperty -Path '$k' -Name '$n' -Force")
    }
    try {
        Remove-ItemProperty -Path $Entry.RegPath -Name $Entry.RegName -Force -ErrorAction Stop
        return $true
    } catch {
        Write-Host "   $($_.Exception.Message)" -ForegroundColor DarkGray
        return $false
    }
}

# Add something to the user's Startup folder as a shortcut. Always user-scope: writing
# to the all-users folder needs admin and is rarely what someone wants for themselves.
function Add-StartupEntry {
    param([Parameter(Mandatory)][string]$Path, [string]$Name)

    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $target = (Resolve-Path -LiteralPath $Path).Path
    if (-not $Name) { $Name = [IO.Path]::GetFileNameWithoutExtension($target) }

    $lnk = Join-Path (Get-StartupFolderPath) "$Name.lnk"
    try {
        $sh = New-Object -ComObject WScript.Shell
        $s  = $sh.CreateShortcut($lnk)
        $s.TargetPath       = $target
        $s.WorkingDirectory = [IO.Path]::GetDirectoryName($target)
        $s.Description      = "Added by PowerFlow start-folder"
        $s.Save()
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($sh)
        return (Test-Path -LiteralPath $lnk)
    } catch {
        Write-Host "   $($_.Exception.Message)" -ForegroundColor DarkGray
        return $false
    }
}
