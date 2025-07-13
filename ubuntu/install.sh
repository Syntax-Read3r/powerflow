#!/bin/bash

# ============================================================================
# PowerFlow Fish Shell Installation Script
# ============================================================================
# Installs and configures PowerFlow enhanced Fish profile for WSL Ubuntu.
# This script sets up Fish shell with intelligent auto-completion, enhanced
# Git workflows, and productivity-focused tools.
#
# Repository: https://github.com/Syntax-Read3r/powerflow
# Documentation: See README.md for complete feature list and usage examples
# Version: 1.0.4
# Release Date: 13-07-2025
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Script version and repository
INSTALL_VERSION="1.0.4"
POWERFLOW_REPO="Syntax-Read3r/powerflow"

# Installation directories
FISH_CONFIG_DIR="$HOME/.config/fish"
FISH_COMPLETIONS_DIR="$FISH_CONFIG_DIR/completions"
FISH_FUNCTIONS_DIR="$FISH_CONFIG_DIR/functions"

echo -e "${CYAN}=  PowerFlow Fish Shell Installation${NC}"
echo -e "${CYAN}=====================================${NC}"
echo -e "${GRAY}Version: $INSTALL_VERSION${NC}"
echo -e "${GRAY}Target: Fish Shell for WSL Ubuntu${NC}"
echo ""

# Check if running on WSL
if ! grep -q microsoft /proc/version 2>/dev/null; then
    echo -e "${YELLOW}   Warning: This script is optimized for WSL Ubuntu${NC}"
    echo -e "${GRAY}Some features may not work correctly on other systems.${NC}"
    echo ""
    read -p "$(echo -e "${YELLOW}Continue anyway? (y/n): ${NC}")" continue_anyway
    if [[ "$continue_anyway" != "y" && "$continue_anyway" != "Y" ]]; then
        echo -e "${RED}L Installation cancelled${NC}"
        exit 0
    fi
fi

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install package via apt
install_apt_package() {
    local package="$1"
    local description="$2"
    
    if ! command_exists "$package"; then
        echo -e "${BLUE}=æ Installing $description...${NC}"
        if sudo apt update >/dev/null 2>&1 && sudo apt install -y "$package" >/dev/null 2>&1; then
            echo -e "${GREEN}    $description installed successfully${NC}"
        else
            echo -e "${YELLOW}      Failed to install $description via apt${NC}"
            return 1
        fi
    else
        echo -e "${GRAY}    $description already installed${NC}"
    fi
}

# Function to install Fish shell
install_fish_shell() {
    echo -e "${BOLD}=  Setting up Fish Shell${NC}"
    echo ""
    
    # Install Fish
    if ! command_exists fish; then
        echo -e "${BLUE}=æ Installing Fish shell...${NC}"
        sudo apt update >/dev/null 2>&1
        if sudo apt install -y fish >/dev/null 2>&1; then
            echo -e "${GREEN}    Fish shell installed successfully${NC}"
        else
            echo -e "${RED}   L Failed to install Fish shell${NC}"
            exit 1
        fi
    else
        echo -e "${GRAY}    Fish shell already installed${NC}"
    fi
    
    # Add Fish to valid shells
    if ! grep -q "/usr/bin/fish" /etc/shells 2>/dev/null; then
        echo -e "${BLUE}=' Adding Fish to valid shells...${NC}"
        echo "/usr/bin/fish" | sudo tee -a /etc/shells >/dev/null
        echo -e "${GREEN}    Fish added to /etc/shells${NC}"
    else
        echo -e "${GRAY}    Fish already in /etc/shells${NC}"
    fi
    
    echo ""
}

