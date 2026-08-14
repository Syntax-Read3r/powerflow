# `git-rl` Project Setup Guide

> 🚀 **You probably want `git-rl -h` instead of reading this by hand.**
>
> Run it from inside the project you want to set up. It writes
> **`docs/git-release-help.md`** into that project and copies a ready-made AI setup prompt
> to your clipboard — paste it into any AI assistant and it builds the whole pipeline, then
> verifies it.
>
> | | |
> |---|---|
> | [`docs/git-rl/SETUP-PROMPT.md`](git-rl/SETUP-PROMPT.md) | The prompt `git-rl -h` copies to your clipboard and embeds in the guide. |
> | [`docs/git-rl/README.md`](git-rl/README.md) | The short manual — releasing by hand, aborting a bad release. |
> | **This file** | The deep technical reference: every workflow, field by field. |

---

## Overview

`git-rl` is a two-part release system:

1. **Local** — the `git-rl` PowerShell command bumps the version, commits, creates a `vX.Y.Z` tag, and pushes it
2. **CI/CD** — pushing the tag triggers a GitHub Actions pipeline that validates, builds, publishes, and notifies

Both parts must be set up for the full system to work. The sections below describe exactly what each part needs.

---

## Part 1 — Local: What `git-rl` Needs

### Version resolution (priority order)

| Priority | Source | Requirement |
|----------|--------|-------------|
| 1 | `config/PowerFlow.settings.ps1` | File exists AND contains `$script:POWERFLOW_VERSION = "X.Y.Z"` |
| 2 | Latest git tag | A tag matching `vX.Y.Z` exists |
| 3 | Neither | **Stops.** `git-rl` reports that the project is not set up and points at `git-rl -h`, writing nothing. It does not fall back to `0.0.0` and open the bump picker |

**Priority 1 is the recommended setup** — it auto-updates the version file as part of the release commit. Priority 2 (tag-only) works but leaves no version in source files.

### Minimum required file

Create `config/PowerFlow.settings.ps1` at the repo root containing at minimum:

```powershell
$script:POWERFLOW_VERSION = "1.0.0"
```

Additional variables are fine in the same file. `git-rl` only reads and writes the `POWERFLOW_VERSION` line.

**Read pattern:** `\$script:POWERFLOW_VERSION = "([^"]+)"`
**Write pattern (replaces):** `\$script:POWERFLOW_VERSION = "[^"]+"` → `$script:POWERFLOW_VERSION = "$newVersion"`

### What `git-rl` does step by step

1. Reads current version from `config/PowerFlow.settings.ps1`
2. Presents fzf bump picker (patch / minor / major / custom)
3. Prompts for a release description
4. Updates `config/PowerFlow.settings.ps1` to the new version
5. `git add .`
6. `git commit -m "vr-commit (vX.Y.Z) - <description>"`
7. `git push`
8. `git tag vX.Y.Z`
9. `git push origin vX.Y.Z` → **triggers the CI pipeline**

---

## Part 2 — CI/CD: The GitHub Actions Pipeline

The pipeline lives in `.github/workflows/` and consists of **6 files**. The entry point is `release.yml` which calls the others in stages.

```
push tag v*
    │
    ▼
release.yml  (orchestrator)
    │
    ├── Stage 1 ──► release-validate.yml       (checks version, files, syntax)
    │                        │
    ├── Stage 2 (parallel) ──┤
    │   ├────────────────────► release-generate-scripts.yml  (install/uninstall/release notes)
    │   └────────────────────► release-bundle-archive.yml    (zip archive)
    │                        │
    ├── Stage 3 ─────────────► release-publish.yml           (GitHub release + assets)
    │                        │
    └── Stage 4 ─────────────► release-notify.yml            (log / notifications)
```

---

### `release.yml` — Orchestrator

**Trigger:** `push: tags: - 'v*'`

**Responsibilities:** Calls all component workflows in the correct order. Passes `version` and `tag_name` outputs from validate to downstream jobs.

**What to adapt for a new project:**
- Change the workflow `name:`
- The stage structure and wiring is generic — copy it as-is and only update names

```yaml
on:
  push:
    tags:
      - 'v*'
```

---

### `release-validate.yml` — Validate

**Responsibilities:**
1. Parse `version` and `tag_name` from the git ref (strips leading `v`)
2. Check required files exist (hard fail) and optional files exist (warn)
3. Verify `config/PowerFlow.settings.ps1` contains `$script:POWERFLOW_VERSION` matching the tag
4. Run a syntax check on the main entry-point file

**Outputs:** `version` (e.g. `2.0.1`), `tag_name` (e.g. `v2.0.1`) — consumed by all downstream jobs.

**What to adapt for a new project:**

```yaml
env:
  SETTINGS_FILE: config/PowerFlow.settings.ps1   # keep this — it's what git-rl writes
```

Change the required/optional files list to match the project:

```powershell
$required = @(
    "config/PowerFlow.settings.ps1",   # always required — git-rl writes here
    "src/index.ts",                    # your project's entry point
    "package.json"                     # or whatever is critical
)
$optional = @(
    "README.md",
    "CHANGELOG.md"
)
```

The version-match check reads this exact pattern — do not change it:
```powershell
$content -match '\$script:POWERFLOW_VERSION = "([^"]+)"'
```

If the project also tracks version elsewhere (e.g. `package.json`), add an advisory check (warn-only) rather than a hard fail.

---

### `release-generate-scripts.yml` — Generate Scripts

**Responsibilities:** Generates install/uninstall scripts and `RELEASE_NOTES.md`. Uploads everything as the `release-scripts` artifact.

