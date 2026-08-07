# 📦 PowerFlow Installation Guide

Complete installation guide for PowerFlow - the enhanced PowerShell profile that supercharges your terminal experience.

## 📋 System Requirements

### Minimum Requirements
- **PowerShell 7.0** or higher
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

### Step 2: Windows Prerequisite and Dependencies

Scoop is PowerFlow's Windows prerequisite. The main installer verifies or installs it before
anything else and activates its shim in the current PowerShell process. It then installs the
managed tools and font below. Manual pre-installation is optional:

```powershell
# Install Scoop (package manager)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression

# Install core tools
scoop install starship fzf zoxide lsd git

# Install FiraCode Nerd Font Mono
scoop bucket add nerd-fonts
scoop install FiraCode-NF-Mono
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
4. Set **Font face** to `FiraCode Nerd Font Mono`
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
                "fontFace": "FiraCode Nerd Font Mono",
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
ls --tree       # Tree view of current directory (`ls -t` sorts by time)
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
1. Run `pwsh-font` (or manually: `scoop install FiraCode-NF-Mono`)
2. Set terminal font to "FiraCode Nerd Font Mono"
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

> **Windows PowerShell 5.1 is not supported.** The floor was raised to 7.0 in v4.4.0 because
> the claim was never testable: the source tree is UTF-8 **without** a BOM, which 5.1 decodes
> as the legacy ANSI code page and then fails to parse wherever a file contains non-ASCII text —
> which is most of them, given the output uses box-drawing characters and emoji. At least one
> adapter also uses PowerShell 7's null-coalescing operator. Every supported install path and
> both CI legs already run `pwsh`, so 5.1 was documented but never exercised.
>
> `pwsh` installs alongside Windows PowerShell — it does not replace it.

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
# Recovery: the PowerFlow installer normally installs this prerequisite automatically
Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
```

**Icons show as squares/boxes**
```powershell
# Solution: Install and configure Nerd Font
scoop bucket add nerd-fonts
scoop install FiraCode-NF-Mono
# Then set Windows Terminal font to "FiraCode Nerd Font Mono"
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

**The uninstaller is already on your machine.** It was installed alongside PowerFlow, and it
reads the manifest written at install time — so it removes exactly what PowerFlow placed and
**never removes a tool you already had**.

### From inside PowerFlow

```powershell
powerflow-uninstall
```

### From any shell

```bash
# Linux
pwsh -NoProfile -File ~/.config/powershell/uninstall.ps1
```

```powershell
# Windows
pwsh -NoProfile -File "$HOME\Documents\PowerShell\uninstall.ps1"
```

Add `-Yes` to skip the confirmation, `-Purge` to also delete your bookmarks
(`~/.nav_bookmarks.json`), which are kept by default.

On Windows, interactive uninstall asks separately whether Scoop should also be removed.
PowerFlow keeps Scoop by default, and `-Yes` **always keeps it**. If you answer yes, PowerFlow
then explains the risk before continuing: Scoop's own removal uninstalls every Scoop-managed
application and removes its buckets and shims, including tools unrelated to PowerFlow. Scoop
retains its own final y/N confirmation.

### What it does

- Removes only the files listed in `.powerflow-manifest.json`
- Removes the dependencies **PowerFlow installed** (`starship`, `fzf`, `zoxide`, `lsd`) — and
  **keeps** any that were already on your machine before PowerFlow, `git` included
- Keeps the shared Scoop prerequisite unless an interactive user separately opts in after the
  risk warning and confirms again in Scoop's own uninstaller
- Restores your original pre-PowerFlow profile if you had one
- On Linux, removes the `~/.bashrc` login hook, and reverts your login shell to bash **before**
  removing pwsh, so you cannot be locked out

### ⚠️ Do not uninstall by hand

Deleting `$PROFILE` yourself leaves the component tree, the dependencies and the login hook
behind, and loses the manifest that records which tools were yours. If the manifest is gone,
nothing can tell your `fzf` from PowerFlow's.

> **`bash install.sh --uninstall` only works if `install.sh` is on disk.** The documented
> install is `curl … | bash`, which leaves no file behind — so that command gives you
> `No such file or directory`. Use one of the commands above instead.

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
