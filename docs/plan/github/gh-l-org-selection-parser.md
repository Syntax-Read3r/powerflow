# Plan — Fix `gh-l-org` Organisation Selection Parsing

> **Status: Implemented** — Approved and completed 2026-05-25.

## Goal

Make `gh-l-org` reliably extract the selected organisation login from the fzf picker regardless of emoji rendering, terminal encoding, ANSI handling, or organisation description text.

## Root Cause

`components/github/browser.ps1` formats organisation picker rows like:

```powershell
"🏢 {0,-30}  {1}" -f $_.login, $desc
```

Then parses the fzf result with:

```powershell
if ($orgSelection -match '🏢\s+(\S+)') {
    $selectedOrg = $Matches[1].Trim()
}
```

This couples data extraction to a decorative emoji. A local regex check confirms the parser works only when the literal emoji survives unchanged. The user's failure after selecting a valid organisation means the fzf-returned line did not match that exact decorated prefix.

## Scope

**Changing:**
- `components/github/browser.ps1` — replace emoji-dependent org parsing with stable parsing.
- `docs/plan/issues/current-issues.md` / `resolved-issues.md` — move the issue after implementation.
- `docs/log/2026/May/25 Mon/log-2.md` — record implementation work.

**Not changing:**
- Token retrieval and storage.
- GitHub API endpoints.
- Repo picker layout and clone actions, except if a small shared parsing helper is useful.
- Public command name or parameters.

## Chunks

### Chunk 1 — Stable org picker rows

Use a tab-delimited hidden data column or an object lookup instead of parsing from an emoji prefix.

Preferred implementation:

```powershell
$orgChoices = $orgs | ForEach-Object {
    $desc = if ($_.description) { $_.description } else { "no description" }
    "$($_.login)`t🏢 $($_.login.PadRight(30))  $desc"
}

$orgSelection = $orgChoices | fzf --with-nth=2.. ...

$selectedOrg = ($orgSelection -split "`t", 2)[0].Trim()
```

This keeps the UI readable while making the returned login independent of emoji rendering.

### Chunk 2 — Validate selected org

After parsing, verify the login is non-empty and exists in `$orgs.login`. If parsing fails, print the raw returned selection in a debug-friendly message so future parser failures are diagnosable.

### Chunk 3 — Regression test notes

Add a small manual test checklist to the implementation log:
- `gh-l-org` with no argument opens org picker and selecting an org proceeds to repo fetch.
- `gh-l-org <org>` still bypasses the picker.
- Selection still works if the display prefix is removed or changed.
- Organisation descriptions containing spaces do not affect parsing.

### Chunk 4 — Issue bookkeeping and log

Move Issue 1 from `current-issues.md` to `resolved-issues.md` with a resolved status once the code fix is applied. Create the required daily log entry for the fix.

## Rollback

Revert `components/github/browser.ps1` to the previous parser block. No external state is changed by the parser fix.

## Testing

1. Reload the profile.
2. Run `gh-l-org`.
3. Select an organisation from fzf.
4. Confirm it prints `Organisation: <org>` and proceeds to repository fetching.
5. Run `gh-l-org <org>` and confirm direct argument mode still works.

Plan is ready — awaiting your approval to proceed.
