# Log 2 — July 19, 2026 — srv: named SSH connections (joins 3.5.0)

**User request:** `ssh you@192.168.1.50` is hard to recall — wanted servers saved by
name, a ping test before saving, and an online/offline flag at pick time so an offline
server reads as "go turn it on", not a connection error.

## Naming

`srv`, shaped like `nav` (bare = picker, `srv <name>` = act, subcommands as first arg).
Rejected: `con`/`conn` (**CON is a reserved Windows device name**), `ssh-l` (reads as a
lister), `server` (confusable with the `service` brother). `ssh` itself is never wrapped
or shadowed — the coreutils principle extended to the network.

## The design upgrade over the request

The user asked for a ping test. **Ping answers the wrong question** — "is the machine
on?", when the question is "can I ssh in?". The probe is a TCP connect to the SSH port
with ICMP only as tiebreaker, which yields **three** states:

- `✅ online` — connect
- `🟡 host up, ssh not answering` — machine on, sshd down/blocked. **Ping alone cannot
  see this state**, and it changes the fix (restart sshd vs. press the power button)
- `⛔ offline · last seen Jul 17` — powered off or mistyped; lastSeen gives the clue

`srv add` runs the same probe: a dead address at entry is exactly the typo the test
exists to catch, but a powered-off server can be saved after confirming. Statuses for
the picker run in parallel (`ForEach-Object -Parallel`, throttle 8) so one dead server
does not serialize its timeout onto the rest — the probe is inlined there because
`-Parallel` scriptblocks cannot see local functions.

## Checklist discipline (it caught me last release; run it, say so)

- §1: architecture gate, parse, **drift gate 125/125** (the four `srv` entries were
  required by the gate before pwsh-h could ship them — the registry doing its job on its
  first new feature).
- §2: 24 mocked assertions run **with stdin genuinely piped** — every prompt (`add`
  offline-confirm, `rm` confirm, connect-anyway) refuses with an explanation instead of
  hanging; ssh args verified via a mock function (`-p 2222 other@127.0.0.1`);
  deterministic states via a local TcpListener + TEST-NET (192.0.2.1). Then the full
  Linux round trip against a **real sshd** in the container: install → survived → add
  detects online → uninstall keeps `~/.powerflow-servers.json` (bookmarks treatment;
  `-Purge` removes it, and uninstall's purge list now also covers `.nav_roots.json`).
- §3: CHANGELOG (folded into the still-uncut 3.5.0 alongside the pwsh-h registry),
  COMPONENTS.md, README feature block, this log.

§4/§5 remain the user's: 3.5.0 now ships two features — the help registry and `srv`.
