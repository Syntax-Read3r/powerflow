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

  --yes         Assume yes; no prompts (CI-safe)
  --no-deps     Install PowerFlow only; skip fzf/zoxide/starship/lsd
  --prefix DIR  Install root (default: ~/.local/share/powerflow)
  --uninstall   Remove PowerFlow
  -h, --help    Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes|-y)     ASSUME_YES=1; shift ;;
        --no-deps)    NO_DEPS=1; shift ;;
        --prefix)     PREFIX="$2"; shift 2 ;;
        --uninstall)  DO_UNINSTALL=1; shift ;;
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
    else echo "none"; fi
}
PM="$(detect_pm)"

# ── 2. Install pwsh if missing ────────────────────────────────────────────────
install_pwsh() {
    if command -v pwsh >/dev/null 2>&1; then
        ok "PowerShell already installed ($(pwsh --version))"
        return 0
    fi

    info "📦 Installing PowerShell..."

    # snap is the fewest moving parts when it is available.
    if command -v snap >/dev/null 2>&1; then
        if $SUDO snap install powershell --classic; then
            ok "PowerShell installed via snap"
            return 0
        fi
        warn "snap install failed — falling back to the package repository"
    fi

    case "$PM" in
        apt)
            $SUDO apt-get update -qq
            $SUDO apt-get install -y curl gnupg apt-transport-https ca-certificates
            local codename; codename="$(. /etc/os-release && echo "${VERSION_ID}")"
            curl -fsSL "https://packages.microsoft.com/config/ubuntu/${codename}/packages-microsoft-prod.deb" \
                -o /tmp/packages-microsoft-prod.deb 2>/dev/null \
              || curl -fsSL "https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb" \
                -o /tmp/packages-microsoft-prod.deb
            $SUDO dpkg -i /tmp/packages-microsoft-prod.deb
            $SUDO apt-get update -qq
            $SUDO apt-get install -y powershell
            ;;
        dnf)
            $SUDO rpm --import https://packages.microsoft.com/keys/microsoft.asc
            $SUDO dnf install -y https://packages.microsoft.com/config/rhel/9/packages-microsoft-prod.rpm || true
            $SUDO dnf install -y powershell
            ;;
        pacman)
            err "PowerShell is in the AUR on Arch. Install it first:  yay -S powershell-bin"
            exit 1
            ;;
        zypper)
            $SUDO rpm --import https://packages.microsoft.com/keys/microsoft.asc
            $SUDO zypper --non-interactive install powershell
            ;;
        *)
            err "No supported package manager found. Install PowerShell manually:"
            err "  https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux"
            exit 1
            ;;
    esac

    command -v pwsh >/dev/null 2>&1 || { err "PowerShell installation failed."; exit 1; }
    ok "PowerShell installed"
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
        cp -r "$src"/. "$PREFIX"/
    fi
    ok "PowerFlow files placed in ${PREFIX}"

    # Hand off. install.ps1 does the real work and is shared with Windows.
    info "🔧 Running the shared installer..."
    args=("-Platform" "linux" "-Prefix" "$PREFIX")
    [[ "$ASSUME_YES" -eq 1 ]] && args+=("-Yes")
    [[ "$NO_DEPS"    -eq 1 ]] && args+=("-NoDeps")

    pwsh -NoProfile -File "${PREFIX}/install.ps1" "${args[@]}"
}

main "$@"
