# Log 2 — July 23, 2026 — pwsh-h becomes a manual; pwsh-config review fixes (staged for v3.9.0)

Two things, both folded into the held v3.9.0 so it stays one release.

## pwsh-h: a manual by default, the browser one flag away

**User:** "we need pwsh-h and pwsh-help -advanced || pwsh-h -a. The current pwsh-h moves
to pwsh-h -a and we bring back a look-alike of the previous version — users should scroll
through all functions like reading a paper manual, simple and less clutter. Group these and
redesign the page, don't just lift the old design."

The old (pre-registry) pwsh-h was a 350-line hand-drawn menu; when it became
registry-generated the default turned into an fzf browser. The user wanted the *readable*
experience back — but redesigned, not the box-art resurrected.

**What shipped:**

- Default `pwsh-h` → **`Show-PFManual`**: a quiet, printed reference. No fzf, no borders.
  It reads top to bottom and scrolls like a page.
- The 13 fine-grained sections are folded into **6 chapters** (`$PF_HelpChapters` in
  registry.ps1): Navigation · Files · Git & GitHub · Learn Linux · System & Disk ·
  Setup & Config. That's the "group these" — fewer, broader headings instead of thirteen
  small ones. Sections stay as-is for `pwsh-h <topic>` filtering and the fzf browser.
- The fzf finder moved to **`pwsh-h -a`**, with **`pwsh-help`** as a long alias and
  **`-advanced`** as the long flag (`pwsh-help -advanced` == `pwsh-h -a`).

**Design decisions worth remembering:**

- *Chapters are data, sections are identity.* A command still registers into a section;
  chapters are a presentation layer that folds sections together. Adding a section that no
  chapter claims doesn't make it vanish — Show-PFManual prints the leftovers under "MORE"
  (there's a test for exactly this).
- *Alignment is arithmetic, not emoji-safe surgery.* Chapter rules are a fixed-width line
  on their own row, so an emoji in the title can't push them off-grid (the exact bug that
  rotted the old menu). Command names print green, aliases dim — padding is computed from
  the full label length so the two colours don't skew the synopsis column.
- *The default no longer touches fzf*, so `pwsh-h` prints identically at a terminal, down a
  pipe, or in CI — and can't hang. `pwsh-h -a` falls back to the manual when output is
  redirected or fzf is missing, same guarantee.

The CI's pwsh-h assertion (release-validate-linux.yml) moved off the literal old section
string "SMART NAVIGATION" to the manual's own markers ("Command Manual", the "NAVIGATION"
chapter) plus registry command names — asserting the new render, not stale prose.

## pwsh-config: the adversarial review's four minor findings, fixed

The review of the pwsh-config code (9 agents) confirmed 4 findings, all minor, all real:

1. **Locale kept its `LANG=` prefix.** `localectl status` prints `System Locale:
   LANG=en_US.UTF-8`; the adapter surfaced the whole thing while every other row (and the
   picker's own list-locales) is bare. Fixed in the adapter: extract LANG's value, so
   Current is `en_US.UTF-8` like the rest. The component's one-off `--query -replace
   '^LANG='` paper-over is gone.
2. **The menu and its prompts disagreed on "interactive."** The setting-picker gated on
   `IsOutputRedirected`, the toggle/text prompts on `IsInputRedirected` — so a
   half-redirected session could fzf-pick a setting the prompt then refused to apply.
3. **The `pwsh-config kb` path had no input guard at all**, so fzf failing for lack of a
   tty was misreported as a user "Cancelled."
   → 2 and 3 fixed together: one `$canPrompt` (both streams must be a terminal) decided
   once, up front. Every path is now consistent — run the pickers AND prompts, or print the
   list / say "run it in an interactive shell." Never navigate to a dead end.
4. **Hostname was forwarded without a `--` terminator or a trim.** A hostname typed as
   `-foo` would be read as a flag; ` box ` kept its spaces. Fixed: `--` before the value in
   the adapter (argv, so never a shell issue) and `.Trim()` on the Read-Host result.

## Verified (all green)

- pwsh-h manual renders on both platforms; chapters fold sections; orphan section lands
  under MORE; platform filtering hides the other OS's commands; `pwsh-h -a` browser present.
- pwsh-config: LANG= strip (incl. multi-var and unset), hostname `--`, locale `LANG=` wrap,
  ntp; non-interactive consistency across list/text/toggle; unknown key rejected.
- CI gates: architecture (components/ platform-agnostic), help-registry drift (every
  command + the new `pwsh-help` alias registered), adapter parity (4 sysconfig functions
  both platforms).

Still holding for the green light — no version bump, tag, or push. v3.9.0 now carries
pwsh-config **and** the pwsh-h manual, which is exactly the batching the user asked for.
