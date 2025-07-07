## Features

> 🐧 **Cross-Platform Excellence**: PowerFlow delivers complete feature parity between Windows (PowerShell) and Ubuntu/WSL (Bash) environments with bidirectional integration and seamless workflow transitions.

### 🧭 Smart Navigation System

- **Intelligent project search** - Quickly navigate to projects with fuzzy matching across ~/Code and bookmarked directories
- **Persistent bookmarks** - Save frequently used directories with memorable names, persisted across sessions in JSON format
- **Context-aware navigation** - Automatically detects your working environment and adapts search behavior
- **Configurable auto-navigation** - Start in your preferred directory (like VSCode's workspace behavior) with easy configuration
- **Nested project discovery** - Advanced search algorithms find projects buried in complex directory structures

### 📁 Enhanced File Operations

- **Fuzzy search file operations** - Move, rename, and delete files using partial names with intelligent matching
- **Cut-and-paste workflow** - Modern file management with `mv` to cut, `mv-t` to paste, and `mv-c` to cancel
- **Safety-first design** - Confirmation prompts and backup creation prevent accidental data loss
- **Beautiful directory listings** - Modern file views with icons, colors, and tree structures using `lsd`
- **Smart completion** - PowerShell-like predictive text with history-based suggestions and case-insensitive matching

### 🚀 Streamlined Git Workflow

- **One-command releases** - Update version and release with `git-a -vr` for instant GitHub releases
- **Automated release generation** - GitHub Actions integration creates install scripts and release notes automatically
- **Interactive commit workflow** - Beautiful fuzzy-search interface for staging, committing, and pushing changes
- **Smart rollback system** - Create rollback branches from any commit with automatic naming and branch management
- **Branch management** - Interactive branch switching, creation, and deletion with safety checks
- **Cross-platform Git tools** - Identical Git workflow available in both PowerShell and Bash environments

### 🔗 GitHub Integration

- **Repository browser** - List, filter, and manage your GitHub repositories with commit activity statistics
- **Secure token management** - GitHub tokens stored safely in Windows Credential Manager with automatic fallback
- **One-click actions** - Clone, browse, or delete repositories directly from the terminal interface
- **Rate limit handling** - Intelligent API usage with automatic cooldowns and error recovery

### 🎨 Beautiful User Experience

- **Starship prompt integration** - Modern, informative prompt with Git status, language detection, and performance metrics
- **Consistent visual design** - Emoji indicators, color schemes, and formatting create intuitive interfaces
- **Clipboard integration** - All operations automatically copy relevant data (paths, hashes, URLs) to clipboard
- **Fuzzy search everywhere** - fzf integration provides fast, searchable interfaces for all interactive commands
- **Live previews** - File and directory previews with syntax highlighting and tree views in fuzzy finder

### 🔍 Advanced Search & Discovery

- **FZF integration** - Powerful fuzzy finding with customizable themes and intelligent previews
- **History-based prediction** - Command history search with real-time filtering and completion
- **Multi-modal search** - File finder (Ctrl+T), command history (Ctrl+R), and directory navigation (Alt+C)
- **Smart file type detection** - Automatic syntax highlighting and appropriate preview generation
- **Cross-platform file access** - Seamless navigation between Windows and WSL file systems

### 🛡️ Safety & Reliability

- **Destructive operation protection** - Multiple confirmations and safety checks prevent accidental deletions
- **Current branch protection** - Prevents deletion or modification of active Git branches
- **Version validation** - Ensures profile versions match Git tags before releases
- **Automatic dependency management** - Installs and configures required tools automatically with daily checks
- **Self-healing capabilities** - Built-in recovery tools and diagnostic functions for troubleshooting
- **Graceful degradation** - Fallback behaviors when optional dependencies are unavailable

### ⚙️ System Integration

- **Windows Terminal optimization** - Enhanced tab management and terminal control functions
- **PowerShell profile enhancement** - Extends native PowerShell with productivity-focused aliases and functions
- **Cross-session persistence** - Bookmarks, settings, and preferences maintained across sessions
- **Auto-update system** - Built-in version checking and update mechanisms with conflict resolution
- **Ubuntu/WSL full parity** - Complete feature compatibility with Linux environments via enhanced .bashrc
- **Intelligent path translation** - Automatic Windows ↔ WSL path conversion for seamless cross-platform workflows

### 🖥️ Cross-Platform Terminal Management

- **Bidirectional terminal launching** - Open PowerShell tabs from Ubuntu and Ubuntu tabs from PowerShell
- **Smart path preservation** - Automatically translates and preserves current directory across shell switches
- **Universal shell shortcuts** - `open-nt p` (PowerShell), `open-nt u` (Ubuntu), `open-nt cmd` (Command Prompt)
- **Advanced tab control** - Navigate between tabs with `next-t`, `prev-t`, and numbered tab switching
- **Profile-aware launching** - Automatically detects and uses correct Windows Terminal profiles
- **Keyboard automation** - Uses xdotool (Linux) or SendKeys (Windows) for seamless tab management

### 🎯 Productivity Features

- **One-command workflows** - Complex operations simplified into single, memorable commands
- **Intelligent defaults** - Smart parameter detection and context-aware behavior
- **Extensive help system** - Comprehensive documentation accessible via help commands
- **Quick configuration** - Interactive setup menus for customizing behavior without editing config files
- **Performance optimization** - Lazy loading and daily dependency checks minimize startup time
- **Error recovery** - Comprehensive recovery menus with guided troubleshooting steps

### 🔧 Developer Experience

- **Modern toolchain integration** - Works seamlessly with VS Code, Git, Node.js, and other development tools
- **Extensible architecture** - Easy to customize and extend with additional functionality
- **Cross-platform consistency** - Identical command syntax and behavior across Windows and Linux
- **Professional workflows** - Supports enterprise development patterns and team collaboration
- **Version management** - Built-in update mechanisms and version tracking for easy maintenance
