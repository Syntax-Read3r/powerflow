# Changelog

All notable changes to PowerFlow will be documented in this file.

## [Unreleased]

### Planning
- Additional database providers
- Testing framework integration
- Enhanced Docker optimizations

## [2.2.0] - 2026-05-24

### Added
- 🔔 **Version display on startup**: profile load line now shows the running version
  (`✅ PowerFlow v2.2.0 loaded`) so the current version is always visible without
  running a command.
- 📋 **3-option update prompt**: when a new version is available the bare `y/n/s` prompt
  is replaced with a numbered menu — `1) Install now`, `2) Skip today`,
  `3) Turn off update reminders`.
- 🔕 **Persistent reminder toggle (option 3)**: choosing option 3 permanently writes
  `$script:CHECK_PROFILE_UPDATES = $false` to `config/PowerFlow.settings.ps1` so
  the setting survives profile reloads without manual editing.
- 🔔 **`pwsh-reminders` command**: interactive toggle for update reminder notifications.
  Shows current ON/OFF status and flips it by rewriting the settings file. Re-enabling
  clears the daily check marker so the update check fires on the very next load.

### Fixed
- 📦 **README install URL**: changed from `releases/latest/download/install.ps1` to
  `raw.githubusercontent.com/main/install.ps1` — the old URL resolved to v1.0.5 because
  newer releases were never confirmed to have created GitHub Release objects.

### Documentation
- 📋 **`docs/instructions.md`**: added mandatory post-release verification rule to §9
  and a CHANGELOG ordering convention so release drift cannot recur silently.

## [2.1.0] - Unreleased

