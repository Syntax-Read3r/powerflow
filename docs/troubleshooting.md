# 🚨 PowerFlow Troubleshooting Guide

Comprehensive troubleshooting guide for PowerFlow issues. Most problems can be resolved quickly with the solutions below.

## 🔍 Quick Diagnosis

### First Steps for Any Issue
```powershell
# 1. Check PowerFlow version and status
Get-PowerFlowVersion

# 2. Check if all dependencies are available
Get-Command starship, fzf, zoxide, lsd, git -ErrorAction SilentlyContinue

# 3. Test basic functionality
pwsh-h          # Should show help menu
ls              # Should show icons (not squares)
nav list        # Should show bookmark interface

# 4. Check for error messages during profile load
$Error | Select-Object -First 5
```

### Enable Debug Mode
```powershell
# Add to top of profile temporarily for detailed output
$VerbosePreference = "Continue"
$DebugPreference = "Continue"

# Reload profile
. $PROFILE
```

---

## 🚫 Installation Issues

### ❌ "Execution Policy" Error

**Symptoms:**
```
Execution of scripts is disabled on this system
```

**Solutions:**
```powershell
# Solution 1: Enable for current user (recommended)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

# Solution 2: Bypass for single session
powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/Syntax-Read3r/powerflow/main/install.ps1 | iex"

# Solution 3: Check current policy
Get-ExecutionPolicy -List
```

### ❌ "Cannot Download Profile" Error

**Symptoms:**
```
Failed to download profile: The remote server returned an error
```

**Causes & Solutions:**
```powershell
# Cause 1: Network restrictions
# Test connectivity
Test-NetConnection github.com -Port 443

# Cause 2: Corporate firewall
# Use alternative download method
$profileUrl = "https://raw.githubusercontent.com/Syntax-Read3r/powerflow/main/Microsoft.PowerShell_profile.ps1"
Start-Process $profileUrl  # Opens in browser, save manually

# Cause 3: TLS/SSL issues (older PowerShell)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
```

### ❌ "Profile Directory Not Found" Error

**Symptoms:**
```
Could not find part of the path 'Documents\PowerShell'
```

**Solution:**
```powershell
# Create profile directory manually
$profileDir = Split-Path $PROFILE -Parent
New-Item -ItemType Directory -Path $profileDir -Force

# Verify profile path
$PROFILE
```

---

## 🎨 Font and Display Issues

### ❌ Icons Show as Squares or Boxes

**Symptoms:**
- Squares instead of icons: ⬜ ⬜ ⬜
- Missing characters in `ls` output
- Broken starship prompt symbols

**Diagnosis:**
```powershell
# Test icon display
Write-Host "🚀 📁 ✅ 🌿 💻 🔍 🎯 📦 🔄 ⚡"
# Should show clear icons, not squares
```

**Solutions:**

**Step 1: Install FiraCode Nerd Font**
```powershell
# Via Scoop (recommended)
scoop bucket add nerd-fonts
scoop install FiraCode-NF

# Via winget
winget install -e --id "DEVCOM.FiraCodeNerdFont"

# Manual: Download from https://github.com/ryanoasis/nerd-fonts/releases
```

**Step 2: Configure Windows Terminal**
1. Open Windows Terminal
2. Press `Ctrl + ,` (Settings)
3. Go to PowerShell profile → Appearance
4. Set **Font face** to `FiraCode Nerd Font` or `FiraCode NF`
5. Save and restart terminal

**Step 3: Verify Font Installation**
```powershell
# Check if font files exist
Get-ChildItem "$env:WINDIR\Fonts" | Where-Object { $_.Name -like "*FiraCode*" }
Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows\Fonts" | Where-Object { $_.Name -like "*FiraCode*" }
```

### ❌ Colors Look Wrong or Missing

**Symptoms:**
- No colors in output
- All text appears white/black
- Git status colors missing

**Solutions:**
```powershell
# Check if colors are enabled
$PSStyle.OutputRendering
# Should be "Auto" or "Ansi"

# Force enable colors
$PSStyle.OutputRendering = "Ansi"

# Test colors
Write-Host "Red" -ForegroundColor Red
Write-Host "Green" -ForegroundColor Green
Write-Host "Blue" -ForegroundColor Blue
```

