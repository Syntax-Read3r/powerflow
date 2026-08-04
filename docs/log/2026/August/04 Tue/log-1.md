# Log 1 — August 4, 2026 — `team-room`: you could start a watcher but never stop one (v3.16.0)

**User:** "inspect team-room, build code that can see active watchers, it should show if they
are live, and have the ablity to shut them down. also, we need the ability to activate any
previously activated and note deleted team-room. **the reason is, currently, unless i tell ai
to shut the team-room down, i have no ability to.**"

That last sentence is the whole feature. The only shutdown path was *asking the agent to shut
itself down* — which fails in exactly the cases you need it: the agent isn't listening, isn't
running, or is itself the thing you want stopped.

## The first thing I got wrong was thinking a room had a state

It doesn't. It has **three**, and they are independent:

| State | What it is | Where it lives |
|---|---|---|
| Wake connector | a Scheduled Task `TeamChat-<agent>-<repo>` | the Windows task registry |
| Arm stamp | `team-room/state/armed.json`, scoped to **this boot** | the repo |
| Watcher | a live `node teamchat-wait.js` process | the process table |

My first list rendered a single ●/○ per room. It was wrong on this very machine within a
minute: `belief-index` showed as off while its connector sat at `Ready`, and `powerflow`
showed as on while nothing but an arm stamp existed. Both readings were defensible and both
were useless — the question the owner is actually asking is *"will an agent wake up?"*, and
that is a **derived** value, not a stored one.

So the list shows all three per room and derives `Live` from them. The detail view prints each
with its reason. Merging them is what made a room impossible to reason about in the first
place; a command built to end that confusion cannot reintroduce it.

## Arming is boot-scoped, and that has to fail closed

The stamp records the **boot instant** — now minus uptime — rather than a wall-clock time, so
a clock change moves both terms together and the value keeps naming the same boot session.
Anything outside a 3-minute tolerance reads as *disarmed*.

Three ways to be non-armed, three distinct reasons, all closed:

```
never-armed-this-boot     no stamp
unreadable-arm-stamp      corrupt JSON — does not throw, does not assume armed
malformed-arm-stamp       stamp with no bootInstantMs
armed-in-previous-boot    stamp survived a reboot
```

A stamp that fails to parse must not read as armed. The whole point of the command is that
you can trust what it says about whether something will happen.

## Orphans are shown, not hidden

`TeamChat-Fable-Hutano` is a scheduled task on this machine whose repo config no longer
exists. The tidy behaviour is to skip it. The correct behaviour is to show it with a warning
that PowerFlow **cannot status or uninstall it**, because an invisible thing that can still
wake an agent is precisely the problem being solved. Discovery therefore unions four sources:
config directories, orphan tasks, absolute-path watcher command lines, and the repo you are
standing in — plus an `unattached` pseudo-room for watchers claimed by nothing.

## Two bugs worth recording

**`$Pid` is a read-only automatic variable.** I named a parameter `$Pid` — the same class of
mistake I had just written up in someone else's Proxmox code two hours earlier. It's
`$ProcessId` now, in both adapters and the call site.

**The live watcher was invisible.** My test for "is this a rooted path" checked the first
token of the command line, which is `node.exe` — always absolute. The watcher's *script*
argument is relative. Fixed by extracting the script token and testing that, which is what
`ScriptIsRooted` exists to answer.

## Stopping re-verifies identity

`Stop-TeamRoomWatcher` re-reads the process's command line and confirms it is still a
`teamchat-wait` **immediately before signalling**. PIDs are reused, and this code runs after a
confirmation prompt a human may have taken a minute over. The test spawns a non-watcher
`pwsh`, asks the adapter to stop it, and asserts both the refusal and that the process is
still alive.

## The Linux half does not pretend

CI parity requires `Set-TeamRoomTask` on both platforms. The wake connector registers a
*Windows Scheduled Task*; the toolkit ships no Linux equivalent — not a cron job, not a
systemd timer. The Linux implementation says so and returns `$false`. Returning `$true` would
have made `team-room start` report success for something that never happened, which is the
exact silent lie this command exists to remove.

## Verified

45 assertions against the live machine, all green: discovery matches the real scheduled tasks,
the orphan surfaces with its warning, all four arm-state paths fail closed, the identity guard
refuses a non-watcher, and the live `powerflow` arm stamp is left untouched by every test
(round-trips run against a scratch repo).
