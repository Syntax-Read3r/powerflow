#!/usr/bin/env bash
# ==============================================================================
# PowerFlow — Linux Installer (terminal)
# ==============================================================================
# This is a THIN BOOTSTRAP, not the installer.
#
# The real installer is install.ps1 — the same one Windows uses. This script only
# exists because pwsh may not be present yet on a fresh box, and you cannot run a
# PowerShell installer without PowerShell. Its entire job is:
#
#   1. detect the distro / package manager
#   2. install pwsh
#   3. hand off to install.ps1
#
# Everything after step 3 is shared with Windows. Writing a second, parallel
# installer in bash is exactly the duplication that rotted the old Ubuntu port.
#
#   curl -fsSL https://github.com/Syntax-Read3r/powerflow/releases/latest/download/install.sh | bash
#   curl -fsSL ... | bash -s -- --yes --no-deps
# ==============================================================================
set -euo pipefail

REPO="Syntax-Read3r/powerflow"
ASSUME_YES=0
NO_DEPS=0
DO_UNINSTALL=0
PREFIX="${HOME}/.local/share/powerflow"

# How should PowerFlow start on login?
#   ask   — prompt (default when interactive)
#   auto  — exec pwsh from ~/.bashrc, guarded  (RECOMMENDED)
#   login — chsh: make pwsh the actual login shell
#   none  — do nothing; run `pwsh` by hand
LOGIN_SHELL_MODE="ask"

# The marker that makes the ~/.bashrc block findable and idempotent.
PF_BASHRC_MARKER="PowerFlow: launch pwsh on interactive login"

# Where is this script? Empty when piped (`curl … | bash`), because BASH_SOURCE is
# then not a real file. A non-empty $HERE containing components/ means we are in a
# checkout and must install from IT, not from a download.
HERE=""
_self="${BASH_SOURCE[0]:-$0}"
if [[ -f "$_self" ]]; then
    HERE="$(cd "$(dirname "$_self")" && pwd)"
fi

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}$*${NC}"; }
ok()    { echo -e "${GREEN}✅ $*${NC}"; }
warn()  { echo -e "${YELLOW}⚠️  $*${NC}"; }
err()   { echo -e "${RED}❌ $*${NC}" >&2; }

usage() {
    cat <<'EOF'
PowerFlow installer (Linux)

  --yes                 Assume yes; no prompts (CI-safe)
  --auto-login          Launch PowerFlow automatically on login (RECOMMENDED).
                        Short alias for --login-shell auto.
  --no-deps             Install PowerFlow only; skip fzf/zoxide/starship/lsd
  --prefix DIR          Install root (default: ~/.local/share/powerflow)
  --uninstall           Remove PowerFlow
  -h, --help            Show this help

  PowerFlow is a PowerShell profile — it only loads when `pwsh` runs. On a server
  your login shell is normally bash, so after a reboot you land in bash and
  PowerFlow is simply not there. Choose how it should start:

  --auto-login          Launch pwsh from ~/.bashrc on interactive login.
                        RECOMMENDED, and the same as --login-shell auto. Guarded,
                        so a broken pwsh still leaves you with bash — no lockout.
  --login-shell login   chsh: make pwsh your actual login shell. Cleaner, but if
                        pwsh fails to start you have NO shell. Risky on a headless
                        box.
  --login-shell none    Do nothing. Run `pwsh` by hand.

  With no --login-shell and no --yes, the installer asks.
  With --yes and no --login-shell, it does nothing (CI-safe default).
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes|-y)     ASSUME_YES=1; shift ;;
        --auto-login) LOGIN_SHELL_MODE="auto"; shift ;;   # short alias for --login-shell auto
        --no-deps)    NO_DEPS=1; shift ;;
        --prefix)     PREFIX="$2"; shift 2 ;;
        --uninstall)  DO_UNINSTALL=1; shift ;;
        --login-shell)
            LOGIN_SHELL_MODE="$2"
            case "$LOGIN_SHELL_MODE" in
                auto|login|none) ;;
                *) err "--login-shell must be: auto | login | none"; exit 1 ;;
            esac
            shift 2 ;;
        -h|--help)    usage; exit 0 ;;
        *)            err "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# ── sudo only when we are not already root ────────────────────────────────────
SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then SUDO="sudo"
    else err "Not root and sudo is unavailable. Re-run as root."; exit 1; fi
fi

# ── 1. Detect the package manager ─────────────────────────────────────────────
detect_pm() {
    if   command -v apt-get >/dev/null 2>&1; then echo "apt"
    elif command -v dnf     >/dev/null 2>&1; then echo "dnf"
    elif command -v pacman  >/dev/null 2>&1; then echo "pacman"
    elif command -v zypper  >/dev/null 2>&1; then echo "zypper"
    elif command -v apk     >/dev/null 2>&1; then echo "apk"
    else echo "none"; fi
}
PM="$(detect_pm)"

# ── 2. Install pwsh if missing ────────────────────────────────────────────────

# Is PowerShell actually USABLE?
#
# `command -v pwsh` is NOT sufficient. The binary archive can install a pwsh that
# exists on PATH but dies instantly with "Couldn't find a valid ICU package" — so the
# installer would report success and then everything downstream fails. Run it.
pwsh_works() {
    command -v pwsh >/dev/null 2>&1 || return 1
    pwsh --version >/dev/null 2>&1
}

# Runtime libraries the PowerShell binary needs.
#
# A distro package pulls these in automatically. The tarball does NOT — hence the
# ICU crash above. Install them explicitly before falling back to the archive.
install_pwsh_prereqs() {
    case "$PM" in
        apt)    $SUDO apt-get install -y -qq libicu-dev  >/dev/null 2>&1 || true ;;
        dnf)    $SUDO dnf install -y -q libicu            >/dev/null 2>&1 || true ;;
        zypper) $SUDO zypper --non-interactive install libicu >/dev/null 2>&1 || true ;;
        pacman) $SUDO pacman -S --noconfirm icu           >/dev/null 2>&1 || true ;;
        apk)    $SUDO apk add --quiet icu-libs libstdc++ >/dev/null 2>&1 || true ;;
    esac
}

