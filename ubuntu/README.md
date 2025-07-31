# PowerFlow Ubuntu Integration

## Overview

PowerFlow Ubuntu integration provides a comprehensive enhanced zsh profile that mirrors the functionality of the PowerShell profile for Ubuntu/WSL environments. This profile includes smart navigation, bookmark management, dependency auto-installation, and enhanced file operations with modern shell features.

## Features

### >� Smart Navigation System
- **Intelligent project search** - Navigate to projects with fuzzy matching across code directories
- **Persistent bookmarks** - Save frequently used directories with memorable names
- **Context-aware navigation** - Automatically detects your working environment and adapts search behavior
- **Parent directory shortcuts** - Quick navigation with `..`, `...`, `....` aliases

### =� Bookmark Management
- **Create bookmarks** - `nav create-b <name>` or `nav cb <name>` to bookmark current directory
- **Navigate to bookmarks** - `nav b <bookmark>` to navigate to saved locations
- **Interactive bookmark list** - `nav list` or `nav l` for interactive bookmark management
- **Rename/Delete bookmarks** - `nav rename-b <old> <new>` and `nav delete-b <name>`

### =' Dependency Management
- **Auto-installation** - Automatically installs missing dependencies on first run
- **Daily checks** - Checks for missing tools once per day to avoid slow startup
- **Required tools**: curl, wget, git, jq, fzf, xclip
- **Optional tools**: starship, zoxide, lsd (for enhanced experience)

### =� Enhanced File Operations
- **Modern directory listing** - Beautiful file views with lsd integration
- **Tree view** - `lst` command for tree-style directory listing
- **Smart depth detection** - Automatically adjusts tree depth for different project types
- **Enhanced file utilities** - Improved touch, mkdir, and which commands

### <� Beautiful User Experience
- **Starship prompt** - Modern, informative prompt with Git status and project detection
- **Consistent visual design** - Emoji indicators and color schemes
- **Clipboard integration** - Copy paths and results to clipboard automatically
- **Context-aware operations** - Adapts to current directory and project type

### =� Safety & Reliability
- **Dependency validation** - Ensures all required tools are available
- **Recovery system** - Built-in recovery and diagnostics menu
- **Non-destructive operations** - Confirmation prompts for potentially destructive actions
- **Version management** - Track profile version and check for updates

### 🖥️ Cross-Platform Terminal Integration
- **Windows Terminal integration** - Open new tabs in different shells from Ubuntu
- **PowerShell tab opening** - `open-nt pwsh` or `open-nt p` to launch PowerShell tabs
- **Ubuntu tab management** - `open-nt ubuntu` or `open-nt u` for new Ubuntu instances
- **Smart path conversion** - Automatically converts WSL paths to Windows paths when needed
- **Command Prompt support** - `open-nt cmd` to open Command Prompt tabs

## Installation

### Quick Install

```bash
# Download and install the enhanced .zshrc
curl -o ~/.zshrc https://raw.githubusercontent.com/Syntax-Read3r/powerflow/main/ubuntu/.zshrc
source ~/.zshrc
```

### Manual Install

1. Install zsh and Oh My Zsh:
```bash
sudo apt update
sudo apt install zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

2. Backup your existing .zshrc:
```bash
cp ~/.zshrc ~/.zshrc.backup
```

3. Copy the PowerFlow .zshrc:
```bash
cp /path/to/powerflow/ubuntu/.zshrc ~/.zshrc
```

4. Install required plugins:
```bash
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
```

5. Source the new profile:
```bash
source ~/.zshrc
```

## Uninstallation

### Quick Uninstall

```bash
# Download and run uninstall script
curl -fsSL https://raw.githubusercontent.com/Syntax-Read3r/powerflow/main/ubuntu/uninstall.sh | bash

# Or download and run manually
wget https://raw.githubusercontent.com/Syntax-Read3r/powerflow/main/ubuntu/uninstall.sh
chmod +x uninstall.sh
./uninstall.sh
```

### Manual Uninstall

```bash
# Restore previous .zshrc backup
cp ~/.zshrc.backup ~/.zshrc

# Or remove PowerFlow .zshrc completely
rm ~/.zshrc

# Clean up PowerFlow files
rm -f ~/.wsl_bookmarks.json ~/.wsl_init_check ~/.wsl_profile_update_check ~/.nav_history
rm -f /tmp/.powerflow_*

