# PowerFlow Component Registry

This table lists every component file in the modular architecture, its domain, and the functions it exports.

| File | Domain | Functions |
|------|--------|-----------|
| `config/PowerFlow.settings.ps1` | Config | `$script:POWERFLOW_VERSION`, `$script:POWERFLOW_REPO`, `$script:CHECK_PROFILE_UPDATES`, `$script:CHECK_DEPENDENCIES`, `$script:CHECK_UPDATES`, `$script:DB_USERNAME`, `$script:DB_PASSWORD` |
| `config/PowerFlow.paths.ps1` | Config | Scoop PATH setup, Starship init, Zoxide init, alias removal, auto-navigate |
| `components/core/version.ps1` | Core | `Check-PowerFlowUpdates`, `powerflow-update`, `Get-PowerFlowVersion`, `powerflow-version` |
| `components/core/dependencies.ps1` | Core | `Initialize-Dependencies`, `Check-PowerShellUpdates` |
| `components/core/recovery.ps1` | Core | `pwsh-recovery` |
| `components/shared/strings.ps1` | Shared | `Convert-ToKebabCase`, `Convert-ToSnakeCase`, `Convert-ToPascalCase`, `Convert-ToCamelCase` |
| `components/shared/aliases.ps1` | Shared | `grep` (alias), `less` (alias), `which`, `pwd` (alias) |
| `components/navigation/bookmarks.ps1` | Navigation | `Initialize-DefaultBookmarks`, `Get-Bookmarks`, `Save-Bookmarks`, `Add-Bookmark`, `Remove-Bookmark`, `Rename-Bookmark`, `Show-BookmarkList` |
| `components/navigation/projects.ps1` | Navigation | `Search-NestedProjects` |
| `components/navigation/nav.ps1` | Navigation | `nav`, `Test-NavFunction`, `z` (alias) |
| `components/navigation/directory.ps1` | Navigation | `here`, `..`, `...`, `....`, `.....`, `~`, `back`, `cd-` (alias), `copy-pwd` |
| `components/files/listing.ps1` | Files | `ls`, `la`, `ll`, `clr` (alias), `cat` (alias), `cp` (alias) |
| `components/files/operations.ps1` | Files | `rm`, `mv`, `mv-t`, `mv-c`, `rmdir`, `touch`, `mkdir` |
| `components/files/rename.ps1` | Files | `rn` |
| `components/files/clipboard.ps1` | Files | `open-pwd`, `op`, `paste-file`, `copy-file`, `cf`, `pf` |
| `components/git/remote.ps1` | Git | `Create-RemoteRepository` |
| `components/git/commit.ps1` | Git | `git-a`, `git-a-plus`, `git-aa`, `git-aq`, `git-ad`, `git-am` |
| `components/git/branches.ps1` | Git | `git-branch`, `Invoke-DeleteBranch`, `git-b`, `git-cm`, `git-bd`, `git-bD`, `git-c.sb` |
| `components/git/rollback.ps1` | Git | `git-rba`, `grba` (alias), `git-rb` |
| `components/git/interactive.ps1` | Git | `git-l`, `git-log`, `git-s`, `git-st`, `git-pick`, `git-p`, `git-stash`, `git-remote`, `git-sh`, `git-r` |
| `components/git/reset.ps1` | Git | `git-f`, `git-next` |
| `components/github/browser.ps1` | GitHub | `gh-l`, `gh-l-reset`, `gh-l-status` |
| `components/terminal/tabs.ps1` | Terminal | `send-keys`, `open-nt`, `close-ct`, `next-t`, `prev-t`, `open-t`, `close-t` |
| `components/terminal/wsl.ps1` | Terminal | `open-ubuntu`, `Get-WindowsTerminalProfiles`, `open-wsl-simple` |
| `components/projects/create-next.ps1` | Projects | `create-next`, `create-n` |
| `components/system/config-files.ps1` | System | `pwsh-profile`, `pwsh-starship`, `pwsh-settings` |
| `components/system/shutdown.ps1` | System | `shutdown`, `s` |
| `components/help/menu.ps1` | Help | `pwsh-h` |
