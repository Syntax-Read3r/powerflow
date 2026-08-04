# 🚀 PowerFlow

> A beautiful, intelligent PowerShell profile that supercharges your terminal experience with smart navigation, enhanced Git workflows, and productivity-focused tools.

[![Latest Release](https://img.shields.io/github/v/release/Syntax-Read3r/powerflow)](https://github.com/Syntax-Read3r/powerflow/releases)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Windows Terminal](https://img.shields.io/badge/Windows%20Terminal-Recommended-brightgreen.svg)](https://github.com/microsoft/terminal)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## 🎬 Demo

<div align="center">

### See PowerFlow in Action!

<!-- Upload demo-video.mp4 to GitHub Issues to get the CDN link, then replace this line: -->
<!-- https://github.com/Syntax-Read3r/powerflow/assets/USER_ID/VIDEO_ID.mp4 -->

![PowerFlow Demo](assets/demo-pic.png)

### Feature Screenshots

<img src="assets/demo-pic-1.png" width="45%" alt="PowerFlow Git Workflow"/> <img src="assets/demo-pic-2.png" width="45%" alt="PowerFlow File Operations"/>

_🎥 **Full video demo**: Upload `assets/demo-video.mp4` to a GitHub issue to get the embeddable link_

</div>

## ✨ Features

### 🧭 Smart Navigation System

- **Intelligent Project Search**: `nav chess-guru` finds projects across multiple directories
- **Persistent Bookmarks**: Create, manage, and navigate to frequently used locations
- **Fuzzy Search Integration**: Beautiful fzf interfaces for everything
- **Context-Aware Navigation**: Adapts based on your current location

### 🎯 Enhanced Git Workflow

- **Beautiful Add-Commit-Push**: Interactive workflow with visual feedback
- **Repository-Based Versioning**: Auto-increment versions from git tags
- **Rollback System**: Create rollback branches from any commit safely
- **Interactive Branch Manager**: Pick, create, delete branches with visual interface
- **GitHub Integration**: Browse, clone, and manage your repositories with token security

### ✂️ File Operations That Speak Bash

- **Real GNU flags**: `rm -rf`, `mkdir -p a/b/c`, `touch -c`, `ls -la` — your muscle
  memory just works, on Windows too
- **Move or cut**: `mv old.txt new.txt` moves like bash; `mv filename` cuts, `mv-t` pastes
- **Interactive Rename**: Beautiful interface for renaming files
- **Safety Checks**: `rm <dir>` without `-r` refuses, like GNU — a typo'd path should
  not take a tree with it

### 🎓 It Teaches You Linux While You Use It

- **`lesson <command>` / `l <command>`**: learn any command — runs nothing, always safe.
  24 lessons across 7 topics, with tab-completion
- **Brother commands**: `changemode` → `chmod`, `findtext` → `grep`, `dirsize` → `du` and
  20 more — same flags, same result, and each prints the real command it ran
- **`perms <path>`**: file permissions with every column actually labelled
- **`linux-lessons full|hint|off`**: teaching is a phase, not a permanent state

### 🌐 Servers by Name, Not by IP

- **`srv proxmox`** instead of `ssh you@192.168.1.50` — connections saved by name
- **Live status in the picker**: `✅ online` · `🟡 host up, ssh not answering` ·
  `⛔ offline · last seen Jul 17` — so you know to press the power button, not retry
- **Tested before saving**: `srv add` probes the SSH port first, catching typo'd IPs

### 🖥️ Machine Health at a Glance

- **`pc-whoami`**: CPU, GPU, RAM spec, drives, free ports/slots, BIOS age, power plan,
  hardware errors — one screen, no hex, no GUIDs. Custom/OEM power plans get flagged
- **`pc-whoami -ram`**: a map of where your memory is, in five levels — `huge` `large`
  `medium` `small` `tiny`. Read-only, five rows instead of 167. Open one with `-ram huge`
- **`pc-whoami -ram java`**: that program's processes with **command lines**, so you can tell
  eight javas apart. Enter closes one process (confirm with its PID), ctrl-a closes the whole
  program (warned harder) — system-critical processes and your own shell are never killed
- **`pc-cap 85` / `pc-cap restore`**: cap CPU speed with **guaranteed restoration** —
  the prior state is recorded to disk before anything changes
- **`team-room`**: every AI agent watcher on the machine, and whether it is actually
  **live** — then `team-room stop <name>` ends it. Previously you could only ask the agent
  to stop itself

### ⚡ Proxmox Without the Incantations (Linux)

- **`pmx`**: node, disks, ZFS pools, guests and pending updates — one command instead of
  `pvesh` + `lsblk` + `smartctl` + `zpool` + `journalctl`
- **`pmx disk sdg report`**: *is this drive genuine?* Zero WWN, a generic model string, a
  six-digit serial, a drive that refuses SMART, a size that disagrees with itself, kernel
  I/O errors — each is evidence, and the report says which fired and what it means
- **`-Write`** saves the whole bundle (report, raw SMART, kernel log, stable IDs) so a
  refund request is a file you attach, not a story you tell

### 🎨 Beautiful Interface

- **FiraCode Nerd Font**: Auto-installed for perfect icon display
- **Starship Prompt**: Cross-shell prompt with Git integration
- **Color-Coded Output**: Consistent visual feedback throughout
- **Auto-Update System**: Keeps PowerFlow current with latest features

### 🪟 Terminal Enhancement

- **Tab Management**: Create, switch, and close Windows Terminal tabs
- **Auto-Dependency Management**: Automatically installs required tools
- **Comprehensive Help**: Built-in documentation system
- **Performance Optimized**: Fast loading with smart caching

## 💻 Code Examples

```powershell
# Smart navigation - finds projects intelligently
nav my-react-app

# Enhanced Git workflow
git-a               # Beautiful add → commit → push interface
git-rl              # Interactive release: pick patch/minor/major, commit, tag, push

# Cut and paste files
mv important-file   # Cuts file
# Navigate to destination
mv-t               # Pastes file

# Interactive Git log
git-l              # Beautiful log viewer with actions

# GitHub repo browser
gh-l               # Browse your repos with activity stats

# Learn Linux as you go
l grep             # a lesson on grep — runs nothing, always safe
perms ward-a       # permissions with every column explained
changemode 775 dir # runs chmod 775, and tells you it did

# Machine health
pc-whoami          # CPU, GPU, RAM, drives, BIOS age, power, errors — one screen
pc-whoami -ram     # a map of where your RAM went, in five levels
pc-whoami -ram huge # open the level that matters — then drill in to close something

# Check for updates
powerflow-update   # Full-tree update via the real installer
```

## ⚡ Quick Installation

PowerFlow runs on **Windows and Linux** from one codebase.

### 🪟 Windows

```powershell
irm https://github.com/Syntax-Read3r/powerflow/releases/latest/download/install.ps1 | iex
```

### 🐧 Linux

```bash
# terminal — and start PowerFlow automatically on login
curl -fsSL https://github.com/Syntax-Read3r/powerflow/releases/latest/download/install.sh | bash -s -- --auto-login

# ...or a graphical installer (zenity / kdialog / yad)
curl -fsSL https://github.com/Syntax-Read3r/powerflow/releases/latest/download/install-gui.sh -o install-gui.sh
bash install-gui.sh
```

The Linux installer installs PowerShell if you don't have it (Debian, Ubuntu, Fedora,
Arch, openSUSE, Alpine), then PowerFlow, its dependencies, and a Nerd Font.

> #### ⚠️ On Linux, PowerFlow only loads when `pwsh` runs
>
> It is a PowerShell *profile*. Your login shell is normally bash, so after a reboot you
> land in bash and PowerFlow is **not there** — nothing is broken, you're just in a
> different shell. **`--auto-login`** (above) handles this by adding a guarded block to
> `~/.bashrc`. Already installed without it? Turn it on from inside PowerFlow — no
> re-install:
>
> ```
> pwsh-autologin          # start PowerFlow on login  (pwsh-autologin off to undo)
> ```
>
> The hook is guarded: if pwsh is ever removed or broken you still get bash, so you can't
> be locked out of your own server. Test it without logging out with `bash -l`.

> #### 🎨 If the prompt or `ls` shows boxes / Chinese characters
>
> That's a **missing Nerd Font** — Starship and lsd draw with special glyphs. The installer
> now installs one, but a font can only be *set* by you:
>
> ```
> pwsh-font          # install the font (if needed) and print the one terminal step
> ```
>
> Then set your terminal's font to **FiraCode Nerd Font Mono**. The Mono variant keeps
> lsd's icons from overlapping filenames.

### 🐧 Linux keeps its GNU coreutils

`rm`, `mv`, `cp`, `cat`, `grep` and friends stay the **real GNU tools** — PowerFlow never
shadows them. Its own versions are **`del`** and **`mvf`**.

### Prerequisites

| | |
|---|---|
| **Windows** | PowerShell 5.1+ (7+ recommended) · Windows 10/11 or Server 2016+ |
| **Linux** | Any distro with apt / dnf / pacman / zypper / apk (PowerShell 7 is installed for you) |
| **Both** | Internet connection, for dependency installation |

**📖 [Complete Installation Guide](docs/installation.md)** · **[Upgrading from v2.x](docs/migration/v3-upgrade.md)**

## 🚀 What Happens After Installation?

PowerFlow automatically sets up your environment:

1. **🎨 Installs FiraCode Nerd Font** - Scoop on Windows, direct download + `fc-cache`
   on Linux (re-run any time with `pwsh-font`)
2. **📦 Installs Dependencies** - Starship, fzf, zoxide, lsd (Scoop / your distro's
   package manager)
3. **🔖 Creates Default Bookmarks** - Quick access to common directories
4. **🔄 Enables Auto-Updates** - Stay current with latest features
5. **💡 Shows Setup Tips** - Points you at the one manual step: setting the terminal font

### Final Setup Step

**Configure Windows Terminal Font:**
1. Open Windows Terminal → Settings (`Ctrl+,`)
2. Go to your PowerShell profile → Appearance
3. Set **Font face** to `FiraCode Nerd Font`
4. Restart terminal and enjoy! 🎉

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
git-rl               # Interactive release: bump version, commit, tag, push

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
ls --tree            # Tree view with smart depth
ls -t                # Sort by time (real GNU flag)
```

### GitHub Integration

```powershell
# Browse your repositories
gh-l                 # List repos with activity stats
gh-l 20              # Show top 20 repos

# Token management (automatic secure storage)
gh-l-status          # Check if token is saved
gh-l-reset           # Remove saved token
```

## 🔧 Version Control Setup

### Release Workflow

PowerFlow releases are managed through `git-rl` (`git-release`), an interactive fzf workflow that handles the full release pipeline in one command.

#### How It Works

```powershell
git-rl   # or: git-release
```

The workflow:
1. Reads the current version from `config/PowerFlow.settings.ps1`
2. Presents a bump-type selector (patch / minor / major / custom)
3. Prompts for a release description
4. Updates `config/PowerFlow.settings.ps1` to the new version
5. Commits all staged changes, pushes, creates the tag, and pushes the tag

**Example Flow:**
- **Current**: `v2.0.1` + pick **patch** → **Next**: `v2.0.2`
- **Current**: `v2.0.1` + pick **minor** → **Next**: `v2.1.0`
- **Current**: `v2.0.1` + pick **major** → **Next**: `v3.0.0`

#### Setting Up Development Environment

For PowerFlow development and contributions:

```powershell
# 1. Fork and clone the repository
git clone https://github.com/your-username/powerflow.git
cd powerflow

# 2. Set up upstream remote
git remote add upstream https://github.com/Syntax-Read3r/powerflow.git

# 3. Create development branch
git checkout -b feature/your-feature-name

# 4. Make your changes and test
# Edit files in components/ — the profile is now a bootloader
# that dot-sources 28 component files under components/ and config/
# Test your changes thoroughly

# 5. Commit and push your changes
git-a                # Use PowerFlow's own workflow!

# 6. Create pull request to upstream
```

#### Version Release Workflow

For maintainers creating releases:

```powershell
# 1. Ensure you're on main branch with latest changes
git checkout main
git pull upstream main

# 2. Run the release workflow
git-rl              # fzf picker: choose patch/minor/major/custom

# This will:
# - Present a version bump selector
# - Update config/PowerFlow.settings.ps1 to the new version
# - Commit all changes with a versioned commit message
# - Push the commit to remote
# - Create and push the version tag (e.g., v2.0.2)
# - Trigger the GitHub Actions release pipeline
```

#### Manual Version Control

If you need to manage tags directly:

```powershell
# View tag history
git tag --list --sort=-version:refname

# Delete incorrect tags
git tag -d v2.0.0           # Delete locally
git push origin :v2.0.0     # Delete remotely
```

#### GitHub Actions Integration

PowerFlow includes automated release workflows:

- **🔍 Validation**: Checks profile syntax and version consistency
- **📦 Build**: Creates install scripts and release assets
- **🚀 Release**: Creates GitHub release with downloadable files
- **🔔 Notifications**: Updates auto-update system

**Release Process:**
1. Push version tag → Triggers workflow
2. Workflow validates and builds release
3. Creates GitHub release with install scripts
4. Users get auto-update notifications

#### Best Practices

**For Contributors:**
- Always test your changes thoroughly
- Use descriptive commit messages
- Create feature branches for new work
- Don't create version tags (maintainers only)

**For Maintainers:**
- Use `git-rl` for all version releases
- Update `CHANGELOG.md` before running `git-rl`
- Test the release workflow in development
- Monitor GitHub Actions for build status

**Version Tag Format:**
- ✅ `v1.0.0` - Semantic versioning with 'v' prefix
- ✅ `v1.2.3` - Major.Minor.Patch format
- ❌ `1.0.0` - Missing 'v' prefix
- ❌ `v1.0` - Incomplete version number

## 📚 Complete Feature Reference

### Smart Navigation & Bookmarks

| Command               | Description                              |
| --------------------- | ---------------------------------------- |
| `nav <project>`       | Smart project search with fuzzy matching |
| `nav b <bookmark>`    | Navigate to bookmark                     |
| `nav create-b <name>` | Create bookmark from current directory   |
| `nav delete-b <name>` | Delete bookmark with confirmation        |
| `nav list`            | Interactive bookmark manager             |
| `nav roots`           | Show where nav searches (Win: `~/Code` · Linux: `~`) |
| `nav roots add /srv`  | Also search `/srv` (or `/opt`, `/mnt/data`, …) |
| `..`, `...`, `....`   | Quick parent directory navigation        |

### Enhanced Git Workflow

| Command           | Description                                          |
| ----------------- | ---------------------------------------------------- |
| `git-a`           | Beautiful add → commit → push workflow               |
| `git-rl`          | Interactive release: bump version, commit, tag, push. Works in **any** project — reads `package.json`, `pyproject.toml`, `Cargo.toml`, `*.csproj`, `build.gradle`, `VERSION`, and keeps multiple version files in sync |
| `git-rl -h`       | Set up `git-rl` in **another** project — writes a guide into it and copies an AI setup prompt to your clipboard |
| `git-rb <commit>` | Create rollback branch from commit                   |
| `git-rba`         | Rollback branch add-commit-push                      |
| `git-mrb`         | Merge rollback branch to main                        |
| `git-l`           | Interactive log viewer with actions                  |
| `git-b`           | Branch picker and manager                            |
| `git-s`           | Interactive status viewer                            |

### File Operations

Single dash is Linux's, long dash is PowerFlow's: `ls -t` sorts by time (GNU),
`ls --tree` is PowerFlow's tree view. On Linux the real GNU coreutils stay untouched —
PowerFlow's versions live on as `del` and `mvf`.

| Command             | Description                                        |
| ------------------- | -------------------------------------------------- |
| `mv <src> <dst>`    | Move or rename, like bash (`-f` force, `-n` never overwrite) |
| `mv <a> <b> <dir>/` | Move several files into a directory                |
| `mv <file>`         | ✂️ Cut for moving (1 arg = cut, 2+ = move)          |
| `mv-t`              | Paste cut file                                     |
| `rn [file]`         | Interactive file rename                            |
| `rm`                | fzf picker, then confirm before deleting           |
| `rm -rf <dir>`      | Recursive force remove — bash muscle memory works  |
| `rm *.log`          | Wildcard removal — lists every match, one confirm  |
| `mkdir -p a/b/c`    | Create the whole chain                             |
| `touch -c <file>`   | Bump timestamp only if it exists — never truncates |
| `ls -la` / `ls -t`  | Real GNU flags (list all / sort by time)           |
| `ls --tree`         | PowerFlow's tree view with smart depth             |

### Learn Linux While You Use It

| Command                | Description                                      |
| ---------------------- | ------------------------------------------------ |
| `lesson <command>`     | Learn any command — runs nothing, always safe    |
| `l grep` · `l rm`      | Shorthand; tab-completes commands and topics     |
| `lesson permissions`   | Every lesson in a topic (7 topics, 24 lessons)   |
| `perms <path>`         | Permissions with every column labelled           |
| `changemode 775 <dir>` | Brother of `chmod` — same flags, teaches the real command |
| `dirsize -sh *`        | Brother of `du` (also: `diskfree`, `listports`, `systemlogs`, …) |
| `defaultmode 022`      | The umask, with what it actually produces        |
| `linux-lessons off`    | Hide the teaching (`full` · `hint` · `off`)      |

### Machine Health

| Command              | Description                                       |
| -------------------- | ------------------------------------------------- |
| `pc-whoami`          | Vitals: power plan, CPU cap, HW errors, BIOS age  |
| `pc-whoami -power`   | Every power plan, caps decoded — no hex, no GUIDs |
| `pc-whoami -crashes` | Hardware errors, bugchecks, dumps (`-export` bundles the evidence) |
| `pc-whoami -bios`    | Firmware version, age, board model                |
| `pc-whoami -ram`     | The map: how much memory sits in each level (read-only) |
| `pc-whoami -ram huge`| One level: `huge` · `large` · `medium` · `small` · `tiny` (`-min N` for a custom cut-off) |
| `pc-whoami -ram java`| That program's processes with **command lines** — Enter closes one, ctrl-a closes all |
| `pc-cap 85`          | Cap CPU speed — prior state recorded for safe undo |
| `pc-cap restore`     | Put back exactly what was recorded                |
| `team-room`          | Every agent watcher on this machine — which are **live**, and stop them |
| `team-room stop <name>` | Stop a room: disarm it and end its watcher process |
| `team-room start <name>`| Re-arm a room you previously set up (arm is boot-scoped) |

### Proxmox VE (Linux)

`pmx` is one command for the things you otherwise reach for `pvesh`, `lsblk`, `smartctl`,
`zpool` and `journalctl` to answer. It runs **only on a Proxmox node** — everywhere else
every verb but `help` says so plainly rather than rendering an empty dashboard.

| Command                  | Description                                     |
| ------------------------ | ----------------------------------------------- |
| `pmx`                    | Node dashboard: uptime, load, memory, storage, guests, updates |
| `pmx disks`              | Every physical disk — model, size, SSD/HDD, what is using it |
| `pmx disk sdg`           | One disk in full: stable IDs, SMART, and what would be destroyed |
| `pmx disk sdg smart`     | The SMART report, decoded                       |
| `pmx disk sdg report`    | **Is this drive genuine?** Evidence-based authenticity + health verdict |
| `pmx disk sdg report -Write` | Save the evidence bundle (report, raw SMART, kernel log, IDs) for an RMA |
| `pmx pools` / `pmx guests` / `pmx updates` | ZFS pools · VMs and containers · pending updates |

### Appearance & Login

| Command                | Description                                              |
| ---------------------- | ------------------------------------------------------- |
| `pwsh-font`            | Install the Nerd Font, then show the terminal-font step  |
| `pwsh-font -status`    | Is the font installed? (installs nothing)                |
| `pwsh-autologin`       | Start PowerFlow on login — no installer re-run (Linux)   |
| `pwsh-autologin off`   | Stop starting on login                                   |
| `pwsh-exit`            | Drop to bash without closing your SSH session (Linux)    |
| `pwsh-config`          | Menu that **applies** OS settings: timezone, locale, hostname, time-sync (+ keyboard on Linux) |
| `start-folder`         | Manage what runs at login — Enter toggles, ctrl-d deletes (alias `startup`) |

### System

| Command                  | Description                                     |
| ------------------------ | ----------------------------------------------- |
| `shutdown 1h 30m`        | Schedule a shutdown (10 min – 6 hr range)        |
| `shutdown cancel` / `s c`| Cancel a scheduled shutdown                     |
| `set-path <dir>`         | Add a directory to the User PATH (no quotes)     |
| `set-path -system <dir>` | Add to the System PATH (requires Administrator)  |

### Disk Reclaim

Nothing below **1 GB** is ever listed, and a query **cannot span two size bands** —
an unreviewable list in front of a delete action is how people destroy things.

| Command                  | Description                                             |
| ------------------------ | ------------------------------------------------------- |
| `installed-apps -o`      | Overview of every size band, then drill into one         |
| `installed-apps`         | Pick a size band, then browse installed apps             |
| `installed-apps 2gb-4gb` | Apps in a range (must fit inside a single band)          |
| `disk-big`               | Large **folders and files** (vhdx, node_modules, caches) |
| `disk-big 50gb-200gb`    | The biggest offenders on disk                            |
| `disk-big -Path D:\`     | Scan a specific location instead of the usual hot spots  |

Bands: `1–5 GB` · `5–20 GB` · `20–50 GB` · `50 GB+`.
Each row shows **size and age** — big *and* old is the strongest reclaim signal.
Actions: open folder · copy path · **uninstall properly** · Recycle Bin · permanent delete.
Protected system paths are refused outright, and virtual disks (`.vhdx`/`.vmdk`) warn that
deleting them destroys every container and volume inside.

### Version Management

| Command              | Description                      |
| -------------------- | -------------------------------- |
| `powerflow-version`  | Show PowerFlow version info      |
| `powerflow-update`   | Full-tree update via the real installer |
| `Get-PowerFlowVersion` | Detailed version information   |

On startup, PowerFlow checks for updates once a day (via the `releases/latest`
redirect — no API quota) and offers: **install now · remind me tomorrow · snooze a
week · turn off**. Piped/non-interactive shells get one quiet line, never a prompt.

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
| `pwsh-h`        | The command manual — grouped, scroll to read (`pwsh-h -a` for the fzf browser, `pwsh-h git` filters) |
| `pwsh-help`     | Long alias for `pwsh-h` (`pwsh-help -advanced` = `pwsh-h -a`) |

## 🔧 Configuration

### Auto-Installed Dependencies

PowerFlow automatically installs these tools via Scoop:

- **Starship**: Cross-shell prompt with Git integration
- **fzf**: Fuzzy finder for interactive selection
- **zoxide**: Smart directory navigation with learning
- **lsd**: Modern ls replacement with icons
- **git**: Version control system
- **FiraCode Nerd Font**: Beautiful font with programming ligatures

### Customization

```powershell
pwsh-profile  # Opens profile in VS Code for editing
```

### Disable Features

Edit `config/PowerFlow.settings.ps1` and set any of these flags to `$false`:

```powershell
$script:CHECK_DEPENDENCIES = $false    # Skip dependency checks
$script:CHECK_UPDATES = $false         # Skip PowerShell update checks  
$script:CHECK_PROFILE_UPDATES = $false # Skip PowerFlow update checks
```

## 🔄 Auto-Update System

PowerFlow includes intelligent update management:

- **Daily Update Checks** - Respectful, once-per-day maximum
- **Version Notifications** - Beautiful interface when updates available
- **One-Click Updates** - Automatic backup and update process
- **Rollback Safety** - Easy recovery if issues occur

```powershell
# Manual update commands
powerflow-update        # Force check for updates
powerflow-version       # Show current version info
```

## 🛡️ Safety Features

- **Automatic Backups**: Profile backed up before updates
- **Current Branch Protection**: Prevents deletion of active Git branches
- **Confirmation Prompts**: For destructive operations like file deletion
- **Path Validation**: Ensures operations target valid locations
- **Error Handling**: Graceful handling of missing dependencies
- **Corporate-Friendly**: Works in restricted environments

## 📖 Documentation

- **📦 [Installation Guide](docs/installation.md)** - Complete setup instructions
- **🚨 [Troubleshooting](docs/troubleshooting.md)** - Fix common issues quickly  
- **🎯 [Features Guide](docs/features.md)** - Detailed feature documentation
- **💡 [Contributing](CONTRIBUTING.md)** - How to contribute to PowerFlow

## 🆘 Need Help?

### Quick Self-Help

```powershell
pwsh-h              # The command manual — grouped, scroll to read
pwsh-h -a           # Searchable fzf browser · pwsh-h git filters a section
powerflow-version   # Version and status info
Get-Command starship, fzf, zoxide, lsd, git  # Check dependencies
```

### Common Issues

**Icons show as squares?** → Install FiraCode Nerd Font and configure Windows Terminal  
**Commands not found?** → Run PowerShell as Administrator for first setup  
**Profile won't load?** → Check execution policy: `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`

**🚨 [Full Troubleshooting Guide](docs/troubleshooting.md)** - Solutions for all common problems

### Community Support

- **🐛 [Report Issues](https://github.com/Syntax-Read3r/powerflow/issues)** - Bug reports and feature requests
- **💬 [Discussions](https://github.com/Syntax-Read3r/powerflow/discussions)** - General questions and community chat
- **📚 [Documentation](docs/)** - Complete guides and references

## 🤝 Contributing

Contributions are welcome! PowerFlow is community-driven and benefits from diverse perspectives.

### Quick Contributing Guide

1. **Fork the repository** and create a feature branch
2. **Make your changes** with clear, well-commented code  
3. **Test thoroughly** on different Windows/PowerShell versions
4. **Update documentation** if needed
5. **Submit a pull request** with a clear description

### Areas for Contribution

- 🚀 Additional Git workflow improvements
- 📁 More file operation enhancements  
- 🌐 Cross-platform compatibility
- ⚡ Performance optimizations
- 🔧 New navigation features
- 📖 Documentation improvements
- 🎨 UI/UX enhancements

**📄 [Contributing Guidelines](CONTRIBUTING.md)** - Detailed contribution instructions

## 🚀 Releases & Updates

PowerFlow uses semantic versioning and automated releases:

- **🏷️ [Latest Release](https://github.com/Syntax-Read3r/powerflow/releases/latest)** - Current stable version
- **📋 [All Releases](https://github.com/Syntax-Read3r/powerflow/releases)** - Complete version history  
- **📝 [Changelog](CHANGELOG.md)** - Detailed changes by version
- **🔔 Auto-Updates** - Get notified of new versions automatically

## 📄 License

PowerFlow is licensed under the [MIT License](LICENSE) - see the LICENSE file for details.

### What this means:
- ✅ **Use** - Personal, commercial, any purpose
- ✅ **Modify** - Change the code however you want  
- ✅ **Distribute** - Share your modifications
- ✅ **Private Use** - Use in private/internal projects
- ℹ️ **Attribution** - Keep the license notice (that's it!)

## 🙏 Acknowledgments

PowerFlow builds on amazing open-source projects:

- **[Starship](https://starship.rs/)** - Beautiful cross-shell prompt
- **[fzf](https://github.com/junegunn/fzf)** - Amazing fuzzy finding capabilities
- **[zoxide](https://github.com/ajeetdsouza/zoxide)** - Smart directory navigation
- **[lsd](https://github.com/Peltoche/lsd)** - Modern file listing with icons
- **[Windows Terminal](https://github.com/microsoft/terminal)** - Excellent terminal experience
- **[PowerShell](https://github.com/PowerShell/PowerShell)** - Powerful cross-platform shell

## 🌟 Star History

[![Star History Chart](https://api.star-history.com/svg?repos=Syntax-Read3r/powerflow&type=Date)](https://star-history.com/#Syntax-Read3r/powerflow&Date)

---

<div align="center">
  <strong>Made with ❤️ for the PowerShell community</strong>
  <br>
  <sub>If PowerFlow improves your workflow, consider giving it a ⭐!</sub>
  <br><br>
  
  **🚀 Ready to supercharge your terminal?**
  
  ```powershell
  irm https://raw.githubusercontent.com/Syntax-Read3r/powerflow/main/install.ps1 | iex
  ```
</div>