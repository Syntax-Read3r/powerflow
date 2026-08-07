# PMX VM Network Inspection

**Status:** Implemented and locally verified on Windows and Linux PowerShell. Read-only acceptance
against the user's Proxmox host remains the final deployment check.

## Implementation result

- Added the four responsibility-focused components described below.
- Added the identical allow-listed VM-agent read to both management adapters.
- Added canonical routes, short conveniences, table/JSON contracts, help, registry entries, and
  documentation without adding public `pmx guest net` or root-level network routes.
- Windows PMX/network/Windows suites, Linux-container PMX suite, Linux parsing, profile loading,
  platform separation, command registry, and adapter-token parity pass locally.
- No command in this feature calls a mutation adapter or performs fallback discovery.

## Goal

Add a read-only, component-based Proxmox VM networking layer that speaks in user goals while
keeping Proxmox/QEMU implementation vocabulary inside the translation layer. It exposes two
independent sources:

- configured virtual NICs from the Proxmox VM configuration;
- runtime interfaces, addresses, and counters reported by the VM agent.

The combined view may relate records by normalized MAC address, but no component may silently treat
a Proxmox slot such as `net0` as a guest interface such as `ens18`.

## Command contract

Canonical, goal-based commands:

```text
pmx vm network <name|vmid>
pmx vm network adapters <name|vmid>
pmx vm network addresses <name|vmid>
pmx vm network stats <name|vmid>
pmx vm network list
```

Memorable short aliases:

```text
pmx vm net <name|vmid>        -> pmx vm network <name|vmid>
pmx vm nic <name|vmid>        -> pmx vm network adapters <name|vmid>
pmx vm ip <name|vmid>         -> pmx vm network addresses <name|vmid>
pmx vm net stats <name|vmid>  -> pmx vm network stats <name|vmid>
pmx vm net list               -> pmx vm network list
```

Do not add `pmx guest net`, `pmx net`, or `pmx network` to the public interface. They make users
learn Proxmox's meaning of "guest" or lose the VM subject. Internally, the runtime-address adapter
may use Proxmox guest-command vocabulary, but normal output and main help must not expose it.

`pmx host net` and `pmx node net` remain reserved for a future host-network layer. VM networking
must not absorb host bridges, bonds, physical NICs, routes, or VLAN-aware bridge management.

## Routing decisions

- Extend the `pmx vm` router with exact `network`, `net`, `nic`, and `ip` routes.
- Route every alias to the same canonical handler; do not duplicate query, model, or rendering
  logic.
- Treat `adapters`, `addresses`, `stats`, and `list` as reserved actions before resolving a VM
  name, while still allowing ordinary VM names in the combined form.
- Leave the existing root `pmx guest [vmid|name]` behavior unchanged.
- Help routes are connection-independent: `pmx help vm network` and every detailed network topic
  must work on Windows without a configured/reachable Proxmox host.

## Supported options

```text
--table / -t
--json / -j
--all
--ipv4 / -4
--ipv6 / -6
--include-loopback
--show-native
--explain
```

Rules:

1. Output mode follows explicit option, configured default, then built-in table fallback.
2. Table/JSON conflicts and duplicate long/short spellings are errors.
3. IPv4 and IPv6 may be combined; neither means both families.
4. `--include-loopback` adds loopback rows while retaining normal filtering.
5. `--all` means include every valid guest-reported address, including loopback and unspecified
   rows. This gives `--all` a precise meaning without changing the all-VM inventory scope.
6. `-table`, `-json`, bundled `-tj`, and unknown short options remain invalid.
7. Adapter and stats views reject address-only filters instead of silently ignoring them.
8. JSON remains one pure document. `--show-native` and `--explain` populate structured `sources`
   and `explanations` fields rather than writing decorative text around JSON.
9. Native Proxmox/QEMU command vocabulary is absent unless `--show-native` is explicit. In JSON,
   native-command fields remain null unless that option is present.

## Component design

Do not place the feature in one file.

1. `components/proxmox/network-config-model.ps1`
   - Parse exact `netN` VM configuration entries.
   - Return slot, numeric slot order, model, bridge, raw/normalized MAC, firewall, VLAN tag,
     link-down state, rate limit, MTU, and sanitized raw value.
   - Expose agent-channel configuration separately from runtime reachability.
2. `components/proxmox/guest-network-model.ps1`
   - Normalize VM-agent interface, address, and traffic-counter records without querying Proxmox.
   - Classify IPv4/IPv6 addresses using numeric address bytes, not string prefixes.
   - Sort interfaces/addresses deterministically and filter loopback/unspecified rows by policy.
   - Match configured and guest interfaces only through valid normalized MAC values.
   - Rank inferred primary-address candidates while never testing or claiming reachability.
3. `components/proxmox/network-view.ps1`
   - Render adapter, address, stats, combined, and all-VM table views.
   - Build schema-versioned JSON contracts with explicit nulls and stable property ordering.
   - Keep headings/explanations on information output; JSON uses the success stream alone.
4. `components/proxmox/network-read.ps1`
   - Own strict argument parsing, VM resolution, read orchestration, failure classification, and
     alias handlers.
   - Reuse existing VM list/config/status queries and call one new internal VM-agent adapter query.
   - Never call `Invoke-ProxmoxManagementChange`.
5. Load the pure network models/views and read orchestrator after the existing VM resolver. The
   pending `pmx vm show --full` renderer reuses configured adapter models but never VM runtime
   queries unless the user invokes the network commands.

## Adapter extension

Add one allow-listed read operation, `vm-guest-network`, to both management adapters.

Inputs:

```text
Node, Vmid
```

Internal native source (displayed only with `--show-native`):

```text
qm guest cmd <vmid> network-get-interfaces
```

The adapter will execute a fixed token array locally or through the existing saved-alias SSH
transport, parse JSON, and return the established structured result. It will categorize timeout,
unsupported-command, and guest-agent-unreachable failures without returning saved SSH endpoint
data. No user text becomes a shell command, and no mutation operation is added.

The normal table, JSON, warning, and help vocabulary says VM agent, adapter, address, and stats.
The raw `qm guest cmd ... network-get-interfaces` translation is educational detail gated by
`--show-native`, never the public command users are instructed to run.

Before implementation, token fixtures will be checked against the installed Proxmox `qm help`
surface on the real host because the public documentation search exposes the `qm`/`pvesh` command
families but did not provide a reliably fetchable per-command schema.

## Configured NIC model

Recognized properties include:

```text
net0: virtio=BC:24:11:AC:D9:AC,bridge=vmbr0,firewall=1,tag=20,link_down=0,rate=100,mtu=1500
```

Rules:

- Sort by numeric slot (`net2` before `net10`).
- Normalize valid MACs to uppercase colon-separated form.
- Preserve invalid/missing MAC text for diagnostics but set normalized MAC to null.
- Link is `down` only when `link_down=1`; otherwise it is configured up, not proven connected.
- Missing optional values become explicit nulls in JSON and `—` in tables.
- Configuration view works for stopped VMs and templates.

## Guest runtime model

Expected VM-agent fields are normalized from returned interface names, hardware/MAC addresses,
IP-address records, and optional receive/transmit counters. The model retains the raw safe record
for diagnostics but emits stable fields:

```text
name, mac, matched_configured_slot, addresses[], stats
```

`stats` contains nullable integer receive/transmit bytes, packets, errors, and dropped counters.
Byte displays use IEC units while JSON preserves exact integers. Missing counters are reported as
unavailable rather than fabricated as zero.

Runtime gates:

- Template: do not query the guest; configured NICs remain available.
- Stopped VM: do not query the guest; return a non-fatal stopped reason.
- Agent disabled: do not query; explain channel enablement separately from the in-guest package.
- Agent configured/running: query once and classify success, timeout, unsupported, or unreachable.
- A read command never enables the channel, installs a package, starts a service, or changes state.

## Address classification

Use `System.Net.IPAddress` parsing and address bytes so classification is platform-neutral and
does not hard-code one LAN.

