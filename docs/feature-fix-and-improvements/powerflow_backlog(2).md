# PowerFlow Backlog

> **Cumulative working log**
>
> Reset on 2026-08-10 after the previous backlog was pushed for change.
>
> **Outstanding entries: 16**

---

## Status key

- **BUG** — broken behaviour or a regression.
- **UX** — command-shape, discoverability, or convenience improvement.
- **FEATURE** — additive capability.
- **INVESTIGATE** — suspected defect requiring more evidence or instrumentation.

---

# Active backlog

## PF-FEAT-001 — guarded VM destroy / purge

### Native workflow

```bash
qm destroy 103 --purge 1
```

### PowerFlow grammar

Prefer the object-first form:

```powershell
pmx vm 103 destroy --purge
```

Keep an action-first compatibility route if required by the existing router:

```powershell
pmx vm destroy 103 --purge
```

### Safety classification

**RED / destructive and irreversible.** This command deletes VM state and attached VM-owned storage. `--purge` expands the operation to related Proxmox configuration. It must not use the ordinary one-key `y/N` amber confirmation unchanged.

### Required flow

```text
resolve explicit VM
→ read authoritative config/status
→ enumerate disks/snapshots and related configuration impact
→ refuse unsafe preconditions
→ show RED destructive preview
→ require typed identity confirmation
→ revalidate everything
→ execute one allow-listed destroy operation
→ verify VM/config absence
→ verify purge outcome where observable
→ write secret-free audit record
```

### Explicit selector only

Do **not** open an fzf picker for destroy. A destructive action should require an explicit VMID or VM name in the command line:

```powershell
pmx vm 103 destroy
```

This reduces the chance of destroying a VM selected by mistake from a transient picker.

### Default safety gates

Before confirmation:

- resolve the VMID/name authoritatively;
- show current status, node, type/template state and protection state;
- enumerate the attached VM-owned disks that Proxmox reports will be removed;
- show snapshot count/names if available;
- show whether `--purge` will remove related configuration;
- refuse a running VM by default;
- refuse a protected VM rather than silently overriding protection;
- refuse non-interactive/redirected sessions;
- support `--dry-run` with zero mutation.

Initial PowerFlow implementation should **not** expose native force-destroy as the easy path. If the VM is running, answer with the safe next step:

```text
VM 103 is running.
Shutdown first:
  pmx vm 103 shutdown
```

A separate force-destroy capability can be considered later with an even stronger gate.

### Destructive preview

Example:

```text
🛑 DESTROY VM — IRREVERSIBLE
────────────────────────────────────────────
VM            103 web-prod
Node          pve
Status        stopped
Protected     no

Will delete
  scsi0       40 GiB · local-zfs
  efidisk0    1 MiB · local-zfs
  snapshots   2

Purge         yes · remove related Proxmox configuration

This is not a snapshot rollback and cannot be undone by PowerFlow.
Type the VM name `web-prod` to continue:
```

The typed token must match the freshly-resolved VM name (or, for unnamed/edge cases, the exact VMID). `y` is insufficient.

### Revalidation

After the typed confirmation and immediately before execution, re-read:

- VM identity/VMID;
- status;
- protection flag;
- configuration digest/version if available;
- attached disk set;
- node ownership.

If any destructive-plan input changed, abort and require a fresh preview.

### Verification

After Proxmox reports success:

- VMID no longer resolves in managed inventory;
- VM configuration no longer exists;
- with `--purge`, related configured references are absent where the API exposes them;
- do not claim individual storage volumes were deleted unless the adapter can verify that reliably.

### Backups

Do not call a VM snapshot a safety backup: snapshots belonging to the VM can disappear with destruction. A future backup-awareness check may warn about the age/existence of an external backup, but destroy must not fabricate reassurance when backup state was not checked.

### Tests

- stopped VM destroy
- `--purge`
- running VM → refuse
- protected VM → refuse
- template destroy
- explicit VM name and VMID
- no selector → refuse (no picker)
- `--dry-run`
- typed name mismatch
- redirected input/output → refuse
- config changes between preview and confirm → revalidation refusal
- disk set changes between preview and execution → refusal
- execution accepted but verification fails → `unverified`, never false success
- audit record contains no endpoint/secrets

---

## PF-FEAT-002 — complete the high-value VM lifecycle surface

Current PMX already covers inventory/show/config/status, disks/network, clone, start/shutdown, CPU/memory, disk growth, and snapshot list/create. The next useful gaps should be added selectively rather than mirroring every `qm` subcommand.

### Tier 1 — everyday lifecycle

```powershell
pmx vm 102 reboot
```

Graceful reboot. Prefer guest-aware/graceful semantics and verify the VM returns to running state. This belongs beside start/shutdown.

```powershell
pmx vm 102 stop
```

Hard power-off. Stronger warning than shutdown; require the VM to be running and make data-loss risk explicit.

```powershell
pmx vm 102 reset
```

Hard reset. Strong warning: equivalent to a reset button, not an OS reboot. Do not make it the suggested next step after a normal failure.

### Tier 2 — snapshot completeness

Existing snapshot support has list/create but not the two operations needed to make snapshots operationally complete:

```powershell
pmx vm 102 snapshot rollback <name>
pmx vm 102 snapshot delete <name>
```

Rollback is destructive to current VM state and needs a RED plan with typed confirmation and a clear current-state warning. Snapshot delete is irreversible but narrower; use a strong confirmation and revalidate the snapshot identity before deletion.

### Tier 3 — runtime state

```powershell
pmx vm 102 suspend
pmx vm 102 resume
```

Show current state first; refuse nonsensical transitions (resume an already-running VM, suspend a stopped VM). Keep any experimental/native caveats visible rather than pretending all backends support identical semantics.

### Tier 4 — mobility/storage

```powershell
pmx vm 102 migrate <node>
pmx vm 102 disk move scsi0 <storage>
```

Migration should preview source node, target node, running/offline mode, storage mappings and constraints. Disk move should preview source/target storage, disk size, available target capacity and whether the source will be deleted after a verified copy.

These deserve the same validate → preview → confirm → revalidate → execute → verify structure as current guarded mutations.

### Lower priority / separate design pass

- convert VM to template;
- create a blank VM from scratch (clone already covers the common PowerFlow path);
- backup/restore (`vzdump`/restore is larger than `qm` and deserves its own safety model);
- arbitrary guest exec (keep identity/network probes allow-listed unless a separate remote-exec feature is deliberately designed).

---

## PF-UX-001 — `pmx list` / `pmx status` aliases and typo suggestions

### Observed

```powershell
pmx list
```

currently returns:

```text
❌ Unknown pmx command 'list'. Run: pmx help
```

Native `qm list` muscle memory makes this an obvious command.

### Proposal

```powershell
pmx list
```

should be an alias for:

```powershell
pmx vm
# / pmx vm list
```

and show the VM inventory.

Also support the obvious host-status shorthand:

```powershell
pmx status
```

as an alias for:

```powershell
pmx node status
```

This should use the exact existing node-status implementation; it is only another route into the same read-only view.

### Typo assistance

Observed:

```powershell
pmx lis
```

Instead of only a generic unknown-command error, offer a bounded suggestion:

```text
❌ Unknown pmx command 'lis'.
Did you mean:
  pmx list
```

Do **not** auto-run typo corrections. In particular, never autocorrect into a mutating/destructive command.

Suggestion policy:

- only suggest known registered PMX routes;
- small edit-distance/prefix mistakes only;
- one or at most a few high-confidence suggestions;
- preserve the exact input in the error;
- unknown commands with no close match still say `pmx help`.

Tests:

- `pmx list` parity with `pmx vm list`
- `pmx status` parity with `pmx node status`
- `pmx lis` suggests `pmx list`
- `pmx statu` suggests `pmx status`
- no autocorrection
- mutation/destruction names are suggestions only, never executed

---

## PF-UX-002 — picker cancellation is not an error

### Observed

```powershell
pmx disk list
```

opens the VM-selection path; cancelling it currently ends with:

```text
❌ cancelled
```

### Problem

Escaping an interactive picker is an intentional user action, not a command failure. Rendering it with the red error marker makes normal cancellation look like a defect.

### Proposal

Represent cancellation as a distinct result/state rather than the generic error string `cancelled`.

Preferred UI:

```text
↩ Cancelled.
```

in a neutral/dim style, or return silently where the surrounding PowerFlow picker convention already treats Escape as silent cancellation.

### Shared fix

Do this at the shared picker/result boundary so every PMX VM picker gets consistent semantics rather than special-casing `pmx disk list`.

Expected distinction:

```text
user pressed Esc       → Cancelled (neutral)
no VMs exist           → actionable state/error
fzf unavailable        → actionable instruction
transport failed       → error
invalid selector       → error
```

Tests:

- Escape from VM picker
- Escape from disk picker
- no-result condition vs cancellation
- redirected/noninteractive sessions never invoke fzf
- cancellation produces no red error marker


---

## PF-FEAT-003 — `server setup`: guided clone → identity hygiene → srv handoff → role provisioning

### Goal

Turn the current multi-shell server build process into one resumable PowerFlow workflow rather than a loose collection of remembered `qm`, SSH, hostname, identity, and package commands.

The entry point should be PowerFlow-wide, **not a PMX subcommand**:

```powershell
server setup
```

Optional compatibility spelling if desired:

```powershell
server --setup
```

Prefer the subcommand form in help because this is a workflow/mode, not a boolean flag.

### Why this should not live under `pmx`

The workflow crosses execution contexts:

```text
PowerFlow workstation / Proxmox host
        ↓
Proxmox clone/config operations
        ↓
first VM boot
        ↓
retrieve guest address through PMX/agent
        ↓
SSH / srv handoff into the guest
        ↓
guest identity repair
        ↓
role-specific server provisioning
```

Once the operator is inside the cloned VM, PMX is no longer the right local namespace. A top-level `server` orchestrator can call the correct subsystem for each phase:

```text
PMX   → hypervisor operations
srv   → SSH connection/alias handoff
pc-*  → guest identity/system operations where applicable
server → workflow state and role provisioning
```

### Primary UX

Bare:

```powershell
server setup
```

opens an fzf workflow picker such as:

```text
🧰 SERVER SETUP
────────────────────────────────────────────────────────
▶ New server
  Resume web-prod       · identity hygiene
  Resume media-01       · role provisioning
  Review docker-host    · complete
```

Do not make the user remember "which step am I on" if PowerFlow can infer it. Persist the workflow stage and re-check live state before continuing.

An advanced/recovery view may expose explicit steps when needed:

```text
1  Clone / VM resources
2  First boot / address
3  Guest identity
4  SSH / srv registration
5  Server role
6  Role verification
```

### Phase 1 — choose source and desired VM shape

When the PMX management connection is available, show the authoritative VM/template inventory and let the user pick the source with fzf.

Collect the desired target values in one guided plan:

```text
Source        100 debian13-base
Name          web-prod
VMID          auto (or explicit)
CPU           2 cores
Memory        4 GiB
Disk          32 GiB (or requested final size)
Role          Podman server
SSH user      you
```

The underlying native sequence may correspond to:

```bash
qm clone 100 103 --name web-prod --full 1
qm set 103 --cores 2 --memory 4096
qm resize 103 scsi0 +8G
qm config 103
```

but PowerFlow should use the existing allow-listed PMX clone/CPU/memory/disk functions rather than shelling out to a compound native command.