### Added
- 🏢 **GitHub Organisation Browser** (`gh-l-org`): Browse and bulk-clone GitHub
  organisation repositories from the terminal.
  - **Org picker**: fzf list of all organisations the authenticated user belongs to
  - **Repo picker**: identical column layout to `gh-l` — privacy, name, last push date,
    24h commits, 1w commits, language
  - **Action menu**: clone selected repo, clone ALL repos into `.\<orgName>\` folder,
    open in browser, copy HTTPS or SSH URL
  - **Bulk clone**: uses `Push-Location`/`Pop-Location` to restore CWD; reports per-repo
    success/failure counts on completion
  - **Token scope fallback**: automatically retries with `type=public` and warns user if
    token lacks `read:org` scope
  - **Direct org argument**: `gh-l-org mycompany` skips the org picker
  - **Shared token helpers**: `_GhL-SetToken`, `_GhL-GetToken`, `_GhL-CommitCount`
    extracted to module level — shared by `gh-l` and `gh-l-org`, compiled once per session

## [2.0.1] - 2026-05-21

### Fixed
- 🐛 **`nav` multi-word query truncation**: `nav source code` previously only searched for `"source"` — every word after the first was silently dropped. Extra positional arguments are now joined into a single query string before being passed to fzf (or the BFS fallback), so `nav source code` correctly searches for `"source code"`.

## [2.0.0] - 2026-05-19

### Breaking Change — Modular Architecture
The profile is no longer a single monolithic file. `Microsoft.PowerShell_profile.ps1` is now a thin bootloader (~109 lines) that dot-sources 28 component files organized by domain. **Installation must use the `powerflow-v2.0.0.zip` archive** — downloading only the profile file will produce a broken install.

### Architecture
- **Component-based layout** inspired by React feature-folder conventions
- **28 component files** split across 10 domain folders under `components/`
- **`config/`** folder for settings (`PowerFlow.settings.ps1`) and environment init (`PowerFlow.paths.ps1`)
- **`_pf_source` bootloader helper** — warns on missing components instead of hard-failing, portable via `$script:PowerFlowRoot`
- **`COMPONENTS.md`** — registry table of every file, domain, and exported function
- **`IMPORT_ORDER.md`** — documented rationale for load order at each stage
- **`docs/`** and **`tests/`** scaffold directories for future growth

### Changed
- `$script:POWERFLOW_VERSION` moved from main profile to `config/PowerFlow.settings.ps1`
- Release workflow updated: version validation now checks `config/PowerFlow.settings.ps1`; releases now ship a `powerflow-v2.0.0.zip` archive containing the full component tree
- Install script updated to download and extract the zip archive into the profile directory

## [1.0.5] - 2025-01-23

### Added
- 🚀 **Automatic GitHub Repository Creation**: `git-a` now creates remote repositories on-the-fly
  - **Smart Remote Detection**: Automatically detects when no remote repository exists
  - **GitHub CLI Integration**: Checks for `gh` installation and authentication before offering to create
  - **Interactive Repository Setup**: Beautiful fzf interface for repository configuration
  - **Naming Convention Options**: Choose from kebab-case, snake_case, PascalCase, camelCase, or custom
  - **Visibility Selection**: Interactive private/public repository selection with clear descriptions
  - **Seamless Workflow**: Creates remote, sets origin, and pushes in one smooth operation
  - **Error Recovery**: Handles deleted remotes and offers to recreate them
  - **Authentication Status**: Shows current GitHub user during repository creation
- 🖥️ **Cross-Platform Terminal Integration**: Enhanced `open-nt` function with shell switching
  - **PowerShell from Ubuntu**: `open-nt pwsh` or `open-nt p` to launch PowerShell tabs from Ubuntu
  - **Ubuntu from PowerShell**: `open-nt ubuntu` or `open-nt u` to launch Ubuntu tabs from PowerShell
  - **Smart Path Conversion**: Automatically converts WSL paths ↔ Windows paths when switching shells
  - **Command Prompt Support**: `open-nt cmd` to open Command Prompt tabs from either environment
  - **Fallback Handling**: Graceful degradation when Windows Terminal is unavailable
- 🐧 **Ubuntu `open-nt` Function**: Complete implementation for Ubuntu/WSL environments
  - **Cross-shell navigation**: Launch any shell from Ubuntu terminal
  - **Windows Terminal integration**: Seamless tab management across environments
  - **Path translation**: Intelligent handling of /mnt/ paths to Windows drive letters

### Enhanced
- **`git-a` Workflow**: Now handles the complete git lifecycle from init to push
  - **Repository initialization**: Offers to init git if not in a repository
  - **Remote status display**: Shows if repository is local-only or has remote
  - **Upstream handling**: Automatically sets upstream on first push to new branches
  - **Complete automation**: From local changes to live GitHub repository in one command
- **PowerShell `open-nt`**: Extended existing function with cross-platform shell selection
- **Ubuntu Help System**: Updated `wsl_help` to include `open-nt` cross-platform usage
- **Documentation**: Comprehensive coverage of cross-platform terminal features

### Fixed
- 🐛 **`git-a` Syntax Errors**: Resolved critical issues in the git-a function
  - **Incomplete regex pattern**: Fixed unclosed regex replacement for repository name sanitization
  - **Duplicate code removal**: Eliminated ~140 lines of duplicated code in `Create-RemoteRepository` function
- 🔤 **Naming Convention Functions**: Improved word boundary detection in case conversion
  - **Smart word detection**: Now properly handles camelCase, PascalCase, snake_case, and kebab-case
  - **Single word preservation**: Fixed issue where single words like "back" were split into "b-a-c-k"
  - **Enhanced patterns**: Better regex patterns for detecting transitions between words and acronyms
  - **Examples**: "MyProject" → "my-project", "XMLParser" → "xml-parser", "back" → "back" (not "b-a-c-k")

## [1.0.4] - 10-07-2025

### Added
- 🚀 **Professional Next.js Project Creator**: `create-next` / `create-n` command
  - **Database Selection**: Choose from PostgreSQL+Prisma, Supabase, MongoDB, MySQL+Prisma, or SQLite+Prisma
  - **Complete CI/CD Pipeline**: 3 GitHub Actions workflows (ci.yml, docker-build.yml, deploy.yml)
  - **Docker Integration**: Development and production Docker configurations with database services
  - **Enterprise Structure**: Professional folder organization with all necessary directories
  - **Comprehensive Documentation**: API docs, development guide, and deployment guide auto-generated
  - **Database-Specific Configurations**: Tailored setup for each database type with proper connection strings
  - **TypeScript Ready**: Full TypeScript support with database-specific type definitions
  - **Beautiful Interface**: Same fzf-powered interface as `git-a` with database selection
- 🏷️ **Version release workflow**: `git-a -VersionRelease` / `git-a -vr` 
- 🤖 **GitHub Actions integration**: Automatic release creation when version tags are pushed
- 🎯 **One-command releases**: Update version → `git-a -vr` → Automatic release generation
- ✅ **Smart release validation**: Ensures profile version matches git tag
- 📦 **Auto-generated release assets**: install.ps1, uninstall.ps1, and release notes

### Enhanced
- `git-a` function now supports version release workflow
- Help documentation updated with new release commands and `create-next` functionality
- Release process streamlined from manual to automated
- `pwsh-h` help system expanded with comprehensive Next.js project creation documentation

### Technical Details
- **`create-next`**: Creates production-ready Next.js applications with:
  - Latest Next.js 15+ with App Router, TypeScript, Tailwind CSS, ESLint
  - Database integration: Prisma schemas, Supabase client, or Mongoose models
  - Docker Compose configurations for development and production
  - GitHub Container Registry integration
  - Automated dependency installation based on database choice
  - Environment variable templates for each database type
  - Professional npm scripts for database operations and Docker management