# Universal fallback: install PowerShell from Microsoft's official release archive.
# Needs no apt/dnf repo and no GPG key, so it cannot hit repo-signing problems.
install_pwsh_tarball() {
    local arch libc tag ver url tmp
    case "$(uname -m)" in
        x86_64)  arch="x64" ;;
        aarch64) arch="arm64" ;;
        armv7l)  arch="arm32" ;;
        *) err "Unsupported architecture: $(uname -m)"; return 1 ;;
    esac

    # Alpine is musl, not glibc — it needs a different archive entirely.
    libc="linux"
    if [[ "$PM" == "apk" ]] || ! ldd /bin/sh 2>/dev/null | grep -q 'libc\.so\.6'; then
        if [[ "$PM" == "apk" ]]; then libc="linux-musl"; fi
    fi

    command -v curl >/dev/null 2>&1 || { err "curl is required to download PowerShell."; return 1; }

    info "⬇️  Installing PowerShell from the official release archive..."
    install_pwsh_prereqs

    # Finding the latest release WITHOUT dying to rate limits. api.github.com 403s
    # anonymous calls from shared CI runner IPs — that exact 403 killed the v3.3.2
    # release on the Arch leg. Three layers:
    #
    #   1. The redirect trick: github.com/…/releases/latest 302s to …/tag/vX.Y.Z.
    #      That is the website, not the API — no meaningful rate limit.
    #   2. The API, authenticated if a token is around (CI passes GITHUB_TOKEN).
    #   3. A pinned known-good version, loudly, so an outage degrades instead of aborts.
    tag="$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
            https://github.com/PowerShell/PowerShell/releases/latest 2>/dev/null \
            | sed 's|.*/tag/||')"

    if [[ ! "$tag" =~ ^v[0-9] ]]; then
        auth=()
        [[ -n "${GITHUB_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
        tag="$(curl -fsSL ${auth[@]+"${auth[@]}"} \
                https://api.github.com/repos/PowerShell/PowerShell/releases/latest \
                | grep -m1 '"tag_name"' | cut -d'"' -f4)"
    fi

    if [[ ! "$tag" =~ ^v[0-9] ]]; then
        tag="v7.5.2"
        warn "Could not query the latest PowerShell release (rate limit or outage) — falling back to ${tag}."
    fi
    ver="${tag#v}"
    url="https://github.com/PowerShell/PowerShell/releases/download/${tag}/powershell-${ver}-${libc}-${arch}.tar.gz"

    tmp="$(mktemp -d)"
    if ! curl -fsSL "$url" -o "${tmp}/pwsh.tar.gz"; then
        err "Download failed: $url"; rm -rf "$tmp"; return 1
    fi

    $SUDO mkdir -p /opt/microsoft/powershell/7
    $SUDO tar -xzf "${tmp}/pwsh.tar.gz" -C /opt/microsoft/powershell/7
    $SUDO chmod +x /opt/microsoft/powershell/7/pwsh
    $SUDO ln -sf /opt/microsoft/powershell/7/pwsh /usr/local/bin/pwsh
    rm -rf "$tmp"

    pwsh_works
}

install_pwsh() {
    if pwsh_works; then
        ok "PowerShell already installed ($(pwsh --version))"
        return 0
    fi

    info "📦 Installing PowerShell..."

    # snap is the fewest moving parts when it is available.
    if command -v snap >/dev/null 2>&1; then
        if $SUDO snap install powershell --classic 2>/dev/null && pwsh_works; then
            ok "PowerShell installed via snap"
            return 0
        fi
        warn "snap install failed — falling back to the package repository"
    fi

    # Read the REAL distro id and version.
    #
    # Getting this wrong is not cosmetic. Building an Ubuntu URL from a Debian
    # VERSION_ID 404s, and falling back to a hardcoded debian/12 repo puts a
    # *bookworm* source on a *trixie* box — whose signing key carries a SHA1 binding
    # signature that Debian 13's apt rejects outright ("repository is not signed").
    # Ask for the correct distro/version and the problem does not exist.
    local distro version
    distro="$(. /etc/os-release && echo "${ID}")"
    version="$(. /etc/os-release && echo "${VERSION_ID}")"

    case "$PM" in
        apt)
            # A previous or failed install may have left a Microsoft apt source pointing
            # at the WRONG release — e.g. a bookworm repo on a trixie box. Its signing
            # key uses SHA1, which Debian 13's apt rejects, and that poisons EVERY
            # subsequent `apt-get update`. With `set -e` the script would then abort here,
            # before it could reach the correct-repo logic below — so the machine stays
            # broken no matter how many times you re-run a fixed installer.
            #
            # Clear any stale Microsoft source before touching apt.
            if compgen -G "/etc/apt/sources.list.d/microsoft*" >/dev/null 2>&1; then
                warn "Removing a stale Microsoft apt source (it blocks apt-get update)"
                # PURGE, not remove: -r leaves the conffile registered, so installing the
                # correct repo later hits an interactive conffile prompt, dies with
                # "end of file on stdin at conffile prompt", and leaves a .dpkg-new orphan.
                $SUDO dpkg --purge packages-microsoft-prod >/dev/null 2>&1 || true
                $SUDO rm -f /etc/apt/sources.list.d/microsoft*.list \
                            /etc/apt/sources.list.d/microsoft*.sources \
                            /etc/apt/sources.list.d/microsoft*.dpkg-* 2>/dev/null || true
            fi

            # Never let a third-party repo error abort the install.
            $SUDO apt-get update -qq 2>/dev/null || warn "apt-get update reported errors — continuing"
            $SUDO apt-get install -y curl gnupg apt-transport-https ca-certificates >/dev/null 2>&1 || true

            local url="https://packages.microsoft.com/config/${distro}/${version}/packages-microsoft-prod.deb"
            info "🔎 Microsoft repo for ${distro} ${version}"

            if curl -fsSL "$url" -o /tmp/packages-microsoft-prod.deb 2>/dev/null; then
                # noninteractive + force-confnew: dpkg must never stop for a prompt here,
                # and every failure below is recoverable via the archive fallback.
                $SUDO DEBIAN_FRONTEND=noninteractive dpkg -i --force-confnew \
                    /tmp/packages-microsoft-prod.deb >/dev/null 2>&1 || true
                $SUDO apt-get update -qq 2>/dev/null || true

                if $SUDO apt-get install -y powershell >/dev/null 2>&1 && pwsh_works; then
                    ok "PowerShell installed from the ${distro} ${version} repository"
                    return 0
                fi
                warn "Repository install failed — falling back to the official archive"
            else
                warn "No Microsoft repo for ${distro} ${version} — using the official archive"
            fi

            install_pwsh_tarball || return 1
            ;;

        dnf|zypper)
            # Microsoft publishes an .rpm repo config for rhel / fedora / opensuse.
            # Importing the signing key alone is NOT enough — without the repo config
            # the `powershell` package simply does not exist and the install fails.
            local rpm_url="https://packages.microsoft.com/config/${distro}/${version}/packages-microsoft-prod.rpm"
            info "🔎 Microsoft repo for ${distro} ${version}"

            $SUDO rpm --import https://packages.microsoft.com/keys/microsoft.asc >/dev/null 2>&1 || true

            if curl -fsSL -o /tmp/packages-microsoft-prod.rpm "$rpm_url" 2>/dev/null; then
                if [[ "$PM" == "dnf" ]]; then
                    $SUDO dnf install -y -q /tmp/packages-microsoft-prod.rpm >/dev/null 2>&1 || true
                    $SUDO dnf install -y -q powershell >/dev/null 2>&1 || true
                else
                    $SUDO zypper --non-interactive install /tmp/packages-microsoft-prod.rpm >/dev/null 2>&1 || true
                    $SUDO zypper --non-interactive --gpg-auto-import-keys refresh >/dev/null 2>&1 || true
                    $SUDO zypper --non-interactive install powershell >/dev/null 2>&1 || true
                fi

                if pwsh_works; then
                    ok "PowerShell installed from the ${distro} ${version} repository"
                    return 0
                fi
                warn "Repository install failed — falling back to the official archive"
            else
                warn "No Microsoft repo for ${distro} ${version} — using the official archive"
            fi

            install_pwsh_tarball || return 1
            ;;

        pacman|apk)
            # Arch only has PowerShell in the AUR, and Alpine has no official package.
            # We must not drive an AUR helper on the user's behalf — the official
            # archive works on both and needs neither.
            install_pwsh_tarball || return 1
            ;;

        *)
            warn "Unrecognised package manager — using the official archive"
            install_pwsh_tarball || {
                err "Could not install PowerShell automatically. Install it manually:"
                err "  https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux"
                exit 1
            }
            ;;
    esac

    # Verify it RUNS, not merely that it exists on PATH.
    pwsh_works || { err "PowerShell was placed but cannot run. Install it manually."; exit 1; }
    ok "PowerShell installed ($(pwsh --version))"
}

