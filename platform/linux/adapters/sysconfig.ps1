# ==============================================================================
# PowerFlow — System Config Adapter (Linux)
# ==============================================================================
# Domain   : Platform / Linux
# File     : platform/linux/adapters/sysconfig.ps1
# Purpose  : Read and change OS settings (keyboard, timezone, locale, hostname,
#            time-sync) for the pwsh-config menu — via systemd, not dpkg-reconfigure
# Contract : Test-SysConfigSupported, Get-SysConfigOptions, Get-SysConfigChoices,
#            Set-SysConfig
# Depends  : localectl / timedatectl / hostnamectl (systemd — every modern distro)
# ==============================================================================
#
# WHY systemd TOOLS, NOT dpkg-reconfigure
#
# dpkg-reconfigure is Debian/Ubuntu-only and silently does nothing when debconf can't
# find a dialog frontend — which is exactly the "I ran it and nothing happened" report
# this came from. localectl/timedatectl/hostnamectl ship on Fedora, Debian, Ubuntu,
# Arch and openSUSE alike and are non-interactive (you pass the value), so PowerFlow can
# put its OWN fzf picker in front — one experience on every distro.
#
# THE DOMAIN MODEL
#
# Get-SysConfigOptions returns one row per configurable thing, with its current value
# and a Kind ('list' | 'text' | 'toggle') telling the component how to prompt. Adding a
# new setting = one row here + a case in Get-SysConfigChoices/Set-SysConfig. That is the
# whole extensibility story pwsh-config is built on.
# ==============================================================================

# localectl needs a live systemd bus. In a container or WSL without systemd as PID 1,
# the binary exists but every call fails with "System has not been booted with systemd".
# So "supported" means it can actually OPERATE, not merely that it is installed.
function Test-SysConfigSupported {
    if (-not (Get-Command localectl -ErrorAction SilentlyContinue)) { return $false }
    localectl status *> $null
    return ($LASTEXITCODE -eq 0)
}

