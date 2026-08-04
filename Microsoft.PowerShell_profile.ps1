# ==============================================================================
# PowerFlow — Bootloader
# ==============================================================================
# Version  : 3.0.0
# Repo     : https://github.com/Syntax-Read3r/powerflow
# Purpose  : Platform-aware bootloader. Detects the OS, loads that platform's
#            adapters, then the shared components, then the platform bindings.
# ==============================================================================
#
# This same file is $PROFILE on BOTH platforms — pwsh looks for
# Microsoft.PowerShell_profile.ps1 on Windows and Linux alike.
#
# Load order matters:
#   1. settings            — script-scoped variables everything else reads
#   2. platform adapters   — MUST precede components; components call them
#   3. platform paths      — PATH, prompt, shell integrations
#   4. components          — shared domain logic (no OS APIs)
#   5. windows-only        — features with no Linux equivalent (WSL)
#   6. platform bindings   — MUST follow components; rebinds command names
#   7. help                — references everything above
# ==============================================================================

$script:PowerFlowRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# ------------------------------------------------------------------------------
# Platform detection
# ------------------------------------------------------------------------------
# CAREFUL: $IsWindows does NOT exist in Windows PowerShell 5.1 — it is $null there,
# which is falsy. A naive `if ($IsWindows)` would classify a 5.1 box as "not
# Windows", the platform layer would never load, and the profile would break for
# every 5.1 user. 5.1 is always Desktop edition and always Windows, so check that
# first. PowerFlow supports 5.1+ (see install.ps1's `#Requires -Version 5.1`).
# ------------------------------------------------------------------------------
$script:PowerFlowOS =
    if ($PSVersionTable.PSEdition -eq 'Desktop') { 'windows' }   # Windows PowerShell 5.1
    elseif ($IsWindows)                          { 'windows' }   # pwsh 6+ on Windows
    elseif ($IsLinux)                            { 'linux' }
    elseif ($IsMacOS)                            { 'macos' }
    else                                         { 'unknown' }

if ($script:PowerFlowOS -eq 'macos') {
    Write-Warning "PowerFlow: macOS is not supported yet. Falling back to the Linux platform layer."
    $script:PowerFlowOS = 'linux'
}
elseif ($script:PowerFlowOS -eq 'unknown') {
    Write-Warning "PowerFlow: could not detect the platform. Aborting profile load."
    return
}

# ------------------------------------------------------------------------------
# Source helpers
# ------------------------------------------------------------------------------
# IMPORTANT: the dot-source (. $_p) happens in the bootloader body, NOT inside a
# function. Dot-sourcing inside a function puts the definitions in that function's
# local scope, which is destroyed on return — every component would vanish.
function _pf_path {
    param([string]$relativePath)
    $fullPath = Join-Path $script:PowerFlowRoot $relativePath
    if (Test-Path $fullPath) { return $fullPath }
    Write-Warning "PowerFlow: component not found: $fullPath"
    return $null
}

# Enumerate every .ps1 under a directory, in stable order.
function _pf_files {
    param([string]$relativeDir)
    $dir = Join-Path $script:PowerFlowRoot $relativeDir
    if (-not (Test-Path $dir)) {
        Write-Warning "PowerFlow: directory not found: $dir"
        return @()
    }
    return @(Get-ChildItem -Path $dir -Filter *.ps1 -File | Sort-Object Name | Select-Object -ExpandProperty FullName)
}

# ------------------------------------------------------------------------------
# 1. Settings
# ------------------------------------------------------------------------------
$_p = _pf_path "config\PowerFlow.settings.ps1"; if ($_p) { . $_p }

# ------------------------------------------------------------------------------
# 2. Platform adapters — MUST load before components
# ------------------------------------------------------------------------------
foreach ($_p in (_pf_files "platform\$script:PowerFlowOS\adapters")) { . $_p }

# ------------------------------------------------------------------------------
# 3. Platform paths — PATH, Starship, zoxide, auto-navigate
# ------------------------------------------------------------------------------
$_p = _pf_path "config\paths.$script:PowerFlowOS.ps1"; if ($_p) { . $_p }

