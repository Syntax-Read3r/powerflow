# ==============================================================================
# PowerFlow — Help Menu
# ==============================================================================
# Domain   : Help
# File     : components/help/menu.ps1
# Purpose  : Comprehensive command reference and help display
# Functions: pwsh-h
# Depends  : none
# ==============================================================================

function pwsh-h {
    # Build the version banner line with centred padding so the box stays aligned
    $verText   = "Enhanced Profile v$($script:POWERFLOW_VERSION)"
    $innerWidth = 78
    $totalPad  = $innerWidth - $verText.Length
    $leftPad   = ' ' * [math]::Floor($totalPad / 2)
    $rightPad  = ' ' * [math]::Ceiling($totalPad / 2)
    $verLine   = "║$leftPad$verText$rightPad║"

    $helpText = @"

╔══════════════════════════════════════════════════════════════════════════════╗
║                    🐚 POWERSHELL COMMAND REFERENCE                           ║
$verLine
╚══════════════════════════════════════════════════════════════════════════════╝

┌─ 🧭 SMART NAVIGATION & BOOKMARKS ────────────────────────────────────────────┐
│  🎯 CORE NAVIGATION:                                                         │
│  nav <project>       → smart project search in ~/Code and bookmarked dirs    │
│  nav -verbose        → detailed search output for troubleshooting            │
│  z <project>         → alias for nav                                         │
│                                                                              │
│  🔖 BOOKMARK MANAGEMENT:                                                     │
│  nav b <bookmark>    → navigate to bookmark                                  │
│  nav create-b <name> → create bookmark (current dir)                         │
│  nav cb <name>       → shorthand for create-b                                │
│  nav delete-b <name> → delete bookmark with confirmation                     │
│  nav db <name>       → shorthand for delete-b                                │
│  nav rename-b <old> <new> → rename existing bookmark                         │
│  nav rb <old> <new>  → shorthand for rename-b                                │
│  nav list            → interactive bookmark manager                          │
│  nav l               → shorthand for list                                    │
│                                                                              │
│  ⬆️ PARENT NAVIGATION:                                                       │
│  ..                  → go up one level (fast!)                               │
│  ...                 → go up two levels (fast!)                              │
│  ....                → go up three levels (fast!)                            │
│  ~                   → go to home directory                                  │
│                                                                              │
│  📍 LOCATION UTILITIES:                                                      │
│  here                → detailed info about current directory                 │
│  copy-pwd            → copy current path to clipboard                        │
│  open-pwd            → open current directory in File Explorer               │
│  op                  → alias for open-pwd                                    │
│  back                → go to previous directory                              │
│  cd-                 → alias for back                                        │
│  pwd                 → print working directory (alias)                       │
└───────────────────────────────────────────────────────────────────────────────┘


┌─ 🧱 PROJECT GENERATORS ──────────────────────────────────────────────────────┐
│  create-next         → create full Next.js app with DB/Docker/CI setup       │
│  create-n            → shorthand for create-next                             │
└──────────────────────────────────────────────────────────────────────────────┘

┌─ 🐧 WSL / TERMINAL LAUNCHERS  (Windows only) ────────────────────────────────┐
│  open-nt             → open new PowerShell tab                               │
│  open-nt ubuntu      → open Ubuntu/WSL tab                                   │
│  open-nt cmd         → open Command Prompt tab                               │
│  open-ubuntu         → direct Ubuntu launcher using configured profile GUID  │
│  open-wsl-simple     → simple WSL profile launcher                           │
│  Get-WindowsTerminalProfiles → inspect Windows Terminal profiles             │
│  (on Linux, tab commands drive tmux windows instead)                         │
└──────────────────────────────────────────────────────────────────────────────┘

┌─ ⏻ SHUTDOWN TIMER ───────────────────────────────────────────────────────────┐
│  shutdown 1h         → schedule shutdown in 1 hour                           │
│  shutdown 1h 30m     → schedule shutdown in 1 hour 30 minutes                │
│  shutdown cancel     → cancel scheduled shutdown                             │
│  s 1h                → shorthand shutdown timer                              │
│  s c                 → cancel scheduled shutdown                             │
└──────────────────────────────────────────────────────────────────────────────┘

┌─ 📂 ENHANCED FILE OPERATIONS ────────────────────────────────────────────────┐
│  📋 DIRECTORY LISTING:                                                       │
│  ls [path]           → beautiful directory listing with lsd                  │
│  ls -t [path]        → tree view with smart depth detection                  │
│  ls -t -d <N> [path] → tree view with custom depth                           │
│  la                  → list all files including hidden                       │
│  ll                  → long list format with details                         │
│                                                                              │
│  📄 FILE VIEWING & SEARCH:                                                   │
│  cat <file>          → display file contents                                 │
│  grep <pattern>      → search text in files                                  │
│  less <file>         → page through file content                             │
│  which <cmd>         → show command location                                 │
│                                                                              │
│  🔧 FILE MANIPULATION:                                                       │
│  cp <src> <dst>      → copy files/directories                                │
│  touch <file>        → create new empty file                                 │
│  mkdir <dir>         → create new directory (strict naming rules)            │
│                                                                              │
│  ✂️ CUT-AND-PASTE FILE WORKFLOW:                                             │
│  mv <filename>       → 🎯 smart cut file for moving (supports fuzzy search)  │
│  mv-t                → paste cut file in current directory                   │
│  mv-c                → cancel move operation (drop held file)                │
│                                                                              │
│  🏷️ ENHANCED RENAME:                                                         │
│  rn [filename]       → 🎨 beautiful interactive rename with fuzzy search     │
│                                                                              │
│  🗑️ SMART FILE REMOVAL:   (🐧 on Linux this is 'del', not 'rm' — see below)  │
│  rm                  → 🎯 fzf picker, then confirm before deleting           │
│  rm <filename>       → remove a single file or directory (recursive)         │
│  rm <file1> <file2>  → remove multiple targets in one command                │
│  rm *.log            → wildcard removal — lists every match, one confirm     │
│  rm <filename> -f    → force remove (skip the confirmation prompt)           │
│  rmdir <path>        → enhanced directory removal with confirmations         │
│                                                                              │
│  🐧 ON LINUX — GNU coreutils are NOT shadowed:                               │
│  del [...]           → PowerFlow's smart removal (what 'rm' is on Windows)   │
│  mvf <filename>      → PowerFlow's cut-and-paste move (Windows calls it 'mv')│
│  rm / mv / cp / cat  → the real GNU tools, untouched                         │
│                                                                              │
│  📋 FILE CLIPBOARD OPERATIONS:                                               │
│  copy-file <file>    → copy file to clipboard for pasting                    │
│  cf <file>           → shorthand for copy-file                               │
│  paste-file [path]   → paste file from clipboard                             │
│  pf [path]           → shorthand for paste-file                              │
│  pf -Force [path]    → paste file with overwrite confirmation skip           │
└──────────────────────────────────────────────────────────────────────────────┘

┌─ 🎯 ENHANCED GIT WORKFLOW ───────────────────────────────────────────────────┐
│  🚀 ADD-COMMIT-PUSH WORKFLOW:                                                │
│  git-a               → 🎨 beautiful add → commit → push workflow             │
│  git-a-plus          → enhanced version with multiple modes:                 │
│    git-aq            → ⚡ quick mode (minimal prompts)                        │
│    git-ad            → 🔍 dry run mode (preview changes)                     │
│    git-am            → 🔄 amend last commit with new message                 │
│                                                                              │
│  🏷️  RELEASE WORKFLOW:                                                       │
│  git-release         → 🚀 bump version → update settings → commit → tag     │
│  git-rl              → alias for git-release                                 │
│    patch             → v2.0.0 → v2.0.1  (bug fixes)                         │
│    minor             → v2.0.0 → v2.1.0  (new features)                      │
│    major             → v2.0.0 → v3.0.0  (breaking changes)                  │
│    custom            → enter a specific version number                       │
│  (automatically updates config/PowerFlow.settings.ps1 and triggers CI)      │
│                                                                              │
│  🔄 ROLLBACK WORKFLOW:                                                       │
│  git-rb <commit>     → 🔄 create rollback branch from specific commit        │
│  git-rba             → 🚀 rollback branch add-commit-push (rollback-* only)  │
│  grba                → alias for git-rba                                     │
│                                                                              │
│  🔥 INTERACTIVE INTERFACES:                                                  │
│  git-l               → 🌟 beautiful interactive log viewer with actions      │
│  git-log             → alias for git-l                                       │
│  git-pick            → 🎯 commit hash picker (copies to clipboard)           │
│  git-p               → alias for git-pick                                    │
│  git-branch          → 🌿 beautiful branch picker with delete actions        │
│  git-b               → alias for git-branch                                  │
│  git-c.sb            → 🔀 enhanced branch creation/switching interface       │
│  git-s               → 📊 interactive status viewer with quick actions       │
│  git-st              → alias for git-s                                       │
│  git-stash           → 📦 interactive stash manager                          │
│  git-sh              → alias for git-stash                                   │
│  git-remote          → 🌐 interactive remote manager                          │
│  git-r               → alias for git-remote                                  │
│                                                                              │
│  🛠 UTILITY COMMANDS:                                                        │
│  git-f               → nuclear reset + clean + fetch (with confirmation)     │
│  git-cm              → quickly checkout main branch                          │
│  git-bd <branch>     → safe delete branch (prevents current branch)          │
│  git-bD <branch>     → force delete branch (with safety check)               │
│  git-next            → clean .next + node_modules + reinstall deps           │
│                                                                              │
│  🐙 GITHUB INTEGRATION:                                                      │
│  gh-l [count]        → 🚀 list your GitHub repos with activity stats         │
│  gh-l-reset          → remove saved GitHub token                             │
│  gh-l-status         → check if GitHub token is saved                        │
│  gh-l-org [org]      → 🏢 browse org repos; clone one or all                 │
└──────────────────────────────────────────────────────────────────────────────┘

┌─ 🪟 TERMINAL TAB MANAGEMENT ─────────────────────────────────────────────────┐
│  open-nt             → open new Windows Terminal tab                         │
│  close-ct            → close current tab                                     │
│  next-t              → switch to next terminal tab                           │
│  prev-t              → switch to previous terminal tab                       │
│  open-t <N>          → switch to terminal tab N (1-9)                        │
│  close-t <N>         → switch to tab N then close it                         │
│  send-keys <keys>    → send keyboard shortcuts to terminal                   │
└──────────────────────────────────────────────────────────────────────────────┘



┌─ ⚙️  CONFIGURATION & SETTINGS ───────────────────────────────────────────────┐
│  pwsh-profile        → open PowerShell profile in VS Code                    │
│  pwsh-starship       → open Starship prompt config                           │
│  pwsh-settings       → open Windows Terminal settings.json                   │
│  pwsh-h              → show this help menu                                   │
│  pwsh-recovery       → PowerFlow recovery and diagnostics menu               │
│                                                                              │
│  🔄 VERSION MANAGEMENT:                                                      │
│  Get-PowerFlowVersion    → detailed PowerFlow version and status info        │
│  powerflow-version       → quick version display                             │
│  powerflow-update        → check for and install PowerFlow updates           │
│  pwsh-reminders          → toggle update reminder notifications on/off       │
│  powerflow-uninstall     → remove PowerFlow and optionally its dependencies  │
│                                                                              │
│  📍 PATH MANAGEMENT:                                                         │
│  set-path <path>            → add directory to User PATH (no quotes needed)  │
│  set-path -system <path>    → add directory to System PATH (admin required)  │
└──────────────────────────────────────────────────────────────────────────────┘

┌─ 🔧 DEBUGGING & TESTING ─────────────────────────────────────────────────────┐
│  Test-NavFunction    → debug navigation search with detailed output          │
└──────────────────────────────────────────────────────────────────────────────┘

┌─ 🚀 KEY FEATURES ────────────────────────────────────────────────────────────┐
│  🎯 Smart File Operations → mv, rm, rn all support fuzzy search and patterns │
│  🔖 Persistent Bookmarks  → Saved across sessions in JSON file               │
│  ✂️ Cut-Paste Workflow   → mv cuts files, mv-t pastes, mv-c cancels          │
│  🔄 Git Rollback System  → Create rollback branches from any commit          │
│  🐙 GitHub Integration   → Browse, clone, delete repos with token security   │
│  🌟 Starship Prompt      → Beautiful, informative prompt with Git info       │
│  📋 Clipboard Integration → All interactive tools copy results to clipboard  │
│  🔍 Fuzzy Search         → Interactive pickers with fzf for everything       │
│  🛡️  Safety Checks       → Prevents accidental deletion and data loss        │
│  🎨 Beautiful UI         → Consistent emoji indicators and color schemes     │
│  ⚡ Context-Aware        → Tools adapt to current repository state            │
│  🌳 Git Integration      → Deep integration with Git workflows               │
└──────────────────────────────────────────────────────────────────────────────┘

📚 DOCUMENTATION: All functions include detailed help via Get-Help

"@

    Write-Host $helpText -ForegroundColor White
}