IPv4: loopback, link-local, private, unspecified, multicast, or global/other.

IPv6: loopback, link-local, unique-local, unspecified, multicast, or global/other.

Invalid addresses remain diagnostic records with `family=unknown`, never candidates. Default views
hide loopback and unspecified rows and report hidden counts. IPv4 sorts before IPv6 unless filtered;
within a family, addresses sort numerically.

## MAC matching

- Match only when both records have the same valid normalized MAC.
- Never infer `net0 = ens18` or rely on array position.
- A unique match sets `matched_configured_slot` and the configured NIC's matched guest name(s).
- Duplicate/ambiguous MACs remain unmatched with a warning.
- Unmatched configured and guest records are both shown; neither is discarded.

## Primary address candidate inference

This is address ranking, not a connectivity or service probe.

- Exclude invalid, loopback, unspecified, and multicast addresses.
- Respect explicit IPv4/IPv6 filters; otherwise prefer IPv4.
- Prefer private/global/unique-local scopes over link-local.
- Prefer an interface uniquely MAC-matched to configured `net0`.
- Select only when exactly one address remains at the best rank.
- If best-ranked candidates tie, expose all candidates and set `primary_candidate` to null.
- JSON records `inferred=true`, the candidate list, and a deterministic reason. Table text says
  `Primary candidate (inferred)` and never says reachable, connected, or listening.

## All-VM summary

`pmx vm network list` queries VM inventory, then configuration per QEMU VM. It queries VM runtime
only for running, non-template VMs whose agent channel is configured.

- One guest-agent/config failure creates a per-VM error/status and does not abort the inventory.
- Emit one row per configured NIC so multi-NIC VMs lose no information; repeat VM identity fields.
- VMs without configured NICs still receive one row with null NIC fields.
- Include an explicit AGENT column/status rather than hiding failure behind a blank IPv4 field.
- Sort by VMID, numeric NIC slot, then numeric address.
- Templates and stopped VMs show `—` for runtime addresses.

## JSON contracts

Every network JSON document uses goal-based public field names:

```text
schema_version, command, generated_at, node, vm, agent,
adapters, interfaces, address_selection, sources,
warnings, explanations
```

Adapter-, address-, and stats-only commands retain the same top-level shape and use empty
arrays/explicit nulls for data not requested. Interface records own their `addresses[]` and nullable
`stats` object so exact runtime facts are not reconstructed from display strings. The list command
uses `schema_version`, `command`,
`generated_at`, `node`, and `vms[]`, where each VM entry has the same nested source separation.

JSON rules:

- snake_case stable names and explicit nulls;
- no emoji, ANSI, headings, or prose outside the JSON document;
- raw native errors are reduced to safe categorized messages;
- `address_selection` contains `primary_candidate`, `candidates`, `inferred`, and `reason`;
- `sources` identifies configured and VM-reported data independently, while its native-command
  value is null unless `--show-native` was requested;
- order is deterministic and does not depend on guest-agent return order.

## Human rendering

Combined table sections (`pmx vm network <vm>`):

1. VM identity/status/agent availability.
2. VIRTUAL ADAPTERS.
3. VM ADDRESSES.
4. Primary candidate(s), sources, warnings, and optional educational/native sections.

Required focused table fields:

```text
ADAPTERS: ADAPTER, MODEL, BRIDGE, MAC ADDRESS, FIREWALL, VLAN, LINK
ADDRESSES: INTERFACE, ADDRESS, TYPE, SCOPE, ADAPTER
STATS: INTERFACE, RX BYTES, RX PACKETS, TX BYTES, TX PACKETS, ERRORS, DROPPED
```

The address view ends with `Primary candidate <address>` and `Agent <status>`. It must not label the
candidate as an SSH endpoint. Stats are intentionally a focused view rather than noise in the
combined overview.

Adapter, address, and stats commands render only the requested view plus VM identity. The stats
table uses exact integer packet/error/drop counters and IEC byte displays. When runtime data is
unavailable, combined/adapter views still render configured adapters and a concise, non-fatal
reason; address/stats views fail cleanly without pretending an empty response means zero activity.

## Help contract

Update:

- main `pmx help` overview;
- `pmx help vm` family;
- `pmx help vm network`, `pmx help vm network adapters`,
  `pmx help vm network addresses`, `pmx help vm network stats`, and
  `pmx help vm network list`;
- short aliases and all supported long/short options.

Canonical examples remain VM-centered and goal-based. Main help must not advertise `guest cmd` or
`pmx guest net`. Detailed help distinguishes `net0`, adapter model, bridge, VM interface name, MAC
matching, IP ownership, and inferred-not-tested primary candidates. It describes `--show-native`
without printing a raw native command unless the user actually requests that option.

## Test plan

1. Parser/router matrix for every canonical and short alias, rejected former/root/guest shapes,
   reserved-action disambiguation, and option applicability.
2. Short options `-t`, `-j`, `-4`, `-6`; conflicts, duplicates, malformed long forms, and bundles.
3. Adapter token parity and hostile parameter rejection on Windows/Linux.
4. Config parser fixtures for multi-digit slots, NIC models, bridge, MAC normalization, firewall,
   VLAN, link-down, rate, MTU, missing values, malformed values, and terminal controls.
5. VM-agent fixtures for running/stopped/template, disabled/unreachable/timed-out/unsupported agent,
   multiple adapters, duplicate MACs, unmatched records, multiple IPs, loopback filtering, complete
   and missing traffic counters.
6. Complete IPv4/IPv6 boundary classification fixtures.
7. Primary-candidate ranking fixtures, including ties that must remain unresolved.
8. JSON schema/purity/explicit-null/stable-order snapshots for combined/adapters/addresses/stats/list,
   including the `--show-native` disclosure gate.
9. All-VM continuation when one VM query fails.
10. Static/read-only assertion that the new components never call a change adapter.
11. Complete PMX help inventory and Linux-container parity suites.

## Documentation and release

Update `COMPONENTS.md`, `README.md`, `docs/features.md`, `docs/troubleshooting.md`, PMX instructions,
issue/solved-problem records, session log, and v4.1.0 release notes. Because v4.1.0 is still
unreleased, this additive networking layer remains part of that minor release; `git-rl` owns the
version bump after real-host read-only verification.

## Real-host acceptance

- Compare `pmx vm network adapters <vm>` with `qm config <vmid>` for
  stopped/template/running VMs.
- Compare `pmx vm network addresses <vm>` and `pmx vm network stats <vm>` with the internal
  agent result, without exposing the native command unless `--show-native` is set.
- Prove the combined view matches only by MAC and labels the primary candidate inferred.
- Prove stopped/disabled/unreachable agent states preserve configured output.
- Prove one broken agent does not abort `pmx vm network list`.
- Parse redirected `--json` with `ConvertFrom-Json` and confirm no non-JSON success output.
- Confirm all network commands perform reads only.

## Rollback

Remove the four network components and loader entries, the single adapter read operation, router/help
aliases, tests, and docs. No saved configuration, guest, NIC, bridge, firewall, or Proxmox state
requires migration.

00000

The point of powerflow is to hide jorgun and make what the user wants to do easy and if there is error, the user is to be guided.

Do not use flags unnecessarily, use convinient straight forward methods

Translate this code into easily digestable and executable code. FYI, they may already be functions that have been created for some of the executed code. so first insure that there is no repeatation of functions

you in 🌐 docker-host in ~
❯ lsblk -o NAME,FSTYPE,LABEL,PARTLABEL,UUID,MOUNTPOINTS
NAME FSTYPE LABEL PARTLABEL UUID MOUNTPOINTS
sda
├─sda1 vfat BC3B-F0D6 /boot/efi
├─sda2 ext4 cf1b9139-2415-4f2d-8fa3-2abd9ea6857c /
├─sda3 swap e0de9e16-6e18-4315-adc0-ca14eee9234e [SWAP]
└─sda4 ext4 docker-data 0ad87e7b-028e-4da3-ae52-4caec91cf4c5
sr0

