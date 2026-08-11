## Features

> 🪟🐧 **Windows and Linux**: PowerFlow uses one component layer with matching platform
> adapters. Linux keeps GNU `rm`/`mv`/`cp`/`cat` intact while exposing PowerFlow's safer file
> commands under unambiguous names.

### 🧭 Smart Navigation System

- **Intelligent project search** - Quickly navigate to projects with fuzzy matching across ~/Code and bookmarked directories
- **Persistent bookmarks** - Save frequently used directories with memorable names, persisted across sessions in JSON format
- **Context-aware navigation** - Automatically detects your working environment and adapts search behavior
- **Configurable auto-navigation** - Start in your preferred directory (like VSCode's workspace behavior) with easy configuration
- **Nested project discovery** - Advanced search algorithms find projects buried in complex directory structures

### 📁 Enhanced File Operations

- **Fuzzy search file operations** - Move, rename, and delete files using partial names with intelligent matching
- **Cut-and-paste workflow** - Modern file management with `mv` to cut, `mv-t` to paste, and `mv-c` to cancel
- **Safety-first design** - Confirmation prompts and backup creation prevent accidental data loss
- **Beautiful directory listings** - Modern file views with icons, colors, and tree structures using `lsd`
- **Smart completion** - PowerShell-like predictive text with history-based suggestions and case-insensitive matching

### 🚀 Streamlined Git Workflow

- **One-command releases** - Update version and release with `git-a -vr` for instant GitHub releases
- **Automated release generation** - GitHub Actions integration creates install scripts and release notes automatically
- **Interactive commit workflow** - Beautiful fuzzy-search interface for staging, committing, and pushing changes
- **Smart rollback system** - Create rollback branches from any commit with automatic naming and branch management
- **Branch management** - Interactive branch switching, creation, and deletion with safety checks

### 🔗 GitHub Integration

- **Repository browser** - List, filter, and manage your GitHub repositories with commit activity statistics
- **Secure token management** - GitHub tokens stored safely in Windows Credential Manager with automatic fallback
- **One-click actions** - Clone, browse, or delete repositories directly from the terminal interface
- **Rate limit handling** - Intelligent API usage with automatic cooldowns and error recovery

### 🎨 Beautiful User Experience

- **Starship prompt integration** - Modern, informative prompt with Git status, language detection, and performance metrics
- **Consistent visual design** - Emoji indicators, color schemes, and formatting create intuitive interfaces
- **Clipboard integration** - All operations automatically copy relevant data (paths, hashes, URLs) to clipboard
- **Fuzzy search everywhere** - fzf integration provides fast, searchable interfaces for all interactive commands
- **Live previews** - File and directory previews with syntax highlighting and tree views in fuzzy finder

### 🔍 Advanced Search & Discovery

- **FZF integration** - Powerful fuzzy finding with customizable themes and intelligent previews
- **History-based prediction** - Command history search with real-time filtering and completion
- **Multi-modal search** - File finder (Ctrl+T), command history (Ctrl+R), and directory navigation (Alt+C)
- **Smart file type detection** - Automatic syntax highlighting and appropriate preview generation

### 🛡️ Safety & Reliability

- **Destructive operation protection** - Multiple confirmations and safety checks prevent accidental deletions
- **Current branch protection** - Prevents deletion or modification of active Git branches
- **Version validation** - Ensures profile versions match Git tags before releases
- **Automatic dependency management** - Installs and configures required tools automatically with daily checks
- **Self-healing capabilities** - Built-in recovery tools and diagnostic functions for troubleshooting
- **Graceful degradation** - Fallback behaviors when optional dependencies are unavailable

### 🌐 Private Saved SSH Connections

- **Alias-first operation** - `srv`, `srv list`, picker rows, status messages, and normal
  connection handling show saved server aliases and reachability without repeating usernames,
  addresses, or ports
- **Authenticated detail view** - `srv <name> info` performs a non-mutating SSH authentication
  probe and reveals the saved endpoint only after it succeeds
- **Private password prompt** - A platform askpass helper shows only `Password for '<alias>':`
  and sends hidden input directly to OpenSSH. It never persists, logs, echoes, exports, or places
  the password on a command line
- **Attached native transport** - Successful direct sessions remain attached to the terminal;
  failed and cancelled connections return categorized alias-only messages

### 🐳 Containers (`dkr` for docker · `pman` for podman)

- **Two names, one implementation** - `dkr` drives docker and `pman` drives podman. The command
  NAME is the engine selector, so there is no `--engine` flag to remember. A switchable alias was
  rejected deliberately: it would make `dkr` mean different things on different machines, so help
  text, documentation and muscle memory would all become machine-dependent. Every verb below
  works under either name.
- **`pman stores`** - podman keeps *rootless* and *rootful* containers in entirely separate
  stores, each with its own images, volumes and networks, reached by connections matched on SSH
  **port** rather than name. So a container can be plainly running and still invisible: the
  engine answers truthfully that there are none *here*. `stores` shows the whole inventory.

- **One table, grouped by stack** - `dkr` shows every container with its status and ports,
  grouped by compose project. Stopped containers are listed, not hidden: when the table holds
  only what is running, "it is not there" and "it is dead" look identical
- **Mark several, act once** - with `fzf`, `dkr` opens a multi-select picker. Tab marks
  containers, Enter picks one action for all of them, so
  `sudo docker stop qbittorrent radarr sonarr jellyfin` becomes four keystrokes
- **Names work from anywhere** - `dkr restart sonarr` matches a container, a compose *service*,
  or a whole *project*, resolved through the compose labels. No `cd` into the stack directory
  first. A miss suggests near-matches instead of `No such container`
- **Compose-correct restarts** - plain `docker restart` ignores an edited compose file, which is
  the classic "I changed the yml and nothing happened". `dkr restart` uses the compose form when
  the container belongs to a project
- **Stacks that are down are still reachable** - `dkr up media` works when nothing of `media` is
  running, because a stopped project is invisible to `docker ps`. `dkr up` with no name uses the
  compose file in the current directory
- **`dkr down` cannot delete your data** - plain `down` removes containers and networks and
  leaves named volumes alone; the `-v` flag that deletes them is not reachable from anywhere in
  PowerFlow. It confirms first and says so
- **Logs and shells** - `dkr logs [name]` tails 200 lines (`-f` follows, no name opens a picker);
  `dkr shell [name]` opens `bash` if the image has it and `sh` otherwise, so you do not have to
  remember which image ships which
- **Never silently elevates** - the docker socket is root-equivalent, so `dkr` reports whether it
  is usable rather than quietly prepending `sudo`. It tells you the four-state answer: not
  installed, daemon down, needs group membership, or ready
- **`--show-native` on every command** - prints the real `docker` command it runs, so it teaches
  the CLI instead of hiding it

### ⚙️ System Integration

- **Windows Terminal optimization** - Enhanced tab management and terminal control functions
- **PowerShell profile enhancement** - Extends native PowerShell with productivity-focused aliases and functions
- **Cross-session persistence** - Bookmarks, settings, and preferences maintained across sessions
- **Auto-update system** - Built-in version checking and update mechanisms with conflict resolution

### ⚡ Proxmox VE Management

- **Local or SSH transport** - Inspect/manage a local Proxmox node or select a saved `srv`
  alias from Windows/Linux; PMX stores no credentials
- **Structured discovery** - Nodes, VM-image storage, bridges, templates, VMs, VMIDs, virtual
  disks, power state, and snapshots come from allow-listed `pvesh` JSON queries
- **Source-separated VM networking** - `pmx vm network <vm>` combines configured virtual
  adapters with VM-reported interfaces and addresses without equating `net0` with `ens18`;
  records match only through a unique normalized MAC address
- **Goal-based network conveniences** - `pmx vm nic <vm>` shows adapters, `pmx vm ip <vm>`
  shows addresses, and `pmx vm net stats <vm>` shows exact traffic counters; `-t`, `-j`, `-4`,
  and `-6` provide strict short forms
- **Honest address inference** - Primary candidates are ranked by family, scope, and a unique
  adapter match, but never labelled as an SSH endpoint or claimed reachable
- **Guarded changes** - Full template clones, CPU/memory changes, grow-only VM disks, start,
  graceful shutdown, and snapshot creation preview and require interactive confirmation
- **Exact disk contracts** - Virtual disks retain configured byte counts, display unambiguous
  IEC units, and derive boot/data roles from Proxmox boot configuration
- **Concise, fail-closed growth** - `pmx disk grow <vm> <size>` selects automatically only for
  a single eligible disk; multi-disk VMs require an explicit slot and receive copy-ready retries
- **Visible clone placement** - Full-clone previews show source and target storage, configured
  provisioned capacity, and current availability for every virtual disk
- **State-race protection** - PMX re-reads identity/config after confirmation, uses Proxmox
  config digests where supported, and verifies the postcondition
- **Executable help** - `pmx help` lists every routed operation with required arguments;
  `pmx help vm`, `pmx help disk`, `pmx help snapshot`, and action topics provide purpose,
  syntax, examples, native equivalents, and safety boundaries
- **Educational output** - `--explain`, `--show-native`, `--dry-run`, `--json`, and
  human-readable tables reveal what PowerFlow is doing without exposing the saved SSH endpoint
- **Automation-safe clone JSON** - Clone output separates the requested plan from the verified
  result and retains exact per-disk byte/storage fields
- **Private disconnected state** - Remote SSH failures become alias-only state and actionable
  `srv <alias>` guidance; native authentication diagnostics stay behind the adapter boundary
- **Physical-disk evidence** - Local Linux views retain SMART, stable IDs, counterfeit-drive
  signals, RMA evidence bundles, and the destructive F3 safety gate
- **Modular design** - Parsing, connection state, configuration, host views, physical disks,
  evidence, VM reads, network configuration/runtime models, network rendering/orchestration,
  VM changes, snapshots, help, routing, and OS execution are separate components/adapters

### 🖥️ Terminal Tab Management

- **WSL tab launching** - Open an Ubuntu/WSL tab from PowerShell with `open-nt u` or `open-ubuntu`
- **WSL path bridging** - Translates the current Windows path to its `/mnt/…` WSL equivalent and copies the `cd` command to your clipboard
- **Shell shortcuts** - `open-nt p` (PowerShell), `open-nt u` (Ubuntu/WSL), `open-nt cmd` (Command Prompt)
- **Advanced tab control** - Navigate between tabs with `next-t`, `prev-t`, and numbered tab switching
- **Profile-aware launching** - Automatically detects and uses correct Windows Terminal profiles
- **Keyboard automation** - Uses SendKeys for seamless tab management

### 🎯 Productivity Features

- **One-command workflows** - Complex operations simplified into single, memorable commands
- **Intelligent defaults** - Smart parameter detection and context-aware behavior
- **Extensive help system** - Comprehensive documentation accessible via help commands
- **Quick configuration** - Interactive setup menus for customizing behavior without editing config files
- **Performance optimization** - Lazy loading and daily dependency checks minimize startup time
- **Error recovery** - Comprehensive recovery menus with guided troubleshooting steps

### 🔧 Developer Experience

- **Modern toolchain integration** - Works seamlessly with VS Code, Git, Node.js, and other development tools
- **Extensible architecture** - Easy to customize and extend with additional functionality
- **Professional workflows** - Supports enterprise development patterns and team collaboration
- **Version management** - Built-in update mechanisms and version tracking for easy maintenance



Linux Feature to be added if not done so already: 

lsblk --bytes --json -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,PKNAME
findmnt --json --bytes
df --block-size=1 --output=source,fstype,size,used,avail,pcent,target
swapon --show --bytes --output=NAME,TYPE,SIZE,USED,PRIO


sudo hostnamectl set-hostname docker-host
sudo sed -i 's/debian13-base/docker-host/g' /etc/hosts

Meaning:

hostnamectl set-hostname changes the computer’s hostname.
sed replaces the old hostname inside /etc/hosts.
-i means edit the file in place.

Verify:

hostnamectl --static

Expected:

docker-host

Your current shell prompt may continue showing the old name until you reconnect.

2. Give it a unique machine identity
sudo rm -f /etc/machine-id
sudo systemd-machine-id-setup

machine-id is Linux’s internal identifier for this installation. A clone should not retain the template’s identifier.

Verify that a new value exists:

cat /etc/machine-id

It should show a long hexadecimal value.

3. Generate unique SSH host keys
sudo rm -f /etc/ssh/ssh_host_*
sudo ssh-keygen -A
sudo sshd -t

Meaning:

Command	Purpose
rm -f /etc/ssh/ssh_host_*	Remove the copied server identity keys
ssh-keygen -A	Generate all missing SSH host keys
sshd -t	Test the SSH server configuration without restarting it

sshd -t should return no output when everything is valid.

Display the new ED25519 fingerprint:

ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
4. Reboot only the VM

--------------------

Required presentation
STORAGE
  Virtual disk     /dev/sda · 100 GiB
  Root filesystem  /dev/sda2 · ext4 · 29 GiB
  Root available   27 GiB
  EFI partition    /dev/sda1 · 975 MiB
  Swap             /dev/sda3 · 1.7 GiB
  Unallocated      approximately 68 GiB

Required JSON shape

  {
  "block_devices": [
    {
      "name": "/dev/sda",
      "type": "disk",
      "size_bytes": 107374182400,
      "virtual": true,
      "partitions": [
        {
          "name": "/dev/sda2",
          "filesystem": "ext4",
          "mountpoints": ["/"],
          "size_bytes": 31138512896,
          "available_bytes": 28991029248
        }
      ]
    }
  ],
  "swap": [
    {
      "name": "/dev/sda3",
      "size_bytes": 1825361100,
      "used_bytes": 0
    }
  ]
}


Fixes to consider: 

PowerFlow must not calculate storage values by parsing its own formatted sentence.

Required: iGPU is incorrectly labelled

Your output says:

iGPU Vendor 1234 Device 1111

Inside this VM, that is almost certainly a virtual display adapter presented by QEMU, not an integrated physical GPU.

The label should be:

Display adapter   QEMU virtual VGA

or:

Virtual GPU       Vendor 1234 · Device 1111

The function should use virtualization detection such as:

systemd-detect-virt
lspci -nn

When virtualization is detected, it should not label a display device as the host’s physical iGPU.

Recommended: clarify virtual RAM and firmware

These lines are also potentially misleading:

RAM   8 GB   install dmidecode for type/speed
BIOS  4.2025.05-2

Inside a VM:

the 8 GB is virtual RAM allocated by Proxmox;
dmidecode may only expose virtual SMBIOS information;
it cannot reliably describe the T440’s physical ECC RDIMMs;
the displayed BIOS is the VM’s virtual firmware, not the Dell T440 BIOS.

Better output:

Memory          8 GiB allocated to VM
Physical DIMMs  unavailable inside guest
Firmware        SeaBIOS/QEMU virtual firmware · 4.2025.05-2
Hypervisor      KVM/QEMU

Checkpoint:

We need to be able to do this in powerflow: 

Tiny lesson: the diagnosis is confirmed.

```text
/dev/sda     100G   whole virtual disk
/dev/sda2   29.4G   Debian root filesystem
/dev/sda3    1.7G   swap
```

Roughly **68 GiB is still unallocated**. Debian can see the larger building, but those rooms have not been assigned to a department.

Because the swap partition sits after the root partition:

```text
sda1 → EFI
sda2 → /
sda3 → swap
free space → about 68 GiB
```

we cannot simply stretch `sda2` into the free space without moving or removing `sda3`.

For this Docker VM, the cleaner beginner-friendly plan is:

```text
sda2   Debian operating system
sda3   swap
sda4   Docker service data
```

We will mount `sda4` at:

```text
/srv/docker
```

Later Docker will store containers, images, volumes, and service data there instead of filling Debian’s root filesystem.

Before creating anything, inspect the exact partition boundaries:

```bash
sudo fdisk -l /dev/sda
```

Also confirm the root filesystem capacity:

```bash
df -hT /
```

`fdisk -l` means:

* `fdisk` — inspect or edit disk partition tables
* `-l` — list the current layout
* `/dev/sda` — inspect this specific disk

Do not enter interactive `fdisk` yet. Send both outputs.

Checkpoint:

1. Why can’t `sda2` simply grow directly into the free space?
2. What will `/srv/docker` hold?
3. Is the unused 68 GiB currently part of any filesystem?


Tiny lesson: the disk map confirms exactly what we expected.

```text
Whole virtual disk      /dev/sda   100 GiB
Debian root partition   /dev/sda2   29.4 GiB
Swap                    /dev/sda3    1.7 GiB
Unallocated space                  about 68 GiB
```

The warning:

```text
The backup GPT table is not on the end of the device.
```

appeared because the disk used to be 32 GiB. GPT keeps a backup copy of the partition map at the end of the disk, and that backup is still sitting at the old 32 GiB boundary. Writing the partition table once will move it to the new end of the 100 GiB disk.

We will create only `/dev/sda4`. Do not delete or alter `sda1`, `sda2`, or `sda3`.

Run:

```bash
sudo fdisk /dev/sda
```

Inside `fdisk`, enter these keys one at a time:

```text
n
Enter
Enter
Enter
p
```

Meaning:

| Input          | Action                                  |
| -------------- | --------------------------------------- |
| `n`            | Create a new partition                  |
| first `Enter`  | Accept partition number `4`             |
| second `Enter` | Accept the first free sector            |
| third `Enter`  | Use all remaining space                 |
| `p`            | Print the proposed layout before saving |

At the preview, verify that:

```text
sda1   still 976M
sda2   still 29.4G
sda3   still 1.7G
sda4   approximately 68G
```

Do **not** type `d`, `g`, or `o`:

* `d` deletes a partition.
* `g` creates a new empty GPT table.
* `o` creates a new empty DOS partition table.

Only when the preview is correct, type:

```text
w
```

`w` means **write the changes**. It will also repair the GPT backup-table location.

Then verify:

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
```

Expected new line:

```text
sda4   approximately 68G   part
```

It should have no filesystem and no mount point yet. That is correct—we will format and mount it only after verifying the partition.


Tiny lesson: the new partition exists, but it is still an empty room with no shelving system.

```text
/dev/sda4   68G   partition
Filesystem  none
Mount point none
```

Now create an **ext4 filesystem** on that new partition:

```4 filesystem** on thatbash
sudo mkfs.ext4 -L docker-data /dev/sda4
```

Meaning:

| Part             | Meaning                         |
| ---------------- | ------------------------------- |
| `mkfs`           | make filesystem                 |
| `.ext4`          | create an ext4 filesystem       |
| `-L docker-data` | give it the label `docker-data` |
| `/dev/sda4`      | format this exact partition     |

This command is destructive to anything already on `/dev/sda4`, but the partition is newly created and empty. Do not substitute `sda`, `sda1`, `sda2`, or `sda3`.

After it finishes, verify:

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS /dev/sda
```

Expected important line:

```text
sda4   68G   ext4   docker-data
```

It should still have no mount point. We will mount it at `/srv/docker` in the next step.

Checkpoint:

1. What does `mkfs` do?
2. Why are we formatting `/dev/sda4` rather than `/dev/sda`?
3. Does creating a filesystem automatically mount the partition?
