Yes. We will turn the Proxmox interface work into a **PowerFlow `pmx` module**, then use that module to build `docker-host`.

Tiny lesson: imagine Proxmox as a hotel.

* The web interface is the reception desk with buttons.
* `qm` is the hotel manager’s terminal for controlling virtual-machine rooms.
* `pvesh` is direct access to the hotel’s management API.
* PowerFlow will be your simplified remote-control panel.

Proxmox documents `qm` as its command-line tool for QEMU/KVM virtual machines. `pvesh` exposes Proxmox API functions directly when run as root on the Proxmox node. ([Proxmox VE][1])

## Proposed PowerFlow vocabulary

```powershell
pmx vm list
pmx vm status 101
pmx vm show 101

pmx vm clone 100 102 docker-host
pmx vm set-cpu 102 4
pmx vm set-memory 102 8GB
pmx disk list 102
pmx disk grow 102 scsi0 +70G

pmx vm start 102
pmx vm shutdown 102
pmx vm reboot 102

pmx snapshot create 102 pre-docker
pmx snapshot list 102
pmx snapshot rollback 102 pre-docker
pmx snapshot delete 102 pre-docker
```

PowerFlow will connect through SSH and translate those into Proxmox commands.

## Translation layer

| PowerFlow                              | Proxmox command                                |
| -------------------------------------- | ---------------------------------------------- |
| `pmx vm list`                          | `qm list`                                      |
| `pmx vm show 101`                      | `qm config 101`                                |
| `pmx vm status 101`                    | `qm status 101`                                |
| `pmx vm clone 100 102 docker-host`     | `qm clone 100 102 --name docker-host --full 1` |
| `pmx vm set-cpu 102 4`                 | `qm set 102 --cores 4`                         |
| `pmx vm set-memory 102 8GB`            | `qm set 102 --memory 8192`                     |
| `pmx disk grow 102 scsi0 +70G`         | `qm resize 102 scsi0 +70G`                     |
| `pmx vm start 102`                     | `qm start 102`                                 |
| `pmx vm shutdown 102`                  | `qm shutdown 102`                              |
| `pmx snapshot create 102 pre-docker`   | `qm snapshot 102 pre-docker`                   |
| `pmx snapshot list 102`                | `qm listsnapshot 102`                          |
| `pmx snapshot rollback 102 pre-docker` | `qm rollback 102 pre-docker`                   |

## Safety design

PowerFlow should classify commands like your RACADM module:

```text
Green:
list, show, status, disk list, snapshot list
Run immediately.

Amber:
clone, set CPU, set memory, start, shutdown, create snapshot
Show the planned action and ask for confirmation when appropriate.

Red:
stop, reset, rollback, destroy, delete snapshot
Require an explicit confirmation phrase.
```

For example:

```text
PowerFlow is about to destroy VM 102: docker-host.

This permanently removes the VM and its attached disks.

Type: DESTROY docker-host
```

We should not provide a generic command such as:

```powershell
pmx run "anything the user types"
```

That would allow accidental shell-command injection or unrestricted root commands. Each supported action should validate its inputs and translate only to an approved Proxmox command.

## The terminal-only clone walkthrough

This reproduces what we were about to do through the interface.

Connect to Proxmox:

```powershell
srv proxmox
```

Confirm the existing machines:

```bash
qm list
```

Expected important entries:

```text
VMID  NAME
100   debian13-base
101   debian13-lab
```

Inspect the template:

```bash
qm config 100
```

Confirm that VM ID `102` is unused:

```bash
qm status 102
```

Expected result:

```text
Configuration file 'nodes/chikara/qemu-server/102.conf' does not exist
```

That error is useful here: it confirms that `102` is available.

Create the independent clone:

```bash
qm clone 100 102 --name docker-host --full 1
```

Meaning:

```text
qm          = QEMU virtual-machine manager
clone       = copy an existing VM or template
100         = source template
102         = new VM ID
--name      = name the new VM
--full 1    = make an independent full clone
```

Then assign resources:

```bash
qm set 102 --cores 4
qm set 102 --memory 8192
qm set 102 --agent 1
```

Here, memory is measured in MiB:

```text
8192 MiB = 8 GiB
```

Inspect its disk before resizing:

```bash
qm config 102
```