### Clone safety

Before mutation, show one complete plan and confirm once:

```text
🧬 BUILD SERVER VM
────────────────────────────────────────────
Source       100 debian13-base
Target       103 web-prod
Clone        full / independent
CPU          2 cores
Memory       4 GiB
Disk         scsi0 32 GiB → 40 GiB
First boot   held until clone verification
Role         Podman server
```

Flow:

```text
resolve source
→ allocate/revalidate target VMID
→ validate resource values
→ preview
→ confirm
→ clone
→ verify cloned config
→ apply CPU/RAM/disk values
→ verify final config
→ only then offer/start first boot
```

Do **not** boot the VM before the cloned configuration has been read back and verified.

Support `--dry-run` for the whole phase.

### Phase 2 — first boot and address discovery

After verified VM creation, start through the guarded PMX lifecycle path.

Then poll the existing PMX guest/network read path for a guest-reported address rather than asking the user to hunt for it manually.

Example handoff:

```text
✅ VM 103 web-prod is running
Address       192.168.x.x · DHCP
SSH user      you
```

The raw IP may be shown because the user explicitly requested the handoff, but it should not be copied into unrelated logs/debug output.

If guest-agent address discovery is unavailable, report that specific state and give the safe fallback rather than inventing an address.

### Phase 3 — clone identity hygiene

The workflow must never hard-code a known template `machine-id` such as:

```text
40deabad5baf433dba66e9db16cb97c2
```

Instead compare the clone against the **actual source/template identity record**.

Identity checks:

```text
hostname
/etc/machine-id
SSH ED25519 host-key fingerprint
```

#### Source identity record

PowerFlow needs a reusable template identity record so comparison does not depend on a pasted value.

Preferred model:

```powershell
server template audit <vm>
```

while the source guest is reachable, before/while preparing it as the reusable template. Record only the identity values needed for clone-hygiene comparison.

For privacy, persist hashes/fingerprints where an exact raw identifier is unnecessary. Machine-ID equality can be detected with a cryptographic hash rather than retaining/displaying the raw source machine ID everywhere.

If no source identity record exists, do **not** claim the clone is unique. Offer either:

```text
Identity comparison unavailable — source identity was never recorded.
```

or the safer clone policy of regenerating clone-specific identity unconditionally.

#### Clone comparison

After first boot and guest-agent availability:

```text
SOURCE vs CLONE
Machine ID      duplicate | unique | unknown
SSH host key    duplicate | unique | unknown
Hostname        inherited | changed
```

Example warning:

```text
⚠ Clone inherited source identity
  Machine ID    duplicate
  SSH host key  duplicate
```

### Phase 4 — guided guest identity repair

PowerFlow should provide the exact guest-side steps, but preferably execute them through an explicit privileged guest workflow rather than making the user reconstruct them from prose.

Hostname/hosts synchronization should reuse the planned safe hostname feature:

```powershell
pc-name web-prod
```

which updates the hostname and the matching `/etc/hosts` entry together, preserving the existing domain suffix instead of hard-coding `.powerhub`.

SSH server identity repair:

```bash
sudo rm -f /etc/ssh/ssh_host_*
sudo ssh-keygen -A
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

Machine identity repair:

```bash
sudo rm -f /var/lib/dbus/machine-id
sudo truncate -s 0 /etc/machine-id
sudo reboot
```

PowerFlow must clearly state that SSH **server host keys** are being regenerated; this must never touch the user's personal `~/.ssh` client keys.

After reboot, re-read the clone identity and verify it is no longer equal to the recorded source/template identity.

### Reboot/resume behaviour

The workflow necessarily crosses a reboot, so it must be resumable.

Persist a non-secret setup record such as:

```text
workflow id
target VMID/name
source VMID/name
chosen role
desired CPU/RAM/disk
SSH username
current stage
source identity comparison hashes/fingerprints
```

Do not persist passwords, private keys, or arbitrary guest command output.

After the VM returns:

```powershell
server setup
```

should find the in-progress `web-prod` workflow, re-check the VM/guest state, and continue at the correct phase.

### Phase 5 — automatic `srv` registration

Once the guest has a usable address and the operator supplies/chooses the SSH username, PowerFlow should offer to add the guest to `srv` automatically.

Example:

```text
SSH handoff
Alias         web-prod
User          you
Address       192.168.x.x

Add to srv? [Y/n]
```

Then the operator's normal connection becomes:

```powershell
srv web-prod
```

rather than repeatedly copying:

```text
ssh you@<discovered-ip>
```

Reuse the existing `srv` validation/privacy rules. Do not create a second SSH credential store inside `server`.

If DHCP later changes the address, normal `srv` management/update behaviour should own that problem rather than duplicating it in this workflow.

### Phase 6 — choose a server role

The workflow should ask what this machine is being built for.

Initial role picker:

```text
📦 SERVER ROLE
────────────────────────
Podman server
Docker server
Media server
Web server
Generic Linux server
Custom / no role
```

Roles should be **declarative profiles**, not giant hard-coded branches in one command.

Each role profile owns:

```text
prerequisite checks
packages/repositories
user/group requirements
firewall/network notes
service enablement
verification commands
optional next steps
```

Do not make role setup destructive by default, and do not silently remove competing software/repositories without showing the plan.

### Podman profile — baseline from the current proven workflow

Current requested baseline:

```bash
sudo apt install -y podman
podman --version
grep '^<user>:' /etc/subuid
grep '^<user>:' /etc/subgid
podman info --format '{{.Host.Security.Rootless}}'
```

Desired verification:

```text
Podman installed
subuid mapping present
subgid mapping present
rootless mode true
linger enabled
Quadlet user path ready
```

The username must come from the workflow (`you` in the current example), never be hard-coded.

After rootless UID/GID checks, verify the user-manager persistence state:

```bash
loginctl show-user <user> -p Linger
```

If it returns `Linger=no`, do not silently change it. Explain that the rootless user manager can disappear after logout and offer a guarded step:

```powershell
pdm doctor persistence --fix
```

which previews and, after confirmation, runs the equivalent of:

```bash
sudo loginctl enable-linger <user>
```

Then re-read the property and require `Linger=yes` before declaring the Podman server persistent-service ready.

Do not run the first long-lived production container until rootless prerequisites and persistence have been verified.

Any package/repository specifics beyond this baseline should be checked against the target distribution when the role profile is implemented.

### Docker role

Separate profile. Do not assume Docker and Podman have identical setup or rootless requirements.

The profile should detect existing Docker repository/key remnants and show exactly what it plans to add/remove before changing package sources.

### Media-server role

Keep this initially as a profile shell until the exact media stack is chosen. The workflow can safely collect common infrastructure choices without assuming a specific application:

```text
storage/mount locations
service account
container engine preference
ports/network exposure
GPU/transcode requirement
```

Application-specific installs (for example a particular media server) should be separate selectable recipes, not silently assumed by the generic `Media server` label.

### Generic/custom role

Allow the user to stop after clone hygiene + srv registration:

```text
✅ Base server ready
  VM identity unique
  SSH host identity unique
  srv alias registered
  no application role installed
```

This prevents `server setup` from becoming mandatory application automation.

### One-step meaning

"One step" should mean **one entry point and one resumable guided workflow**, not one enormous command that blindly executes every mutation without checkpoints.

The user can start with:

```powershell
server setup
```

and PowerFlow owns the state transitions, safety previews, handoffs, and resume logic until the server is complete.

### Suggested companion commands

```powershell
server setup                 # picker: new/resume/review
server setup new             # start a new workflow
server setup resume web-prod # explicit resume
server setup status web-prod # show current stage and live checks
server setup abandon web-prod# discard workflow metadata only; never delete the VM
server template audit <vm>   # record source identity for clone comparison
```

`abandon` must remove only PowerFlow workflow state. It must never destroy the VM; VM deletion remains the separately guarded `pmx vm <id> destroy` operation.

### Failure/partial-success handling

Every phase must report what already succeeded.

Example:

```text
✓ VM 103 cloned
✓ CPU/memory verified
✓ First boot completed
✓ Address discovered
✗ SSH registration failed

VM 103 was kept.
Resume:
  server setup resume web-prod
```

Never automatically destroy a successfully-created VM because a later provisioning phase failed.

### Tests

At minimum:

- local Proxmox management path
- PMX-over-saved-srv management path
- source selection with fzf
- automatic and explicit target VMID
- CPU/RAM/disk desired values
- clone verification before boot
- first boot
- guest-agent unavailable
- DHCP address unavailable
- workflow interruption/resume
- source identity record present/absent
- duplicate machine ID detection
- duplicate SSH host-key detection
- hostname + `/etc/hosts` synchronization
- identity regeneration + reboot + post-reboot verification
- automatic srv registration
- Podman role with username other than `you`
- missing subuid/subgid mappings
- role setup failure after successful base-server build
- `abandon` never mutates/destroys VM state
- no secrets/private keys stored in setup state
- noninteractive mode never opens fzf or privilege prompts



---

## PF-FEAT-004 — `pdm` Podman wrapper with human event time ranges

### Goal

Add a PowerFlow Podman surface that keeps native Podman available but makes common inspection workflows much shorter and easier to read.

Initial focus:

```powershell
pdm -e ...
pdm --events ...
```

Both spellings should route to the same event reader.

Do not shadow or replace the native `podman` command.

### Human time-range grammar

Preferred examples:

```powershell
pdm -e t@00:40 00:50
pdm --events today@00:40 00:50
pdm -e yd@00:40 00:50
pdm -e 2025-03-05@00:40 01:03
pdm -e 05/03/25@00:40 to 01:03
```

Aliases:

```text
t   = today
td  = today
today

y   = yesterday
yd  = yesterday
yesterday
```

`to` is optional visual grammar:

```powershell
pdm -e t@00:40 00:50
pdm -e t@00:40 to 00:50
```

Both forms are equivalent.

### Range resolution

PowerFlow should resolve the friendly range into exact local timestamps before invoking Podman.

Example at Europe/London local time:

```powershell
pdm -e t@12:35 12:42
```

becomes conceptually:

```bash
podman events --since '2026-08-12T12:35:00+01:00' --until '2026-08-12T12:42:00+01:00'
```

Use the machine's local timezone and include the resolved range in the output header so there is no hidden timezone interpretation.

### End-before-start rule

This should be an error:

```powershell
pdm -e yd@00:40 00:30
```

because the second bare time inherits the same day and is earlier than the start.

Return something explicit:

```text
❌ End time 00:30 is before start time 00:40 on yesterday.

For a cross-midnight range, name the second day explicitly:
  pdm -e yd@00:40 t@00:30
