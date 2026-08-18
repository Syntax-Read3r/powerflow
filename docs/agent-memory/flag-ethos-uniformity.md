---
name: flag-ethos-uniformity
description: "Flag style across PowerFlow is inconsistent by the owner's own admission; an ethos doc is being designed from an audit, so don't add new commands in an arbitrary style"
metadata: 
  node_type: memory
  type: project
  originSessionId: <archived>
  modified: 2026-08-08T08:35:43.260Z
---

On 2026-08-08 the owner called flag style a **major** problem in PowerFlow, in their words:

> "so far my powerflow commands have been written on my whims and there is no uniformity,
> i.e. --flag and -flag and flag. this can easily confuse a user, we should use one flag
> type. find all non uniform writing and log them so that we design the ethos doc around them"

An audit was commissioned to **log** the non-uniformity, not fix it — the convention is the
owner's decision to make. Output goes to `docs/plan/ethos/flag-uniformity-audit.md`.

**Why:** the surface already mixes four mechanically different token kinds — `param()`
switches (which PowerShell also reaches by case variants and unambiguous *prefixes*),
hand-parsed `$args` strings, bare subcommands, and positionals. `pwsh-h` alone declares
`[switch]$a, [switch]$advanced, [switch]$all`. Every new command added before the ethos
exists makes the eventual migration bigger.

**How to apply:** when adding a user-facing command, do not invent a flag style. Match the
nearest existing command in the same domain, and say in the summary that the choice is
provisional pending the ethos doc. The real tension to respect: `-word` is *native* to
PowerShell via `param()`, but reads as clustered short flags to anyone with Unix instincts —
whichever rule wins violates one of those, so don't quietly pick a side.

Constraints any rule must survive, already deliberate in the tree: `ls -r` is **not**
aliased to recurse because GNU uses it for reverse-sort; coreutils are never shadowed on
Linux (see [[powerflow-creed-convenience]]); `--show-native` is deliberately long-form.

Related: [[powerflow-creed-convenience]] — the "never make users memorise flags" creed is
what makes this worth doing at all.
