# Log 2 — July 14, 2026 — v3.2.0: git-rl works in any project + PowerFlow starts on login

**Work performed:**

- **New: `install.sh --login-shell auto|login|none`.** Reported from a real headless
  Proxmox server: PowerFlow installed successfully, the user rebooted, landed in bash, and
  PowerFlow was gone. Cause: PowerFlow is a PowerShell *profile* — it only loads when
  `pwsh` runs — and the login shell is bash. The installer never mentioned this and told
  people to *"restart your shell"*, which on Linux does nothing at all.

  - `auto` (recommended) appends a guarded block to `~/.bashrc`. Three guards:
    `$- == *i*` (interactive only — never scp/rsync/cron), `PWSH_STARTED` (no login loop),
    and `command -v pwsh` (**if pwsh disappears you still get bash — no lockout**).
    Idempotent; `--uninstall` strips it back out.
  - `login` uses `chsh`. Cleaner, but leaves you with **no shell** if pwsh fails to start.
  - With no flag it asks. With `--yes` and no flag it does **nothing** — CI and
    `curl … | bash` must never rewrite a user's shell config unasked.
  - The GUI installer asks the same question.
  - The Linux CI job now asserts all four properties, including the lockout guard (it
    actually deletes `pwsh` and checks a shell still comes up).

- **New: `components/git/version-files.ps1`** — detects, reads and rewrites a project's
  *native* version file. `git-rl` previously read one hardcoded location
  (`config/PowerFlow.settings.ps1` → `$script:POWERFLOW_VERSION`) and, in any other
  project, silently fell back to the latest git tag and **rewrote nothing** — so a Node
  project's `package.json` was never bumped.

  Now supports: `package.json`, `pyproject.toml` (`[project]` / `[tool.poetry]`),
  `Cargo.toml` (`[package]`), `*.csproj`, `build.gradle(.kts)`, `VERSION`, and
  `config/PowerFlow.settings.ps1`. Falls back to the latest git tag if none exists.

- **Multiple version files are updated together; drift is caught before the bump.**
  `Test-VersionDrift` warns when e.g. `package.json` says 1.0.0 and `VERSION` says 0.9.0,
  and on confirmation syncs them all. If any file fails to update, the release aborts
  **before** anything is committed, tagged or pushed.

- **Rewrote `docs/git-rl/SETUP-PROMPT.md` and `docs/git-rl/README.md`.** They previously
  told Node/Python developers to create a PowerShell file in their repo and add a CI check
  to stop it drifting from `package.json`. That was a workaround for the limitation above.
  The prompt now says: if the project already has a version file, you are done.

**Files modified:**
- Added: `components/git/version-files.ps1`, this log
- Modified: `components/git/release.ps1`, `Microsoft.PowerShell_profile.ps1`,
  `install.sh`, `install.ps1`, `install-gui.sh`,
  `docs/git-rl/SETUP-PROMPT.md`, `docs/git-rl/README.md`,
  `docs/migration/v3-upgrade.md`, `COMPONENTS.md`, `IMPORT_ORDER.md`,
  `README.md`, `CHANGELOG.md`, `.github/workflows/release-validate-linux.yml`

**Decisions:**
- **Minor bump (3.1.0 → 3.2.0).** New capability, backwards compatible — PowerFlow still
  resolves its own `config/PowerFlow.settings.ps1` exactly as before (verified).
- **Regex rewrite, never parse-and-reserialise.** Round-tripping `package.json` through
  `ConvertFrom-Json` / `ConvertTo-Json` would reorder keys and reindent the whole file — an
  unacceptable diff for a version bump. The regex is anchored to the *current* version so
  it can only match the intended occurrence.
- **TOML section anchoring.** `Read-TomlSectionVersion` matches the version only inside
  `[package]` / `[project]` / `[tool.poetry]`. A naive `^version = "..."` would happily
  match the first entry under `[dependencies]`.
- **`version-files.ps1` loads BEFORE `release.ps1`** in the bootloader — `git-rl` calls
  `Get-ProjectVersion` at runtime.
- Lives in `components/git/`, not `platform/`: text handling is platform-agnostic, so it
  is not an OS adapter.

**Bugs found and fixed this session:**
- **The whole file failed to parse.** In a double-quoted PowerShell string the regex
  fragment `$(?:` is read as a *subexpression* `$(...)`, giving
  `"Missing property name after reference operator"`. The TOML pattern is now built by
  concatenating single-quoted fragments, which keep the regex literal.
- **The first version of the test was worthless.** The nested `semver.version` fixture was
  `9.9.9` — the same value being bumped *to* — so a corrupted nested key would have looked
  identical to a correct one. Changed to `8.8.8` so the trap can actually fire.
- **`chsh` failed silently.** Plain `chsh` prompts for a password, so it fails when piped
  or non-interactive: the login shell was never changed and **nothing was reported**. It
  now elevates via `sudo` and verifies the result in `/etc/passwd` rather than trusting the
  exit code.
- **Uninstall could have left the user with no shell.** It printed "reverting to bash"
  while leaving `pwsh` as the login shell (same `chsh` bug), then removed pwsh — so the
  next login would point at a shell that no longer existed. Uninstall now reverts the shell
  **before** removing pwsh, verifies it, and **aborts loudly** if it cannot.
- **README had no Linux install instructions at all.** Linux was rebuilt in v3.0.0 but the
  README still listed "Windows 10/11" as a prerequisite and offered only the PowerShell
  one-liner, three releases later.

**Verification:** all 7 project types detect, read and bump correctly; formatting and line
counts preserved; nested/dependency versions provably untouched (`left-pad 1.0.0`,
`serde 1.0.100`, `[tool.other] 99.99.99`, nested `semver 8.8.8`); multi-file drift detected
and synced. PowerFlow still resolves its own version file — no regression on the tool that
will cut this release.

**Commit message:** `feat(git-rl): detect and bump any project's version file (v3.2.0)`