```

Do not silently roll the end time into the next day.

### Explicit dates

Canonical script-safe date syntax:

```text
YYYY-MM-DD@HH:mm
```

Example:

```powershell
pdm -e 2025-03-05@00:40 01:03
```

A locale-friendly slash date may also be accepted interactively:

```powershell
pdm -e 05/03/25@00:40 01:03
```

but PowerFlow must resolve and echo the interpreted date before showing results.

For ambiguous slash dates, use the configured/system locale date order; `--json`/script usage should prefer ISO dates.

Never guess silently across MDY/DMY conventions.

### Container filtering

Allow the time range to combine naturally with a container name or ID:

```powershell
pdm -e web-test t@12:35 12:42
pdm -e --container web-test t@12:35 12:42
```

Normalize to Podman's native event filter rather than filtering formatted text after the fact.

Future event filters can expose the useful Podman dimensions without inventing new semantics:

```powershell
pdm -e --event stop t@12:00 13:00
pdm -e --type container t@12:00 13:00
```

### Output

Default PowerFlow output should be compact and table-oriented:

```text
📜 PODMAN EVENTS — today 12:35 → 12:42
────────────────────────────────────────────────────────
TIME      TYPE       EVENT      NAME       EXIT
12:39:05  container  stop       web-test   0
12:39:06  container  cleanup    web-test   0
```

Keep:

```powershell
pdm -e --json ...
```

for structured output.

Do not discard Podman's event status, object type, container name/ID, exit code, or timestamp in the internal model.

### Historical-event diagnostics

Observed native state:

```text
podman inspect web-test
  Exit=0
  Finished=2026-08-12 12:39:06 +0100
```

but:

```bash
podman events --since '2026-08-12T12:35:00' --until '2026-08-12T12:42:00'
```

returned no events.

This is not enough evidence to call it a Podman bug. Podman event history depends on its configured event backend and available retained history.

When a bounded historical query returns zero rows, PowerFlow should distinguish:

```text
no matching events
historical event backend disabled
backend unavailable
query valid but retained history unavailable
```

rather than printing an unexplained blank screen.

Useful diagnostic command:

```powershell
pdm -e doctor
```

or:

```powershell
pdm doctor events
```

Preferred output:

```text
🩺 PODMAN EVENTS
Backend       journald
Rootless      yes
History read  available
Current user  you
```

The backend can be read from Podman system info (`Host.EventLogger`).

If the backend is `none`, say directly that historical/live Podman events are disabled and name the relevant Podman/containers.conf setting without changing it automatically.

Do not silently switch the user's event backend.

### Native compatibility

Podman's current event command accepts `--since` and `--until` timestamps or Go-style durations, and supports native filters including container, event, image, label, pod, volume, and type.

PowerFlow should preserve an escape hatch for native-style values where possible:

```powershell
pdm -e --since 10m
pdm -e --since 1h --until 10m
```

Do not make the friendly parser less capable than the native command for common reads.

### Parser rules

Hand-parse the arguments consistently with PowerFlow commands that deliberately accept nonstandard single-dash convenience tokens.

Important distinctions:

```text
-e / --events     PowerFlow event route
-t                do not reuse if it collides with an established Podman/PowerFlow meaning
`to`              grammar separator only, not an option
@                 separates day/date token from clock time
```

Validate all ranges before executing Podman.

### Tests

At minimum:

- `t@00:40 00:50`
- `today@00:40 to 00:50`
- `yd@00:40 00:50`
- yesterday end earlier than start → error
- explicit cross-midnight range with both day tokens
- ISO date
- locale slash date
- ambiguous locale-date handling
- DST transition day
- current local timezone included correctly
- container filter
- event/type filters
- `--json`
- backend journald
- backend file
- backend none
- valid zero-event result
- unavailable/expired history state
- rootless user
- native duration passthrough
- no command hangs when stdout is redirected


---

## PF-FEAT-005 — refined `pdm logs` + readable container lifecycle inspection

### Native workflow being replaced

```bash
podman logs --tail 30 --timestamps web-test
podman inspect web-test --format 'Exit={{.State.ExitCode}} Finished={{.State.FinishedAt}} Error={{.State.Error}}'
podman inspect web-test --format 'StopSignal={{.Config.StopSignal}}'
```

These are useful diagnostics, but the operator has to remember several Podman flags and Go-template property paths just to answer:

```text
what did this container log?
when did it stop?
did it exit cleanly?
what stop signal is configured?
```

### Recommended logs command

```powershell
pdm logs web-test
```

PowerFlow-friendly defaults:

```text
timestamps   on
tail         30 lines
follow       off
```

Equivalent native intent:

```bash
podman logs --tail 30 --timestamps web-test
```

### Default display is cleaned, not raw

The default `pdm logs` view should make noisy application logs readable without destroying evidence.

Use conservative grouping rather than arbitrary filtering. For example, repeated nginx worker startup/exit lines may collapse to:

```text
10:26:20  INFO   nginx 1.31.3 starting
10:26:20  INFO   worker processes started · 2
10:27:05  HTTP   GET / → 200
10:27:06  ERROR  /favicon.ico missing → 404
12:39:06  STOP   SIGTERM received
12:39:06  STOP   SIGQUIT · graceful shutdown
12:39:06  INFO   workers exited cleanly · 2
```

Never collapse away:

- errors or warnings;
- non-zero exits;
- OOM messages;
- authentication failures;
- HTTP request/status lines;
- unique signals;
- stack traces;
- unique configuration/startup messages.

Provide explicit escape hatches:

```powershell
pdm logs web-test --raw   # native lines, no cleanup
pdm logs web-test --full  # all available history, still PowerFlow-formatted
```

Live `-f` mode should use only light formatting and should not aggressively group lines, because timing/order is part of the evidence.

Do not dump the container's entire lifetime by default. Full history should be explicit:

```powershell
pdm logs web-test --all
```

### Tail refinement

Avoid inventing `-n` as a PowerFlow tail shorthand because Podman's own `podman logs -n` means `--names`, not `--tail`.

Use either:

```powershell
pdm logs web-test --tail 100
```

or the convenient positional form:

```powershell
pdm logs web-test 100
```

The positional integer should normalize internally to Podman's `--tail` value.

### Reuse the PF-FEAT-004 human time parser

The event time grammar should become a shared Podman time-range parser, not remain event-specific.

Examples:

```powershell
pdm logs web-test t@12:35 12:42
pdm logs web-test yd@23:50 t@00:10
pdm logs web-test 2026-08-12@10:25 to 10:30
```

Normalize to native:

```text
--since <resolved timestamp>
--until <resolved timestamp>
```

Use the same validation rules as `pdm -e`:

- inherited day/date for a bare end time;
- reject end-before-start unless the end carries a later explicit day/date;
- ISO dates canonical for scripts;
- visibly resolve locale-style dates;
- preserve local timezone/offset correctly.

### Follow mode

Keep the familiar native spelling:

```powershell
pdm logs web-test -f
pdm logs web-test --follow
```

A bounded historical time range plus `--follow` should be validated deliberately rather than producing surprising semantics.

### Bare logs command

Interactive:

```powershell
pdm logs
```

should open a container picker showing at least:

```text
NAME        STATE       IMAGE
web-test    exited      nginx:alpine
```

Then display logs for the selected container.

Redirected/noninteractive output must never open fzf; require an explicit container selector.

### Readable inspect / lifecycle view

Add:

```powershell
pdm inspect web-test
```

or a shorter read-only alias:

```powershell
pdm show web-test
```

PowerFlow should extract useful fields from structured `podman inspect` output instead of requiring users to write Go templates.

Example:

```text
📦 CONTAINER — web-test
────────────────────────────────────────────
Image         nginx:alpine
State         exited
Exit          0 · clean
Started       10:26:20
Finished      12:39:06
Error         —
Stop signal   SIGQUIT
Ports         8080 → 80/tcp
```

Useful state fields include:

```text
State.Status
State.Running
State.Paused
State.Restarting
State.OOMKilled
State.Dead
State.ExitCode
State.Error
State.StartedAt
State.FinishedAt
Config.StopSignal
```

Keep raw structured output available:

```powershell
pdm inspect web-test --json
```

### Logs footer

For a non-following logs read, append a small lifecycle footer derived from inspect data:

```text
────────────────────────────────────────────
Container     web-test
State         exited
Exit          0 · clean
Finished      12:39:06
Stop signal   SIGQUIT
```

This lets the user correlate the final log lines with container state without another command.

Do not claim that the configured stop signal caused a particular log message unless Podman/state data actually proves that relationship.

For `--follow`, omit the footer while streaming; if the follow session ends normally and the container can be inspected, print the final state afterward.

### Useful follow-up actions

The lifecycle view can name obvious next commands without changing state automatically:

```text
pdm logs web-test -f
pdm events web-test t@12:30 12:45
pdm start web-test
```

Do not auto-restart an exited container just because logs are being inspected.

### Relationship to PF-FEAT-004

PF-FEAT-004 introduced friendly Podman event time expressions.

Factor its parser into a shared helper used by both:

```text
pdm events / pdm -e
pdm logs
```

This prevents two date/time grammars from drifting.

### Tests

At minimum:

- default tail = 30
- timestamps shown by default
- explicit `--tail`
- positional tail count
- `--all`
- `-f` / `--follow`
- time-range grammar shared with events
- cross-midnight explicit range
- invalid backwards range
- running container
- exited code 0
- exited nonzero
- OOMKilled state
- State.Error populated
- StopSignal populated / absent
- stopped container with historical logs
- no logs available
- container picker interactive
- no picker when redirected
- `--json` inspect output
- logs footer state matches authoritative inspect data
- control characters/container names sanitized before terminal display


---

## PF-FEAT-006 — `journal`: clean Linux system timeline over `journalctl`

### Problem

Raw Linux journal output is powerful but difficult to reason about because one incident can contain messages from SSH, PAM, logind, the system user manager, Podman/conmon, the container process, sockets, slices, and cleanup units in one chronological stream.

Example incident evidence showed, within seconds:

```text
sshd connection timeout
→ SSH/PAM session closed
→ systemd-logind removed the session
→ user@1000.service began stopping
→ libpod / podman scopes began stopping
→ nginx received SIGTERM / SIGQUIT
→ container exited cleanly
→ Podman recorded container died + cleanup
→ user manager exited
```

The valuable information is the **relationship between those events**, not 70 nearly-equivalent shutdown lines.

### Recommended command family

Linux-only PowerFlow command:

```powershell
journal
```

It is a readable front-end to `journalctl`, not a replacement logging database.

Reuse the same human time-range parser as `pdm events` / `pdm logs`:

```powershell
journal t@12:38:30 12:39:30
journal yd@23:50 t@00:10
journal 2026-08-12@12:38:30 to 12:39:30
```

### Default output: grouped timeline

Instead of printing every raw entry, parse structured journal data and render a chronological timeline grouped by source and transition.

For the supplied incident, a useful PowerFlow result would be approximately:

```text
🧭 SYSTEM TIMELINE — 12:38:30 → 12:39:30
────────────────────────────────────────────────────────
12:38:56  SSH      remote 10.0.0.3 timed out
12:38:56  SESSION  you session closed
12:38:56  LOGIND   session 1 removed

12:39:06  USER     user@1000 manager stopping
12:39:06  PODMAN   3 rootless Podman scopes stopping
12:39:06  WEB-TEST SIGTERM received
12:39:06  WEB-TEST SIGQUIT · graceful shutdown
12:39:06  WEB-TEST workers exited cleanly · 2
12:39:06  PODMAN   container died · web-test
12:39:07  PODMAN   cleanup complete · web-test
12:39:07  USER     user@1000 manager stopped

LIKELY CHAIN
  SSH session ended
      ↓
  user manager shut down
      ↓
  rootless Podman scopes were stopped
      ↓
  web-test exited cleanly
