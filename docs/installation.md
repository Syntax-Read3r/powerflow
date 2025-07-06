# 📦 PowerFlow Installation Guide

Complete installation guide for PowerFlow - the enhanced PowerShell profile that supercharges your terminal experience.

## 📋 System Requirements

### Minimum Requirements
- **PowerShell 5.1** or higher (PowerShell 7+ recommended)
- **Windows 10/11** or Windows Server 2016+
- **Internet connection** for downloading dependencies
- **Administrator privileges** (for some dependency installations)

### Recommended Setup
- **PowerShell 7.x** (latest version)
- **Windows Terminal** (for best visual experience)
- **Git** (for Git workflow features)
- **VS Code** (for configuration editing)

### Check Your PowerShell Version
```powershell
$PSVersionTable.PSVersion
# Should show 5.1 or higher
```

---

## ⚡ Quick Installation (Recommended)

### One-Line Install
```powershell
irm https://raw.githubusercontent.com/Syntax-Read3r/powerflow/main/install.ps1 | iex
```

### Alternative Quick Install
```powershell
# Download and run install script
Invoke-RestMethod -Uri "https://raw.githubusercontent.com/Syntax-Read3r/powerflow/main/install.ps1" -OutFile "install.ps1"
.\install.ps1
```

### Force Overwrite Existing Profile
```powershell
.\install.ps1 -Force
```

---

## 🛠️ Manual Installation

### Step 1: Download Profile
```powershell
# Create profile directory if it doesn't exist
$profileDir = Split-Path $PROFILE -Parent
if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force
}

# Download the profile
Invoke-RestMethod -Uri "https://raw.githubusercontent.com/Syntax-Read3r/powerflow/main/Microsoft.PowerShell_profile.ps1" -OutFile $PROFILE
```

### Step 2: Install Dependencies
PowerFlow will automatically install these on first run, but you can pre-install:

```powershell
# Install Scoop (package manager)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression

# Install core tools
scoop install starship fzf zoxide lsd git

# Install FiraCode Nerd Font
scoop bucket add nerd-fonts
scoop install FiraCode-NF
```

### Step 3: Reload Profile
```powershell
# Reload your PowerShell profile
. $PROFILE
```

---

## 🔧 Post-Installation Setup

### 1. Configure Windows Terminal Font

**Method 1: Via Settings UI**
1. Open Windows Terminal
2. Press `Ctrl + ,` (Settings)
3. Go to your PowerShell profile → Appearance
4. Set **Font face** to `FiraCode Nerd Font` or `FiraCode NF`
5. Optionally set **Font size** to `11` or `12`
6. Save settings

**Method 2: Via JSON Settings**
```json
{
    "profiles": {
        "defaults": {},
        "list": [
            {
                "name": "PowerShell",
                "source": "Windows.Terminal.PowershellCore",
                "fontFace": "FiraCode Nerd Font",
                "fontSize": 11
            }
        ]
    }
}
```

### 2. Enable Execution Policy (if needed)
```powershell
# Allow local scripts to run
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### 3. Verify Installation
```powershell
# Check PowerFlow version
Get-PowerFlowVersion

# Test core features
pwsh-h          # Show help
nav list        # Show bookmarks
git-s           # Git status (in a Git repository)
ls -t           # Tree view of current directory
```

---

## 🎨 Visual Configuration

### Icons and Symbols Test
After installation, test that icons display correctly:

```powershell
# Run this test - you should see clear icons, not squares
Write-Host "🚀 📁 ✅ 🌿 💻 🔍 🎯 📦 🔄 ⚡"
```

**If you see squares or missing characters:**
1. Install FiraCode Nerd Font: `scoop install FiraCode-NF`
2. Set terminal font to "FiraCode Nerd Font"
3. Restart Windows Terminal

### Color Scheme (Optional)
PowerFlow works with any color scheme, but these are recommended:
- **Campbell Powershell** (default)
- **One Half Dark**
- **Dracula**
- **Solarized Dark**

---

## 🌐 Git Integration Setup

### Configure Git (if not already done)
```powershell
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

