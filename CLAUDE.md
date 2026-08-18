# PowerFlow — Claude Code Instructions

> **Starting fresh on a new machine?** `docs/agent-memory/` holds the archived per-project
> memory notes — the architecture rule and why it exists, the flag ethos, the convenience
> creed, the agreed build order, and the decisions still open. Claude Code's own memory lives
> outside the repo and does not survive a reset; that folder does, and its README has the
> restore command. Verify anything it names still exists before acting on it.

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

## Help Registration Rule

`pwsh-h` is **generated from the command registry** — there is no hand-drawn menu to
edit. When you add a user-facing command, add a `Register-PFCommand` call **in the same
file, beside the function**:

```powershell
Register-PFCommand -Name 'my-cmd' -Section '📂 ENHANCED FILE OPERATIONS' `
    -Synopsis 'one line, ~60 chars, present tense' -Example 'my-cmd foo' `
    -Aliases @('mc')            # -Platform 'Windows'|'Linux' if not Both
```

Rules:

- Section names come from `$script:PF_HelpSections` in `components/help/registry.ps1` —
  use one of those exactly; new sections get added there first.
- Every alias (`Set-Alias`) must appear in `-Aliases` of some registration.
- Internal helpers (Verb-Noun names: `Assert-Admin`, `Copy-ToClipboard`, …) go in
  `COMPONENTS.md`, **not** the registry — pwsh-h is a command reference, not a function
  index. The CI gate is case-sensitive and only counts kebab/lowercase names.
- **CI enforces this** (`release-validate.yml`, "Help registry covers every command"): a
  kebab-named function or alias without a registration fails the release.

Also update `COMPONENTS.md` — including the **Platform** column (Windows / Linux / Both).

---

## Command Shadowing on Linux (do not break this)

PowerShell resolves `Alias → Function → Cmdlet → native binary`. So a **function beats a
native binary**, and an **alias beats a function**. A function named `rm` in `components/`
therefore hides `/usr/bin/rm` on Linux.

> **Nothing in `components/` may be named after a GNU coreutil.**

Not `rm`, `mv`, `cp`, `cat`, `mkdir`, `touch`, `rmdir`, `which`, `grep`, `less`, `pwd`.

PowerFlow's own file commands use **PowerFlow's own names on every platform**: `del` and
`mvf` (in `components/files/operations.ps1`). They are not clones — `del` drives an fzf
picker and confirms, `mvf` treats a single argument as a *cut* — so borrowing a coreutil's
name would mean a Linux user's reflexes silently getting different behaviour.

Where the platform-specific parts go:

| | |
|---|---|
| `windows-only/coreutils.ps1` | `mkdir -p`, `touch`, `rmdir` — clones, for a platform that has none of them. Never loads on Linux. |
| `platform/windows/bindings.ps1` | **adds only.** Binds `rm`→`del`, `mv`→`mvf`, plus `grep`/`less`/`pwd`/`which`. |
| Linux | **has no bindings file.** There is nothing to unbind. |

This replaced an arrangement where `components/` claimed the coreutil names and
`platform/linux/bindings.ps1` removed them again afterwards. That failed in the dangerous
direction — shadowing unconditional, undo conditional — so anything that stopped the undo
from running left Linux with a silently substituted `rm`. Its own header recorded that the
bug had shipped once already. Adding names is now the only operation, and its worst failure
is a missing convenience on Windows.

**CI enforces this** (`release-validate.yml`, "Coreutil names are not shadowed"): a static
scan of `components/` for `^function <name>` and `^Set-Alias <name>` against a 57-name
coreutil list. `ls`/`la`/`ll` are the one deliberate exception — the pretty listing is the
point — and the gate allow-lists them by name. A second gate fails the release if
`platform/linux/bindings.ps1` ever comes back.

**This is checked twice, on purpose.** `release-validate-linux.yml` already installs PowerFlow on
an Alpine/Arch matrix, loads the profile, and asserts `rm`/`mv`/`cp`/`cat`/`grep` resolve to
`Application` and that `del`/`mvf` exist — that proves the real behaviour. The static scan above
fails earlier and closer to the cause: on the name, in the file that defines it, before anything
is installed, and without depending on a profile load succeeding.

Run the runtime check locally before pushing with `tests/linux/coreutil-resolution.ps1` in any
Linux container — see `tests/linux/README.md`. It also covers what the CI job does not: that
`windows-only/` stays unloaded, and that GNU `rm` still refuses a directory without `-r`.

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
