# PowerFlow Fish to zsh Migration Guide

## Overview

This guide documents the migration from Fish shell to zsh for PowerFlow. The migration was necessary due to compatibility issues with Fish shell, particularly with npm commands and password-protected operations.

## Why We Moved Away from Fish Shell

Fish shell encountered several critical issues:

1. **npm Compatibility Issues** - `npm run dev` and other npm commands failed to execute properly
2. **Password Mode Problems** - Commands were running in password mode, causing authentication issues
3. **POSIX Non-compliance** - Fish's unique syntax caused compatibility problems with many tools
4. **Development Tool Issues** - Various development tools had problems with Fish's syntax

## Why zsh is Better

zsh was chosen as the replacement for the following reasons:

1. **POSIX Compliance** - Full compatibility with bash and development tools
2. **Better Performance** - Faster startup and execution times
3. **Rich Plugin Ecosystem** - Oh My Zsh provides extensive plugin support
4. **Auto-suggestions** - Intelligent command completion based on history
5. **Syntax Highlighting** - Real-time command validation and coloring
6. **npm Compatibility** - Perfect compatibility with Node.js and npm commands

## Migration Summary

### Files Updated

| File | Purpose | Status |
|------|---------|---------|
| `.zshrc` | Main zsh configuration with all PowerFlow functions | ✅ Complete |
| `README.md` | Updated documentation for zsh setup | ✅ Complete |
| `install.sh` | Updated installation script for zsh and Oh My Zsh setup | ✅ Complete |
| `uninstall.sh` | Enhanced uninstaller supporting zsh, Oh My Zsh, and bash | ✅ Complete |

### Function Equivalency

All PowerShell profile functions have been ported to zsh with equivalent or enhanced functionality:

#### Core Functions Ported

| PowerShell Function | zsh Equivalent | Status | Notes |
|-------------------|-----------------|---------|--------|
| `claude`, `cc` | `cc` | ✅ | Consolidated with flags |
| `explain` | `cc -e` | ✅ | Now part of main cc function |
| `fix` | `cc -f` | ✅ | Now part of main cc function |
| `build` | `cc -b` | ✅ | Now part of main cc function |
| `review` | `cc -r` | ✅ | Now part of main cc function |
| `git-a` | `git-a` | ✅ | Enhanced with preview |
| `git-aa` | `git-aa` | ✅ | Interactive confirmation |
| `git-cm` | `git-cm` | ✅ | Direct port |
| `git-s`/`git-st` | `git-s`/`git-st` | ✅ | Enhanced format |
| `git-l` | `git-l` | ✅ | Direct port |
| `git-log` | `git-log` | ✅ | Direct port |
| `git-b` | `git-b` | ✅ | Enhanced feedback |
| `git-p` | `git-p` | ✅ | Enhanced with branch detection |
| `git-stash`/`git-sh` | `git-stash`/`git-sh` | ✅ | Enhanced subcommand support |
| `git-remote`/`git-r` | `git-remote`/`git-r` | ✅ | Direct port |
| `nav` | `nav` | ✅ | Enhanced with bookmarks |
| `here` | `here` | ✅ | Enhanced project detection |
| `copy-pwd` | `copy-pwd` | ✅ | Multiple clipboard support |
| `copy-file`/`cf` | `copy-file`/`cf` | ✅ | Enhanced with validation |
| `open-pwd`/`op` | `open-pwd`/`op` | ✅ | Cross-platform support |
| `next-t` | `next-t` | ✅ | Direct port |
| `prev-t` | `prev-t` | ✅ | Direct port |
| `create-next`/`create-n` | `create-next`/`create-n` | ✅ | Enhanced feedback |
| `powerflow-version` | `powerflow-version` | ✅ | Fish-specific info |
| `powerflow-update` | `powerflow-update` | ✅ | Direct port |

#### Enhanced Functions

| Function | Enhancement | Benefit |
|----------|-------------|---------|
| `ls` | Auto-detection of `lsd`/`exa` | Better file listing |
| `touch` | Feedback on file creation/update | Clear user feedback |
| `mkdir` | Auto-creation with `-p` flag | Simplified directory creation |
| `which` | Enhanced output with file info | More detailed command location |
| `here` | Extended project type detection | Better project awareness |
| `back` | Numeric back navigation | More flexible navigation |

#### New Functions

| Function | Purpose | Usage |
|----------|---------|-------|
| `create-bookmark`/`cb` | Create navigation bookmarks | `cb myproject` |
| `delete-bookmark`/`db` | Delete bookmarks | `db myproject` |
| `list-bookmarks`/`lb` | List all bookmarks | `lb` |
| `zsh-help`/`help` | Comprehensive help system | `help` |

## Installation

### Quick Install

```bash
cd ubuntu/
chmod +x install.sh
./install.sh
```

### Manual Setup

1. **Install zsh and Oh My Zsh**
   ```bash
   sudo apt update && sudo apt install -y zsh
   sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
   ```

2. **Install zsh Plugins**
   ```bash
   git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
   git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
   ```

3. **Copy Configuration Files**
   ```bash
   cp .zshrc ~/.zshrc
   ```

4. **Set zsh as Default Shell** (Optional)
   ```bash
   chsh -s /usr/bin/zsh
   ```

## Key Features

### 1. Intelligent Auto-completion

zsh with Oh My Zsh provides context-aware completions for:
- File and directory names
- Command options and flags
- Git branches and remotes
- Navigation bookmarks
- Project directories

### 2. Enhanced Git Workflow

All Git functions include:
- Visual feedback with emojis
- Status previews before actions
- Interactive confirmations
- Enhanced error handling

### 3. Smart Navigation