```

The **LIKELY CHAIN** must be explicitly marked as inference. The timeline above it is factual evidence.

### Structured input, not regexing pretty journal text

PowerFlow should request a structured journal format (`journalctl` JSON/export output) and use fields such as:

```text
__REALTIME_TIMESTAMP
PRIORITY
MESSAGE
_SYSTEMD_UNIT
_SYSTEMD_USER_UNIT
SYSLOG_IDENTIFIER
_COMM
_PID
_UID
```

Do not parse the default human-rendered `Aug 12 12:39:06 ...` text if structured output is available.

### Conservative cleanup rules

Collapse repetitive state transitions when the meaning is preserved:

```text
Closed gpg-agent.socket
Closed gpg-agent-extra.socket
Closed gpg-agent-browser.socket
```

may become:

```text
USER     auxiliary user sockets closed · 3
```

Likewise multiple clean worker exits can become one count.

Never collapse away:

- warning/error/critical messages;
- service failures;
- authentication failures;
- OOM kills;
- kernel errors;
- filesystem/storage errors;
- network link failures;
- container non-zero exits;
- unique signals;
- explicit resource peaks if they are unusually high;
- the first and final state transition of a service/session.

### Views / filters

Useful human forms:

```powershell
journal t@12:38 12:40
journal ssh t@12:38 12:40
journal podman t@12:38 12:40
journal web-test t@12:38 12:40
journal -p warning t@12:38 12:40
journal -u ssh.service t@12:38 12:40
```

The free selector (`ssh`, `podman`, `web-test`) should search structured identifiers/unit names/messages without shelling out to `grep`.

Keep native-style exact filtering available with explicit flags.

### `journal why`

Add an evidence-oriented incident view:

```powershell
journal why web-test t@12:38:30 12:39:30
```

It may correlate:

- container events;
- user-manager lifecycle;
- SSH/logind sessions;
- systemd units/scopes;
- Podman/conmon messages.

Output must separate:

```text
EVIDENCE
INFERENCE
CHECK NEXT
```

Example:

```text
EVIDENCE
  12:38:56 SSH session closed
  12:39:06 user@1000.service began stopping
  12:39:06 Podman scopes began stopping
  12:39:06 web-test received shutdown signals
  12:39:06 container exited 0

INFERENCE
  The container likely stopped because the user's systemd manager was being torn down after logout.

CHECK NEXT
  loginctl show-user you -p Linger
```

Never state inferred causality as proven fact.

### Rootless-server diagnostic

For a machine intended to host persistent rootless services, add a focused check such as:

```powershell
server check rootless
```

or within Podman:

```powershell
pdm doctor persistence
```

It should inspect at least:

```text
rootless mode
subuid/subgid
systemd user manager
loginctl Linger
Quadlet/user-service presence
```

If `Linger=no`, explain that the user manager is not configured to remain around after logouts. Do not automatically enable lingering; offer the exact remediation only after explaining the consequence.

### Raw / full escape hatches

```powershell
journal --raw t@12:38:30 12:39:30
journal --full t@12:38:30 12:39:30
```

Suggested distinction:

```text
default  → grouped timeline
--full   → every entry, PowerFlow formatting
--raw    → native journal text
```

`--raw` is essential whenever cleanup might hide a clue.

### Privilege handling

Do not automatically prepend `sudo` to every journal read.

1. Attempt the requested read with current-user permissions.
2. If the journal reports insufficient access and the missing data is required, explain what is unavailable.
3. In an interactive terminal, offer/elevate only that read through `sudo` if PowerFlow's privilege policy allows it.
4. Never prompt for sudo in redirected/noninteractive output.

### Relationship to `pdm`

Keep responsibilities separate:

```text
pdm logs       → application/container stdout/stderr
pdm events     → Podman lifecycle events
pdm show       → current container state/config summary
journal        → host-wide Linux/systemd timeline
journal why    → cross-source correlation
```

A `pdm show` footer can suggest a relevant journal query when a container stopped unexpectedly:

```text
journal why web-test t@12:35 12:42
```

### Tests

At minimum:

- absolute and relative time ranges;
- cross-midnight ranges;
- JSON/export journal parsing;
- system vs user units;
- SSH session close + logind removal;
- user-manager shutdown;
- Podman/conmon scopes;
- repeated socket shutdown collapsed safely;
- warning/error entries never hidden;
- non-zero exits never hidden;
- inference visibly separated from evidence;
- `--full` contains every parsed entry;
- `--raw` bypasses cleanup;
- insufficient journal permissions;
- sudo unavailable;
- noninteractive mode never prompts;
- terminal control characters sanitized.

---


---

## PF-FEAT-007 — `pdm service`: guided Quadlet conversion and rootless persistence

### Context

A rootless Podman container started interactively can be tied to the user's systemd manager. In the observed server workflow:

```bash
loginctl show-user you -p Linger
```

returned:

```text
Linger=no
```

and the journal showed the user manager stopping immediately before the rootless Podman scopes and container shut down.

After:

```bash
sudo loginctl enable-linger you
```

`Linger=yes` becomes the persistence prerequisite for long-running rootless user services.

### `pdm doctor persistence`

Add:

```powershell
pdm doctor persistence
```

Example:

```text
🩺 PODMAN PERSISTENCE
────────────────────────────────────────
User          you
Rootless      yes
subuid        ready
subgid        ready
User manager  available
Linger        no  ⚠
Quadlet path  ~/.config/containers/systemd

Long-running rootless services may stop when the user manager exits.

Fix:
  pdm doctor persistence --fix
```

`--fix` must be guarded. It should:

1. resolve the current user rather than hard-code a username;
2. show current `Linger` state;
3. explain the effect;
4. preview the native operation;
5. confirm;
6. run `loginctl enable-linger <user>` with the required privilege;
7. re-read `Linger` and verify `yes`.

Do not enable linger merely because Podman is installed.

### Quadlet workflow

Once persistence is healthy, provide:

```powershell
pdm service
```

Bare interactive mode opens an fzf picker of containers and service actions.

Useful explicit forms:

```powershell
pdm service web-test
pdm service web-test convert
pdm service web-test show
pdm service web-test start
pdm service web-test stop
pdm service web-test restart
pdm service web-test status
pdm service web-test logs
pdm service list
```

### Convert an ad-hoc container

For a container such as `web-test`, `convert` should inspect the existing container and build a proposed `.container` file from structured metadata.

It may derive:

```text
image
container name
published ports
volumes
networks
selected environment variables
restart policy
command/arguments
working directory
healthcheck
```

Never copy secrets blindly from inspect output into a generated Quadlet. Environment variables that look secret-bearing must be redacted and require explicit handling.

### Preview before writing

```powershell
pdm service web-test convert
```

should show something like:

```text
📦 QUADLET PLAN — web-test
────────────────────────────────────────
Source        existing container · web-test
Target        ~/.config/containers/systemd/web-test.container
Image         docker.io/library/nginx:alpine
Port          8080 → 80/tcp
Restart       on-failure
Boot          user manager startup
Linger        yes

Generated definition:
  [Unit]
  Description=web-test

  [Container]
  Image=docker.io/library/nginx:alpine
  ContainerName=web-test
  PublishPort=8080:80

  [Service]
  Restart=on-failure

  [Install]
  WantedBy=default.target

Write this Quadlet? [y/N]
```

The exact generated keys must follow the installed Podman/Quadlet version rather than assuming every release has identical options.

### Name collision handling

The existing ad-hoc container often owns the same name the Quadlet wants.

Do not automatically remove it before the user sees the plan.

Recommended sequence:

```text
inspect existing container
→ generate/validate Quadlet
→ confirm conversion
→ stop existing container if required
→ remove only the old ad-hoc container object
→ write Quadlet
→ systemctl --user daemon-reload
→ start generated service
→ verify container/service state
```

If conversion fails after the old container is removed, retain enough inspected metadata to explain recovery. Do not delete volumes/images as part of conversion.

### Dry-run

```powershell
pdm service web-test convert --dry-run
```

must perform no mutation and should still:

- inspect the container;
- check linger;
- locate the rootless Quadlet path;
- generate the proposed file;
- validate obvious collisions;
- show resulting service name and commands.

### Service status

```powershell
pdm service web-test status
```

should combine systemd + Podman state:

```text
📦 SERVICE — web-test
────────────────────────────────────────
Quadlet       web-test.container
Service       web-test.service
Systemd       active
Container     running
Image         nginx:alpine
PID           4627
Port          8080 → 80
Linger        yes
Boot ready    yes
```

### Logs

```powershell
pdm service web-test logs
```

should reuse the clean journal/log timeline work already defined in PF-FEAT-005 and PF-FEAT-006 rather than inventing another log parser.

It should be able to correlate:

```text
systemd user service
Podman/conmon scope
container output
container lifecycle events
```

with `--raw` / `--full` escape hatches.

### `server setup` integration

For the `Podman server` profile in PF-FEAT-003, the guided stages should become:

```text
install Podman
→ verify version
→ verify subuid/subgid
→ verify rootless
→ verify/enable linger
→ create Quadlet directory
→ optionally create/convert first service
→ verify service survives logout/reboot readiness
```

The role picker can offer:

```text
Podman server
  ✓ engine installed
  ✓ rootless ready
  ✓ persistence ready
  ○ no managed services yet
```

### Important separation

`pdm service` manages Podman/Quadlet services inside the Linux guest.

`server setup` orchestrates the wider machine-build workflow.

`pmx` remains Proxmox-host/remote-Proxmox management.

Do not collapse those namespaces together.

### Tests

- Linger=yes
- Linger=no
- guarded `--fix`
- non-root user with sudo
- no sudo
- missing subuid/subgid
- rootless=false
- Quadlet directory missing
- container conversion dry-run
- existing container name collision
- ports
- bind mounts and named volumes
- networks
- environment redaction
- stop/remove failure during conversion
- invalid generated Quadlet
- daemon-reload failure
- service start failure
- service/container status disagreement
- logout/re-login persistence check
- no volumes/images deleted during conversion


---

## PF-FEAT-008 — top-level PMX fleet network + SSH status

### Goal

Provide a fast Proxmox-level answer to:

```text
Which VMs are running, what addresses do their guest agents report, and which of those guests currently have SSH reachable?
```

The native building block is:

```bash
qm guest cmd <vmid> network-get-interfaces
```

but PowerFlow should aggregate that across the VM inventory and render a clean status view.

### Preferred syntax

Fleet view:

```powershell
pmx net -a status
pmx network --all status
```

Single VM:

```powershell
pmx net 900 status
pmx network web-prod status
```

`net` and `network` are aliases to the same implementation.

`-a` is the short form of `--all`.

### Example fleet output

```text
🌐 VM NETWORK STATUS
──────────────────────────────────────────────────────────────────────
VMID  NAME             VM       AGENT       ADDRESS          SSH
100   debian13-base    stopped  —           —                stopped
101   debian13-lab     running  available   192.168.1.111    ready
102   docker-host      running  available   192.168.1.112    ready
103   web-prod         running  available   192.168.1.114    ready
900   debian13-base-v2 running  available   192.168.1.120    closed
```

Suggested SSH states:

```text
ready
closed
unreachable
no-address
agent-unavailable
stopped
not-tested
```

Do not flatten `agent-unavailable`, `no-address`, and `closed` into the same generic failure.

### Data flow

For `--all`:

1. read authoritative VM inventory;
2. retain stopped VMs in the table rather than silently omitting them;
3. for each running QEMU VM, query configured/guest-agent state through the existing PMX network functions;
4. when the guest agent is available, use `network-get-interfaces` data to obtain guest-reported addresses;
5. exclude loopback and obvious link-local addresses from the primary candidate by default;
6. choose/display the same clearly-labelled primary candidate already used by the PMX network layer;
7. test SSH reachability only against those known candidate addresses;
8. render one fleet table.

Do not create a second implementation of guest interface parsing if `pmx vm network list` already owns this data path.

### SSH probe semantics

`SSH=ready` should mean only:

```text
TCP connection to the selected SSH port succeeded
```

It must **not** mean:

```text
credentials were accepted
login succeeded
host key was trusted
```

Default port is 22 unless PowerFlow has an explicit saved `srv` target/port for that VM and can correlate it confidently.

Reuse the existing `srv` TCP-port reachability logic rather than creating a PMX-specific socket tester.

### No scanning

This view must not perform LAN/subnet discovery.

Specifically, do not fall back to:

```text
ARP scraping
DNS guessing
DHCP lease scraping
ping sweeps
port scans across 192.168.x.0/24
```

when guest-agent data is absent.

If PMX does not know the guest address, display:

```text
no-address
```

or:

```text
agent-unavailable
```

and leave it at that.

### Multiple interfaces

If a VM has multiple usable addresses, default output should show the primary candidate plus a count:

```text
192.168.1.114  +2
```

Drill-down:

```powershell
pmx net 103 status
```

can show all interfaces:

```text
VM 103 — web-prod
────────────────────────────────────────
State       running
Agent       available

