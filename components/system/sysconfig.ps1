# ==============================================================================
# PowerFlow — System Config Menu
# ==============================================================================
# Domain   : System
# File     : components/system/sysconfig.ps1
# Purpose  : pwsh-config — one menu to change OS settings (keyboard, timezone,
#            locale, hostname, time-sync), each picked with fzf
# Functions: pwsh-config
# Depends  : sysconfig adapter — Test-SysConfigSupported, Get-SysConfigOptions,
#            Get-SysConfigChoices, Set-SysConfig ; fzf (optional)
# ==============================================================================
#
# One entry point instead of a command per setting: you don't have to know the name of
# what you want to change — you browse the list (with current values shown) and pick.
# Adding a new setting is a row in the adapter's Get-SysConfigOptions; this menu picks
# it up for free. Replaces reaching for dpkg-reconfigure (Debian-only, silently no-ops
# without a debconf frontend).
#
# All OS work is in the adapter; this only renders and prompts.
# ==============================================================================

# Friendly aliases so `pwsh-config kb` jumps straight to the keyboard setting.
$script:PF_ConfigAliases = @{
    'kb' = 'keyboard'; 'keys' = 'keyboard'
    'tz' = 'timezone'; 'time' = 'timezone'
    'loc' = 'locale';  'lang' = 'locale'
    'host' = 'hostname'; 'name' = 'hostname'
    'ntp' = 'ntp'; 'sync' = 'ntp'
}

<#
.SYNOPSIS
    pwsh-config — change a system setting from a menu (Linux).
.DESCRIPTION
    pwsh-config            browse every setting (current values shown) and pick one
    pwsh-config <name>     jump straight to one: keyboard | timezone | locale |
                           hostname | ntp  (kb / tz / loc / host / sync also work)
    Each change is applied with sudo; systemd (localectl/timedatectl) does the work,
    so it behaves the same on Fedora, Debian, Ubuntu, Arch and openSUSE.
.EXAMPLE
    pwsh-config
    pwsh-config kb
