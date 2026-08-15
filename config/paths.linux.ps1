# ==============================================================================
# PowerFlow — Paths (Linux)
# ==============================================================================
# Domain   : Config
# File     : config/paths.linux.ps1
# Purpose  : Configure PATH, initialise Starship and Zoxide, auto-navigate to Code
# Functions: (none — initialisation statements only)
# Depends  : Get-PowerFlowConfigPath (platform/linux/adapters/locations.ps1)
# ==============================================================================

# ══════════════════════════════════════════════════════════════════════════════
#  APPENDING TO PATH: always use ${env:PATH}, never "$env:PATH:..."
# ══════════════════════════════════════════════════════════════════════════════
# In an interpolated string, a colon after $env:NAME is read as PART OF THE VARIABLE NAME.
# So "$env:PATH:$dir" asks for an environment variable literally called `PATH:` — which does
# not exist, evaluates to empty — and the result is just $dir. Measured:
#
#     $env:PATH = '/usr/bin:/bin'
#     $env:PATH = "$env:PATH:/home/you/.local/bin"
#     $env:PATH   ->   /home/you/.local/bin        <-- everything else is GONE
#
# This is not a hypothetical. The `~/.local/bin` line below shipped in that form, so on any
# Linux box where `~/.local/bin` existed at profile-load time, PowerFlow replaced the whole
# PATH with that one directory. It went unnoticed because the guard only fires when the
# directory exists AND is absent from PATH: on a fresh machine `~/.local/bin` is created by
# the dependency install, which runs LATER in the load than this file, so the very first
# session — the one people test — never triggers it.
#
# `${env:PATH}` braces the name explicitly and is the only form used here.
# Regression: tests/linux/sbin-path.ps1.

# ~/.local/bin is where the starship/zoxide install scripts drop binaries, and it
# is not always on PATH in a non-login shell.
$localBin = Join-Path $HOME '.local/bin'
if ((Test-Path $localBin) -and ($env:PATH -split ':' -notcontains $localBin)) {
    $env:PATH = "${env:PATH}:$localBin"
}

# ── PF-BUG-007: the admin directories ─────────────────────────────────────────
# Reported from a real VM:
#
#     ❯ swapon --show
#     swapon: The term 'swapon' is not recognized as a name of a cmdlet, function,
#             script file, or executable program.
#     ❯ sudo /sbin/swapon --show      # works
#
# `swapon` is not missing; it is in /sbin, which Debian and friends keep OFF a normal
# user's PATH — historically these were "root-only" tools. In bash you rarely notice,
# because `sudo` runs with root's own PATH (secure_path in /etc/sudoers) and finds them.
# In pwsh you DO notice: PowerShell resolves the command name against YOUR PATH before
# sudo is ever executed, so it fails at the resolution step with a message that reads as
# "this tool isn't installed" rather than "it isn't on your PATH".
#
# That misleading error is the actual bug. Most of these tools READ state — swapon --show,
# fdisk -l, blkid, ip, ss — and are exactly what an admin reaches for on a new box.
#
# APPENDED, never prepended: a user's own PATH entries must keep winning, and a directory
# that does not exist is not added. Each is checked so this stays correct on distros that
# merge /sbin into /usr/bin (Arch, recent Fedora), where some of these are symlinks or
# simply absent.
foreach ($adminDir in @('/usr/local/sbin', '/usr/sbin', '/sbin')) {
    if ((Test-Path $adminDir) -and ($env:PATH -split ':' -notcontains $adminDir)) {
        $env:PATH = "${env:PATH}:$adminDir"
    }
}
Remove-Variable adminDir -ErrorAction SilentlyContinue

# PowerFlow-managed persistent PATH entries (written by `set-path`).
# See platform/linux/adapters/env.ps1 — Linux has no registry, so PowerFlow owns
# exactly one file it can safely append to and read back.
$pathFragment = Join-Path (Get-PowerFlowConfigPath) 'path.ps1'
if (Test-Path $pathFragment) { . $pathFragment }

# Starship prompt
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (&starship init powershell)
}

# Zoxide smart navigation
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    $zoxideInit = &zoxide init --hook prompt powershell
    Invoke-Expression ($zoxideInit -join "`n")

    # Remove zoxide's default 'z' alias — components/navigation/nav.ps1 defines its own
    if (Test-Path Alias:\z) { Remove-Item Alias:\z -Force }
}

# Auto-navigate to ~/Code when starting from HOME
if ((Get-Location).Path -eq $HOME) {
    $codeDir = Join-Path $HOME 'Code'
    if (Test-Path $codeDir) {
        Set-Location $codeDir
        Write-Host "🏠 Auto-navigated to ~/Code" -ForegroundColor DarkGray
    }
}
