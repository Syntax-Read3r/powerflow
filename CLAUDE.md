# PowerFlow — Claude Code Instructions

## Help Menu Rule

Whenever a new function is added to any file under `components/`, update
`components/help/menu.ps1` in the same response — without waiting for the user
to ask.

Place the entry in the correct section of `pwsh-h` based on the function's
domain:

| Component folder | Help section |
|---|---|
| `components/git/` | `🎯 ENHANCED GIT WORKFLOW` |
| `components/navigation/` | `🧭 SMART NAVIGATION & BOOKMARKS` |
| `components/files/` | `📂 ENHANCED FILE OPERATIONS` |
| `components/terminal/` | `🪟 TERMINAL TAB MANAGEMENT` or `🐧 WSL / TERMINAL LAUNCHERS` |
| `components/system/` | `⚙️ CONFIGURATION & SETTINGS` |
| `components/projects/` | `🧱 PROJECT GENERATORS` |
| `components/help/` | `⚙️ CONFIGURATION & SETTINGS` |
| `components/core/` | `⚙️ CONFIGURATION & SETTINGS` |
| `components/shared/` | whichever section is most relevant |

Also update `COMPONENTS.md` to add the new file/function to the registry table.
