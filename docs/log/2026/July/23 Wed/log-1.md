# Log 1 — July 23, 2026 — pwsh-config: one menu for OS settings (staged for v3.9.0)

**User:** `dpkg-reconfigure keyboard-configuration` did nothing in PowerFlow; wanted a
`keyboard-config` command, and asked what other reconfigure targets are worth having.

## Why dpkg-reconfigure did nothing, and why not to wrap it

`dpkg-reconfigure` is Debian/Ubuntu-only and silently no-ops when debconf can't find a
dialog frontend (whiptail/dialog) — the exact symptom. And the user's server is Fedora,
where it doesn't exist at all. Wrapping it would give a command that works on their Debian
lab but silently fails on Fedora — the opposite of one-codebase.

## The design the user landed on

First I proposed a `-config` command family (keyboard-config/kb-config, timezone-config,
locale-config). The user pushed back with a better idea: **one `pwsh-config` menu** where
every setting is selectable with its current value shown — "one would need to know what
config they want to change" otherwise, and this way "we can have many more config options
to add." That's the design: a single discoverable entry point, extensible by data.

## Built

- **`platform/{linux,windows}/adapters/sysconfig.ps1`** — a domain model: `Get-SysConfigOptions`
  returns one row per setting `{Key, Label, Current, Kind}` where Kind ∈ list|text|toggle.
  `Get-SysConfigChoices` lists the options for a list-kind; `Set-SysConfig` applies via
  systemd. Backends: `localectl` (keyboard/locale), `timedatectl` (timezone/ntp),
  `hostnamectl` (hostname) — systemd, so identical on Fedora/Debian/Ubuntu/Arch/openSUSE.
  Windows adapter is honest no-ops (no systemd). Adding a setting = one row + a case.
- **`components/system/sysconfig.ps1`** — `pwsh-config`: fzf-pick a setting → fzf-pick a
  value (or prompt/toggle) → apply with sudo. `pwsh-config kb` jumps straight in
  (kb/tz/loc/host/sync aliases). No-fzf / piped → prints the list.
- `Test-SysConfigSupported` checks localectl can OPERATE (bus up), not just that it exists —
  so it degrades honestly in containers/WSL without systemd. (Docker has no systemd as
  PID 1, which is exactly why the adapter logic was tested with mocked localectl output
  rather than live calls.)

## Verified

Adapter logic (Docker, mocked systemd CLIs): parses current values (VC Keymap, System
Locale, Timezone, NTP yes→on, hostname); builds the right set commands with a sudo prefix
when non-root (locale correctly wrapped as `LANG=`); the array-unroll sudo trap avoided via
an explicit list. Menu flow (stubbed fzf): two-level list flow sets the chosen value;
alias resolution (tz→timezone); cancel changes nothing; toggle/text correctly refuse under
a pipe (no terminal to prompt); no-arg under redirection prints the list; unknown key
rejected. Windows: prints the "use Windows Settings" note, changes nothing. Static gates:
parse, architecture (localectl only in the adapter), parity (4 functions both platforms),
pwsh-config registered.

## Process note

Held at release-ready per the user: 3.8.0 (pwsh-exit) shipped earlier the same day, and
they rightly flagged that cutting a second version hours later is noise — pwsh-exit and
pwsh-config could have been one release. Lesson: batch a session's features into one
release unless asked to ship incrementally. v3.9.0 waits for the green light.