you in 🌐 docker-host in ~
❯ grep -vE '^[[:space:]]\*(#|$)' /etc/fstab
UUID=cf1b9139-2415-4f2d-8fa3-2abd9ea6857c / ext4 errors=remount-ro 0 1
UUID=BC3B-F0D6 /boot/efi vfat umask=0077 0 1
UUID=e0de9e16-6e18-4315-adc0-ca14eee9234e none swap sw 0 0
/dev/sr0 /media/cdrom0 udf,iso9660 user,noauto 0 0

you in 🌐 docker-host in ~
❯ sudo e2label /dev/sda2 rootfs

you in 🌐 docker-host in ~
❯ sudo swaplabel -L swap /dev/sda3
swaplabel: /dev/sda3: failed to write label: Text file busy

you in 🌐 docker-host in ~
❯ sudo umount /boot/efi

you in 🌐 docker-host in ~
❯ sudo fatlabel /dev/sda1 EFI
sudo: fatlabel: command not found

you in 🌐 docker-host in ~
❯ sudo mount /boot/efi

you in 🌐 docker-host in ~
❯ findmnt /boot/efi
TARGET SOURCE FSTYPE OPTIONS
/boot/efi /dev/sda1 vfat rw,relatime,fmask=0077,dmask=0077,codepage=437,iocharset=ascii,shortname=mixed,utf8,errors=remount-ro

you in 🌐 docker-host in ~
❯ sudo apt update
Hit:1 http://deb.debian.org/debian trixie InRelease
Hit:2 http://deb.debian.org/debian trixie-updates InRelease
Get:3 http://security.debian.org/debian-security trixie-security InRelease [43.4 kB]
Get:4 http://security.debian.org/debian-security trixie-security/main Sources [198 kB]
Get:5 http://security.debian.org/debian-security trixie-security/main amd64 Packages [232 kB]
Hit:6 https://packages.microsoft.com/debian/13/prod trixie InRelease
Fetched 473 kB in 1s (726 kB/s)
21 packages can be upgraded. Run 'apt list --upgradable' to see them.

you in 🌐 docker-host in ~ took 2s
❯ sudo umount /boot/efi

you in 🌐 docker-host in ~
❯ sudo fatlabel /dev/sda1 EFI
sudo: fatlabel: command not found

you in 🌐 docker-host in ~
❯ sudo mount /boot/efi

you in 🌐 docker-host in ~
❯ findmnt /boot/efi
TARGET SOURCE FSTYPE OPTIONS
/boot/efi /dev/sda1 vfat rw,relatime,fmask=0077,dmask=0077,codepage=437,iocharset=ascii,shortname=mixed,utf8,errors=remount-ro

you in 🌐 docker-host in ~
❯ free -h
total used free shared buff/cache available
Mem: 7.7Gi 557Mi 6.6Gi 44Mi 879Mi 7.2Gi
Swap: 1.7Gi 0B 1.7Gi

you in 🌐 docker-host in ~
❯ swapon --show
swapon: The term 'swapon' is not recognized as a name of a cmdlet, function, script file, or executable program.
Check the spelling of the name, or if a path was included, verify that the path is correct and try again.

you in 🌐 docker-host in ~
❯ sudo apt install -y dosfstools
Installing:
dosfstools

Summary:
Upgrading: 0, Installing: 1, Removing: 0, Not Upgrading: 21
Download size: 133 kB
Space needed: 317 kB / 27.5 GB available

Get:1 http://deb.debian.org/debian trixie/main amd64 dosfstools amd64 4.2-1.2 [133 kB]
Fetched 133 kB in 0s (2,271 kB/s)
Selecting previously unselected package dosfstools.
(Reading database ... 39819 files and directories currently installed.)
Preparing to unpack .../dosfstools_4.2-1.2_amd64.deb ...
Unpacking dosfstools (4.2-1.2) ...
Setting up dosfstools (4.2-1.2) ...
Processing triggers for man-db (2.13.1-1) ...

you in 🌐 docker-host in ~ took 2s
❯ Test-Path /usr/sbin/fatlabel
True

you in 🌐 docker-host in ~
❯ sudo umount /boot/efi

you in 🌐 docker-host in ~
❯ sudo /usr/sbin/fatlabel /dev/sda1 EFI

you in 🌐 docker-host in ~
❯ sudo mount /boot/efi

you in 🌐 docker-host in ~
❯ findmnt /boot/efi
TARGET SOURCE FSTYPE OPTIONS
/boot/efi /dev/sda1 vfat rw,relatime,fmask=0077,dmask=0077,codepage=437,iocharset=ascii,shortname=mixed,utf8,errors=remount-ro

you in 🌐 docker-host in ~
❯ sudo /usr/sbin/swapon --show
NAME TYPE SIZE USED PRIO
/dev/sda3 partition 1.7G 0B -2

you in 🌐 docker-host in ~
❯ lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINTS
NAME SIZE FSTYPE LABEL UUID MOUNTPOINTS
sda 100G
├─sda1 976M vfat EFI BC3B-F0D6 /boot/efi
├─sda2 29.4G ext4 cf1b9139-2415-4f2d-8fa3-2abd9ea6857c /
├─sda3 1.7G swap e0de9e16-6e18-4315-adc0-ca14eee9234e [SWAP]
└─sda4 68G ext4 docker-data 0ad87e7b-028e-4da3-ae52-4caec91cf4c5
sr0 1024M

you in 🌐 docker-host in ~
❯ sudo /usr/sbin/e2label /dev/sda2 rootfs

you in 🌐 docker-host in ~
❯ sudo /usr/sbin/e2label /dev/sda2
rootfs

you in 🌐 docker-host in ~
❯ sudo /usr/sbin/swapoff /dev/sda3

you in 🌐 docker-host in ~
❯ sudo /usr/sbin/swaplabel -L swap /dev/sda3

you in 🌐 docker-host in ~
❯ sudo /usr/sbin/swapon /dev/sda3

you in 🌐 docker-host in ~
❯ lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINTS
NAME SIZE FSTYPE LABEL UUID MOUNTPOINTS
sda 100G
├─sda1 976M vfat EFI BC3B-F0D6 /boot/efi
├─sda2 29.4G ext4 cf1b9139-2415-4f2d-8fa3-2abd9ea6857c /
├─sda3 1.7G swap swap e0de9e16-6e18-4315-adc0-ca14eee9234e [SWAP]
└─sda4 68G ext4 docker-data 0ad87e7b-028e-4da3-ae52-4caec91cf4c5
sr0 1024M

you in 🌐 docker-host in ~
❯ sudo /usr/sbin/blkid -p /dev/sda2
/dev/sda2: LABEL="rootfs" UUID="cf1b9139-2415-4f2d-8fa3-2abd9ea6857c" VERSION="1.0" FSBLOCKSIZE="4096" BLOCK_SIZE="4096" FSLASTBLOCK="7703808" FSSIZE="31554797568" TYPE="ext4" USAGE="filesystem" PART_ENTRY_SCHEME="gpt" PART_ENTRY_UUID="263ef7b9-a8d8-4fbe-8e34-b00c48d41c2e" PART_ENTRY_TYPE="0fc63daf-8483-4772-8e79-3d69d8477de4" PART_ENTRY_NUMBER="2" PART_ENTRY_OFFSET="2000896" PART_ENTRY_SIZE="61630464" PART_ENTRY_DISK="8:0"

you in 🌐 docker-host in ~
❯ sudo mkdir -p /srv/docker

you in 🌐 docker-host in ~
❯ sudo mount /dev/sda4 /srv/docker

you in 🌐 docker-host in ~
❯ findmnt /srv/docker
TARGET SOURCE FSTYPE OPTIONS
/srv/docker /dev/sda4 ext4 rw,relatime

you in 🌐 docker-host in ~
❯ df -hT /srv/docker
Filesystem Type Size Used Avail Use% Mounted on
/dev/sda4 ext4 67G 2.1M 63G 1% /srv/docker

