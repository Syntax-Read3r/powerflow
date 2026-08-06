# SRV Private Endpoint Display

**Status:** Implemented and locally verified.

## Goal

Make normal `srv` use alias-first and endpoint-private: lists, pickers, status and connection
messages show only the saved server name and reachability, while `srv <name> info` reveals the
stored SSH endpoint only after successful SSH authentication.

## Scope

This change covers the `srv` component, its help/registry entries, focused regressions, public
documentation, issue tracking and release notes. It does not encrypt the existing server JSON,
change SSH authentication, store passwords, redefine/shadow `ssh`, or intercept OpenSSH's native
credential prompt. OpenSSH may still render its own `user@host's password:` text; hiding that
would require a separate password-capture/askpass design and is intentionally excluded.

## Chunks

1. **Centralize private display and authenticated info**
   - Keep endpoint construction in a private helper used only for native SSH invocation and
     authenticated detail rendering.
   - Remove the endpoint from the connection banner; show alias and current status only.
   - Add `srv <name> info`: perform a non-mutating SSH authentication probe, reveal nothing if
     authentication fails/cancels, and render username, host/address, port and saved timestamps
     only after exit code zero.

2. **Make every normal management view alias-only**
   - Change `srv`, `srv list` and picker rows to server name + live state only.
   - Remove endpoint echoes from save success, duplicate name, rename collision, removal and
     picker-delete confirmations, reachability warnings, examples and runtime hints.
   - Preserve storage schema, parallel reachability checks, status sorting, last-seen history,
     delete/rename controls and the actual SSH token array.

3. **Regression and release closure**
   - Add componentized tests with mocked `ssh`, status probes, fzf and persistence.
   - Assert ordinary output never contains fixture usernames/addresses/ports; assert the native
     SSH call still receives the exact stored target; assert info reveals details only after a
     successful authentication probe and stays private on failure.
   - Register/document `srv <name> info`, update component/help/README/release docs, resolve the
     issue, write the solved-problem entry and run the full release gates.

## Rollback

Revert the `srv` component, tests, registry/docs and changelog changes. The persisted
`.powerflow-servers.json` schema is unchanged, so rollback requires no data migration.

## Testing

- Run the new `srv` privacy suite in clean PowerShell processes on Windows and Linux-compatible
  syntax paths without contacting a real server.
- Exercise bare list, picker, connect, add, remove, rename, duplicate and unknown-name paths
  with sentinel endpoint values and fail on any pre-auth disclosure.
- Mock successful, failed and cancelled SSH authentication for `srv <name> info`.
- Verify the actual connection call retains `-p <port> user@host` tokens without shell-string
  construction.
- Run all PowerShell parse, architecture, automatic-variable, help-registry, adapter-parity,
  privacy, whitespace, PMX, Linux dependency and Windows prerequisite gates.

## Result

Endpoint construction and native invocation now live in `server-privacy.ps1`; the existing
`servers.ps1` remains the command/status/persistence router. Ordinary paths render only aliases
and live state. The authenticated info path fails closed, reveals details only after SSH exits
successfully, and never handles a password. Focused regressions cover public output, exact native
argument tokens, successful authentication, and failed/cancelled authentication.
