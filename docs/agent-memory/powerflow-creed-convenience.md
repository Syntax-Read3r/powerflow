---
name: powerflow-creed-convenience
description: PowerFlow's purpose is convenience — a user must never have to remember many flags; native complexity stays hidden behind --show-native
metadata:
  type: feedback
---

The owner's words (2026-08-07): *"the purpose of powerflow is convenience, and to not make a
user have to remember 1000 flags unless they type `--show-native`."*

**Why:** PowerFlow exists so nobody has to recall `pvesh get /nodes/localhost/qemu/101/config`
or forty smartctl flags. A PowerFlow command that requires memorising *its own* flags has moved
the memorisation problem, not solved it — which is the failure to watch for, especially in code
written by another agent.

**How to apply — the house shape:**
- A **bare** command does the most useful thing (`pc-whoami`, `srv proxmox`, `nav <fuzzy>`).
- Refinement is one short **word**, not a flag string (`pc-whoami -ram huge` → `-ram java`).
- Ambiguity is resolved with an **fzf picker**, not a usage error. Refusing where a picker
  would do is the classic anti-pattern here.
- Native vocabulary appears only behind `--show-native` / `--explain` (both already exist and
  are honoured in the pmx layer).
- Errors teach: say what to type *instead*, name the candidates, give the exact retry line.

Measured 2026-08-07: `components/proxmox` alone carries **34 distinct long flags** across ~31
help topics — worth keeping an eye on as the surface grows.

Related: [[project-architecture]], [[adapters-make-code-runnable-off-target]]
