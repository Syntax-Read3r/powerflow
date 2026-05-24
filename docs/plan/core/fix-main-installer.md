# Plan — Fix Main-Branch Installer for v2.x Modular Architecture

> **Status: Awaiting approval**

## Goal

Update the root `install.ps1` so it downloads the full zip archive (bootloader +
`config/` + `components/`) rather than only the bootloader file. Add clear
documentation in `README.md` and `docs/installation.md` of both install URL patterns:
the versioned pinned URL and the "always latest" URL.

---

## Root Cause

`install.ps1` in the repo root downloads only `Microsoft.PowerShell_profile.ps1`.
For the v1.x monolithic profile this was sufficient. For v2.x (modular architecture)
the bootloader alone is useless — without `components/` and `config/` every function
is missing. Anyone using `raw.githubusercontent.com/main/install.ps1` gets a broken
installation.

The CI-generated `install.ps1` (from `release-generate-scripts.yml`) is correct: it
downloads `powerflow-v{version}.zip` and extracts `Microsoft.PowerShell_profile.ps1`,
`config/`, `components/`, and `docs/` to the profile directory. The root installer
needs to match that logic for "latest release."

---

## Two Install URL patterns

| Pattern | URL | When to use |
|---|---|---|
| **Pinned versioned** | `releases/download/v2.2.0/install.ps1` | Reproducible, production installs — created by CI when `git-rl` runs |
| **Latest from main** | `raw.githubusercontent.com/main/install.ps1` | Always gets newest code — depends on a GitHub Release existing |

---

## Scope

**Changing:**
- `install.ps1` — rewrite to download zip from `releases/latest` API; extract full component tree; keep Scoop + tools installation
- `README.md` — document both URL patterns; add note that versioned URL is available after each release
- `docs/installation.md` — same documentation update

**Not changing:**
- CI workflows — `release-generate-scripts.yml` already generates correct versioned install.ps1
- Component files — no functional changes

---

## Chunks

### Chunk 1 — `install.ps1`: Download zip from releases/latest

Replace the current single-file download block with:

1. Call GitHub API: `GET https://api.github.com/repos/Syntax-Read3r/powerflow/releases/latest`
2. Find the `powerflow-v{version}.zip` asset in `.assets`
3. Download to `$env:TEMP\powerflow-v{version}.zip`
4. Extract to `$env:TEMP\powerflow-v{version}\`
5. Copy `Microsoft.PowerShell_profile.ps1` → `$profilePath`
6. Copy `config\`, `components\`, `docs\` → `$profileDir\` (Recurse + Force)
7. Clean up temp files
8. Continue with existing Scoop + tools installation (unchanged)

**Fallback**: if the API call fails or no release exists, print an actionable error message pointing to GitHub releases page and exit cleanly (do not silently produce a broken install).

### Chunk 2 — `README.md`: Document both URL patterns

Replace the Quick Installation section to show both patterns:

```
### Versioned Install (Recommended)
irm https://github.com/Syntax-Read3r/powerflow/releases/download/v2.2.0/install.ps1 | iex

### Always Latest
irm https://raw.githubusercontent.com/Syntax-Read3r/powerflow/main/install.ps1 | iex
```

Add a note: "The versioned URL is created automatically when a release is published."

### Chunk 3 — `docs/installation.md`: Same update

Mirror the README Quick Install section update in the installation guide.

### Chunk 4 — Log

Create `docs/log/2026/May/24 Sun/log-6.md`.

---

## Rollback

`install.ps1` is the only functional change. Revert by restoring the old file.
No persistent state is modified — the installer is idempotent.

## Testing

1. Run updated `install.ps1` → downloads zip, extracts all folders, profile directory
   contains `Microsoft.PowerShell_profile.ps1` + `components/` + `config/`
2. Reload profile → `✅ PowerFlow v2.2.0 loaded` (all components found)
3. Simulate missing release (point at a non-existent tag) → clean error message, no partial install