Look for a line similar to:

```text
scsi0: rpool:vm-102-disk-0,size=30G
```

Only after confirming the disk identifier and current size would we enlarge it:

```bash
qm resize 102 scsi0 +70G
```

That grows a 30 GB virtual disk to approximately 100 GB. It does not automatically enlarge the partition and filesystem inside Debian; we handle that separately after boot.

Finally:

```bash
qm start 102
qm status 102
```

Expected result:

```text
status: running
```

## First PowerFlow implementation milestone

We should build the feature in this order:

```text
Phase 1: read-only
pmx vm list
pmx vm show
pmx vm status

Phase 2: safe lifecycle
pmx vm start
pmx vm shutdown
pmx vm reboot

Phase 3: provisioning
pmx vm clone
pmx vm set-cpu
pmx vm set-memory
pmx disk grow

Phase 4: recovery
pmx snapshot create/list/delete/rollback

Phase 5: guarded destruction
pmx vm destroy
```

Start with **Phase 1**, because it lets us verify SSH execution, parsing and output formatting without changing anything on Proxmox.

Your first PowerFlow behaviour should translate:

```powershell
pmx vm list
```

into:

```bash
ssh root@192.168.8.20 -- qm list
```

The next coding step is to implement that read-only command and confirm it returns VMs `100` and `101`.

[1]: https://pve.proxmox.com/pve-docs/qm.1.html?utm_source=chatgpt.com "qm(1)"


Tiny lesson: **`100` is not a special cloning number. It is the Proxmox ID of your existing template.**

Think of Proxmox as a hotel:

```text
VMID 100 = room number
debian13-base = name written on the room door
```

Proxmox identifies every VM or container using a unique numeric **VMID**. The friendly name is a label for humans, while the VMID is the authoritative identifier used by commands, configuration files and virtual disks. ([Proxmox VE][1])

Your current guests are:

|  VMID | Name            | Role                    |
| ----: | --------------- | ----------------------- |
| `100` | `debian13-base` | Debian template         |
| `101` | `debian13-lab`  | Linux practice VM       |
| `102` | `docker-host`   | Proposed new service VM |

So this native command:

```bash
qm clone 100 102 --name docker-host --full 1
```

means:

| Part                 | Meaning                              |
| -------------------- | ------------------------------------ |
| `qm`                 | Proxmox QEMU virtual-machine manager |
| `clone`              | Copy an existing VM or template      |
| `100`                | Source VMID: `debian13-base`         |
| `102`                | New VMID for the clone               |
| `--name docker-host` | Human-readable name                  |
| `--full 1`           | Create an independent full copy      |

The story is:

> Go to room `100`, copy its contents into a new room numbered `102`, and place the sign `docker-host` on the new door.

Had your Debian template been VMID `450`, the command would start with:

```bash
qm clone 450 ...
```

## Better PowerFlow syntax

For educational clarity, positional numbers are too mysterious:

```powershell
pmx vm clone 100 102 docker-host
```

A better design uses named arguments:

```powershell
pmx vm clone `
  --source-vmid 100 `
  --new-vmid 102 `
  --name docker-host `
  --full
```

On Fedora or Linux PowerShell, the same command can be written on one line:

```powershell
pmx vm clone --source-vmid 100 --new-vmid 102 --name docker-host --full
```

PowerFlow should then display a preview table:

```text
Clone plan
────────────────────────────────────────
Source VMID       100
Source name       debian13-base
Source type       Template
New VMID          102
New name          docker-host
Clone type        Full, independent copy
Native command    qm clone 100 102 --name docker-host --full 1
────────────────────────────────────────
Proceed? [y/N]
```

This teaches the user what every value represents before anything changes.

## Friendly-name support

PowerFlow could also allow:

```powershell
pmx vm clone --source debian13-base --new-vmid 102 --name docker-host --full
```

PowerFlow would internally run a lookup and report:

```text
Resolved source:
debian13-base → VMID 100
```

Then it would execute the numeric native command.

The safest rule should be:

```text
PowerFlow may accept either a VMID or a friendly name.
Before acting, it resolves and displays both.
The native Proxmox command always receives the VMID.
```

## Educational `pmx help`

The top-level command should be:

```powershell
pmx help
```

Example output:

| Command group        | Purpose                     | Example                        |
| -------------------- | --------------------------- | ------------------------------ |
| `pmx vm`             | Manage virtual machines     | `pmx vm list`                  |
| `pmx disk`           | Inspect or resize VM disks  | `pmx disk list --vmid 101`     |
| `pmx snapshot`       | Create and manage snapshots | `pmx snapshot list --vmid 101` |
| `pmx storage`        | Inspect Proxmox storage     | `pmx storage list`             |
| `pmx node`           | Inspect the Proxmox host    | `pmx node status`              |
| `pmx help <command>` | Explain one command         | `pmx help vm clone`            |

Then:

```powershell
pmx help vm clone
```

should explain:

```text
PURPOSE
    Create a new VM from an existing VM or template.

STORY
    Copy one hotel room into a new room with its own room number.

SYNTAX
    pmx vm clone --source-vmid <number>
                 --new-vmid <number|auto>
                 --name <text>
                 [--full]

REQUIRED VALUES
    --source-vmid   Existing Proxmox VMID to copy.
    --new-vmid      Unique VMID for the new machine.
    --name          Friendly name for humans.

OPTIONS
    --full          Create an independent copy.
    --dry-run       Show the plan without changing Proxmox.

EXAMPLE
    pmx vm clone --source-vmid 100 --new-vmid 102 \
                 --name docker-host --full

TRANSLATES TO
    qm clone 100 102 --name docker-host --full 1

SAFETY
    Amber: creates a VM and consumes storage.
```

Also add:

```powershell
pmx vm next-id
```

This should ask Proxmox for an available VMID rather than guessing. Proxmox maintains unique numerical VMIDs and supports a configurable next-free VMID range. ([Proxmox VE][1])

So the eventual convenient command could be:

```powershell
pmx vm clone --source debian13-base --new-vmid auto --name docker-host --full
```

PowerFlow would resolve both numbers, show the table, and request confirmation before cloning.

[1]: https://pve.proxmox.com/wiki/Migrate_to_Proxmox_VE?trk=public_post_comment-text&utm_source=chatgpt.com "Migrate to Proxmox VE - Proxmox VE"

Tiny lesson: think of the `pmx` module as a **hospital control desk**. Before admitting a new VM-patient, it should know which ward to use, how many resources to allocate, what safety checks to perform, and how to explain every action.

I suggest two configuration layers:

1. **PowerFlow settings** — how `pmx` behaves.
2. **VM profiles** — reusable blueprints for different kinds of VM.

## 1. PowerFlow `pmx` settings

Add these commands:

```powershell
pmx config show
pmx config set <setting> <value>
pmx config reset <setting>
pmx config validate
pmx config discover
```

A useful configuration table could look like this:

| Setting           | Suggested value | Purpose                                |
| ----------------- | --------------- | -------------------------------------- |
| `host`            | `proxmox`       | SSH alias or server address            |
| `node`            | `chikara`       | Proxmox node name                      |
| `transport`       | `ssh`           | Initial connection method              |
| `output`          | `table`         | Default readable output                |
| `show-native`     | `true`          | Display the underlying Proxmox command |
| `explain`         | `true`          | Explain unfamiliar arguments           |
| `vmid-policy`     | `auto`          | Ask Proxmox for the next free VMID     |
| `clone-mode`      | `full`          | Independent clone by default           |
| `confirmation`    | `risk-based`    | Confirm amber/red operations           |
| `audit-log`       | `true`          | Record changes made through PowerFlow  |
| `timeout-seconds` | `60`            | Stop waiting after a sensible period   |

Example:

```powershell
pmx config set host proxmox
pmx config set node chikara
pmx config set output table
pmx config set show-native true
```

Then:

```powershell
pmx config show
```

could produce:

| Setting         | Value        | Meaning                                |
| --------------- | ------------ | -------------------------------------- |
| Host            | `proxmox`    | SSH destination                        |
| Node            | `chikara`    | Target Proxmox node                    |
| Output          | `table`      | Human-readable tables                  |
| VMID policy     | `auto`       | Choose the next available ID           |
| Clone mode      | `full`       | New VM receives an independent disk    |
| Native commands | `shown`      | Educational mode enabled               |
| Confirmation    | `risk-based` | Dangerous actions require confirmation |

## 2. Discovery before hard-coding