# ------------------------------------------------------------------------------
# 4. Components — shared domain logic (dependency order within each domain)
# ------------------------------------------------------------------------------
$_pf_components = @(
    # registry.ps1 MUST be first — every component registers its commands into it.
    "components\help\registry.ps1"

    "components\core\version.ps1"
    "components\core\dependencies.ps1"
    "components\core\recovery.ps1"

    "components\shared\strings.ps1"

    # Shell: bash builtins PowerShell lacks, plus the Linux teaching layer.
    # lessons.ps1 MUST precede teach.ps1 and brothers.ps1 — both read its data.
    "components\shell\bash-compat.ps1"
    "components\shell\history.ps1"
    "components\shell\lessons.ps1"
    "components\shell\teach.ps1"
    "components\shell\brothers.ps1"

    # roots.ps1 MUST precede nav.ps1 — nav resolves its search roots through it.
    "components\navigation\roots.ps1"
    "components\navigation\bookmarks.ps1"
    "components\navigation\projects.ps1"
    "components\navigation\nav.ps1"
    "components\navigation\directory.ps1"

    "components\files\listing.ps1"
    "components\files\operations.ps1"
    "components\files\rename.ps1"
    "components\files\clipboard.ps1"

    "components\git\remote.ps1"        # Create-RemoteRepository — used by git-a
    "components\git\commit.ps1"
    "components\git\branches.ps1"
    "components\git\rollback.ps1"
    "components\git\interactive.ps1"
    "components\git\version-files.ps1" # Get-ProjectVersion — MUST precede release.ps1
    "components\git\release.ps1"
    "components\git\reset.ps1"

    "components\github\browser.ps1"

    "components\terminal\tabs.ps1"

    "components\projects\create-next.ps1"

    "components\system\config-files.ps1"
    "components\system\shutdown.ps1"
    "components\system\path.ps1"
    "components\system\apps.ps1"
    "components\system\health.ps1"
    "components\system\proxmox.ps1"
    "components\system\team-room.ps1"
    "components\system\fonts.ps1"
    "components\system\login.ps1"
    "components\system\sysconfig.ps1"
    "components\system\startup.ps1"

    "components\network\servers.ps1"
)
foreach ($_c in $_pf_components) {
    $_p = _pf_path $_c; if ($_p) { . $_p }
}

# ------------------------------------------------------------------------------
# 5. Windows-only features (WSL launchers — no Linux equivalent)
# ------------------------------------------------------------------------------
if ($script:PowerFlowOS -eq 'windows') {
    foreach ($_p in (_pf_files "windows-only")) { . $_p }
}

# ------------------------------------------------------------------------------
# 6. Platform bindings — MUST load after components (rebinds command names)
# ------------------------------------------------------------------------------
$_p = _pf_path "platform\$script:PowerFlowOS\bindings.ps1"; if ($_p) { . $_p }

# ------------------------------------------------------------------------------
# 7. Help (last — its text references everything above)
# ------------------------------------------------------------------------------
$_p = _pf_path "components\help\menu.ps1"; if ($_p) { . $_p }

Remove-Variable _p, _c, _pf_components -ErrorAction SilentlyContinue

# ------------------------------------------------------------------------------
# Startup checks (non-blocking, after all components are loaded)
# ------------------------------------------------------------------------------
if ($script:CHECK_PROFILE_UPDATES) { Check-PowerFlowUpdates }
if ($script:CHECK_DEPENDENCIES)    { Initialize-Dependencies }
if ($script:CHECK_UPDATES)         { Check-PowerShellUpdates }

# ------------------------------------------------------------------------------
# Done
# ------------------------------------------------------------------------------
Write-Host "✅ PowerFlow v${script:POWERFLOW_VERSION} loaded" -NoNewline -ForegroundColor Green
Write-Host " ($script:PowerFlowOS)" -NoNewline -ForegroundColor DarkGray
Write-Host ". Type " -NoNewline -ForegroundColor Green
Write-Host "pwsh-h" -NoNewline -ForegroundColor Yellow
Write-Host " for help" -ForegroundColor Green