# ── 2b. How should PowerFlow start on login? ──────────────────────────────────
#
# PowerFlow is a PowerShell PROFILE — it only loads when pwsh runs. On a server the
# login shell is normally bash, so after a reboot the user lands in bash and PowerFlow
# is simply absent. The installer never used to mention this and told people to
# "restart your shell", which on Linux does nothing at all.

# Is the ~/.bashrc launcher already installed?
bashrc_hook_present() {
    [[ -f "$HOME/.bashrc" ]] && grep -q "$PF_BASHRC_MARKER" "$HOME/.bashrc"
}

# Option A: exec pwsh from ~/.bashrc, guarded so it can never lock you out.
install_bashrc_hook() {
    if bashrc_hook_present; then
        ok "Login hook already present in ~/.bashrc — nothing to do"
        return 0
    fi

    cat >> "$HOME/.bashrc" <<EOF

# ── ${PF_BASHRC_MARKER} ──
# Guards, in order:
#   \$- == *i*      only interactive shells — never scp/rsync/cron/scripts
#   PWSH_STARTED   prevents a login loop
#   command -v     if pwsh is ever removed you still get bash — no lockout
#   pwsh --version pwsh must RUN, not merely exist — a broken pwsh (e.g. missing
#                  ICU) falls through to bash instead of exec-crash-looping login
if [[ \$- == *i* ]] && [[ -z "\$PWSH_STARTED" ]] && command -v pwsh >/dev/null 2>&1 && pwsh --version >/dev/null 2>&1; then
    export PWSH_STARTED=1
    exec pwsh
fi
EOF

    ok "PowerFlow will now start on login (via ~/.bashrc)"
    info "   Test it WITHOUT logging out — from this session run:  bash -l"
    info "   Undo:  sed -i '/${PF_BASHRC_MARKER}/,/^fi$/d' ~/.bashrc"
    return 0
}

