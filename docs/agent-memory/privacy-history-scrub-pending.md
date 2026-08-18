---
name: privacy-history-scrub-pending
description: "Real username and the owner's home subnet subnet still live in pushed git history from two separate incidents; a rewrite is an open, owner-decided follow-up"
metadata: 
  node_type: memory
  type: project
  originSessionId: <archived>
  modified: 2026-08-18T09:35:29.524Z
---

PowerFlow's git history still carries the owner's real username and home subnet in
**two** places, both already pushed to GitHub:

1. **Pre-v3.9.0 blobs** — v3.9.0 scrubbed the username from the working tree, but older
   commits keep it.
2. **`a278bb8` (2026-08-18)** — the round-2 backlog was committed as pasted and carried 27
   instances of `the owner's home subnet` and 14 of the username. The working tree was scrubbed in
   `023a4c9`, but that commit's blob is public.

**Why:** removing these needs a history rewrite (`git filter-repo` + force push), which
breaks every existing clone and rewrites published commit SHAs. That is destructive and
outward-facing, so it is the owner's decision — not something to do as a side effect of a
release.

**How to apply:** do not rewrite history unless the owner explicitly asks. Do keep the
*working tree* clean: run release-checklist item 4 (the IP grep, plus a the username grep) before
every cut. The a278bb8 leak was caught by that item one commit late — the grep works, it just
has to run before the commit that introduces the data, not before the release that follows
it. When pasting an owner-supplied report into the repo, scrub it in the same commit that
adds it. See [[surface-existing-mechanisms-before-building]] for the related habit of
checking what already exists before acting.
