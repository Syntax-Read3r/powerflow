# Log 7 — August 6, 2026 — private SSH prompt and PMX connection state

**Work performed:**
- Traced bare `pmx` disclosure to raw OpenSSH diagnostics crossing the PMX adapter/session boundary.
- Traced `srv` disclosure to OpenSSH's hard-coded `user@host` password prompt, which writes directly
  to the controlling terminal and cannot be corrected with ordinary PowerShell output filtering.
- Added matching Windows/Linux private SSH session adapters and shipped askpass helpers. The prompt
  is alias-only; the password travels only from terminal input to OpenSSH's askpass pipe.
- Separated SSH invocation from result retrieval to preserve a directly attached remote shell.
- Added a focused PMX connection-state component, failure categorization, endpoint-free previews,
  and a calm disconnected dashboard with `srv <alias>` guidance.
- Added SRV/PMX privacy regressions and updated the CI adapter-contract allow-list.
- Prepared v4.0.1 release notes and corrected the shipped v4.0.0 changelog date.

**Files modified:**
- `platform/{windows,linux}/adapters/ssh-session.ps1` and platform askpass helpers (created)
- `components/network/server-privacy.ps1`, `components/network/servers.ps1` (adapter orchestration)
- `components/proxmox/connection-state.ps1` (created), `config.ps1`, `host.ps1`
- `platform/{windows,linux}/adapters/proxmox-management.ps1` (safe failure/preview boundary)
- Network and PMX regression suites, profile loader, validation workflow, public/architecture docs
- Plan, Issue 16, solved-problem note, changelog and this session log

**Security decisions:**
- No password enters PowerShell output, environment state, process arguments, logs, or persistent
  storage. The platform helper holds it only transiently while writing to OpenSSH's private pipe.
- The Linux cached helper is forced to owner-only mode `0700`, independent of archive/mount modes.
- Failure to prepare the helper fails closed; PowerFlow does not fall back to OpenSSH's revealing
  native password prompt.
- Actual SSH target tokens stay in the platform adapter and authenticated `srv <name> info` view.

**Bug status:** Fix applied — awaiting user confirmation on the real Windows server.

**Verification:** Focused SRV, PMX, and Windows prerequisite suites pass. The Windows helper builds
from shipped source; the Linux SRV/PMX suites run in a PowerShell container and its cached helper is
verified at mode `0700`. Every PowerShell file parses; component architecture, automatic-variable,
help registry (134 commands), adapter parity/CI allow-list, profile-load, changelog extraction,
workflow YAML, private-data, and whitespace gates pass.

**Suggested commit message:** `fix(privacy): hide SSH endpoints in srv and pmx`
