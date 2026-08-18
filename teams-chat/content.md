# Team-chat index

The watcher and the Codex wake connector follow the pointer under **Current log** — never a
system date — so this file is the one place that says which log is live.

## Current log

- [2026-08-18 — owner-chat archive](2026-08-18-owner-chat-archive.md)

## Logs

| Date | Log | What it is |
|---|---|---|
| 2026-08-18 | [owner-chat archive](2026-08-18-owner-chat-archive.md) | 372 blocks, 186 from the owner, spanning 04 Jul – 18 Aug. A reset-recovery snapshot of the Claude Code session that closed backlog round 1 and shipped five of round 2. Conversation only — no tool calls, no reasoning. |

## Conventions

Every block starts with a **single `#`** header naming sender and recipient:

```
# 2026-08-18 14:05 BST — Claude → the owner
```

The newest block's *recipient* is whose turn it is. The marker is derived from the file
itself, which is why it cannot desync the way a separate `.turn` file can. The em dash `—`
and right arrow `→` are required exactly; plain `-` or `->` is invalid (owner directive,
2026-07-30, so each conversation start is easy to trace).

See [`team-room/PROTOCOL.md`](../team-room/PROTOCOL.md) for the append lock and the watcher.

> This archive is a **snapshot, not a live conversation.** It was written in one pass from a
> session transcript, so it has not gone through the `mkdir`-lock append path. Treat it as
> history; start a new dated log before appending anything new.