you in 🌐 docker-host in ~
❯ ls -ld /srv/docker
drwxr-xr-x root root 4.0 KB Thu Aug 6 17:50:13 2026  /srv/docker

you in 🌐 docker-host in ~

.........

We need a better way to perform this, inputting UUID is not the way forward

you in 🌐 docker-host in ~
❯ findmnt /srv/docker
TARGET SOURCE FSTYPE OPTIONS
/srv/docker /dev/sda4 ext4 rw,relatime

you in 🌐 docker-host in ~
❯ df -hT /srv/docker
Filesystem Type Size Used Avail Use% Mounted on
/dev/sda4 ext4 67G 2.1M 63G 1% /srv/docker

you in 🌐 docker-host in ~
❯ lsblk -d -o NAME,SIZE,MODEL,TYPE
NAME SIZE MODEL TYPE
sda 100G QEMU HARDDISK disk
sr0 1024M QEMU DVD-ROM rom

you in 🌐 docker-host in ~
❯ sudo cp /etc/fstab /etc/fstab.before-docker-data
[sudo] password for you:
Sorry, try again.
[sudo] password for you:

you in 🌐 docker-host in ~ took 10s
❯ grep -n '0ad87e7b-028e-4da3-ae52-4caec91cf4c5' /etc/fstab

you in 🌐 docker-host in ~
❯ 'UUID=0ad87e7b-028e-4da3-ae52-4caec91cf4c5 /srv/docker ext4 defaults 0 2' | sudo tee -a /etc/fstab
UUID=0ad87e7b-028e-4da3-ae52-4caec91cf4c5 /srv/docker ext4 defaults 0 2

you in 🌐 docker-host in ~
❯ sudo mount -a

you in 🌐 docker-host in ~
❯ findmnt /srv/docker
TARGET SOURCE FSTYPE OPTIONS
/srv/docker /dev/sda4 ext4 rw,relatime

you in 🌐 docker-host in ~
❯ df -hT /srv/docker
Filesystem Type Size Used Avail Use% Mounted on
/dev/sda4 ext4 67G 2.1M 63G 1% /srv/docker

you in 🌐 docker-host in ~
❯ sudo apt install -y ca-certificates curl
ca-certificates is already the newest version (20250419).
curl is already the newest version (8.14.1-2+deb13u4).
Summary:
Upgrading: 0, Installing: 0, Removing: 0, Not Upgrading: 21

you in 🌐 docker-host in ~
❯ sudo /usr/bin/install -m 0755 -d /etc/apt/keyrings

you in 🌐 docker-host in ~
❯ sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc

you in 🌐 docker-host in ~
❯ sudo chmod a+r /etc/apt/keyrings/docker.asc

you in 🌐 docker-host in ~
❯ $arch = (dpkg --print-architecture).Trim()

you in 🌐 docker-host in ~
❯

you in 🌐 docker-host in ~
❯ @"
∙ Types: deb
∙ URIs: https://download.docker.com/linux/debian
∙ Suites: trixie
∙ Components: stable
∙ Architectures: $arch
∙ Signed-By: /etc/apt/keyrings/docker.asc
∙ "@ | sudo tee /etc/apt/sources.list.d/docker.sources
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: trixie
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc

you in 🌐 docker-host in ~
❯ sudo apt update
Hit:1 http://deb.debian.org/debian trixie InRelease
Hit:2 http://deb.debian.org/debian trixie-updates InRelease
Get:3 http://security.debian.org/debian-security trixie-security InRelease [43.4 kB]
Hit:4 https://packages.microsoft.com/debian/13/prod trixie InRelease
Get:5 https://download.docker.com/linux/debian trixie InRelease [32.5 kB]
Get:6 http://security.debian.org/debian-security trixie-security/main Sources [200 kB]
Get:7 https://download.docker.com/linux/debian trixie/stable amd64 Packages [43.8 kB]
Get:8 http://security.debian.org/debian-security trixie-security/main amd64 Packages [233 kB]
Get:9 http://security.debian.org/debian-security trixie-security/main Translation-en [142 kB]
Fetched 695 kB in 0s (1,556 kB/s)
21 packages can be upgraded. Run 'apt list --upgradable' to see them.

you in 🌐 docker-host in ~ took 2s
❯ sudo /usr/bin/install -d -m 0755 /etc/docker

you in 🌐 docker-host in ~
❯ sudo /usr/bin/install -d -m 0711 /srv/docker/engine

you in 🌐 docker-host in ~
❯ '{"data-root": "/srv/docker/engine"}' | sudo tee /etc/docker/daemon.json
{"data-root": "/srv/docker/engine"}

you in 🌐 docker-host in ~
❯ sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
Installing:
containerd.io docker-buildx-plugin docker-ce docker-ce-cli docker-compose-plugin

Installing dependencies:
docker-ce-rootless-extras iptables libip4tc2 libip6tc2 libnetfilter-conntrack3 libnfnetlink0 pigz

Suggested packages:
cgroupfs-mount | cgroup-lite docker-model-plugin firewalld

Summary:
Upgrading: 0, Installing: 12, Removing: 0, Not Upgrading: 21
Download size: 103 MB
Space needed: 398 MB / 27.5 GB available

