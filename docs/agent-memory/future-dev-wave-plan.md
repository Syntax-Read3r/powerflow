---
name: future-dev-wave-plan
description: "Agreed build order (waves) for implementing the docs/future-dev-plan.md backlog, and which wave is done"
metadata: 
  node_type: memory
  type: project
  originSessionId: <archived>
---

Agreed sequencing for the [[project-architecture]] future-dev backlog (`docs/future-dev-plan.md`), reorganized from the doc's impact-tiers into dependency/effort-aware waves on 2026-07-06.

**Why:** trivial one-liners and shared foundations should ship before the features that depend on them, rather than strictly by impact tier.

**How to apply:** build in this order; each feature ships with its `components/help/menu.ps1` entry (user-facing commands only) + `COMPONENTS.md` row in the same change.

- **Wave 0 — Foundation ✅ DONE (2026-07-06):** `components/shared/admin.ps1` (`Test-Admin`, `Assert-Admin`); refactored `components/system/path.ps1` to use it. Internal helpers → COMPONENTS.md only, NOT the help menu (follows existing convention for `Create-RemoteRepository` etc.).
- **Wave 1 — Free wins:** `pwsh-r` (config-files.ps1), `show-path` (path.ps1), `json` (shared/json.ps1), `watch` (terminal/watch.ps1).
- **Wave 2 — Highest impact:** `kill-port`/`which-port` (system/ports.ps1), `load-env`/`show-env` (system/env.ps1). `load-env` parsing is the only non-trivial part.
- **Wave 3 — Admin cluster (needs Wave 0):** `elevate` (system/elevation.ps1), `symlink` (files/operations.ps1), `hosts` (system/hosts.ps1).
- **Wave 4 — Tier 2 polish:** `kill-proc`/`find-proc` (system/processes.ps1, fzf), `zip`/`unzip` (files/archive.ps1), `sysinfo` (system/sysinfo.ps1).
- **Wave 5 — Niceties:** `http-get`/`http-post` (shared/http.ps1), `scoop-up` (system/packages.ps1), `new-script` (projects/create-script.ps1), `docker-list`.