**Release notes:** Automatically extracted from `CHANGELOG.md` by matching the `## [X.Y.Z]` section. Falls back to a generic template if the section is not found.

**What to adapt for a new project:**

This is the most project-specific workflow. The install/uninstall scripts need to match the project's delivery mechanism:

| Project type | Install script approach |
|---|---|
| PowerShell profile | Download zip, extract to `$PROFILE` directory (existing approach) |
| Node.js CLI | `npm install -g <package>` or download binary |
| Python package | `pip install <package>` or download wheel |
| Standalone binary | Download binary from release assets, add to PATH |
| Web app | Deploy steps to hosting provider |

**Keep the `RELEASE_NOTES.md` generation logic unchanged** — it reads `CHANGELOG.md` and the format is project-agnostic:

```powershell
$pattern = "(?s)## \[$version\].*?(?=## \[|\z)"
```

Maintain `CHANGELOG.md` with entries in `## [X.Y.Z]` format and release notes are automatic.

**Artifact name must stay:** `release-scripts` — downstream jobs reference it by this name.

---

### `release-bundle-archive.yml` — Bundle Archive

**Responsibilities:** Creates a `<project>-vX.Y.Z.zip` containing the distributable project files. Uploads as the `component-archive` artifact.

**What to adapt for a new project:**

Change the zip name and the list of paths included:

```powershell
$zipName = "my-project-v$version.zip"   # change project name

$paths = @(
    "src",                  # whatever your distributable files are
    "config",               # keep config — contains the settings file
    "README.md",
    "CHANGELOG.md"
)
Compress-Archive -Path $paths -DestinationPath $zipName -Force
```

**Artifact name must stay:** `component-archive`

---

### `release-publish.yml` — Publish

**Responsibilities:** Downloads both artifacts, creates the GitHub release using `softprops/action-gh-release@v3`, attaches all assets.

**What to adapt for a new project:**

- Change `name:` to your project name
- Update the `files:` list to match the assets your generate and bundle steps produce
- Remove assets that don't apply to your project

```yaml
- uses: softprops/action-gh-release@v3
  with:
    tag_name:  ${{ inputs.tag_name }}
    name:      "MyProject ${{ inputs.tag_name }}"
    body_path: ./release-files/RELEASE_NOTES.md
    files: |
      ./release-files/install.ps1
      ./release-files/my-project-v${{ inputs.version }}.zip
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

**No changes needed** to the artifact download steps — they use the fixed names `release-scripts` and `component-archive`.

---

### `release-notify.yml` — Notify

**Responsibilities:** Logs the release outcome and install commands. Extend this file for Slack, Discord, email, or webhook notifications.

**What to adapt for a new project:**

Update the log messages and install commands to match the project. The structure is boilerplate — the only project-specific content is the strings.

---

## Checklist for AI Setup

### Local side
- [ ] Create `config/PowerFlow.settings.ps1` with `$script:POWERFLOW_VERSION = "X.Y.Z"`
- [ ] Ensure at least one commit exists on the branch

### CI/CD side
- [ ] Create `.github/workflows/release.yml` (copy orchestrator, update name)
- [ ] Create `.github/workflows/release-validate.yml` (update required files list, keep version-match logic unchanged)
- [ ] Create `.github/workflows/release-generate-scripts.yml` (adapt install/uninstall for project type, keep RELEASE_NOTES.md logic)
- [ ] Create `.github/workflows/release-bundle-archive.yml` (change zip name and bundled paths)
- [ ] Create `.github/workflows/release-publish.yml` (update release name and assets list)
- [ ] Create `.github/workflows/release-notify.yml` (update log messages)
- [ ] Ensure repo has `contents: write` permission available (GitHub default — no action needed unless org restricts it)
- [ ] Ensure `CHANGELOG.md` exists with entries in `## [X.Y.Z]` format

### Verification
- [ ] Run `git-rl` → fzf header shows `Current: vX.Y.Z (config/PowerFlow.settings.ps1)`
- [ ] Complete a release → GitHub Actions pipeline runs all 4 stages green
- [ ] GitHub release page shows expected assets

---

## Adapting the Version File for Non-PowerShell Projects

If the project also tracks version in a native file, add a sync block inside `git-release` (in PowerFlow's `components/git/release.ps1`) after the `# ── Update settings.ps1` block:

**`package.json`**
```powershell
$pkgPath = Join-Path $repoRoot "package.json"
if (Test-Path $pkgPath) {
    $pkg = Get-Content $pkgPath -Raw | ConvertFrom-Json
    $pkg.version = $newVersion
    $pkg | ConvertTo-Json -Depth 10 | Set-Content $pkgPath -Encoding UTF8
    Write-Host "✅ package.json → $newVersion" -ForegroundColor Green
}
```

**`pyproject.toml`**
```powershell
$pyPath = Join-Path $repoRoot "pyproject.toml"
if (Test-Path $pyPath) {
    $raw = Get-Content $pyPath -Raw
    $raw = $raw -replace '(?m)^version = "[^"]+"', "version = `"$newVersion`""
    Set-Content $pyPath $raw -Encoding UTF8
    Write-Host "✅ pyproject.toml → $newVersion" -ForegroundColor Green
}
```

**`VERSION` file**
```powershell
$verPath = Join-Path $repoRoot "VERSION"
if (Test-Path $verPath) {
    Set-Content $verPath $newVersion -Encoding UTF8 -NoNewline
    Write-Host "✅ VERSION → $newVersion" -ForegroundColor Green
}
```

Add the corresponding sync to `release-validate.yml` as an advisory (warn-only) check so mismatches are surfaced in CI without blocking the release.
