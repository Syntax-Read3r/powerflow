# PowerFlow Backlog

> **Cumulative working log**
>
> This file is the single running backlog for PowerFlow additions, bugs, regressions, and UX fixes collected in this chat.
> **Do not reset or clear this file until the user explicitly confirms that a copy has been made and asks for the backlog to be reset.**
>
> Last updated: 2026-08-10

---

## Status key

- **BUG** — behaviour is broken or contradicts the documented/expected command contract.
- **UX** — command works as designed, but a more convenient or clearer route should be added.
- **FEATURE** — additive capability.
- **INVESTIGATE** — evidence strongly suggests a defect, but the exact failing layer still needs instrumentation.

---

# File operations and permissions

## PF-FEAT-001 — `rn --chmod <mode>`

### Goal

Allow a rename and POSIX permission change to be performed as one workflow.

### Proposed syntax

```powershell
rn wg-home.conf --chmod 600
rn --chmod 600
```

The second form preserves normal interactive `rn` behaviour:

1. Pick the file with the existing picker.
2. Choose the new name.
3. Validate the destination.
4. Rename.
5. Apply the requested POSIX mode to the **new path**.
6. Verify the resulting mode.
7. Print the final result.

### Recommended output

```text
✓ Renamed
  wg.conf → wg-home.conf

✓ Permissions
  600  rw-------
```

### Failure behaviour

If the rename succeeds but chmod fails, do **not** silently roll the rename back. Report the partial success and give the exact recovery command.

```text
✓ Renamed: wg.conf → wg-home.conf
✗ Could not set permissions to 600

Run:
  chmod 600 ./wg-home.conf
```

### Platform rule

Numeric chmod modes are POSIX semantics. On Windows, do not pretend NTFS ACLs are equivalent. Return a clear unsupported-platform message unless a separate ACL-aware feature is deliberately designed.

### Design note

Prefer the long PowerFlow-specific flag `--chmod`. Do not advertise `-cm` unless there is a deliberate short-flag policy for it.

### Tests

- direct rename + chmod
- interactive picker + chmod
- rename succeeds / chmod fails
- invalid mode
- destination collision
- path containing spaces
- Linux success
- Windows explicit unsupported behaviour
- verification uses the renamed path, not the old path

---

## PF-FEAT-002 — `ls --perms`

### Goal

Add a permission-focused listing rather than merely duplicating GNU `ls -l`, which PowerFlow already supports.

### Proposed syntax

```powershell
ls --perms
ls --perms -a
```

### Proposed view

```text
PERM        MODE  NAME
rw-------   600   wg-home.conf
rw-r--r--   644   notes.md
rwxr-xr-x   755   install.sh
drwxr-xr-x  755   scripts/
```

Optionally flag obviously risky modes:

```text
rwxrwxrwx   777   deploy.sh       ⚠ world-writable
```

### Relationship to existing commands

- `ls -l` / `ls -la` remains GNU-style long listing.
- `ls --perms` is a compact PowerFlow permission view.
- `perms <path>` remains the detailed explanation/teaching command.

### Tests

- files and directories
- hidden files with `-a`
- symlinks
- executable bits
- setuid/setgid/sticky bits if supported
- filenames with spaces/unicode
- Windows behaviour explicitly defined rather than faked

---

# Proxmox / PMX

## PF-BUG-001 — `pmx disk list` leaks a raw empty-array binding exception

### Reproduction

```powershell
pmx disk list
```

### Actual result

```text
Show-PmxManagedVmDisks: .../components/proxmox/command.ps1:218
Cannot bind argument to parameter 'Arguments' because it is an empty array.
```

### Diagnosis

The dispatcher routes `pmx disk list` into the managed VM disk command and attempts to derive a command tail after `list`. When no further arguments exist, an empty array reaches a parameter path that rejects it.

This is a PowerFlow dispatcher/parser defect, not a Proxmox or Fedora failure.

### Expected behaviour

Missing VM should mean **unspecified**, not parser failure.

Interactive terminal:

```text
pmx disk list
    ↓
VM picker
    ↓
show selected VM disks
```

Non-interactive / redirected session:

```text
❌ No VM selected.
Use: pmx disk list --vm <name|vmid>
```

No raw `ParameterBindingException` should reach the user.

### Fix direction

- Allow an empty command tail at the dispatch boundary.
- Resolve the VM after parsing output flags.
- Reuse the existing managed-VM resolver/picker rather than special-casing this command.
- Preserve ambiguity errors when the user supplies conflicting selectors.

### Regression tests

```text
pmx disk list
pmx disk list --table
pmx disk list --json
```

Run each in:
- interactive terminal with fzf available
- interactive terminal without fzf
- redirected/non-interactive output

---

## PF-BUG-002 — `pmx disk list --vm <vm> --table` returns `malformed JSON` for a valid VM

### Reproduction

```powershell
pmx disk list --vm 102 --table
```

Also observed repeatedly with:

```powershell
pmx disk list --table
```

### Actual result

```text
❌ Proxmox returned malformed JSON.
```

### Native control case

The same Proxmox host returns valid VM data directly:

```text
qm list
  102 docker-host running 8192 100.00 ...

qm config 102
  ide2: none,media=cdrom
  scsi0: local-zfs:vm-102-disk-1,discard=on,iothread=1,size=100G
```

Therefore VM `102` exists and has a normal attached virtual disk.

### Expected result

A table similar to:

```text
💽 VM DISKS — 102 docker-host
──────────────────────────────────────────────
DISK      ROLE       SIZE      STORAGE
scsi0     boot       100 GiB   local-zfs
```

`ide2: none,media=cdrom` should not be presented as a growable data disk. It can either be excluded from the default disk table or displayed separately as an empty CD-ROM device.

### Investigation direction

Capture the transport result **before** JSON parsing.

Potential failure classes:

- stdout contaminated by warnings/banners/progress text
- stderr incorrectly merged into stdout
- empty response
- multiple JSON documents concatenated
- adapter returning native text where JSON was expected
- encoding/newline issue
- local and SSH adapters returning different shapes
- output formatter accidentally influencing the transport request

### Required diagnostic improvement

Do not collapse all parser failures into only:

```text
❌ Proxmox returned malformed JSON.
```

For debug mode, retain scrubbed evidence such as:

```text
Command class: managed-vm-disks
Exit code: ...
stdout bytes: ...
stderr bytes: ...
Transport: local|ssh
Parser: json
```

Never include secrets or unsanitized private endpoints in the diagnostic record.

### Regression tests

Known-good fixtures should cover at least:

- VM with one `scsi0` data disk
- VM with `scsi0` plus empty `ide2` CD-ROM
- template disk
- stopped VM
- running VM
- local transport
- remote `srv` transport
- `--table`
- `--json`

---

## PF-BUG-003 — VM target resolution changes when output flags are present

### Observed behaviour

In one session:

```powershell
pmx disk list
```

crashed with an empty-array binding exception, while:

```powershell
pmx disk list --table
```

successfully selected/resolved VM `100 debian13-base` once before later malformed-JSON failures.

### Problem

Output formatting flags such as `--table` or `--json` must not alter whether a VM target is considered present, absent, or selectable.

### Expected invariant

Target resolution should be independent of output format:

1. Parse selectors and format flags separately.
2. Resolve explicit VM if supplied.
3. If no VM supplied:
   - interactive → picker
   - non-interactive → clean usage error
4. Fetch data.
5. Format result as default/table/json.

### Tests

Matrix:

```text
pmx disk list
pmx disk list --table
pmx disk list --json
pmx disk list --vm 100
pmx disk list --vm 100 --table
pmx disk list --vm 100 --json
```

All equivalent commands must resolve the same VM before formatting.

---

## PF-UX-001 — convenience alias `pmx start <vm>`

### Observation

```powershell
pmx start 101
```

currently returns:

```text
❌ Unknown pmx command 'start'. Run: pmx help
```

The documented canonical command is:

```powershell
pmx vm start 101
```

So this is not a parser bug; it is a convenience gap.

### Proposal

Add additive top-level convenience routes:

```powershell
pmx start 101
pmx shutdown 101
```

mapping internally to:

```powershell
pmx vm start 101
pmx vm shutdown 101
```

Keep the `pmx vm ...` implementation canonical so mutation logic, confirmation, dry-run, verification, and audit behaviour remain centralized.

Do not create duplicate mutation implementations.

---

## PF-UX-002 — `pmx vm disks [vm]`

### Goal

Match the natural operator workflow:

```text
show VMs → choose VM → show its disks
```

### Proposed syntax

```powershell
pmx vm disks 102
pmx vm disks
```

- `pmx vm disks 102` → convenience route to managed VM disk listing.
- bare `pmx vm disks` → existing VM picker when interactive.
- canonical script-friendly command remains:

```powershell
pmx disk list --vm 102
```

### Reason

Physical disk commands and VM virtual-disk commands currently share the `pmx disk` namespace. A VM-scoped convenience route makes intent clearer without breaking existing syntax.

---

## PF-BUG-004 — network commands fail runtime-status read for VMs already known to be running

### Reproduction

VM inventory shows both VM `101` and `102` as running:

```text
100 debian13-base   stopped
101 debian13-lab    running
102 docker-host     running
```

Yet:

```powershell
pmx vm ip 102
pmx vm net 102
pmx vm net 101
```

produce output containing:

```text
Status        running
Agent         unavailable
...
No addresses match the selected filters.
...
⚠ Current VM status could not be read; VM-reported network data was not queried.
```

### Why this is a bug

The same rendered view simultaneously states:

```text
Status running
```

and:

```text
Current VM status could not be read
```

That indicates two separate status sources or a failed runtime-detail path being collapsed into contradictory UI state.

Because the runtime status lookup fails, PowerFlow never reaches the guest-agent network query, so `pmx vm ip` cannot discover addresses even when the VM itself is running.

### Control case

`pmx vm` successfully identifies the same VMs as running.

Native `qm list` also reports:

```text
101 debian13-lab  running
102 docker-host   running
```

### Fix direction

Separate these concepts internally:

```text
inventory state
runtime-detail state
guest-agent configured state
guest-agent reachable state
guest-agent query state
```

Do not use one generic `Status`/`Agent` field to hide which stage failed.

Suggested flow:

1. Resolve VM.
2. Read inventory status.
3. Read authoritative runtime status/details.
4. If running, query guest-agent configuration/reachability.
5. If agent is reachable, query interfaces/addresses.
6. Correlate reported interfaces to configured adapters.
7. Render explicit partial-state information when any stage fails.

### Required diagnostics

When runtime detail fails, retain a scrubbed diagnostic reason:

```text
runtime-status:
  transport: local
  exit-code: ...
  parser: ...
  stdout-bytes: ...
  stderr-bytes: ...
```

The user-facing default can stay concise, but debug output must make the failing layer observable.

### Regression tests

At minimum:

- running VM with guest agent enabled and reachable
- running VM with agent enabled but service unavailable
- running VM with agent disabled
- stopped VM
- runtime-status read failure
- agent query malformed response
- local transport
- remote SSH transport

Assertions:

- a VM cannot simultaneously be shown simply as `Status running` and then generically claimed to have unreadable status without qualification
- agent query is attempted only when its prerequisites are satisfied
- failure of runtime detail does not get mislabeled as guest-agent unavailability
- `pmx vm ip` and `pmx vm net` share the same status semantics

---

## PF-UX-003 — make guest-agent state precise instead of `unavailable` / `not-requested` ambiguity

### Observed outputs

`pmx vm net 101`:

```text
Agent unavailable
```

`pmx vm nic 101`:

```text
Agent not-requested
```

The second is reasonable because adapter-only output does not need the guest agent. The first is ambiguous because the accompanying warning says the agent was **not queried due to a runtime-status failure**.

### Problem

`unavailable` currently risks meaning several materially different things:

- agent feature not configured
- agent configured but VM stopped
- agent configured but service not responding
- query skipped because runtime status could not be read
- query attempted but transport/parser failed

These should not be conflated.

### Proposed states

Use explicit states such as:

```text
Agent  not-requested
Agent  not-configured
Agent  skipped · runtime status unavailable
Agent  configured · not responding
Agent  available
Agent  query-failed
```

