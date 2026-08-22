# TODO — the working list

**This file is the continuity mechanism.** A session todo list is local: it dies with the
session, and it died with the machine reset. This one is committed, so the answer to "where
were we" is a file rather than a memory.

**Rules for keeping it honest**

- Strike an item out only when its evidence exists on disk — a test, a command, a shipped
  file. Status here is *verified against the tree*, never trusted from a report.
- When you strike something out, say **what proves it**. "Done" with nothing after it is how
  a list starts lying.
- New work goes at the bottom of its section unless the owner says otherwise.

Last verified against the tree: **2026-08-19**.

---

## 1 · Round 2 backlog — 5 of 16 closed

Source: [powerflow_backlog(2).md](<powerflow_backlog(2).md>). IDs are the **(b2)** numbering —
round 1 reuses the same numbers for different work, so a bare `PF-FEAT-001` is ambiguous.

### Closed

- [x] ~~**PF-UX-002** — picker cancellation is not an error~~
      Escape now reads `↩ Cancelled.`, dim, at the shared boundary. Both pickers fixed.
      *Proof:* `tests/proxmox/picker-cancellation.ps1`
- [x] ~~**PF-UX-001** — `pmx list` / `pmx status` aliases and typo suggestions~~
      Suggestions derived from the help catalogue rather than a second list, prefix-first,
      bounded to 3, only ever printed. *Proof:* `tests/proxmox/route-suggestions.ps1`
- [x] ~~**PF-FEAT-008** — top-level PMX fleet network + SSH status~~
      Seven SSH states, never flattened; probes only agent-reported addresses and never
      scans. *Proof:* `tests/proxmox/fleet-network-status.ps1`
- [x] ~~**PF-UX-003** — restore word navigation, deletion and selection~~
      The real defect was Emacs mode (the Linux default) leaving five chords unbound.
      Filled additively; `pwsh-keys` reports who bound what.
      *Proof:* `tests/shell/editing-keys.ps1`
- [x] ~~**PF-FEAT-005** — refined `pman logs` + readable inspection~~ *(mostly)*
      Timestamps, 30-line default, conservative tidying, `--raw`/`-a`/`--tail`,
      `pman inspect`/`show`. *Proof:* `tests/containers/log-view.ps1`
      **Deferred half is still open — see PF-FEAT-004 below.**

### Open — the eleven large ones

| ID (b2) | What | Blocked on |
|---|---|---|
| **PF-FEAT-004** | `pman events` human time ranges (`t@HH:MM`, `yd@`) | nothing — **highest leverage left** |
| PF-FEAT-002 | reboot/stop/reset, snapshot rollback/delete, suspend/resume, migrate, disk move | `Invoke-PmxVmLifecycleChange` is fenced by `[ValidateSet('start','shutdown')]`; needs adapter ops both platforms |
| PF-FEAT-001 | guarded VM destroy / `--purge` | **four owner decisions — listed below** |
| PF-FEAT-006 | `journal` — Linux timeline over `journalctl` | largely net-new |
| PF-FEAT-007 | `pman service` — Quadlet + rootless persistence | net-new; mutating, needs guarded-preview treatment |
| PF-FEAT-011 | `network dns` — status, split-DNS enrol, test, undo | net-new; `nmcli`/`resolvectl` appear nowhere |
| PF-FEAT-012 | `network`/`nw`, `svc`, `sys` namespaces | ~35 subcommands — biggest single surface in the file |
| PF-FEAT-013 | fill those namespaces | depends on 012; ~¼ already shipped under other names |
| PF-FEAT-003 | `server setup` — guided clone → identity → srv → role | Phase 1 already shipped as round 1's PF-FEAT-003 (v5.0.0) |
| PF-FEAT-010 | DNS server role inside `server setup` | depends on 003 **and** 011 |
| PF-FEAT-009 | PMX SSH connection/session telemetry | lowest value for the size; needs a guest-exec path that does not exist |

**PF-FEAT-004 first.** Its time-range grammar is the shared parser PF-FEAT-005's deferred
half is waiting on, so it unblocks two items.

#### The four decisions PF-FEAT-001 (destroy) needs before it can be built

