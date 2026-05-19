# Plan — Navigation Fuzzy Search (fzf Integration)

> **Status: Implemented** — This plan was created retrospectively after implementation.
> Future comprehensive tasks must have the plan approved BEFORE implementation begins (see `docs/instructions.md` §5a).

## Goal

Replace the 2-level hardcoded nav search with a BFS traversal up to 4 levels deep, piping
all candidate directories to fzf for fuzzy matching, so `nav power` navigates to `powerflow`
regardless of its nesting depth.

## Scope

**Changing:**
- `components/navigation/projects.ps1` — add `-All` switch for candidate-collection mode; add skip-list; configurable depth
- `components/navigation/nav.ps1` — primary path uses fzf; BFS best-match kept as fallback when fzf unavailable
- `COMPONENTS.md` — rename `Search-NestedProjects` → `Search-Projects`

**Not changing:**
- `components/navigation/bookmarks.ps1` — bookmark system untouched
- `Microsoft.PowerShell_profile.ps1` — bootloader load order untouched
- `components/core/dependencies.ps1` — fzf already in `$requiredTools`

## Chunks

### Chunk 1 — `Search-Projects` BFS rewrite (`projects.ps1`)
- Replace `Search-NestedProjects` with `Search-Projects`
- Add `[switch]$All` parameter
- `-All` mode: BFS collects every traversable directory as a relative path string for fzf
- Normal mode: BFS returns single best match (1=exact, 2=prefix, 3=contains; shallowest wins; exact returns immediately)
- Add skip-list: `node_modules`, `.git`, `dist`, `build`, `target`, `bin`, `obj`, `.next`, `.nuxt`, `__pycache__`, `.venv`, `venv`, `.cache`, `coverage`, `.turbo`, `out`
- Skip hidden dirs (names starting with `.`) in both modes

### Chunk 2 — `nav` fzf integration (`nav.ps1`)
- If `fzf` available: collect all candidates via `Search-Projects -All`, pipe to fzf with `--query $command --select-1 --exit-0`
- `--select-1` auto-navigates when only one match survives (seamless UX for unique names)
- `--exit-0` exits cleanly on no match; show "Cancelled" message
- If fzf unavailable: fall through to existing BFS best-match path

### Chunk 3 — `COMPONENTS.md` update
- Update the registry table: `Search-NestedProjects` → `Search-Projects`

### Chunk 4 — Log
- Create `docs/log/2026/May/19 Tue/log-2.md` (BFS rewrite) and `log-3.md` (fzf integration)

## Rollback

Revert `projects.ps1` and `nav.ps1` to pre-BFS state (restore `Search-NestedProjects`).
No persistent state affected — nav does not write to disk.

## Testing

1. `nav power` from any directory under `~/Code` → navigates to `powerflow` (4 levels deep)
2. `nav p` → fzf picker opens showing all dirs matching `p`; select one and navigate
3. With fzf uninstalled: `nav power` → falls back to BFS best-match, still navigates correctly
4. `nav nonexistent` → "Cancelled" or "No project matching..." message, no crash
5. `nav -verbose power` → shows search root and BFS traversal output
