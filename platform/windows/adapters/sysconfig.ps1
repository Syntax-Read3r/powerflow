# ==============================================================================
# PowerFlow — System Config Adapter (Windows)
# ==============================================================================
# Domain   : Platform / Windows
# File     : platform/windows/adapters/sysconfig.ps1
# Purpose  : Read and change OS settings (timezone, hostname, regional format,
#            time sync) for the pwsh-config menu — actually applying them
# Contract : Test-SysConfigSupported, Get-SysConfigOptions, Get-SysConfigChoices,
#            Set-SysConfig
# Depends  : Test-Admin (elevation.ps1)
# ==============================================================================
#
# WHY THIS EXISTS (it used to be a stub)
#
# v3.9.0 shipped this adapter as honest no-ops: pwsh-config printed "change these in
# Windows Settings, or with cmdlets like Set-TimeZone / Rename-Computer". That is a
# printed man page, not a tool — the whole point of pwsh-config is that YOU pick the
# value and IT does the work. So every setting here now actually applies.
#
# THE ELEVATION PROBLEM
#
# Three of these four settings are machine-wide and need Administrator: timezone,
# hostname and the time-sync service. PowerFlow is normally run unelevated, so rather
# than refuse, we re-run the ONE set command in an elevated child pwsh
# (Start-Process -Verb RunAs → the standard UAC prompt) and wait for its exit code.
# The user consents once, per change, to a visible prompt — no silent privilege grab,
# and no "permission denied" dead end.
#
# WHAT IS DELIBERATELY NOT HERE: KEYBOARD
#
# Linux has a single console keymap. Windows has no equivalent — the layout is a
# property of the input-language list (Set-WinUserLanguageList with tips like
# '0809:00000809'), and a wrong value can leave you unable to type. Half-implementing
# that is worse than omitting it, so Windows returns four settings, not five. The
# domain model allows this: rows are data, and the menu renders whatever it is given.
# ==============================================================================

# Windows always supports these settings — unlike the Linux side, there is no bus to
# be down. (Kept as a function so the contract matches; see the Linux adapter.)
function Test-SysConfigSupported { return $true }

# Which settings need Administrator to apply.
function Test-SysConfigNeedsAdmin {
    param([Parameter(Mandatory)][string]$Key)
    return ($Key -in @('timezone', 'hostname', 'ntp'))
}

# Run a set command, elevating via UAC only when the setting requires it. The elevated
# path lives in elevation.ps1 (Invoke-ElevatedCommand) because the startup adapter needs
# exactly the same thing for its machine-wide entries.
function Invoke-SysSetWindows {
    param(
        [Parameter(Mandatory)][string]$Command,   # PowerShell to run
        [Parameter(Mandatory)][bool]$NeedsAdmin
    )

    if (-not $NeedsAdmin -or (Test-Admin)) {
        try {
            Invoke-Expression $Command
            return $true
        } catch {
            Write-Host "   $($_.Exception.Message)" -ForegroundColor DarkGray
            return $false
        }
    }

    Write-Host "   🔐 This setting is machine-wide — approve the UAC prompt..." -ForegroundColor DarkGray
    return (Invoke-ElevatedCommand -Command $Command)
}

# Is Windows keeping the clock in sync? Settings' "Set time automatically" maps to the
# W32Time service running with a sync type other than NoSync.
function Get-TimeSyncState {
    $svc = Get-Service W32Time -ErrorAction SilentlyContinue
    if (-not $svc -or $svc.Status -ne 'Running') { return 'off' }
    $type = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters' `
                              -Name Type -ErrorAction SilentlyContinue).Type
    if ($type -eq 'NoSync') { return 'off' }
    return 'on'
}

function Get-SysConfigOptions {
    $tz = try { (Get-TimeZone).Id } catch { '(unknown)' }
    if (-not $tz) { $tz = '(unknown)' }

    $name = $env:COMPUTERNAME
    if (-not $name) { $name = '(unknown)' }

    # "Regional format" (per-user culture) is the honest analogue of Linux's LANG: it
    # drives date/number/currency formatting. Set-WinSystemLocale (the non-Unicode
    # system locale) is a different, reboot-requiring setting and is not what people
    # mean by "language" here.
    $culture = try { (Get-Culture).Name } catch { '(unknown)' }

    return @(
        [pscustomobject]@{ Key = 'timezone'; Label = 'Timezone';          Current = $tz;                   Kind = 'list'
                           Note = 'applies immediately' }
        [pscustomobject]@{ Key = 'locale';   Label = 'Regional format';   Current = $culture;              Kind = 'list'
                           Note = 'applies to new shells/apps' }
        [pscustomobject]@{ Key = 'hostname'; Label = 'Hostname';          Current = $name;                 Kind = 'text'
                           Note = 'takes effect after a RESTART' }
        [pscustomobject]@{ Key = 'ntp';      Label = 'Network time sync';  Current = (Get-TimeSyncState);   Kind = 'toggle'
                           Note = 'W32Time service' }
    )
}

function Get-SysConfigChoices {
    param([Parameter(Mandatory)][string]$Key)
    switch ($Key) {
        'timezone' { return @((Get-TimeZone -ListAvailable | Select-Object -ExpandProperty Id)) }
        # Specific cultures only: neutral ones ('en') are not valid regional formats.
        'locale'   { return @([System.Globalization.CultureInfo]::GetCultures('SpecificCultures') |
                              Select-Object -ExpandProperty Name | Sort-Object) }
        default    { return @() }
    }
}

function Set-SysConfig {
    param([Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][string]$Value)

    # Reject a value that isn't one of the offered choices. This is not paranoia:
    # Set-Culture ACCEPTS an unknown name (it wrote a bogus 'zz-ZZ' regional format
    # during testing) instead of failing, unlike Set-TimeZone which validates. Shielding
    # the caller from that per-cmdlet inconsistency is exactly the adapter's job.
    $choices = @(Get-SysConfigChoices -Key $Key)
    if ($choices.Count -gt 0 -and $Value -notin $choices) { return $false }

    # Single-quote the value into the child command; '' escapes an embedded quote so a
    # value can never break out of the string (these run through pwsh -Command).
    $safe  = $Value -replace "'", "''"
    $admin = Test-SysConfigNeedsAdmin -Key $Key

    switch ($Key) {
        'timezone' { return (Invoke-SysSetWindows -Command "Set-TimeZone -Id '$safe' -ErrorAction Stop" -NeedsAdmin $admin) }
        'locale'   { return (Invoke-SysSetWindows -Command "Set-Culture -CultureInfo '$safe' -ErrorAction Stop" -NeedsAdmin $admin) }
        'hostname' { return (Invoke-SysSetWindows -Command "Rename-Computer -NewName '$safe' -Force -ErrorAction Stop" -NeedsAdmin $admin) }
        'ntp'      {
            # 'true'/'false' comes from the component's toggle, matching the Linux contract.
            if ($Value -eq 'true') {
                $cmd = "Set-Service W32Time -StartupType Automatic -ErrorAction Stop; " +
                       "Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters' -Name Type -Value 'NTP' -ErrorAction Stop; " +
                       "Start-Service W32Time -ErrorAction Stop; w32tm /resync | Out-Null"
            } else {
                $cmd = "Stop-Service W32Time -Force -ErrorAction Stop; " +
                       "Set-Service W32Time -StartupType Manual -ErrorAction Stop"
            }
            return (Invoke-SysSetWindows -Command $cmd -NeedsAdmin $admin)
        }
        default    { return $false }
    }
}
