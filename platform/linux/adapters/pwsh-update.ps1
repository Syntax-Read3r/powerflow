# ==============================================================================
# PowerFlow — PowerShell Update Adapter (Linux)
# ==============================================================================
# Domain   : Platform / Linux
# File     : platform/linux/adapters/pwsh-update.ps1
# Purpose  : Point the user at the correct upgrade path for how pwsh was installed
# Contract : Invoke-PowerShellUpdate
# Depends  : Get-PackageManagerName (packages.ps1), Open-Url (openers.ps1)
# ==============================================================================
#
# Linux never self-upgrades pwsh behind the user's back. Package managers own the
# binary, and fighting them (as the Windows MSI/winget path has to) causes exactly
# the "conflict" state that adapter exists to repair. So we detect the install
# source, print the one correct command, and let the user run it.
# ==============================================================================

# How was pwsh installed on this box?
function Get-PowerShellInstallMethod {
    if ($PSHOME -like '*/snap/*')      { return 'snap' }
    if (Test-Path '/opt/microsoft/powershell') { return 'package' }   # apt/dnf/zypper
    if ($PSHOME -like '*/.dotnet/*')   { return 'dotnet-tool' }
    return 'unknown'
}

function Get-PowerShellUpdateCommand {
    switch (Get-PowerShellInstallMethod) {
        'snap'        { return 'sudo snap refresh powershell' }
        'dotnet-tool' { return 'dotnet tool update --global PowerShell' }
        'package' {
            switch (Get-PackageManagerName) {
                'apt'    { return 'sudo apt-get update && sudo apt-get install --only-upgrade powershell' }
                'dnf'    { return 'sudo dnf upgrade powershell' }
                'zypper' { return 'sudo zypper update powershell' }
                default  { return 'update the powershell package with your package manager' }
            }
        }
        default { return $null }
    }
}

function Invoke-PowerShellUpdate {
    param(
        [Parameter(Mandatory)]$LatestRelease,
        [Parameter(Mandatory)]$CurrentVersion,
        [Parameter(Mandatory)]$LatestVersion,
        [Parameter(Mandatory)][string]$UpdateCheckFile,
        [Parameter(Mandatory)][string]$Today
    )

    Write-Host "🚀 PowerShell update available: v$CurrentVersion → v$LatestVersion" -ForegroundColor Cyan

    $method  = Get-PowerShellInstallMethod
    $command = Get-PowerShellUpdateCommand

    Write-Host "🔧 Install method: $method" -ForegroundColor Yellow
    Write-Host "📍 Release page: $($LatestRelease.html_url)" -ForegroundColor DarkGray
    Write-Host ""

    if ($command) {
        Write-Host "💡 Update with:" -ForegroundColor Cyan
        Write-Host "   $command" -ForegroundColor White
        if (Test-ClipboardSupport) {
            Copy-ToClipboard $command
            Write-Host "📋 Command copied to clipboard" -ForegroundColor Green
        }
    } else {
        Write-Host "⚠️  Could not determine how pwsh was installed." -ForegroundColor Yellow
        Write-Host "   See: https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux" -ForegroundColor DarkGray
    }

    Write-Host ""
    switch (Read-Host "🔄 (1) Open release page (2) Skip today (3) Disable checks") {
        "1" { Open-Url $LatestRelease.html_url }
        "2" { Write-Host "⏭️  Skipping update check for today" -ForegroundColor Yellow; $Today | Set-Content $UpdateCheckFile }
        "3" {
            Write-Host "🚫 Disabling automatic update checks" -ForegroundColor Yellow
            try {
                $settings = Join-Path $script:PowerFlowRoot 'config/PowerFlow.settings.ps1'
                $content  = Get-Content $settings -Raw
                $updated  = $content -replace '\$script:CHECK_UPDATES = \$true', '$script:CHECK_UPDATES = $false'
                if ($updated -ne $content) {
                    Set-Content $settings $updated
                    Write-Host "✅ Automatic update checks disabled" -ForegroundColor Green
                }
            } catch {
                Write-Host "💡 Edit config/PowerFlow.settings.ps1 and set `$script:CHECK_UPDATES = `$false" -ForegroundColor DarkGray
            }
        }
        default { Write-Host "⏭️  Update check skipped" -ForegroundColor DarkGray }
    }
}
