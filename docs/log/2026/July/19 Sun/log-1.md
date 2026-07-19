# Log 1 — July 19, 2026 — pwsh-h modernised: the registry (staged for v3.5.0)

**The user's complaint: "a lot of functions are not in pwsh-h, and it is poorly designed."
The audit said the second half was the real story.**

## The audit (data before vibes)

Extracted every user-facing command from `components/` + `windows-only/` and diffed
against the menu: **117 defined, 110 mentioned — only 4 real gaps** (`clr`, `git-aa`,
`removefile`, `unalias`; three others were Verb-Noun internals, correctly excluded).
So coverage was 94%… buried in ~350 lines of hand-drawn box art, 11 rows off the 80-char
grid, one row actively false. Coverage was not the problem. **Discoverability and
maintainability were.**

## The rebuild

- **`components/help/registry.ps1`** — `Register-PFCommand` / `Get-PFCommandRegistry` /
  `Get-PFHelpSections`. Loads FIRST among components. Canonical section list lives here.
- **29 files gained registration blocks** beside their definitions — 133 entries covering
  124 kebab-named commands and aliases. Help metadata now lives WITH the code, the same
  cure `lessons.ps1` applied to the teaching layer.
- **`menu.ps1` rewritten** (~200 lines replacing ~350 of box art): generated print with
  computed alignment; **fzf browser on bare `pwsh-h`** (preview-file based, `cat` on
  Linux / `type` on Windows, since fzf runs previews under sh/cmd respectively); topic
  routing preserved (`pwsh-h chmod` → lesson) and extended (substring search over names
  and synopses as the fallthrough).
- **Platform filtering is data**: `-Platform 'Linux'` on `del`/`mvf` (registered from
  `bindings.ps1`), `'Windows'` on terminal tabs and WSL; sections with no entries for the
  current OS vanish rather than rendering empty.
- **CI drift gate** in `release-validate.yml`: every kebab-named function/`Set-Alias` in
  `components/` + `windows-only/` must appear as a `-Name` or in an `-Aliases` list.
  124/124 at ship time.

## Two of my own bugs, caught in the run

- **The gate's regex was case-insensitive** — PowerShell's default — so `[a-z]` matched
  every Verb-Noun helper and reported 76 phantom violations. `-CaseSensitive` is
  load-bearing and commented as such in the workflow.
- The first migration attempt via stacked bash heredocs died on quoting; redone as a
  single PowerShell script with here-strings (quoting-proof, idempotent via a marker
  check, skip-if-present).

## Doc changes

CLAUDE.md's **Help Menu Rule replaced by the Help Registration Rule** — the old
folder→section table described hand-editing a file that no longer exists. COMPONENTS.md,
CHANGELOG 3.5.0, and this log. The release checklist's pwsh-h item now points at the
registration rule (the gate does the checking).

Verified: Windows (parse, registry live with 110 entries, all six render paths) and Linux
container (103 entries after platform filtering, del/mvf present, Windows-only absent,
empty sections skipped, coreutils untouched, no fzf hang when piped).
