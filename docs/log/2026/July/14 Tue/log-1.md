# Log 1 — July 14, 2026 — v3.1.0: disk reclaim + Linux installer hardening

**Work performed:**

- **New feature: `installed-apps` and `disk-big`** (`components/system/apps.ps1`,
  `platform/{windows,linux}/adapters/apps.ps1`). Find what is actually consuming the disk,
  then open / copy / uninstall / trash / permanently delete it.
  - `installed-apps -o` scans once and prints a band overview (Band / Apps / Total), then
    lets you drill into a band via fzf **without rescanning** — the overview and the
    drill-in share one pass.
  - Rows show **size and age**. Age comes from the registry `InstallDate` (falling back to
    folder creation time) on Windows; `rpm INSTALLTIME` and pacman's Install Date on Linux;
    and the mtime of `/var/lib/dpkg/info/<pkg>.list` for dpkg, which records no install date.
  - `disk-big` scans hot spots for large **folders and files** — a registry enumeration can
    never surface a 169 GB `docker_data.vhdx`, because it is not an "installed app".
- **New: `git-rl -h`** (`components/git/release.ps1`, `docs/git-rl/`). `git-rl` only works
  in a repo that satisfies its contract, and that knowledge lived nowhere. `git-rl -h` asks
  (via fzf) whether you are in your project folder; if yes it writes a self-contained
  `docs/git-release-help.md` into that project — the **AI setup prompt** *and* the manual —
  and copies the prompt to the clipboard. If no, it advises navigating there and exits
  **without printing anything**.

- **Linux installer fixed on every distro it claims to support.** The `dnf`/`pacman`/
  `zypper`/`apk` paths had never been executed once. Verified on real containers: Debian 13,
  Ubuntu 22.04, Fedora 42, Arch, openSUSE Tumbleweed, Alpine (musl).
- **CI distro matrix** added to `release-validate-linux.yml` — 8 distros, all 5 package
  managers, asserting pwsh *runs*, deps install, profile loads, coreutils unshadowed.

**Files modified:**
- Added: `components/system/apps.ps1`, `platform/windows/adapters/apps.ps1`,
  `platform/linux/adapters/apps.ps1`, `docs/git-rl/SETUP-PROMPT.md`,
  `docs/git-rl/README.md`, this log
- Modified: `install.sh`, `install.ps1`, `uninstall.ps1`,
  `Microsoft.PowerShell_profile.ps1`, `components/git/release.ps1`,
  `components/help/menu.ps1`, `COMPONENTS.md`, `README.md`, `CHANGELOG.md`,
  `docs/git-rl-project-setup.md`,
  `.github/workflows/release-validate.yml`, `.github/workflows/release-validate-linux.yml`

**Decisions:**
- **Minor bump (3.0.1 → 3.1.0)**, not a patch: this adds new user-facing commands. The
  installer fixes ride along, which is desirable — a Debian user installing 3.1.0 gets the
  self-healing installer *and* the new feature in one step.
- **1 GB floor and single-band queries** are the safety model. `1gb-100gb` is refused. An
  unreviewable list in front of a delete action is how people destroy things.
- **Apps are uninstalled, never `rm -rf`'d.** Deleting an app's folder leaves the
  uninstaller, registry keys and PATH shims behind.
- **Virtual disks are special-cased.** Deleting a `.vhdx` destroys every image, container
  and volume inside it — and would not reclaim the space anyway, since a VHDX grows but
  never shrinks. The tool recommends prune-then-compact instead.
- The fzf picker uses the `value<TAB>display` pattern (`--with-nth=2..`) per
  `docs/solved-problems/powershell-fzf-decorated-row-parsing.md`, so it cannot repeat the
  row-parsing bug that broke `gh-l-org`.
- Did not edit `config/PowerFlow.settings.ps1`; the version bump is owned by `git-rl`.

**Bugs found and fixed this session:**
- `install.sh` built an **Ubuntu** repo URL from a Debian `VERSION_ID` and fell back to a
  hardcoded `debian/12` repo. On Debian 13 that repo's SHA1-signed key is rejected by apt
  → `"The repository is not signed."` Reported by a user on a real Proxmox server.
- **A failed install left the machine permanently unrecoverable**: the stale Microsoft repo
  poisons every `apt-get update`, and `set -e` then aborts the installer before it reaches
  the corrected code. The installer now purges a stale source before touching apt.
- The archive fallback installed **no runtime libraries** — pwsh installed and then died
  with `"Couldn't find a valid ICU package"`, while the installer reported success because
  it only checked `command -v pwsh`. It now verifies pwsh **runs**.
- `dnf`/`zypper` imported the signing key but **never added the repo**.
- Alpine is **musl**, needing a different archive; `apk` was missing from detection entirely.
- **Non-root crash**: `$sudo = if (root) { @() } else { @('sudo') }` — PowerShell unrolls a
  single-element array to a scalar, making `$sudo + $cmd` a *string* concat, so `$full[0]`
  indexed the character `'s'`. Only broke when not root, so it passed in a root container
  and failed on the CI runner.
- `Format-Age` threw on a null install date (a `[datetime]` parameter cannot take `$null`).
- **`docs/git-rl/` did not survive installation.** `install.ps1` copied only `config/`,
  `components/`, `platform/` and `windows-only/` — but `git-rl -h` **reads** those docs at
  runtime, so they are a dependency, not documentation. On a real install they were absent
  and `git-rl -h` silently fell back to a network fetch, failing entirely offline. The
  installer now ships `docs/git-rl/`, the uninstaller removes it, and the Linux CI job
  asserts it survives an install so this cannot regress.

**Commit message:** `feat: add installed-apps + disk-big disk reclaim; fix Linux installer across all distros (v3.1.0)`