The exact vocabulary can be shortened, but the cause must remain visible.

### Benefit

This turns `pmx vm ip` from a dead-end message into actionable diagnosis.

---

# Cross-cutting PMX reliability work

## PF-INVESTIGATE-001 — centralize managed-command response parsing and diagnostics

Multiple PMX failures now point toward weak visibility at the transport/JSON boundary:

- managed VM disk listing reports malformed JSON
- network runtime-status lookup fails despite valid inventory status
- UI currently collapses underlying failures into generic messages

### Proposal

Create one shared managed-response boundary that owns:

1. command execution
2. stdout/stderr separation
3. exit-code capture
4. privacy scrubbing
5. JSON validation
6. typed error classification
7. optional debug record
8. user-facing error translation

Example internal error classes:

```text
TransportUnavailable
NativeCommandFailed
EmptyResponse
MalformedJson
UnexpectedSchema
VmNotFound
AgentUnavailable
PermissionDenied
```

This is preferable to each PMX read command independently doing `ConvertFrom-Json` and printing a generic error.

### Safety

Debug records must preserve PowerFlow's privacy rules:
- no password material
- no raw `user@host`
- no unsanitized saved endpoints
- no secrets from command output
- alias-first presentation

---

# Suggested implementation order

1. **PF-BUG-005** — fix the shared guarded-mutation empty `NativeCommand` contract; this may block the entire mutation surface.
2. **PF-BUG-001** — trivial/high-confidence `pmx disk list` parser crash.
3. **PF-BUG-002** — instrument and fix managed disk response parsing.
4. **PF-BUG-004** — trace/fix runtime status and guest-agent query path.
5. **PF-BUG-003** — lock target-resolution invariants with tests.
6. **PF-UX-003** — precise agent/status state rendering.
7. **PF-INVESTIGATE-001** — consolidate the response/diagnostic boundary while fixing the above.
8. **PF-UX-004** — add `pmx vm config` and targeted `pmx config <vm>` hint.
9. **PF-UX-002** — `pmx vm disks`.
10. **PF-UX-001** — top-level lifecycle convenience aliases.
11. **PF-FEAT-003** — clone-and-configure workflow.
12. **PF-FEAT-001** — `rn --chmod`.
13. **PF-FEAT-002** — `ls --perms`.

---


---

## PF-FEAT-003 — clone-and-configure VM in one guarded PowerFlow workflow

### Native workflow being replaced

```bash
qm clone 100 103 --name web-prod --full 1
qm set 103 --cores 2 --memory 4096
qm resize 103 scsi0 +8G
qm config 103
```

### Goal

Turn the common "clone → size CPU/RAM → grow boot disk → inspect final config" sequence into one PowerFlow command while preserving PowerFlow's preview / confirm / revalidate / verify safety model.

### Recommended syntax

```powershell
pmx vm clone 100 web-prod --vmid 103 --cores 2 --memory 4G --grow-by 8G --show
```

Equivalent using automatic VMID allocation:

```powershell
pmx vm clone 100 web-prod --cores 2 --memory 4G --grow-by 8G --show
```

The second form should remain the preferred/default PowerFlow experience because PowerFlow already knows how to allocate the next VMID automatically.

### Why `--vmid` should be optional

PowerFlow's current clone UX deliberately removes unnecessary tokens and auto-selects the VMID.

An explicit numeric `--vmid` is still useful when:
- the operator wants a known ID for automation/documentation;
- another system expects a specific VMID;
- migrating an existing native `qm clone` workflow.

Rules:

```text
--vmid omitted    → allocate authoritative next free VMID
--vmid 103        → use 103 only if currently free
--vmid occupied   → refuse before mutation
```

Do not reintroduce a meaningless `--new-vmid auto` flag.

### Why `--grow-by 8G` instead of overloading existing disk-grow semantics

Current PowerFlow virtual-disk growth is intentionally expressed as a **final size** for safety.

For clone workflows, the operator commonly thinks in terms of:

```text
clone source disk
then add 8 GiB
```

So expose the delta explicitly as:

```powershell
--grow-by 8G
```

Internally PowerFlow should:

1. read the cloned VM's eligible boot/data disk after clone;
2. determine its current size;
3. calculate the final target size;
4. show both values in the preview;
5. call the existing guarded disk-grow implementation with the **final size**.

Example:

```text
Disk
  scsi0   32 GiB → 40 GiB   (+8 GiB)
```

This preserves the existing safety invariant instead of teaching the disk-grow layer to accept ambiguous relative sizes everywhere.

If multiple growable disks exist, the combined clone workflow must refuse to guess unless an explicit slot is supplied:

```powershell
pmx vm clone 100 web-prod --grow-by 8G --disk scsi0
```

### Memory syntax

Accept human-readable IEC sizes:

```powershell
--memory 4G
--memory 4096M
--memory 4GiB
```

Normalize internally to the existing managed-memory path.

Do not require native Proxmox MiB-only vocabulary from the user.

### Proposed preview

```text
🧬 CLONE VM
────────────────────────────────────────
Source       100 debian13-base
Target       103 web-prod
Clone mode   full

CPU
  cores      2

Memory
  4 GiB

Disk
  scsi0      32 GiB → 40 GiB   (+8 GiB)

After clone
  show final configuration

This will create and modify VM 103.
Continue? [y/N]
```

### Execution model

Do not shell out to one compound command string.

Use the existing guarded PMX operations in sequence:

```text
resolve source
    ↓
resolve/allocate target VMID
    ↓
validate all requested settings
    ↓
preview entire transaction
    ↓
confirm once
    ↓
revalidate source + target VMID
    ↓
clone
    ↓
verify clone exists
    ↓
set CPU
    ↓
verify CPU
    ↓
set memory
    ↓
verify memory
    ↓
resolve eligible disk
    ↓
grow disk to calculated final size
    ↓
verify disk size
    ↓
show final config
```

Each mutation still uses its existing allow-listed implementation.

### Partial-failure behaviour

This is **not an atomic transaction**. If clone succeeds and a later step fails, do not delete the VM automatically.

Report exactly what succeeded and what remains:

```text
✓ Cloned 100 → 103 web-prod
✓ CPU set to 2 cores
✓ Memory set to 4 GiB
✗ Disk growth failed

VM 103 was kept.

Continue manually:
  pmx disk grow 103 40G
  pmx vm show 103
```

Automatic destructive rollback after a successful clone is too risky.

### `--dry-run`

The whole workflow must support:

```powershell
pmx vm clone 100 web-prod --cores 2 --memory 4G --grow-by 8G --dry-run
```

Dry-run should:
- resolve the source;
- resolve or propose the VMID;
- inspect the source disk layout;
- calculate the target final disk size;
- validate all values;
- print the complete plan;
- perform **zero mutations**.

### `--show`

`--show` should print the final managed VM configuration after all requested mutations verify successfully.

Without `--show`, the success footer should still give the obvious next step:

```text
✓ VM 103 web-prod is ready.

  pmx vm show 103  ·  pmx vm net 103  ·  pmx vm start 103
```

### Optional future shorthand

Once the long-form options are stable, a convenience alias could be considered:

```powershell
pmx clone 100 web-prod --cores 2 --memory 4G --grow-by 8G
```

but `pmx vm clone` should remain canonical internally.

### Regression tests

At minimum:

- source by VMID
- source by name
- automatic VMID
- explicit free VMID
- explicit occupied VMID
- invalid CPU count
- invalid memory size
- single eligible disk + relative growth
- multiple eligible disks without `--disk` → refuse
- multiple eligible disks with explicit `--disk`
- clone succeeds / CPU mutation fails
- clone succeeds / memory mutation fails
- clone succeeds / disk growth fails
- `--dry-run` performs no mutation
- `--show` reads final authoritative config
- interrupted/non-interactive confirmation behaviour
- audit record contains no secrets/endpoints

### Documentation example

```powershell
# Native Proxmox:
# qm clone 100 103 --name web-prod --full 1
# qm set 103 --cores 2 --memory 4096
# qm resize 103 scsi0 +8G
# qm config 103

# PowerFlow:
pmx vm clone 100 web-prod --vmid 103 --cores 2 --memory 4G --grow-by 8G --show
```



---

## PF-BUG-005 — guarded PMX mutations fail when native-command display is hidden

### Severity

**High / systemic**

This is not limited to `pmx vm start`.

### Reproduction

```powershell
pmx vm start 103
```

### Actual result

```text
Confirm-PmxAmberPlan: .../components/proxmox/vm-change.ps1:67
Cannot bind argument to parameter 'NativeCommand' because it is an empty string.
  ⛔ Cancelled — no Proxmox state was changed.
```

Native control:

```bash
qm start 103
```

succeeds.

### Confirmed root cause

The shared guarded-mutation path deliberately hides the native command unless native output is enabled:

```powershell
$showNative = $Session.Config.ShowNative -or $Options.ContainsKey('ShowNative')
$native = if ($showNative) { "$($preview.NativeCommand)" } else { '' }
```

It then calls:

```powershell
Confirm-PmxAmberPlan ... -NativeCommand $native
```

But `Confirm-PmxAmberPlan` declares:

```powershell
[Parameter(Mandatory)][string]$NativeCommand
```

without `[AllowEmptyString()]`.

PowerShell therefore rejects the intentionally-hidden empty string **before the confirmation function can run**.

Inside `Confirm-PmxAmberPlan`, the implementation already treats the field as optional for display:

```powershell
if ($NativeCommand) {
    Write-PmxField 'Native' ...
}
```

So the parameter contract contradicts the implementation.

### Impact

Because `Invoke-PmxAmberMutation` is shared by guarded VM changes, this defect may affect every mutation routed through it when `ShowNative` is false, including:

- VM start
- VM shutdown
- CPU changes
- memory changes
- clone operations
- other guarded mutations using the same helper

This must be tested across the entire mutation surface rather than fixed only at the `start` call site.

### Fix

Preferred:

```powershell
function Confirm-PmxAmberPlan {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Fields,
        [AllowEmptyString()][string]$NativeCommand = '',
        [string[]]$Warnings = @(),
        [switch]$DryRun
    )
```

Alternatively, omit `-NativeCommand` entirely when native display is disabled, but that requires making the parameter optional anyway.

Do **not** solve this by turning native command display back on by default. Native command hiding is deliberate PowerFlow behaviour.

### Required invariant

These two invocations must differ only in whether the native command is shown:

```powershell
pmx vm start 103
pmx vm start 103 --show-native
```

Both must reach the same confirmation, revalidation, execution, and verification path.

### Regression tests

For every guarded mutation:

```text
default ShowNative=false
explicit --show-native
--dry-run
confirmation accepted
confirmation declined
redirected/non-interactive session
```

At minimum cover:

```powershell
pmx vm start <vm>
pmx vm shutdown <vm>
pmx vm cpu set <vm> --cores 2
pmx vm memory set <vm> --size 4G
pmx vm clone <source> <name>
pmx disk grow <vm> <size>
```

Assertions:

- no parameter-binding exception
- hidden native command remains hidden
- `--show-native` reveals it
- mutation semantics are identical
- audit behaviour is unchanged

---

## PF-UX-004 — provide a VM-config route and a targeted hint for `pmx config <vmid>`

### Reproduction / operator expectation

After using native:

```bash
qm config 103
```

the natural PowerFlow attempt was:

```powershell
pmx config 103
```

### Actual result

```text
❌ Unknown config action '103'. Run: pmx help config
```

### Classification

This is **not currently a parser bug** because top-level:

```powershell
pmx config ...
```

is already the PowerFlow configuration namespace.

However, `qm config <vmid>` is common Proxmox muscle memory, so the current error should be more useful.

### Recommended command

Add:

```powershell
pmx vm config 103
```

as an alias for:

```powershell
pmx vm show 103
```

`pmx vm show` should remain canonical internally.

### Targeted error hint

If the first argument to top-level `pmx config` looks like a VMID or resolvable VM name, return:

```text
❌ `pmx config` manages PowerFlow/PMX settings.

Did you mean:
  pmx vm config 103
  pmx vm show 103
```

Do not silently reinterpret `pmx config 103` as VM configuration because that overloads an established namespace and could become ambiguous as PMX configuration grows.

### Expected VM-config view