Get:1 http://deb.debian.org/debian trixie/main amd64 libip4tc2 amd64 1.8.11-2 [20.0 kB]
Get:2 http://deb.debian.org/debian trixie/main amd64 libip6tc2 amd64 1.8.11-2 [20.3 kB]
Get:3 http://deb.debian.org/debian trixie/main amd64 libnfnetlink0 amd64 1.0.2-3 [14.4 kB]
Get:4 http://deb.debian.org/debian trixie/main amd64 libnetfilter-conntrack3 amd64 1.1.0-1 [42.1 kB]
Get:5 http://deb.debian.org/debian trixie/main amd64 iptables amd64 1.8.11-2 [361 kB]
Get:6 http://deb.debian.org/debian trixie/main amd64 pigz amd64 2.8-1 [62.7 kB]
Get:7 https://download.docker.com/linux/debian trixie/stable amd64 containerd.io amd64 2.3.3-1~debian.13~trixie [22.7 MB]
Get:8 https://download.docker.com/linux/debian trixie/stable amd64 docker-ce-cli amd64 5:29.7.2-1~debian.13~trixie [17.0 MB]
Get:9 https://download.docker.com/linux/debian trixie/stable amd64 docker-ce amd64 5:29.7.2-1~debian.13~trixie [24.0 MB]
Get:10 https://download.docker.com/linux/debian trixie/stable amd64 docker-buildx-plugin amd64 0.36.1-1~debian.13~trixie [17.2 MB]
Get:11 https://download.docker.com/linux/debian trixie/stable amd64 docker-ce-rootless-extras amd64 5:29.7.2-1~debian.13~trixie [10.2 MB]
Get:12 https://download.docker.com/linux/debian trixie/stable amd64 docker-compose-plugin amd64 5.4.0-1~debian.13~trixie [11.1 MB]
Fetched 103 MB in 2s (49.5 MB/s)
Selecting previously unselected package containerd.io.
(Reading database ... 39853 files and directories currently installed.)
Preparing to unpack .../00-containerd.io_2.3.3-1~debian.13~trixie_amd64.deb ...
Unpacking containerd.io (2.3.3-1~debian.13~trixie) ...
Selecting previously unselected package docker-ce-cli.
Preparing to unpack .../01-docker-ce-cli_5%3a29.7.2-1~debian.13~trixie_amd64.deb ...
Unpacking docker-ce-cli (5:29.7.2-1~debian.13~trixie) ...
Selecting previously unselected package libip4tc2:amd64.
Preparing to unpack .../02-libip4tc2_1.8.11-2_amd64.deb ...
Unpacking libip4tc2:amd64 (1.8.11-2) ...
Selecting previously unselected package libip6tc2:amd64.
Preparing to unpack .../03-libip6tc2_1.8.11-2_amd64.deb ...
Unpacking libip6tc2:amd64 (1.8.11-2) ...
Selecting previously unselected package libnfnetlink0:amd64.
Preparing to unpack .../04-libnfnetlink0_1.0.2-3_amd64.deb ...
Unpacking libnfnetlink0:amd64 (1.0.2-3) ...
Selecting previously unselected package libnetfilter-conntrack3:amd64.
Preparing to unpack .../05-libnetfilter-conntrack3_1.1.0-1_amd64.deb ...
Unpacking libnetfilter-conntrack3:amd64 (1.1.0-1) ...
Selecting previously unselected package iptables.
Preparing to unpack .../06-iptables_1.8.11-2_amd64.deb ...
Unpacking iptables (1.8.11-2) ...
Selecting previously unselected package docker-ce.
Preparing to unpack .../07-docker-ce_5%3a29.7.2-1~debian.13~trixie_amd64.deb ...
Unpacking docker-ce (5:29.7.2-1~debian.13~trixie) ...
Selecting previously unselected package pigz.
Preparing to unpack .../08-pigz_2.8-1_amd64.deb ...
Unpacking pigz (2.8-1) ...
Selecting previously unselected package docker-buildx-plugin.
Preparing to unpack .../09-docker-buildx-plugin_0.36.1-1~debian.13~trixie_amd64.deb ...
Unpacking docker-buildx-plugin (0.36.1-1~debian.13~trixie) ...
Selecting previously unselected package docker-ce-rootless-extras.
Preparing to unpack .../10-docker-ce-rootless-extras_5%3a29.7.2-1~debian.13~trixie_amd64.deb ...
Unpacking docker-ce-rootless-extras (5:29.7.2-1~debian.13~trixie) ...
Selecting previously unselected package docker-compose-plugin.
Preparing to unpack .../11-docker-compose-plugin_5.4.0-1~debian.13~trixie_amd64.deb ...
Unpacking docker-compose-plugin (5.4.0-1~debian.13~trixie) ...
Setting up libip4tc2:amd64 (1.8.11-2) ...
Setting up libip6tc2:amd64 (1.8.11-2) ...
Setting up docker-buildx-plugin (0.36.1-1~debian.13~trixie) ...
Setting up containerd.io (2.3.3-1~debian.13~trixie) ...
Created symlink '/etc/systemd/system/multi-user.target.wants/containerd.service' → '/usr/lib/systemd/system/containerd.service'.
Setting up docker-compose-plugin (5.4.0-1~debian.13~trixie) ...
Setting up docker-ce-cli (5:29.7.2-1~debian.13~trixie) ...
Setting up pigz (2.8-1) ...
Setting up libnfnetlink0:amd64 (1.0.2-3) ...
Setting up docker-ce-rootless-extras (5:29.7.2-1~debian.13~trixie) ...
Setting up libnetfilter-conntrack3:amd64 (1.1.0-1) ...
Setting up iptables (1.8.11-2) ...
update-alternatives: using /usr/sbin/iptables-legacy to provide /usr/sbin/iptables (iptables) in auto mode
update-alternatives: using /usr/sbin/ip6tables-legacy to provide /usr/sbin/ip6tables (ip6tables) in auto mode
update-alternatives: using /usr/sbin/iptables-nft to provide /usr/sbin/iptables (iptables) in auto mode
update-alternatives: using /usr/sbin/ip6tables-nft to provide /usr/sbin/ip6tables (ip6tables) in auto mode
update-alternatives: using /usr/sbin/arptables-nft to provide /usr/sbin/arptables (arptables) in auto mode
update-alternatives: using /usr/sbin/ebtables-nft to provide /usr/sbin/ebtables (ebtables) in auto mode
Setting up docker-ce (5:29.7.2-1~debian.13~trixie) ...
Created symlink '/etc/systemd/system/multi-user.target.wants/docker.service' → '/usr/lib/systemd/system/docker.service'.
Created symlink '/etc/systemd/system/sockets.target.wants/docker.socket' → '/usr/lib/systemd/system/docker.socket'.
Processing triggers for man-db (2.13.1-1) ...
Processing triggers for libc-bin (2.41-12+deb13u3) ...

you in 🌐 docker-host in ~ took 18s
❯ sudo systemctl is-active docker
active

you in 🌐 docker-host in ~
❯ sudo docker compose version
Docker Compose version v5.4.0

you in 🌐 docker-host in ~
❯ sudo docker info --format '{{.DockerRootDir}}'
/srv/docker/engine

you in 🌐 docker-host in ~
❯ sudo docker run --rm hello-world
Unable to find image 'hello-world:latest' locally
latest: Pulling from library/hello-world
4f55086f7dd0: Pull complete
d5e71e642bf5: Download complete
Digest: sha256:7f4da0fc94bcece205a8c0b6f4d11c8196924654ffe5c4d1aa439b7f632048b2
Status: Downloaded newer image for hello-world:latest

Hello from Docker!
This message shows that your installation appears to be working correctly.

To generate this message, Docker took the following steps:

1.  The Docker client contacted the Docker daemon.
2.  The Docker daemon pulled the "hello-world" image from the Docker Hub.
    (amd64)
3.  The Docker daemon created a new container from that image which runs the
    executable that produces the output you are currently reading.
4.  The Docker daemon streamed that output to the Docker client, which sent it
    to your terminal.

To try something more ambitious, you can run an Ubuntu container with:
$ docker run -it ubuntu bash

Share images, automate workflows, and more with a free Docker ID:
https://hub.docker.com/

For more examples and ideas, visit:
https://docs.docker.com/get-started/



you in 🌐 docker-host in ~
❯ sudo apt install -y ca-certificates curl
ca-certificates is already the newest version (20250419).
curl is already the newest version (8.14.1-2+deb13u4).
Summary:
  Upgrading: 0, Installing: 0, Removing: 0, Not Upgrading: 21

you in 🌐 docker-host in ~
❯ sudo /usr/bin/install -m 0755 -d /etc/apt/keyrings

you in 🌐 docker-host in ~
❯ sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc

you in 🌐 docker-host in ~
❯ sudo chmod a+r /etc/apt/keyrings/docker.asc

you in 🌐 docker-host in ~
❯ $arch = (dpkg --print-architecture).Trim()

you in 🌐 docker-host in ~
❯

you in 🌐 docker-host in ~
❯ @"
∙ Types: deb
∙ URIs: https://download.docker.com/linux/debian
∙ Suites: trixie
∙ Components: stable
∙ Architectures: $arch
∙ Signed-By: /etc/apt/keyrings/docker.asc
∙ "@ | sudo tee /etc/apt/sources.list.d/docker.sources
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: trixie
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc

you in 🌐 docker-host in ~
❯ sudo apt update
Hit:1 http://deb.debian.org/debian trixie InRelease
Hit:2 http://deb.debian.org/debian trixie-updates InRelease
Get:3 http://security.debian.org/debian-security trixie-security InRelease [43.4 kB]
Hit:4 https://packages.microsoft.com/debian/13/prod trixie InRelease
Get:5 https://download.docker.com/linux/debian trixie InRelease [32.5 kB]
Get:6 http://security.debian.org/debian-security trixie-security/main Sources [200 kB]
Get:7 https://download.docker.com/linux/debian trixie/stable amd64 Packages [43.8 kB]
Get:8 http://security.debian.org/debian-security trixie-security/main amd64 Packages [233 kB]
Get:9 http://security.debian.org/debian-security trixie-security/main Translation-en [142 kB]
Fetched 695 kB in 0s (1,556 kB/s)
21 packages can be upgraded. Run 'apt list --upgradable' to see them.

you in 🌐 docker-host in ~ took 2s
❯ sudo /usr/bin/install -d -m 0755 /etc/docker

you in 🌐 docker-host in ~
❯ sudo /usr/bin/install -d -m 0711 /srv/docker/engine

you in 🌐 docker-host in ~
❯ '{"data-root": "/srv/docker/engine"}' | sudo tee /etc/docker/daemon.json
{"data-root": "/srv/docker/engine"}

you in 🌐 docker-host in ~
❯ sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
Installing:
  containerd.io  docker-buildx-plugin  docker-ce  docker-ce-cli  docker-compose-plugin

