# Linux — Installers & Uninstall

Three deliverables:

1. **Terminal installer** — the canonical `curl … | bash` one-liner.
2. **GUI installer** — a graphical wizard for users who never open a terminal first.
3. **Baked-in uninstall** — removable in one command, from inside PowerFlow or from disk.

---

## 1. Principle: two front-ends, ONE core

> ⚠️ The old port died of duplication. **Do not write two installers.**

`install.sh` and `install-gui.sh` are **thin front-ends**. They contain no install logic.
They collect consent, then delegate to the same core.

```
install.sh  ─┐                       (bash, ~60 lines: detect distro, install pwsh)
             ├──►  pwsh install.ps1  ◄── THE installer. Shared with Windows.
install-gui.sh ─┘                     (writes the manifest; does all real work)
```

### The bootstrap problem

The core installer is PowerShell — but on a fresh Linux box **`pwsh` does not exist yet**.
So the bash layer is unavoidable. Keep its job as small as possible:

1. Detect the distro / package manager (`apt` / `dnf` / `pacman` / `zypper`).
2. Install `pwsh` from the appropriate source (Microsoft repo, or the `powershell` snap/AUR).
3. `exec pwsh ./install.ps1 --platform linux`.

Everything after step 3 is shared PowerShell — dependency install, file placement,
`$PROFILE` wiring, manifest writing. **That is the whole point:** one installer codebase
for both platforms.

> `install.ps1` today is 108 lines and hardcodes Scoop. Phase 0's **packages adapter**
> (`Install-Dependency` / `Test-Dependency`) is exactly what makes it cross-platform —
> the installer calls the adapter instead of `scoop` directly.

---

## 2. Terminal installer — `install.sh`

The idiomatic Linux path. Must work non-interactively for CI and dotfile bootstraps.

```bash
curl -fsSL https://github.com/Syntax-Read3r/powerflow/releases/latest/download/install.sh | bash

# non-interactive / scripted
curl -fsSL … | bash -s -- --yes --no-deps
```

| Flag | Effect |
|---|---|
| `--yes` | assume yes; no prompts (CI-safe) |
| `--no-deps` | skip fzf/zoxide/starship/lsd — install PowerFlow only |
| `--prefix <dir>` | override install root (default `~/.local/share/powerflow`) |
| `--uninstall` | run the uninstaller |

**Must be idempotent** — re-running upgrades in place rather than duplicating profile lines.

---

## 3. GUI installer — `install-gui.sh`

For users who want to double-click, not type. On Linux there are two legitimate
interpretations; **recommend (a), keep (b) as a later add-on.**

### (a) Graphical wizard — `zenity` *(recommended)*

A dialog-driven front-end. Same bash bootstrap, but every prompt and the progress bar
are native GTK dialogs. Widely available, tiny dependency, works from a `.desktop` file.

Flow:
1. **Welcome** — what PowerFlow is, version, license.
2. **Dependency checklist** — pre-ticked list (`fzf`, `zoxide`, `starship`, `lsd`, `bat`);
   already-installed tools shown as ✔ and greyed out.
3. **Password prompt** — one `pkexec` / `sudo` elevation for the package install.
4. **Progress bar** — piped from the core installer's stdout.
5. **Done** — "Open a terminal and run `pwsh-h`."

Toolkit fallback chain: `zenity` (GNOME) → `kdialog` (KDE) → `yad` → **fall back to the
terminal installer with a clear message.** Never hard-fail because a dialog tool is missing.

### (b) Distro package — `.deb` / `.rpm` *(later)*

The *most* native "GUI install" on Linux is a package the software centre can open.
Deferred: it needs signing, repo hosting, and per-distro packaging — real infrastructure.
Revisit once the terminal path is proven.

---

## 4. Baked-in uninstall

Today's `uninstall.ps1` is 51 lines and effectively just deletes the profile file. It has
**no record of what was installed**, so it cannot clean up properly or safely.

Fix that with a **manifest**. The installer writes exactly what it did:

`~/.local/share/powerflow/manifest.json`
```json
{
  "version": "3.0.0",
  "installedAt": "2026-07-13T10:04:00Z",
  "profilePath": "~/.config/powershell/Microsoft.PowerShell_profile.ps1",
  "files": ["~/.local/share/powerflow/components/…"],
  "backups": [
    { "original": "~/.config/powershell/Microsoft.PowerShell_profile.ps1",
      "backup":   "~/.config/powershell/…profile.ps1.powerflow-backup.20260713" }
  ],
  "dependencies": [
    { "name": "fzf",      "manager": "apt", "installedByPowerFlow": true  },
    { "name": "starship", "manager": "apt", "installedByPowerFlow": false }
  ]
}
```

### The rule that makes uninstall safe

> **`installedByPowerFlow: false` means never touch it.**
> If the user already had `fzf` before installing PowerFlow, uninstalling PowerFlow must
> not remove `fzf`. Only ever remove what we actually added, and restore what we backed up.

The old port's `uninstall.sh` deleted `~/.bashrc` outright. That is the failure mode a
manifest exists to prevent.

### Three ways to uninstall — all one code path

| Entry point | For | Calls |
|---|---|---|
| `powerflow-uninstall` | inside a PowerFlow session | `uninstall.ps1` |
| `install.sh --uninstall` | terminal, PowerFlow won't load | `uninstall.ps1` |
| "Uninstall PowerFlow" `.desktop` entry | GUI users | `uninstall.ps1` (zenity confirm) |

`powerflow-uninstall` **already exists** on Windows (`components/core/recovery.ps1`). It
becomes cross-platform for free once it calls the packages adapter instead of `scoop`.
No new command, no new help-menu entry — it just starts working on Linux.

Uninstall must always:
- Show exactly what will be removed, and require confirmation (unless `--yes`).
- Restore any backed-up profile.
- Leave a `~/.config/powerflow/` config untouched by default (offer `--purge` to remove it).

---

## 5. XDG paths (Linux)

| What | Path |
|---|---|
| pwsh profile | `~/.config/powershell/Microsoft.PowerShell_profile.ps1` |
| PowerFlow code | `~/.local/share/powerflow/` |
| User config / bookmarks | `~/.config/powerflow/` |
| Manifest | `~/.local/share/powerflow/manifest.json` |

---

## 6. CI (Phase 5)

`release-generate-scripts.yml` currently emits Windows scripts only — the Ubuntu
generation step was deleted in v3.0.0. Re-add, but generating the **new** artifacts:

- `install.sh`, `install-gui.sh` → attached as release assets
- `release-publish.yml` — add them to `files:` (**note `fail_on_unmatched_files: true`;
  a missing asset hard-fails the release**)
- `release-validate.yml` — add a Linux job on the `ubuntu-latest` runner that installs
  pwsh, runs `install.sh --yes`, loads the profile, asserts `pwsh-h` renders, then runs
  `install.sh --uninstall` and asserts a clean removal.

That last check is the real prize: **install → use → uninstall, verified on every release.**
The old port never had it, which is why it silently rotted.

---

## Open decisions

1. **GUI toolkit** — `zenity` wizard (recommended) vs. going straight to `.deb`/`.rpm`?
2. **pwsh install source** — Microsoft apt/dnf repo (official, needs key setup) vs.
   `snap install powershell --classic` (one line, but snap is contentious on some distros)?
3. **Should `install.sh` offer to make `pwsh` the login shell?** Recommend **no** by
   default — too invasive. Offer it as an explicit opt-in flag.