# Remove zsh plugins if no longer needed
rm -rf ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
rm -rf ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
```

### Uninstall Options

The uninstall script provides three removal options:

1. **Remove PowerFlow only** - Keeps all dependencies installed
2. **Remove PowerFlow + optional dependencies** - Removes starship, zoxide, lsd
3. **Complete cleanup** - Removes PowerFlow and all dependencies (including curl, wget, git, etc.)

**Note**: The script will create a backup before removal and offers to restore previous .bashrc backups if available.

### First Run

On first run, the profile will:
- Check for missing dependencies
- Install required tools automatically
- Initialize default bookmarks
- Set up the navigation system
- Configure zsh with Oh My Zsh and plugins
- Install Starship prompt for enhanced experience

## Usage

### Navigation Commands

| Command | Description |
|---------|-------------|
| `nav <project>` | Smart project search in code directories |
| `nav b <bookmark>` | Navigate to bookmark |
| `nav create-b <name>` | Create bookmark for current directory |
| `nav delete-b <name>` | Delete bookmark with confirmation |
| `nav rename-b <old> <new>` | Rename existing bookmark |
| `nav list` | Interactive bookmark manager |
| `z <project>` | Alias for nav |

### Directory Shortcuts

| Command | Description |
|---------|-------------|
| `..` | Go up one level |
| `...` | Go up two levels |
| `....` | Go up three levels |
| `~` | Go to home directory |
| `back` | Go to previous directory |

### File Operations

| Command | Description |
|---------|-------------|
| `lsl [path]` | Beautiful directory listing with lsd |
| `lst [path]` | Tree view with smart depth detection |
| `here` | Detailed info about current directory |
| `copy-pwd` | Copy current path to clipboard |
| `open-pwd` | Open current directory in Windows Explorer |
| `open-nt` | Open new Windows Terminal tab (default: zsh) |
| `open-nt pwsh` | Open new PowerShell tab |
| `open-nt p` | Open new PowerShell tab (short form) |
| `open-nt ubuntu` | Open new Ubuntu tab |
| `open-nt u` | Open new Ubuntu tab (short form) |

### System Management

| Command | Description |
|---------|-------------|
| `get_wsl_profile_version` | Show profile version and status |
| `wsl_recovery` | Recovery and diagnostics menu |
| `wsl_help` | Show comprehensive help menu |

## Default Bookmarks

The profile initializes with these default bookmarks:
- `code` � `/mnt/c/Users/_munya/Code`
- `documents` � `/mnt/c/Users/_munya/Documents`
- `downloads` � `/mnt/c/Users/_munya/Downloads`
- `pictures` � `/mnt/c/Users/_munya/Pictures`
- `videos` � `/mnt/c/Users/_munya/Videos`
- `home` � `/home/munya`
- `winhome` � `/mnt/c/Users/_munya`

## Configuration

### Environment Variables

- `WSL_PROFILE_VERSION` - Current profile version
- `CHECK_DEPENDENCIES` - Enable/disable dependency checking
- `CHECK_UPDATES` - Enable/disable update checking
- `BOOKMARK_FILE` - Location of bookmark JSON file

### Customization

You can customize the profile by:
1. Editing the default bookmarks in `initialize_default_bookmarks()`
2. Modifying search directories in the `nav` function
3. Adding custom aliases and functions
4. Adjusting dependency lists

## Dependencies

### Required Tools
- **zsh** - Modern shell with advanced features
- **curl** - For downloading files and updates
- **wget** - Alternative download tool
- **git** - Version control integration
- **jq** - JSON processing for bookmark management
- **fzf** - Fuzzy finder for interactive selections
- **xclip** - Clipboard integration

### Optional Tools
- **starship** - Modern prompt with Git integration (recommended)
- **zoxide** - Smart directory jumping
- **lsd** - Modern ls replacement with icons and colors
- **Oh My Zsh** - Framework for managing zsh configuration
- **zsh-autosuggestions** - Auto-suggestions based on history
- **zsh-syntax-highlighting** - Syntax highlighting for commands

## Troubleshooting

### Common Issues

1. **Missing dependencies**
   - Run `check_dependency_status` to see what's missing
   - Run `initialize_dependencies` to reinstall all tools

2. **Bookmarks not working**
   - Check if jq is installed: `which jq`
   - Reset bookmarks: `rm ~/.wsl_bookmarks.json && source ~/.bashrc`

3. **Navigation not finding projects**
   - Use `nav <project> -verbose` for detailed search output
   - Check if you're in the correct bookmark location

4. **Slow startup**
   - Dependencies are only checked once per day
   - Delete `~/.wsl_init_check` to force recheck
   - Disable heavy plugins if startup is too slow

5. **zsh plugins not working**
   - Ensure plugins are properly installed in Oh My Zsh custom directory
   - Check if plugins are enabled in ~/.zshrc
   - Reload shell with `source ~/.zshrc`

### Recovery

Run `wsl_recovery` for interactive recovery options:
1. Reload profile
2. Check dependencies
3. Reinstall tools
4. Reset bookmarks
5. Full dependency reinstall
6. Edit profile manually

## Version History

- **v1.0.0** - Initial release with core navigation and bookmark features
- Enhanced WSL integration with PowerShell feature parity
- Auto-dependency installation and management
- Comprehensive help and recovery system

## Contributing

To contribute to the Ubuntu integration:
1. Fork the repository
2. Make changes to `ubuntu/.zshrc` and related files
3. Test thoroughly in WSL environment with zsh
4. Submit pull request with detailed description

## License

This project is licensed under the same terms as the main PowerFlow project.