The managed PowerFlow view should expose the useful equivalent of:

```bash
qm config 103
```

without forcing raw Proxmox vocabulary unless requested.

Example:

```text
🧱 VM CONFIG — 103 web-prod
────────────────────────────────────────────
Status       running
CPU          2 cores · x86-64-v2-AES
Memory       4 GiB
Firmware     UEFI
Machine      q35
Agent        enabled

DISKS
scsi0        40 GiB · local-zfs · boot
efidisk0     1 MiB · EFI
ide2         empty CD-ROM

NETWORK
net0         virtio · vmbr0 · firewall on
```

Then:

```text
--show-native
```

may reveal raw slot/config details where useful.

### Tests

- `pmx vm config 103`
- `pmx vm config web-prod`
- alias parity with `pmx vm show`
- `pmx config 103` gives targeted hint
- `pmx config show` continues to mean PMX settings
- VM name that resembles a config setting does not get silently rerouted

---

## Evidence update — VM 103 native operations are healthy

The following native operations succeeded on the same Proxmox host:

```bash
qm clone 100 103 --name web-prod --full 1
qm config 103
qm resize 103 scsi0 +8G
qm start 103
```

Observed resulting disk:

```text
scsi0: local-zfs:vm-103-disk-1,...,size=40G
```

This strengthens the conclusion that the corresponding PMX failures are PowerFlow-side rather than failures of the VM, storage, or Proxmox host.


---

## PF-FEAT-004 — Linux/VM identity + storage view in `pc-whoami`

### Native workflow being replaced

```bash
hostname
hostnamectl
lsblk -f
df -hT
```

### Goal

Make `pc-whoami` useful inside Linux guests and servers, not just as a hardware-oriented host-health command.

The command should answer, in one readable screen:

- what machine am I on?
- is it physical or virtual?
- which OS/kernel/architecture is running?
- what firmware/platform information is useful?
- what disks/partitions/filesystems exist?
- what is actually mounted?
- how much space is used/free on real filesystems?

Do not create a separate top-level command for this. `pc-whoami` already owns machine identity/health.

### Recommended bare Linux/VM view

```text
🖥️  DEBIAN13-BASE
──────────────────────────────────────────────────────────────
  Hostname       debian13-base
  OS             Debian GNU/Linux 13 (trixie)
  Kernel         Linux 6.12.94+deb13-amd64
  Architecture   x86-64
  Virtualization KVM · QEMU q35
  Firmware       4.2025.05-2 · 8 months old

  STORAGE
  DEVICE   FS      SIZE    USED    FREE    MOUNT
  sda1     vfat    975M    8.8M    966M    /boot/efi
  sda2     ext4     29G    1.7G     26G    /
  sda3     swap      —       —       —     [swap]
  sr0      —         —       —       —     —

  Root            1.7 GiB / 29 GiB · 7% used
```

The exact formatting can follow existing PowerFlow visual conventions, but the information hierarchy should remain compact and human-first.

### Recommended drill-down flags

```powershell
pc-whoami -system
pc-whoami -storage
```

`-system` should focus on:

```text
hostname
OS / distro release
kernel
architecture
virtualization
chassis / VM state
hardware vendor/model when readable
firmware version/date/age when readable
```

`-storage` should combine the useful parts of `lsblk -f` and `df -hT`:

```text
block device
partition
filesystem type
filesystem label when present
size
mountpoint
used/free/% for mounted filesystems
swap state
```

If existing `pc-whoami` flag naming already has a better storage convention, reuse it rather than adding aliases gratuitously.

### Do not dump pseudo-filesystems by default

Raw `df -hT` output includes entries such as:

```text
udev
tmpfs
efivarfs
/run/credentials/...
/run/user/...
```

These are valid system mounts but usually noise for the operator asking "where is my disk space?".

Default `pc-whoami` should show persistent/block-backed storage and swap.

A detailed mode may expose all mounts if needed, for example:

```powershell
pc-whoami -storage --all
```

### Handle restricted `hostnamectl` fields cleanly

Observed as a normal unprivileged user:

```text
Failed to query product UUID, ignoring: Access denied
Failed to query hardware serial, ignoring: Access denied
```

PowerFlow should not surface these as scary errors when the rest of the identity query succeeded.

Rules:

- product UUID and hardware serial are optional enrichment;
- permission-denied on optional DMI fields should degrade to `unavailable`/omitted;
- do not require `sudo` merely to render machine identity;
- do not print raw stderr from `hostnamectl` into the dashboard.

### Implementation direction

Prefer structured platform-adapter data over parsing decorated human output.

Possible Linux data sources:

```text
hostname / hostnamectl or equivalent structured systemd properties
/etc/os-release
uname
systemd-detect-virt
/sys/class/dmi/id/* where readable
lsblk --json
findmnt --json and/or a structured filesystem-usage query
```

The adapter should normalize these into PowerFlow objects before rendering.

Do not make the renderer parse column spacing from `lsblk` or `df` text.

### Virtual-machine awareness

When virtualization is detected, make it visible near the top:

```text
Virtualization  KVM
Platform        QEMU · q35
```

This is especially useful in a PowerFlow session because the prompt already shows the remote hostname; `pc-whoami` should explain what that remote machine actually is.

Do not imply that `QEMU` means the guest is necessarily managed by Proxmox unless there is authoritative evidence for that.

### Firmware age

If firmware date is available, preserve the existing PowerFlow pattern of rendering an age rather than forcing the user to mentally compare dates.

Example:

```text
Firmware  4.2025.05-2 · 8 months old
```

If the date cannot be read without privileges, omit the age gracefully.

### Filesystem usage semantics

The storage view should distinguish:

```text
physical/virtual block-device capacity
partition/filesystem size
mounted filesystem usage
swap
empty optical devices
```

Do not treat an empty `sr0`/CD-ROM as an error.

Do not sum pseudo-filesystems into "disk usage".

### Suggested next-step footer

```text
pc-whoami -storage  ·  perms /  ·  diskfree -h
```

Only include commands that actually exist on the current platform and are registered in PowerFlow.

### Tests

At minimum:

- Debian/Ubuntu guest on KVM/QEMU
- Fedora guest
- physical Linux machine
- container/WSL if PowerFlow supports them
- unprivileged user with unreadable product UUID/serial
- EFI system
- BIOS system
- ext4 root
- XFS/Btrfs root
- swap partition
- swapfile
- empty optical device
- multiple mounted disks
- hidden/pseudo mounts filtered by default
- `--all`/detailed mode if implemented
- filenames/mountpoints with spaces
- non-systemd Linux fallback if within supported distro scope

### Privacy

Machine IDs, boot IDs, product UUIDs, hardware serials and filesystem UUIDs should **not** be dumped in the default human view merely because native tools expose them.

They are identifiers, not everyday health information.

If PowerFlow later exposes them in an explicit detailed/debug mode, apply the same privacy-first rules used elsewhere in the project.


---

## PF-FEAT-005 — safe Linux hostname change with `/etc/hosts` synchronization

### Native workflow being replaced

```bash
sudo hostnamectl set-hostname web-prod
sudo nano /etc/hosts
```

Changing only the hostname can temporarily break local resolution:

```text
sudo: unable to resolve host web-prod: Name or service not known
```

because the system hostname changes while an existing Debian-style `/etc/hosts` entry still points at the old name.

### Recommended command

```powershell
pc-name web-prod
```

Optional explicit alias:

```powershell
pc-hostname web-prod
```

Keep `pc-whoami` read-only; `pc-name` is its mutating sibling.

### Desired behaviour

1. Read the current static hostname.
2. Detect the matching local-host entry in `/etc/hosts`.
3. Validate the requested hostname.
4. Preview both changes.
5. Back up `/etc/hosts`.
6. Apply the new hostname.
7. Update only the matching local-host entry.
8. Verify local resolution.
9. Report the new identity.

Example before:

```text
127.0.1.1   debian13-base.powerhub   debian13-base
```

Command:

```powershell
pc-name web-prod
```

Preview:

```text
🖥️  RENAME HOST
────────────────────────────────────────────
Current       debian13-base
New           web-prod

/etc/hosts
127.0.1.1
  debian13-base.powerhub   debian13-base
        ↓
  web-prod.powerhub        web-prod

This changes the machine hostname and local resolver entry.
Continue? [y/N]
```

Expected result:

```text
✅ Host renamed

Hostname      web-prod
Local FQDN    web-prod.powerhub
Resolution    OK

  pc-whoami
```

### Preserve the existing domain suffix

Do not hardcode `.powerhub`.

If the old line is:

```text
127.0.1.1   oldhost.example.net   oldhost
```

then the new line should become:

```text
127.0.1.1   newhost.example.net   newhost
```

If no domain suffix is present, update only the short hostname.

### `/etc/hosts` safety rules

PowerFlow must not regenerate the whole file.

It should:

- preserve comments;
- preserve IPv6 entries;
- preserve unrelated IPv4 entries and aliases;
- change only the line confidently associated with the current hostname;
- refuse if multiple candidate lines make the edit ambiguous.

Preferred matching order:

1. exact old short-hostname match;
2. exact FQDN whose first label matches the old hostname;
3. Debian-style `127.0.1.1` hostname mapping;
4. otherwise refuse and show candidate lines.

### Privilege handling

The command needs elevated privileges for the hostname and hosts-file write.

- root session → execute directly;
- normal interactive user → elevate only the required operations with `sudo`;
- unavailable/insufficient sudo → fail before partial mutation where possible.

Do not require users to run their whole PowerFlow session as root.

### Backup and rollback

Record the old hostname and previous hosts-file content before mutation.

If hostname change succeeds but `/etc/hosts` update fails:

1. restore the old hostname;
2. verify restoration;
3. report whether rollback succeeded.

Add:

```powershell
pc-name restore
```

to restore the latest PowerFlow-recorded hostname transaction after preview/confirmation.

Do not silently rollback by repeatedly mutating state after an uncertain verification failure.

### Verification

Verify at least:

```bash
hostname
hostnamectl --static
getent hosts "$(hostname)"
```

`getent` is the relevant local resolver check; do not use `ping` as the primary test.

Success means:

- short hostname matches the requested name;
- static hostname agrees;
- the new hostname resolves through NSS;
- the replaced local-host line no longer contains the old short hostname.

### Hostname validation

Accept a normal Linux hostname label:

```text
letters
digits
hyphen
1–63 characters
must not start or end with a hyphen
```

Prefer a short hostname such as:

```text
web-prod
```

rather than treating a full FQDN as the machine name unless FQDN support is deliberately added later.

### Ambiguous-file example

```text
❌ Could not safely identify the local hostname entry.

Candidates:
  127.0.1.1    oldhost.example   oldhost
  192.168.1.20 oldhost.example   oldhost

No changes were made.

Inspect:
  grep -n 'oldhost' /etc/hosts
```

### Cross-platform note

This exact implementation is Linux-specific.

If `pc-name` is later supported on Windows, implement Windows computer-name semantics separately; do not pretend Windows uses `/etc/hosts` hostname conventions.

### Tests

- Debian-style `127.0.1.1 fqdn short`
- short hostname only
- custom domain suffix
- no domain suffix
- comments and IPv6 preserved
- unrelated aliases preserved
- multiple matching lines → refuse
- no matching line
- root execution
- sudo execution
- hostname succeeds / hosts write fails → rollback
- hosts write succeeds / hostname fails
- verification failure
- `pc-name restore`
- no unrelated `/etc/hosts` line modified

### Documentation example

```powershell
# Native:
sudo hostnamectl set-hostname web-prod
sudo nano /etc/hosts

# PowerFlow:
pc-name web-prod
```


---

## PF-UX-005 — allow multiple `ls` named starting-point/query pairs in one command

### Goal

Reuse PowerFlow's existing named starting-point system so one `ls` invocation can query multiple known roots without typing full paths.

### Motivating native command

```bash
ls -l /etc/machine-id /var/lib/dbus/machine-id
```

### Proposed PowerFlow form

```powershell
ls -l -etc machine-id -var machine-id
```

Interpretation:

```text
-l              → render all resolved results in long format
-etc machine-id → resolve/list machine-id under the existing etc starting point
-var machine-id → resolve/list machine-id under the existing var starting point
```

