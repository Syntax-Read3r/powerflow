# ==============================================================================
# PowerFlow — Startup Entries Adapter (Linux)
# ==============================================================================
# Domain   : Platform / Linux
# File     : platform/linux/adapters/startup.ps1
# Purpose  : Enumerate and manage what runs at login — XDG autostart .desktop files
#            — for the start-folder command
# Contract : Get-StartupEntry, Set-StartupEntryState, Remove-StartupEntry,
#            Add-StartupEntry, Get-StartupFolderPath
# Depends  : Get-XdgConfigHome (locations.ps1)
# ==============================================================================
#
# THE LINUX MODEL
#
# XDG autostart: every .desktop file in ~/.config/autostart (user) or /etc/xdg/autostart
# (system) is launched when a DESKTOP SESSION starts. The user directory shadows the
# system one by filename, which is how a desktop "disables" a system entry — it drops a
# copy carrying Hidden=true.
#
# Hidden=true is the precise analogue of Windows' StartupApproved flag: the entry stays
# on disk, it simply does not run, and flipping it back restores it. That symmetry is why
# start-folder can be one command on both platforms instead of two lookalikes.
#
# WHAT THIS DOES NOT COVER: systemd --user units also start things at login, but they are
# a service manager (dependencies, restart policy, sockets), not a "startup item" list —
# folding them in would mean showing rows this tool must not casually delete. `systemctl
# --user list-unit-files --state=enabled` is the right tool for those, and start-folder
# says so rather than pretending.
#
# NOTE: autostart is a DESKTOP-session mechanism. On a headless server nothing here runs
# at SSH login (that is ~/.profile / systemd), and the component says so.
# ==============================================================================

function Get-StartupFolderPath {
    param([switch]$Machine)
    if ($Machine) { return '/etc/xdg/autostart' }
    return (Join-Path (Get-XdgConfigHome) 'autostart')
}

# Read one key out of a .desktop file. Deliberately simple: the [Desktop Entry] group is
# the only one that matters here, and these files are flat key=value.
function Get-DesktopKey {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Key)
    $line = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue |
            Where-Object { $_ -match "^\s*$Key\s*=" } | Select-Object -First 1
    if (-not $line) { return $null }
    return ($line -split '=', 2)[1].Trim()
}

# Rewrite (or add) a single key, preserving every other line. We do NOT regenerate the
# file: a .desktop can carry translations, actions and vendor keys that matter to the
# desktop environment, and rewriting would silently drop them.
function Set-DesktopKey {
    param([Parameter(Mandatory)][string]$Path,
          [Parameter(Mandatory)][string]$Key,
          [Parameter(Mandatory)][string]$Value)

    $lines = @(Get-Content -LiteralPath $Path -ErrorAction Stop)
    $done  = $false
    $out   = foreach ($l in $lines) {
        if ($l -match "^\s*$Key\s*=") { $done = $true; "$Key=$Value" } else { $l }
    }
    if (-not $done) {
        # Insert into [Desktop Entry] rather than appending, which could land in a later group.
        $idx = [Array]::FindIndex([string[]]$out, [Predicate[string]]{ param($x) $x -match '^\s*\[Desktop Entry\]' })
        if ($idx -ge 0) {
            $out = @($out[0..$idx]) + @("$Key=$Value") + @($out[($idx + 1)..($out.Count - 1)])
        } else {
            $out = @("[Desktop Entry]", "$Key=$Value") + $out
        }
    }
    Set-Content -LiteralPath $Path -Value $out -ErrorAction Stop
}

