# PowerFlow — Linux Port Plan

> The original `ubuntu/` port (bash/zsh/fish, 4,160 lines) was deleted in **v3.0.0**.
> It is being rebuilt properly. This directory is the plan.

## Why the old port failed

It was a **parallel re-implementation**. A 2,105-line `.zshrc` re-wrote navigation,
git helpers, bookmarks and file operations in shell script, duplicating logic that
already existed in PowerShell. Two copies of every feature meant guaranteed drift:
a fix on Windows never reached Linux, and the Linux half rotted.

**The new port shares one codebase.** Linux is not a second implementation — it is a
second *backend* behind the same components.

## Documents

| Doc | Purpose |
|---|---|
| [architecture.md](architecture.md) | Runtime choice, ports-and-adapters design, file layout, command-shadowing policy |
| [phase-0-refactor.md](phase-0-refactor.md) | The Windows-safe refactor. Zero Linux code. Do this first. |
| [installers.md](installers.md) | Terminal + GUI installers, manifest-based uninstall, Linux CI |

## Phase overview

Every phase gates on a **Windows regression pass**. Linux work is purely additive:
Windows must never break to make Linux work.

| Phase | Goal | Status |
|---|---|---|
| **0** | Extract platform adapters; `components/` becomes OS-agnostic | ✅ **Done (v3.0.0)** |
| **1** | Linux boots: profile loads under `pwsh`, `pwsh-h` renders | ✅ **Done (v3.0.0)** |
| **2** | Clipboard adapter → unlocks git, github, navigation on Linux | ✅ **Done (v3.0.0)** |
| **3** | Remaining adapters: packages, elevation, openers, locations | ✅ **Done (v3.0.0)** |
| **4** | Linux-native equivalents: tabs→tmux, shutdown, PATH | ✅ **Done (v3.0.0)** |
| **5** | Ship: terminal + GUI installers, manifest uninstall, Linux CI job | ✅ **Done (v3.0.0)** |

**All phases shipped together in v3.0.0** — the removal and the rebuild landed in the same
release, so no version ever went out with Linux deleted-and-not-replaced.

Phase 5 is specced in [installers.md](installers.md): `install.sh` (terminal),
`install-gui.sh` (zenity wizard), and a manifest-driven uninstall reachable three ways.
`release-validate-linux.yml` proves **install → use → uninstall** on a real `ubuntu-latest`
box and **blocks publish** if Linux is broken.

## Guiding rules

1. **`components/` never calls an OS API directly.** It calls an adapter
   (`Copy-ToClipboard`, not `Set-Clipboard`). This is the whole design.
2. **Windows is the reference implementation.** A Linux adapter that can't do
   something declines gracefully — it never degrades the Windows path.
3. **No feature is "done" until it works on both platforms or is explicitly
   marked Windows-only** in `COMPONENTS.md`.
4. **WSL is a Windows concept.** `open-ubuntu` / `open-wsl-simple` live in
   `windows-only/` and never port.