1. **The grammar does not exist.** `pmx vm 103 destroy` answers *"Unknown VM action '103'"*.
   Object-first is a router-wide change across ~20 subcommands; action-first
   (`pmx vm destroy 103`) needs no change at all. **Which?**
2. **"No picker" contradicts a written house rule.** `Resolve-PmxManagedVm` opens a picker on
   an empty selector *by design*, and its own comment calls refusing-where-a-picker-would-do
   the house anti-pattern. Destroy wants the opposite. **Deliberate exception?**
3. **There is no RED confirmation primitive.** `Confirm-PmxAmberPlan` is hardwired to `[y/N]`.
   Typing the VM name back needs a new primitive or a `-Confirm` scriptblock.
4. **The disk preview would UNDER-REPORT.** `Get-PmxVirtualDisksFromConfig` matches only
   `^(ide|sata|scsi|virtio)\d+$`, so `efidisk0`, `tpmstate0` and `unused0..N` are invisible —
   and the backlog's own example preview lists `efidisk0`. A destroy preview that understates
   what it deletes is wrong in the one direction it must never be wrong.

---

## 2 · Storage allocation — a separate initiative, not in either backlog

Started 2026-08-19 from the owner's ask: *use a second drive when there is one, and allocate
properly even when there is not, instead of memory growing in unknown locations.*
Design: [../file system upgrade/storage-allocation-design.md](<../file system upgrade/storage-allocation-design.md>).

### Closed

- [x] ~~**Increment 0** — PowerFlow stops overwriting a relocated Scoop root~~
      `config/paths.windows.ps1` *assigned* `$env:SCOOP` behind a substring guard; 3 of 4
      measured cases were wrong. *Proof:* `tests/windows/scoop-root-resolution.ps1` (`c31d1dc`)
- [x] ~~**Increment 2** — one Scoop resolver, reading `root_path`~~
      Scoop records its root in its own config, not a variable; four sites read only the
      variable and one hardcoded `~\scoop`. `Get-PackageManagerRoot` on both platforms
      (Linux returns `$null` — a distro package manager has no relocatable root). (`dc5ad9e`)
- [x] ~~**Increment 3a** — multi-alias anchors + `nav setup`~~
      One anchor answers to several names; the folder names itself; `nav setup` finds the
      code drive and offers *both* the anchor and the search root.
      *Proof:* `tests/navigation/anchors.ps1` (`020f3c9`)
- [x] ~~**Increment 3b** — `storage root`, read-only verifier~~
      Which volume could hold what grows and why the others could not, plus what is still on
      the system drive and what would move it. *Proof:* `tests/storage/root-report.ps1` (`f330873`)
- [x] ~~One classifier, not two~~ — `nav setup` and `storage root` shared eligibility logic
      collapsed into `components/shared/volumes.ps1` (`3817678`)

### Open

- [ ] **Increment 5 — installer placement.** Set **process-scope** `$env:SCOOP` before the
      Scoop bootstrap so a fresh install lands correctly, and **never persist a User-scope
      `SCOOP`** — the upstream installer writes `root_path` only when no such variable
      exists. This is a **major** version bump: it changes the install destination.
- [ ] **Increment 6 — dev-environment provisioning** (Claude Code, Codex, podman, VS Code).
      Detect-first, opt-in, never under `-Yes` — **owner decided: needs an explicit
      `--with-devtools`** (~640 MB of binaries must never land on a CI runner).
      Needs a new adapter contract, `Set-PersistentEnvironmentVariable`, on both platforms:
      the `env.ps1` adapter is PATH-only today, and `SetEnvironmentVariable` is a forbidden
      token in `components/`. `winget` is forbidden there too, so the install belongs in
      `platform/windows/adapters/packages.ps1` — and Linux needs an honest counterpart.
- [ ] **Answer the design doc's seven open questions** (§10) before increment 5. The two that
      actually gate work: the command name (`storage root` vs `storage home`/`where`), and
      whether Linux should relocate by default or only detect-and-advise.
- [x] ~~**Live upgrade bug fixed:** an upgrade no longer undoes settings the user changed.~~
      `install.ps1` replaces `config/` wholesale, and `pwsh-reminders` persists the user''s
      answer *into that very file*. Changed values are now carried across, with the names
      derived from both files rather than hand-listed, and `POWERFLOW_VERSION` explicitly
      release-owned. *Proof:* `tests/windows/install-settings-preserved.ps1`

