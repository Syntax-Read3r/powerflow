# Log 1 — July 27, 2026 — start-folder, and making pwsh-config actually DO the work (v3.10.0)

Two asks in one turn, plus an instruction that shaped the whole session: *"You will need to
verify that your code is functional before release."*

## 1. `start-folder` (renamed from the proposed `pwsh-startup`)

**User:** "revise the name to start-folder, pwsh-startup seems like its a pwsh setting."

Right call — `pwsh-*` is PowerFlow's family for *shell/profile* things (`pwsh-config`,
`pwsh-autologin`, `pwsh-exit`). This command is about the Windows **Startup folder**, so the
name should say that. `startup` is the alias (verified it collides with no Linux binary).

Design (agreed the turn before): the Startup folder is only part of the story — on this
machine it held **1** item while the registry `Run` keys held **13**. So the command merges
every source into one list. Modelled on `srv` (picker-as-manager with `--expect`), not on
`pwsh-config` (which is for scalar settings).

**Enter toggles, ctrl-d deletes.** Toggling is reversible on both platforms — Windows flips
the `StartupApproved` flag exactly as Task Manager does; Linux clears `Hidden=true` in the
`.desktop`. Deleting is confirmed by typing the entry's name and shows the full command
first, because a removed registry `Run` value is unrecoverable (nothing records its command
line). Same reasoning as `installed-apps`' size bands: never put an unreviewable list in
front of a destructive action.

**The state trap.** Task Manager doesn't delete when you disable — it writes a flag. Docker
Desktop sits in HKCU `Run` on this machine and is *disabled*. Reading `Run` alone would
report it as starting at login, i.e. the tool would lie. Every row is joined against
`StartupApproved`. The flag is a 12-byte blob whose byte 0 carries the state; we test **bit
0** rather than compare whole bytes, because writers differ (observed `0x01` from an
installer, `0x03` from Task Manager) — and we write Task Manager's own values.

Linux is genuine parity, not a lookalike: XDG autostart, with `Hidden=true` as the exact
analogue. A **system** entry is shadow-copied into `~/.config/autostart` rather than edited
in place — the package owns the original and an upgrade would clobber an edit — and
`Remove` on a system entry disables it instead of deleting a packaged file. systemd `--user`
units are deliberately out of scope (a service manager, not a startup list); the component
says so instead of pretending.

## 2. `pwsh-config` on Windows: a menu that tells you what to run is not a tool

**User:** "pwsh-config on windows is not working as intended. Instead its providing fn() to
run to do the intended job... the purpose of pwsh-config is to streamline those functions in
the background."

Correct, and the v3.9.0 stub was the wrong call. It printed "change these in Settings, or
with cmdlets like Set-TimeZone / Rename-Computer" — a printed man page. Now Windows reads
and **applies** four settings: timezone, regional format, hostname, network time sync.

**Elevation.** Three of the four are machine-wide. Rather than refuse when PowerFlow runs
unelevated, the adapter re-runs *that one command* in an elevated child pwsh
(`Start-Process -Verb RunAs`) — one visible UAC prompt, per change, no silent privilege.
Factored into `Invoke-ElevatedCommand` in elevation.ps1 because the startup adapter needs
exactly the same thing for HKLM entries.

**Keyboard is deliberately absent on Windows.** A Windows layout is a property of the
input-language list (tips like `0809:00000809`), not a keymap; a wrong value can leave you
unable to type. Four honest settings beat five with a trap. The domain model already allows
this — rows are data, and the menu renders whatever the adapter returns.

Per-setting caveats ("takes effect after a RESTART") moved into a `Note` on the row, so the
component no longer special-cases keyboard.

## The bug functional testing caught (and it bit the real machine)

Testing `Set-SysConfig locale` with a junk value returned **True** and wrote a bogus `zz-ZZ`
regional format to the live machine. `Set-Culture` accepts an unknown culture name instead
of failing — unlike `Set-TimeZone`, which validates. Restored to `en-GB` immediately, then
fixed properly: both the adapter and `Complete-SysConfigChange` now reject a value that
isn't in the setting's own choices list. Re-tested: all three junk values rejected, setting
untouched, valid values still apply. A bad timezone is now also rejected *before* raising a
pointless UAC prompt.

This is exactly what "verify it's functional" is for — the code parsed, the happy path
worked, and it was still wrong.

## Verified (not assertions about code — the code, running)

**Windows, live, on the real machine:** enumerated 14 entries across 3 sources; Docker
Desktop correctly reported *disabled*; `desktop.ini` filtered; then a full CRUD lifecycle on
a probe entry created for the purpose — add → appears enabled with the `.lnk` resolved to
its target → toggle off (wrote `03 …`, re-read disabled) → toggle on (wrote `02 …`, re-read
enabled) → delete → gone. Cleanup verified the machine back to exactly its original 14
entries, no stray flags, regional format `en-GB`.

**Linux, in a container:** XDG round-trip — add (LF-only, trailing newline), toggle
`Hidden`, GNOME key kept consistent, an unrelated vendor key **survived** a toggle (proving
we rewrite one key rather than regenerate the file), system entry shadow-copied with the
original byte-identical and listed once (not duplicated), system remove disables rather than
deletes, user remove really deletes.

**Both platforms:** full profile load — `start-folder`, `startup`, `pwsh-config` resolve;
coreutils still native on Linux; both commands appear in the manual. Gates: parse,
architecture, adapter parity (5 new contract names on both platforms **and** added to the
hardcoded CI regex), help-registry, privacy.

**Not tested, stated plainly:** `Rename-Computer` was never executed — it changes machine
identity and needs a reboot. Its command construction, admin gating and validation path are
verified; the write itself is not. Same for the elevated write path: UAC cannot be
auto-approved, so `Invoke-ElevatedCommand` is verified up to the prompt.
