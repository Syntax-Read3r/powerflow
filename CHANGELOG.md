# Changelog

All notable changes to PowerFlow will be documented in this file.

## [Unreleased]

### Added
- 🏷️ **Version release workflow**: `git-a -VersionRelease` / `git-a -vr` 
- 🤖 **GitHub Actions integration**: Automatic release creation when version tags are pushed
- 🎯 **One-command releases**: Update version → `git-a -vr` → Automatic release generation
- ✅ **Smart release validation**: Ensures profile version matches git tag
- 📦 **Auto-generated release assets**: install.ps1, uninstall.ps1, and release notes

### Enhanced
- `git-a` function now supports version release workflow
- Help documentation updated with new release commands
- Release process streamlined from manual to automated

## [1.0.3] - 4-07-2025

### Added
- Initial release
- Smart navigation with bookmarks
- Enhanced Git workflows (git-a, git-rb, git-rba)
- Beautiful file operations with fuzzy search
- Auto-installation of dependencies (Starship, fzf, zoxide, lsd)
- FiraCode Nerd Font auto-installation
- GitHub repository integration (gh-l)
- Terminal tab management
- Comprehensive help system
- Version checking and auto-update system