function Get-StartupEntry {
    $entries = [System.Collections.Generic.List[object]]::new()
    $userDir = Get-StartupFolderPath

    # User entries first, and remember their filenames: a user file SHADOWS the system
    # one of the same name, so the system copy must not also be listed.
    $seen = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($spec in @(
        @{ Dir = $userDir;                          Scope = 'user';    Label = 'autostart (user)' }
        @{ Dir = (Get-StartupFolderPath -Machine);  Scope = 'machine'; Label = 'autostart (system)' }
    )) {
        if (-not $spec.Dir -or -not (Test-Path $spec.Dir)) { continue }
        Get-ChildItem -LiteralPath $spec.Dir -Filter '*.desktop' -File -ErrorAction SilentlyContinue |
            ForEach-Object {
                if ($spec.Scope -eq 'machine' -and $seen.Contains($_.Name)) { return }
                if ($spec.Scope -eq 'user') { [void]$seen.Add($_.Name) }

                $hidden  = Get-DesktopKey -Path $_.FullName -Key 'Hidden'
                $enabled = Get-DesktopKey -Path $_.FullName -Key 'X-GNOME-Autostart-enabled'
                # Hidden=true means "do not run"; GNOME also honours its own key.
                $state = if ($hidden -eq 'true' -or $enabled -eq 'false') { 'disabled' } else { 'enabled' }

                $name = Get-DesktopKey -Path $_.FullName -Key 'Name'
                if (-not $name) { $name = [IO.Path]::GetFileNameWithoutExtension($_.Name) }
                $exec = Get-DesktopKey -Path $_.FullName -Key 'Exec'

                $entries.Add([pscustomobject]@{
                    Name     = $name
                    Source   = $spec.Label
                    Scope    = $spec.Scope
                    State    = $state
                    Command  = $exec
                    Kind     = 'desktop'
                    FilePath = $_.FullName
                    FileName = $_.Name
                })
            }
    }

    return @($entries)
}

# Disable = Hidden=true, exactly what a desktop environment writes. Reversible.
#
# A SYSTEM entry is not edited in place (it is root-owned and package-managed, so an edit
# would be clobbered on upgrade). Instead we do what the desktops do: copy it into the
# user's autostart directory and set the flag there, where it shadows the original.
function Set-StartupEntryState {
    param([Parameter(Mandatory)]$Entry, [Parameter(Mandatory)][bool]$Enabled)

    try {
        $path = $Entry.FilePath
        if ($Entry.Scope -eq 'machine') {
            $userDir = Get-StartupFolderPath
            if (-not (Test-Path $userDir)) { New-Item -ItemType Directory -Path $userDir -Force | Out-Null }
            $path = Join-Path $userDir $Entry.FileName
            if (-not (Test-Path $path)) { Copy-Item -LiteralPath $Entry.FilePath -Destination $path -ErrorAction Stop }
        }
        Set-DesktopKey -Path $path -Key 'Hidden' -Value $(if ($Enabled) { 'false' } else { 'true' })
        # Keep GNOME's key consistent when the file already uses it.
        if ($null -ne (Get-DesktopKey -Path $path -Key 'X-GNOME-Autostart-enabled')) {
            Set-DesktopKey -Path $path -Key 'X-GNOME-Autostart-enabled' -Value $(if ($Enabled) { 'true' } else { 'false' })
        }
        return $true
    } catch {
        Write-Host "   $($_.Exception.Message)" -ForegroundColor DarkGray
        return $false
    }
}

# Only the user's own copy is ever deleted. A system entry belongs to a package; removing
# it would be undone by the next upgrade, so we disable (shadow) it instead.
function Remove-StartupEntry {
    param([Parameter(Mandatory)]$Entry)

    if ($Entry.Scope -eq 'machine') {
        Write-Host "   (system entry — disabling it instead; the package owns the file)" -ForegroundColor DarkGray
        return (Set-StartupEntryState -Entry $Entry -Enabled $false)
    }
    try {
        Remove-Item -LiteralPath $Entry.FilePath -Force -ErrorAction Stop
        return $true
    } catch {
        Write-Host "   $($_.Exception.Message)" -ForegroundColor DarkGray
        return $false
    }
}

function Add-StartupEntry {
    param([Parameter(Mandatory)][string]$Path, [string]$Name)

    $target = $Path
    if (Test-Path -LiteralPath $Path) { $target = (Resolve-Path -LiteralPath $Path).Path }
    if (-not $Name) { $Name = [IO.Path]::GetFileNameWithoutExtension($target) }

    $dir = Get-StartupFolderPath
    try {
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $file = Join-Path $dir ("{0}.desktop" -f ($Name -replace '[^\w.-]', '_'))
        # LF endings and a trailing newline: .desktop is parsed by C libraries that are
        # not tolerant of CRLF, and PowerShell on Windows would otherwise write CRLF.
        $body = @(
            '[Desktop Entry]'
            'Type=Application'
            "Name=$Name"
            "Exec=$target"
            'Terminal=false'
            'X-GNOME-Autostart-enabled=true'
            'Comment=Added by PowerFlow start-folder'
        ) -join "`n"
        [IO.File]::WriteAllText($file, $body + "`n")
        return (Test-Path -LiteralPath $file)
    } catch {
        Write-Host "   $($_.Exception.Message)" -ForegroundColor DarkGray
        return $false
    }
}
