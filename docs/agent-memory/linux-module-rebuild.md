---
name: linux-module-rebuild
description: The old Ubuntu/Linux port was deleted in v3.0.0; a properly designed Linux module is to be built from scratch
metadata: 
  node_type: memory
  type: project
  originSessionId: <archived>
---

On 2026-07-06 the entire `ubuntu/` Linux port was deleted (9 files, 4,160 lines: `.bashrc`, a 2,105-line `.zshrc`, `install.sh`, `uninstall.sh`, `install-essentials.sh`, `nav.fish`, READMEs), along with `docs/claude.integration.md` (Fish-on-Ubuntu notes from the same abandoned effort). Shipped as the **v3.0.0 breaking change**.

**Why:** the port was poorly written and never properly configured. It is being replaced by a Linux module built properly from scratch — that rebuild is the next major initiative after [[future-dev-wave-plan]].

**How to apply:**
- Do NOT resurrect the old `ubuntu/` code — it was deliberately removed. Build fresh.
- **`components/terminal/wsl.ps1` and the `open-nt ubuntu|wsl|bash` branch in `tabs.ps1` were deliberately KEPT.** They are *Windows-side* PowerShell functions that launch a WSL tab in Windows Terminal and bridge `C:\…` → `/mnt/c/…`. They are not part of the Linux port. Don't delete them when working on Linux.
- The release CI (`.github/workflows/release-*.yml`) no longer generates or publishes `ubuntu-install.sh`, `ubuntu-uninstall.sh`, or the `.bashrc` asset. A new Linux module must re-add its own CI wiring — `release-validate.yml` hard-fails on missing required files, and `release-publish.yml` sets `fail_on_unmatched_files: true`.