# Run a systemd `set-*` command, elevating with sudo only when not already root.
#
# ⚠️ Built as an explicit list, NOT `$sudo = if(root){@()}else{@('sudo')}; $sudo + $cmd`.
# PowerShell unrolls a one-element array to a scalar, so @('sudo') becomes the STRING
# 'sudo' and the concatenation turns into string math — the same trap documented in the
# packages adapter. Returns $true only if the command exits 0.
function Invoke-SysSet {
    param([Parameter(Mandatory)][string[]]$Command)
    $argv = [System.Collections.Generic.List[string]]::new()
    if ((id -u) -ne '0') { $argv.Add('sudo') }
    foreach ($c in $Command) { $argv.Add($c) }
    $exe  = $argv[0]
    $rest = @($argv | Select-Object -Skip 1)
    & $exe @rest 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

# The keyboard has TWO models across distros. Fedora/Arch use vconsole keymaps
# (`localectl list-keymaps` / `set-keymap`, /etc/vconsole.conf). Debian/Ubuntu ship NO
# vconsole keymaps and manage the keyboard via console-setup / X11 layouts
# (`localectl list-x11-keymap-layouts` / `set-x11-keymap`, /etc/default/keyboard) — there,
# `list-keymaps` is empty. Detect which model this box actually supports so pwsh-config's
# keyboard setting works on both instead of dead-ending with "no choices" on Debian.
function Get-KeyboardMode {
    if (@(localectl list-keymaps 2>/dev/null).Count -gt 0) { return 'vc' }
    return 'x11'
}

function Get-SysConfigOptions {
    $status = localectl status 2>/dev/null
    $keymap = ($status | Select-String 'VC Keymap' | ForEach-Object { (($_ -split ':', 2)[1]).Trim() })
    # On Debian/Ubuntu the VC Keymap is unset and the real value is the X11 Layout — fall
    # back to it so the menu shows what's actually configured, not "(unset)".
    if (-not $keymap -or $keymap -in @('(unset)', 'n/a')) {
        $x11 = ($status | Select-String 'X11 Layout' | ForEach-Object { (($_ -split ':', 2)[1]).Trim() })
        if ($x11) { $keymap = $x11 }
    }
    $locale = ($status | Select-String 'System Locale' | ForEach-Object { (($_ -split ':', 2)[1]).Trim() })
    # localectl prints "System Locale: LANG=en_US.UTF-8"; we manage LANG, so surface its
    # bare value — every other row's Current (and list-locales) is bare, so this matches.
    if ($locale -match 'LANG=(\S+)') { $locale = $matches[1] }
    if (-not $keymap) { $keymap = '(unset)' }
    if (-not $locale) { $locale = '(unset)' }

    $tz   = (timedatectl show -p Timezone --value 2>/dev/null)
    $ntp  = (timedatectl show -p NTP --value 2>/dev/null)   # yes | no
    $name = (hostnamectl --static 2>/dev/null)
    if (-not $tz)   { $tz   = '(unknown)' }
    if (-not $name) { $name = '(unknown)' }
    $ntpLabel = if ($ntp -eq 'yes') { 'on' } else { 'off' }

    # Note carries the per-setting caveat the menu prints after a successful change —
    # same shape as the Windows adapter, so the component needs no per-OS special cases.
    $kbNote = if ((Get-KeyboardMode) -eq 'vc') {
        'console keymap; a graphical session may also need the X11 layout'
    } else {
        'X11 layout (/etc/default/keyboard); does not affect your SSH session'
    }

    return @(
        [pscustomobject]@{ Key = 'keyboard'; Label = 'Keyboard layout';    Current = $keymap;   Kind = 'list'
                           Note = $kbNote }
        [pscustomobject]@{ Key = 'timezone'; Label = 'Timezone';           Current = $tz;       Kind = 'list'
                           Note = 'applies immediately' }
        [pscustomobject]@{ Key = 'locale';   Label = 'Locale / language';  Current = $locale;   Kind = 'list'
                           Note = 'applies to new logins' }
        [pscustomobject]@{ Key = 'hostname'; Label = 'Hostname';           Current = $name;     Kind = 'text'
                           Note = 'new shells show the new name' }
        [pscustomobject]@{ Key = 'ntp';      Label = 'Network time sync';  Current = $ntpLabel; Kind = 'toggle'
                           Note = 'systemd-timesyncd' }
    )
}

function Get-SysConfigChoices {
    param([Parameter(Mandatory)][string]$Key)
    switch ($Key) {
        'keyboard' {
            if ((Get-KeyboardMode) -eq 'vc') { return @(localectl list-keymaps 2>/dev/null) }
            return @(localectl list-x11-keymap-layouts 2>/dev/null)   # Debian/Ubuntu
        }
        'timezone' { return @(timedatectl list-timezones 2>/dev/null) }
        'locale'   { return @(localectl list-locales 2>/dev/null) }
        default    { return @() }
    }
}

function Set-SysConfig {
    param([Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][string]$Value)
    switch ($Key) {
        # Set through whichever model this box uses (see Get-KeyboardMode): set-x11-keymap on
        # Debian/Ubuntu writes /etc/default/keyboard and converts to a console keymap too.
        'keyboard' {
            if ((Get-KeyboardMode) -eq 'vc') { return (Invoke-SysSet @('localectl', 'set-keymap',     $Value)) }
            return (Invoke-SysSet @('localectl', 'set-x11-keymap', $Value))
        }
        'timezone' { return (Invoke-SysSet @('timedatectl', 'set-timezone', $Value)) }
        # set-locale wants VARIABLE=value; list-locales gives the bare locale, so wrap it.
        'locale'   { return (Invoke-SysSet @('localectl',   'set-locale',   "LANG=$Value")) }
        # '--' ends option parsing: hostname is user-typed, so a value like "-foo" must
        # reach hostnamectl as a hostname, not be mistaken for a flag. (argv, so no shell.)
        'hostname' { return (Invoke-SysSet @('hostnamectl', 'set-hostname', '--', $Value)) }
        'ntp'      { return (Invoke-SysSet @('timedatectl', 'set-ntp',      $Value)) }   # true | false
        default    { return $false }
    }
}

# ── PF-FEAT-005: renaming the host, without breaking name resolution ──────────
#
# `hostnamectl set-hostname web-prod` on its own leaves /etc/hosts pointing at the OLD
# name, and the very next sudo prints:
#
#     sudo: unable to resolve host web-prod: Name or service not known
#
# It still works — sudo falls back after a timeout — but it is alarming, it slows every
# elevated command, and on Debian it persists until somebody edits /etc/hosts by hand.
# Changing the two together is the whole point of this pair.

<#
.SYNOPSIS
    RFC 1123 validation for a hostname label.
.DESCRIPTION
    hostnamectl accepts more than DNS does, so validating here rather than letting it
    through means the refusal arrives BEFORE anything is changed. Underscores are the
    common trap: legal in a Windows NetBIOS name, illegal in DNS, and the resulting host
    is unreachable by name from anything that resolves properly.
#>
function Test-HostNameValid {
    # AllowEmptyString, deliberately. Mandatory alone rejects '' with a binder error, which
    # would make the empty-name branch below unreachable and replace a sentence the caller
    # can print with an exception it has to catch.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Name)

    if ($Name.Length -eq 0)  { return [pscustomobject]@{ Valid = $false; Error = 'the name is empty' } }
    if ($Name.Length -gt 63) { return [pscustomobject]@{ Valid = $false; Error = "'$Name' is $($Name.Length) characters; a label may not exceed 63" } }
    if ($Name -notmatch '^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$') {
        $hint = if ($Name -match '_') { ' (underscores are legal on Windows but not in DNS)' } else { '' }
        return [pscustomobject]@{ Valid = $false
            Error = "'$Name' is not a valid hostname — use letters, digits and hyphens, not starting or ending with a hyphen$hint" }
    }
    if ($Name -match '^[0-9]+$') {
        return [pscustomobject]@{ Valid = $false; Error = "'$Name' is all digits, which resolvers read as an address" }
    }
    return [pscustomobject]@{ Valid = $true; Error = '' }
}

<#
.SYNOPSIS
    The current hostname, from whichever source this distro actually has.
.DESCRIPTION
    hostnamectl is systemd-only. Alpine and a plain container have neither it nor systemd,
    and `2>/dev/null` does NOT silence a missing native command — PowerShell throws
    CommandNotFoundException before the redirect is ever reached. So every source is
    probed with Get-Command first.
#>
function Get-CurrentHostName {
    if (Get-Command hostnamectl -ErrorAction SilentlyContinue) {
        $name = "$(hostnamectl --static 2>$null)".Trim()
        if ($name) { return $name }
    }
    if (Get-Command hostname -CommandType Application -ErrorAction SilentlyContinue) {
        $name = "$(& hostname 2>$null)".Trim()
        if ($name) { return $name }
    }
    if (Test-Path '/etc/hostname') {
        $name = "$(Get-Content '/etc/hostname' -ErrorAction SilentlyContinue | Select-Object -First 1)".Trim()
        if ($name) { return $name }
    }
    return [Environment]::MachineName
}

<#
.SYNOPSIS
    What renaming this host would change — read-only.
.DESCRIPTION
    Returns the current name, the /etc/hosts line that would be rewritten, and the exact
    replacement, so the caller can PREVIEW the whole change before anything happens.

    Only the LOCAL-HOST entry is touched: the 127.x line that already carries the current
    hostname. Every other line is left alone — /etc/hosts commonly holds an operator's own
    static entries for other machines, and a rename has no business rewriting those.
#>
function Get-HostRenamePlan {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$NewName)

    $current = Get-CurrentHostName

    $validation = Test-HostNameValid -Name $NewName
    if (-not $validation.Valid) {
        return [pscustomobject]@{
            Supported = $true; Valid = $false; Current = $current; New = $NewName
            HostsPath = '/etc/hosts'; LineNumber = 0; Before = ''; After = ''
            Fqdn = ''; Error = $validation.Error
        }
    }

    if ($current -eq $NewName) {
        return [pscustomobject]@{
            Supported = $true; Valid = $false; Current = $current; New = $NewName
            HostsPath = '/etc/hosts'; LineNumber = 0; Before = ''; After = ''
            Fqdn = ''; Error = "this host is already called '$NewName'"
        }
    }

    $before = ''; $after = ''; $lineNo = 0; $fqdn = ''
    if (Test-Path '/etc/hosts') {
        $lines = @(Get-Content '/etc/hosts' -ErrorAction SilentlyContinue)
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ($line -match '^\s*#') { continue }
            # The local-host entry: a loopback address whose names include the current one.
            if ($line -notmatch '^\s*127\.') { continue }
            $fields = @($line -split '\s+' | Where-Object { $_ })
            if ($fields.Count -lt 2) { continue }
            $names = @($fields | Select-Object -Skip 1)
            # Match the SHORT name against each label, so "old.domain old" is caught by both
            # its FQDN and its bare form.
            $hit = @($names | Where-Object { $_ -eq $current -or $_ -like "$current.*" })
            if (-not $hit.Count) { continue }

            $before = $line
            $lineNo = $i + 1
            # Replace only the hostname portion of each name, preserving any domain suffix.
            $rewritten = @($names | ForEach-Object {
                if ($_ -eq $current) { $NewName }
                elseif ($_ -like "$current.*") { $NewName + $_.Substring($current.Length) }
                else { $_ }
            })
            $after = ($fields[0] + "`t" + ($rewritten -join ' '))
            $fqdn = @($rewritten | Where-Object { $_ -like '*.*' } | Select-Object -First 1)
            break
        }
    }

    return [pscustomobject]@{
        Supported  = $true
        Valid      = $true
        Current    = $current
        New        = $NewName
        HostsPath  = '/etc/hosts'
        LineNumber = $lineNo
        Before     = $before
        After      = $after
        Fqdn       = "$fqdn"
        # No matching line is NOT an error: plenty of systems have no 127.0.1.1 entry at
        # all. It means there is nothing to sync, and the caller should say so rather than
        # inventing an entry the distro never had.
        Error      = ''
    }
}

