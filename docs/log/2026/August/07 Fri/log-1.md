# Log 1 — August 7, 2026 — auditing another AI's release, then rebuilding nav (v4.2.0)

Two jobs in one session. The first was the one asked for; the second is what the first turned up.

**User:** *"we are about to make a new release, you need to test codex's new code."*
**User, later:** *"the purpose of powerflow is convenience, and to not make a user have to
remember 1000 flags unless they type `--show-native`."*

That second sentence became the standard everything got measured against, and it is now in
`docs/` and in my memory, because it explains most of what follows.

## The release that was not a release

`v4.1.0` was tagged, pushed, and **never published**. Its `validate` job was cancelled after 15
minutes — a job that normally takes 49 seconds — and everything downstream skipped. The latest
published release was still v4.0.0, so the pmx network layer had been stranded for a day with
nobody noticing.

This is the exact failure `docs/release-checklist.md` calls out twice: *"a pushed tag with failed
CI is not a release, and it fails silently."* It failed silently.

## Auditing Codex's work

The structural checks came back clean, and I want that on record because it is the honest result:
every `.ps1` parsed, all three suites passed, all 88 adapter functions referenced by components
existed on **both** platforms, and 31 `pmx help` topics all resolved. The monolith had been split
into 19 `components/proxmox/*` files — a real refactor, done properly. The mutation guards
re-validate identity *after* confirmation before executing, which is the correct pattern.

Then a seven-lens convenience review (72 agents, every finding adversarially refuted) found what
the structural checks could not, because none of it is a bug:

- **`ShowNative = $true` was the DEFAULT.** The flag whose entire purpose is "show native detail
  only when asked" was showing it to everyone, including `qm … --digest <sha1>`. A perfect
  inversion, invisible to any test that only asks "does it work".
- **`--help` errored on 15 paths.** Root cause was one line of ordering: in `vm-read.ps1` the
  help check sits *below* the parse-failure gate, so asking for help failed arity validation
  first. `network-read.ps1` has it the right way round, which is why `pmx vm network --help`
  worked and `pmx vm show --help` did not.
- **The teaching error was called at 1 of 17 sites.** `Write-PmxDisconnectedState` — which names
  the recovery command — was written, handled all three cases, and was wired to exactly one
  session-failure site. The other sixteen printed the bare fact. Most-hit error in the tool.
- **`pmx disk grow 101 50G` was rejected.** The parser demanded `50GB`/`50GiB`, case-sensitively.
  `50G` is what everyone types and what `qm resize` itself accepts.
- **11 pmx entries in `pwsh-h`** on machines with no Proxmox, where every one answers "not
  connected". The owner's fix was better than my planned capability-gate: *"there is pmx help
  that they can be migrated to."* Eleven became one.

Also: a real LAN address in a committed, pushed test fixture. One commit deep, no published
release carried it, fixed forward.

## Then nav, from the bottom up

**User:** *"nav <destination> works well in windows, but in linux … it doesn't work well."*

`nav downloads` on the Linux box answered *"No directories found in: /home/you"* while the thing
being looked for sat in `/srv/docker/downloads`. nav searched one root.

The redesign is named starting points — `nav -srv downloads`, `nav -pics screenshots` — plus
user-defined **anchors** (`nav --anchor . mon`). Three things are worth recording:

**nav had a `param()` block, so `-srv` could never reach the body.** PowerShell tried to bind it
as a parameter name, failed, and nav printed its help. This is the identical trap COMPONENTS.md
footnote 5 documents for `rm -rf`, and the reason `ls` has no param block. Hand-parsing `$args`
is the only way a PowerShell function can accept user-invented flags.

**My first resolver was unusable.** `Get-ChildItem -Recurse -Depth 4 -Force` descends into every
`node_modules`; it took *minutes* and timed out its own test run. `Search-Projects` already
prunes `node_modules/.git/dist/build/target`, so delegating to it took the same lookup to
**180 ms**. Reuse beat cleverness by three orders of magnitude.

**I built the wrong picker, and the owner caught it.** He pasted what `nav ai` already does —
every candidate in fzf, `126/171` narrowing as you type, arrows to choose — and my anchored path
pre-filtered and showed a dumb list with no query. Two different pickers in one command, which is
the exact inconsistency the redesign existed to remove. The fix deleted code: an anchor now
*scopes* the existing search instead of getting one of its own. Exactly one `fzf` invocation
remains in the file.

## The bug my own gates caught, twice

I used `$args` as a local — the automatic-variable class I added a CI gate for in v3.16.0. The
gate caught it immediately. Then my rename was **incomplete** (`$argv` assigned, `$args` still
passed) and the gate did *not* catch that, because it only flags assignments. Reading the file
caught it. I then deliberately re-broke it to prove the regression test had teeth: six failures.

Later, `$env:APPDATA` in a component — caught by the architecture gate.

Two gates I wrote catching me twice in one session is the best argument for them I could offer.

## The Windows folder trap

**User:** *"in windows, nav is useless for Docs, Pics, Downloads etc."*

He was right, and my first fix was wrong in a way that would have been worse than the original.
`Join-Path $home 'Documents'` is not where Documents is on a modern Windows install. Measured on
the real machine:

```
~\Pictures      does not exist          →  nav -pics silently unavailable
~\Documents     exists, but is a stub   →  nav -docs lands in the EMPTY one
MyDocuments     C:\Users\…\OneDrive\Documents     ← the live folder
```

OneDrive Known Folder Move redirects three of them. So `nav -docs` would not have failed loudly —
it would have *worked* and put the user in the wrong directory.

New adapter contract `Get-UserFolderPath` on both platforms. Windows reads the Known Folder
registry. Linux has the same trap wearing different clothes: XDG user dirs are relocatable and
**localised** (`~/Documentos`), so it uses `xdg-user-dir(1)` and falls back to parsing
`~/.config/user-dirs.dirs`.

And because some people deliberately keep files off OneDrive, it is a **preference**, not a fact:
`pwsh-config` → *User folders* → `auto`/`local`/`known`. Under `local` a missing folder returns
empty rather than silently falling back to the redirect — falling back would ignore the
preference just set — and offers to create it. Offered and confirmed, never automatic: it is a
real directory on someone's disk.

## What I got wrong, and was corrected on

- Proposed collapsing Docker's 18 subcommands to 5. **User:** *"I think 18 is better than 50 with
  flags etc."* Correct, and the reasoning is worth keeping: subcommands are *vocabulary*, flags
  are *grammar*. `dkr <tab>` shows you all 18; `--format <tab>` shows you nothing. My collapse
  would not have removed the actions, only their names — making them less discoverable and
  impossible to script or tab-complete.
- Called `pmx disk`'s virtual/physical overlap a **hazard**. It is not: `pmx disk 101` stops at
  the Proxmox-host gate and the destructive path needs `capacity-test` + `-Destroy` + a typed
  phrase. Overstated, corrected.
- Sat on blocking `TaskOutput` polls waiting for background work. **User:** *"you seem stuck in
  thought, hence the interruption."* Now in memory.

## Verified

170 assertions across nine new suites, plus the three repo suites and every gate: architecture,
automatic variables, help registry (134 commands), adapter parity (**0 of 89** unchecked, after
adding `Get-PowerFlowDataPath` and `Get-UserFolderPath` to the hand-maintained CI regex), and a
whole-tree privacy sweep.
