# Log 3 — July 19, 2026 — v3.5.0 rescued (third silent CI failure); srv picker becomes a manager

## v3.5.0: the checklist's §5 catches its third silent failure

The user asked a feature question; §5 discipline said check the release state first —
and **v3.5.0's CI had failed**. The Linux validate step asserted literal prose from the
old hand-drawn menu (`POWERSHELL COMMAND REFERENCE`, `GNU coreutils are NOT shadowed`) —
strings that lived in the 350-line wall the registry rewrite deleted. The product's
pwsh-h worked perfectly; the *test* had gone stale.

The irony is complete: the release that made help drift impossible was failed by help
drift **in the CI's own assertions**. And the meta-lesson: my local gates asserted my
new strings — I never ran the workflow's own step verbatim. Now the step asserts
**registry data** (section names from `PF_HelpSections`, registered command names, the
`del`/`mvf` Platform=Linux entries), verified verbatim in a container before pushing.
CI-only fix → tag moved (the 3.3.0 procedure) → **v3.5.0 published, 5 assets**.

Silent-failure count: 3.2.0, 3.3.2, 3.5.0. A notify-on-failure step is overdue.

## srv: delete / rename / Enter-to-connect (staged for 3.6.0)

The user asked: can I delete from the list, rename, or just press Enter to connect?
Enter-to-connect existed; delete only as a subcommand; rename not at all.

- **`srv rename <old> <new>`** — re-keys the record intact: host, port, addedAt,
  **lastSeen** all travel. That is the reason rename exists rather than `rm` + `add`:
  re-adding re-probes and loses the history that says when an offline box was last seen.
- **The picker is now a manager** via fzf `--expect`: Enter connects, `ctrl-d` deletes
  (confirm first), `ctrl-r` renames (prompt), and after either action the picker reopens
  with fresh statuses. Esc closes.

Tested: 15 new assertions (rename validation + record integrity, and the full picker
dispatch driven by a **stubbed fzf** — a queue of scripted `--expect` outputs — plus a
stubbed Read-Host), the original 24 still green, drift gate clean (`srv rename`
registered — the gate demanded it), parse + pwsh-h render checks green.