---

## 📦 Dependency Issues

### ❌ "Scoop not found" Error

**Symptoms:**
```
scoop : The term 'scoop' is not recognized
```

**Solutions:**
```powershell
# Install Scoop
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression

# Refresh PATH
$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")

# Verify installation
scoop --version
```

### ❌ "fzf/starship/zoxide not found" Errors

**Symptoms:**
```
fzf : The term 'fzf' is not recognized
```

**Diagnosis:**
```powershell
# Check which tools are missing
$tools = @("starship", "fzf", "zoxide", "lsd", "git")
foreach ($tool in $tools) {
    $found = Get-Command $tool -ErrorAction SilentlyContinue
    Write-Host "$tool : $(if ($found) { '✅ Found' } else { '❌ Missing' })"
}
```

**Solutions:**
```powershell
# Install missing tools via Scoop
scoop install starship fzf zoxide lsd git

# Manual installation alternative
# Download from respective GitHub releases pages:
# - Starship: https://github.com/starship/starship/releases
# - fzf: https://github.com/junegunn/fzf/releases
# - zoxide: https://github.com/ajeetdsouza/zoxide/releases
# - lsd: https://github.com/Peltoche/lsd/releases

# Verify PATH includes tool directories
$env:PATH -split ';' | Where-Object { $_ -like "*scoop*" }
```

### ❌ Tools Installed but Not Found

**Symptoms:**
- Scoop shows tools as installed
- Commands still not recognized

**Solutions:**
```powershell
# Refresh PATH environment
$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")

# Check Scoop shim directory
Get-ChildItem "$env:USERPROFILE\scoop\shims" | Where-Object { $_.Name -like "*.exe" }

# Add Scoop to PATH manually if needed
$env:PATH += ";$env:USERPROFILE\scoop\shims"

# Restart PowerShell session
```

---

## ⚡ Performance Issues

### ❌ Profile Loads Slowly

**Symptoms:**
- PowerShell takes 5+ seconds to start
- Long delays when opening new tabs

**Diagnosis:**
```powershell
# Time profile loading
Measure-Command { . $PROFILE }
```

**Solutions:**
```powershell
# Solution 1: Disable dependency checks (if tools already installed)
# Add to top of profile:
$script:CHECK_DEPENDENCIES = $false

# Solution 2: Disable update checks
$script:CHECK_UPDATES = $false
$script:CHECK_PROFILE_UPDATES = $false

# Solution 3: Use async loading (advanced)
# Wrap slow operations in Start-Job for background loading
```

### ❌ Commands Feel Sluggish

**Symptoms:**
- `ls`, `nav`, `git-*` commands are slow
- fzf interface takes time to appear

**Solutions:**
```powershell
# Check if antivirus is scanning PowerShell scripts
# Add PowerShell and profile directory to antivirus exclusions

# Verify SSD vs HDD for profile location
Get-PhysicalDisk | Select-Object DeviceID, MediaType

# Clear PowerShell module cache
Remove-Module * -Force
Import-Module *
```

---

## 🔧 Git Integration Issues

### ❌ Git Commands Don't Work

**Symptoms:**
```
git : The term 'git' is not recognized
```

**Solutions:**
```powershell
# Install Git
scoop install git

# Or download from https://git-scm.com/download/win

# Verify installation
git --version

# Configure Git if first time
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

### ❌ "Not in a Git repository" Errors

**Symptoms:**
- `git-a`, `git-l` show repository errors
- Git commands work but PowerFlow Git functions don't

**Solutions:**
```powershell
# Verify you're in a Git repository
git status

# Initialize repository if needed
git init

# Check if .git directory exists
Test-Path .git

# Navigate to a Git repository
cd "C:\path\to\your\git\repo"
```

### ❌ GitHub Integration (gh-l) Issues

**Symptoms:**
- `gh-l` shows authentication errors
- Can't access private repositories

**Solutions:**
```powershell
# Check if token is saved
gh-l-status

# Reset saved token
gh-l-reset

# Generate new GitHub token:
# 1. Go to https://github.com/settings/tokens
# 2. Generate new token (classic)
# 3. Select 'repo' scope
# 4. Run gh-l and enter token when prompted

