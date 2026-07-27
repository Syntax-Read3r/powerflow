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
