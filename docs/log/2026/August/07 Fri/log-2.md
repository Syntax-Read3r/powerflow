# Log 2 — August 7, 2026 — finishing the convenience review (v4.3.0)

v4.2.0 shipped the first half of the seven-lens convenience review. This is the rest of it,
worked with the owner's *"you have free autonomy, complete the work"*.

Every item had already been adversarially verified — a second agent whose job was to refute it
against the real code — so the work here was implementation, not judgement. Which is the point
of verifying first: nothing below needed re-litigating.

## The picker that existed but was wired to one noun

Thirteen VM-taking commands answered a missing name with a usage line:

```
❯ pmx vm show
❌ supply one VM name or VMID after the action
```

…while `Resolve-PmxDisk -Interactive` — a working fzf picker — sat forty lines away, wired to
physical disks only. `pmx disk` opened a picker; `pmx vm show` did not.

The fix went into **`Resolve-PmxManagedVm`**, not into thirteen call sites. An empty selector now
opens a picker showing VMID, name, status and node. Every caller gained it at once, and there is
one implementation to keep correct rather than thirteen.

Two things had to hold, and were tested for:

- **Safety is untouched.** Whatever is picked still goes through validate → confirm → revalidate
  → verify, and `Confirm-PmxAmberPlan` already refuses non-interactive sessions.
- **It must never hang.** Guarded on `[Console]::IsOutputRedirected` and on fzf being present,
  falling back to a message that names what it needs.

The parser change that fed it is worth recording: `RequireSelector` used to treat *absent* and
*ambiguous* as the same error. They are not. Supplying **both** `--vm` and a positional is
genuinely ambiguous and still refuses; supplying **neither** is merely unspecified, and that is
what a picker is for.

## Clone: four flags, three names, and one magic word

```
pmx vm clone --source debian-base --new-vmid auto --name docker-host --full --dry-run
```

The most common Proxmox task had the worst ergonomics in pmx. Worse, two of those tokens were
fiction:

- **`--full` never did anything.** Registered as a switch, read nowhere, and the clone call
  hardcodes `Full = $true`. It was advertised in every syntax line, the example, and the
  overview.
- **`--new-vmid auto`** — `auto` was the *only* value the system accepted (`config.ps1` rejected
  anything else), so the user was required to type the only possible answer.

Now `pmx vm clone debian-base docker-host`. The VMID resolves automatically and the amber
preview prints it before confirmation, so nothing became invisible. Older forms all still work;
`--full` is still accepted so no script breaks, just no longer advertised as a choice.

While there: **`vmid-policy` and `clone-mode` were dead configuration** — never read outside
`config.ps1`, each accepting exactly one value, yet `pmx config set` advertised "clone mode" as
something you could change. Removed. A saved `pmx.json` carrying them is ignored rather than
rejected, because `Get-PmxConfig` only reads keys present in the defaults.

## A pre-existing crash found by looking

`pmx vm net` with no VM threw:

```
Cannot bind argument to parameter 'Arguments' because it is an empty array.
```

A raw .NET binding failure, before any parsing, because the parameter was `Mandatory` with no
default. It looked like something I had broken — it was not; the binding fails before my parser
change could run. Fixed with a default, and bare `pmx vm net` now lists the fleet, mirroring
bare `pmx vm`. Erroring there taught the opposite of what the level above does.

## The small one that matters

`pmx vm list` ended in silence. `srv` and `pc-whoami` both end by naming what to do next, so the
user never has to go back to help for the obvious follow-up. It now ends:

```
  pmx vm show <name>  ·  pmx vm ip <name>  ·  pmx snapshot list <name>
```

## One test had to change, and that was correct

`tests/proxmox/help-surface.ps1` asserts that every routed command appears in the overview with
its exact syntax string. Changing clone's advertised form broke it — which is the test doing its
job. Updated with a comment explaining why the string changed, rather than loosened.

## Verified

221 assertions across twelve suites plus the three repo suites and every gate: architecture,
automatic-variable shadowing, help registry, adapter parity, and the privacy sweep.