---

## 2b · Outcome messaging

Arrived from real use, 2026-08-19: `nav zovoya` (a typo for `zavoya`) answered
**`❌ Cancelled`** — a cancellation the user never made, in a marker reserved for errors.

- [x] ~~**`nav` separates its three outcomes**~~
      fzf exits 0 on selection, **1 when nothing matched**, **130 on Escape**. `nav` tested
      only whether the result string was empty, so two opposite outcomes reached one branch
      and it printed the message written for the other. Escape now gives the house
      `↩ Cancelled.`; a miss says what missed and names the nearest real directory.
      *Proof:* `tests/navigation/outcomes.ps1`
- [ ] **Wire `outcomes.ps1` into `tests/navigation/run.ps1`.** One line. Deferred only
      because that file has uncommitted changes from a concurrent session.
- [ ] **Audit the rest of the command surface for the same defect class** — conflation
      (distinct outcomes sharing a message), misleading text, wrong severity marker. Audit
      running; findings to land in `outcome-messaging-audit.md`.

---

## 3 · Repository hygiene

- [x] ~~**Strip `Co-Authored-By: Claude` trailers**~~ — five commits, rewritten in a throwaway
      clone (the working tree was dirty with a concurrent session's work, which `filter-branch`
      refuses and which must not be stashed) then applied with `git reset --soft`, so the
      branch pointer moved and nothing else did. Trees verified byte-identical before applying.
- [ ] **Merge `storage-allocation` → `main`** (6 commits) once the above is settled.
- [x] ~~**Documentation contradiction settled: `CLAUDE.md` is right, the archive note is stale.**~~
      `components/git/release.ps1:446` emits `vr-commit ($newTag) - $description`, and **every
      release commit in this repository''s history matches that format** (v4.0.0 through
      v5.0.2). `git-rl` also owns the version write, via `version-files.ps1:38-40`. So it is
      installed, it is used, and `$script:POWERFLOW_VERSION` must not be hand-edited.
- [x] ~~**Set a git identity**~~ — set repo-locally to the authorship this repository has always used. Nothing global was touched.
- [x] ~~**Restore `docs/agent-memory/` into the live memory directory**~~ — 12 notes restored,
      two corrected where they had gone stale (the flag ethos is decided; the architecture
      note''s file list is four months out of date), and two added: the trailer ban, and the
      owner''s D: drive layout.
- [x] ~~**Correct `IMPORT_ORDER.md`**~~ — Stage 6 rewritten (Linux has no bindings file, and
      the old arrangement is recorded as the fail-dangerous bug it was), the parity gate
      described as derived rather than hand-kept, and `shared/volumes.ps1` added to Stage 4
      with why its position is load-bearing.

---

## 4 · Machine-side, not code

- [ ] **Enable WSL** (elevation + reboot). Podman is installed and every path is placed under
      `D:\DevTools\VM\Containers`, but it cannot run a container until WSL exists.
- [ ] Clear the ~232 MB of stale `C:\...\Local\Temp` orphaned by the `TEMP` redirect.

Done: Scoop relocated to D: and the superseded C: copy removed; npm prefix and cache
leftovers removed; VS Code extensions and user data moved to `D:\DevTools\IDE\VSCode` behind
junctions; 86 READMEs written across the D: layout; `root_path` recorded alongside `SCOOP`.

---

## 5 · Standing constraints — do not relearn these the hard way

Recovered from [../../teams-chat/2026-08-18-owner-chat-archive.md](../../teams-chat/2026-08-18-owner-chat-archive.md)
after the reset. They are recorded here because a rule that lives only in a memory is a rule
one reset away from being broken — which is exactly what happened.

- **No `Co-Authored-By: Claude` trailers on commits in this repo.**
- **Never use the owner's real IP, username or hostnames as example text.** Use placeholders
  (`you@192.168.1.50`). A pushed commit message is forever without a history rewrite.
- **Automated tests must never invoke `f3probe --destructive`.**
- **Leave the `Podmansidecar` machine alone** — it belongs to another project.
- Work `docs/release-checklist.md` before every release. A tag with failed CI is not a
  release: verify `gh release view vX.Y.Z` shows it published with assets.
- Don't block-poll background workflows.