#>
function pwsh-config {
    param([string]$Which)

    if (-not (Test-SysConfigSupported)) {
        Write-Host ""
        if ($script:PowerFlowOS -eq 'windows') {
            Write-Host "ℹ️  pwsh-config manages Linux system settings (systemd)." -ForegroundColor Cyan
            Write-Host "   On Windows, change these in Settings, or with cmdlets like" -ForegroundColor DarkGray
            Write-Host "   Set-TimeZone / Rename-Computer / Set-WinUserLanguageList." -ForegroundColor DarkGray
        } else {
            Write-Host "❌ pwsh-config needs systemd (localectl/timedatectl), which isn't operating here." -ForegroundColor Red
            Write-Host "   (Common in containers/WSL without systemd as PID 1 — your real server is fine.)" -ForegroundColor DarkGray
        }
        Write-Host ""
        return
    }

    $opts = @(Get-SysConfigOptions)
    if ($opts.Count -eq 0) { Write-Host "❌ No settings available." -ForegroundColor Red; return }

    # One notion of "interactive" for the WHOLE flow. fzf reads /dev/tty even when stdin
    # is redirected, but Read-Host reads stdin — so a half-redirected session (piped-in,
    # terminal out) could pick a setting through fzf that the prompt then can't apply.
    # Deciding once, up front, keeps every path honest: we either run the pickers AND the
    # prompts, or we print the list / say "need a terminal" — never navigate to a dead end.
    $canPrompt = -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected
    $haveFzf   = [bool](Get-Command fzf -ErrorAction SilentlyContinue)

    # ── pick the setting ──────────────────────────────────────────────────────
    $entry = $null
    if ($Which) {
        $key = if ($script:PF_ConfigAliases.ContainsKey($Which.ToLower())) { $script:PF_ConfigAliases[$Which.ToLower()] } else { $Which.ToLower() }
        $entry = $opts | Where-Object Key -eq $key | Select-Object -First 1
        if (-not $entry) {
            Write-Host "❌ No setting '$Which'. Options: $($opts.Key -join ', ')" -ForegroundColor Red
            return
        }
    }
    else {
        # Can't run the menu (redirected either way, or no fzf) → print the list and bail.
        if (-not $canPrompt -or -not $haveFzf) {
            Write-Host ""
            # Example uses hostname on purpose: without fzf only the text/toggle settings
            # (hostname, ntp) can be changed — the list ones need fzf to pick from.
            Write-Host "⚙️  System settings — pass one to change it (e.g. pwsh-config hostname):" -ForegroundColor Cyan
            $w = ($opts.Key | Measure-Object -Maximum Length).Maximum + 2
            foreach ($o in $opts) {
                Write-Host ("  {0}" -f $o.Key.PadRight($w)) -NoNewline -ForegroundColor Green
                Write-Host ("{0,-20} " -f $o.Label) -NoNewline -ForegroundColor White
                Write-Host $o.Current -ForegroundColor DarkGray
            }
            Write-Host ""
            return
        }

        $lines = $opts | ForEach-Object { "{0}`t{1}`t{2}" -f $_.Key, $_.Label, $_.Current }
        $sel = $lines | fzf `
            --delimiter "`t" --with-nth '2,3' `
            --reverse --border=rounded --height=45% `
            --prompt="⚙️  Configure: " `
            --header="Pick a setting to change · Esc cancels" --header-first `
            --color="header:bold:cyan,prompt:bold:green,border:cyan"
        if (-not $sel) { Write-Host "❌ Cancelled" -ForegroundColor DarkGray; return }
        $entry = $opts | Where-Object Key -eq (($sel -split "`t")[0]) | Select-Object -First 1
    }

    # ── change it, by kind ────────────────────────────────────────────────────
    Write-Host ""
    Write-Host "$($entry.Label) — currently: " -NoNewline -ForegroundColor Cyan
    Write-Host $entry.Current -ForegroundColor Yellow

    # Reached here via `pwsh-config <name>` with no usable terminal: show the value, but
    # every way to change it (prompt, toggle, fzf) needs a tty — so say so, don't dead-end.
    if (-not $canPrompt) {
        Write-Host "   (run pwsh-config in an interactive shell to change it)" -ForegroundColor DarkGray
        return
    }

    switch ($entry.Kind) {
        'toggle' {
            $isOn = $entry.Current -in @('on', 'yes', 'true', 'active')
            $new  = if ($isOn) { 'false' } else { 'true' }   # systemd wants true/false
            $verb = if ($isOn) { 'OFF' } else { 'ON' }
            if ((Read-Host "   Turn it $verb? [y/N]") -notin @('y', 'Y')) { Write-Host "❌ Unchanged." -ForegroundColor Yellow; return }
            # Report in the same on/off vocabulary as the prompt, not systemd's true/false.
            Complete-SysConfigChange $entry $new -Display $(if ($isOn) { 'off' } else { 'on' })
        }
        'text' {
            $val = (Read-Host "   New $($entry.Label)").Trim()
            if (-not $val) { Write-Host "❌ Unchanged." -ForegroundColor Yellow; return }
            Complete-SysConfigChange $entry $val
        }
        default {
            # 'list' — fzf over the choices, current value pre-filled as the query.
            if (-not $haveFzf) {
                Write-Host "   Install fzf to pick from the list, or set it directly with the real command." -ForegroundColor DarkGray
                return
            }
            $choices = @(Get-SysConfigChoices -Key $entry.Key)
            if ($choices.Count -eq 0) {
                # Per-setting hint — "are locales generated?" is wrong for a keyboard problem.
                $why = switch ($entry.Key) {
                    'locale'   { 'no locales are generated — add lines to /etc/locale.gen, then run `sudo locale-gen`' }
                    'keyboard' { 'this system exposes no keyboard layouts (try `sudo apt install console-setup xkb-data`, or `kbd` on Fedora/Arch)' }
                    default    { "localectl returned nothing for $($entry.Key)" }
                }
                Write-Host "❌ No choices available — $why." -ForegroundColor Red
                return
            }
            $val = $choices | fzf `
                --query $entry.Current --reverse --border=rounded --height=60% `
                --prompt="$($entry.Label): " `
                --header="$($choices.Count) options · type to filter · Enter to apply · Esc cancels" --header-first `
                --color="header:bold:cyan,prompt:bold:green,border:cyan"
            if (-not $val) { Write-Host "❌ Cancelled" -ForegroundColor DarkGray; return }
            Complete-SysConfigChange $entry $val.Trim()
        }
    }
}

# Apply one change and report the result (with sudo handled in the adapter). $Display is
# what the user sees (defaults to $Value); it lets a toggle send systemd 'true'/'false'
# while showing 'on'/'off', so the confirmation matches the prompt's vocabulary.
function Complete-SysConfigChange {
    param($Entry, [string]$Value, [string]$Display = $Value)
    Write-Host "🔧 Setting $($Entry.Label) → $Display ..." -ForegroundColor DarkGray
    if (Set-SysConfig -Key $Entry.Key -Value $Value) {
        Write-Host "✅ $($Entry.Label) is now: $Display" -ForegroundColor Green
        if ($Entry.Key -eq 'keyboard') {
            Write-Host "   (affects the console/VC keymap; a graphical session may need X11 layout too)" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "❌ Could not apply the change (permission denied, or an invalid value)." -ForegroundColor Red
    }
}

# ── pwsh-h registration ───────────────────────────────────────────────────────
Register-PFCommand -Name 'pwsh-config' -Platform 'Linux' -Section '⚙️ CONFIGURATION & SETTINGS' -Synopsis 'menu to change OS settings: keyboard, timezone, locale, hostname, time-sync' -Example 'pwsh-config · pwsh-config kb'
