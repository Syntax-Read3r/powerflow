# OpenSSH and PMX — saved endpoint appears before a connection succeeds

## Problem

A named SSH launcher hides its saved target in lists but the native password prompt still shows
`user@host`. A management command that uses the same saved connection also prints native SSH
authentication failures containing that target.

**Status:** Fix applied — awaiting confirmation.

## Root cause

OpenSSH constructs password and final authentication messages from the effective username and
host. Those messages are written directly to the terminal, outside a PowerShell output filter.
Separately, the management adapter captured native diagnostics but returned them unchanged to the
component layer. Hiding endpoints only in list formatting therefore protected neither boundary.

## Solution

Put interactive authentication behind platform adapters. Use `SSH_ASKPASS_REQUIRE=force` with a
small helper that ignores OpenSSH's endpoint-bearing prompt, reads hidden input directly from the
controlling terminal, and writes the secret only to OpenSSH's askpass pipe. Keep invocation and
result retrieval as separate adapter calls so the interactive process is never captured by a
PowerShell assignment. Suppress native connection diagnostics and return a categorized result.

At the management boundary, retain native diagnostics only long enough to classify failures such
as authentication, host-key, or reachability errors. Return fixed safe messages and build preview
commands with the saved alias rather than the actual target. The component layer can then render
a useful disconnected state without possessing endpoint-bearing error text.

## Notes

- Never pass a password through an environment variable, command argument, log, return object, or
  persistent file.
- Cache an askpass helper with owner-only permissions (`0700` on Linux); a writable helper could
  be replaced by another local user before authentication.
- `StrictHostKeyChecking=accept-new` avoids a first-use prompt containing the target while still
  refusing a changed known host key.
- Do not return an object from the function that directly hosts an interactive native session;
  an outer assignment redirects its streams. Store the categorized result in adapter state and
  retrieve it with a second call.
- A non-interactive management probe should not open a password prompt. Direct password-only users
  into the named interactive session and let them run local management commands there.
