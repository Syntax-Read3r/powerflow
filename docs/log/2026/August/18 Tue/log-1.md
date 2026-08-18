# 18 Aug 2026 — closing round 1, opening round 2, and a leak the checklist caught one commit late

> **The full session is archived beside this file.** [`session-transcript.md`](session-transcript.md)
> is the readable conversation (185 turns); [`session-raw.jsonl`](session-raw.jsonl) holds the
> complete records. Both were scrubbed before they were committed — username, home paths, the
> real home subnet, machine names, email and every credential-shaped string are placeholders,
> because this repository is public. Archived ahead of a machine reset.

Four backlog items shipped and one privacy incident. The incident is the part worth reading:
the grep that found it works, it just ran a week after the commit that needed it.

---

## 1 · PF-FEAT-005 — `pc-name`: renaming a host without breaking `sudo`

The mutating sibling to the read-only `pc-whoami`. It replaces:

```bash
sudo hostnamectl set-hostname web-prod
sudo nano /etc/hosts
```

**The second line is the entire feature.** Setting the hostname alone leaves `/etc/hosts`
naming the old host, and the next `sudo` prints:

```text
sudo: unable to resolve host web-prod: Name or service not known
```

It still *works* — sudo falls back after a timeout — and that is precisely why it survives.
The cost shows up as every elevated command being a bit slower, not as an error anyone traces
back to a rename they did last week.

Because it mutates, it got the full shape: validate → preview **both** edits → confirm → back
up → apply → *verify the new name resolves*. Only the 127.x line that already names this host
is rewritten; an operator's own static entries for other machines are not a rename's business,
a commented-out line is not an entry, and a host with no such line is told there is nothing to
sync rather than having one invented for it.

### Three bugs the container found that reading could not

Every one of these came from running it, not from re-reading it:

1. **`2>/dev/null` does not silence a missing native command.** PowerShell throws
   `CommandNotFoundException` *before* the redirect is ever reached, so every `hostnamectl`
   call exploded on a distro without systemd. Alpine and Arch-without-systemd are both in
   PowerFlow's own Linux CI matrix, so this was not a hypothetical platform.
2. **`[Parameter(Mandatory)][string]` rejects `''` with a binder error** — which made the
   empty-name branch below it unreachable, and replaced a sentence the caller could print with
   an exception it would have to catch. `[AllowEmptyString()]`.
3. **The hosts edit used `sed -i` with `[regex]::Escape`.** That is .NET escaping fed into
   POSIX BRE, where `\+`, `\(` and `\{` mean the *opposite* of what .NET emitted them for. On
   busybox sed the mismatch is not theoretical. Rewritten in-process and copied into place with
   `cp` (not `mv`, so the original inode, owner and mode survive) — no escaping layer at all.

The test really renames a container, asserts the new name resolves, and **puts the machine
back**. A CI job left with a hostname its `/etc/hosts` does not know inherits the exact stall
this feature exists to prevent, and every later step pays for it.

That closes round 1: **20 of 20.**

---

## 2 · PF-UX-002 (b2) — Escape is a decision, not a failure

Escaping a PMX picker ended with a red `❌ cancelled`. The red marker is the one piece of
output that has to stay trustworthy; spending it on someone who simply changed their mind
teaches them to scan past it, and the next time it means something, they will.

Five outcomes reached the same renderer and **only one is neutral**:

| | |
|---|---|
| Esc pressed | neutral — nothing to fix |
| no VMs / no disks | a state worth reporting |
| fzf unavailable | an instruction — nobody was *asked*, so nobody declined |
| invalid selector | an error |
| ambiguous selector | an error |

Fixed at the shared boundary rather than per command: nine call sites rendered the failure by
hand, and a convention enforced in nine places is one that drifts in one of them. A test now
greps for a tenth.

Two things fell out of it. The **disk** picker had the same bug in different clothes — it
answered `$null` to both *cancelled* and *no picker available*, and the caller reacted by
re-printing the whole disk list, so escaping a picker of those same rows looked like the Escape
had not registered. And *"may we open a picker at all"* was inlined in two files with slightly
different spellings; it is one named predicate now (`Test-PmxCanPick`), which is also the only
reason the interactive paths became testable — a harness always runs with output redirected, so
the real check refused before `fzf` was ever reached.

---

## 3 · PF-UX-001 (b2) — `pmx list`, `pmx status`, and typos that suggest

`qm list` muscle memory reaches for `pmx list`. Both new spellings call the same function as
their canonical form, so they are another door into one view rather than a second view.

