# ==============================================================================
# PowerFlow — Paths (Windows)
# ==============================================================================
# Domain   : Config
# File     : config/paths.windows.ps1
# Purpose  : Configure PATH, initialise Starship and Zoxide, auto-navigate to Code
# Functions: Initialize-PFScoopPath
# Depends  : loaded after platform adapters, before components
# ==============================================================================

# ------------------------------------------------------------------------------
# Scoop shims on PATH
# ------------------------------------------------------------------------------
# READ $env:SCOOP. NEVER WRITE IT.
#
# Scoop's root is relocatable — its installer takes -ScoopDir, and the chosen root is
# persisted as the SCOOP environment variable at User scope. Both adapters already
# honour that (platform/windows/adapters/packages.ps1 and .../apps.ps1 read $env:SCOOP
# with a fallback). This file was the one place that ASSIGNED it, and so undid them.
#
# What the old two lines did, measured in an isolated `pwsh -NoProfile`:
#
#   PATH contains D:\DevTools\Scoop\shims   SCOOP=D:\DevTools\Scoop  -> kept   (by luck)
#   root relocated to a folder NOT named
#     "scoop", e.g. D:\DevTools\Tools       SCOOP=D:\DevTools\Tools  -> CLOBBERED to C:
#   root relocated, PATH not yet propagated SCOOP=D:\DevTools\Scoop  -> CLOBBERED to C:
#   unrelated D:\Projects\scooper\bin       SCOOP=(unset)            -> left EMPTY, no shims
#
# Only the first case survived, and only because the folder happened to be called
# "scoop" — the guard was `-not ($env:PATH -like "*scoop*")`, a substring test against
# the WHOLE of PATH. So the shell silently repointed at a C: path that did not exist,
# and every scoop-managed tool (git, fzf, starship, lsd, zoxide) became unreachable.
#
# The shim directory is only added when it actually exists: a non-existent entry on
# PATH buys nothing, and a fresh install has no shims yet. That case is already covered
# — Initialize-Dependencies bootstraps Scoop and Add-ScoopShimToCurrentPath activates
# the shims inside the same session.
#
# This resolution is deliberately inline rather than a shared adapter call. config/ is
# scanned by the adapter-parity gate exactly like components/, so calling a Windows-only
# adapter function from here would make that name part of the cross-platform contract
# and fail the release for want of a Linux twin. A shared root contract belongs with the
# install-time placement work, where Linux has something real to say.
# ------------------------------------------------------------------------------
function Initialize-PFScoopPath {
    $scoopRoot = if ($env:SCOOP) { $env:SCOOP } else { Join-Path $HOME 'scoop' }
    $shims     = Join-Path $scoopRoot 'shims'
    if (-not (Test-Path -LiteralPath $shims)) {
        Write-Verbose "🛠 Scoop shims not present yet: $shims"
        return
    }

    # Exact entry match, not a substring scan of the whole PATH.
    $already = @($env:PATH -split ';' | Where-Object { $_ } | Where-Object {
        [string]::Equals($_.TrimEnd('\'), $shims.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)
    })
    if (-not $already.Count) { $env:PATH += ";$shims" }

    Write-Verbose "🛠 Scoop shims on PATH: $shims"
}
Initialize-PFScoopPath

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