# Option B: make pwsh the actual login shell.
install_login_shell() {
    local pwsh_path me
    pwsh_path="$(command -v pwsh)"
    me="$(id -un)"

    # A shell must be listed in /etc/shells before chsh will accept it.
    if ! grep -qx "$pwsh_path" /etc/shells 2>/dev/null; then
        info "Registering $pwsh_path in /etc/shells..."
        echo "$pwsh_path" | $SUDO tee -a /etc/shells >/dev/null
    fi

    # Plain `chsh` PROMPTS FOR A PASSWORD, so it fails silently when piped or run
    # non-interactively — the shell stays unchanged and the user is told nothing.
    # Go through sudo (no prompt) and only fall back to plain chsh.
    if $SUDO chsh -s "$pwsh_path" "$me" 2>/dev/null || chsh -s "$pwsh_path" 2>/dev/null; then
        # Verify: never claim success on chsh's exit code alone.
        local now
        now="$(getent passwd "$me" | cut -d: -f7)"
        if [[ "$now" == "$pwsh_path" ]]; then
            ok "pwsh is now your login shell"
            warn "If pwsh ever fails to start you will have NO shell on login."
            info "   Undo:  chsh -s /bin/bash"
            return 0
        fi
    fi

    err "Could not change your login shell (chsh needs a password, or PAM refused)."
    info "   Run it yourself:  chsh -s $pwsh_path"
    info "   Or use the safer option:  bash install.sh --login-shell auto"
    return 1
}

# Copy the source tree into PREFIX.
#
# NOT `cp -r "$src"/. "$PREFIX"/`. That copies .git along with everything else, and git's
# loose objects are mode 444 — read-only. On a FIRST install that is merely wasteful (a
# few MB the runtime never reads). On a SECOND install cp cannot overwrite them, fails,
# and `set -euo pipefail` kills the installer with a wall of "Permission denied".
#
# Which means: re-running install.sh from a clone — the normal way to change your mind
# about --login-shell — was impossible. It also broke the release CI, which installs
# twice on purpose to prove the login hook is idempotent.
#
# .github, node_modules and assets/ are excluded for the same "the runtime never reads it"
# reason. assets/ alone is 58 MB of README screenshots — it was landing in every Linux
# install, while the Windows installer (which copies a curated list) never shipped it.
copy_tree() {
    local src="$1" dst="$2"
    ( cd "$src" && tar -cf - \
          --exclude=./.git \
          --exclude=./.github \
          --exclude=./node_modules \
          --exclude=./assets \
          . ) | ( cd "$dst" && tar -xf - )
}

