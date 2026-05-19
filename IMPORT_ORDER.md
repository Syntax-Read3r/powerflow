# PowerFlow Import Order

The bootloader (`Microsoft.PowerShell_profile.ps1`) sources component files in a specific order. This document explains why each group loads when it does.

## Load Order Rationale

### Stage 1 — Config (`config/`)

**`PowerFlow.settings.ps1`** loads first because it defines script-scoped variables (`$script:POWERFLOW_VERSION`, `$script:DB_USERNAME`, `$script:DB_PASSWORD`, `$script:CHECK_*` flags, `$ProgressPreference`) that every subsequent file may reference. Nothing works correctly without these values being set.

**`PowerFlow.paths.ps1`** loads second because it configures the shell environment: it adds Scoop to `$env:PATH`, initialises Starship (which changes the prompt), initialises Zoxide and removes its default `z` alias, and navigates to `$HOME\Code`. This must happen before any interactive function needs those tools, but after the settings are available.

### Stage 2 — Core (`components/core/`)

Core functions (`Check-PowerFlowUpdates`, `Initialize-Dependencies`, `Check-PowerShellUpdates`, `pwsh-recovery`) are loaded early because the startup checks at the bottom of the bootloader call them immediately after all components are sourced. They have no dependencies on domain-specific components.

### Stage 3 — Shared (`components/shared/`)

**`strings.ps1`** must load before `components/git/remote.ps1`, which calls `Convert-ToKebabCase`, `Convert-ToSnakeCase`, `Convert-ToPascalCase`, and `Convert-ToCamelCase` to generate repository name suggestions.

**`aliases.ps1`** provides simple shell aliases (`grep`, `less`, `which`, `pwd`) that any interactive session may use immediately.

### Stage 4 — Navigation (`components/navigation/`)

The navigation components load in dependency order:

1. **`bookmarks.ps1`** — defines the bookmark data model and persistence helpers that `nav.ps1` reads.
2. **`projects.ps1`** — defines `Search-NestedProjects`, called inside `nav` when no bookmark matches.
3. **`nav.ps1`** — the main `nav`/`z` function; depends on both of the above being defined.
4. **`directory.ps1`** — standalone dot-navigation shortcuts and `copy-pwd`; no dependencies on the other nav files.

### Stage 5 — Files (`components/files/`)

File components are independent of each other but load before Git because the Git commit workflow (`git-a`) uses the current working directory, not file functions. The ordering within the group is conventional:

1. `listing.ps1` — replaces the built-in `ls` alias first, so later files can safely call `ls`.
2. `operations.ps1` — replaces `rm`, `rmdir`, `mv`.
3. `rename.ps1` — standalone `rn` function.
4. `clipboard.ps1` — standalone `cf`/`pf` functions.

### Stage 6 — Git (`components/git/`)

Git components load in call-dependency order:

1. **`remote.ps1`** — `Create-RemoteRepository` is called by `git-a` in `commit.ps1`; must be defined first.
2. **`commit.ps1`** — `git-a` and `git-a-plus` depend on `Create-RemoteRepository`.
3. **`branches.ps1`** — `git-branch`, `git-c.sb`; no dependency on commit.
4. **`rollback.ps1`** — `git-rba`, `git-rb`; no dependency on other git files.
5. **`interactive.ps1`** — `git-l`, `git-s`, `git-stash`, `git-remote`, `git-pick`; standalone.
6. **`reset.ps1`** — `git-f`, `git-next`; standalone.

### Stage 7 — GitHub (`components/github/`)

`browser.ps1` loads after all Git components because `gh-l` may call `git clone` internally after the user selects a repository.

### Stage 8 — Terminal (`components/terminal/`)

Terminal management loads after navigation and files so that `open-nt` can correctly report the current directory, which may have been changed by the navigation functions. `tabs.ps1` loads before `wsl.ps1` because `wsl.ps1` functions are companions to `open-nt` and do not depend on `send-keys` directly.

### Stage 9 — Projects (`components/projects/`)

`create-next.ps1` reads `$script:DB_USERNAME` and `$script:DB_PASSWORD` from the settings loaded in Stage 1. It loads late because it has no functions that other components depend on.

### Stage 10 — System (`components/system/`)

System utilities (`pwsh-profile`, `pwsh-starship`, `pwsh-settings`, `shutdown`, `s`) are standalone. They load late because nothing else depends on them.

### Stage 11 — Help (`components/help/`)

`menu.ps1` loads last because it references function names in its static help text. Loading it last guarantees all functions it documents are already defined, making `Get-Help pwsh-h` accurate.

### Startup Checks

After all components are sourced, the bootloader conditionally runs:

```powershell
if ($script:CHECK_PROFILE_UPDATES) { Check-PowerFlowUpdates }
if ($script:CHECK_DEPENDENCIES)    { Initialize-Dependencies }
if ($script:CHECK_UPDATES)         { Check-PowerShellUpdates }
```

These flags are set in `config/PowerFlow.settings.ps1`. Toggle any of them to `$false` to skip the corresponding startup check and speed up profile load time.
