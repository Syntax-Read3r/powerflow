# ==============================================================================
# PowerFlow — SSH Server Manager
# ==============================================================================
# Domain   : Network
# File     : components/network/servers.ps1
# Purpose  : Alias-only SSH server management with live online/offline status
# Functions: srv, Test-ServerOnline, Get-PFServers, Save-PFServers,
#            Get-PFServerStatuses, Format-PFServerStatus, Connect-PFServer,
#            Show-PFServerPicker
# Depends  : server-privacy.ps1, Get-HomePath (locations adapter), fzf (optional)
# ==============================================================================
#
# THE STATUS CHECK IS A TCP PROBE OF THE SSH PORT, NOT A PING.
#
# A ping answers "is the machine on?" — but the question being asked is "can I ssh
# in?". Probing the port answers the real question and yields THREE states:
#
#   ✅ online    port accepts connections — ssh will work
#   🟡 no-ssh    host answers ICMP but not the port — machine on, sshd down/blocked
#   ⛔ offline   nothing answers — powered off, or the address is wrong
#
# The middle state is the one a plain ping cannot see, and it changes what you do
# next (restart sshd vs. walk to the power button).
#
# `ssh` itself is NEVER redefined or shadowed — the same principle as the GNU
# coreutils. srv is a named launcher beside the native command.
# ==============================================================================

$script:PFServersFile = Join-Path (Get-HomePath) '.powerflow-servers.json'

function Get-PFServers {
    if (-not (Test-Path $script:PFServersFile)) { return @{} }
    try {
        $raw = Get-Content $script:PFServersFile -Raw | ConvertFrom-Json
        $map = @{}
        foreach ($p in $raw.PSObject.Properties) { $map[$p.Name] = $p.Value }
        return $map
    } catch {
        Write-Warning "srv: could not read $script:PFServersFile"
        return @{}
    }
}

function Save-PFServers {
    param([hashtable]$Servers)
    $Servers | ConvertTo-Json -Depth 3 | Set-Content $script:PFServersFile -Encoding UTF8
}

<#
.SYNOPSIS
    online / no-ssh / offline for one host, in ~1s worst case.
#>
function Test-ServerOnline {
    param(
        [Parameter(Mandatory)][string]$TargetHost,
        [int]$Port = 22,
        [int]$TimeoutMs = 1200
    )

    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $task = $client.ConnectAsync($TargetHost, $Port)
        if ($task.Wait($TimeoutMs) -and $client.Connected) { return 'online' }
    } catch {} finally { $client.Dispose() }

    # Port dead — does the MACHINE answer? (.NET Ping is unprivileged on both platforms.)
    try {
        $ping = [System.Net.NetworkInformation.Ping]::new()
        if ($ping.Send($TargetHost, 800).Status -eq 'Success') { return 'no-ssh' }
    } catch {}

    return 'offline'
}

# Status for every server AT ONCE — one offline server must not add its timeout to
# the next. ForEach-Object -Parallel cannot see local functions, so the probe is
# inlined; keep it in sync with Test-ServerOnline above.
function Get-PFServerStatuses {
    param([hashtable]$Servers)

    $jobs = $Servers.GetEnumerator() | ForEach-Object {
        [pscustomobject]@{ Name = $_.Key; TargetHost = $_.Value.host; Port = [int]$_.Value.port }
    }

    $results = $jobs | ForEach-Object -ThrottleLimit 8 -Parallel {
        $state  = 'offline'
        $client = [System.Net.Sockets.TcpClient]::new()
        try {
            $task = $client.ConnectAsync($_.TargetHost, $_.Port)
            if ($task.Wait(1200) -and $client.Connected) { $state = 'online' }
        } catch {} finally { $client.Dispose() }
        if ($state -ne 'online') {
            try {
                $ping = [System.Net.NetworkInformation.Ping]::new()
                if ($ping.Send($_.TargetHost, 800).Status -eq 'Success') { $state = 'no-ssh' }
            } catch {}
        }
        [pscustomobject]@{ Name = $_.Name; State = $state }
    }

    $map = @{}
    foreach ($r in $results) { $map[$r.Name] = $r.State }
    return $map
}

function Format-PFServerStatus {
    param([string]$State, $Server)
    switch ($State) {
        'online'  { '✅ online' }
        'no-ssh'  { '🟡 host up, ssh not answering' }
        default   {
            $seen = if ($Server.lastSeen) {
                try { ' · last seen ' + ([datetime]$Server.lastSeen).ToString('MMM d') } catch { '' }
            } else { '' }
            "⛔ offline$seen"
        }
    }
}