configure_login_shell() {
    # Already launching pwsh? Say so and stop.
    if bashrc_hook_present; then
        ok "PowerFlow already starts on login (~/.bashrc hook present)"
        return 0
    fi

    # Non-interactive with no explicit choice: do nothing. Never surprise CI or a
    # `curl … | bash --yes` by rewriting someone's shell config.
    if [[ "$LOGIN_SHELL_MODE" == "ask" && "$ASSUME_YES" -eq 1 ]]; then
        LOGIN_SHELL_MODE="none"
    fi

    # NO TERMINAL, NO QUESTION.
    #
    # In `curl … | bash`, stdin is the pipe curl already drained. `read` therefore gets EOF
    # immediately and returns non-zero — and under `set -euo pipefail` that killed the
    # installer with exit 1 AFTER it had already installed everything successfully. The
    # user saw "🎉 PowerFlow installed!" followed by a failure, which is a great way to make
    # someone distrust an installer that actually worked.
    if [[ "$LOGIN_SHELL_MODE" == "ask" && ! -t 0 ]]; then
        LOGIN_SHELL_MODE="none"
        info "🐚 No terminal to ask on (the installer is being piped), so your login shell is untouched."
        info "   To have PowerFlow start automatically on login, re-run with:"
        info "     curl -fsSL <url>/install.sh | bash -s -- --login-shell auto"
    fi

    if [[ "$LOGIN_SHELL_MODE" == "ask" ]]; then
        echo ""
        info "🐚 How should PowerFlow start?"
        echo ""
        echo "   PowerFlow is a PowerShell profile — it only loads when 'pwsh' runs."
        echo "   Your login shell is ${SHELL:-bash}, so after a reboot you will land in"
        echo "   bash and PowerFlow will NOT be there unless you set this up."
        echo ""
        echo "   1) Launch pwsh automatically on login   (recommended — adds a guarded"
        echo "      block to ~/.bashrc; a broken pwsh still leaves you with bash)"
        echo "   2) Make pwsh my login shell             (chsh — cleaner, but if pwsh"
        echo "      fails to start you have NO shell. Risky on a headless server.)"
        echo "   3) Do nothing                           (run 'pwsh' by hand)"
        echo ""
        read -r -p "Choose [1/2/3] (default 1): " choice
        case "${choice:-1}" in
            1) LOGIN_SHELL_MODE="auto"  ;;
            2) LOGIN_SHELL_MODE="login" ;;
            *) LOGIN_SHELL_MODE="none"  ;;
        esac
    fi

    case "$LOGIN_SHELL_MODE" in
        auto)  install_bashrc_hook ;;
        login) install_login_shell ;;
        none)
            info "ℹ️  PowerFlow will not start automatically."
            info "   Run 'pwsh' to use it, or re-run with:  --login-shell auto"
            ;;
    esac
}

