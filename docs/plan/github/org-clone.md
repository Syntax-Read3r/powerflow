# Plan — GitHub Organisation Browser & Bulk Clone (`gh-l-org`)

> **Status: Implemented** — Approved and completed 2026-05-24.

## Goal

Add `gh-l-org` to `components/github/browser.ps1` so users can list their GitHub
organisations, browse an org's repos in a fzf picker (matching `gh-l`'s column
layout), and either clone a single repo or bulk-clone the entire org into a local
folder named after the organisation.

---

## Scope

**Changing:**
- `components/github/browser.ps1` — extract shared token helpers to module level;
  add `gh-l-org` function
- `components/help/menu.ps1` — add `gh-l-org` entry in the 🐙 GITHUB INTEGRATION
  subsection
- `COMPONENTS.md` — append `gh-l-org` to the Functions column for `browser.ps1`
- `docs/log/2026/May/24 Sun/log-1.md` — session log (planning)

**Not changing:**
- `gh-l`, `gh-l-reset`, `gh-l-status` — behaviour unchanged; only the three inner
  helpers are lifted out of `gh-l`'s body
- Auth mechanism — same Windows Credential Manager token, same prompt/save flow
- fzf column layout — `gh-l-org`'s repo picker will match `gh-l` exactly

**Interface decision — separate function, not a switch on `gh-l`:**
A `-Organisation` switch on `gh-l` would conflate two distinct workflows in one
function and complicate the signature. A dedicated `gh-l-org` is consistent with
the existing pattern (`gh-l-reset`, `gh-l-status`) and is easier to document and
discover in `pwsh-h`.

---

## Chunks

### Chunk 1 — Extract shared token helpers (`browser.ps1`)

Move the three functions currently nested inside `gh-l` to module level, above the
`gh-l` definition. Rename with an `_GhL` prefix to mark them as internal helpers:

| Old (nested inside `gh-l`) | New (module level)     |
|----------------------------|------------------------|
| `Set-GitHubToken`          | `_GhL-SetToken`        |
| `Get-GitHubToken`          | `_GhL-GetToken`        |
| `Get-CommitCount`          | `_GhL-CommitCount`     |

Update the three call sites inside `gh-l` to use the new names. No behaviour change.

> **Why extract:** `gh-l-org` needs identical token retrieval and commit-count logic.
> Leaving them nested would force duplication and create two diverging copies.

---

### Chunk 2 — Add `gh-l-org` function (`browser.ps1`)

New function placed after `gh-l-status`. Signature:

```powershell
function gh-l-org {
    param (
        [string]$Org,       # optional: skip org picker if supplied
        [int]$Count = 100   # max repos to fetch from the org
    )
```

**Workflow:**

**Step 1 — Authenticate**
Call `_GhL-GetToken` (same flow as `gh-l`; prompts and offers to save if missing).

**Step 2 — Fetch user's organisations**
```
GET https://api.github.com/user/orgs?per_page=100
```
Returns orgs the authenticated user belongs to (member or owner). Each entry
has `login`, `description`, `public_repos`.

If `$Org` was supplied as a parameter, skip the picker and go straight to Step 4.

**Step 3 — Org picker (fzf)**
Display one line per org:
```
🏢 <login>   <description>   (N public repos)
```
User selects one; `$selectedOrg = <login>`.

**Step 4 — Fetch org repos**
```
GET https://api.github.com/orgs/{org}/repos?type=all&per_page=100&page=N
```
Paginate until all repos are fetched. Sort by `pushed_at` descending, take
`$Count`. `type=all` returns public + private repos (requires token with
`read:org` scope for private ones).

**Token scope warning:** if the endpoint returns 403, show:
```
⚠️ Token may lack 'read:org' scope — showing public repos only.
Regenerate at https://github.com/settings/tokens with read:org checked.
```
Then retry with `type=public`.

**Step 5 — Repo picker (fzf)**
Identical column layout to `gh-l`:
```
🔒/🌐  <name>   📅<last-push>   📊24h:<N>   📈1w:<N>   💻<language>
```
Header line matches `gh-l`'s header string.

**Step 6 — Action menu**
After selection:
```
1. Clone selected repo
2. Clone ALL repos in org  (⚠️  N repos — creates .\<orgName>\ folder)
3. Open selected repo in browser
4. Copy HTTPS URL
5. Copy SSH URL
```

**Clone-all flow (option 2):**
```powershell
$confirm = Read-Host "Clone all $($orgRepos.Count) repos into .\$selectedOrg\? (y/n)"
if ($confirm -eq 'y') {
    New-Item -ItemType Directory -Path $selectedOrg -ErrorAction SilentlyContinue | Out-Null
    Push-Location $selectedOrg
    foreach ($r in $orgRepos) {
        Write-Host "  Cloning $($r.name)..." -ForegroundColor DarkGray
        git clone $r.clone_url
    }
    Pop-Location
    Write-Host "✅ Cloned $($orgRepos.Count) repos into .\$selectedOrg\" -ForegroundColor Green
}
```

Use `Push-Location`/`Pop-Location` (PowerShell idiom) instead of `cd` so the
caller's directory is restored if anything throws.

---

### Chunk 3 — Update `components/help/menu.ps1`

Add one line to the `🐙 GITHUB INTEGRATION` block (after `gh-l-status`):

```
│  gh-l-org [org]      → 🏢 browse org repos; clone one or all                  │
```

---

### Chunk 4 — Update `COMPONENTS.md`

Append `gh-l-org` to the Functions column of the `components/github/browser.ps1`
row:

```
`components/github/browser.ps1` | GitHub | `gh-l`, `gh-l-reset`, `gh-l-status`, `gh-l-org`
```

---

## Rollback

All changes are additive except Chunk 1 (token-helper extraction). If the
extraction breaks `gh-l`, restore with:

```powershell
git checkout HEAD -- components/github/browser.ps1
```

No persistent state, config files, or external systems are affected.

---

## Testing

1. `gh-l-org` with no args → uses saved token (or prompts), shows org fzf picker
2. Select an org → repo picker appears with same columns as `gh-l`
3. Action 1 (clone single) → repo cloned in CWD
4. Action 2 (clone all) → `<orgName>/` folder created, all repos cloned inside it,
   CWD restored to where user started
5. `gh-l-org myorg` (positional) → skips org picker, goes straight to repo picker
6. Token with only `repo` scope (no `read:org`) → warning shown, public repos still
   listed
7. `gh-l` still works identically after Chunk 1 extraction
8. `pwsh-h` shows `gh-l-org` in the GITHUB INTEGRATION section
