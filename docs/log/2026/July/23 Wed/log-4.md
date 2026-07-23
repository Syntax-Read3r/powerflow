# Log 4 — July 23, 2026 — pwsh-config keyboard: the Debian/vconsole gap (staged for v3.9.1)

**User (on a Debian 13 server):** ran `pwsh-config`, picked *Keyboard layout* (shown as
`(unset)`), and got `❌ No choices available (are locales generated?).`

## Root cause — two keyboard models, not one

`pwsh-config`'s keyboard setting was written against the **vconsole** model:
`localectl list-keymaps` / `set-keymap`, backed by keymap files in `/usr/share/keymaps`.
That's how Fedora and Arch do it. **Debian/Ubuntu don't.** They ship *no* vconsole keymaps
and manage the keyboard through **console-setup / X11 layouts** (`/etc/default/keyboard`),
so `localectl list-keymaps` is empty by design.

Reproduced the package side in a `debian:trixie` container: neither `kbd` nor a minimal base
provides `/usr/share/keymaps` (0 files), and `kbd-model-map` is absent — confirming the
vconsole keymaps simply aren't there on Debian. (localectl's *operations* need a live systemd
bus, which a plain container lacks, so the list/set calls themselves can't be exercised in
Docker — those were verified by logic + the user's real server.)

The old error message made it worse: "are locales generated?" blamed locales for a keyboard
problem, sending the user down the wrong path.

## Fix — detect the model, use the right one

New `Get-KeyboardMode` in the Linux adapter: vconsole keymaps present → `vc`, else → `x11`.
The keyboard setting now branches on it:

- **choices** — `list-keymaps` (vc) or `list-x11-keymap-layouts` (x11, Debian/Ubuntu)
- **set** — `set-keymap` (vc) or `set-x11-keymap` (x11; on Debian this writes
  `/etc/default/keyboard` and converts to a console keymap too)
- **current** — read `VC Keymap` from `localectl status`, and when it's unset/`n/a` fall back
  to the `X11 Layout` line, so the menu shows what's actually configured instead of `(unset)`

Fedora/Arch are untouched: the fallback only fires when `list-keymaps` / `VC Keymap` is empty.
The component's empty-list message is now per-setting (keyboard vs locale vs timezone) instead
of always naming locales.

## Verified

Adapter + component parse; full tree parses. Mock-tested the decision logic: `set` dispatches
to `set-keymap` in vc mode and `set-x11-keymap` in x11 mode; other settings
(timezone/locale/hostname) unchanged; the X11-Layout `Current` fallback resolves `gb`/`fr`
when VC Keymap is unset/`n/a` and leaves a real VC keymap (`us`) alone; the keyboard hint no
longer mentions locales. The live `localectl list-x11-keymap-layouts` / `set-x11-keymap`
calls need validation on a real Debian box (no systemd in Docker) — flagged for the user.

Held with the [3.9.1] batch — no release.
