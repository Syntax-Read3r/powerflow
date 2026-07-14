# ==============================================================================
# PowerFlow — Terminal Adapter (Windows)
# ==============================================================================
# Domain   : Platform / Windows
# File     : platform/windows/adapters/terminal.ps1
# Purpose  : Windows Terminal tab management via `wt` and SendKeys automation
# Contract : Test-TerminalSupport, Get-TerminalName, New-TerminalTab,
#            Send-TerminalKeys, Switch-TerminalTab, Close-TerminalTabAt
# Depends  : Copy-ToClipboard (platform/windows/adapters/clipboard.ps1)
# ==============================================================================

# SendKeys lives in Windows Forms — Windows-only, so it is loaded here in the
# adapter rather than in a shared component.
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

function Get-TerminalName { return 'Windows Terminal' }

function Test-TerminalSupport {
    return [bool](Get-Command wt -ErrorAction SilentlyContinue)
}

function Send-TerminalKeys {
    param([Parameter(Mandatory)][string]$Keys)
    [System.Windows.Forms.SendKeys]::SendWait($Keys)
}

# Translate a Windows path to its WSL /mnt/<drive>/... equivalent.
function ConvertTo-WslPath {
    param([Parameter(Mandatory)][string]$Path)
    $drive = $Path.Substring(0, 1).ToLower()
    $rest  = $Path.Substring(3) -replace '\\', '/'
    return "/mnt/$drive/$rest"
}

# Open a new terminal tab running $Shell, starting in $Path.
# Supported shells: pwsh | cmd | wsl (ubuntu/u/bash) | default
function New-TerminalTab {
    param(
        [string]$Shell = 'pwsh',
        [string]$Path  = (Get-Location).Path
    )

    switch ($Shell.ToLower()) {
        { $_ -in @('ubuntu', 'u', 'wsl', 'bash') } {
            Write-Host "🐧 Opening Ubuntu WSL tab..." -ForegroundColor Cyan
            $success = $false

            # Method 1: exact profile GUID (most reliable)
            try {
                Start-Process "wt" -ArgumentList "-w", "0", "nt", "-p", "{07b52e3e-de2c-5db4-bd2d-ba144ed6c273}" -NoNewWindow
                Write-Host "✅ Opened Ubuntu-20.04 tab by GUID" -ForegroundColor Green
                $success = $true
            } catch { }

            # Method 2 / 3: by profile name
            if (-not $success) {
                foreach ($profileName in @('Ubuntu-20.04', 'Ubuntu 20.04.6 LTS', 'Ubuntu')) {
                    try {
                        Start-Process "wt" -ArgumentList "-w", "0", "nt", "-p", $profileName -NoNewWindow
                        Write-Host "✅ Opened with profile: $profileName" -ForegroundColor Green
                        $success = $true
                        break
                    } catch { continue }
                }
            }

            if ($success) {
                $wslPath = ConvertTo-WslPath $Path
                Write-Host ""
                Write-Host "📁 To navigate to your current directory, run this in the Ubuntu tab:" -ForegroundColor Yellow
                Write-Host "cd '$wslPath'" -ForegroundColor White
                Copy-ToClipboard "cd '$wslPath'"
                Write-Host "📋 Command copied to clipboard!" -ForegroundColor Green
            }
            else {
                Write-Host "❌ All methods failed. Opening default WSL..." -ForegroundColor Red
                try {
                    Start-Process "wt" -ArgumentList "-w", "0", "nt", "wsl" -NoNewWindow
                    Write-Host "⚠️  Opened default WSL instead" -ForegroundColor Yellow
                } catch {
                    Write-Host "❌ Even default WSL failed" -ForegroundColor Red
                }
            }
            return $success
        }

        { $_ -in @('pwsh', 'powershell', 'ps') } {
            wt -w 0 nt -p "PowerShell" --startingDirectory "$Path"
            Write-Host "💻 Opened new PowerShell tab in: $Path" -ForegroundColor Green
            return $true
        }

        { $_ -in @('cmd', 'command') } {
            wt -w 0 nt -p "Command Prompt" --startingDirectory "$Path"
            Write-Host "⚡ Opened new Command Prompt tab in: $Path" -ForegroundColor Green
            return $true
        }

        default {
            wt -w 0 nt --startingDirectory "$Path"
            Write-Host "🆕 Opened new tab in: $Path" -ForegroundColor Green
            return $true
        }
    }
}

# Switch tabs. -Index 1..9 jumps to that tab; -Direction Next/Prev cycles.
function Switch-TerminalTab {
    param(
        [int]$Index,
        [ValidateSet('Next', 'Prev')][string]$Direction
    )

    if ($Direction -eq 'Next') { Send-TerminalKeys "^{TAB}";  return $true }
    if ($Direction -eq 'Prev') { Send-TerminalKeys "^+{TAB}"; return $true }

    Send-TerminalKeys "%$Index"   # Alt+N
    return $true
}

# Switch to tab $Index, then close it.
function Close-TerminalTabAt {
    param([Parameter(Mandatory)][int]$Index)

    Send-TerminalKeys "%$Index"
    Start-Sleep -Milliseconds 100
    Send-TerminalKeys "^+w"
    return $true
}
