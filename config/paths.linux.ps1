# ==============================================================================
# PowerFlow — Paths (Linux)
# ==============================================================================
# Domain   : Config
# File     : config/paths.linux.ps1
# Purpose  : Configure PATH, initialise Starship and Zoxide, auto-navigate to Code
# Functions: (none — initialisation statements only)
# Depends  : Get-PowerFlowConfigPath (platform/linux/adapters/locations.ps1)
# ==============================================================================

# ~/.local/bin is where the starship/zoxide install scripts drop binaries, and it
# is not always on PATH in a non-login shell.
$localBin = Join-Path $HOME '.local/bin'
if ((Test-Path $localBin) -and ($env:PATH -split ':' -notcontains $localBin)) {
    $env:PATH = "$env:PATH:$localBin"
}

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