# Test API access
$headers = @{ "Authorization" = "Bearer YOUR_TOKEN" }
Invoke-RestMethod -Uri "https://api.github.com/user" -Headers $headers
```

---

## 🌐 Network and Update Issues

### ❌ "Cannot check for updates" Errors

**Symptoms:**
```
Could not check for PowerShell/PowerFlow updates (network/API limit)
```

**Solutions:**
```powershell
# Test GitHub API connectivity
Test-NetConnection api.github.com -Port 443

# Check API rate limit
Invoke-RestMethod -Uri "https://api.github.com/rate_limit"

# Disable update checks temporarily
$script:CHECK_UPDATES = $false
$script:CHECK_PROFILE_UPDATES = $false

# Clear update check cache
Remove-Item "$env:TEMP\.pwsh_update_check" -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\.powerflow_update_check" -ErrorAction SilentlyContinue
```

### ❌ Corporate Firewall/Proxy Issues

**Symptoms:**
- Cannot download dependencies
- Update checks fail
- GitHub integration doesn't work

**Solutions:**
```powershell
# Configure PowerShell to use system proxy
[System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials

# Set proxy for current session
$proxy = [System.Net.WebProxy]::new("http://proxy.company.com:8080")
$proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
[System.Net.WebRequest]::DefaultWebProxy = $proxy

# Disable features that require internet
$script:CHECK_DEPENDENCIES = $false
$script:CHECK_UPDATES = $false
$script:CHECK_PROFILE_UPDATES = $false

# Manual dependency installation required
```

---

## 🪟 Windows Terminal Specific Issues

### ❌ Terminal Settings Not Saving

**Symptoms:**
- Font changes don't persist
- Settings revert after restart

**Solutions:**
```powershell
# Check Windows Terminal version
# Settings → About

# Locate settings file
$wtSettings = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
Test-Path $wtSettings

# Edit settings manually
code $wtSettings

# Example font configuration:
{
    "profiles": {
        "defaults": {
            "fontFace": "FiraCode Nerd Font",
            "fontSize": 11
        }
    }
}
```

### ❌ Multiple PowerShell Profiles in Terminal

**Symptoms:**
- PowerFlow only works in one PowerShell profile
- Inconsistent behavior between profiles

**Solutions:**
```powershell
# Check all PowerShell profile locations
$allProfiles = @(
    "$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1",           # PS 7+
    "$HOME\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"     # PS 5.1
)

foreach ($prof in $allProfiles) {
    Write-Host "$prof : $(if (Test-Path $prof) { '✅ Exists' } else { '❌ Missing' })"
}

# Copy PowerFlow to all profiles
$sourceProfile = $PROFILE
foreach ($prof in $allProfiles) {
    if ($prof -ne $sourceProfile) {
        $profDir = Split-Path $prof -Parent
        if (-not (Test-Path $profDir)) { New-Item -ItemType Directory -Path $profDir -Force }
        Copy-Item $sourceProfile $prof -Force
        Write-Host "Copied PowerFlow to: $prof"
    }
}
```

---

## 🔍 Advanced Debugging

### Enable Detailed Logging
```powershell
# Create debug profile
$debugProfile = $PROFILE + ".debug"
$profileContent = Get-Content $PROFILE -Raw

# Add debug statements
$debugContent = @"
# DEBUG MODE
`$VerbosePreference = "Continue"
`$DebugPreference = "Continue"
Start-Transcript -Path "`$env:TEMP\powerflow-debug.log" -Append

$profileContent

Stop-Transcript
"@

Set-Content $debugProfile $debugContent

# Load debug profile
. $debugProfile

# Check debug log
Get-Content "$env:TEMP\powerflow-debug.log" -Tail 50
```

### Function-Specific Debugging
```powershell
# Debug navigation issues
nav your-project -verbose

# Debug Git issues with detailed output
$VerbosePreference = "Continue"
git-a

# Test individual components
Test-Path "$HOME\Code"
Get-Bookmarks
Test-FiraCodeInstalled
```

### PowerShell Module Conflicts
```powershell
# Check for conflicting modules
Get-Module | Where-Object { $_.Name -like "*Git*" -or $_.Name -like "*Navigation*" }

# Remove conflicting modules
Remove-Module ConflictingModuleName -Force

# Import PowerFlow fresh
. $PROFILE
```

---

## 🚑 Recovery Procedures

### Complete Profile Reset
```powershell
# Backup current profile
Copy-Item $PROFILE "$PROFILE.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"

# Remove current profile
Remove-Item $PROFILE -Force

# Reinstall PowerFlow
irm https://raw.githubusercontent.com/Syntax-Read3r/powerflow/main/install.ps1 | iex
```

### Restore from Backup
```powershell
# List available backups
Get-ChildItem "$([System.IO.Path]::GetDirectoryName($PROFILE))" | Where-Object { $_.Name -like "*.backup.*" }

# Restore specific backup
$backupFile = "Microsoft.PowerShell_profile.ps1.backup.20240315-143022"
Copy-Item $backupFile $PROFILE -Force

# Reload profile
. $PROFILE
```

### Emergency Safe Mode
```powershell
# Create minimal safe profile
$safeProfile = @"
# PowerFlow Safe Mode - Minimal Configuration
Write-Host "PowerFlow Safe Mode - Limited functionality" -ForegroundColor Yellow

# Basic aliases only
Set-Alias ll Get-ChildItem
Set-Alias .. Set-Location .. 

# Disable all PowerFlow features
`$script:CHECK_DEPENDENCIES = `$false
`$script:CHECK_UPDATES = `$false
`$script:CHECK_PROFILE_UPDATES = `$false

function pwsh-recovery {
    Write-Host "PowerFlow Recovery Options:" -ForegroundColor Cyan
    Write-Host "1. Reinstall: irm https://raw.githubusercontent.com/Syntax-Read3r/powerflow/main/install.ps1 | iex"
    Write-Host "2. Manual fix: code `$PROFILE"
    Write-Host "3. Remove profile: Remove-Item `$PROFILE"
}
"@

Set-Content $PROFILE $safeProfile
. $PROFILE
```

---

## 📞 Getting Additional Help

### Before Reporting Issues

1. **Check PowerFlow version**: `Get-PowerFlowVersion`
2. **Test with clean profile**: Rename current profile, reinstall fresh
3. **Document error messages**: Copy exact error text
4. **Note your environment**:
   ```powershell
   $PSVersionTable
   Get-ComputerInfo | Select-Object WindowsProductName, WindowsVersion
   ```

### Information to Include in Bug Reports

```powershell
# Run this and include output in your bug report
@"
PowerFlow Version: $(try { $script:POWERFLOW_VERSION } catch { "Unknown" })
PowerShell Version: $($PSVersionTable.PSVersion)
Windows Version: $([System.Environment]::OSVersion.VersionString)
Terminal: $(try { $env:WT_SESSION } catch { "Unknown" })
Profile Path: $PROFILE
Dependencies Status:
$(
    $tools = @("starship", "fzf", "zoxide", "lsd", "git")
    foreach ($tool in $tools) {
        $found = Get-Command $tool -ErrorAction SilentlyContinue
        "  $tool : $(if ($found) { 'Found' } else { 'Missing' })"
    }
)
Font Test: 🚀 📁 ✅ 🌿 💻 🔍
"@
```

### Community Resources

- **GitHub Issues**: [Report bugs](https://github.com/Syntax-Read3r/powerflow/issues)
- **GitHub Discussions**: [General questions](https://github.com/Syntax-Read3r/powerflow/discussions)
- **Documentation**: [Full documentation](https://github.com/Syntax-Read3r/powerflow/tree/main/docs)

### Quick Self-Help Commands

```powershell
# Built-in help system
pwsh-h

# Version and update info
Get-PowerFlowVersion
powerflow-update

# Dependency status
Get-Command starship, fzf, zoxide, lsd, git -ErrorAction SilentlyContinue

# Recovery mode
pwsh-recovery  # (after enabling safe mode)
```

---

**🎯 Remember**: Most PowerFlow issues are related to fonts not being configured properly or dependencies not being installed. Start with those solutions first!

**💡 Pro Tip**: Keep your PowerFlow installation up to date with `powerflow-update` to get the latest fixes and improvements.