INTERFACES
eth0        192.168.1.114/24
            fe80::....

SSH
Address     192.168.1.114
Port        22
Status      ready
```

### IPv4 / IPv6

Reuse PMX network filtering conventions where possible:

```powershell
pmx net -a status -4
pmx net -a status -6
```

Do not treat IPv6 support as a separate implementation.

### Relationship to existing PMX network routes

The existing VM-scoped/fleet network functions remain the underlying source of truth.

This feature adds the ergonomic top-level route:

```text
pmx net ...
pmx network ...
```

and enriches the fleet status with SSH reachability.

It should not fork the parser or guest-agent model used by:

```text
pmx vm net
pmx vm ip
pmx vm nic
pmx vm network list
```

### `srv` integration

When a VM can be confidently matched to a saved `srv` alias, display it as optional metadata:

```text
103  web-prod  192.168.1.114  SSH ready  srv:web-prod
```

Do not auto-create an `srv` entry from this read-only status command.

Registration belongs to the guided `server setup` workflow or an explicit `srv` action.

### Performance / concurrency

Fleet SSH probes may run concurrently, but use a small bounded concurrency limit and short connect timeout.

One slow/unreachable guest must not block the entire table.

Preserve deterministic VMID ordering in final output even if probes complete out of order.

### Noninteractive / output modes

No picker is needed for `--all`.

Single-VM missing selector may use the existing guarded VM picker interactively.

Support script-friendly forms through the same structured model:

```powershell
pmx net -a status --json
pmx net -a status --table
```

### Tests

- all VMs stopped
- mixed running/stopped fleet
- running + agent available + SSH ready
- running + agent available + SSH closed
- running + agent unavailable
- no usable guest address
- multiple interfaces
- loopback excluded
- IPv4 filter
- IPv6 filter
- custom saved srv SSH port
- no matching srv alias
- bounded concurrent probes
- one timeout does not block fleet
- no ARP/DNS/DHCP/subnet fallback
- deterministic VMID order
- `net` / `network` alias parity
- `-a` / `--all` parity
- JSON/table parity


---

## PF-FEAT-009 — PMX SSH connection/session telemetry: compact fleet counts, detailed per-VM view

### Goal

Extend the top-level network status feature so PowerFlow answers two different questions at the right level of detail:

```powershell
pmx net -a status
pmx network --all status
```

→ compact fleet health, including whether SSH is listening/reachable and how many live SSH transports/sessions are observable.

```powershell
pmx net 103 status
pmx network web-prod status
```

→ detailed network + SSH state for one VM.

### Terminology: connection vs session vs channel

Do not collapse these into one misleading number.

Use:

```text
Connection  = one established SSH TCP transport
Session     = an observable shell/login/exec/subsystem session carried by SSH
Channel     = OpenSSH protocol channel; may also be forwarding, agent, X11, etc.
```

PowerFlow should advertise **Connections** and **Sessions** because those can be observed with normal guest telemetry.

Do not claim an exact `Channels` count unless the selected platform/sshd telemetry actually exposes all active channel types. An SSH connection can contain multiple sessions and non-session channels, so `sessions != all channels`.

If a future instrumented backend can enumerate protocol channels reliably, expose it as an additional field rather than changing the meaning of `Sessions`.

### Fleet view (`--all`)

Keep this deliberately compact and privacy-conscious:

```text
🌐 VM NETWORK STATUS
──────────────────────────────────────────────────────────────────────
VMID  NAME             VM       ADDRESS          SSH    CONN  SESS
100   debian13-base    stopped  —                —         0     0
101   debian13-lab     running  192.168.1.111    ready     1     1
102   docker-host      running  192.168.1.112    ready     2     3
103   web-prod         running  192.168.1.114    ready     1     2
900   debian13-base-v2 running  192.168.1.120    closed    0     0
```

Recommended meanings:

```text
SSH ready   = configured SSH port accepted a TCP connection probe
SSH closed  = address known, port refused/closed
SSH timeout = address known, bounded probe timed out
SSH ?       = no authoritative address or no usable telemetry
CONN        = established SSH TCP transports observed inside guest
SESS        = observable authenticated SSH shell/login/exec/subsystem sessions
```

Do **not** show remote source IPs, usernames, commands, or TTYs in the `--all` view.

### Individual VM view

For an explicit VM selector, show the deeper detail automatically:

```text
🌐 NETWORK — VM 103 · web-prod
────────────────────────────────────────────────────────────
State          running
Agent          available
Primary IPv4   192.168.1.114
SSH port       22
SSH            ready
Connections    2 established
Sessions       3 observable

INTERFACES
NAME   MAC                ADDRESS
ens18  BC:24:11:..        192.168.1.114/24
lo     —                  127.0.0.1/8

