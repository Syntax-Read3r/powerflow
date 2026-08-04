# Log 3 — August 4, 2026 — verifying Codex's code, and what "45 assertions green" was worth (v3.16.0)

**User:** "we are about to make a new release, you need to test codex's new code. im sure it may
be impossible to do so on some scripts, so you just have to verify them that they are doing
what they claim to do."

I had already reported Proxmox v2 as "complete and green — 45 assertions." That was true and
almost worthless. Those 45 assertions covered the **evidence layer I wrote** plus static
checks. Not one of them executed Codex's parsers, because the parsers "only run on a Proxmox
node" — and I had accepted that as a reason not to run them.

That premise was wrong, in two places.

## The component layer was always executable

PowerFlow's architecture rule says `components/` never touches an OS API. That is not just a
portability rule — it means **the entire 626-line component layer is testable anywhere**, if
you supply the adapter contract. I faked the fourteen adapter functions and ran the real
renderers and dispatcher on Windows: 95 assertions covering normal data, empty data, all-null
fields, single-element array collapse, every selector form, every documented verb, and the
destructive path with a probe stub that records its arguments instead of touching a disk.

## The adapter was executable too, which I had not expected

The Linux adapter reaches the OS through `& smartctl` and `& lsblk`. PowerShell resolves a
bare command name to a **function** before a native binary — so defining functions with those
names runs Codex's real parsing bodies against recorded output. Fixtures came from
`docs/proxmox.md`: model `SSD 4TB`, serial `003134`, firmware `VA001CBN`, all-zero WWN.

68 more assertions. And the first run **hung**.

## Two total failures, both fatal, both invisible to static checks

**`Get-PmxStableIds` did `$matches = @()`** and then ran `-match` inside its loop. `$matches`
is an automatic variable that every `-match` overwrites with a Hashtable, so the next
`$matches += $path` threw *"A hash table can only be added to another hash table"*. I proved
it with a faithful reproduction of a real `/dev/disk/by-id` listing, then traced the blast
radius: it aborts `Get-ProxmoxDisks`, and therefore `pmx`, `pmx disks`, `pmx disk <x>` — the
whole subsystem — on any host with a partitioned boot disk. Which is all of them.

The bitter part: I had fixed this exact bug class twice already in the *component*
(`Resolve-PmxDisk`, `Show-PmxGuests`) and written a comment about it. I never scanned the
adapter.

**`Get-PmxBlockDescendants` recursed forever.** That was the hang. `lsblk` omits `"children"`
for every leaf, and `@($null)` is a **one**-element array containing `$null`, not an empty
one — so the loop ran once with `$child = $null` and recursed on `$null` until PowerShell's
call-depth overflow. Note that the same file gets this right eleven lines later
(`if ($child) { $queue.Enqueue($child) }`), so it was an inconsistency, not ignorance.

## Then a five-lens audit, adversarially checked

44 agents across external-command correctness, claims-versus-behaviour, renderers, the
destructive path, and the `ls` fix — every finding then given to a separate agent whose job
was to **refute** it. 38 findings, 29 survived, 9 refuted. Two reported as release-blocking
were refuted on re-check against upstream source: f3probe really does return
`100 + fake_type`, so the exit mapping is right, and util-linux really does emit
`{"signatures":[]}` for a clean disk, so the signature check does not false-fail.

Four more real ones, each of which I re-verified myself before touching anything:

- **`Capacity testblocked`** on every disk view. `{0,-12}` is a *minimum* width; .NET never
  truncates; the one 13-character label got no separator.
- **The prompt documented the wrong token** — "typed serial confirmation" in two places, while
  the gate demands `DESTROY <by-id leaf>`, with the serial printed two lines above it.
- **Enter threw a raw exception.** `Read-Host` returns `''`; `[Parameter(Mandatory)][string]`
  refuses it. The most likely abort produced a stack trace instead of "cancelled".
- **`-cne` is culture-sensitive.** I tested three zero-width characters: all three make a
  pasted phrase compare **equal** to the real one. Ordinal rejects all three. It cannot select
  a *different* disk, so it is hardening rather than a wrong-disk risk — but it is the last
  gate before `f3probe --destructive`, and it is one line.

## What I changed about the process, not just the code

Two new CI gates, because finding these by hand twice is not a strategy:

1. **No automatic variable used as a local.** This class has now produced four bugs here
   (`$matches` ×3, my own `$Pid` in team-room). Reading `$matches` after a `-match` stays
   legal; assigning to the name does not. Verified to catch all four historical cases and to
   fire zero false positives on the tree. Two pre-existing `$input = Read-Host` locals were
   renamed so the gate could be strict.
2. **The adapter parsers run against recorded tool output in CI**, using the same shim trick.
   Both fatal bugs are pinned by name. `f3probe` is never defined in that step.

## The honest summary

383 assertions now pass across seven suites. Before today, the number was 45 and the
subsystem did not work at all. The lesson is not "test more" — it is that **"this can only run
in production" was a claim I should have checked rather than inherited.** A ports-and-adapters
codebase is, by construction, mostly runnable off-target; that is half the point of the
architecture, and I had been treating it as a deployment detail.
