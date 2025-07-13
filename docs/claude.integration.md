# Claude Code + Fish Shell Troubleshooting Guide

## Problem: Claude Code Asking for Sudo Password on Every Launch

### Context: Fish Shell Breaking Existing Claude Code Installation
**This issue occurs when you have a functional Claude Code installation on Ubuntu, then install and switch to Fish shell.** The specific sequence is:

1. **Ubuntu with bash** - Claude Code installed and working perfectly
2. **Install Fish shell** - Switch default shell from bash to Fish
3. **Claude Code stops working** - Original installation becomes inaccessible in Fish environment
4. **Install new Claude Code instance** - Required for Fish shell compatibility
5. **Sudo password prompts** - New installation attempts terminal integration setup

The problem arises because:
- Fish shell has different PATH and environment variable handling than bash
- Your original Claude Code installation may not be accessible in Fish's environment
- Installing a new Claude Code instance for Fish triggers terminal integration setup
- Fish shell isn't automatically registered in system shells, causing repeated setup attempts

### Symptoms
- Claude Code worked perfectly in bash/Ubuntu
- **After switching to Fish shell, original Claude Code becomes inaccessible** (`command not found` or similar)
- Installing new Claude Code for Fish environment works, but prompts for `[sudo] password for user:` every time you run `claude`
- Claude Code starts successfully after entering password but behavior repeats on restart
- Issue persists across terminal sessions and system reboots
- **The problem specifically began when switching from bash to Fish shell**

### Root Cause Analysis

Using system tracing (`strace -f -e trace=execve claude 2>&1 | grep -i sudo`), we identified that Claude Code was executing:

```bash
sudo apt update
sudo tee -a /etc/shells
```

**Why this happens after installing Fish on Ubuntu:**
- Claude Code has a "terminal integration setup" feature
- **Installing Fish shell on Ubuntu changes your default shell environment**
- Claude Code detects this change and assumes it needs to reconfigure itself
- When Claude Code detects Fish (a non-standard shell), it tries to:
  1. Register Fish in the `/etc/shells` system file
  2. Update package lists for potential dependencies
- This setup runs on **every launch** instead of just once
- **The issue is triggered specifically because Fish wasn't automatically registered in `/etc/shells` during installation**

## Solution (Recommended)

### Manual Shell Registration
Execute these commands to complete what Claude Code was trying to do:

```bash
# Add Fish to system shells (prevents repeated sudo attempts)
echo "/usr/bin/fish" | sudo tee -a /etc/shells

# Update package lists (completes the setup Claude Code wanted)
sudo apt update

# Test - should now work without sudo
claude --version
claude
```

### Verification
After applying the fix:
- `claude --version` should work without password prompt
- `claude` should start directly without sudo request
- Changes persist across reboots

## Alternative Solutions

### Option 1: Disable Terminal Integration
```bash
# Start Claude Code (enter password when prompted)
claude

# Inside Claude Code session:
/config set terminalIntegration false
/config set autoSetupShell false
```

### Option 2: Bypass Permissions Entirely
```bash
# For development/sandbox environments only
claude --dangerously-skip-permissions
```

### Option 3: Complete Automatic Setup
```bash
# Let Claude Code complete its setup (may be unreliable)
claude
# Inside Claude Code:
/terminal-setup
# Follow prompts
```

## Prevention Tips

### 1. Switching to Fish Shell with Existing Claude Code
**IMPORTANT:** If you have working Claude Code on Ubuntu and want to switch to Fish shell:

**Option A: Make original installation accessible to Fish**
```bash
# Install Fish
sudo apt install fish

# Register Fish in system shells
echo "/usr/bin/fish" | sudo tee -a /etc/shells

# Start Fish and add original Claude path
fish
# In Fish shell:
echo 'set -gx PATH /usr/local/bin $PATH' >> ~/.config/fish/config.fish
# Test if original Claude works
claude --version
```

**Option B: Fresh installation for Fish (recommended)**
```bash
# Install Fish
sudo apt install fish

# Immediately register Fish and update packages
echo "/usr/bin/fish" | sudo tee -a /etc/shells
sudo apt update

# Install Claude Code specifically for Fish
npm install -g @anthropic-ai/claude-code --prefix ~/.npm-global

# Add to Fish PATH
echo 'set -gx PATH ~/.npm-global/bin $PATH' >> ~/.config/fish/config.fish

# Test
claude --version
```

**Following Option B prevents the sudo password issue entirely.**

### 2. Claude Code Configuration Management
```bash
# Check current configuration
claude config list

# Disable problematic auto-features
claude config set autoUpdate false
claude config set terminalIntegration false
```

### 3. Clean Installation Process
When installing Claude Code in a new environment:

```bash
# 1. Install to user directory to avoid permission issues
npm install -g @anthropic-ai/claude-code --prefix ~/.npm-global

# 2. Ensure PATH includes npm global bin
echo 'set -gx PATH ~/.npm-global/bin $PATH' >> ~/.config/fish/config.fish

# 3. Pre-register shell to prevent setup conflicts
echo "/usr/bin/fish" | sudo tee -a /etc/shells

# 4. Test installation
claude --version
```

