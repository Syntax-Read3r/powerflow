---
name: ci-parity-regex-is-hardcoded
description: "SUPERSEDED 2026-08-18 — the adapter-parity gate is now derived, not a hand-kept list. Kept because the reasoning that forced the rewrite still applies to other gates."
metadata: 
  node_type: memory
  type: project
  originSessionId: <archived>
  modified: 2026-08-18T12:38:29.434Z
---

**This is no longer true, and the correction is the point.**

Until 2026-08-18, `release-validate.yml`'s "Verify Adapter Contract Parity" step matched a
**hardcoded alternation of contract names**. A new adapter function absent from that list
passed CI on one platform and exploded at runtime on the other. Two container functions
shipped uncovered exactly that way.

**It is now derived.** The gate computes the contract as *the set of adapter-defined
functions that `components/` actually calls*, and additionally fails on any Verb-Noun call
that resolves nowhere. Nothing to update by hand when adding an adapter function.

**Why this note survives its own obsolescence:** the release checklist item that guarded the
old gate said, in as many words, that the list was manual and had to be maintained. It was
still missed. **A rule that depends on remembering is a rule that eventually fails** — that
is what justified rewriting the gate to derive its own inputs, and it applies to every other
gate in this repo. When you find yourself writing "remember to also add it to X", change X
so it does not need remembering.

Related: [[project-architecture]], [[adapters-make-code-runnable-off-target]]
