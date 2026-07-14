#!/usr/bin/env bash
# ==============================================================================
# PowerFlow — Linux Installer (graphical)
# ==============================================================================
# A GUI FRONT-END, not a second installer.
#
# This collects consent through native dialogs and then delegates to install.sh,
# which delegates to install.ps1 — the same installer Windows uses. There is one
# installer codebase; this file only decides how the questions get asked.
#
# Dialog toolkit is chosen at runtime:
#     zenity (GNOME) -> kdialog (KDE) -> yad -> fall back to the terminal installer
#
# It never hard-fails just because a dialog tool is missing.
# ==============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SH="${HERE}/install.sh"

# ── Pick a dialog toolkit ─────────────────────────────────────────────────────
GUI=""
if   command -v zenity  >/dev/null 2>&1; then GUI="zenity"
elif command -v kdialog >/dev/null 2>&1; then GUI="kdialog"
elif command -v yad     >/dev/null 2>&1; then GUI="yad"
fi

if [[ -z "$GUI" ]]; then
    echo "⚠️  No graphical dialog tool found (zenity / kdialog / yad)."
    echo "   Falling back to the terminal installer."
    echo ""
    exec bash "$INSTALL_SH" "$@"
fi

# ── Thin wrappers over the three toolkits ─────────────────────────────────────
gui_info() {
    case "$GUI" in
        zenity)  zenity  --info --width=420 --title="PowerFlow" --text="$1" ;;
        kdialog) kdialog --title "PowerFlow" --msgbox "$1" ;;
        yad)     yad     --info --title="PowerFlow" --text="$1" ;;
    esac
}
gui_error() {
    case "$GUI" in
        zenity)  zenity  --error --width=420 --title="PowerFlow" --text="$1" ;;
        kdialog) kdialog --title "PowerFlow" --error "$1" ;;
        yad)     yad     --error --title="PowerFlow" --text="$1" ;;
    esac
}
gui_confirm() {   # returns 0 = yes
    case "$GUI" in
        zenity)  zenity  --question --width=460 --title="PowerFlow" --text="$1" ;;
        kdialog) kdialog --title "PowerFlow" --yesno "$1" ;;
        yad)     yad     --question --title="PowerFlow" --text="$1" ;;
    esac
}

# ── 1. Welcome ────────────────────────────────────────────────────────────────
WELCOME="<b>PowerFlow</b> — an enhanced PowerShell profile for Linux.

Smart navigation, Git workflows, fuzzy pickers and productivity tooling.

This installer will:
  • install PowerShell (pwsh) if it is not present
  • install PowerFlow into ~/.config/powershell
  • optionally install: starship, fzf, zoxide, lsd, git

<i>Your existing shell is not changed. GNU tools (rm, mv, cp, cat) keep working
exactly as they do now — PowerFlow's own versions are named 'del' and 'mvf'.</i>

Continue?"

if ! gui_confirm "$WELCOME"; then
    exit 0
fi

# ── 2. Dependencies ───────────────────────────────────────────────────────────
NO_DEPS_FLAG=""
DEPS_TEXT="Install the recommended tools?

  • <b>starship</b> — prompt
  • <b>fzf</b> — fuzzy finder (required by nav, git pickers)
  • <b>zoxide</b> — smart directory jumping
  • <b>lsd</b> — pretty listings
  • <b>git</b> — version control

Tools you already have will be left alone.

Choosing <b>No</b> installs PowerFlow only."

if ! gui_confirm "$DEPS_TEXT"; then
    NO_DEPS_FLAG="--no-deps"
fi

# ── 3. Run the real installer, streaming progress into a dialog ───────────────
# install.sh needs sudo for the package manager. pkexec gives a graphical prompt
# when available; otherwise the terminal sudo prompt still works.
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

run_install() {
    bash "$INSTALL_SH" --yes $NO_DEPS_FLAG 2>&1 | tee "$LOG"
}

case "$GUI" in
    zenity)
        run_install | zenity --progress --pulsate --auto-close --width=520 \
            --title="Installing PowerFlow" --text="Installing…" || true
        ;;
    yad)
        run_install | yad --progress --pulsate --auto-close --width=520 \
            --title="Installing PowerFlow" --text="Installing…" || true
        ;;
    kdialog)
        # kdialog has no streaming progress widget; run it and report at the end.
        run_install >/dev/null 2>&1 || true
        ;;
esac

# ── 4. Report ─────────────────────────────────────────────────────────────────
if grep -q "PowerFlow v.* installed" "$LOG" 2>/dev/null; then
    gui_info "<b>✅ PowerFlow installed.</b>

Open a terminal and run:
    <tt>pwsh</tt>
then:
    <tt>pwsh-h</tt>   for the full command reference

<i>Note: rm / mv / cp / cat remain the GNU tools.
PowerFlow's versions are 'del' and 'mvf'.</i>"
else
    gui_error "<b>❌ Installation failed.</b>

Last lines of the log:

<tt>$(tail -n 8 "$LOG" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')</tt>

Try the terminal installer for full output:
<tt>bash install.sh</tt>"
    exit 1
fi
