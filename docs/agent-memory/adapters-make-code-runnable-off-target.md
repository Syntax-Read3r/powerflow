---
name: adapters-make-code-runnable-off-target
description: "PowerFlow's ports-and-adapters layout means Linux-only features are testable on Windows — fake the adapter contract for components, shim `& tool` as a function for adapters"
metadata: 
  node_type: memory
  type: project
  originSessionId: <archived>
  modified: 2026-08-04T11:03:30.107Z
---

"This only runs on a Proxmox node / on Linux" is almost never a reason to skip executing
PowerFlow code. Two properties make nearly all of it runnable on Windows:

1. **`components/` never call an OS API** — that is the architecture rule. So a component is
   executable anywhere by defining its adapter contract as stubs returning fixture data. The
   whole 626-line `pmx` component ran on Windows this way.
2. **Adapters reach the OS through `& toolname`**, and PowerShell resolves a bare command name
   to a **function** before a native binary. Defining `function smartctl { $global:FIXTURE }`
   makes the adapter's real parsing body execute against recorded tool output.

**Why it matters:** v3.16.0 (2026-08-04) shipped two total-failure bugs past a 45-assertion
suite that only did static checks plus the layer Claude had written — `$matches` used as a
local, and infinite recursion on `@($null)` (a ONE-element array, not empty). Both aborted
every `pmx` disk command on any real host. Executing the code found them in minutes; the
suite grew to 383 assertions.

**How to apply:** before claiming a platform-specific feature is verified, ask which half is
actually unreachable. Usually it is only the handful of lines that exec the tool — not the
parsing, not the rendering, not the dispatch. Guard fixtures so nothing destructive is ever
defined (never define `f3probe`).

Related: [[project-architecture]], [[ci-parity-regex-is-hardcoded]]
