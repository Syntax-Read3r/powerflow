# 🚀 PowerFlow

> A beautiful, intelligent PowerShell profile that supercharges your terminal experience with smart navigation, enhanced Git workflows, and productivity-focused tools.

[![PowerShell](https://img.shields.io/badge/PowerShell-7.0+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Windows Terminal](https://img.shields.io/badge/Windows%20Terminal-Recommended-brightgreen.svg)](https://github.com/microsoft/terminal)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## ✨ Features

### 🧭 Smart Navigation System

- **Intelligent Project Search**: `nav chess-guru` finds projects across multiple directories
- **Persistent Bookmarks**: Create, manage, and navigate to frequently used locations
- **Fuzzy Search Integration**: Beautiful fzf interfaces for everything
- **Context-Aware Navigation**: Adapts based on your current location

### 🎯 Enhanced Git Workflow

- **Beautiful Add-Commit-Push**: Interactive workflow with visual feedback
- **Rollback System**: Create rollback branches from any commit safely
- **Interactive Branch Manager**: Pick, create, delete branches with visual interface
- **GitHub Integration**: Browse, clone, and manage your repositories with token security

### ✂️ Cut-and-Paste File Operations

- **Smart File Moving**: `mv filename` cuts files, `mv-t` pastes anywhere
- **Fuzzy File Search**: Find files with partial names and patterns
- **Interactive Rename**: Beautiful interface for renaming files
- **Safety Checks**: Prevents accidental deletion and data loss

### 🪟 Terminal Enhancement

- **Tab Management**: Create, switch, and close Windows Terminal tabs
- **Beautiful Interfaces**: Consistent emoji indicators and color schemes
- **Auto-Dependency Management**: Automatically installs required tools
- **Comprehensive Help**: Built-in documentation system

## 🎬 Quick Demo

```powershell
# Smart navigation - finds projects intelligently
nav my-react-app

# Enhanced Git workflow
git-a  # Beautiful add → commit → push interface

# Cut and paste files
mv important-file    # Cuts file
# Navigate to destination
mv-t                 # Pastes file

# Interactive Git log
git-l               # Beautiful log viewer with actions

# GitHub repo browser
gh-l                # Browse your repos with activity stats
```

## 🛠 Installation

### Prerequisites

- **PowerShell 7.0+** (recommended)
- **Windows Terminal** (for best experience)
- **Git** (for Git features)

### Quick Install

1. **Backup your existing profile** (if you have one):

   ```powershell
   Copy-Item $PROFILE "$PROFILE.backup" -ErrorAction SilentlyContinue
   ```

2. **Download and install PowerFlow**:

   ```powershell
   # Download the profile
   Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Syntax-Read3r/powerflow/main/Microsoft.PowerShell_profile.ps1" -OutFile $PROFILE

   # Reload your profile
   . $PROFILE
   ```

3. **First run setup**:
   PowerFlow will automatically:
   - Install required dependencies (Scoop, Starship, fzf, etc.)
   - Initialize default bookmarks
   - Configure the environment

### Manual Installation

1. Clone the repository:

   ```bash
   git clone https://github.com/Syntax-Read3r/powerflow.git
   ```

2. Copy the profile to your PowerShell profile location:

   ```powershell
   Copy-Item "powerflow/Microsoft.PowerShell_profile.ps1" $PROFILE
   ```

3. Reload your profile:
   ```powershell
   . $PROFILE
   ```

## 🎯 Quick Start Guide

### Navigation Basics

```powershell
# Create bookmarks for frequent locations
nav cb work          # Bookmark current directory as 'work'
nav b work           # Navigate to 'work' bookmark
nav list             # Interactive bookmark manager

# Smart project navigation
nav my-project       # Finds project in ~/Code or bookmarked directories
nav .. src           # Go up one level, then into 'src' directory
```

### Git Workflow

```powershell
# Enhanced add-commit-push
git-a                # Interactive workflow with file preview

# Rollback system
git-rb abc123        # Create rollback branch from commit
git-rba              # Rollback branch workflow (only on rollback-* branches)

# Interactive tools
git-b                # Branch picker and manager
git-l                # Beautiful log viewer
git-s                # Interactive status viewer
```

### File Operations

```powershell
# Cut and paste workflow
mv myfile.txt        # Cut file (supports fuzzy search)
mv-t                 # Paste file in current directory
mv-c                 # Cancel move operation

# Smart rename
rn                   # Interactive file picker and rename
rn myfile.txt        # Direct rename with interface

# Enhanced listing
ls                   # Beautiful directory listing
ls -t                # Tree view with smart depth
```

### GitHub Integration

```powershell
# Browse your repositories
gh-l                 # List repos with activity stats
gh-l 20              # Show top 20 repos

# Token management
gh-l-status          # Check if token is saved
gh-l-reset           # Remove saved token
```

## 📚 Complete Feature Reference

### Smart Navigation & Bookmarks

| Command               | Description                              |
| --------------------- | ---------------------------------------- |
| `nav <project>`       | Smart project search with fuzzy matching |
| `nav b <bookmark>`    | Navigate to bookmark                     |
| `nav create-b <name>` | Create bookmark from current directory   |
| `nav delete-b <name>` | Delete bookmark with confirmation        |
| `nav list`            | Interactive bookmark manager             |
| `..`, `...`, `....`   | Quick parent directory navigation        |

### Enhanced Git Workflow

| Command           | Description                            |
| ----------------- | -------------------------------------- |
| `git-a`           | Beautiful add → commit → push workflow |
| `git-rb <commit>` | Create rollback branch from commit     |
| `git-rba`         | Rollback branch add-commit-push        |
| `git-l`           | Interactive log viewer with actions    |
| `git-b`           | Branch picker and manager              |
| `git-s`           | Interactive status viewer              |

### File Operations

| Command     | Description                          |
| ----------- | ------------------------------------ |
| `mv <file>` | Smart cut file for moving            |
| `mv-t`      | Paste cut file                       |
| `rn [file]` | Interactive file rename              |
| `rm <file>` | Smart file removal with fuzzy search |
| `ls -t`     | Tree view with smart depth           |

### Terminal Management

| Command             | Description                   |
| ------------------- | ----------------------------- |
| `open-nt`           | Open new Windows Terminal tab |
| `next-t` / `prev-t` | Switch between tabs           |
| `open-t <N>`        | Switch to specific tab        |

### Configuration

| Command         | Description                    |
| --------------- | ------------------------------ |
| `pwsh-profile`  | Edit PowerShell profile        |
| `pwsh-starship` | Edit Starship config           |
| `pwsh-settings` | Edit Windows Terminal settings |
| `pwsh-h`        | Show complete help menu        |

## 🔧 Configuration

### Dependencies

PowerFlow automatically installs these tools via Scoop:

- **Starship**: Cross-shell prompt
- **fzf**: Fuzzy finder
- **zoxide**: Smart directory navigation
- **lsd**: Modern ls replacement
- **git**: Version control

### Customization

Edit your profile to customize:

```powershell
pwsh-profile  # Opens profile in VS Code
```

### Disable Features

You can disable specific features by editing these variables at the top of the profile:

```powershell
$script:CHECK_DEPENDENCIES = $false  # Skip dependency checks
$script:CHECK_UPDATES = $false       # Skip PowerShell update checks
```

## 🛡️ Safety Features

- **Current branch protection**: Prevents deletion of active Git branches
- **Confirmation prompts**: For destructive operations like file deletion
- **Backup suggestions**: Warns before potentially destructive actions
- **Path validation**: Ensures operations target valid locations
- **Error handling**: Graceful handling of missing dependencies or permissions

## 🎨 Customization Examples

### Custom Bookmarks

```powershell
# Add your frequently used directories
nav create-b projects "$HOME\Development\Projects"
nav create-b docs "$HOME\Documents\Work"
nav create-b scripts "$HOME\Scripts"
```

### Git Aliases

```powershell
# The profile includes many Git aliases, or add your own:
function git-sync { git pull; git push }
function git-clean { git-f }
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

### Development Setup

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

### Areas for Contribution

- Additional Git workflow improvements
- More file operation enhancements
- Cross-platform compatibility
- Performance optimizations
- New navigation features

## 📝 Changelog

### v6.0 (Current)

- Enhanced rollback branch workflow
- Improved GitHub integration with secure token storage
- Smart file operations with fuzzy search
- Beautiful interactive interfaces
- Comprehensive help system

### Previous Versions

See [CHANGELOG.md](CHANGELOG.md) for detailed version history.

## 🆘 Troubleshooting

### Common Issues

**Profile doesn't load**

- Ensure PowerShell execution policy allows script execution:
  ```powershell
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
  ```

**Dependencies fail to install**

- Run PowerShell as Administrator for the first setup
- Check internet connection for Scoop package manager

**Fuzzy search not working**

- Ensure fzf is installed: `scoop install fzf`
- Restart PowerShell after dependency installation

**Git commands not working**

- Ensure Git is installed and in PATH
- Check if you're in a Git repository

### Getting Help

- Use `pwsh-h` for the complete help menu
- Check function documentation: `Get-Help git-a -Detailed`
- Open an issue on GitHub for bugs or feature requests

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **Starship** - For the beautiful cross-shell prompt
- **fzf** - For the amazing fuzzy finding capabilities
- **Windows Terminal** - For the excellent terminal experience
- **PowerShell Team** - For the powerful shell environment

## 🌟 Star History

[![Star History Chart](https://api.star-history.com/svg?repos=Syntax-Read3r/powerflow&type=Date)](https://star-history.com/#Syntax-Read3r/powerflow&Date)

---

<div align="center">
  <strong>Made with ❤️ for the PowerShell community</strong>
  <br>
  <sub>If PowerFlow improves your workflow, consider giving it a ⭐!</sub>
</div>