# ── 3. Fetch PowerFlow and hand off to the shared installer ───────────────────
main() {
    echo ""
    info "🚀 PowerFlow — Linux installation"
    info "================================="
    echo ""

    if [[ "$DO_UNINSTALL" -eq 1 ]]; then
        if ! command -v pwsh >/dev/null 2>&1; then
            err "pwsh not found — nothing to uninstall."; exit 1
        fi
        [[ -f "${PREFIX}/uninstall.ps1" ]] \
            || { err "PowerFlow is not installed at ${PREFIX}"; exit 1; }

        # Strip the ~/.bashrc launcher FIRST. Leaving it behind after removing pwsh
        # would leave a dead `exec pwsh` in the login path — the `command -v pwsh`
        # guard saves the user from a lockout, but the block is still dead weight.
        if bashrc_hook_present; then
            # Anchor the range START on the FRAMED comment line (# ── marker ──), not the
            # bare marker: a user comment that merely mentions the phrase has no box-frame,
            # so it can never start a deletion. End on `fi` allowing a trailing CR, so a
            # CRLF ~/.bashrc (edited on Windows) still terminates the range correctly. If
            # no framed line exists, the range never opens and nothing is deleted.
            sed -i "/# ── ${PF_BASHRC_MARKER} ──/,/^fi[[:space:]]*\$/d" "$HOME/.bashrc"
            ok "Removed the PowerFlow launcher from ~/.bashrc"
        fi

        # If pwsh was made the login shell, hand the user back a working one BEFORE
        # removing pwsh — otherwise the next login has no shell at all.
        #
        # Read the real shell from passwd, not $SHELL: $SHELL is inherited from the
        # parent process and still says /bin/bash inside a bash subshell even after
        # chsh has changed it.
        local me current
        me="$(id -un)"
        current="$(getent passwd "$me" | cut -d: -f7)"

        if [[ "$current" == *pwsh* ]]; then
            warn "pwsh is your login shell — reverting to bash so you are not left without one."
            # sudo, because plain chsh prompts for a password and fails silently.
            $SUDO chsh -s /bin/bash "$me" 2>/dev/null || chsh -s /bin/bash 2>/dev/null || true

            current="$(getent passwd "$me" | cut -d: -f7)"
            if [[ "$current" == *pwsh* ]]; then
                err "Could not revert your login shell. Do it NOW, before you log out:"
                err "   chsh -s /bin/bash"
                exit 1
            fi
            ok "Login shell reverted to $current"
        fi

        # Build the arg list explicitly — an unquoted $(...) here would word-split.
        uninstall_args=()
        [[ "$ASSUME_YES" -eq 1 ]] && uninstall_args+=("-Yes")
        exec pwsh -NoProfile -File "${PREFIX}/uninstall.ps1" "${uninstall_args[@]}"
    fi

    install_pwsh

    mkdir -p "$PREFIX"

    # Source resolution: prefer a local checkout, else download.
    #
    # This MUST come first. If it always downloaded, running install.sh from a git
    # checkout (or from CI, which checks out the tag) would silently discard that
    # code and install whatever happens to be on the main branch instead — so a
    # release could be "validated" against code that is not the code being released.
    if [[ -n "$HERE" && -d "$HERE/components" && -d "$HERE/platform" ]]; then
        src="$HERE"
        info "📦 Installing from local checkout: $src"
    else
        info "⬇️  Downloading PowerFlow..."
        tmp="$(mktemp -d)"
        trap 'rm -rf "$tmp"' EXIT

        if ! curl -fsSL "https://github.com/${REPO}/archive/refs/heads/main.tar.gz" -o "${tmp}/pf.tar.gz"; then
            err "Download failed."; exit 1
        fi
        tar -xzf "${tmp}/pf.tar.gz" -C "$tmp"
        src="$(find "$tmp" -maxdepth 1 -type d -name 'powerflow-*' | head -1)"
        [[ -n "$src" ]] || { err "Unexpected archive layout."; exit 1; }
    fi

    # Copy into PREFIX unless we are already installing from it
    if [[ "$(cd "$src" && pwd)" != "$(cd "$PREFIX" && pwd)" ]]; then
        copy_tree "$src" "$PREFIX"
    fi
    ok "PowerFlow files placed in ${PREFIX}"

    # Hand off. install.ps1 does the real work and is shared with Windows.
    info "🔧 Running the shared installer..."
    args=("-Platform" "linux" "-Prefix" "$PREFIX")
    [[ "$ASSUME_YES" -eq 1 ]] && args+=("-Yes")
    [[ "$NO_DEPS"    -eq 1 ]] && args+=("-NoDeps")

    pwsh -NoProfile -File "${PREFIX}/install.ps1" "${args[@]}" || exit 1

    # ── Finally: make sure PowerFlow actually STARTS ──────────────────────────
    # Without this the install "succeeds" and then the user reboots into bash and
    # sees no PowerFlow at all — which is exactly what happened.
    configure_login_shell

    echo ""
    if bashrc_hook_present || [[ "$LOGIN_SHELL_MODE" == "login" ]]; then
        ok "Done. Log out and back in — PowerFlow will load automatically."
        info "   Or test right now, without logging out:  bash -l"
    else
        ok "Done. Start PowerFlow with:  pwsh"
        info "   Then type 'pwsh-h' for the command reference."
    fi
    echo ""
}

main "$@"
