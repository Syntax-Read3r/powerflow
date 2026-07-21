# Log 1 — July 21, 2026 — Nerd Font install, --auto-login, pwsh-autologin (v3.7.0)

Two Fedora friction points the user hit in daily use, fixed at the root.

## The font was never installed — the README lied for years

The user's Fedora prompt showed Chinese characters and `ls` icons overlapping filenames.
Diagnosis: no Nerd Font. Starship and lsd draw with Private-Use-Area glyphs; with no Nerd
Font, Linux fallback picks Noto CJK (which has glyphs at those codepoints), and CJK is
double-width → overlap. The tell was unmistakable.

Grepping the installer proved the deeper problem: **PowerFlow never installed a Nerd Font
on any platform.** The only FiraCode reference anywhere was in `create-next.ps1` (a project
template). The README's "FiraCode Nerd Font auto-installed" was aspirational fiction.

Fixed properly, as a real dependency:

- **`platform/{windows,linux}/adapters/fonts.ps1`** — a font is not a CLI tool, so it
  can't use `Test-Dependency`'s `Get-Command` model. Windows: Scoop nerd-fonts bucket
  (`FiraCode-NF-Mono`, per-user, no admin), detect via the font registry. Linux: download
  the release zip → extract Mono TTFs to `~/.local/share/fonts/PowerFlow-NerdFont` →
  `fc-cache`, detect via `fc-list`. Expand-Archive (not `unzip`) and Invoke-WebRequest
  (not curl) — no extra dependencies on a slim box.
- **The Mono variant, deliberately** — single-cell glyphs are what stop the `ls` overlap.
- **Manifest-tracked** (`kind: font`): uninstall removes it via `Uninstall-NerdFont`, and
  only PowerFlow's own copy (its dedicated dir), never a font the user installed. The
  ownership + `-NoDeps` logic from the July 17 fixes carried over unchanged.
- **`pwsh-font`** component — install + print the one step no tool can automate: setting
  the terminal emulator's font. That half is genuinely un-automatable (a dozen terminals,
  no common API), so the honest move is to do the font and instruct the rest.
- The architecture gate caught my first draft: the component hard-coded `scoop`/`fc-cache`
  in help strings, which the gate forbids in `components/`. Correct fix — a
  `Get-NerdFontInstallHint` adapter function owns the platform specifics. The gate did its
  job.

## Auto-login: shorter flag + a runtime toggle

User: "I shouldn't have to re-run the installer with `--login-shell auto`; a simple
`--auto-login` is enough." Correct.

- **`install.sh --auto-login`** — a plain alias for `--login-shell auto`.
- **`pwsh-autologin`** — the runtime twin, so you never touch the installer to change your
  mind. `platform/{windows,linux}/adapters/login.ps1`: Linux toggles the guarded `~/.bashrc`
  hook; Windows reports `'always'` (pwsh always sources `$PROFILE` — nothing to toggle).
  The Linux adapter writes a **byte-identical** block to the installer's — same marker,
  same guards — verified in Docker, including that it stays **LF-only** (the .ps1 source is
  CRLF on a Windows checkout, so the block is built with explicit `` `n `` and stripped of
  `` `r ``; a stray CR would turn `fi` into `fi\r` and break bash login).

## Verification

Full Linux round trip (Ubuntu + fontconfig): shellcheck · install `--auto-login` writes
exactly one hook · font installs and `fc-list` sees it · `pwsh-autologin off→on` round trips
with no duplication and no CR · **lockout safety** (interactive loads pwsh, non-interactive
stays bash, pwsh-unreachable still gives bash) · uninstall removes the font and keeps
pre-existing git. Fedora container: real download → 6 Mono TTFs → fontconfig indexes them →
uninstall removes only PowerFlow's dir. Windows: static gates + `pwsh-autologin` correctly
reports the no-hook-to-toggle state.

Release: three new adapter functions per platform added to the CI parity list; `pwsh-font`
and `pwsh-autologin` registered (drift gate 127/127).

## Adversarial review before release — 8 confirmed, all fixed

Ran a 4-dimension review workflow (ownership, login-hook, architecture/CI, cross-platform)
with per-finding adversarial verification. 9 raw findings, 8 confirmed, 1 refuted (a
parity-list nitpick with no real breakage). **Two were major and I'd have shipped both:**

1. **Login lockout on a *broken* pwsh.** The guard checked only `command -v pwsh`, never
   runnability — so a present-but-crashing pwsh (missing ICU, the exact case
   `install.sh`'s own `pwsh_works()` guards) would `exec pwsh`, crash, and re-crash every
   login: a real lockout on a headless server. Especially damning because I was *adding*
   `pwsh-autologin`, which writes that same hook. Fixed by adding `pwsh --version` to the
   guard, in both the installer and the adapter (kept byte-identical). Verified in Docker
   with a pwsh stub that exits 1: bash now survives.

2. **Failed install recorded as owned.** `(-not $preExisting) -or $weOwnIt` marked a
   dependency owned whenever it was merely *absent* at start, even if the install failed —
   so on Windows, uninstall could delete a font the user installed themselves. My font
   code inherited the bug from the pre-existing tools line; fixed both to `$weOwnIt` /
   `$fontOwned` alone. Verified: a font install that fails (no fontconfig) records
   `installedByPowerFlow=false`.

Minor (all fixed + tested): `~/.bashrc` over-deletion if a user comment names the marker
(removal now requires the block to contain `exec pwsh`; installer `sed` anchored on the
framed comment + CR-tolerant); font detection matched non-Mono variants (now Mono-specific);
missing adapter-missing warning in the uninstall font branch.

The lesson: real-execution testing (which I'd done) proves the happy path works; it does
NOT surface "what if pwsh breaks *after* install" or "what if the user already owns this."
The adversarial pass earned its keep — two major, ship-blocking bugs in code I'd already
Docker-verified green.
