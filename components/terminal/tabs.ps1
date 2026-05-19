# ==============================================================================
# PowerFlow — Windows Terminal Tab Management
# ==============================================================================
# Domain   : Terminal
# File     : components/terminal/tabs.ps1
# Purpose  : Open, close, and navigate Windows Terminal tabs using SendKeys automation
# Functions: send-keys, open-nt, close-ct, next-t, prev-t, open-t, close-t
# Depends  : none
# ==============================================================================

# Load Windows Forms for SendKeys functionality
Add-Type -AssemblyName System.Windows.Forms

function send-keys {
    param([string]$keys)
    [System.Windows.Forms.SendKeys]::SendWait($keys)
}

function open-nt {
    param(
        [string]$Shell = "pwsh"
    )

    $cwd = Get-Location
    $currentPath = $cwd.Path

    switch ($Shell.ToLower()) {
        { $_ -in @("ubuntu", "u", "wsl", "bash") } {
            Write-Host "🐧 Opening Ubuntu WSL tab..." -ForegroundColor Cyan

            $success = $false

            # Method 1: Use the exact profile GUID (most reliable)
            try {
                Write-Host "   Attempting: Ubuntu-20.04 by GUID..." -ForegroundColor DarkGray
                # Using the GUID from your diagnostics: {07b52e3e-de2c-5db4-bd2d-ba144ed6c273}
                Start-Process "wt" -ArgumentList "-w", "0", "nt", "-p", "{07b52e3e-de2c-5db4-bd2d-ba144ed6c273}" -NoNewWindow
                Write-Host "✅ Opened Ubuntu-20.04 tab by GUID" -ForegroundColor Green
                $success = $true
            } catch {
                Write-Host "   GUID method failed: $($_.Exception.Message)" -ForegroundColor Red
            }

            # Method 2: Use exact profile name
            if (-not $success) {
                try {
                    Write-Host "   Attempting: Ubuntu-20.04 by name..." -ForegroundColor DarkGray
                    Start-Process "wt" -ArgumentList "-w", "0", "nt", "-p", "Ubuntu-20.04" -NoNewWindow
                    Write-Host "✅ Opened Ubuntu-20.04 tab by name" -ForegroundColor Green
                    $success = $true
                } catch {
                    Write-Host "   Name method failed: $($_.Exception.Message)" -ForegroundColor Red
                }
            }

            # Method 3: Try other profile names from your diagnostics
            if (-not $success) {
                $profileNames = @("Ubuntu 20.04.6 LTS", "Ubuntu")
                foreach ($profileName in $profileNames) {
                    try {
                        Write-Host "   Attempting: $profileName..." -ForegroundColor DarkGray
                        Start-Process "wt" -ArgumentList "-w", "0", "nt", "-p", $profileName -NoNewWindow
                        Write-Host "✅ Opened with profile: $profileName" -ForegroundColor Green
                        $success = $true
                        break
                    } catch {
                        Write-Host "   Profile '$profileName' failed" -ForegroundColor Red
                        continue
                    }
                }
            }

            # Show navigation instructions
            if ($success) {
                Write-Host ""
                Write-Host "📁 To navigate to your current directory, run this in the Ubuntu tab:" -ForegroundColor Yellow
                $drive = $currentPath.Substring(0,1).ToLower()
                $restOfPath = $currentPath.Substring(3) -replace "\\", "/"
                $wslPath = "/mnt/$drive/$restOfPath"
                Write-Host "cd '$wslPath'" -ForegroundColor White
                Set-Clipboard "cd '$wslPath'"
                Write-Host "📋 Command copied to clipboard!" -ForegroundColor Green
            } else {
                Write-Host "❌ All methods failed. Opening default WSL..." -ForegroundColor Red
                try {
                    Start-Process "wt" -ArgumentList "-w", "0", "nt", "wsl" -NoNewWindow
                    Write-Host "⚠️  Opened default WSL instead" -ForegroundColor Yellow
                } catch {
                    Write-Host "❌ Even default WSL failed" -ForegroundColor Red
                }
            }
        }
        { $_ -in @("pwsh", "powershell", "ps") } {
            wt -w 0 nt -p "PowerShell" --startingDirectory "$currentPath"
            Write-Host "💻 Opened new PowerShell tab in: $currentPath" -ForegroundColor Green
        }
        { $_ -in @("cmd", "command") } {
            wt -w 0 nt -p "Command Prompt" --startingDirectory "$currentPath"
            Write-Host "⚡ Opened new Command Prompt tab in: $currentPath" -ForegroundColor Green
        }
        default {
            wt -w 0 nt --startingDirectory "$currentPath"
            Write-Host "🆕 Opened new tab in: $currentPath" -ForegroundColor Green
        }
    }
}

function close-ct { exit }

function next-t {
    send-keys "^{TAB}"
    Write-Host "➡️ Switched to next tab" -ForegroundColor Cyan
}

function prev-t {
    send-keys "^+{TAB}"
    Write-Host "⬅️ Switched to previous tab" -ForegroundColor Cyan
}

function open-t {
    param([int]$index)
    if ($index -lt 1 -or $index -gt 9) {
        Write-Host "❌ Tab index must be between 1–9" -ForegroundColor Red
        return
    }
    send-keys "%$index"  # Alt+Number shortcut
    Write-Host "🔀 Switched to tab $index" -ForegroundColor Cyan
}

function close-t {
    param([int]$index)
    if ($index -lt 1 -or $index -gt 9) {
        Write-Host "❌ Tab index must be between 1–9" -ForegroundColor Red
        return
    }
    send-keys "%$index"                # Switch to tab
    Start-Sleep -Milliseconds 100      # Brief pause
    send-keys "^+w"                    # Close tab shortcut
    Write-Host "🗑 Closed tab $index" -ForegroundColor Yellow
}