Installing dependencies:
  docker-ce-rootless-extras  iptables  libip4tc2  libip6tc2  libnetfilter-conntrack3  libnfnetlink0  pigz

Suggested packages:
  cgroupfs-mount  | cgroup-lite  docker-model-plugin  firewalld

Summary:
  Upgrading: 0, Installing: 12, Removing: 0, Not Upgrading: 21
  Download size: 103 MB
  Space needed: 398 MB / 27.5 GB available

Get:1 http://deb.debian.org/debian trixie/main amd64 libip4tc2 amd64 1.8.11-2 [20.0 kB]
Get:2 http://deb.debian.org/debian trixie/main amd64 libip6tc2 amd64 1.8.11-2 [20.3 kB]
Get:3 http://deb.debian.org/debian trixie/main amd64 libnfnetlink0 amd64 1.0.2-3 [14.4 kB]
Get:4 http://deb.debian.org/debian trixie/main amd64 libnetfilter-conntrack3 amd64 1.1.0-1 [42.1 kB]
Get:5 http://deb.debian.org/debian trixie/main amd64 iptables amd64 1.8.11-2 [361 kB]
Get:6 http://deb.debian.org/debian trixie/main amd64 pigz amd64 2.8-1 [62.7 kB]
Get:7 https://download.docker.com/linux/debian trixie/stable amd64 containerd.io amd64 2.3.3-1~debian.13~trixie [22.7 MB]
Get:8 https://download.docker.com/linux/debian trixie/stable amd64 docker-ce-cli amd64 5:29.7.2-1~debian.13~trixie [17.0 MB]
Get:9 https://download.docker.com/linux/debian trixie/stable amd64 docker-ce amd64 5:29.7.2-1~debian.13~trixie [24.0 MB]
Get:10 https://download.docker.com/linux/debian trixie/stable amd64 docker-buildx-plugin amd64 0.36.1-1~debian.13~trixie [17.2 MB]
Get:11 https://download.docker.com/linux/debian trixie/stable amd64 docker-ce-rootless-extras amd64 5:29.7.2-1~debian.13~trixie [10.2 MB]
Get:12 https://download.docker.com/linux/debian trixie/stable amd64 docker-compose-plugin amd64 5.4.0-1~debian.13~trixie [11.1 MB]
Fetched 103 MB in 2s (49.5 MB/s)
Selecting previously unselected package containerd.io.
(Reading database ... 39853 files and directories currently installed.)
Preparing to unpack .../00-containerd.io_2.3.3-1~debian.13~trixie_amd64.deb ...
Unpacking containerd.io (2.3.3-1~debian.13~trixie) ...
Selecting previously unselected package docker-ce-cli.
Preparing to unpack .../01-docker-ce-cli_5%3a29.7.2-1~debian.13~trixie_amd64.deb ...
Unpacking docker-ce-cli (5:29.7.2-1~debian.13~trixie) ...
Selecting previously unselected package libip4tc2:amd64.
Preparing to unpack .../02-libip4tc2_1.8.11-2_amd64.deb ...
Unpacking libip4tc2:amd64 (1.8.11-2) ...
Selecting previously unselected package libip6tc2:amd64.
Preparing to unpack .../03-libip6tc2_1.8.11-2_amd64.deb ...
Unpacking libip6tc2:amd64 (1.8.11-2) ...
Selecting previously unselected package libnfnetlink0:amd64.
Preparing to unpack .../04-libnfnetlink0_1.0.2-3_amd64.deb ...
Unpacking libnfnetlink0:amd64 (1.0.2-3) ...
Selecting previously unselected package libnetfilter-conntrack3:amd64.
Preparing to unpack .../05-libnetfilter-conntrack3_1.1.0-1_amd64.deb ...
Unpacking libnetfilter-conntrack3:amd64 (1.1.0-1) ...
Selecting previously unselected package iptables.
Preparing to unpack .../06-iptables_1.8.11-2_amd64.deb ...
Unpacking iptables (1.8.11-2) ...
Selecting previously unselected package docker-ce.
Preparing to unpack .../07-docker-ce_5%3a29.7.2-1~debian.13~trixie_amd64.deb ...
Unpacking docker-ce (5:29.7.2-1~debian.13~trixie) ...
Selecting previously unselected package pigz.
Preparing to unpack .../08-pigz_2.8-1_amd64.deb ...
Unpacking pigz (2.8-1) ...
Selecting previously unselected package docker-buildx-plugin.
Preparing to unpack .../09-docker-buildx-plugin_0.36.1-1~debian.13~trixie_amd64.deb ...
Unpacking docker-buildx-plugin (0.36.1-1~debian.13~trixie) ...
Selecting previously unselected package docker-ce-rootless-extras.
Preparing to unpack .../10-docker-ce-rootless-extras_5%3a29.7.2-1~debian.13~trixie_amd64.deb ...
Unpacking docker-ce-rootless-extras (5:29.7.2-1~debian.13~trixie) ...
Selecting previously unselected package docker-compose-plugin.
Preparing to unpack .../11-docker-compose-plugin_5.4.0-1~debian.13~trixie_amd64.deb ...
Unpacking docker-compose-plugin (5.4.0-1~debian.13~trixie) ...
Setting up libip4tc2:amd64 (1.8.11-2) ...
Setting up libip6tc2:amd64 (1.8.11-2) ...
Setting up docker-buildx-plugin (0.36.1-1~debian.13~trixie) ...
Setting up containerd.io (2.3.3-1~debian.13~trixie) ...
Created symlink '/etc/systemd/system/multi-user.target.wants/containerd.service' → '/usr/lib/systemd/system/containerd.service'.
Setting up docker-compose-plugin (5.4.0-1~debian.13~trixie) ...
Setting up docker-ce-cli (5:29.7.2-1~debian.13~trixie) ...
Setting up pigz (2.8-1) ...
Setting up libnfnetlink0:amd64 (1.0.2-3) ...
Setting up docker-ce-rootless-extras (5:29.7.2-1~debian.13~trixie) ...
Setting up libnetfilter-conntrack3:amd64 (1.1.0-1) ...
Setting up iptables (1.8.11-2) ...
update-alternatives: using /usr/sbin/iptables-legacy to provide /usr/sbin/iptables (iptables) in auto mode
update-alternatives: using /usr/sbin/ip6tables-legacy to provide /usr/sbin/ip6tables (ip6tables) in auto mode
update-alternatives: using /usr/sbin/iptables-nft to provide /usr/sbin/iptables (iptables) in auto mode
update-alternatives: using /usr/sbin/ip6tables-nft to provide /usr/sbin/ip6tables (ip6tables) in auto mode
update-alternatives: using /usr/sbin/arptables-nft to provide /usr/sbin/arptables (arptables) in auto mode
update-alternatives: using /usr/sbin/ebtables-nft to provide /usr/sbin/ebtables (ebtables) in auto mode
Setting up docker-ce (5:29.7.2-1~debian.13~trixie) ...
Created symlink '/etc/systemd/system/multi-user.target.wants/docker.service' → '/usr/lib/systemd/system/docker.service'.
Created symlink '/etc/systemd/system/sockets.target.wants/docker.socket' → '/usr/lib/systemd/system/docker.socket'.
Processing triggers for man-db (2.13.1-1) ...
Processing triggers for libc-bin (2.41-12+deb13u3) ...

you in 🌐 docker-host in ~ took 18s
❯ sudo systemctl is-active docker
active

you in 🌐 docker-host in ~
❯ sudo docker compose version
Docker Compose version v5.4.0

you in 🌐 docker-host in ~
❯ sudo docker info --format '{{.DockerRootDir}}'
/srv/docker/engine

you in 🌐 docker-host in ~
❯ sudo docker run --rm hello-world
Unable to find image 'hello-world:latest' locally
latest: Pulling from library/hello-world
4f55086f7dd0: Pull complete
d5e71e642bf5: Download complete
Digest: sha256:7f4da0fc94bcece205a8c0b6f4d11c8196924654ffe5c4d1aa439b7f632048b2
Status: Downloaded newer image for hello-world:latest

