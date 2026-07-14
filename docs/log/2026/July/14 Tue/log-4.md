# Log 4 — July 14, 2026 — v3.3.0 released; v3.3.1 prepped (`mv`)

**v3.3.0 shipped, but only on the third attempt.** Two CI failures, and neither error message
said what was actually wrong.

**Failure 1 — the lockout test was broken, not the product.**
`release-validate-linux.yml` ran `sudo mv "$(command -v pwsh)" /tmp/pwsh.bak`, which moves only
the **first** pwsh on PATH. The GitHub runner has pwsh preinstalled at `/usr/bin/pwsh` *and* the
workflow installs a second via snap at `/snap/bin/pwsh`. So one survived, `~/.bashrc`'s
`command -v pwsh` guard passed, `exec pwsh` replaced bash, and `echo SURVIVED` never ran. The
captured "output" was literally a starship prompt. The step reported a lockout that did not
exist — and its restore line would have dropped the snap symlink on top of the preinstalled
binary. That assertion had never once executed: every earlier attempt died before reaching it.

Fixed by building a sandbox `PATH` containing no pwsh instead of moving anything — immune to
however many installs exist, and nothing needs restoring. Also added `|| true` on the capture,
because under `set -e -o pipefail` a genuine lockout kills the step at the assignment (exit 127)
*before* the `::error::` can print — a bare red X with no explanation, which is exactly the
diagnostic hole that cost two release cycles. Verified in both directions: passes with 3 pwsh on
PATH, still fails on a deliberately unguarded hook.

**Failure 2 — re-running the installer disabled its own uninstall.**
The manifest recorded `installedByPowerFlow = (-not $preExisting)`. On a *second* install every
tool is present **precisely because the first install put it there**, so each re-install quietly
flipped `starship`/`fzf`/`zoxide`/`lsd` to "the user already had this". Uninstall then correctly
honoured a manifest that had become a lie and left them behind forever. Ownership is now carried
forward from the previous manifest.

**The tag contained the file-destroying `touch`.** `git-rl minor` ran before the second half of
the work landed, so `v3.3.0` pointed at a commit with `New-Item -ItemType File -Path $f -Force`
(truncates existing files), the `rm -rf` hang, and none of the nine new lessons. **Had CI passed,
that is what would have shipped.** The tag was moved to `693d315`. The failing CI is the only
reason a data-loss release did not go out.

Published, then verified from the real `curl | bash` path on a clean Debian 13: reports v3.3.0,
GNU `grep` intact, `touch` preserves files, `l grep`, 24 lessons, `mkdir -p`, `nav`, `ls -ld`.

---

## v3.3.1 (prepped, unreleased) — `mv`

The last member of the family that produced 3.3.0's `touch` / `rm -rf` / `mkdir` bugs.

**`mv a.txt b.txt` silently did nothing on Windows** — the most basic operation in any shell.
PowerFlow's `mv` is a cut/paste workflow, so with two arguments it joined them into the single
filename `"a.txt b.txt"`, found no such file, and gave up without a word.

**One argument still cuts. Two or more is now a real move.** `Invoke-GnuMove` handles
`mv src dst`, `mv f dir/`, `mv a b c dir/`, `-f`, `-n`, `-v`.

**Decisions:**

- **Overwriting prompts unless `-f`.** GNU clobbers silently; PowerFlow's `rm` prompts. Internal
  consistency beats strict parity, and safety is the right direction in which to differ.
- **`mv my report.txt` still cuts.** An unquoted filename with a space is genuinely ambiguous.
  The cut reading is chosen only when it is the *unambiguous* one — the joined name exists **and**
  the first word does not. `mv a.txt b.txt` is unaffected because `a.txt` exists.
- **`-detailed` is stripped before flag parsing.** `Split-GnuArgs` would otherwise read it as the
  bundled short flags `-d -e -t -a -i -l -e -d`. (`--detailed` is the correct spelling under
  PowerFlow's own single-dash-is-Linux's rule; the old form is still accepted.)
- Guarded: `mv same.txt same.txt` refuses rather than deleting the file; `mv f.txt notadir/`
  refuses rather than creating a stray *file* named `notadir`.

**The through-line, again.** Every Windows file-op bug this week — `ls -ld`, `rm -rf`, `mkdir -p`,
`touch`, and now `mv` — came from the same two mistakes: **a `param()` block makes PowerShell bind
`-r`/`-p`/`-l`/`-f` as parameter names**, and **joining `$args` with spaces turns several arguments
into one filename**. Both are now documented in `COMPONENTS.md` (footnotes 5 and 6) rather than
left to be rediscovered a sixth time.