The suggestion engine is the part with a rule attached: **it never runs the suggestion.** No
*"did you mean … [Y/n]"*, which is exactly what makes a near-miss on a destructive word safe —
printing is all it can do. A test reads the source and fails if `Invoke-Expression`,
`Read-Host` or a `Confirm-` ever appears on that path, because a behavioural test written today
would still pass after someone added a prompt tomorrow.

Suggestions come from the help catalogue, not a second hand-kept list, because **a suggestion
is a promise that the thing suggested exists**. Sending someone to type a command that does not
run teaches them to distrust the tool rather than the typo. That immediately caught one:
`local` is a help *topic* covering `pmx`/`disks`/`pools`/`guests`, not a command — so `loca`
would have suggested a phantom. It is excluded, and a test cross-checks every suggestible route
against the router so the exclusion cannot go stale.

It is deliberately stingy. A flat edit distance of 2 makes `vm` and `ip` look like near-misses
for half the catalogue, so the budget scales with word length; one letter is not treated as a
prefix; at most three are offered; and `pmx zzzz` gets no guess at all. A guess offered with no
confidence is noise wearing the costume of help.

---

## 4 · PF-FEAT-008 (b2) — `pmx net status`

```text
  VMID   NAME                   VM        AGENT              ADDRESS              SSH
  100    debian13-base          stopped   stopped            —                    stopped
  101    debian13-lab           running   available          192.168.1.111        ready
  102    docker-host            running   available          192.168.1.112  +2    ready
  104    no-agent-vm            running   not-responding     —                    agent-unavailable
  105    silent-vm              running   available          —                    no-address
  900    debian13-base-v2       running   available          192.168.1.120        closed
```

Three things it deliberately does **not** do, each asserted rather than promised:

- **It never flattens a failure.** `stopped`, `agent-unavailable`, `no-address` and `closed`
  are four answers with four different fixes — start the VM, start the agent, look inside the
  guest, look at sshd. Collapsing them sends someone to debug the wrong layer.
- **It never scans.** No ARP, no DNS guessing, no DHCP leases, no ping sweep, no port scan
  across the subnet. The test stands in for the prober and asserts *what was probed*, which is
  the only way to prove this. It also reads the source with **comments blanked in place** —
  because the function's own comment says *"No ARP"*, and a naive substring scan fails on the
  promise instead of on a breach of it.
- **`ready` does not overclaim.** It means the TCP connection succeeded. Not that the host key
  was trusted, credentials were accepted, or a login would work. Stated under the table *and*
  carried as a field in `--json`, so a consumer cannot read `ssh: ready` as "authentication
  would succeed".

Reuse over reimplementation: guest-interface parsing and the primary-address choice come from
the existing PMX network layer, and the TCP probe is `srv`'s. That last one meant extracting
`Get-PFHostReachability` — `srv` had the parallel probe inlined, because a
`ForEach-Object -Parallel` runspace cannot see local functions, and a third copy of a socket
timeout is a third place for the timeout to be wrong.

The SSH port is 22 unless a saved `srv` target has the **same address** — never the same name.
A reused name would point the probe at the wrong port and report a healthy VM as closed.

---

## 5 · The leak — checklist item 4 worked, one commit late

Pre-flight for this release ran the private-data grep and found the round-2 backlog carrying
**27 instances of the owner's real subnet and 14 of their username**, across `ssh <user>@<host>`,
`/home/<user>` and `loginctl show-user` examples. It had been committed as pasted, and pushed.

The tree is scrubbed — placeholders that keep every "same host / different host" relationship
the examples depend on. None of it was load-bearing; a backlog example teaches exactly as well
on a documentation subnet, which is the whole reason the checklist item exists.

**What I actually got wrong is the timing.** The checklist puts that grep at the release, and
it duly caught this at the release. But the data enters the repo at the commit that pastes the
report in, and by release time that commit is already public — so the grep can only ever
discover the leak, never prevent it. The rule that would have worked: *scrub an owner-supplied
report in the same commit that adds it.*

The values remain in git history and in the GitHub blob for `a278bb8`. Removing them needs a
rewrite, which breaks every clone and rewrites published SHAs — the owner's call, not a release
side effect. This is the second such pending item; the first predates v3.9.0.

---

## What this release is

`pc-name`, `storage report`, `--educate` on every command, `pc-whoami --system`,
`ls --perms`, `rn --chmod`, `pmx net status`, `pmx list`/`pmx status`, neutral picker
cancellation, and the prune of unused `git-a` siblings.