This is intentionally a generic `ls` capability, not a machine-ID-specific command.

### Why this fits PowerFlow

PowerFlow already has named starting points for navigation and `ls`; this extends the existing grammar so more than one scoped lookup can be supplied in a single invocation.

The implementation should reuse the same starting-point resolver used by the existing `ls`/`nav` feature rather than adding hard-coded `/etc` or `/var` handling at individual call sites.

### Resolution semantics

If the current `ls` starting-point implementation already searches/fuzzily resolves descendants, preserve that behaviour for each pair.

For example:

```powershell
ls -l -var machine-id
```

may resolve:

```text
/var/lib/dbus/machine-id
```

If the existing starting-point implementation only changes the direct root and does not search descendants, do **not** silently invent recursive behaviour only for this syntax. Instead extend the shared starting-point resolver deliberately and document the rule.

### Multiple-pair parser model

Treat a named starting point as starting a new scoped operand group:

```powershell
ls -l -etc machine-id -var machine-id
```

Conceptually becomes:

```text
format flags: -l
requests:
  { root: etc, query: machine-id }
  { root: var, query: machine-id }
```

This is better than interpreting `-etc` and `-var` as global modifiers where the last one wins.

### Output

Keep one combined listing, preserving the existing `ls -l` visual style, but retain enough path context to distinguish same-named files:

```text
.r--r--r-- root root 33 B ...  /etc/machine-id
.rw-r--r-- root root 33 B ...  /var/lib/dbus/machine-id
```

Do not collapse both rows to only `machine-id`, because identical basenames would become ambiguous.

### Useful generalized examples

```powershell
ls -l -etc hosts -var log
ls -a -docs report -pics screenshot
ls -l -srv compose -docs compose
```

The exact available starting-point names should remain whatever PowerFlow's shared registry currently defines.

### Ambiguity handling

If a scoped query matches multiple paths:

- interactive terminal → use the existing picker/resolver behaviour;
- redirected/non-interactive output → return a deterministic ambiguity error or all matches according to the existing `ls` contract;
- do not pick an arbitrary first result.

### Compatibility

Normal GNU-style flags must keep their existing meaning:

```powershell
ls -l
ls -la
ls -t
```

Named starting-point tokens are PowerFlow routing tokens layered around the existing listing flags; they must not break GNU muscle memory.

### Tests

- one starting-point/query pair
- two starting-point/query pairs
- same basename in two roots
- one exact match + one fuzzy/recursive match
- ambiguous match in one root
- one missing result while another succeeds
- `-l`, `-a`, `-t` combined with starting points
- repeated same starting point
- interactive picker behaviour
- redirected output behaviour
- path names with spaces/unicode
- named-starting-point registry parity between `nav` and `ls`



---

## PF-FEAT-006 — guest identity / clone-hygiene view via QEMU Guest Agent

### Native workflow being replaced

```bash
qm guest exec 103 -- cat /etc/machine-id
qm guest exec 103 -- ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

These commands are especially useful after cloning because they answer whether the guest has its own machine identity and SSH host key.

### Recommended command

```powershell
pmx vm identity 103
```

Example:

```text
🪪 VM IDENTITY — 103 web-prod
────────────────────────────────────────────
Status        running
Agent         available
Hostname      web-prod
Machine ID    4b4c1c54d1e742eb95bc3daf3b4a2be8
SSH host key  ED25519 · SHA256:C3qzOEffk9j2CPM/CHFNXp+vUDCb5paLZFth0AtWW0Y
```

### Design rule

Do **not** expose a general arbitrary-command wrapper such as:

```powershell
pmx vm exec 103 <anything>
```

as part of this feature.

Instead, use an allow-listed, read-only guest-identity probe. That keeps the feature narrow, auditable, and consistent with PowerFlow's guarded/explicit Proxmox design.

Suggested allow-listed probes:

```text
hostname
/etc/machine-id
/etc/ssh/ssh_host_ed25519_key.pub fingerprint
```

### Guest-agent dependency

This command requires:
- the VM to be running;
- QEMU Guest Agent to be configured for the VM;
- the agent service inside the guest to be reachable.

Failure states should be precise:

```text
Agent  not-configured
Agent  configured · not responding
Agent  available
```

Do not report an agent transport failure as "machine ID missing".

### Privacy

Machine ID is a stable host identifier. It is appropriate to show it in an **explicit** identity command, but it should not be added to general dashboards such as bare `pmx`, `pmx vm`, or `pc-whoami` by default.

SSH output should show the public-host-key fingerprint, not private key material.

### Optional comparison mode

A useful later extension:

```powershell
pmx vm identity compare 101 103
```

or:

```powershell
pmx vm identity 103 --compare 101
```

could highlight duplicated clone identity:

```text
Machine ID       unique
SSH ED25519 key  unique
Hostname         different
```

If two running cloned guests report the same machine ID or SSH host-key fingerprint, flag it prominently.

Do not automatically start stopped VMs just to perform this comparison.

### Clone workflow integration

After a successful clone/start, PowerFlow can suggest:

```text
pmx vm identity 103
```

as a next step.

Do not make clone success depend on guest identity verification unless the user explicitly requests such a check, because the clone may intentionally remain stopped or lack a guest agent.

### Tests

- running VM with reachable guest agent
- running VM with agent disabled
- configured agent but service unavailable
- stopped VM
- machine-id read succeeds
- machine-id probe fails
- ED25519 host key exists
- no ED25519 key
- guest command returns nonzero
- output JSON parsing
- control characters stripped from guest output
- explicit identity view may show full machine ID
- general PMX dashboards do not leak machine ID

---

## PF-UX-006 — accept obvious PMX status shorthands

### Existing canonical syntax

PowerFlow currently routes:

```powershell
pmx node status
pmx vm status 102
```

The VM router is action-first: the first token after `pmx vm` is interpreted as the action.

### Observed natural attempts

```powershell
pmx status
```

currently:

```text
❌ Unknown pmx command 'status'. Run: pmx help
```

and:

```powershell
pmx vm 102 status
```

currently:

```text
❌ Unknown VM action '102'. Run: pmx help
```

### Proposed aliases

Support:

```powershell
pmx status
```

as a convenience alias for:

```powershell
pmx node status
```

and support object-first VM status:

```powershell
pmx vm 102 status
```

as an alias for:

```powershell
pmx vm status 102
```

Canonical forms remain unchanged.

### Why this fits PowerFlow

Both attempts are unambiguous and natural:
- `pmx status` asks for the selected/local Proxmox node status;
- `pmx vm 102 status` reads as object → action.

PowerFlow already favours additive convenience forms while retaining canonical script-friendly syntax.

### Router implementation

Preserve existing action-first precedence.

For `pmx vm`:

1. if token 1 is a known action, use the existing router unchanged;
2. otherwise, if token 2 is a known object-first action and token 1 looks like a VM selector, normalize internally.

Example:

```text
pmx vm 102 status
        ↓ normalize
