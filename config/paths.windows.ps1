# ==============================================================================
# PowerFlow — Paths (Windows)
# ==============================================================================
# Domain   : Config
# File     : config/paths.windows.ps1
# Purpose  : Configure PATH, initialise Starship and Zoxide, auto-navigate to Code
# Functions: (none — initialisation statements only)
# Depends  : loaded after platform adapters, before components
# ==============================================================================

# Scoop shims on PATH
if (-not ($env:PATH -like "*scoop*")) {
    $env:SCOOP = "$env:USERPROFILE\scoop"
    $env:PATH += ";$env:SCOOP\shims"
    Write-Verbose "🛠 Scoop PATH configured: $env:SCOOP\shims"
}

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