SSH CONNECTIONS
SOURCE             USER     SESSIONS   AGE      DETAIL
10.0.0.3:53238     you           2   18m      shell · exec
10.0.0.8:42117     backup          1   3m       sftp
```

Only show fields PowerFlow can actually correlate. If the guest exposes established connections but not a trustworthy per-connection user/session mapping, degrade honestly:

```text
Connections    2 established
Sessions       3 observable
Correlation    unavailable
```

Never fabricate a source→user relationship from timestamps alone.

### Data sources / implementation boundary

Reuse the existing PMX network model first:

- VM inventory/status;
- QEMU Guest Agent availability;
- `network-get-interfaces` guest-reported addresses;
- existing primary-address selection;
- existing bounded SSH-port probe / `srv` port knowledge.

For live SSH occupancy, add a narrow **read-only guest telemetry adapter** executed through the QEMU Guest Agent when available.

The adapter may collect structured equivalents of:

- established TCP sockets owned by/listening for sshd;
- login/session records;
- sshd/sshd-session process relationships;
- systemd-logind session metadata where useful.

Do not expose arbitrary `qm guest exec` to the user as part of this feature. Keep the guest commands allow-listed and parse them into a typed PowerFlow model.

### Port resolution

Do not hard-code port 22 if PowerFlow already knows a different port.

Resolution order should be explicit and deterministic, for example:

1. matching saved `srv` alias port;
2. guest-observed/listening sshd port when safely available;
3. default SSH port 22.

Display the resolved port in the single-VM view.

### What counts as an SSH connection

Count **established server-side SSH TCP transports**, not:

- the listening socket;
- unauthenticated SYNs;
- unrelated port-22 connections not owned by sshd when process ownership is available;
- PowerFlow's own temporary reachability probe.

The probe used to determine `SSH ready` must not inflate `CONN`.

### What counts as an SSH session

Count observable authenticated SSH session workloads such as:

- interactive shell / PTY;
- one-shot command/exec;
- SFTP/subsystem session.

Forward-only, agent-forwarding, X11, and other SSH protocol channels should **not** be silently counted as sessions.

If these are visible later, show them separately, e.g.:

```text
Forwarding     2 channels
Agent          1 channel
X11            0
```

but only from a backend that can prove those values.

### Privacy

Fleet view: counts only.

Single-VM explicit view may show remote source addresses and usernames because the operator explicitly selected one VM and asked for connection detail.

Still avoid displaying:

- environment variables;
- SSH keys/fingerprints unrelated to the explicit identity view;
- command arguments likely to contain secrets;
- authentication material;
- arbitrary process environments.

For `--json`, preserve the same privacy boundary; structured output is not permission to leak more.

### Failure / partial-state behavior

Examples:

```text
Agent          configured · not responding
SSH            ready
Connections    ? · guest telemetry unavailable
Sessions       ? · guest telemetry unavailable
```

or:

```text
Agent          available
SSH            closed
Connections    0
Sessions       0
```

Do not turn partial telemetry into a whole-command failure.

### Optional dedicated deep-dive alias

The individual status command should already provide the requested detail:

```powershell
pmx net 103 status
```

A future discoverability alias may be added without a second implementation:

```powershell
pmx net 103 ssh
```

→ same network model, SSH-focused rendering.

Do not require the extra subcommand for the useful details the user expects from a single-VM `status`.

### Tests

- fleet shows SSH `ready/closed/timeout/?`
- fleet shows connection/session counts only
- fleet does not show source addresses or usernames
- one established connection / one session
- one multiplexed connection / multiple sessions
- multiple SSH connections from same source
- multiple source addresses
- SFTP session
- one-shot exec session
- SSH forwarding without a shell session does not inflate session count
- external reachability probe does not inflate connection count
- custom SSH port from `srv`
- guest agent unavailable but TCP probe succeeds
- guest agent available but sshd closed
- stopped VM
- session-to-connection correlation unavailable
- privacy scrub for process arguments/environment
- `net` / `network` parity
- `-a` / `--all` parity
- JSON/table parity

---

## PF-FEAT-010 — DNS server role inside `server setup`

### PowerFlow-first entry point

```powershell
server setup --role dns
```

Interactive equivalent:

```powershell
server setup
```

→ role picker → **DNS server**.

This extends PF-FEAT-003 rather than creating a separate DNS installer command family.

### What this combines

The guided DNS role should own the common first-build sequence that otherwise requires remembering a chain such as:

```bash
sudo apt update
sudo apt install bind9 bind9-utils bind9-dnsutils
systemctl status bind9
```

and later the complementary recursive-resolver setup.

PowerFlow should not create wrappers for every `apt` invocation. The value is the **role workflow**:

```text
OS/package readiness
→ authoritative DNS package/tool install
→ service health
→ private-zone configuration
→ recursive resolver configuration
→ port-conflict validation
→ local query validation
→ client-enrollment handoff
```

### Recommended syntax

```powershell
server setup --role dns --name dns-lab
```

Optional explicit role profile:

```powershell
server setup --role dns --profile bind-unbound --name dns-lab
```

### Flags

| Flag | Function |
|---|---|
| `--role dns` | Select the DNS-server provisioning role without opening the role picker. |
| `--profile bind-unbound` | Select the BIND-authoritative + Unbound-recursive design. Do not silently substitute a different DNS architecture. |
| `--name <name>` | Set/confirm the server identity used by the workflow. Reuse the existing hostname/hosts safety logic rather than writing hostname files ad hoc. |
| `--zone <name>` | Supply the private authoritative zone, e.g. `lab.test`; if omitted, ask interactively before writing DNS configuration. |
| `--authoritative bind` | Explicitly select BIND as the authoritative service. Useful if additional authoritative backends are added later. |
| `--resolver unbound` | Explicitly select Unbound as the client-facing recursive/forwarding resolver. |
| `--dry-run` | Resolve package/service/config changes, show the proposed plan, but install/write/restart nothing. |
| `--resume` | Resume the saved provisioning workflow at the first incomplete verified stage. |
| `--from <stage>` | Start/re-run from an explicit stage such as `packages`, `bind`, `unbound`, `zone`, or `verify`; require confirmation before re-running mutating stages. |
| `--show-native` | Reveal translated native commands/config-file targets for learning/debugging; hidden by default. |

### Stage behavior

#### Packages

PowerFlow may run the distro-native package refresh/install through the Linux adapter, but the user-facing operation remains:

```text
DNS packages → install/verify
```

Do not turn `apt update` into a global PowerFlow package abstraction solely for this workflow.

#### BIND

Verify:
- package present;
- service available;
- configuration parses;
- intended authoritative listener does not collide with the recursive resolver;
- authoritative zone answers locally.

#### Unbound

Verify:
- service available;
- client-facing DNS listener is available;
- private-zone queries reach the authoritative layer;
- ordinary recursive queries still work according to the chosen policy.

Do not assume exact BIND/Unbound ports from a hard-coded tutorial. Derive them from the PowerFlow role profile/config and validate socket ownership before service restarts.

### Handoff

Successful server-side verification should end with the next PowerFlow action, e.g.:

```text
DNS server is answering directly.
Client machines are not enrolled yet.
Next: network dns enroll --interface <iface> --server dns-lab --zone <zone>
```

### Safety

- preview package installs and config-file writes;
- back up changed DNS config files;
- validate syntax before restarting services;
- verify listeners after restart;
- verify direct authoritative/resolver queries before calling the role complete;
- on failure, report the exact completed stage and preserve resumability;
- never rewrite `/etc/resolv.conf` directly when a managed resolver/network service owns it.

### Tests

- clean Debian install
- packages already installed
- package refresh failure
- BIND service failure
- Unbound service failure
- listener/port collision
- invalid zone name
- invalid generated config caught before restart
- direct authoritative lookup succeeds
- recursive lookup succeeds
- resume after failure/reboot
- dry-run performs zero mutations
- show-native does not expose secrets

---

## PF-FEAT-011 — `network dns`: simple DNS status, testing, and enrollment

### PowerFlow principle

The normal path must not require users to learn `nmcli`, `resolvectl`, NetworkManager property names, or a collection of PowerFlow flags.

Use short positional commands for common work. Advanced flags are optional escape hatches only.

### Preferred command surface

```powershell
nw dns
nw dns wg-home
nw dns wg-home use 192.168.1.30 for .test
nw dns temp wg-home 192.168.1.30 test
nw dns test mywebsite.test
nw dns test mywebsite.test dns-lab
nw dns undo wg-home
```

Canonical long form may remain `network dns ...`, but documentation and interactive help should lead with `nw`.

### Meaning

| Command | Meaning |
|---|---|
| `nw dns` | Show the useful DNS state for active connections. |
| `nw dns wg-home` | Show DNS state for one connection/link. |
| `nw dns wg-home use 192.168.1.30 for .test` | Persistently route `.test` DNS queries on `wg-home` to `192.168.1.30`. This is the normal setup path. |
| `nw dns temp wg-home 192.168.1.30 test` | Apply the same split-DNS routing only for the current runtime/session. |
| `nw dns test mywebsite.test` | Test the normal system resolver path used by applications. |
| `nw dns test mywebsite.test dns-lab` | Test the named DNS server directly without changing client configuration. |
| `nw dns undo wg-home` | Preview and restore the previous PowerFlow-recorded DNS state for that connection. |

### Persistent translation

This simple PowerFlow command:

```powershell
nw dns wg-home use 192.168.1.30 for .test
```

maps on NetworkManager systems to the equivalent of:

```bash
sudo nmcli connection modify wg-home ipv4.dns "192.168.1.30" ipv4.dns-search "~test"
```

PowerFlow owns the translation, verification, rollback metadata, and safe connection reactivation. The user should not need to know the native property names.

### Temporary translation

```powershell
nw dns temp wg-home 192.168.1.30 test
```

maps on systemd-resolved systems to the equivalent of:

```bash
sudo resolvectl dns wg-home 192.168.1.30
sudo resolvectl domain wg-home '~test'
```

`test` is interpreted as a routing-only DNS domain (`~test`) for this workflow.

### Smart defaults

- Persistent configuration is the default for `nw dns <link> <server> <zone>` because a connection profile is normally what the user intends to configure.
- Use `temp` when the user explicitly wants runtime-only state.
- Preserve unrelated DNS servers/domains unless the operation explicitly replaces them.
- Resolve a server name through known PowerFlow/server metadata when possible; otherwise accept a validated IP.
- If the connection must be bounced for changes to take effect and that could interrupt the current SSH/network path, warn and ask before doing it.
- After mutation, verify the effective resolver state and test a known/private name when available.

### Clean status

`nw dns` should combine the useful parts of `resolvectl status` and the owning connection manager into one compact view:

```text
🌐 DNS
────────────────────────────────────────────
LINK      DNS            DOMAIN    DEFAULT   SAVED
wlo1      10.35.103.61   —         yes       yes
wg-home   192.168.1.30   ~test     no        yes
```

`nw dns wg-home` expands details for that link.

### Optional expert flags

PowerFlow may still support advanced flags such as `--json`, `--dry-run`, and `--show-native`, but they must not be required for normal interactive use or dominate help output.

### Safety / verification

- Never edit managed resolver files directly when NetworkManager/systemd-resolved owns them.
- Preview destructive replacement if existing DNS state would be overwritten.
- Record rollback metadata for PowerFlow-managed changes.
- Re-read the resolver after applying changes; do not trust command exit status alone.
- Keep runtime and persisted state visibly distinct.
- Do not automatically reactivate a connection if doing so could sever the user's current session.

### Tests

- bare DNS status
- one-link DNS status
- simple persistent positional form
- simple temporary positional form
- direct server test
- system resolver test
- preserve unrelated DNS
- routing domain becomes `~test`
- persistent state survives reconnect/reboot where supported
- temporary state disappears appropriately
- safe reactivation warning
- undo/restore previous state
- `--json`, `--dry-run`, `--show-native` remain optional expert paths

---


---

## PF-FEAT-012 — simplified Linux operations: `network`, `svc`, and `sys`

### Goal

Replace repeated `nmcli`, `resolvectl`, `systemctl`, `loginctl`, `networkctl`, and common `journalctl` combinations with three job-oriented PowerFlow surfaces:

```powershell
network  # network + resolver state
nw       # short alias for network
svc      # systemd service/unit operations
sys      # host/user/session/systemd state
```

Do not shadow or replace the native tools. PowerFlow should aggregate them, normalize output, add safety around mutations, and always provide `--show-native` when the operator wants the translation.

#### Namespace collision rule

Do **not** make bare `net` the global PowerFlow command because Windows already owns `net.exe`. Use `network` as the cross-platform canonical namespace and `nw` as the convenience alias. A nested form such as `pmx net` is safe because it does not shadow the native executable.

### 1. `network` / `nw` — one network dashboard instead of correlating nmcli + resolvectl by hand

Bare:

```powershell
network
nw
network status
```

should combine active NetworkManager profiles, device/link state, addresses, default-route role, and resolver state:

```text
🌐 NETWORK
────────────────────────────────────────────────────────────────────
CONNECTION    TYPE        DEVICE   STATE      ADDRESS          DEFAULT   DNS
ss-SKY-72636  wifi        wlo1     connected  192.168.x.x     yes       10.35.103.61
wg-home       wireguard   wg-home  connected  10.x.x.x        no        —
lo            loopback    lo       connected  127.0.0.1       —         —

DNS
System resolver   systemd-resolved · stub
Current DNS       10.35.103.61 via wlo1
Private route     wg-home · no DNS scope
```

This is the PowerFlow-first replacement for the common pair:

```bash
nmcli connection show --active
resolvectl status
```

#### Network command surface

```powershell
net                         # combined dashboard
network active                  # active connections only
network links                   # device/link view
network <connection>            # one connection detail
network <connection> up
network <connection> down
network <connection> restart
network route                   # concise route/default-gateway view
network dns ...                 # existing PF-FEAT-011 resolver surface
network wifi                     # Wi-Fi status/current AP
network wifi list                # nearby APs when supported
network vpn                      # active VPN/WireGuard-style connections
network vpn <name> status
network vpn <name> up|down
network doctor                   # link → route → DNS health summary
```

#### `network` flags

| Flag | Function |
|---|---|
| `-a` / `--all` | Include inactive connections/devices in list views. Bare `network` stays focused on active state. |
| `-i <device>` / `--interface <device>` | Scope to one interface such as `wg-home` or `wlo1`. |
| `-c <name>` / `--connection <name>` | Scope to one NetworkManager connection profile when profile name and device name differ. |
| `-4` / `--ipv4` | Show/test IPv4 state only. |
| `-6` / `--ipv6` | Show/test IPv6 state only. |
| `--dns` | Add resolver details to an otherwise concise view. Bare `network` already includes the current DNS summary. |
| `--routes` | Add non-default routes; default output shows only the useful default/primary routing state. |
| `--temporary` | Runtime-only change where the underlying manager supports it. |
| `--persistent` | Persist through the owning network manager/profile. Never silently choose persistence. |
| `--dry-run` | Show current state, intended mutation, connectivity risk and verification with zero changes. |
| `--restore` | Restore the most recent PowerFlow-recorded network transaction for the targeted connection. |
| `--json` | Structured output. |
| `--show-native` | Show translated `nmcli`, `resolvectl`, `ip`, etc. commands. |

#### Network safety

`network <connection> down|restart` must detect when the connection appears to carry the current SSH/session path. If disrupting it could strand the user, show a strong warning and require explicit confirmation. Do not auto-reconnect by guessing another interface.

Mutations follow:

```text
resolve owner/profile → validate → preview → confirm → revalidate → execute → verify
```

### 2. `svc` — readable systemd service control

Preferred grammar:

```powershell
svc <unit> <action>
```

Examples:

```powershell
svc ssh status
svc NetworkManager restart
svc bind9 status
svc podman status --user
svc web-test status --user
```

Bare `svc` should show the services that need attention, not thousands of loaded units:

```text
⚙️ SERVICES
────────────────────────────────────────────────────
FAILED       0
ACTIVATING   0
RUNNING      37