Add:

```powershell
pmx discover
```

This should inspect the real Proxmox host and return:

| Category            | Example             |
| ------------------- | ------------------- |
| Nodes               | `chikara`           |
| Storages            | actual storage IDs  |
| Network bridges     | `vmbr0`             |
| Existing VMIDs      | `100`, `101`        |
| Next available VMID | `102`               |
| Templates           | `100 debian13-base` |
| Host CPU threads    | `16`                |
| Host memory         | `128 GB`            |

This matters because PowerFlow should not assume that every installation uses storage named `rpool` or bridge `vmbr0`.

`pvesh` can invoke Proxmox’s API directly from the node, which makes it useful for discovery, although Proxmox restricts local `pvesh` execution to root. ([Proxmox VE][1])

Suggested native sources:

```bash
qm list
pvesm status
ip -br link
pvesh get /nodes
pvesh get /cluster/resources --type vm
pvesh get /cluster/nextid
```

PowerFlow should translate those results into tables rather than displaying raw JSON.

## 3. Reusable VM profiles

Add a profile system:

```powershell
pmx profile list
pmx profile show docker-host
pmx profile create docker-host
pmx profile edit docker-host
pmx profile delete docker-host
```

A profile is a **VM prescription**.

For example:

```text
Profile: docker-host
Source template: debian13-base
CPU cores: 4
Memory: 8192 MiB
Disk target: 100 GiB
Network bridge: vmbr0
Network model: virtio
QEMU agent: enabled
Start at boot: enabled
Tags: docker;intranet
Protection after build: enabled
```

Proxmox supports informational guest tags through `qm set`, and multiple tags are separated using semicolons. ([Proxmox VE][2])

The command could be:

```powershell
pmx vm deploy --profile docker-host --name docker-host
```

PowerFlow would show the complete plan:

| Item          | Resolved value       |
| ------------- | -------------------- |
| Source        | `debian13-base`      |
| Source VMID   | `100`                |
| New VMID      | `102`                |
| Name          | `docker-host`        |
| Clone         | Full                 |
| CPU           | 4 cores              |
| Memory        | 8192 MiB             |
| Disk          | 100 GiB              |
| Bridge        | `vmbr0`              |
| Agent         | Enabled              |
| Start at boot | Enabled              |
| Tags          | `docker`, `intranet` |

Then show:

```text
Native operations:

qm clone 100 102 --name docker-host --full 1
qm set 102 --cores 4
qm set 102 --memory 8192
qm set 102 --agent enabled=1
qm resize 102 scsi0 +70G
qm set 102 --onboot 1
qm set 102 --tags 'docker;intranet'
```

The exact disk-growth calculation must be based on the cloned disk’s current size, not assumed.

## 4. Suggested VM configuration groups

### CPU and memory

```powershell
pmx vm cpu show --vm 102
pmx vm cpu set --vm 102 --cores 4
pmx vm memory set --vm 102 --size 8GiB
```

PowerFlow should display both the friendly unit and native unit:

```text
Requested memory: 8 GiB
Proxmox value:     8192 MiB
```

It should also warn when a user allocates an unreasonable portion of the host:

```text
Warning: this request assigns 14 of the host's 16 logical processors.
```

### Disk

```powershell
pmx disk list --vm 102
pmx disk grow --vm 102 --disk scsi0 --to 100GiB
```

Prefer `--to 100GiB` over `+70G`. The user normally cares about the intended final size.

PowerFlow calculates the difference:

```text
Current size: 30 GiB
Target size:  100 GiB
Growth:       70 GiB
```

Important warning:

```text
This enlarges the virtual disk.
It does not automatically enlarge the partition or filesystem inside Debian.
```

### Network

```powershell
pmx network list --vm 102
pmx network set --vm 102 --bridge vmbr0 --model virtio
```

A Proxmox Linux bridge such as `vmbr0` connects VMs to the underlying network. ([Proxmox VE][3])

Suggested table:

| Interface | Model  | Bridge  | MAC       | Firewall | VLAN |
| --------- | ------ | ------- | --------- | -------- | ---- |
| `net0`    | VirtIO | `vmbr0` | generated | off      | none |

VLAN configuration should remain an advanced feature until we complete the VLAN module.

### Boot behaviour

