# ==============================================================================
# PowerFlow — Bootloader
# ==============================================================================
# Version  : 1.0.5
# Repo     : https://github.com/Syntax-Read3r/powerflow
# Purpose  : Thin bootloader that dot-sources all component files in order
# ==============================================================================

# Resolve root path relative to this file so the profile works regardless of
# where $PROFILE points on any machine.
$script:PowerFlowRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Helper: dot-source a component file with error reporting
function _pf_source {
    param([string]$relativePath)
    $fullPath = Join-Path $script:PowerFlowRoot $relativePath
    if (Test-Path $fullPath) {
        . $fullPath
    } else {
        Write-Warning "PowerFlow: component not found: $fullPath"
    }
}

# ------------------------------------------------------------------------------
# 1. Settings & Paths (must load first — other components read these variables)
# ------------------------------------------------------------------------------
_pf_source "config\PowerFlow.settings.ps1"
_pf_source "config\PowerFlow.paths.ps1"

# ------------------------------------------------------------------------------
# 2. Core — version management, dependency checks, recovery
# ------------------------------------------------------------------------------
_pf_source "components\core\version.ps1"
_pf_source "components\core\dependencies.ps1"
_pf_source "components\core\recovery.ps1"

# ------------------------------------------------------------------------------
# 3. Shared utilities (string helpers, aliases used by multiple domains)
# ------------------------------------------------------------------------------
_pf_source "components\shared\strings.ps1"
_pf_source "components\shared\aliases.ps1"

# ------------------------------------------------------------------------------
# 4. Navigation
# ------------------------------------------------------------------------------
_pf_source "components\navigation\bookmarks.ps1"
_pf_source "components\navigation\projects.ps1"
_pf_source "components\navigation\nav.ps1"
_pf_source "components\navigation\directory.ps1"

# ------------------------------------------------------------------------------
# 5. File operations
# ------------------------------------------------------------------------------
_pf_source "components\files\listing.ps1"
_pf_source "components\files\operations.ps1"
_pf_source "components\files\rename.ps1"
_pf_source "components\files\clipboard.ps1"

# ------------------------------------------------------------------------------
# 6. Git workflows
# ------------------------------------------------------------------------------
_pf_source "components\git\remote.ps1"
_pf_source "components\git\commit.ps1"
_pf_source "components\git\branches.ps1"
_pf_source "components\git\rollback.ps1"
_pf_source "components\git\interactive.ps1"
_pf_source "components\git\reset.ps1"

# ------------------------------------------------------------------------------
# 7. GitHub integration
# ------------------------------------------------------------------------------
_pf_source "components\github\browser.ps1"

# ------------------------------------------------------------------------------
# 8. Terminal management
# ------------------------------------------------------------------------------
_pf_source "components\terminal\tabs.ps1"
_pf_source "components\terminal\wsl.ps1"

# ------------------------------------------------------------------------------
# 9. Project generators
# ------------------------------------------------------------------------------
_pf_source "components\projects\create-next.ps1"

# ------------------------------------------------------------------------------
# 10. System utilities
# ------------------------------------------------------------------------------
_pf_source "components\system\config-files.ps1"
_pf_source "components\system\shutdown.ps1"

# ------------------------------------------------------------------------------
# 11. Help system
# ------------------------------------------------------------------------------
_pf_source "components\help\menu.ps1"

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
