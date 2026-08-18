# FUTURE FEATURE — API-error watchdog (nudge only when genuinely stalled)

> **Status: NOT IMPLEMENTED.** This folder holds features we have decided are worth building but
> are deliberately not building yet. Nothing here is wired into `team-room/` tooling. Do not treat
> this document as describing existing behaviour.

## The problem

Claude occasionally hits a transient **API error** mid-turn (observed: `API Error 529`, and a
separate error that coincided with a PC restart). When that happens the agent simply stops. It is
not blocked on a decision, it is not waiting for Codex, and it holds no lock — it has silently
fallen out of the loop, and the checkpoint sits idle until the owner happens to notice and says
"resume".

This has only ever been observed with Claude, never with Codex, so the watchdog is scoped to the
Claude side of the room.

## Why a naive "nudge if quiet" would be wrong

Silence is not the signal. The agent is legitimately quiet in several states, and nudging in the
wrong one is actively harmful — it interrupts work, or worse, prompts a second agent to act while
the first still believes it owns the task.

| State | Looks like | Correct action |
|---|---|---|
| **Working** | No chat post, but tool calls, CI polling, a build or a device run in flight | **Do nothing.** A nudge here can duplicate work or corrupt a run. |
| **Holding for Codex** | Last chat block is `Claude → Codex`; the protocol requires waiting | **Do nothing.** This is obedience, not a stall. Nudging invites a self-approval breach. |
| **Blocked on the owner** | Reported a blocker only the owner can clear (billing, hardware) | **Do nothing** — the owner already has it. |
| **API-error stall** | No chat post, **and** no tool activity, **and** not holding for Codex | **Nudge** — this is the only case the feature exists for. |

The whole value of the feature is in telling the fourth row apart from the first three. A watchdog
that cannot do that should not ship.

## Detection sketch (to be designed properly when we build it)

Three independent signals, all of which must agree before nudging:

1. **Is it holding?** Read the tail of the current day log. If the newest block is `Claude → Codex`,
   the agent is holding by protocol → never nudge. If the newest block is `Codex → Claude` and is
   older than the threshold with no reply, that is a candidate stall.
2. **Is it working?** Liveness must come from something the agent touches *while working*, not from
   chat. Candidates: a heartbeat file the agent writes each turn, mtime on the session's scratchpad
   or task-output directory, or an active harness-tracked background task. Without a liveness
   signal the watchdog cannot distinguish "thinking for ten minutes" from "dead".
3. **Is something external still pending?** A running CI workflow, an EAS build or a device proof
   means the agent may correctly be idle for an hour or more. Check before nudging.

Nudge only when: newest block is addressed to Claude **and** no liveness for N minutes **and** no
external work pending.

## Design constraints

- **Err toward silence.** A missed nudge costs minutes of idle time; a wrong nudge can corrupt a
  checkpoint or push the agent into acting while it should hold.
- **Never auto-approve, never post as Claude.** The watchdog's only output is a nudge to resume; it
  must never write a `Claude → Codex` block or answer Codex on Claude's behalf.
- **Idempotent.** Repeated firings on the same stall must not stack up nudges — consume the
  signature once, exactly as the Codex wake connector was fixed to do on 2026-07-27.
- **Cheap.** It should be a file/clock check, not a poll of any paid API.
- **Observable.** Log why it did or did not nudge, so a wrong decision can be diagnosed after.

## Open questions for when we build it

- What is the liveness signal, concretely? A per-turn heartbeat file is the simplest, but it
  requires the agent to write it reliably — including on the turn where it is about to die.
- What threshold? It must exceed the longest legitimate quiet period during active work (a native
  CI leg is ~1h45; a device proof cycle is several minutes).
- How does the nudge reach the agent — the same scheduled-task mechanism as the Codex wake
  connector, or something else?
- Should it distinguish a *recoverable* API error from a crashed session that needs the
  `reinitiate` path in `team-room/reinitate protocol one.md` instead?

## Related

- `team-room/initiate.md` — the startup ritual after a shutdown.
- `team-room/reinitate protocol one.md` — recovery when a crash lands mid-checkpoint; overlaps this
  feature's territory, and the two should share the "is it actually stalled?" logic if possible.