```powershell
pmx vm autostart enable --vm 102
pmx vm autostart disable --vm 102
pmx vm startup set --vm 102 --order 30 --delay 20
```

Proxmox supports automatic VM startup and configurable startup/shutdown ordering. ([Proxmox VE][4])

Story:

> After a power failure, Proxmox is the morning supervisor. It wakes infrastructure services in the correct order instead of opening every department simultaneously.

For example:

| Order | Service     |
| ----: | ----------- |
|    10 | DNS         |
|    20 | Storage     |
|    30 | Docker host |
|    40 | Monitoring  |

### Protection

```powershell
pmx vm protect --vm 100
pmx vm unprotect --vm 100
```

Use protection for:

```text
templates
important service VMs
VMs that must not be accidentally deleted
```

PowerFlow should explain that protection is a guardrail, not a backup.

### Tags and notes

```powershell
pmx vm tag add --vm 102 docker
pmx vm tag add --vm 102 intranet
pmx vm note set --vm 102 --text "Runs internal Docker services"
```

Suggested tags:

```text
template
lab
docker
intranet
production
windows
backup-required
```

## 5. Educational switches

These would make PowerFlow genuinely useful for learning:

```powershell
pmx vm clone --help
pmx vm clone --explain
pmx vm clone --dry-run ...
pmx vm clone --show-native ...
```

Their roles:

| Option          | Behaviour                                      |
| --------------- | ---------------------------------------------- |
| `--help`        | Show syntax and examples                       |
| `--explain`     | Explain each concept and argument              |
| `--dry-run`     | Validate and preview without changing anything |
| `--show-native` | Display the translated `qm` or `pvesh` command |
| `--json`        | Machine-readable output for scripts            |
| `--table`       | Human-readable output                          |

Example:

```powershell
pmx vm clone --source debian13-base --new-vmid auto `
    --name docker-host --full --dry-run --explain
```

## 6. Safety checks before provisioning

Before cloning, PowerFlow should automatically verify:

| Check                 | Failure message                             |
| --------------------- | ------------------------------------------- |
| Source exists         | `Template debian13-base was not found`      |
| Source is a template  | `Source is a running VM, not a template`    |
| VMID is free          | `VMID 102 already belongs to docker-host`   |
| Name is valid         | `VM names cannot contain spaces`            |
| Storage is active     | `Target storage is unavailable`             |
| Enough storage exists | `Requested disk exceeds available capacity` |
| Bridge exists         | `vmbr0 was not found`                       |
| Source is stopped     | appropriate warning where required          |
| Clone completed       | verify VM configuration afterward           |

Never include an unrestricted escape command such as:

```powershell
pmx exec "<arbitrary root command>"
```

Every PowerFlow operation should map to a known, validated action.

## Recommended first-release scope

Build these first:

```text
pmx help
pmx config show
pmx config discover

pmx node status
pmx storage list

pmx vm list
pmx vm show
pmx vm status
pmx vm next-id

pmx vm clone
pmx vm cpu set
pmx vm memory set
pmx disk list
pmx disk grow

pmx vm start
pmx vm shutdown

pmx snapshot list
pmx snapshot create
```

Then add profiles:

```text
pmx profile list
pmx profile show
pmx vm deploy --profile <name>
```

The strongest new feature is **`pmx vm deploy`**: one educational, validated workflow that resolves the template, chooses a VMID, checks storage, shows a table, displays the native commands, asks for confirmation, creates the VM and verifies the final configuration.

[1]: https://pve.proxmox.com/pve-docs/pvesh.1.html?utm_source=chatgpt.com "pvesh(1)"
[2]: https://pve.proxmox.com/pve-docs/pve-admin-guide.pdf?utm_source=chatgpt.com "PROXMOX VE ADMINISTRATION GUIDE"
[3]: https://pve.proxmox.com/wiki/Network_Configuration?source=post_page-----ecfc7b38c6da---------------------------------------&utm_source=chatgpt.com "Network Configuration - Proxmox VE"
[4]: https://pve.proxmox.com/pve-docs-6/pve-admin-guide.pdf?utm_source=chatgpt.com "Proxmox VE Administration Guide183 / 480This way, the guest would first attempt to boot from the disk <code>scsi0</code>, if that fails, it would go on to attempt"