The navigation system includes:
- Bookmark management with JSON storage
- Project discovery in code directories
- Recent directory history
- Tab completion for all navigation targets

### 4. Bookmark System

```bash
# Create bookmarks
cb myproject          # Bookmark current directory
cb myproject /path    # Bookmark specific path

# Navigate to bookmarks
nav b myproject       # Go to bookmarked location

# Manage bookmarks
lb                    # List all bookmarks
db myproject          # Delete bookmark
```

### 5. Enhanced Utilities

- **`here`** - Shows current location with Git status and project detection
- **`copy-pwd`** - Copies current directory to clipboard (WSL & Linux)
- **`open-pwd`** - Opens current directory in file manager
- **`back [n]`** - Navigate back n directories or use cd history

## Configuration

### Environment Variables

```bash
export POWERFLOW_VERSION="1.0.5"
export WSL_START_DIRECTORY="/mnt/c/Users/_munya/Code"
export BOOKMARKS_FILE="$HOME/.wsl_bookmarks.json"
```

### zsh Configuration

The configuration includes:
- Oh My Zsh framework
- Auto-suggestions plugin (gray text suggestions)
- Syntax highlighting plugin (green for valid, red for invalid)
- Starship prompt integration
- Custom aliases and functions

### Dependencies

Optional but recommended tools:
- **starship** - Enhanced prompt
- **zoxide** - Smart directory jumping
- **lsd** - Modern ls replacement
- **fzf** - Fuzzy file finder
- **jq** - JSON processing for bookmarks

## Comparison: PowerShell vs zsh

### Similarities

| Feature | PowerShell | zsh |
|---------|------------|-----|
| Auto-completion | IntelliSense | Tab completion |
| Syntax highlighting | ✅ | ✅ (via plugins) |
| Command history | ✅ | ✅ |
| Aliases | ✅ | ✅ |
| Functions | ✅ | ✅ |
| Error handling | ✅ | ✅ |

### zsh Advantages

- **POSIX compliance** - Compatible with bash and most tools
- **Better performance** - Faster startup and execution than Fish
- **Cross-platform** - Works on all Unix-like systems
- **Rich ecosystem** - Oh My Zsh provides hundreds of plugins
- **npm compatibility** - Perfect for Node.js development

## Troubleshooting

### Common Issues

1. **zsh not found after installation**
   ```bash
   which zsh
   echo $SHELL
   # Re-login or restart terminal
   ```

2. **Bookmarks not working**
   ```bash
   # Check if jq is installed
   which jq
   sudo apt install -y jq
   ```

3. **Plugins not working**
   ```bash
   # Check plugins directory
   ls ~/.oh-my-zsh/custom/plugins/
   # Reload zsh
   exec zsh
   ```

4. **Functions not loading**
   ```bash
   # Check config file
   cat ~/.zshrc
   # Source config manually
   source ~/.zshrc
   ```

5. **npm commands still failing**
   ```bash
   # Verify Node.js and npm
   node --version
   npm --version
   # Check PATH
   echo $PATH
   ```

### Getting Help

```bash
# PowerFlow help
help
zsh-help

# zsh built-in help
man zsh
help <command>

# Function definitions
which nav
type git-a
```

## Migration Checklist

- [ ] Install zsh shell
- [ ] Install Oh My Zsh
- [ ] Install zsh plugins
- [ ] Copy configuration files
- [ ] Test basic commands
- [ ] Verify Git functions
- [ ] Set up bookmarks
- [ ] Test navigation
- [ ] Configure optional dependencies
- [ ] Set zsh as default shell (optional)
- [ ] Test Claude Code integration
- [ ] Verify Windows Terminal integration
- [ ] Test npm commands

## Uninstallation

To remove PowerFlow zsh configuration:

```bash
cd ubuntu/
chmod +x uninstall.sh
./uninstall.sh
```

The uninstaller provides options to:
1. Remove configurations only
2. Remove configurations + optional dependencies
3. Remove everything including zsh shell
4. Remove Oh My Zsh
5. Restore previous configurations from backups

## Tips for zsh Users

### 1. Command History
- Use `↑` and `↓` arrows for history
- Use `Ctrl+R` for reverse search
- zsh remembers working directories

### 2. Auto-suggestions
- Gray text shows suggestions from history
- Press `→` or `End` to accept suggestions
- Press `Ctrl+F` to accept one word

### 3. Tab Completion
- Press `Tab` to see completions
- Press `Tab` again to cycle through options
- Works with files, commands, and custom completions

### 4. Command Substitution
```bash
echo $(date)          # Command substitution
var=$(pwd)            # Capture command output
```

### 5. Variables
```bash
export var=value      # Global variable
local var=value       # Local variable
unset var             # Remove variable
```

## Future Enhancements

Planned improvements:
- [ ] Additional Oh My Zsh themes integration
- [ ] Enhanced fuzzy finding with fzf
- [ ] Custom completions for Claude Code
- [ ] More zsh plugins integration
- [ ] Enhanced Starship prompt customization

## Contributing

To contribute to the zsh shell integration:

1. Fork the repository
2. Create a feature branch
3. Test changes thoroughly in zsh
4. Update documentation
5. Submit a pull request

## Resources

- [zsh Documentation](https://zsh.sourceforge.io/Doc/)
- [Oh My Zsh Documentation](https://ohmyz.sh/)
- [PowerFlow Repository](https://github.com/Syntax-Read3r/powerflow)
- [zsh Users Guide](https://zsh.sourceforge.io/Guide/)
- [Starship Documentation](https://starship.rs/)

---

**PowerFlow Fish to zsh Migration - Complete** ⚡✨