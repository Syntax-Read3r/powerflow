# PowerFlow Fish Shell Migration Guide

## Overview

This guide documents the migration from Bash to Fish shell for PowerFlow, providing equivalent functionality with Fish's superior auto-completion and user experience that closely resembles PowerShell.

## Why Fish Shell?

Fish shell was chosen for the following reasons:

1. **Intelligent Auto-completion** - Similar to PowerShell's IntelliSense
2. **Syntax Highlighting** - Commands are colored as you type
3. **Auto-suggestions** - Based on command history and completions
4. **Better Error Messages** - More user-friendly than Bash
5. **Modern Shell Features** - Web-based configuration, better scripting syntax

## Migration Summary

### Files Updated

| File | Purpose | Status |
|------|---------|---------|
| `config.fish` | Main Fish configuration with all PowerFlow functions | ✅ Complete |
| `nav.fish` | Enhanced navigation completions for Fish | ✅ Complete |
| `install.sh` | Updated installation script for Fish setup | ✅ Complete |
| `uninstall.sh` | Enhanced uninstaller supporting both Bash and Fish | ✅ Complete |

### Function Equivalency

All PowerShell profile functions have been ported to Fish with equivalent or enhanced functionality:

#### Core Functions Ported

| PowerShell Function | Fish Equivalent | Status | Notes |
|-------------------|-----------------|---------|--------|
| `claude`, `cc` | `claude`, `cc` | ✅ | Direct port |
| `explain` | `explain` | ✅ | Enhanced with file validation |
| `fix` | `fix` | ✅ | Direct port |
| `build` | `build` | ✅ | Direct port |
| `review` | `review` | ✅ | Direct port |
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
| `fish-help`/`help` | Comprehensive help system | `help` |

## Installation

### Quick Install

```bash
cd ubuntu/
chmod +x install.sh
./install.sh
```

### Manual Setup

1. **Install Fish Shell**
   ```bash
   sudo apt update && sudo apt install -y fish
   echo /usr/bin/fish | sudo tee -a /etc/shells
   ```

2. **Copy Configuration Files**
   ```bash
   mkdir -p ~/.config/fish/completions
   cp config.fish ~/.config/fish/
   cp nav.fish ~/.config/fish/completions/
   ```

3. **Set Fish as Default Shell** (Optional)
   ```bash
   chsh -s /usr/bin/fish
   ```

## Key Features

### 1. Intelligent Auto-completion

Fish provides context-aware completions for:
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

```fish
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

```fish
set -g POWERFLOW_VERSION "1.0.4"
set -g WSL_START_DIRECTORY "/mnt/c/Users/_munya/Code"
set -g BOOKMARKS_FILE "$HOME/.wsl_bookmarks.json"
```

### Fish Colors

The configuration includes custom colors for:
- Command highlighting (blue)
- Error messages (red)
- Parameters (cyan)
- Quotes (yellow)
- Redirections (magenta)

### Dependencies

Optional but recommended tools:
- **starship** - Enhanced prompt
- **zoxide** - Smart directory jumping
- **lsd** - Modern ls replacement
- **fzf** - Fuzzy file finder
- **jq** - JSON processing for bookmarks

## Comparison: PowerShell vs Fish

### Similarities

| Feature | PowerShell | Fish |
|---------|------------|------|
| Auto-completion | IntelliSense | Tab completion |
| Syntax highlighting | ✅ | ✅ |
| Command history | ✅ | ✅ |
| Aliases | ✅ | ✅ |
| Functions | ✅ | ✅ |
| Error handling | ✅ | ✅ |

### Fish Advantages

- **No learning curve** - Familiar shell syntax
- **Better performance** - Faster startup and execution
- **Cross-platform** - Works on all Unix-like systems
- **Better scripting** - More intuitive syntax than Bash
- **Built-in features** - No need for external modules

## Troubleshooting

### Common Issues

1. **Fish not found after installation**
   ```bash
   which fish
   echo $SHELL
   # Re-login or restart terminal
   ```

2. **Bookmarks not working**
   ```bash
   # Check if jq is installed
   which jq
   sudo apt install -y jq
   ```

3. **Completions not working**
   ```bash
   # Check completions directory
   ls ~/.config/fish/completions/
   # Restart Fish
   exec fish
   ```

4. **Functions not loading**
   ```bash
   # Check config file
   cat ~/.config/fish/config.fish
   # Source config manually
   source ~/.config/fish/config.fish
   ```

### Getting Help

```fish
# PowerFlow help
help
fish-help

# Fish built-in help
help
help <command>

# Function definitions
functions nav
type git-a
```

## Migration Checklist

- [ ] Install Fish shell
- [ ] Copy configuration files
- [ ] Test basic commands
- [ ] Verify Git functions
- [ ] Set up bookmarks
- [ ] Test navigation
- [ ] Configure optional dependencies
- [ ] Set Fish as default shell (optional)
- [ ] Test Claude Code integration
- [ ] Verify Windows Terminal integration

## Uninstallation

To remove PowerFlow Fish configuration:

```bash
cd ubuntu/
chmod +x uninstall.sh
./uninstall.sh
```

The uninstaller provides options to:
1. Remove configurations only
2. Remove configurations + optional dependencies
3. Remove everything including Fish shell
4. Restore previous configurations from backups

## Tips for Fish Users

### 1. Command History
- Use `↑` and `↓` arrows for history
- Use `Ctrl+R` for reverse search
- Fish remembers working directories

### 2. Auto-suggestions
- Gray text shows suggestions from history
- Press `→` or `End` to accept suggestions
- Press `Ctrl+F` to accept one word

### 3. Tab Completion
- Press `Tab` to see completions
- Press `Tab` again to cycle through options
- Works with files, commands, and custom completions

### 4. Command Substitution
```fish
echo (date)           # Command substitution
set var (pwd)         # Capture command output
```

### 5. Variables
```fish
set -g var value      # Global variable
set -l var value      # Local variable
set -e var            # Erase variable
```

## Future Enhancements

Planned improvements:
- [ ] Fish-specific themes integration
- [ ] Enhanced fuzzy finding with fzf
- [ ] Custom completions for Claude Code
- [ ] Web-based configuration interface
- [ ] Plugin system for extensions

## Contributing

To contribute to the Fish shell integration:

1. Fork the repository
2. Create a feature branch
3. Test changes thoroughly
4. Update documentation
5. Submit a pull request

## Resources

- [Fish Shell Documentation](https://fishshell.com/docs/current/)
- [PowerFlow Repository](https://github.com/Syntax-Read3r/powerflow)
- [Fish Tutorial](https://fishshell.com/docs/current/tutorial.html)
- [Fish FAQ](https://fishshell.com/docs/current/faq.html)

---

**PowerFlow Fish Shell Migration - Complete** 🐠✨