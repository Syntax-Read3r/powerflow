## Features

> 🐧 **Cross-Platform Support**: PowerFlow now supports both Windows (PowerShell) and Ubuntu/WSL (Bash) environments with feature parity across platforms.

### 🧭 Smart Navigation System
- **Intelligent project search** - Quickly navigate to projects with fuzzy matching across ~/Code and bookmarked directories
- **Persistent bookmarks** - Save frequently used directories with memorable names, persisted across sessions
- **Context-aware navigation** - Automatically detects your working environment and adapts search behavior

### 📁 Enhanced File Operations  
- **Fuzzy search file operations** - Move, rename, and delete files using partial names with intelligent matching
- **Cut-and-paste workflow** - Modern file management with `mv` to cut, `mv-t` to paste, and `mv-c` to cancel
- **Safety-first design** - Confirmation prompts and backup creation prevent accidental data loss
- **Beautiful directory listings** - Modern file views with icons, colors, and tree structures using `lsd`

### 🚀 Streamlined Git Workflow
- **One-command releases** - Update version and release with `git-a -vr` for instant GitHub releases
- **Automated release generation** - GitHub Actions integration creates install scripts and release notes automatically  
- **Interactive commit workflow** - Beautiful fuzzy-search interface for staging, committing, and pushing changes
- **Smart rollback system** - Create rollback branches from any commit with automatic naming and branch management
- **Branch management** - Interactive branch switching, creation, and deletion with safety checks

### 🔗 GitHub Integration
- **Repository browser** - List, filter, and manage your GitHub repositories with commit activity statistics
- **Secure token management** - GitHub tokens stored safely in Windows Credential Manager
- **One-click actions** - Clone, browse, or delete repositories directly from the terminal interface

### 🎨 Beautiful User Experience
- **Starship prompt integration** - Modern, informative prompt with Git status, language detection, and performance metrics
- **Consistent visual design** - Emoji indicators, color schemes, and formatting create intuitive interfaces
- **Clipboard integration** - All operations automatically copy relevant data (paths, hashes, URLs) to clipboard
- **Fuzzy search everywhere** - fzf integration provides fast, searchable interfaces for all interactive commands

### 🛡️ Safety & Reliability
- **Destructive operation protection** - Multiple confirmations and safety checks prevent accidental deletions
- **Current branch protection** - Prevents deletion or modification of active Git branches
- **Version validation** - Ensures profile versions match Git tags before releases
- **Automatic dependency management** - Installs and configures required tools (Starship, fzf, zoxide, lsd) automatically

### ⚙️ System Integration
- **Windows Terminal optimization** - Enhanced tab management and terminal control functions
- **PowerShell profile enhancement** - Extends native PowerShell with productivity-focused aliases and functions  
- **Cross-session persistence** - Bookmarks, settings, and preferences maintained across PowerShell sessions
- **Auto-update system** - Built-in version checking and update mechanisms for seamless maintenance
- **Ubuntu/WSL support** - Full feature compatibility with Linux environments via enhanced .bashrc