# Function to install dependencies
install_dependencies() {
    echo -e "${BOLD}=æ Installing PowerFlow Dependencies${NC}"
    echo ""
    
    # Essential tools
    install_apt_package "curl" "cURL"
    install_apt_package "wget" "Wget"
    install_apt_package "git" "Git"
    install_apt_package "jq" "jq (JSON processor)"
    install_apt_package "xclip" "xclip (clipboard utility)"
    
    # Enhanced tools
    echo -e "${BLUE}< Installing enhanced tools...${NC}"
    
    # Install Starship prompt
    if ! command_exists starship; then
        echo -e "${BLUE}   Installing Starship prompt...${NC}"
        if curl -sS https://starship.rs/install.sh | sh -s -- --yes >/dev/null 2>&1; then
            echo -e "${GREEN}    Starship installed successfully${NC}"
        else
            echo -e "${YELLOW}      Failed to install Starship${NC}"
        fi
    else
        echo -e "${GRAY}    Starship already installed${NC}"
    fi
    
    # Install zoxide (smart cd)
    if ! command_exists zoxide; then
        echo -e "${BLUE}   Installing zoxide (smart cd)...${NC}"
        if curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash >/dev/null 2>&1; then
            echo -e "${GREEN}    zoxide installed successfully${NC}"
        else
            echo -e "${YELLOW}      Failed to install zoxide${NC}"
        fi
    else
        echo -e "${GRAY}    zoxide already installed${NC}"
    fi
    
    # Install fzf (fuzzy finder)
    if ! command_exists fzf; then
        echo -e "${BLUE}   Installing fzf (fuzzy finder)...${NC}"
        if install_apt_package "fzf" "fzf"; then
            echo -e "${GREEN}    fzf installed successfully${NC}"
        fi
    else
        echo -e "${GRAY}    fzf already installed${NC}"
    fi
    
    # Install lsd (modern ls)
    if ! command_exists lsd; then
        echo -e "${BLUE}   Installing lsd (modern ls)...${NC}"
        # Try to install via apt first, fallback to manual installation
        if ! install_apt_package "lsd" "lsd"; then
            # Manual installation for older Ubuntu versions
            LSD_VERSION=$(curl -s "https://api.github.com/repos/Peltoche/lsd/releases/latest" | jq -r .tag_name 2>/dev/null || echo "v0.23.1")
            if curl -sL "https://github.com/Peltoche/lsd/releases/download/${LSD_VERSION}/lsd_${LSD_VERSION#v}_amd64.deb" -o /tmp/lsd.deb 2>/dev/null; then
                if sudo dpkg -i /tmp/lsd.deb >/dev/null 2>&1; then
                    echo -e "${GREEN}    lsd installed successfully${NC}"
                else
                    echo -e "${YELLOW}      Failed to install lsd${NC}"
                fi
                rm -f /tmp/lsd.deb
            fi
        fi
    else
        echo -e "${GRAY}    lsd already installed${NC}"
    fi
    
    echo ""
}

# Function to setup Fish configuration
setup_fish_config() {
    echo -e "${BOLD}=' Setting up Fish Configuration${NC}"
    echo ""
    
    # Create Fish config directories
    echo -e "${BLUE}=Á Creating Fish configuration directories...${NC}"
    mkdir -p "$FISH_CONFIG_DIR"
    mkdir -p "$FISH_COMPLETIONS_DIR"
    mkdir -p "$FISH_FUNCTIONS_DIR"
    echo -e "${GREEN}    Fish directories created${NC}"
    
    # Get the script directory (where this install.sh is located)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Copy PowerFlow Fish configuration
    if [ -f "$SCRIPT_DIR/config.fish" ]; then
        echo -e "${BLUE}=Ë Installing PowerFlow Fish configuration...${NC}"
        cp "$SCRIPT_DIR/config.fish" "$FISH_CONFIG_DIR/config.fish"
        echo -e "${GREEN}    config.fish installed${NC}"
    else
        echo -e "${RED}   L config.fish not found in $SCRIPT_DIR${NC}"
        exit 1
    fi
    
    # Copy navigation completions
    if [ -f "$SCRIPT_DIR/nav.fish" ]; then
        echo -e "${BLUE}=Ë Installing navigation completions...${NC}"
        cp "$SCRIPT_DIR/nav.fish" "$FISH_COMPLETIONS_DIR/nav.fish"
        echo -e "${GREEN}    nav.fish completions installed${NC}"
    else
        echo -e "${YELLOW}      nav.fish completions not found${NC}"
    fi
    
    # Set correct permissions
    chmod 644 "$FISH_CONFIG_DIR/config.fish"
    [ -f "$FISH_COMPLETIONS_DIR/nav.fish" ] && chmod 644 "$FISH_COMPLETIONS_DIR/nav.fish"
    
    echo ""
}

# Function to setup default shell
setup_default_shell() {
    echo -e "${BOLD}= Shell Configuration${NC}"
    echo ""
    
    # Check current shell
    current_shell=$(basename "$SHELL")
    echo -e "${GRAY}Current shell: $current_shell${NC}"
    
    if [ "$current_shell" != "fish" ]; then
        echo -e "${YELLOW}= Fish is not your default shell${NC}"
        echo ""
        echo -e "${BLUE}Options:${NC}"
        echo -e "${GRAY}1. Set Fish as default shell (recommended)${NC}"
        echo -e "${GRAY}2. Keep current shell, run Fish manually${NC}"
        echo -e "${GRAY}3. Skip shell configuration${NC}"
        echo ""
        
        read -p "$(echo -e "${CYAN}Choose option (1-3): ${NC}")" shell_option
        
        case $shell_option in
            1)
                echo -e "${BLUE}=' Setting Fish as default shell...${NC}"
                if chsh -s /usr/bin/fish 2>/dev/null; then
                    echo -e "${GREEN}    Fish set as default shell${NC}"
                    echo -e "${YELLOW}      Please log out and log back in for changes to take effect${NC}"
                else
                    echo -e "${RED}   L Failed to set Fish as default shell${NC}"
                    echo -e "${GRAY}   You may need to run: chsh -s /usr/bin/fish${NC}"
                fi
                ;;
            2)
                echo -e "${BLUE}=Ý To use PowerFlow Fish:${NC}"
                echo -e "${GRAY}   " Run: fish${NC}"
                echo -e "${GRAY}   " Or add to .bashrc: fish && exit${NC}"
                ;;
            3)
                echo -e "${GRAY}í  Shell configuration skipped${NC}"
                ;;
        esac
    else
        echo -e "${GREEN}    Fish is already your default shell${NC}"
    fi
    
    echo ""
}

