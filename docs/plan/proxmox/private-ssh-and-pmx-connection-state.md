# Private SSH Prompt and PMX Connection State

**Status:** Implemented and locally verified; awaiting confirmation on the real Windows server.

## Goal

Keep saved SSH usernames, addresses, and ports out of both `srv` authentication prompts and all
normal PMX output, while preserving password-based interactive SSH sessions and PMX's local and
key-authenticated remote management paths.

## Scope

This change covers two related disclosure paths:

- `srv <name>` and picker connections must identify the destination by saved alias only, including
  password, host-key, and authentication-failure prompts. The password remains transient between
  the prompt helper and OpenSSH; PowerFlow must never store, log, echo, place it in an environment
  variable, or put it on a process command line.
- Bare `pmx` and every remote PMX operation must convert native SSH failures into an alias-only
  connection state. Bare `pmx` will explain that the saved Proxmox server is not connected and
  direct the user to `srv <alias>`, then to run `pmx` inside that Proxmox session. Raw SSH output
  and endpoint-bearing native command previews must not reach the normal UI.

The change does not alter saved server data, SSH server configuration, PMX allow-listed native
operations, destructive-operation safeguards, or the authenticated `srv <name> info` exception.

## Chunks

1. **Platform-private SSH credential adapters**
   - Add `platform/windows/adapters/ssh-session.ps1` and a small Windows askpass helper source under
     `platform/windows/helpers/`. Compile/cache the helper locally and have it read the password
     directly from the console while writing only to OpenSSH's askpass pipe.
   - Add the matching Linux adapter/helper under `platform/linux/`. It will read from `/dev/tty`,
     suppress echo, and write only to the askpass pipe.
   - Both adapters will temporarily set and then restore OpenSSH askpass variables, use the saved
     alias for public prompts, keep successful interactive sessions attached to the terminal, and
     return only categorized, endpoint-free failures.

2. **SRV orchestration**
   - Refactor `components/network/server-privacy.ps1` to pass the alias and opaque server record to
     the platform adapter instead of invoking OpenSSH directly.
   - Keep `components/network/servers.ps1` responsible for alias/status UX and last-seen updates.
     Failed connections will mention only the alias. `srv <name> info` remains the sole endpoint
     reveal and still requires successful authentication.

3. **PMX connection-state boundary**
   - Add an alias-aware connection-failure formatter in a focused Proxmox component rather than
     scattering privacy strings through command handlers.
   - Update both `platform/*/adapters/proxmox-management.ps1` adapters to retain native diagnostics
     only for internal classification, return safe failure kinds/messages, and render remote native
     previews with the saved alias instead of `user@host`.
   - Update `components/proxmox/config.ps1` and the managed dashboard path in
     `components/proxmox/host.ps1` so bare `pmx` shows an elegant not-connected state and actionable
     `srv <alias>` guidance without a red raw SSH error.

4. **Regression coverage**
   - Extend `tests/network/` with fake askpass/SSH boundaries proving that prompt text, failures,
     ordinary connection output, and process arguments exposed to the public layer contain no
     fixture username, address, or port, while an interactive session remains usable.
   - Add a PMX connection-privacy regression under `tests/proxmox/` and wire it into the suite.
     Simulated authentication, DNS, timeout, and command failures must produce alias-only output;
     local adapter errors must remain useful.
   - Run both domain suites, all PowerShell parse/architecture checks, adapter parity, help registry,
     release-note extraction, workflow YAML, and whitespace gates.

5. **Documentation and patch release preparation**
   - Update `docs/instructions.md` to replace the obsolete allowance for OpenSSH's endpoint-bearing
     prompt with the new private-prompt rule.
   - Update `COMPONENTS.md`, relevant user/troubleshooting docs, the issue tracker, session log, and
     a solved-problem entry marked `Fix applied — awaiting confirmation`.
   - Prepare v4.0.1 release notes in `CHANGELOG.md` and bump the version only after all gates pass.
     The release will remain untagged until the user confirms both real terminal symptoms are gone.

## Rollback

Revert the new platform adapters/helpers, restore direct SSH invocation in the SRV privacy
component, restore the existing PMX error propagation, and remove the new tests/docs/version entry.
Saved server records and Proxmox configuration require no migration, so rollback is code-only.

## Testing

- `srv <alias>` asks for `Password for '<alias>':` without showing the saved username/address/port,
  then opens a directly attached interactive shell.
- A wrong password, unreachable host, host-key prompt, or cancellation reports only the alias.
- Bare `pmx` with password-only or unavailable SSH shows a calm not-connected message and
  `srv <alias>` guidance; it never prints `user@host`, the address, or raw OpenSSH diagnostics.
- Key-authenticated remote PMX and local Proxmox PMX continue to render dashboards and operations.
- `srv <alias> info` reveals the endpoint only after authentication, as designed.
- Automated fixtures use reserved example domains and never copy a real endpoint into the repo.

## Result

The implementation follows the approved component split. `srv` delegates invocation to matching
platform adapters and retrieves its categorized result separately, preserving a terminal-attached
shell. Windows builds a shipped console helper into the user's PowerFlow data directory; Linux
caches its shipped `/dev/tty` helper with forced owner-only mode `0700`. Both show the saved alias
only and pass hidden input straight to OpenSSH's askpass pipe.

PMX now has a focused `connection-state.ps1` component. Remote adapters classify native failures,
withhold endpoint-bearing diagnostics, and render native previews through the alias. The managed
dashboard turns those results into the intended not-connected state and directs password-only
users into `srv <alias>` before running local PMX.

No release tag or manual settings-file bump was made. Repository policy leaves the version change
to `git-rl`; v4.0.1 notes are prepared, and the real Windows prompt/session must be confirmed before
the release is cut.