### GitHub Token for Enhanced Features
For `gh-l` (GitHub repository listing):

1. Go to: https://github.com/settings/tokens
2. Generate new token (classic) with `repo` scope
3. PowerFlow will prompt for token on first use of `gh-l`
4. Token is securely stored in Windows Credential Manager

---

## 🚀 Advanced Installation Options

### Installing in Different PowerShell Profiles

**PowerShell 5.1 (Windows PowerShell)**
```powershell
# Profile location: Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1
$profile51 = "$HOME\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
Invoke-RestMethod -Uri "https://raw.githubusercontent.com/Syntax-Read3r/powerflow/main/Microsoft.PowerShell_profile.ps1" -OutFile $profile51
```

**PowerShell 7+ (PowerShell Core)**
```powershell
# Profile location: Documents\PowerShell\Microsoft.PowerShell_profile.ps1
$profile7 = "$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
Invoke-RestMethod -Uri "https://raw.githubusercontent.com/Syntax-Read3r/powerflow/main/Microsoft.PowerShell_profile.ps1" -OutFile $profile7
```

### Corporate/Restricted Environments

**If Scoop installation fails:**
1. Download tools manually:
   - [Starship](https://starship.rs/guide/#-installation)
   - [fzf](https://github.com/junegunn/fzf/releases)
   - [zoxide](https://github.com/ajeetdsouza/zoxide/releases)
   - [lsd](https://github.com/Peltoche/lsd/releases)

2. Add tool directories to PATH
3. Set `$script:CHECK_DEPENDENCIES = $false` in profile to skip auto-installation

**If execution policy is restricted:**
```powershell
# Bypass for current session only
powershell -ExecutionPolicy Bypass -File install.ps1
```

---

## ✅ Verification Checklist

After installation, verify these features work:

### Core Navigation
- [ ] `nav` - Shows help and navigation options
- [ ] `nav list` - Shows bookmark manager
- [ ] `ls` - Shows beautiful directory listing with icons
- [ ] `..` - Goes up one directory

### Git Features (in a Git repository)
- [ ] `git-a` - Shows beautiful commit interface
- [ ] `git-l` - Shows interactive log viewer
- [ ] `git-s` - Shows interactive status

### Visual Elements
- [ ] Icons display correctly (🚀 📁 ✅ etc.)
- [ ] Colors and formatting look good
- [ ] No error messages on profile load

### Auto-Updates
- [ ] `powerflow-version` - Shows version info
- [ ] `powerflow-update` - Checks for updates

---

## 🐛 Troubleshooting

### Common Issues

**"Execution policy" error**
```powershell
# Solution: Enable script execution
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**"Scoop not found" error**
```powershell
# Solution: Install Scoop manually
Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
```

**Icons show as squares/boxes**
```powershell
# Solution: Install and configure Nerd Font
scoop bucket add nerd-fonts
scoop install FiraCode-NF
# Then set Windows Terminal font to "FiraCode Nerd Font"
```

**Profile loads slowly**
```powershell
# Solution: Disable dependency checks (if tools already installed)
# Edit profile and set: $script:CHECK_DEPENDENCIES = $false
```

**fzf not working**
```powershell
# Check if fzf is installed and in PATH
Get-Command fzf
# If not found, install manually or via Scoop
```

**Git features not working**
```powershell
# Ensure you're in a Git repository
git status
# Configure Git if not already done
git config --global user.name "Your Name"
```

### Getting Help

1. **Check PowerFlow help**: `pwsh-h`
2. **Verify version**: `Get-PowerFlowVersion`
3. **Check dependencies**: `Get-Command starship, fzf, zoxide, lsd`
4. **Report issues**: [GitHub Issues](https://github.com/Syntax-Read3r/powerflow/issues)

### Debug Mode

Enable verbose output for troubleshooting:
```powershell
# Add to top of profile temporarily
$VerbosePreference = "Continue"
. $PROFILE
```

---

## 🗑️ Uninstallation

### Quick Uninstall
```powershell
# Download and run uninstall script
Invoke-RestMethod -Uri "https://raw.githubusercontent.com/Syntax-Read3r/powerflow/main/uninstall.ps1" -OutFile "uninstall.ps1"
.\uninstall.ps1
```

### Manual Uninstall
```powershell
# Backup current profile
Copy-Item $PROFILE "$PROFILE.backup"

# Remove profile
Remove-Item $PROFILE

# Optionally remove dependencies
scoop uninstall starship fzf zoxide lsd FiraCode-NF
```

### Clean Uninstall (Remove Everything)
```powershell
# Remove profile
Remove-Item $PROFILE -Force

# Remove Scoop and all packages (optional)
scoop uninstall *
# Follow Scoop uninstall instructions to remove Scoop itself

# Reset Windows Terminal font to default
# (manually in Terminal settings)
```

---

## 🐧 Ubuntu/WSL Installation

PowerFlow also supports Ubuntu and WSL environments with a comprehensive bash profile.

### Quick Install (Ubuntu/WSL)
```bash
# Download and install the enhanced .bashrc
curl -o ~/.bashrc https://raw.githubusercontent.com/Syntax-Read3r/powerflow/main/ubuntu/.bashrc
source ~/.bashrc
```

### Manual Install (Ubuntu/WSL)
```bash
# Backup existing .bashrc
cp ~/.bashrc ~/.bashrc.backup

# Download PowerFlow .bashrc
wget -O ~/.bashrc https://raw.githubusercontent.com/Syntax-Read3r/powerflow/main/ubuntu/.bashrc

# Source the new profile
source ~/.bashrc
```

### Ubuntu Features
- **Smart navigation** - `nav <project>` for intelligent project search
- **Bookmark management** - Create and manage directory bookmarks
- **Auto-dependency installation** - Automatically installs required tools
- **Enhanced file operations** - Beautiful directory listings and file management
- **WSL integration** - Seamless Windows Explorer integration

### Ubuntu Dependencies
PowerFlow automatically installs these tools on first run:
- **Required**: curl, wget, git, jq, fzf, xclip
- **Optional**: starship, zoxide, lsd (for enhanced experience)

### Ubuntu Usage
```bash
# Navigation
nav <project>        # Find and navigate to project
nav b <bookmark>     # Navigate to bookmark
nav create-b <name>  # Create bookmark

# Enhanced file operations
lsl                  # Beautiful directory listing
lst                  # Tree view
here                 # Current directory info

# System management
wsl_help            # Show comprehensive help
wsl_recovery        # Recovery and diagnostics
```

For complete Ubuntu documentation, see [ubuntu/README.md](../ubuntu/README.md).

---

## 🔄 Updating PowerFlow

PowerFlow includes an automatic update system:

### Automatic Updates
- PowerFlow checks for updates daily
- Shows notification when new version available
- Offers one-click update with backup

### Manual Update Check
```powershell
# Check for updates now
powerflow-update

# Force update check
Check-PowerFlowVersion -Force
```

### Manual Update
```powershell
# Download latest version
Invoke-RestMethod -Uri "https://raw.githubusercontent.com/Syntax-Read3r/powerflow/main/Microsoft.PowerShell_profile.ps1" -OutFile $PROFILE

# Reload profile
. $PROFILE
```

---

## 📞 Support

### Documentation
- **Features Guide**: [features.md](features.md)
- **Troubleshooting**: [troubleshooting.md](troubleshooting.md)
- **GitHub Repository**: https://github.com/Syntax-Read3r/powerflow

### Getting Help
- **Built-in Help**: `pwsh-h`
- **Version Info**: `Get-PowerFlowVersion`
- **GitHub Issues**: [Report a bug or request a feature](https://github.com/Syntax-Read3r/powerflow/issues)

### Community
- **Discussions**: [GitHub Discussions](https://github.com/Syntax-Read3r/powerflow/discussions)
- **Contributing**: [CONTRIBUTING.md](../CONTRIBUTING.md)

---

**🎉 Welcome to PowerFlow! Your terminal experience just got supercharged!**

After installation, type `pwsh-h` to see all available commands and start exploring your enhanced PowerShell environment.