# Function to create initial bookmarks
create_initial_bookmarks() {
    echo -e "${BOLD}=Ö Setting up Bookmarks${NC}"
    echo ""
    
    bookmarks_file="$HOME/.wsl_bookmarks.json"
    
    if [ ! -f "$bookmarks_file" ] && command_exists jq; then
        echo -e "${BLUE}=Ö Creating initial bookmarks...${NC}"
        cat > "$bookmarks_file" << EOF
{
  "code": "/mnt/c/Users/_munya/Code",
  "docs": "/mnt/c/Users/_munya/Documents",
  "home": "$HOME",
  "powerflow": "$(pwd)"
}
EOF
        echo -e "${GREEN}    Initial bookmarks created${NC}"
        echo -e "${GRAY}   " code ’ /mnt/c/Users/_munya/Code${NC}"
        echo -e "${GRAY}   " docs ’ /mnt/c/Users/_munya/Documents${NC}"
        echo -e "${GRAY}   " home ’ $HOME${NC}"
        echo -e "${GRAY}   " powerflow ’ $(pwd)${NC}"
    else
        echo -e "${GRAY}    Bookmarks already exist or jq not available${NC}"
    fi
    
    echo ""
}

# Function to test installation
test_installation() {
    echo -e "${BOLD}>ê Testing Installation${NC}"
    echo ""
    
    # Test Fish shell
    if command_exists fish; then
        echo -e "${GREEN}    Fish shell: Available${NC}"
        fish_version=$(fish --version 2>/dev/null | head -1)
        echo -e "${GRAY}      Version: $fish_version${NC}"
    else
        echo -e "${RED}   L Fish shell: Not found${NC}"
    fi
    
    # Test configuration file
    if [ -f "$FISH_CONFIG_DIR/config.fish" ]; then
        echo -e "${GREEN}    PowerFlow config: Installed${NC}"
    else
        echo -e "${RED}   L PowerFlow config: Missing${NC}"
    fi
    
    # Test completions
    if [ -f "$FISH_COMPLETIONS_DIR/nav.fish" ]; then
        echo -e "${GREEN}    Navigation completions: Installed${NC}"
    else
        echo -e "${YELLOW}      Navigation completions: Missing${NC}"
    fi
    
    # Test dependencies
    echo -e "${BLUE}   =æ Optional dependencies:${NC}"
    for tool in starship zoxide fzf lsd jq; do
        if command_exists "$tool"; then
            echo -e "${GREEN}       $tool${NC}"
        else
            echo -e "${GRAY}      L $tool (optional)${NC}"
        fi
    done
    
    echo ""
}

# Main installation flow
main() {
    echo -e "${YELLOW}=€ Starting PowerFlow Fish installation...${NC}"
    echo ""
    
    # Check for required permissions
    if ! sudo -n true 2>/dev/null; then
        echo -e "${YELLOW}= This script requires sudo access for package installation${NC}"
        echo -e "${GRAY}You may be prompted for your password.${NC}"
        echo ""
    fi
    
    # Installation steps
    install_fish_shell
    install_dependencies
    setup_fish_config
    create_initial_bookmarks
    setup_default_shell
    test_installation
    
    # Success message
    echo -e "${GREEN}<‰ PowerFlow Fish installation completed successfully!${NC}"
    echo ""
    echo -e "${BLUE}=Ë Next Steps:${NC}"
    echo -e "${GRAY}   1. Start Fish shell: ${CYAN}fish${NC}"
    echo -e "${GRAY}   2. Or restart your terminal${NC}"
    echo -e "${GRAY}   3. Run: ${CYAN}help${NC} to see available commands${NC}"
    echo -e "${GRAY}   4. Try: ${CYAN}nav b code${NC} to navigate to your code directory${NC}"
    echo ""
    echo -e "${BLUE}=  PowerFlow Fish Features:${NC}"
    echo -e "${GRAY}   " Intelligent auto-completion${NC}"
    echo -e "${GRAY}   " Enhanced Git workflows${NC}"
    echo -e "${GRAY}   " Smart navigation with bookmarks${NC}"
    echo -e "${GRAY}   " Claude Code integration${NC}"
    echo -e "${GRAY}   " Beautiful, informative prompts${NC}"
    echo ""
    echo -e "${CYAN}=O Thank you for using PowerFlow!${NC}"
    echo -e "${GRAY}Repository: https://github.com/$POWERFLOW_REPO${NC}"
    echo ""
    
    # Optional: Start Fish immediately
    read -p "$(echo -e "${YELLOW}Start Fish shell now? (y/n): ${NC}")" start_fish
    if [[ "$start_fish" == "y" || "$start_fish" == "Y" ]]; then
        echo -e "${BLUE}=  Starting Fish shell...${NC}"
        exec fish
    fi
}

# Run main installation
main "$@"