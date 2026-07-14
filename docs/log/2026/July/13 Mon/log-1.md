# Log 1 — July 13, 2026 — v3.0.0 release prep

**Work performed:**
- **Wave 0 foundation** — created `components/shared/admin.ps1` (`Test-Admin`, `Assert-Admin`), the single elevation check shared by every admin-gated command. Refactored `set-path -System` to call `Assert-Admin` instead of its own inline `WindowsPrincipal` check. Registered in the bootloader at Stage 3 (shared), ahead of `system/path.ps1` at Stage 10.
- **`shutdown` cap raised 3h → 6h** (180 → 360 min). Verified `6h` arms and `6h 1m` / `7h` reject.
- **Deleted the Ubuntu/Linux port** — `ubuntu/` (9 files, 4,160 lines: `.bashrc`, a 2,105-line `.zshrc`, `install.sh`, `uninstall.sh`, `install-essentials.sh`, `nav.fish`, READMEs) plus `docs/claude.integration.md` (Fish-on-Ubuntu notes from the same abandoned effort).
- **Repaired the release CI**, which depended on the deleted files and would have hard-failed the release. Removed Ubuntu asset generation, validation and publishing from all five `release-*.yml` workflows. Verified all six workflows still parse as valid YAML.
- **Stripped false cross-platform claims** from `docs/features.md` ("complete feature parity with Ubuntu/WSL"), `docs/installation.md` (the 53-line Ubuntu install section, which linked to the now-deleted `ubuntu/README.md`), and `docs/git-rl-project-setup.md`.
- **Fixed a live `rm` bug** — `rm *.log` and `rm a.txt b.txt` matched nothing and silently deleted nothing, because all arguments were joined into one literal path. Each argument is now resolved as its own pattern. Updated `pwsh-h`.
- **Wrote the Linux rebuild plan** — `docs/plan/linux/` (README, architecture, phase-0-refactor, installers).
- **Wrote the v3.0.0 upgrade guide** — `docs/migration/v3-upgrade.md`.
- Corrected CHANGELOG drift: `[2.2.1]` and `[2.1.0]` were still marked `Unreleased` despite being tagged. Dated them from their git tags (2026-05-25, 2026-05-24).

**Files modified:**
- Added: `components/shared/admin.ps1`, `docs/migration/v3-upgrade.md`, `docs/plan/linux/{README,architecture,phase-0-refactor,installers}.md`, this log
- Deleted: `ubuntu/**` (9 files), `docs/claude.integration.md`
- Modified: `Microsoft.PowerShell_profile.ps1`, `components/system/{path,shutdown}.ps1`, `components/files/operations.ps1`, `components/help/menu.ps1`, `COMPONENTS.md`, `IMPORT_ORDER.md`, `CHANGELOG.md`, `README.md`, `docs/{features,installation,instructions,future-dev-plan,git-rl-project-setup}.md`, `.github/workflows/release-{validate,generate-scripts,bundle-archive,publish,notify}.yml`, `.github/workflows/release.yml`

**Decisions:**
- **Major bump (2.2.1 → 3.0.0).** `ubuntu-install.sh` and `.bashrc` were published release assets in v2.2.x, so removing them is a breaking change per the semver rules in `docs/instructions.md`.
- **Kept the Windows-side WSL launchers.** `components/terminal/wsl.ps1` (`open-ubuntu`, `open-wsl-simple`) and the `open-nt ubuntu|wsl|bash` branch in `tabs.ps1` are *Windows* PowerShell functions that open a WSL tab in Windows Terminal. They are not part of the Linux port and were deliberately not deleted.
- **Kept `ubuntu-latest` in the workflows** — that is the GitHub Actions runner OS, not the port. Likewise the `bash`/`ubuntu-latest` strings inside `components/projects/create-next.ps1` belong to the generated Next.js template.
- **Internal helpers stay out of `pwsh-h`.** `Test-Admin` / `Assert-Admin` are registered in `COMPONENTS.md` but not the help menu, matching the existing convention for `Create-RemoteRepository`, `Initialize-DefaultBookmarks` and `Invoke-DeleteBranch`.
- **Linux will be rebuilt on PowerShell 7, not bash.** The old port failed because every feature existed twice and drifted. The new design shares one codebase behind a platform-adapter layer. See `docs/plan/linux/architecture.md`.
- Did not edit `config/PowerFlow.settings.ps1`; the version bump is owned by `git-rl`.

**Bug status:**
- Fixed: `rm *.log` / `rm a.txt b.txt` silently deleted nothing (pre-existing, Windows).
- Known, documented, not fixed: PowerFlow's `rm` deletes a directory recursively after one confirmation, where GNU `rm` refuses without `-r`. Acceptable on Windows; captured as a command-shadowing decision for the Linux port in `docs/plan/linux/architecture.md`.

**Commit message:** `feat!: remove Ubuntu/Linux port, add shared admin helpers, fix rm globs (v3.0.0)`