<#
.SYNOPSIS
    Set the hostname itself, on systemd and on distros without it.
.DESCRIPTION
    Alpine and Arch-without-systemd are both in PowerFlow's Linux CI matrix, and neither
    has hostnamectl. There the two halves are separate: `hostname` sets the RUNNING name
    and /etc/hostname sets the one that survives a reboot. Doing only the first is the same
    class of half-change this whole feature exists to avoid.
#>
function Set-MachineHostName {
    param([Parameter(Mandatory)][string]$NewName)

    if (Get-Command hostnamectl -ErrorAction SilentlyContinue) {
        if (Invoke-SysSet @('hostnamectl', 'set-hostname', '--', $NewName)) {
            return [pscustomobject]@{ Success = $true; Error = '' }
        }
        return [pscustomobject]@{ Success = $false
            Error = 'hostnamectl refused the change (is this a container, or was sudo declined?)' }
    }

    if (-not (Get-Command hostname -CommandType Application -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ Success = $false
            Error = 'neither hostnamectl nor hostname is available to set the name with' }
    }

    if (-not (Invoke-SysSet @('hostname', '--', $NewName))) {
        return [pscustomobject]@{ Success = $false
            Error = 'hostname refused the change (is this an unprivileged container, or was sudo declined?)' }
    }

    # Running name changed; now make it survive a reboot. If this half fails, say so
    # exactly — "it is renamed until you reboot" is a very different situation from "it is
    # renamed", and a caller told the wrong one will be surprised much later.
    $tmp = Join-Path ([IO.Path]::GetTempPath()) 'powerflow-hostname'
    try { Set-Content -Path $tmp -Value $NewName -Encoding utf8 -ErrorAction Stop }
    catch {
        return [pscustomobject]@{ Success = $false
            Error = "the running hostname is now '$NewName', but /etc/hostname could not be written — it will revert on reboot" }
    }
    $persisted = Invoke-SysSet @('cp', '--', $tmp, '/etc/hostname')
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    if (-not $persisted) {
        return [pscustomobject]@{ Success = $false
            Error = "the running hostname is now '$NewName', but /etc/hostname could not be written — it will revert on reboot" }
    }

    return [pscustomobject]@{ Success = $true; Error = '' }
}

