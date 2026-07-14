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

# Universal fallback: install PowerShell from Microsoft's official release tarball.
# Needs no apt/dnf repo, no GPG key, and therefore cannot hit repo-signing problems.
# This is Microsoft's documented "binary archive" method and works on any distro.
install_pwsh_tarball() {
    local arch tag ver url tmp
    case "$(uname -m)" in
        x86_64)  arch="x64" ;;
        aarch64) arch="arm64" ;;
        armv7l)  arch="arm32" ;;
        *) err "Unsupported architecture: $(uname -m)"; return 1 ;;
    esac

    command -v curl >/dev/null 2>&1 || { err "curl is required to download PowerShell."; return 1; }

    info "⬇️  Installing PowerShell from the official release archive..."

    tag="$(curl -fsSL https://api.github.com/repos/PowerShell/PowerShell/releases/latest \
            | grep -m1 '"tag_name"' | cut -d'"' -f4)"
    [[ -n "$tag" ]] || { err "Could not determine the latest PowerShell release."; return 1; }
    ver="${tag#v}"
    url="https://github.com/PowerShell/PowerShell/releases/download/${tag}/powershell-${ver}-linux-${arch}.tar.gz"

    tmp="$(mktemp -d)"
    if ! curl -fsSL "$url" -o "${tmp}/pwsh.tar.gz"; then
        err "Download failed: $url"; rm -rf "$tmp"; return 1
    fi

    $SUDO mkdir -p /opt/microsoft/powershell/7
    $SUDO tar -xzf "${tmp}/pwsh.tar.gz" -C /opt/microsoft/powershell/7
    $SUDO chmod +x /opt/microsoft/powershell/7/pwsh
    $SUDO ln -sf /opt/microsoft/powershell/7/pwsh /usr/local/bin/pwsh
    rm -rf "$tmp"

    command -v pwsh >/dev/null 2>&1
}

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
            $SUDO apt-get update -qq
            $SUDO apt-get install -y curl gnupg apt-transport-https ca-certificates

            local url="https://packages.microsoft.com/config/${distro}/${version}/packages-microsoft-prod.deb"
            info "🔎 Microsoft repo for ${distro} ${version}"

            if curl -fsSL "$url" -o /tmp/packages-microsoft-prod.deb 2>/dev/null; then
                $SUDO dpkg -i /tmp/packages-microsoft-prod.deb >/dev/null 2>&1
                $SUDO apt-get update -qq
                if $SUDO apt-get install -y powershell; then
                    ok "PowerShell installed from the ${distro} ${version} repository"
                    return 0
                fi
                warn "Repository install failed — falling back to the official archive"
            else
                warn "No Microsoft repo for ${distro} ${version} — using the official archive"
            fi

            install_pwsh_tarball || return 1
            ;;
        dnf)
            $SUDO rpm --import https://packages.microsoft.com/keys/microsoft.asc 2>/dev/null || true
            if ! $SUDO dnf install -y powershell 2>/dev/null; then
                install_pwsh_tarball || return 1
            fi
            ;;
        zypper)
            $SUDO rpm --import https://packages.microsoft.com/keys/microsoft.asc 2>/dev/null || true
            if ! $SUDO zypper --non-interactive install powershell 2>/dev/null; then
                install_pwsh_tarball || return 1
            fi
            ;;
        pacman)
            # PowerShell is only in the AUR on Arch, which we must not drive for the
            # user. The official archive works fine and needs no AUR helper.
            install_pwsh_tarball || return 1
            ;;
        *)
            # No recognised package manager — the official archive needs none.
            warn "Unrecognised package manager — using the official archive"
            install_pwsh_tarball || {
                err "Could not install PowerShell automatically. Install it manually:"
                err "  https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux"
                exit 1
            }
            ;;
    esac

    command -v pwsh >/dev/null 2>&1 || { err "PowerShell installation failed."; exit 1; }
    ok "PowerShell installed ($(pwsh --version))"
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
