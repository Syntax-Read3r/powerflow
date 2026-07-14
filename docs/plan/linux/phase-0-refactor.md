# Phase 0 — Separation of Scope (Windows-safe refactor)

> **Zero Linux code ships in this phase.** This is a pure refactor that makes
> `components/` platform-agnostic. Windows behaviour must be **byte-identical**
> when it lands. This is the "cleaner codebase" deliverable.

**Success criterion:** a Windows user notices *nothing*. Every command behaves exactly
as before. The only visible change is the file tree.

---

## Step 0.1 — Create the platform layer

Create `platform/windows/` and move the OS-specific code out of `components/`.
Each file exposes the contract from [architecture.md](architecture.md) §3.

| New file | Contract | Moved from |
|---|---|---|
| `platform/windows/clipboard.ps1` | `Copy-ToClipboard`, `Get-FromClipboard` | inline `Set-Clipboard` calls in 7 files |
| `platform/windows/elevation.ps1` | `Test-Admin`, `Assert-Admin` | `components/shared/admin.ps1` (move wholesale) |
| `platform/windows/packages.ps1` | `Install-Dependency`, `Test-Dependency`, `Update-Dependencies` | Scoop logic in `core/dependencies`, `core/recovery` |
| `platform/windows/openers.ps1` | `Open-Path`, `Open-Editor` | `explorer` / `code` calls in `files/clipboard`, `system/config-files` |
| `platform/windows/terminal.ps1` | `New-TerminalTab`, `Switch-TerminalTab`, `Close-TerminalTab` | `wt` + SendKeys in `terminal/tabs` |
| `platform/windows/power.ps1` | `Invoke-Shutdown`, `Stop-Shutdown` | `shutdown.exe` in `system/shutdown` |
| `platform/windows/env.ps1` | `Set-PersistentPath`, `Get-PersistentPath` | `[Environment]::SetEnvironmentVariable` in `system/path` |

**Do NOT create `platform/linux/` yet.** Phase 0 is Windows-only. Adding empty Linux
stubs now just invites half-finished code into the tree.

---

## Step 0.2 — Rewrite components to call adapters

The mechanical part. Every direct OS call in `components/` becomes an adapter call.

```powershell
# before — components/git/interactive.ps1
Set-Clipboard $commitHash

# after
Copy-ToClipboard $commitHash
```

**Start with clipboard** — it is 7 of the ~18 call sites and is a pure mechanical
substitution with no behaviour change. Do it first to build confidence in the pattern.

Order of attack (lowest risk → highest):
1. **clipboard** (7 files) — pure substitution, no logic change
2. **openers** (2 files) — `explorer` / `code`
3. **elevation** (1 file) — already isolated; just relocate `shared/admin.ps1`
4. **power** (1 file) — `system/shutdown`
5. **env** (1 file) — `system/path`
6. **packages** (5 files) — most tangled; Scoop logic is woven into dependency checks
7. **terminal** (2 files) — `wt`/SendKeys is the messiest; do it last

---

## Step 0.3 — Move WSL to `windows-only/`

`components/terminal/wsl.ps1` → `windows-only/wsl.ps1`.

WSL exists only on Windows. `open-ubuntu`, `open-wsl-simple` and
`Get-WindowsTerminalProfiles` must **never** load on Linux. Same for the
`open-nt ubuntu|wsl|bash` branch in `terminal/tabs.ps1` — it moves behind the
terminal adapter, Windows implementation only.

---

## Step 0.4 — Platform-aware bootstrap

Split the bootloader. `Microsoft.PowerShell_profile.ps1` stays the Windows `$PROFILE`
entry point; add `bootstrap.ps1` holding the shared load sequence.

```powershell
# bootstrap.ps1 — sketch
$script:PowerFlowRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:PowerFlowOS   = if ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop') { 'windows' }
                        elseif ($IsLinux) { 'linux' }
                        else { 'unsupported' }

# 1. settings  2. platform adapters  3. os paths  4. components  5. windows-only  6. help
_pf_source "config\PowerFlow.settings.ps1"
_pf_source_dir "platform\$script:PowerFlowOS"        # ← adapters BEFORE components
_pf_source "config\paths.$script:PowerFlowOS.ps1"
_pf_source_dir "components"
if ($script:PowerFlowOS -eq 'windows') { _pf_source_dir "windows-only" }
```

> ### ⚠️ Confirmed trap: `$IsWindows` is a landmine on 5.1
>
> `install.ps1` declares `#Requires -Version 5.1` and the README advertises
> **"PowerShell 5.1+"** — so Windows PowerShell 5.1 is a supported target.
>
> **`$IsWindows` does not exist in 5.1.** It evaluates to `$null`, which is *falsy*.
> A naive `if ($IsWindows) { 'windows' } elseif ($IsLinux) { 'linux' }` therefore
> detects a 5.1 Windows box as **neither** — the platform layer never loads and the
> whole profile breaks for every 5.1 user.
>
> The `PSEdition -eq 'Desktop'` fallback above is **mandatory**, not defensive. 5.1 is
> always `Desktop` edition and always Windows. Add a smoke test that asserts
> `$script:PowerFlowOS -eq 'windows'` under 5.1 before this ships.

---

## Step 0.5 — Docs (same change, per `CLAUDE.md`)

- **`COMPONENTS.md`** — add a **Platform** column (`Windows` / `Linux` / `Both`) and
  rows for every `platform/**` file.
- **`IMPORT_ORDER.md`** — document the new platform stage and *why* adapters load
  before components.
- **`CLAUDE.md`** — the help-menu rule's folder→section table needs entries for
  `platform/` and `windows-only/`.

---

## Gate — must all pass before Phase 1

- [ ] Every `.ps1` parses clean (`[Parser]::ParseFile` over the tree)
- [ ] Profile loads on Windows with no warnings
- [ ] **No `components/**` file references a Windows API.** Enforce with a grep:
      `Set-Clipboard|explorer|scoop|wt\.exe|WindowsPrincipal|shutdown\.exe|SetEnvironmentVariable`
      must return **zero hits** under `components/`.
- [ ] Manual regression of the touched commands: `git-a`, `git-l`, `git-b`, `gh-l`,
      `copy-pwd`, `cf`/`pf`, `open-nt`, `set-path`, `shutdown`, `pwsh-profile`
- [ ] `pwsh-h` renders correctly

That grep in bullet 3 is the real test of this phase — it is the machine-checkable
definition of "separation of scope," and it should become a CI check in Phase 5.