<#
.SYNOPSIS
    Apply the rename: hostname first, then the matching /etc/hosts line.
.DESCRIPTION
    /etc/hosts is BACKED UP before it is touched, next to the original with a timestamp,
    and the backup path is returned — a file this important should never be edited without
    leaving the previous version somewhere obvious.

    Order matters. The hostname is set first because it is the recoverable half: if the
    hosts edit then fails, the host has a new name and a stale resolver entry, which is
    noisy but harmless and is exactly the state the caller is told how to finish. Editing
    hosts first and failing the rename would leave a resolver entry for a name the machine
    does not have.
#>
function Set-HostRename {
    param(
        [Parameter(Mandatory)][string]$NewName,
        [string]$HostsBefore = '',
        [string]$HostsAfter = ''
    )

    $validation = Test-HostNameValid -Name $NewName
    if (-not $validation.Valid) {
        return [pscustomobject]@{ Supported = $true; Success = $false; HostnameSet = $false
            HostsUpdated = $false; BackupPath = ''; Error = $validation.Error }
    }

    $set = Set-MachineHostName -NewName $NewName
    if (-not $set.Success) {
        return [pscustomobject]@{ Supported = $true; Success = $false; HostnameSet = $false
            HostsUpdated = $false; BackupPath = ''; Error = $set.Error }
    }

    if (-not $HostsBefore) {
        # Nothing to sync — the machine had no local-host entry naming it.
        return [pscustomobject]@{ Supported = $true; Success = $true; HostnameSet = $true
            HostsUpdated = $false; BackupPath = ''; Error = '' }
    }

    $stamp = (Get-Date -Format 'yyyyMMdd-HHmmss')
    $backup = "/etc/hosts.powerflow-$stamp"
    if (-not (Invoke-SysSet @('cp', '-p', '--', '/etc/hosts', $backup))) {
        return [pscustomobject]@{ Supported = $true; Success = $false; HostnameSet = $true
            HostsUpdated = $false; BackupPath = ''
            Error = 'the hostname was changed, but /etc/hosts could not be backed up — it was left untouched' }
    }

    # Rewritten here rather than with `sed -i`, deliberately. Escaping a hosts line into a
    # sed script means POSIX BRE, and [regex]::Escape emits .NET escaping — in which \+,
    # \( and \{ are the LITERAL forms, while BRE reads exactly those as the SPECIAL ones.
    # On busybox sed (Alpine) the mismatch is not theoretical. Building the file in
    # PowerShell and copying it into place has no escaping layer at all.
    $failed = [pscustomobject]@{ Supported = $true; Success = $false; HostnameSet = $true
        HostsUpdated = $false; BackupPath = $backup
        Error = "the hostname was changed, but /etc/hosts could not be updated. Restore with: sudo cp -p $backup /etc/hosts" }

    try {
        $lines   = @(Get-Content '/etc/hosts' -ErrorAction Stop)
        $matched = $false
        $rewritten = @($lines | ForEach-Object {
            if (-not $matched -and $_ -eq $HostsBefore) { $matched = $true; $HostsAfter } else { $_ }
        })
        # The line moved or changed since the preview was taken. Writing anyway would apply
        # an edit the user never saw.
        if (-not $matched) { return $failed }

        $tmp = Join-Path ([IO.Path]::GetTempPath()) "powerflow-hosts-$stamp"
        Set-Content -Path $tmp -Value $rewritten -Encoding utf8 -ErrorAction Stop
    }
    catch { return $failed }

    # `cp` onto the existing file, not `mv` — cp writes through the original inode, so the
    # owner, mode and any ACL on /etc/hosts survive. mv would replace it with a file owned
    # by whoever ran the command.
    $copied = Invoke-SysSet @('cp', '--', $tmp, '/etc/hosts')
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    if (-not $copied) { return $failed }

    return [pscustomobject]@{ Supported = $true; Success = $true; HostnameSet = $true
        HostsUpdated = $true; BackupPath = $backup; Error = '' }
}

<#
.SYNOPSIS
    Does the new name resolve locally? The point of the whole exercise.
#>
function Test-HostResolution {
    param([Parameter(Mandatory)][string]$Name)
    if (-not (Get-Command getent -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ Checked = $false; Resolves = $false; Detail = 'getent is not available to check with' }
    }
    $out = & getent hosts $Name 2>$null
    return [pscustomobject]@{
        Checked  = $true
        Resolves = ($LASTEXITCODE -eq 0 -and [bool]$out)
        Detail   = "$(@($out)[0])".Trim()
    }
}