function Connect-PFServer {
    param([string]$Name, $Server)

    if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
        Write-Host "❌ No ssh client on this machine." -ForegroundColor Red
        if ($script:PowerFlowOS -eq 'windows') {
            Write-Host "   Install it:  Settings → Optional features → OpenSSH Client" -ForegroundColor DarkGray
        } else {
            Write-Host "   Install it:  sudo apt install openssh-client" -ForegroundColor DarkGray
        }
        return
    }

    # Reaching this point means the caller saw it online (or chose to try anyway) —
    # record the sighting either way; a successful ssh will prove it shortly.
    $servers = Get-PFServers
    if ($servers[$Name]) {
        $servers[$Name] | Add-Member -NotePropertyName lastSeen -NotePropertyValue (Get-Date).ToString('o') -Force
        Save-PFServers $servers
    }

    Invoke-PFServerSsh -Server $Server | Out-Null
}

<#
.SYNOPSIS
    srv — named SSH connections, with live status.
.DESCRIPTION
    srv                          pick a server (fzf, online-first) and connect
    srv <name>                   connect by name; warns first if it looks offline
    srv <name> info              authenticate, then show the saved SSH endpoint
    srv add <name> <user@host>   save a connection — tested before saving
    srv add <name> <user@host:2222>   non-standard port
    srv rm <name> [-f]           forget a connection
    srv rename <old> <new>       rename — history and status travel with it
    srv list                     every server with its status

    Inside the picker:  Enter connects · ctrl-d deletes · ctrl-r renames
.EXAMPLE
    srv add proxmox you@192.168.1.50
    srv proxmox