RECENT / RELEVANT
ssh             running · enabled
NetworkManager  running · enabled
systemd-resolved running · enabled
```

#### Service command surface

```powershell
svc                         # health summary
svc list                    # concise service list
svc failed                  # failed units only
svc <name>                  # alias for status
svc <name> status
svc <name> start
svc <name> stop
svc <name> restart
svc <name> reload
svc <name> enable
svc <name> disable
svc <name> enable-now       # enable + start, one guarded plan
svc <name> disable-now      # disable + stop, one guarded plan
svc <name> logs             # delegates to the clean journal timeline
svc <name> logs <range>
svc <name> doctor           # status + enablement + recent warnings/errors
svc timers                  # useful systemd timers
svc sockets                 # active listening socket units
```

`svc <name>` should normalize `.service` automatically where unambiguous. Explicit unit suffixes remain accepted for `.socket`, `.timer`, `.mount`, etc.

#### `svc` flags

| Flag | Function |
|---|---|
| `--user` | Operate on the current user's systemd manager instead of PID 1/system services. Important for rootless Podman/Quadlet. |
| `-a` / `--all` | Include inactive/dead units in list views. |
| `--failed` | Limit list/status aggregation to failed units. |
| `--enabled` | Limit list views to enabled units. |
| `--disabled` | Limit list views to disabled units. |
| `--since <range>` | Recent service logs using PowerFlow's shared human time grammar. |
| `-f` / `--follow` | Follow service logs after the status header. |
| `--dry-run` | Preview mutations (`start`, `stop`, `restart`, `enable`, etc.) without executing. |
| `--json` | Structured status/list output. |
| `--show-native` | Show translated `systemctl`/`journalctl` calls. |

#### Service safety

- `status`, list, timers, sockets and logs are read-only.
- `start/reload/restart` are amber mutations.
- `stop`, `disable-now`, and restarting connectivity-critical units (SSH, NetworkManager, systemd-resolved, VPN-related services) must explicitly warn if the current remote session may be affected.
- `enable` and `disable` change boot policy and must show **current → proposed** enablement state.
- Never treat `active` and `enabled` as the same thing.

### 3. `sys` — login/session/systemd host state

This surface absorbs the small but useful `loginctl`, uptime/boot and systemd-manager queries that do not belong under `svc` or `net`.

#### Command surface

```powershell
sys                         # concise host/systemd/session dashboard
sys boot                    # boot time, uptime, boot ID shortened, previous boot availability
sys boots                   # available journal boots
sys sessions                # active login sessions
sys user                    # current user manager/session state
sys user <name>             # specified user state when permitted
sys linger                  # current user's linger state
sys linger on
sys linger off
sys errors                  # warning/error timeline for current boot
sys errors yd@12:00 t@12:00 # shared time grammar
```

Example:

```text
🖥️ SYSTEM
────────────────────────────────────────
Boot          2026-08-12 09:27 · 3d 13h
systemd       running
Sessions      2
User manager  active
Linger        yes
Failed units  0
```

#### `sys` flags

| Flag | Function |
|---|---|
| `--user <name>` | Target a specific user for session/linger inspection. Omit to use current user. |
| `-a` / `--all` | Include inactive sessions/users or extended properties where the view supports it. |
| `--current` | Restrict boot/error views to the current boot. Default for `sys errors`. |
| `--previous` | Use the previous boot for boot/error views. |
| `-p <level>` / `--priority <level>` | Journal priority filter for `sys errors`, e.g. `warning`, `err`. |
| `--dry-run` | Preview linger or other managed mutations. |
| `--json` | Structured state. |
| `--show-native` | Show translated `loginctl`, `journalctl`, `systemctl`, etc. |

#### Linger behavior

```powershell
sys linger
```

is the simple equivalent of querying the current user's `Linger` property.

```powershell
sys linger on
sys linger off
```

must preview the implication before changing it. `on` explains that the user's systemd manager can remain after logout/start at boot; `off` warns if running user services/Quadlets depend on it. This reuses the checks from `pdm doctor persistence` rather than creating duplicate linger logic.

### Shared human time grammar

Reuse the time parser already proposed for `pdm` and `journal` everywhere:

```powershell
svc ssh logs t@12:30 13:00
sys errors yd@23:00 t@01:00
journal ssh t@12:30 13:00
```

One parser, one interpretation of `t@`, `yd@`, ISO dates and cross-midnight validation.

### Interaction with existing backlog items

- `network dns` remains the DNS-specific sub-tree under the broader `net` command.
- `journal` remains the powerful evidence/timeline command; `svc <unit> logs` and `sys errors` are convenient front doors into the same implementation.
- `pdm doctor persistence` reuses `sys linger` checks/mutation rather than calling `loginctl` independently.
- `server setup` may call `network` / `nw`, `svc`, `sys`, and `pdm` stages internally, but should not duplicate their implementation.

### Tests

- NetworkManager active profiles joined correctly to resolver links by interface/device identity.
- Profile name differing from interface name.
- Active WireGuard profile with no DNS scope is visibly distinguishable from disconnected.
- `net -a` includes inactive profiles without changing defaults.
- network down/restart warns for likely current SSH path.
- `svc name` resolves `name.service` only when unambiguous.
- user/system unit separation.
- active vs enabled represented independently.
- service mutation dry-run and revalidation.
- service logs reuse journal parser.
- `sys linger` matches native user property.
- linger off warns when user services/Quadlets are active.
- current/previous boot filters.
- all mutations privacy-safe and auditable.

---

## PF-FEAT-013 — extend Linux simplification into storage, processes, ports, packages, firewall, hardware, and scheduled work

### Design principle

Do not create one PowerFlow command for every native Linux utility.

Prefer a small number of job-oriented views under the existing Linux namespaces:

```text
sys      host, storage, processes, users, hardware, packages
network  links, DNS, routes, ports, firewall exposure
svc      services, sockets, timers, scheduled units
```

Every view should:
- be useful bare;
- keep advanced/native detail behind flags;
- support `--json` where structured output is valuable;
- expose `--show-native` when PowerFlow translates into Linux-native commands;
- keep mutations previewed, confirmed, and verified;
- avoid hiding the underlying Linux concept in help text.

### Recommended additions

| Area | PowerFlow-first syntax | Useful flags | What it replaces / combines |
|---|---|---|---|
| Storage overview | `sys storage` | `-a/--all`, `--fs`, `--mounts`, `--usage`, `--json`, `--show-native` | `lsblk`, `df`, `findmnt` |
| One path/device | `sys storage <path|device>` | `--fs`, `--mounts`, `--usage`, `--parents` | `findmnt -T`, `lsblk`, filesystem lookup |
| Mounts | `sys mounts` | `-a/--all`, `--real`, `--fstab`, `--tree`, `--json` | `findmnt`, `/etc/fstab` inspection |
| Mount validation | `sys mounts doctor` | `--fstab`, `--dry-run`, `--show-native` | compare configured mounts with current mounts; detect missing targets/devices/options |
| Processes | `sys proc` | `-a/--all`, `--user <name>`, `--cpu`, `--ram`, `--tree`, `--json` | `ps`, selected `top`/`free`/`uptime` state |
| One process | `sys proc <pid|name>` | `--tree`, `--files`, `--ports`, `--env` (redacted), `--json` | process status + parent/child + optional file/socket context |
| Resource pressure | `sys load` | `--cpu`, `--ram`, `--swap`, `--io`, `--top <n>`, `--json` | uptime/load, memory, top consumers |
| Listening ports | `network ports` | `-a/--all`, `--listen`, `--established`, `--tcp`, `--udp`, `-4`, `-6`, `--process`, `--json` | `ss` |
| One port | `network port 22` | `--process`, `--connections`, `--json` | listening owner + established peers for one port |
| Exposure check | `network expose` | `--listen`, `--public`, `--localhost`, `--process`, `--json` | combine socket bind addresses with firewall state |
| Firewall status | `network firewall` | `--rules`, `--open`, `--zones`, `--json`, `--show-native` | firewalld/nftables adapter-specific inspection |
| Firewall change | `network firewall allow 8080/tcp` | `--zone <name>`, `--temporary`, `--persistent`, `--dry-run`, `--restore`, `--show-native` | guarded firewall mutation |
| Package health | `sys packages` | `--updates`, `--security`, `--installed`, `--manual`, `--json` | distro adapter over apt/dnf/etc. |
| Package lookup | `sys packages find <name>` | `--installed`, `--available`, `--json` | package search/query |
| Package update | `sys packages update` | `--check`, `--security-only` where supported, `--dry-run`, `--show-native` | distro-specific update workflow |
| Hardware overview | `sys hardware` | `--cpu`, `--ram`, `--pci`, `--usb`, `--storage`, `--network`, `--json` | lscpu, memory summary, lspci, lsusb, lsblk |
| Device detail | `sys hardware <device>` | `--driver`, `--firmware`, `--bus`, `--json` | udev/sysfs + adapter-specific hardware detail |
| Scheduled work | `svc timers` | `-a/--all`, `--user`, `--next`, `--failed`, `--json` | `systemctl list-timers` |
| Socket activation | `svc sockets` | `-a/--all`, `--user`, `--listening`, `--json` | `systemctl list-sockets` |
| Scheduled-job detail | `svc timer <name>` | `--user`, `--logs`, `--json` | timer + activated service + recent result |
| User overview | `sys users` | `-a/--all`, `--logged-in`, `--system`, `--json` | accounts + login/session overview |
| One user | `sys user <name>` | `--groups`, `--sessions`, `--linger`, `--services`, `--json` | id/groups/loginctl/user-manager state |
| Permissions diagnosis | `sys access <path>` | `--user <name>`, `--parents`, `--acl`, `--json` | ownership/mode/ACL/path traversal explanation |

### Suggested bare views

#### `sys storage`

```text
💾 STORAGE
────────────────────────────────────────────────────────────
DEVICE   FS     SIZE   USED   MOUNT
sda2     ext4   31G    8.2G   /
sda1     vfat   511M   7.1M   /boot/efi

Root usage     27%
Swap           4G · 0 used
Mount issues   none
```

Default should hide pseudo filesystems and implementation noise. `-a/--all` reveals them.

#### `sys proc`

```text
⚙️ PROCESSES
────────────────────────────────────────────────────────────
Load          0.18 · 0.09 · 0.05
CPU           4 cores · 3% busy
RAM           1.4G / 4.0G
Swap          0 / 4.0G