## Common Related Issues

### Original Claude Code Inaccessible in Fish Shell
**Problem:** Claude Code worked in bash but `command not found` in Fish

**Root Cause:** Fish shell has different PATH handling and environment variables than bash

**Diagnosis:**
```bash
# Check if original installation exists but isn't in Fish PATH
which -a claude
whereis claude
echo $PATH
```

**Solutions:**

**Option 1: Add original installation to Fish PATH**
```fish
# In ~/.config/fish/config.fish, add the path where your original claude is located
set -gx PATH /usr/local/bin $PATH
set -gx PATH /usr/bin $PATH
```

**Option 2: Install new instance for Fish (leads to sudo issue covered in main solution)**
```bash
# Install Claude Code specifically for Fish environment
npm install -g @anthropic-ai/claude-code --prefix ~/.npm-global
# Then apply main solution to fix sudo issue
```

### Multiple Claude Code Installations
**Problem:** Conflicts between original bash installation and new Fish installation

**Diagnosis:**
```bash
which -a claude
whereis claude
```

**Solution:**
```bash
# Remove old system installation to avoid conflicts
sudo npm uninstall -g @anthropic-ai/claude-code
sudo rm -f /usr/local/bin/claude

# Keep only Fish-compatible user installation
npm install -g @anthropic-ai/claude-code --prefix ~/.npm-global
```

### WSL Path Conflicts
**Problem:** Windows and Linux Claude Code installations conflicting

**Diagnosis:**
```bash
echo $PATH | tr ':' '\n' | grep -E "(npm|claude)"
```

**Solution:**
Ensure Linux paths come before Windows paths in your Fish config:
```fish
# In ~/.config/fish/config.fish
set -gx PATH ~/.npm-global/bin $PATH
set -gx PATH /usr/local/bin $PATH
set -gx PATH $HOME/.local/bin $PATH
```

### Permission Issues with Config Files
**Problem:** Claude Code config files have wrong ownership

**Diagnosis:**
```bash
ls -la ~/.claude*
sudo find /home -name "*claude*" -user root 2>/dev/null
```

**Solution:**
```bash
# Fix ownership
sudo chown -R $USER:$USER ~/.claude*
sudo chmod -R 644 ~/.claude.json*
sudo chmod -R 755 ~/.claude/
```

### VSCode Integration Issues
**Problem:** Claude Code works in external terminal but not in VSCode

**Solutions:**

1. **Set VSCode to use WSL terminal:**
```json
{
    "terminal.integrated.defaultProfile.windows": "Ubuntu (WSL)",
    "terminal.integrated.defaultProfile.linux": "fish"
}
```

2. **Reload VSCode completely:**
```
Ctrl+Shift+P → "Developer: Reload Window"
```

3. **Use full path in VSCode terminal:**
```bash
/home/username/.npm-global/bin/claude
```

## Debugging Commands

### Trace System Calls
```bash
# See what system commands Claude Code is executing
strace -f -e trace=execve claude 2>&1 | grep -i sudo
```

### Monitor Auth Logs
```bash
# Watch authentication attempts in real-time
sudo tail -f /var/log/auth.log
# In another terminal, run claude to see what triggers sudo
```

### Debug Mode
```bash
# Enable Claude Code debug output
claude --debug
```

### Check Configuration
```bash
# View all Claude Code settings
claude config list

# Check installation type
claude doctor
```

## Environment Information

This guide applies to:
- **OS:** Ubuntu 20.04 LTS (WSL)
- **Shell:** Fish 3.7.1
- **Claude Code:** 1.0.51
- **Node.js:** Any version with npm
- **Installation Method:** npm global with user prefix

## Quick Reference

### Essential Commands
```bash
# Fix sudo issue after installing Fish on Ubuntu (main solution)
echo "/usr/bin/fish" | sudo tee -a /etc/shells && sudo apt update

# Prevent issue when installing Fish on systems with existing Claude Code
sudo apt install fish && echo "/usr/bin/fish" | sudo tee -a /etc/shells && sudo apt update

# Test Claude Code
claude --version && claude

# Emergency bypass
claude --dangerously-skip-permissions

# Check installation
which claude && claude config list
```

### File Locations
- **Claude Binary:** `~/.npm-global/bin/claude`
- **Claude Config:** `~/.claude.json`
- **Fish Config:** `~/.config/fish/config.fish`
- **System Shells:** `/etc/shells`

### Troubleshooting Checklist
- [ ] Fish shell registered in `/etc/shells`
- [ ] Claude Code installed to user directory (`~/.npm-global`)
- [ ] No conflicting system-wide Claude installations
- [ ] Config files owned by user (not root)
- [ ] Terminal integration disabled if problematic
- [ ] Auto-update disabled to prevent permission issues

---

**Last Updated:** July 2025  
**Status:** Verified working solution