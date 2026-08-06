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
