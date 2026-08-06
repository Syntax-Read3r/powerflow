# team-room / future-features

Ideas we have decided are worth building, written down **before** we build them — and deliberately
not implemented yet. The folder name is the status.

Nothing in here is wired into the `team-room/` tooling. If you are debugging live behaviour, none
of these documents describe it.

| Feature | What it would do | Why it is parked |
|---|---|---|
| [api-error-watchdog.md](api-error-watchdog.md) | Detect when Claude has silently fallen out of the loop on a transient API error and nudge it to resume — while staying silent when it is working, holding for Codex, or waiting on the owner | Needs a reliable liveness signal first; a watchdog that cannot tell "stalled" from "holding" would do more harm than good |

When one of these is picked up: build it, move it into the tooling, and replace its row here with a
pointer to what shipped.
