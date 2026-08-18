---
name: dont-block-poll-background-tasks
description: Don't sit on blocking TaskOutput polls waiting for background workflows — keep working and report when the notification arrives
metadata:
  type: feedback
---

The user has twice interrupted a blocking `TaskOutput` call that was waiting on a running
workflow, once saying *"you seem stuck in thought, hence the interruption."*

**Why:** a blocking poll looks like a stall. The harness already re-invokes on completion, so
waiting adds nothing and costs the user their sense that work is progressing.

**How to apply:**
- Launch background work, then **keep doing something useful** — an independent checklist item,
  a cheap verification, logging requirements.
- Check status with a **non-blocking** file-size probe on the task output path if needed.
- Report findings when the completion notification actually arrives.
- Never call `TaskOutput` with `block: true` purely to wait.

Related: [[powerflow-creed-convenience]]