TOP
PID    USER   CPU   RAM    NAME
1221   you  2.1%  220M   podman
625    root   0.4%   31M   systemd-logind
```

#### `network ports`

```text
🔌 LISTENING PORTS
────────────────────────────────────────────────────────────
PROTO  ADDRESS        PORT   PROCESS     EXPOSURE
tcp    0.0.0.0        22     sshd        network
tcp    0.0.0.0        8080   rootless    network
tcp    127.0.0.53     53     resolved    localhost
udp    192.168.1.30   53     unbound     interface
```

PowerFlow should distinguish:
- localhost-only;
- one-interface bind;
- wildcard/public bind;
- established connections.

Do not call something "internet exposed" solely because it binds `0.0.0.0`; firewall/routing state must also support that conclusion.

### `network firewall` adapter model

Do not assume every Linux distribution uses the same firewall frontend.

Prefer an adapter that detects/supports the host's actual management layer, for example:
- firewalld when it is authoritative;
- nftables when directly managed;
- otherwise read-only unsupported state rather than silently mixing managers.

Mutations must:
1. identify the active firewall manager;
2. show current rule/exposure;
3. preview the exact requested delta;
4. confirm;
5. apply;
6. verify;
7. offer restore information when practical.

### Package-manager adapter

Keep package syntax stable across supported Linux distributions:

```powershell
sys packages --updates
sys packages find podman
sys packages update --check
```

Internally use the platform/distro adapter (`apt`, `dnf`, etc.).

Do not pretend package semantics are identical:
- unsupported concepts should be labelled unsupported;
- `--security-only` should only exist where PowerFlow can implement it correctly;
- package mutations should show what will be installed/upgraded/removed before confirmation.

### Process safety

Read-only process inspection is green.

Mutations such as future:

```powershell
sys proc <pid> stop
sys proc <pid> kill
```

should not be part of the first implementation.

If later added:
- `stop`/TERM and `kill`/KILL must be distinct;
- show PID, command, owner, age and parent before confirmation;
- re-resolve/revalidate PID identity immediately before signalling to avoid PID reuse races;
- never let an fzf selection silently send a destructive signal.

### Mount safety

Read-only mount inspection should come first.

If later supporting:

```powershell
sys mounts <target> mount
sys mounts <target> unmount
```

PowerFlow should:
- distinguish transient mount from `/etc/fstab` persistence;
- warn when target is busy;
- show dependent/submounts;
- never edit `/etc/fstab` without backup + validation;
- use UUID/LABEL where appropriate rather than unstable `/dev/sdX` names.

### Priority

Recommended implementation order inside this feature:

1. `network ports`
2. `sys storage`
3. `sys proc` / `sys load`
4. `svc timers` / `svc sockets`
5. `sys hardware`
6. `sys users` / `sys access`
7. `sys packages`
8. `network firewall`
9. only then consider mount/process/firewall mutations

The first six are largely read-only and immediately useful while establishing adapters and output conventions before more privileged mutation surfaces are introduced.

### Relationship to PF-FEAT-012

This extends PF-FEAT-012 rather than replacing it.

PF-FEAT-012 established:

```text
network / nw
svc
sys
```

PF-FEAT-013 fills those namespaces with additional Linux operations so PowerFlow grows by coherent categories instead of new top-level commands.

# PowerFlow-first command matrix

This is the preferred user-facing surface for the active post-reset backlog. Related backlog items are intentionally combined here so implementation can stay modular without exposing command sprawl.

| Area | PowerFlow-first command | Key flags and what they do | Combines |
|---|---|---|---|
| VM destruction + lifecycle | `pmx vm <vm> destroy` / `reboot` / `stop` / `reset` / `suspend` / `resume` | `--purge` remove related configuration after verified destroy; `--dry-run` preview only; `--force` only if deliberately added later and never default; `--show-native` reveal translation | PF-FEAT-001, PF-FEAT-002 |
| PMX inventory/status UX | `pmx list`, `pmx status` | `--json` structured output; `--table` stable table; typo suggestions never execute automatically | PF-UX-001, PF-UX-002 |
| Guided server build | `server setup` | `--role <podman|docker|media|dns|web|generic>` choose role; `--name <host>` desired server identity; `--resume` continue verified workflow; `--from <stage>` resume/re-run explicit stage; `--dry-run`; `--show-native` | PF-FEAT-003, PF-FEAT-010 |
| Podman event timeline | `pdm -e <range>` / `pdm --events <range>` | `t@`/`today@`, `yd@`/`yesterday@`, ISO date ranges; `--container <name>` filter; `--json`; `--raw` when native detail is needed | PF-FEAT-004 |
| Podman logs + inspect | `pdm logs <container>`, `pdm show <container>`, `pdm inspect <container>` | default logs = cleaned recent timestamps; numeric tail e.g. `100`; `-f` follow; `--full` all cleaned history; `--raw` no cleanup; time-range grammar shared with events; `--json` full structured inspect | PF-FEAT-005 |
| Linux incident timeline | `journal <range>` / `journal why <subject> <range>` | `--full` all entries with PF formatting; `--raw` native journal output; `-p <priority>` severity filter; subject selectors such as `ssh`, `podman`, service/container name | PF-FEAT-006 |
| Rootless Podman persistence | `pdm doctor persistence`, `pdm service <name> convert` | `--fix` preview+confirm safe persistence fixes such as linger; `--dry-run`; `--raw`/`--json` where applicable; service actions `status|restart|logs` reuse systemd/Podman model | PF-FEAT-007 |
| Fleet VM network/SSH | `pmx net -a status`, `pmx net <vm> status` | `-a`/`--all` fleet summary; `--json`; `--table`; `--ipv4`/`-4`; `--ipv6`/`-6`; single-VM view expands SSH connection/session detail | PF-FEAT-008, PF-FEAT-009 |
| DNS server role | `server setup --role dns` | `--profile bind-unbound`; `--zone <domain>`; `--authoritative bind`; `--resolver unbound`; `--name`; `--resume`; `--from`; `--dry-run`; `--show-native` | PF-FEAT-010 |
| Client DNS status/test/enroll | `network dns status`, `network dns test <name>`, `network dns enroll` | `--interface/-i`; `--server/-s`; `--zone/-z`; `--all-domains`; `--default-route`; `--temporary`; `--persistent`; `--dry-run`; `--restore`; `--json`; `--show-native`; `--port <n>` adds post-resolution TCP check | PF-FEAT-011 |

| Linux network/systemd simplification | `network` / `nw`, `svc`, `sys` | `network`: `-a/--all`, `-i/--interface`, `-c/--connection`, `-4/-6`, `--dns`, `--routes`, `--temporary/--persistent`, `--dry-run`, `--restore`; `svc`: `--user`, `--failed`, `--enabled/--disabled`, `--since`, `-f`, `--dry-run`; `sys`: `--user`, `--current/--previous`, `-p/--priority`, `--dry-run`; all support `--json` and `--show-native` where applicable | PF-FEAT-012 |
| Linux operations expansion | `sys storage`, `sys proc`, `sys load`, `sys packages`, `sys hardware`, `sys users`, `sys access`; `network ports`, `network firewall`; `svc timers`, `svc sockets` | Shared `-a/--all`, `--json`, `--show-native`; area flags include `--fs`, `--mounts`, `--usage`, `--cpu`, `--ram`, `--tree`, `--listen`, `--established`, `--process`, `--updates`, `--security`, `--user`, `--next`; mutations add `--dry-run`/`--restore` where supported | PF-FEAT-013 |

## Syntax principles

- VM operations prefer `pmx vm <id|name> <command>` where the action naturally belongs to one VM.
- Fleet/network operations use `pmx net ...` because their subject is the node-wide network estate, not one VM.
- Cross-context provisioning uses `server setup`, never `pmx`, because it must survive Proxmox → guest → SSH handoffs.
- Podman ergonomics live under `pdm`.
- Linux system evidence lives under `journal`.
- DNS client configuration lives under `network dns`; DNS-server provisioning is a `server setup` role.
- Long PowerFlow word flags use `--word`; short aliases are single letters only when useful and unambiguous.

---

### DNS syntax refinement — intent-first wording

Preferred common form:

```powershell
nw dns wg-home use 192.168.1.30 for .test
```

Interpretation: on `wg-home`, use DNS server `192.168.1.30` for the `.test` namespace.

PowerFlow should treat persistence as the normal/default behavior for this command. The words `use` and `for` are part of the human-readable grammar and should normalize internally to the existing persistent NetworkManager + systemd-resolved workflow.

Useful variants:

```powershell
nw dns wg-home use dns-lab for .test
nw dns wg-home show
nw dns wg-home undo
```

Avoid making users learn `--interface`, `--server`, `--zone`, `--persistent`, `ipv4.dns`, `ipv4.dns-search`, or the `~test` routing-domain syntax for the normal case. Advanced flags may remain available only as optional expert controls.


---

## PF-UX-003 — restore standard word navigation, deletion, and keyboard selection

### Problem

Inside PowerFlow's interactive shell experience, common editing chords are not behaving as expected:

```text
Ctrl+Left / Ctrl+Right        move by one word
Ctrl+Del                      delete the next word
Ctrl+Shift+Left / Right       extend selection by one word
Delete / Backspace            remove the selected text
```

`Fn+Arrow` currently works as a broader navigation mechanism, but it is too coarse for normal command-line editing.

### PowerFlow expectation

PowerFlow should preserve familiar terminal/readline-style text editing rather than requiring users to learn PowerFlow-specific navigation keys.

Required behavior:

- `Ctrl+Left` moves to the previous word boundary.
- `Ctrl+Right` moves to the next word boundary.
- `Ctrl+Del` deletes the word ahead of the cursor.
- `Ctrl+Backspace` should also delete the word behind the cursor where the host terminal/line editor supports it, for symmetry.
- `Ctrl+Shift+Left` extends the current selection one word to the left.
- `Ctrl+Shift+Right` extends the current selection one word to the right.
- `Delete` or `Backspace` removes the active selection.
- typing while text is selected replaces the selection.
- existing `Fn+Arrow`, Home/End, normal arrows, history navigation, completion, and copy/paste bindings must continue to work.

### Implementation approach

Treat this as an input/editor integration issue, not as a PowerFlow command.

PowerFlow should:

1. determine which line editor is active (for example PSReadLine in PowerShell);
2. avoid overriding native terminal selection/navigation when the terminal already owns the key chord;
3. register explicit line-editor handlers only where PowerFlow currently breaks or masks the expected behavior;
4. keep bindings behind the platform/input adapter so Windows Terminal, Linux terminals, SSH sessions, and differing keyboard layouts can be handled without hard-coded assumptions;
5. never make these bindings dependent on `fzf` or another optional tool.

### Selection model

Keyboard selection should behave like a normal text editor:

```text
cursor movement                → clears/changes selection normally
Ctrl+Shift+Arrow               → expands or shrinks selection by word
Delete / Backspace             → deletes selection
printable input                → replaces selection
Left / Right after selection   → collapse selection to the relevant edge
```

Do not fake selection by rewriting the command buffer with visible markers. Use the line editor's real selection APIs when available.

### Safety / compatibility

- Do not shadow terminal-level copy/paste chords.
- Do not assume all terminals emit the same escape sequence for modified arrows.
- When a terminal cannot expose a requested chord distinctly, leave the native behavior intact and report the limitation in diagnostics/help rather than installing a risky global remap.
- Noninteractive shells are unaffected.

### Suggested diagnostics

A future input diagnostic can expose effective bindings without requiring users to know PSReadLine internals:

```powershell
pf doctor keys
```

Example output:

```text
KEY EDITING
Ctrl+Left           word-left       ✓
Ctrl+Right          word-right      ✓
Ctrl+Del            delete-word     ✓
Ctrl+Shift+Left     select-word      ✓
Ctrl+Shift+Right    select-word      ✓
```

This diagnostic is optional; restoring the expected editing behavior is the priority.

### Tests

- Ctrl+Left/Right across whitespace, punctuation, paths, flags, and quoted arguments.
- Ctrl+Del at start/middle/end of a command.
- Ctrl+Backspace symmetry where supported.
- Ctrl+Shift+Left/Right selection growth and shrinkage.
- Delete and Backspace remove selected text.
- printable input replaces selected text.
- bindings do not break history, completion, copy/paste, Home/End, or Fn+Arrow.
- behavior over local Windows Terminal, local Linux terminal, and SSH where supported by the terminal/line editor.
- no effect in redirected/noninteractive sessions.

# Reset rule

This file is cumulative.

Do not clear or reset it again until the user explicitly confirms the current backlog has been copied/pushed and asks for a reset.
