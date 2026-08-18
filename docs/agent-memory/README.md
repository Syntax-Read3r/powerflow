# Agent memory — archived

Claude Code keeps per-project memory outside the repository, under
`~/.claude/projects/<project-slug>/memory/`. That directory is machine-local and is **not**
covered by any backup this repo controls — a machine reset destroys it.

These are those notes, archived on **18 August 2026** ahead of a reset. They are the things
that were learned about this project and could not be re-derived from the code: the
architecture rule and why it exists, the flag ethos, the convenience creed, agreed build
order, and the decisions still waiting on the owner.

**Scrubbed before commit**, the same as everything else here — the username, home subnet,
machine names, email and session identifiers are placeholders, because this repository is
public.

---

## Restoring them

Claude Code derives the slug from the project's absolute path, so the destination depends on
where the repository is cloned. Find it and copy the notes back:

```powershell
# Windows
$slug = (Get-Location).Path -replace '[:\\/ ]', '-'
$dest = "$HOME\.claude\projects\$slug\memory"
New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item docs\agent-memory\*.md $dest -Exclude 'README.md'
```

```bash
# Linux / macOS
slug=$(pwd | sed 's|[:/ ]|-|g')
dest="$HOME/.claude/projects/$slug/memory"
mkdir -p "$dest"
find docs/agent-memory -name '*.md' ! -name 'README.md' -exec cp {} "$dest/" \;
```

If the slug guess is wrong, the reliable way is to let Claude Code create the directory once
(start a session in the repo and ask it to save any memory), then copy these files into
whichever `memory/` folder appeared.

`MEMORY.md` is the index loaded into context at the start of every session; the rest are one
fact per file. Restore all of them together — the index links to the others by name.

---

## A caveat worth reading before trusting any of them

A memory records what was true **when it was written**. Two of these have already been wrong:

- `ci-parity-regex-is-hardcoded` described a CI gate that was rewritten on 2026-08-18 to work
  the opposite way. It is kept, marked superseded, because the *reasoning* that forced the
  rewrite still applies — but a session that had trusted it would have made a false claim
  about the build.
- `privacy-history-scrub-pending` has been updated twice as new exposures were found.

So: if a note names a file, a function or a flag, **verify it still exists before acting on
it.** The repository is the source of truth; these are context, not authority.