#>
function srv {
    param(
        [string]$Command,
        [string]$Param1,
        [string]$Param2,
        [switch]$f
    )

    $servers = Get-PFServers

    switch ($Command) {
        'add' {
            $name = $Param1; $target = $Param2
            if (-not $name -or -not $target) {
                Write-Host "❌ Usage:  srv add <name> <user@host[:port]>" -ForegroundColor Red
                Write-Host "   e.g.    srv add proxmox you@192.168.1.50" -ForegroundColor DarkGray
                return
            }
            if ($name -in @('add', 'rm', 'remove', 'list', 'ls', 'help')) {
                Write-Host "❌ '$name' is a srv subcommand — pick another name." -ForegroundColor Red
                return
            }
            if ($name -cnotmatch '^[a-z0-9][\w-]*$') {
                Write-Host "❌ Server names are lowercase: letters, digits, dashes. Try '$($name.ToLower())'." -ForegroundColor Red
                return
            }
            if ($target -notmatch '^([^@\s]+)@([^@:\s]+)(?::(\d+))?$') {
                Write-Host '❌ Expected: user@host[:port].' -ForegroundColor Red
                return
            }
            $user = $matches[1]; $addr = $matches[2]
            $port = if ($matches[3]) { [int]$matches[3] } else { 22 }

            if ($servers.ContainsKey($name) -and -not $f) {
                Write-Host "❌ '$name' already exists." -ForegroundColor Red
                Write-Host "   Replace it:  srv add $name <user@host[:port]> -f" -ForegroundColor DarkGray
                return
            }

            # THE PING TEST THE USER ASKED FOR — but probing the ssh port, which is
            # the thing that actually matters, with ICMP only as the tiebreaker.
            Write-Host "🔎 Testing SSH reachability for '$name' ..." -ForegroundColor DarkGray
            $state = Test-ServerOnline -TargetHost $addr -Port $port

            if ($state -ne 'online') {
                $why = if ($state -eq 'no-ssh') {
                    'the host answers ping, but its SSH service is not accepting connections'
                } else {
                    "nothing answers at all — powered off, or the address is mistyped"
                }
                Write-Host "⚠️  '$name' is not reachable: $why" -ForegroundColor Yellow

                # A dead address is EXACTLY what this test exists to catch — but a
                # powered-off server is legitimate to save. Ask. Unless nobody can
                # answer (piped stdin), in which case refuse rather than guess.
                if ([Console]::IsInputRedirected) {
                    Write-Host "❌ Not saved (no terminal to confirm on). Re-run interactively, or when the server is up." -ForegroundColor Red
                    return
                }
                if ((Read-Host "   Save it anyway? [y/N]") -notin @('y', 'Y')) {
                    Write-Host "❌ Not saved." -ForegroundColor Yellow
                    return
                }
            }

            $servers[$name] = [pscustomobject]@{
                host    = $addr
                user    = $user
                port    = $port
                addedAt = (Get-Date).ToString('o')
                lastSeen = if ($state -eq 'online') { (Get-Date).ToString('o') } else { $null }
            }
            Save-PFServers $servers
            $badge = Format-PFServerStatus $state $servers[$name]
            Write-Host "✅ Saved: $name   $badge" -ForegroundColor Green
            Write-Host "   Connect any time:  srv $name" -ForegroundColor Cyan
            return
        }

        { $_ -in 'rm', 'remove' } {
            $name = $Param1
            if (-not $name -or -not $servers.ContainsKey($name)) {
                Write-Host "❌ No server called '$name'.  srv list" -ForegroundColor Red
                return
            }
            if (-not $f) {
                if ([Console]::IsInputRedirected) {
                    Write-Host "❌ Refusing to delete without confirmation on a piped stdin — use:  srv rm $name -f" -ForegroundColor Red
                    return
                }
                if ((Read-Host "Forget '$name'? [y/N]") -notin @('y', 'Y')) {
                    Write-Host "❌ Kept." -ForegroundColor Yellow
                    return
                }
            }
            $servers.Remove($name)
            Save-PFServers $servers
            Write-Host "✅ Forgotten: $name" -ForegroundColor Green
            return
        }

        'rename' {
            $old = $Param1; $new = $Param2
            if (-not $old -or -not $new) {
                Write-Host "❌ Usage:  srv rename <old> <new>" -ForegroundColor Red
                return
            }
            if (-not $servers.ContainsKey($old)) {
                Write-Host "❌ No server called '$old'.  srv list" -ForegroundColor Red
                return
            }
            if ($servers.ContainsKey($new)) {
                Write-Host "❌ '$new' already exists." -ForegroundColor Red
                return
            }
            if ($new -in @('add', 'rm', 'remove', 'rename', 'list', 'ls', 'help') -or $new -cnotmatch '^[a-z0-9][\w-]*$') {
                Write-Host "❌ Names are lowercase letters, digits, dashes — and not a srv subcommand." -ForegroundColor Red
                return
            }
            # Re-key only. The record — host, port, addedAt, lastSeen — travels intact,
            # which is the whole reason rename exists instead of rm + add.
            $servers[$new] = $servers[$old]
            $servers.Remove($old)
            Save-PFServers $servers
            Write-Host "✅ $old → $new" -ForegroundColor Green
            return
        }

        { $_ -in 'list', 'ls' } {
            if ($servers.Count -eq 0) {
                Write-Host "ℹ️  No servers yet.  srv add <name> <user@host>" -ForegroundColor DarkGray
                return
            }
            Write-Host ""
            Write-Host "🌐 Servers" -ForegroundColor Cyan
            $statuses = Get-PFServerStatuses $servers
            $w = ($servers.Keys | Measure-Object -Maximum Length).Maximum + 2
            foreach ($e in ($servers.GetEnumerator() | Sort-Object Key)) {
                $s = $e.Value
                Write-Host ("  {0}" -f $e.Key.PadRight($w)) -NoNewline -ForegroundColor Green
                Write-Host (Format-PFServerStatus $statuses[$e.Key] $s) -ForegroundColor $(switch ($statuses[$e.Key]) { 'online' { 'Green' } 'no-ssh' { 'Yellow' } default { 'DarkGray' } })
            }
            Write-Host ""
            return
        }
    }

    # ── srv <name>: connect by name ───────────────────────────────────────────
    if ($Command) {
        if (-not $servers.ContainsKey($Command)) {
            Write-Host "❌ No server called '$Command'." -ForegroundColor Red
            Write-Host "   srv list   ·   srv add $Command <user@host>" -ForegroundColor DarkGray
            return
        }
        $s = $servers[$Command]
        $state = Test-ServerOnline -TargetHost $s.host -Port ([int]$s.port)

        if ($Param1 -eq 'info') {
            if ($Param2) {
                Write-Host "❌ Usage:  srv $Command info" -ForegroundColor Red
                return
            }
            Show-PFServerAuthenticatedInfo -Name $Command -Server $s -State $state
            return
        }
        if ($Param1) {
            Write-Host "❌ Unknown action '$Param1'. Use: srv $Command  or  srv $Command info" -ForegroundColor Red
            return
        }

        if ($state -ne 'online') {
            Write-Host "⛔ $Command looks $(if ($state -eq 'no-ssh') { 'up, but ssh is not answering' } else { 'offline' })." -ForegroundColor Yellow
            if ($state -eq 'no-ssh') {
                Write-Host "   The machine responds — sshd may be down or the port blocked." -ForegroundColor DarkGray
            } else {
                Write-Host "   It may need turning on. $(Format-PFServerStatus 'offline' $s)" -ForegroundColor DarkGray
            }
            if ([Console]::IsInputRedirected) { return }
            if ((Read-Host "   Try to connect anyway? [y/N]") -notin @('y', 'Y')) { return }
        }
        Connect-PFServer $Command $s
        return
    }

    # ── bare srv: the picker ──────────────────────────────────────────────────
    if ($servers.Count -eq 0) {
        Write-Host "ℹ️  No servers yet." -ForegroundColor DarkGray
        Write-Host "   srv add proxmox you@192.168.1.50" -ForegroundColor Cyan
        return
    }

    # No terminal or no fzf → the list IS the answer.
    if ([Console]::IsOutputRedirected -or -not (Get-Command fzf -ErrorAction SilentlyContinue)) {
        srv list
        return
    }

    Show-PFServerPicker
}