Hello from Docker!
This message shows that your installation appears to be working correctly.

To generate this message, Docker took the following steps:
 1. The Docker client contacted the Docker daemon.
 2. The Docker daemon pulled the "hello-world" image from the Docker Hub.
    (amd64)
 3. The Docker daemon created a new container from that image which runs the
    executable that produces the output you are currently reading.
 4. The Docker daemon streamed that output to the Docker client, which sent it
    to your terminal.

To try something more ambitious, you can run an Ubuntu container with:
 $ docker run -it ubuntu bash

Share images, automate workflows, and more with a free Docker ID:
 https://hub.docker.com/

For more examples and ideas, visit:
 https://docs.docker.com/get-started/


you in 🌐 docker-host in ~ took 4s
❯ sudo /usr/bin/install -d -m 0755 /srv/docker/apps/jellyfin/config

you in 🌐 docker-host in ~
❯ sudo /usr/bin/install -d -m 0755 /srv/docker/apps/jellyfin/cache

you in 🌐 docker-host in ~
❯ sudo /usr/bin/install -d -m 0755 /srv/docker/media/movies

you in 🌐 docker-host in ~
❯ sudo /usr/bin/install -d -m 0755 /srv/docker/media/tv

you in 🌐 docker-host in ~
❯ sudo /usr/bin/install -d -m 0755 /srv/docker/media/music

you in 🌐 docker-host in ~
❯ sudo /usr/bin/chown -R you:you /srv/docker/apps /srv/docker/media

you in 🌐 docker-host in ~
❯ $jellyfinUid = (& /usr/bin/id -u).Trim()

you in 🌐 docker-host in ~
❯ $jellyfinGid = (& /usr/bin/id -g).Trim()

you in 🌐 docker-host in ~
❯

you in 🌐 docker-host in ~
❯ @"
∙ JELLYFIN_UID=$jellyfinUid
∙ JELLYFIN_GID=$jellyfinGid
∙ "@ | Set-Content /srv/docker/apps/jellyfin/.env

you in 🌐 docker-host in ~
❯ Get-Content /srv/docker/apps/jellyfin/.env
JELLYFIN_UID=1000
JELLYFIN_GID=1000

you in 🌐 docker-host in ~
❯ @'
∙ services:
∙   jellyfin:
∙     image: jellyfin/jellyfin:latest
∙     container_name: jellyfin
∙     user: "${JELLYFIN_UID}:${JELLYFIN_GID}"
∙
∙     ports:
∙       - "192.168.1.50:8096:8096/tcp"
∙
∙     volumes:
∙       - ./config:/config
∙       - ./cache:/cache
∙       - type: bind
∙         source: /srv/docker/media
∙         target: /media
∙         read_only: true
∙
∙     restart: unless-stopped
∙ '@ | Set-Content /srv/docker/apps/jellyfin/compose.yaml

you in 🌐 docker-host in ~
❯ Set-Location /srv/docker/apps/jellyfin

you in 🌐 docker-host in docker/apps/jellyfin
❯ sudo docker compose config
name: jellyfin
services:
  jellyfin:
    container_name: jellyfin
    image: jellyfin/jellyfin:latest
    networks:
      default: null
    ports:
      - mode: ingress
        host_ip: 192.168.1.50
        target: 8096
        published: "8096"
        protocol: tcp
    restart: unless-stopped
    user: 1000:1000
    volumes:
      - type: bind
        source: /srv/docker/apps/jellyfin/config
        target: /config
        bind: {}
      - type: bind
        source: /srv/docker/apps/jellyfin/cache
        target: /cache
        bind: {}
      - type: bind
        source: /srv/docker/media
        target: /media
        read_only: true
networks:
  default:
    name: jellyfin_default

you in 🌐 docker-host in docker/apps/jellyfin
❯

you in 🌐 docker-host in docker/apps/jellyfin
❯ sudo docker compose ps
NAME       IMAGE                      COMMAND                SERVICE    CREATED          STATUS                    PORTS
jellyfin   jellyfin/jellyfin:latest   "/jellyfin/jellyfin"   jellyfin   13 minutes ago   Up 13 minutes (healthy)   192.168.1.50:8096->8096/tcp

you in 🌐 docker-host in docker/apps/jellyfin
❯

we need a more streamline version of this: ~
❯ nav .\Videos\
📁 .\Videos\

~\Videos
❯ ls
 Captures   NVIDIA   '2026-01-12 16-34-48.mp4'   '2026-01-12 16-37-18.mp4'   '2026-01-12 16-50-03.mp4'   Graduation.mp4

~\Videos
❯ pwd

Path
----
C:\Users\you\Videos


~\Videos
❯ scp "C:\Users\you\Videos\2026-01-12 16-37-18.mp4" you@192.168.1.50:/home/you/
you@192.168.1.50's password:
2026-01-12 16-37-18.mp4                                                                                                                                                                            100%  124MB  89.5MB/s   00:01

~\Videos took 4s
❯


We need a one lline installer i.e. install docker: this then does all the above, then another one line installer, install jelyfin, and it does all the above, and if im not in a docker or have a docker set up, the system identifies this and suggest that i install docker... This is the homelab media pathway, im now working on: 

Tiny lesson: **Jellyfin is the cinema, not the delivery truck.**

Jellyfin organises, identifies, and streams media files that already exist in its library folders. It may download posters, descriptions, subtitles, and other metadata, but it does not fetch movie files from torrents. ([Jellyfin][1])

The automated stack normally looks like this:

```text
Seerr
You request a movie or programme
        ↓
Radarr / Sonarr
Finds and manages the requested release
        ↓
Download client, such as qBittorrent
Downloads the file
        ↓
Radarr / Sonarr
Renames and moves it into /media/movies or /media/tv
        ↓
Jellyfin
Scans, catalogues and streams it
```

Radarr and Sonarr monitor a configured download client and handle completed downloads; Seerr provides the request interface connected to Jellyfin. ([Servarr Wiki][2])

So manual copying was only a basic test. Once the full stack is configured, media acquisition and organisation can be automated.

Use this system only for public-domain content, Linux ISOs, media you own, or material you are authorised to download.

Our installation order should now be:

```text
1. qBittorrent — downloader
2. Prowlarr — search-source manager
3. Radarr — movies
4. Sonarr — television
5. Seerr — friendly request screen
6. Jellyfin — playback
```

Jellyfin is already complete and healthy. The next hands-on service is the download client.

[1]: https://jellyfin.org/docs/general/server/media/movies/?utm_source=chatgpt.com "Movies | Jellyfin"
[2]: https://wiki.servarr.com/en/sonarr/quick-start-guide?utm_source=chatgpt.com "Sonarr Quick Start Guide | Servarr Wiki"


...

Tiny lesson: **qBittorrent is the downloader; Jellyfin is the player.** We will install qBittorrent now, but only use it for public-domain, Linux ISO, or other authorised downloads.

The LinuxServer qBittorrent image uses `/config` for settings, `/downloads` for downloaded files, port `8080` for the web interface, and `6881` for BitTorrent traffic. Its startup log provides a temporary password for the `admin` account. ([LinuxServer][1])

## Create its folders

```powershell
sudo /usr/bin/install -d -m 0755 /srv/docker/apps/qbittorrent/config
sudo /usr/bin/install -d -m 0755 /srv/docker/downloads/complete
sudo /usr/bin/install -d -m 0755 /srv/docker/downloads/incomplete
sudo /usr/bin/chown -R you:you /srv/docker/apps/qbittorrent /srv/docker/downloads
```

## Create the Compose file

```powershell
@'
services:
  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    container_name: qbittorrent

    environment:
      PUID: "1000"
      PGID: "1000"
      TZ: Europe/London
      WEBUI_PORT: "8080"
      TORRENTING_PORT: "6881"

    volumes:
      - ./config:/config
      - /srv/docker/downloads:/downloads

    ports:
      - "192.168.1.50:8080:8080/tcp"
      - "192.168.1.50:6881:6881/tcp"
      - "192.168.1.50:6881:6881/udp"

    restart: unless-stopped
'@ | Set-Content /srv/docker/apps/qbittorrent/compose.yaml
```

