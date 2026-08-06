# Proxmox VM networking — configured adapters and runtime addresses are confused

## Problem

A VM-network convenience command can expose native Proxmox terminology, imply that a configured
slot such as `net0` is the same object as an operating-system interface such as `ens18`, or present
an address as an SSH endpoint even though no connectivity test occurred.

**Status:** Fix applied — awaiting confirmation on a real Proxmox VM.

## Root cause

Proxmox VM configuration and the VM agent report different layers. Configuration owns adapter
model, bridge, MAC address, firewall and VLAN state. The running operating system owns interface
names, assigned addresses and traffic counters. Array position and similar-looking names are not
an identity contract between those sources.

## Solution

Keep the two sources in separate pure models and match them only when each side has one valid,
normalized, equal MAC address. Expose user-goal commands for adapters, addresses and stats; keep
the fixed native VM-agent command inside an allow-listed platform adapter and reveal it only for an
explicit `--show-native` request.

Rank a primary address candidate from valid address family, scope and a unique adapter match. Label
that result inferred and leave it null when top-ranked candidates tie. Never call it an SSH endpoint
or claim reachability without a separate probe.

## Notes

- Stopped VMs and templates can still expose configured adapters but cannot report runtime facts.
- An unavailable VM agent is a categorized source state, not permission to fall back to ARP, DNS,
  DHCP leases, bridge tables or scans.
- JSON should retain explicit source availability, null native commands by default, exact integer
  counters and stable field ordering.