# The picker is a MANAGER, not just a launcher: Enter connects, ctrl-d deletes,
# ctrl-r renames — fzf's --expect reports which key ended the selection, and after a
# delete or rename the picker reopens with fresh statuses.
function Show-PFServerPicker {
    while ($true) {
        $servers = Get-PFServers
        if ($servers.Count -eq 0) { Write-Host "ℹ️  No servers left.  srv add <name> <user@host>" -ForegroundColor DarkGray; return }

        $statuses = Get-PFServerStatuses $servers
        $rank = @{ online = 0; 'no-ssh' = 1; offline = 2 }
        $lines = $servers.GetEnumerator() |
            Sort-Object { $rank[$statuses[$_.Key]] }, Key |
            ForEach-Object {
                $s = $_.Value
                Format-PFServerPublicRow -Name $_.Key -State $statuses[$_.Key] -Server $s
            }

        # --expect makes fzf's FIRST output line the key that was pressed ('' = Enter),
        # and the SECOND the selection.
        $out = @($lines | fzf `
            --expect=ctrl-d,ctrl-r `
            --delimiter "`t" `
            --reverse --border=rounded --height=40% `
            --prompt="🌐 Connect: " `
            --header="Enter connect · ctrl-d delete · ctrl-r rename · Esc close" `
            --header-first `
            --color="header:bold:cyan,prompt:bold:green,border:cyan")

        if ($out.Count -lt 2) { return }   # Esc / nothing picked
        $key  = $out[0]
        $name = ($out[1] -split "`t")[0]

        switch ($key) {
            'ctrl-d' {
                if ((Read-Host "🗑️  Forget '$name'? [y/N]") -in @('y', 'Y')) {
                    srv rm $name -f
                }
                continue   # back to the picker with fresh state
            }
            'ctrl-r' {
                $new = Read-Host "✏️  New name for '$name'"
                if ($new) { srv rename $name $new }
                continue
            }
            default {
                if ($statuses[$name] -ne 'online') {
                    Write-Host "⛔ $name is $(if ($statuses[$name] -eq 'no-ssh') { 'up, but ssh is not answering' } else { 'offline — it may need turning on' })." -ForegroundColor Yellow
                    if ((Read-Host "   Try to connect anyway? [y/N]") -notin @('y', 'Y')) { return }
                }
                Connect-PFServer $name $servers[$name]
                return
            }
        }
    }
}

# ── pwsh-h registration ───────────────────────────────────────────────────────
Register-PFCommand -Name 'srv'        -Section '🌐 SSH SERVERS' -Synopsis 'private alias/status picker; Enter connects' -Example 'srv · srv proxmox'
Register-PFCommand -Name 'srv info'   -Section '🌐 SSH SERVERS' -Synopsis 'authenticate, then reveal one saved SSH endpoint' -Example 'srv proxmox info'
Register-PFCommand -Name 'srv add'    -Section '🌐 SSH SERVERS' -Synopsis 'save a connection by name - tested before saving' -Example 'srv add proxmox you@192.168.1.50'
Register-PFCommand -Name 'srv rm'     -Section '🌐 SSH SERVERS' -Synopsis 'forget a connection (-f skips the confirm)'
Register-PFCommand -Name 'srv rename' -Section '🌐 SSH SERVERS' -Synopsis 'rename a server - history and status travel with it' -Example 'srv rename lab proxmox'
Register-PFCommand -Name 'srv list'   -Section '🌐 SSH SERVERS' -Synopsis 'server aliases with online / ssh-down / offline status'
