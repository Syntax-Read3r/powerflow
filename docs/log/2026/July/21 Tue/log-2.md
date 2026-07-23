# Log 2 — July 21, 2026 — pwsh-exit (v3.8.0)

**User, on a server via SSH:** typing `exit` in PowerFlow closes the whole SSH connection.
They wanted `exit` to keep meaning "log out" (correct — pwsh is their login shell via the
`exec pwsh` auto-login hook), plus a separate command to reach bash without disconnecting.

## Why exit closes the connection

`--auto-login` writes `exec pwsh` into `~/.bashrc`. `exec` REPLACES bash with pwsh, so
pwsh IS the SSH session's shell — there is no bash underneath. Exiting pwsh ends the
session. Correct and intended; just surprising.

## pwsh-exit

`& bash` then `exit`: start bash (SSH stays open, you're at a bash prompt, PowerFlow
stepped aside), and when you leave that bash, pwsh exits too. pwsh has no native `exec`, so
bash runs as a child rather than replacing pwsh — practically invisible: you're in bash,
still connected. Linux only; on Windows PowerFlow isn't the login shell and the command
says so.

Immediate workaround that already worked: just type `bash` at the `❯` prompt (a subshell;
`exit` returns to PowerFlow). `pwsh-exit` is the discoverable, documented version.

## Verification

Control flow proven in Docker: pwsh-exit prints its message → runs `& bash` → runs `exit`
(never falls through — verified a post-bash marker is unreachable). pwsh→bash invocation
confirmed. The interactive prompt from `& bash` under a live tty is the exact standard
behavior of typing `bash` at a pwsh prompt, which the user already does — the pty-capture
harness in `docker exec` couldn't cleanly record the nested interactive session, but the
mechanic isn't in doubt. Windows branch prints the note without touching the shell. Drift
gate 128, pwsh-exit correctly Linux-only in help.
