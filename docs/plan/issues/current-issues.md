# Current Issues

## Issue 3 — Release notes are not attached to GitHub releases

**File:** `.github/workflows/release-publish.yml`
**Severity:** Medium
**Description:** The mandatory release checklist requires `RELEASE_NOTES.md` as a downloadable
asset, and the generation workflow includes it in the release artifact, but the publish
workflow uses it only as the release body. Published releases therefore omit a required asset.

**Status:** Open

## Issue 4 — README understates what `git-rl` commits

**File:** `README.md`
**Severity:** Medium
**Description:** The release guide says `git-rl` commits staged changes, while the function
runs `git add .` and stages the entire working tree. Following the documentation can therefore
include unrelated modified or untracked files in a release commit.

**Status:** Open

## Issue 5 — Proxmox disk-use checks do not inspect descendant device identities

**File:** `platform/linux/adapters/proxmox.ps1`
**Severity:** Medium
**Description:** Mount-namespace and open-handle checks currently inspect only the selected
whole disk's major:minor identity. A child partition or mapped descendant can therefore be
missing from those diagnostic checks. The present capacity probe still refuses any partition,
but shared disk-idle checks must cover descendants before they can safely support another
destructive disk workflow.

**Status:** Open

---

## Resolved

### Issue 2 — PowerFlow `ls` decoration breaks end-anchored Linux pipelines

**File:** `components/files/listing.ps1`
**Severity:** Medium
**Description:** PowerFlow forces `lsd` colour and icons even when output is piped. The trailing
ANSI reset bytes make an expression such as `ls -l /dev/disk/by-id | grep -E 'sdg$'` return no
match, although the same pipeline works with GNU `ls` in Bash.

**Status:** Fixed in v3.16.0. Both `lsd` invocations (tree view and normal listing) now pass
`--icon=auto --color=auto`, so lsd detects the destination itself: full decoration at an
interactive prompt, plain text into a pipe or a file.

**Why it was hard to see:** the listing *looked* correct. The contamination was an invisible
ANSI reset appended after the filename, so only a pipeline that anchors on the end of the line
could notice — and it failed by finding nothing, which reads as "no such entry" rather than
as a bug.

**Regression test:** `release-validate-linux.yml` → *"PowerFlow ls stays pipeline-safe"*. It
lists a **directory**, deliberately: lsd colours directory names and appends the reset after
them, so the test genuinely fails against the old behaviour.
