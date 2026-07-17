# PowerFlow — Claude Code Instructions

## The Architecture Rule (read this first)

PowerFlow runs on **Windows and Linux from one codebase**.

> **No file under `components/` may call an OS API directly.**

Components call **adapters**; `platform/<os>/adapters/` implements them per OS.

```powershell
Set-Clipboard $hash        # ❌ NEVER in components/ — breaks Linux
Copy-ToClipboard $hash     # ✅ adapter — works on both
```

Forbidden in `components/`: `Set-Clipboard`, `Get-Clipboard`, `explorer.exe`, `scoop`,
`wt`, `WindowsPrincipal`, `shutdown.exe`, `SetEnvironmentVariable`, `System.Windows.Forms`,
`winget`, `$env:TEMP`, `$env:USERPROFILE`, `$env:LOCALAPPDATA`, `$env:APPDATA`.

Use these adapters instead — see `COMPONENTS.md` for the full contract:

| Need | Call | Not |
|---|---|---|
| clipboard | `Copy-ToClipboard`, `Get-FromClipboard` | `Set-Clipboard` |
| open a folder / file / URL | `Open-Path`, `Open-Editor`, `Open-Url` | `explorer.exe`, `code`, `Start-Process <url>` |
| install a tool | `Install-Dependency`, `Test-Dependency`, `Get-DependencyInstallHint` | `scoop install` |
| admin check | `Assert-Admin`, `Test-Admin` | `WindowsPrincipal` |
| terminal tabs | `New-TerminalTab`, `Switch-TerminalTab` | `wt`, SendKeys |
| shutdown | `Invoke-Shutdown`, `Stop-Shutdown` | `shutdown.exe` |
| persistent PATH | `Add-PersistentPathEntry` | `[Environment]::SetEnvironmentVariable` |
| temp / home dir | `Get-TempPath`, `Get-HomePath` | `$env:TEMP`, `$env:USERPROFILE` |

**CI enforces this.** `release-validate.yml` fails the release on any direct OS call in
`components/`, and verifies every adapter call resolves on *both* platforms.

If a feature genuinely has no Linux equivalent (e.g. WSL), it belongs in `windows-only/`,
not `components/`.

### Adding a new adapter function

Add it to **both** `platform/windows/adapters/` **and** `platform/linux/adapters/` with the
same name and signature. A function present on only one platform will fail CI's parity
check and explode at runtime on the other OS.

---

## Help Menu Rule

Whenever a new **user-facing command** is added under `components/`, update
`components/help/menu.ps1` in the same response — without waiting for the user to ask.

Internal helpers (`Assert-Admin`, `Create-RemoteRepository`, `Copy-ToClipboard`, …) go in
`COMPONENTS.md` but **not** in `pwsh-h` — the help menu is a command reference, not a
function index.

Place the entry in the correct section of `pwsh-h`:

| Folder | Help section |
|---|---|
| `components/git/` | `🎯 ENHANCED GIT WORKFLOW` |
| `components/navigation/` | `🧭 SMART NAVIGATION & BOOKMARKS` |
| `components/files/` | `📂 ENHANCED FILE OPERATIONS` |
| `components/terminal/` | `🪟 TERMINAL TAB MANAGEMENT` |
| `components/system/` | `⚙️ CONFIGURATION & SETTINGS` |
| `components/projects/` | `🧱 PROJECT GENERATORS` |
| `components/help/` | `⚙️ CONFIGURATION & SETTINGS` |
| `components/core/` | `⚙️ CONFIGURATION & SETTINGS` |
| `components/shared/` | whichever section is most relevant |
| `windows-only/` | `🐧 WSL / TERMINAL LAUNCHERS` (mark Windows-only) |
| `platform/*/adapters/` | none — adapters are internal |
| `platform/linux/bindings.ps1` | `📂 ENHANCED FILE OPERATIONS` (e.g. `del`, `mvf`) |

Also update `COMPONENTS.md` — including the **Platform** column (Windows / Linux / Both).

---

## Command Shadowing on Linux (do not break this)

PowerShell resolves `Alias → Function → Cmdlet → native binary`. PowerFlow defines `rm`,
`mv`, `cp`, `cat`, `mkdir`, `touch` — which would **shadow the GNU coreutils** on Linux.

`platform/linux/bindings.ps1` prevents that. PowerFlow's versions are re-exposed as
**`del`** and **`mvf`**; the rest defer to the native tools.

Never bind a new command to a GNU coreutil's name without adding it to that file. The
Linux CI job asserts `rm`/`mv`/`cp`/`cat`/`mkdir`/`touch`/`rmdir`/`which`/`grep` all
resolve to `Application` (a native binary) — it will fail if you shadow one.

---

## Releases

`git-rl` owns the version bump. Never hand-edit `$script:POWERFLOW_VERSION`.
New feature → minor; breaking change → major. Update `CHANGELOG.md` in the same change,
and add a session log under `docs/log/`. See `docs/instructions.md`.

**Before every release, work through `docs/release-checklist.md` top to bottom and say
so.** Every item on it exists because skipping it shipped (or nearly shipped) a real
failure — including a tag cut on uncommitted work, a README that documented behaviour a
release had reversed, and two releases whose CI failed silently and sat unpublished.
The two items most often skipped, so stated here too:

1. **The tag points at HEAD** — everything belonging to the release must be committed
   *before* `git-rl` runs.
2. **The release is not done until `gh release view vX.Y.Z` shows it published with
   assets.** A pushed tag with failed CI is not a release, and it fails silently.
