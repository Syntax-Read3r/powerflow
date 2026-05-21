# ==============================================================================
# PowerFlow — Bootloader
# ==============================================================================
# Version  : 2.0.0
# Repo     : https://github.com/Syntax-Read3r/powerflow
# Purpose  : Thin bootloader that dot-sources all component files in order
# ==============================================================================

# Resolve root path relative to this file so the profile works regardless of
# where $PROFILE points on any machine.
$script:PowerFlowRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Helper: resolve a component path and warn if the file is missing.
# Returns the full path, or $null if not found.
#
# IMPORTANT: the actual dot-source (. $_p) is intentionally done in the
# bootloader body — NOT inside this function.  Dot-sourcing inside a function
# places all definitions in the function's local scope, which is destroyed when
# the function returns, making every component function invisible afterwards.
function _pf_path {
    param([string]$relativePath)
    $fullPath = Join-Path $script:PowerFlowRoot $relativePath
    if (Test-Path $fullPath) { return $fullPath }
    Write-Warning "PowerFlow: component not found: $fullPath"
    return $null
}

# ------------------------------------------------------------------------------
# 1. Settings & Paths (must load first — other components read these variables)
# ------------------------------------------------------------------------------
$_p = _pf_path "config\PowerFlow.settings.ps1"; if ($_p) { . $_p }
$_p = _pf_path "config\PowerFlow.paths.ps1";    if ($_p) { . $_p }

# ------------------------------------------------------------------------------
# 2. Core — version management, dependency checks, recovery
# ------------------------------------------------------------------------------
$_p = _pf_path "components\core\version.ps1";      if ($_p) { . $_p }
$_p = _pf_path "components\core\dependencies.ps1"; if ($_p) { . $_p }
$_p = _pf_path "components\core\recovery.ps1";     if ($_p) { . $_p }

# ------------------------------------------------------------------------------
# 3. Shared utilities (string helpers, aliases used by multiple domains)
# ------------------------------------------------------------------------------
$_p = _pf_path "components\shared\strings.ps1"; if ($_p) { . $_p }
$_p = _pf_path "components\shared\aliases.ps1"; if ($_p) { . $_p }

# ------------------------------------------------------------------------------
# 4. Navigation
# ------------------------------------------------------------------------------
$_p = _pf_path "components\navigation\bookmarks.ps1"; if ($_p) { . $_p }
$_p = _pf_path "components\navigation\projects.ps1";  if ($_p) { . $_p }
$_p = _pf_path "components\navigation\nav.ps1";       if ($_p) { . $_p }
$_p = _pf_path "components\navigation\directory.ps1"; if ($_p) { . $_p }

# ------------------------------------------------------------------------------
# 5. File operations
# ------------------------------------------------------------------------------
$_p = _pf_path "components\files\listing.ps1";    if ($_p) { . $_p }
$_p = _pf_path "components\files\operations.ps1"; if ($_p) { . $_p }
$_p = _pf_path "components\files\rename.ps1";     if ($_p) { . $_p }
$_p = _pf_path "components\files\clipboard.ps1";  if ($_p) { . $_p }

# ------------------------------------------------------------------------------
# 6. Git workflows
# ------------------------------------------------------------------------------
$_p = _pf_path "components\git\remote.ps1";      if ($_p) { . $_p }
$_p = _pf_path "components\git\commit.ps1";      if ($_p) { . $_p }
$_p = _pf_path "components\git\branches.ps1";    if ($_p) { . $_p }
$_p = _pf_path "components\git\rollback.ps1";    if ($_p) { . $_p }
$_p = _pf_path "components\git\interactive.ps1"; if ($_p) { . $_p }
$_p = _pf_path "components\git\release.ps1";     if ($_p) { . $_p }
$_p = _pf_path "components\git\reset.ps1";       if ($_p) { . $_p }

# ------------------------------------------------------------------------------
# 7. GitHub integration
# ------------------------------------------------------------------------------
$_p = _pf_path "components\github\browser.ps1"; if ($_p) { . $_p }

# ------------------------------------------------------------------------------
# 8. Terminal management
# ------------------------------------------------------------------------------
$_p = _pf_path "components\terminal\tabs.ps1"; if ($_p) { . $_p }
$_p = _pf_path "components\terminal\wsl.ps1";  if ($_p) { . $_p }

# ------------------------------------------------------------------------------
# 9. Project generators
# ------------------------------------------------------------------------------
$_p = _pf_path "components\projects\create-next.ps1"; if ($_p) { . $_p }

# ------------------------------------------------------------------------------
# 10. System utilities
# ------------------------------------------------------------------------------
$_p = _pf_path "components\system\config-files.ps1"; if ($_p) { . $_p }
$_p = _pf_path "components\system\shutdown.ps1";     if ($_p) { . $_p }
$_p = _pf_path "components\system\path.ps1";         if ($_p) { . $_p }

# ------------------------------------------------------------------------------
# 11. Help system
# ------------------------------------------------------------------------------
$_p = _pf_path "components\help\menu.ps1"; if ($_p) { . $_p }

# Clean up temp variable
Remove-Variable _p -ErrorAction SilentlyContinue

# ------------------------------------------------------------------------------
# Startup checks (non-blocking, run after all components are loaded)
# ------------------------------------------------------------------------------
if ($script:CHECK_PROFILE_UPDATES) { Check-PowerFlowUpdates }
if ($script:CHECK_DEPENDENCIES)    { Initialize-Dependencies }
if ($script:CHECK_UPDATES)         { Check-PowerShellUpdates }

# ------------------------------------------------------------------------------
# Done
# ------------------------------------------------------------------------------
Write-Host "✅ PowerFlow profile loaded! Type " -NoNewline -ForegroundColor Green
Write-Host "pwsh-h" -NoNewline -ForegroundColor Yellow
Write-Host " for help" -ForegroundColor Green
