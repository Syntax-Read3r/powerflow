---
name: surface-existing-mechanisms-before-building
description: "Before implementing a fix the owner sketched, surface any existing mechanism that already covers it — and never make a bare command write files on an unconfirmed assumption"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: <archived>
  modified: 2026-08-14T16:18:35.517Z
---

While fixing PF-UX-005 (`git-rl` saying "Release cancelled" in an un-set-up project), the owner
said "paste the walkthrough into that project or pwd". I implemented that literally — bare
`git-rl` auto-wrote `docs/git-release-help.md` into whatever repo the user stood in — even
though I had read `git-rl -h` minutes earlier and knew it already delivered that exact guide
*after asking "are you in your project folder?"*. The owner's correction: "you should have told
me git-rl -h was active. Then we would have just told the user to run git-rl -h instead of
assuming the user is in a repo."

**Why:** The owner sketches intent, not implementation. When an existing mechanism already
covers the sketched behaviour, they want that surfaced *before* code is written — the decision
between "point at the existing flow" and "build a new path" is theirs, and it is cheap to ask at
design time and expensive after. Separately: writing files into a repo as the side effect of
what amounts to a status query assumes the current repo is the intended target; a clone or
scratch checkout breaks that assumption. Confirmation-before-write lived in `git-rl -h` on
purpose.

**How to apply:** When the owner proposes behaviour, grep for an existing command/function that
already does it and name it in the reply before implementing ("X already does this and asks
first — point at it, or build the inline version?"). Default bare commands to *reporting and
pointing*; keep anything that creates or mutates files behind a flow that confirms intent.
Related: [[powerflow-creed-convenience]] — convenience means the bare command does the useful
thing, and the useful thing for an unconfigured state is an honest signpost, not a side effect.