Binding the ports to `192.168.1.50` makes them available through that VM address instead of every address on the Docker host. ([Docker Documentation][2])

## Validate before starting

```powershell
Set-Location /srv/docker/apps/qbittorrent
sudo docker compose config
```

The resolved output should show:

```text
image: lscr.io/linuxserver/qbittorrent:latest
192.168.1.50:8080
192.168.1.50:6881 TCP and UDP
/srv/docker/downloads → /downloads
```

Do not start it yet. Send the `docker compose config` output.

Checkpoint:

1. Which directory keeps qBittorrent’s configuration?
2. Which host directory will contain completed and incomplete downloads?
3. Which port opens the web interface?

[1]: https://docs.linuxserver.io/images/docker-qbittorrent/ "qbittorrent - LinuxServer.io"
[2]: https://docs.docker.com/reference/compose-file/services/?utm_source=chatgpt.com "Define services in Docker Compose"

Tiny lesson: the Compose file is the prescription; `up -d` now admits the qBittorrent container and leaves it running in the background. Docker documents `-d` as detached mode. ([Docker Documentation][1])

From `/srv/docker/apps/qbittorrent`, run:

```powershell
sudo docker compose config
sudo docker compose up -d
sudo docker compose ps
```

Expected:

```text
NAME          STATUS
qbittorrent   Up ...
```

Now retrieve the temporary login password:

```powershell
sudo docker compose logs --tail 200 qbittorrent |
    Select-String -Pattern 'temporary password|WebUI'
```

The LinuxServer image creates a temporary password for user `admin` and prints it in the startup log. Its Web UI normally listens on port `8080`. ([LinuxServer][2])

Open:

```text
http://192.168.1.50:8080
```

Log in with:

```text
Username: admin
Password: the temporary password from the log
```

Immediately change it under:

```text
Tools → Options → Web UI → Authentication
```

Do not forward port `8080` through either router.

After login, set:

```text
Default save path:        /downloads/complete
Keep incomplete torrents: /downloads/incomplete
```

Use this downloader only for public-domain, freely licensed, or otherwise authorised material.

Checkpoint:

1. What does `-d` do?
2. Where is qBittorrent’s temporary password found?
3. Which directory should completed downloads use?

[1]: https://docs.docker.com/reference/cli/docker/compose/up/?utm_source=chatgpt.com "docker compose up | Docker Docs"
[2]: https://docs.linuxserver.io/images/docker-qbittorrent/?utm_source=chatgpt.com "qbittorrent - LinuxServer.io"

--------------

moving on, 

Tiny lesson: **Prowlarr is the catalogue desk.** It manages search sources for Radarr and Sonarr; it does not download files itself. The LinuxServer image uses `/config` for its database/settings and port `9696` for the web interface. ([LinuxServer][1])

## Install Prowlarr

Create its configuration folder:

```powershell
sudo /usr/bin/install -d -m 0755 /srv/docker/apps/prowlarr/config
sudo /usr/bin/chown -R you:you /srv/docker/apps/prowlarr
```

Create the Compose file:

```powershell
@'
services:
  prowlarr:
    image: lscr.io/linuxserver/prowlarr:latest
    container_name: prowlarr

    environment:
      PUID: "1000"
      PGID: "1000"
      TZ: Europe/London

    volumes:
      - ./config:/config

    ports:
      - "192.168.1.50:9696:9696/tcp"

    restart: unless-stopped
'@ | Set-Content /srv/docker/apps/prowlarr/compose.yaml
```

Validate and start it:

```powershell
Set-Location /srv/docker/apps/prowlarr
sudo docker compose config
sudo docker compose up -d
sudo docker compose ps
```

Expected result:

```text
NAME       STATUS
prowlarr   Up ...
```

Open:

```text
http://192.168.1.50:9696
```

Do not add router port forwarding for `9696`. Use only your LAN or WireGuard VPN.

Send the output of:

```powershell
sudo docker compose ps
```

Checkpoint:

1. Does Prowlarr download files?
2. Which applications will receive search-source information from Prowlarr?
3. Where is Prowlarr’s persistent configuration stored?

[1]: https://docs.linuxserver.io/images/docker-prowlarr/ "prowlarr - LinuxServer.io"


---------

proceeding

Worked for 24s

Tiny lesson: the paste became corrupted here:

mun[object Object],[object Object]

chown interpreted that as a username, rejected it, and stopped. No ownership change occurred, and Sonarr was not started.

Your current folder being docker/apps/radarr is harmless because we use absolute paths.

Run these cleanly, one line at a time:

sudo /usr/bin/install -d -m 0755 /srv/docker/apps/sonarr/config
sudo /usr/bin/chown -R 'you:you' /srv/docker/apps/sonarr

Now check whether the failed paste created a Compose file:

Test-Path /srv/docker/apps/sonarr/compose.yaml

Expected:

False

If it says True, inspect it without running it:

Get-Content /srv/docker/apps/sonarr/compose.yaml

Send the Test-Path result. We will create the Compose file next using a less fragile PowerShell method.

okay, it returned false, whats next

Tiny lesson: since the here-string paste was corrupted, we’ll create the file from an array of plain text lines. This is more reliable in PowerShell.

Run this block:

@(
'services:'
'  sonarr:'
'    image: lscr.io/linuxserver/sonarr:latest'
'    container_name: sonarr'
''
'    environment:'
'      PUID: "1000"'
'      PGID: "1000"'
'      TZ: Europe/London'
''
'    volumes:'
'      - ./config:/config'
'      - /srv/docker/media/tv:/tv'
'      - /srv/docker/downloads:/downloads'
''
'    ports:'
'      - "192.168.1.50:8989:8989/tcp"'
''
'    restart: unless-stopped'
) | Set-Content -Path /srv/docker/apps/sonarr/compose.yaml -Encoding utf8

Confirm the file exists:

Get-Content /srv/docker/apps/sonarr/compose.yaml

Then validate it without starting anything:

Set-Location /srv/docker/apps/sonarr
sudo docker compose config

The validation should show resolved paths such as:

/srv/docker/apps/sonarr/config → /config
/srv/docker/media/tv           → /tv
/srv/docker/downloads          → /downloads
192.168.1.50:8989             → container port 8989

Send the docker compose config result.

is as expected, whats next

Tiny lesson: the Sonarr prescription is valid. Now we start the container and check its vital signs.

From /srv/docker/apps/sonarr, run:

sudo docker compose up -d
sudo docker compose ps

up -d creates and starts Sonarr in the background; docker compose ps shows its status and published port.

Expected:

NAME     STATUS    PORTS
sonarr   Up ...    192.168.1.50:8989->8989/tcp

Check the startup log:

sudo docker compose logs --tail 30 sonarr

Then open:

http://192.168.1.50:8989

In Sonarr, add the library folder:

Settings → Media Management → Root Folders → Add Root Folder

Choose:

/tv

The LinuxServer Sonarr image uses /config for persistent settings, /tv for the final series library, /downloads for completed-download processing, and port 8989 for its web interface.

Do not add router port forwarding for 8989.

Checkpoint:

What does -d do?
Is /tv the organised library or the download waiting area?
Which port opens Sonarr?

Im thinking i need a one liner that does all the above with a fzf picker to pick which systems i would like installed. We could call this media-server set up or something more elegant, we would need to be in a container for it to qualify so that we dont just create it somewhere accidentaly and corrupt the server, so we need a enviroment one liner too, like before you set up that, run blah blah blah, which then does the docker and jellyfin set up, some of the settings required a human to configure in the app, if its possible to manipulate those said setting from the cli while setting up and would be a good streamlined version, if not, after the installation, the guide appears in the terminal for each app as directed by chatgpt to set up those settings ii.e. Add root folder etc. 