pmx vm status 102
```

Potential object-first read routes worth supporting together:

```powershell
pmx vm 102 show
pmx vm 102 status
pmx vm 102 ip
pmx vm 102 net
pmx vm 102 nic
```

Mutating routes such as `start` and `shutdown` may also be supported if they normalize into the existing guarded handlers rather than duplicating mutation logic.

### Reserved-name rule

Existing action-first syntax must win.

If a VM is literally named `status`, `show`, `start`, etc., require canonical selector placement or VMID rather than making the parser guess.

### Better error hint

Even if object-first normalization is limited initially, this:

```powershell
pmx vm 102 status
```

should never end at only:

```text
Unknown VM action '102'
```

A targeted hint should say:

```text
Did you mean:
  pmx vm status 102
```

### Tests

- `pmx status` parity with `pmx node status`
- `pmx vm status 102`
- `pmx vm 102 status`
- VM name selector
- numeric VMID selector
- reserved-word VM name
- unknown action after VM selector
- output flags preserved during normalization
- `--json` / `--table` parity
- mutation aliases still use validate → confirm → revalidate → verify


---

## PF-UX-007 — make `pmx vm <selector> <command>` the canonical VM grammar

### Decision

Prefer object-first VM syntax:

```powershell
pmx vm <name|vmid> <command>
```

instead of action-first:

```powershell
pmx vm <command> <name|vmid>
```

### Canonical examples

```powershell
pmx vm 102 status
pmx vm 102 show
pmx vm 102 ip
pmx vm 102 net
pmx vm 102 nic
pmx vm 102 start
pmx vm 102 shutdown

pmx vm docker-host status
pmx vm docker-host show
pmx vm docker-host net
```

This reads naturally as:

```text
pmx → vm → which VM? → what do you want to do?
```

### Backward compatibility

Existing action-first forms must continue working:

```powershell
pmx vm status 102
pmx vm show 102
pmx vm ip 102
pmx vm start 102
```

but help, examples, next-step hints, and new documentation should advertise object-first syntax.

### Bare forms

Keep useful existing behaviour:

```powershell
pmx vm
```

→ VM inventory.

```powershell
pmx vm 102
```

→ recommended default: equivalent to `pmx vm 102 show`.

This makes selecting a VM itself useful and mirrors PowerFlow's general preference for bare commands showing meaningful state.

### Router strategy

At `Invoke-PmxVmCommand`:

1. no tokens → VM list;
2. token 1 matches a known legacy action → parse legacy action-first form;
3. otherwise token 1 is treated as a VM selector;
4. no token 2 → default to `show`;
5. token 2 selects the VM action;
6. normalize into the existing handlers.

Example:

```text
pmx vm 102 status
        ↓
selector = 102
action   = status
        ↓
Show-PmxManagedVm 102 -StatusOnly
```

Do not duplicate read or mutation implementations.

### Mutation safety

Object-first mutation commands must normalize into the same guarded handlers:

```powershell
pmx vm 102 start
pmx vm 102 shutdown
pmx vm 102 cpu 4
pmx vm 102 memory 8G
```

and therefore retain:

```text
validate → preview → confirm → revalidate → execute → verify
```

### Clone exception

Clone is naturally source-first and creates a new VM, so its grammar can remain:

```powershell
pmx vm clone <source> <new-name>
```

or evolve separately.

Do not force clone into an awkward:

```text
pmx vm <source> clone ...
```

shape solely for grammatical purity.

### Reserved-word VM names

Legacy action names create an ambiguity if a VM is literally named `status`, `show`, `start`, etc.

Resolution rule:

- a valid numeric VMID is never ambiguous;
- known action at token 1 preserves legacy action-first behaviour;
- to address a VM whose name collides with an action, use its VMID;
- optionally allow an explicit selector escape later, e.g. `--vm status`.

Do not guess.

### Help/documentation changes

Advertise:

```text
pmx vm <vm> show
pmx vm <vm> status
pmx vm <vm> net
pmx vm <vm> ip
pmx vm <vm> nic
pmx vm <vm> start
pmx vm <vm> shutdown
```

instead of action-first forms.

Next-step hints should also become object-first:

```text
pmx vm 102 show  ·  pmx vm 102 ip  ·  pmx snapshot 102 list
```

where snapshot grammar is updated separately if desired.

### Relationship to PF-UX-006

PF-UX-006 originally proposed object-first status as an additive shorthand.

This entry supersedes that part of PF-UX-006:

- `pmx status` remains a useful node-status convenience alias.
- `pmx vm <selector> <command>` becomes the preferred VM grammar, not merely a shorthand.

### Tests

Cover both grammars for parity:

```powershell
pmx vm 102 status
pmx vm status 102

pmx vm 102 show
pmx vm show 102

pmx vm 102 net
pmx vm net 102

pmx vm 102 start
pmx vm start 102
```

Assertions:

- same resolved VM
- same output
- same output flags
- same mutation plan
- same audit record
- same verification
- no command implementation duplicated

# Backlog reset rule

This file is cumulative.

**Do not delete, truncate, reset numbering, or replace it with an empty backlog unless the user explicitly confirms that they have copied the backlog and explicitly asks for it to be reset.**

Until then:
- append new findings;
- refine existing entries when new evidence arrives;
- merge duplicates without losing evidence;
- preserve existing IDs where possible;
- mark resolved items rather than silently removing them.
