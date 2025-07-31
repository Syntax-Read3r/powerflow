#!/bin/bash

# ============================================================================
# PowerFlow zsh Shell Installation Script
# ============================================================================
# Installs and configures PowerFlow enhanced zsh profile for WSL Ubuntu.
# This script sets up zsh with Oh My Zsh, intelligent auto-completion, enhanced
# Git workflows, and productivity-focused tools.
#
# Repository: https://github.com/Syntax-Read3r/powerflow
# Documentation: See README.md for complete feature list and usage examples
# Version: 1.0.5
# Release Date: 15-07-2025
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
INSTALL_VERSION="1.0.5"
POWERFLOW_REPO="Syntax-Read3r/powerflow"

# Installation directories
ZSH_CONFIG_DIR="$HOME"
OH_MY_ZSH_DIR="$HOME/.oh-my-zsh"
ZSH_CUSTOM_DIR="$OH_MY_ZSH_DIR/custom"

echo -e "${CYAN}======================================${NC}"
echo -e "${CYAN}⚡ PowerFlow zsh Shell Installation${NC}"
echo -e "${CYAN}======================================${NC}"
echo -e "${GRAY}Version: $INSTALL_VERSION${NC}"
echo -e "${GRAY}Target: zsh with Oh My Zsh for WSL Ubuntu${NC}"
echo ""

# Check if running on WSL
if ! grep -q microsoft /proc/version 2>/dev/null; then
    echo -e "${YELLOW}⚠️  Warning: This script is optimized for WSL Ubuntu${NC}"
    echo -e "${GRAY}Some features may not work correctly on other systems.${NC}"
    echo ""
    read -p "$(echo -e "${YELLOW}Continue anyway? (y/n): ${NC}")" continue_anyway
    if [[ "$continue_anyway" != "y" && "$continue_anyway" != "Y" ]]; then
        echo -e "${RED}❌ Installation cancelled${NC}"
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
        echo -e "${BLUE}📦 Installing $description...${NC}"
        if sudo apt update >/dev/null 2>&1 && sudo apt install -y "$package" >/dev/null 2>&1; then
            echo -e "${GREEN}✅ $description installed successfully${NC}"
        else
            echo -e "${YELLOW}⚠️  Failed to install $description via apt${NC}"
            return 1
        fi
    else
        echo -e "${GRAY}ℹ️  $description already installed${NC}"
    fi
}

# Function to install zsh and Oh My Zsh
install_zsh_shell() {
    echo -e "${BOLD}⚡ Setting up zsh Shell${NC}"
    echo ""
    
    # Install zsh
    if ! command_exists zsh; then
        echo -e "${BLUE}📦 Installing zsh shell...${NC}"
        sudo apt update >/dev/null 2>&1
        if sudo apt install -y zsh >/dev/null 2>&1; then
            echo -e "${GREEN}✅ zsh shell installed successfully${NC}"
        else
            echo -e "${RED}❌ Failed to install zsh shell${NC}"
            exit 1
        fi
    else
        echo -e "${GRAY}ℹ️  zsh shell already installed${NC}"
    fi
    
    # Add zsh to valid shells
    if ! grep -q "/usr/bin/zsh" /etc/shells 2>/dev/null; then
        echo -e "${BLUE}📝 Adding zsh to valid shells...${NC}"
        echo "/usr/bin/zsh" | sudo tee -a /etc/shells >/dev/null
        echo -e "${GREEN}✅ zsh added to /etc/shells${NC}"
    else
        echo -e "${GRAY}ℹ️  zsh already in /etc/shells${NC}"
    fi
    
    # Install Oh My Zsh
    if [ ! -d "$OH_MY_ZSH_DIR" ]; then
        echo -e "${BLUE}📦 Installing Oh My Zsh...${NC}"
        if sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Oh My Zsh installed successfully${NC}"
        else
            echo -e "${RED}❌ Failed to install Oh My Zsh${NC}"
            exit 1
        fi
    else
        echo -e "${GRAY}ℹ️  Oh My Zsh already installed${NC}"
    fi
    
    # Install zsh plugins
    echo -e "${BLUE}📦 Installing zsh plugins...${NC}"
    
    # Auto-suggestions plugin
    if [ ! -d "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions" ]; then
        if git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions" >/dev/null 2>&1; then
            echo -e "${GREEN}✅ zsh-autosuggestions plugin installed${NC}"
        else
            echo -e "${YELLOW}⚠️  Failed to install zsh-autosuggestions plugin${NC}"
        fi
    else
        echo -e "${GRAY}ℹ️  zsh-autosuggestions already installed${NC}"
    fi
    
    # Syntax highlighting plugin
    if [ ! -d "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting" ]; then
        if git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting" >/dev/null 2>&1; then
            echo -e "${GREEN}✅ zsh-syntax-highlighting plugin installed${NC}"
        else
            echo -e "${YELLOW}⚠️  Failed to install zsh-syntax-highlighting plugin${NC}"
        fi
    else
        echo -e "${GRAY}ℹ️  zsh-syntax-highlighting already installed${NC}"
    fi
    
    echo ""
}

# Function to install with user confirmation
install_with_confirmation() {
    local package="$1"
    local description="$2"
    local install_command="$3"
    
    if ! command_exists "$package"; then
        echo -e "${BLUE}📦 $description ($package) is not installed${NC}"
        echo -n "$(echo -e "${CYAN}🤔 Install $package? (y/n): ${NC}")"
        read -r confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            echo -e "${BLUE}📦 Installing $package...${NC}"
            if eval "$install_command" >/dev/null 2>&1; then
                echo -e "${GREEN}✅ $package installed successfully${NC}"
                return 0
            else
                echo -e "${YELLOW}⚠️  Failed to install $package${NC}"
                return 1
            fi
        else
            echo -e "${GRAY}⏭️  Skipping $package installation${NC}"
            return 1
        fi
    else
        echo -e "${GRAY}ℹ️  $package already installed${NC}"
        return 0
    fi
}

# Enhanced dependency installer with comprehensive PowerFlow dependency management
install_dependencies() {
    echo -e "${BOLD}🔧 Installing PowerFlow Dependencies${NC}"
    echo -e "${GRAY}This will install essential tools and offer optional enhancements${NC}"
    echo ""
    
    # Essential tools (automatically installed)
    echo -e "${BLUE}📦 Installing essential tools...${NC}"
    
    # Core system dependencies
    install_apt_package "curl" "cURL HTTP client"
    install_apt_package "wget" "Wget HTTP client"
    install_apt_package "git" "Git version control"
    install_apt_package "jq" "JSON processor"
    install_apt_package "xclip" "X11 clipboard utility"
    
    # Development essentials
    install_apt_package "build-essential" "Build tools for development"
    install_apt_package "software-properties-common" "Common software properties"
    install_apt_package "apt-transport-https" "HTTPS transport for APT"
    install_apt_package "ca-certificates" "SSL certificates"
    install_apt_package "gnupg" "GNU Privacy Guard"
    install_apt_package "lsb-release" "Linux Standard Base"
    
    # Additional useful tools
    install_apt_package "tree" "Directory tree visualization"
    install_apt_package "htop" "Interactive process viewer"
    install_apt_package "neofetch" "System information tool"
    
    # Try to install ripgrep (better grep)
    if ! install_apt_package "ripgrep" "Fast grep alternative"; then
        echo -e "${BLUE}📦 Trying alternative ripgrep installation...${NC}"
        if curl -LO https://github.com/BurntSushi/ripgrep/releases/download/13.0.0/ripgrep_13.0.0_amd64.deb 2>/dev/null; then
            if sudo dpkg -i ripgrep_13.0.0_amd64.deb >/dev/null 2>&1; then
                echo -e "${GREEN}✅ ripgrep installed successfully${NC}"
            fi
            rm -f ripgrep_13.0.0_amd64.deb
        fi
    fi
    
    echo ""
    echo -e "${BLUE}🚀 Enhanced PowerFlow Tools${NC}"
    echo -e "${GRAY}These tools provide enhanced functionality and beautiful interfaces${NC}"
    echo ""
    
    # Install Starship prompt with confirmation
    install_with_confirmation "starship" "Cross-shell prompt" "curl -sS https://starship.rs/install.sh | sh -s -- --yes"
    
    # Install zoxide (smart cd) with confirmation
    install_with_confirmation "zoxide" "Smart directory navigation" "curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash"
    
    # Install fzf (fuzzy finder) with confirmation
    install_with_confirmation "fzf" "Fuzzy finder" "sudo apt update && sudo apt install -y fzf"
    
    # Install lsd (modern ls) with enhanced installation
    if ! command_exists lsd; then
        echo -e "${BLUE}📦 lsd (modern ls replacement) is not installed${NC}"
        echo -n "$(echo -e "${CYAN}🤔 Install lsd? (y/n): ${NC}")"
        read -r confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            echo -e "${BLUE}📦 Installing lsd...${NC}"
            # Try apt first, then manual installation
            if ! install_apt_package "lsd" "lsd"; then
                echo -e "${BLUE}📦 Trying manual installation for lsd...${NC}"
                # Manual installation for older Ubuntu versions
                LSD_VERSION=$(curl -s "https://api.github.com/repos/Peltoche/lsd/releases/latest" | jq -r .tag_name 2>/dev/null || echo "v0.23.1")
                if curl -sL "https://github.com/Peltoche/lsd/releases/download/${LSD_VERSION}/lsd_${LSD_VERSION#v}_amd64.deb" -o /tmp/lsd.deb 2>/dev/null; then
                    if sudo dpkg -i /tmp/lsd.deb >/dev/null 2>&1; then
                        echo -e "${GREEN}✅ lsd installed successfully${NC}"
                    else
                        echo -e "${YELLOW}⚠️  Failed to install lsd${NC}"
                    fi
                    rm -f /tmp/lsd.deb
                else
                    echo -e "${YELLOW}⚠️  Failed to download lsd${NC}"
                fi
            fi
        else
            echo -e "${GRAY}⏭️  Skipping lsd installation${NC}"
        fi
    else
        echo -e "${GRAY}ℹ️  lsd already installed${NC}"
    fi
    
    # Install bat (better cat) with confirmation
    install_with_confirmation "bat" "Syntax highlighting cat" "sudo apt update && sudo apt install -y bat"
    
    # Install exa (another modern ls) as fallback
    if ! command_exists lsd && ! command_exists exa; then
        install_with_confirmation "exa" "Modern ls replacement" "sudo apt update && sudo apt install -y exa"
    fi
    
    # Install fd (better find) with confirmation
    install_with_confirmation "fd" "Fast find alternative" "sudo apt update && sudo apt install -y fd-find"
    
    echo ""
    echo -e "${BLUE}🎨 Development Tools${NC}"
    echo -e "${GRAY}Optional tools for enhanced development experience${NC}"
    echo ""
    
    # Node.js development tools
    if command_exists node; then
        echo -e "${GRAY}ℹ️  Node.js detected${NC}"
        install_with_confirmation "yarn" "Fast package manager" "sudo npm install -g yarn"
    fi
    
    # Python development tools
    if command_exists python3; then
        echo -e "${GRAY}ℹ️  Python 3 detected${NC}"
        install_with_confirmation "pip" "Python package manager" "sudo apt update && sudo apt install -y python3-pip"
    fi
    
    echo ""
}

# Function to setup zsh configuration
setup_zsh_config() {
    echo -e "${BOLD}📝 Setting up zsh Configuration${NC}"
    echo ""
    
    # Get the script directory (where this install.sh is located)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Backup existing .zshrc if it exists
    if [ -f "$HOME/.zshrc" ]; then
        echo -e "${BLUE}📦 Backing up existing .zshrc...${NC}"
        cp "$HOME/.zshrc" "$HOME/.zshrc.backup.$(date +%Y%m%d-%H%M%S)"
        echo -e "${GREEN}✅ Backup created${NC}"
    fi
    
    # Copy PowerFlow zsh configuration
    if [ -f "$SCRIPT_DIR/.zshrc" ]; then
        echo -e "${BLUE}📦 Installing PowerFlow zsh configuration...${NC}"
        cp "$SCRIPT_DIR/.zshrc" "$HOME/.zshrc"
        echo -e "${GREEN}✅ .zshrc installed${NC}"
    else
        echo -e "${RED}❌ .zshrc not found in $SCRIPT_DIR${NC}"
        exit 1
    fi
    
    # Set correct permissions
    chmod 644 "$HOME/.zshrc"
    
    echo ""
}

# Function to setup default shell
setup_default_shell() {
    echo -e "${BOLD}🐚 Shell Configuration${NC}"
    echo ""
    
    # Check current shell
    current_shell=$(basename "$SHELL")
    echo -e "${GRAY}Current shell: $current_shell${NC}"
    
    if [ "$current_shell" != "zsh" ]; then
        echo -e "${YELLOW}⚠️  zsh is not your default shell${NC}"
        echo ""
        echo -e "${BLUE}Options:${NC}"
        echo -e "${GRAY}1. Set zsh as default shell (recommended)${NC}"
        echo -e "${GRAY}2. Keep current shell, run zsh manually${NC}"
        echo -e "${GRAY}3. Skip shell configuration${NC}"
        echo ""
        
        read -p "$(echo -e "${CYAN}Choose option (1-3): ${NC}")" shell_option
        
        case $shell_option in
            1)
                echo -e "${BLUE}📝 Setting zsh as default shell...${NC}"
                if chsh -s /usr/bin/zsh 2>/dev/null; then
                    echo -e "${GREEN}✅ zsh set as default shell${NC}"
                    echo -e "${YELLOW}⚠️  Please log out and log back in for changes to take effect${NC}"
                else
                    echo -e "${RED}❌ Failed to set zsh as default shell${NC}"
                    echo -e "${GRAY}ℹ️  You may need to run: chsh -s /usr/bin/zsh${NC}"
                fi
                ;;
            2)
                echo -e "${BLUE}💡 To use PowerFlow zsh:${NC}"
                echo -e "${GRAY}   ⚡ Run: zsh${NC}"
                echo -e "${GRAY}   📝 Or add to .bashrc: zsh && exit${NC}"
                ;;
            3)
                echo -e "${GRAY}⏭️  Shell configuration skipped${NC}"
                ;;
        esac
    else
        echo -e "${GREEN}✅ zsh is already your default shell${NC}"
    fi
    
    echo ""
}

# Function to create initial bookmarks
create_initial_bookmarks() {
    echo -e "${BOLD}📖 Setting up Bookmarks${NC}"
    echo ""
    
    bookmarks_file="$HOME/.wsl_bookmarks.json"
    
    if [ ! -f "$bookmarks_file" ] && command_exists jq; then
        echo -e "${BLUE}📦 Creating initial bookmarks...${NC}"
        cat > "$bookmarks_file" << EOF
{
  "code": "/mnt/c/Users/_munya/Code",
  "docs": "/mnt/c/Users/_munya/Documents",
  "home": "$HOME",
  "powerflow": "$(pwd)"
}
EOF
        echo -e "${GREEN}✅ Initial bookmarks created${NC}"
        echo -e "${GRAY}📁 code → /mnt/c/Users/_munya/Code${NC}"
        echo -e "${GRAY}📁 docs → /mnt/c/Users/_munya/Documents${NC}"
        echo -e "${GRAY}📁 home → $HOME${NC}"
        echo -e "${GRAY}📁 powerflow → $(pwd)${NC}"
    else
        echo -e "${GRAY}ℹ️  Bookmarks already exist or jq not available${NC}"
    fi
    
    echo ""
}

# Function to test installation
test_installation() {
    echo -e "${BOLD}🧪 Testing Installation${NC}"
    echo ""
    
    # Test zsh shell
    if command_exists zsh; then
        echo -e "${GREEN}✅ zsh shell: Available${NC}"
        zsh_version=$(zsh --version 2>/dev/null | head -1)
        echo -e "${GRAY}      Version: $zsh_version${NC}"
    else
        echo -e "${RED}❌ zsh shell: Not found${NC}"
    fi
    
    # Test Oh My Zsh
    if [ -d "$OH_MY_ZSH_DIR" ]; then
        echo -e "${GREEN}✅ Oh My Zsh: Installed${NC}"
    else
        echo -e "${RED}❌ Oh My Zsh: Missing${NC}"
    fi
    
    # Test configuration file
    if [ -f "$HOME/.zshrc" ]; then
        echo -e "${GREEN}✅ PowerFlow config: Installed${NC}"
    else
        echo -e "${RED}❌ PowerFlow config: Missing${NC}"
    fi
    
    # Test plugins
    if [ -d "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions" ]; then
        echo -e "${GREEN}✅ Auto-suggestions plugin: Installed${NC}"
    else
        echo -e "${YELLOW}⚠️  Auto-suggestions plugin: Missing${NC}"
    fi
    
    if [ -d "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting" ]; then
        echo -e "${GREEN}✅ Syntax highlighting plugin: Installed${NC}"
    else
        echo -e "${YELLOW}⚠️  Syntax highlighting plugin: Missing${NC}"
    fi
    
    # Test dependencies with enhanced information
    echo -e "${BLUE}🔧 PowerFlow Dependencies:${NC}"
    
    # Essential tools
    echo -e "${GRAY}Essential tools:${NC}"
    for tool in git curl wget jq xclip; do
        if command_exists "$tool"; then
            echo -e "${GREEN}✅ $tool${NC}"
        else
            echo -e "${RED}❌ $tool (required)${NC}"
        fi
    done
    
    # Enhanced tools
    echo -e "${GRAY}Enhanced tools:${NC}"
    for tool in starship zoxide fzf lsd exa bat; do
        if command_exists "$tool"; then
            echo -e "${GREEN}✅ $tool${NC}"
        else
            echo -e "${YELLOW}⚠️  $tool (optional)${NC}"
        fi
    done
    
    # Development tools
    echo -e "${GRAY}Development tools:${NC}"
    for tool in node npm yarn python3 pip; do
        if command_exists "$tool"; then
            echo -e "${GREEN}✅ $tool${NC}"
        else
            echo -e "${GRAY}ℹ️  $tool (development)${NC}"
        fi
    done
    
    echo ""
}

# Function to initialize PowerFlow dependency system
init_dependency_system() {
    echo -e "${BOLD}🔧 Initializing PowerFlow Dependency System${NC}"
    echo ""
    
    # Create dependency check file to enable daily checks
    local dep_check_file="$HOME/.wsl_dependency_check"
    echo "$(date +%Y-%m-%d)" > "$dep_check_file"
    
    # Test dependency initialization
    echo -e "${BLUE}🧪 Testing dependency initialization...${NC}"
    
    # Test starship initialization
    if command_exists starship; then
        echo -e "${GREEN}✅ Starship prompt: Available${NC}"
        echo -e "${GRAY}      Will be initialized in zsh profile${NC}"
    else
        echo -e "${YELLOW}⚠️  Starship prompt: Not available${NC}"
    fi
    
    # Test zoxide initialization
    if command_exists zoxide; then
        echo -e "${GREEN}✅ zoxide navigation: Available${NC}"
        echo -e "${GRAY}      Will replace 'cd' with smart navigation${NC}"
    else
        echo -e "${YELLOW}⚠️  zoxide navigation: Not available${NC}"
    fi
    
    # Test fzf initialization
    if command_exists fzf; then
        echo -e "${GREEN}✅ fzf fuzzy finder: Available${NC}"
        echo -e "${GRAY}      Will enable interactive Git workflows${NC}"
    else
        echo -e "${YELLOW}⚠️  fzf fuzzy finder: Not available${NC}"
    fi
    
    # Test lsd/exa initialization
    if command_exists lsd; then
        echo -e "${GREEN}✅ lsd (modern ls): Available${NC}"
        echo -e "${GRAY}      Will enhance directory listings${NC}"
    elif command_exists exa; then
        echo -e "${GREEN}✅ exa (modern ls): Available${NC}"
        echo -e "${GRAY}      Will enhance directory listings${NC}"
    else
        echo -e "${YELLOW}⚠️  Modern ls replacement: Not available${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}📊 Dependency System Status:${NC}"
    echo -e "${GRAY}   • Daily dependency checks: Enabled${NC}"
    echo -e "${GRAY}   • Automatic tool initialization: Enabled${NC}"
    echo -e "${GRAY}   • Smart fallbacks: Enabled${NC}"
    echo -e "${GRAY}   • Recovery system: Available${NC}"
    echo ""
}

# Enhanced installation with comprehensive setup
main() {
    echo -e "${YELLOW}🚀 Starting PowerFlow zsh installation...${NC}"
    echo -e "${GRAY}This will set up a comprehensive zsh environment with intelligent dependency management${NC}"
    echo ""
    
    # Check for required permissions
    if ! sudo -n true 2>/dev/null; then
        echo -e "${YELLOW}⚠️  This script requires sudo access for package installation${NC}"
        echo -e "${GRAY}You may be prompted for your password during installation.${NC}"
        echo ""
    fi
    
    # Pre-installation system check
    echo -e "${BLUE}🔍 System Check${NC}"
    echo -e "${GRAY}OS: $(lsb_release -d 2>/dev/null | cut -f2 || echo 'Unknown Linux')${NC}"
    echo -e "${GRAY}Architecture: $(uname -m)${NC}"
    echo -e "${GRAY}Shell: $SHELL${NC}"
    echo ""
    
    # Installation steps with enhanced dependency management
    install_zsh_shell
    install_dependencies
    setup_zsh_config
    create_initial_bookmarks
    init_dependency_system
    setup_default_shell
    test_installation
    
    # Success message with comprehensive feature overview
    echo -e "${GREEN}🎉 PowerFlow zsh installation completed successfully!${NC}"
    echo ""
    echo -e "${BLUE}🚀 Next Steps:${NC}"
    echo -e "${GRAY}   1. Start zsh shell: ${CYAN}zsh${NC}"
    echo -e "${GRAY}   2. Or restart your terminal${NC}"
    echo -e "${GRAY}   3. Run: ${CYAN}help${NC} to see available commands${NC}"
    echo -e "${GRAY}   4. Try: ${CYAN}nav b code${NC} to navigate to your code directory${NC}"
    echo -e "${GRAY}   5. Check dependencies: ${CYAN}deps${NC} or ${CYAN}check_powerflow_dependencies${NC}"
    echo ""
    echo -e "${BLUE}⚡ PowerFlow zsh Features:${NC}"
    echo -e "${GRAY}   🎯 Intelligent auto-completion with context awareness${NC}"
    echo -e "${GRAY}   🌈 Real-time syntax highlighting${NC}"
    echo -e "${GRAY}   💭 Smart auto-suggestions from history${NC}"
    echo -e "${GRAY}   🌳 Enhanced Git workflows with visual feedback${NC}"
    echo -e "${GRAY}   🧭 Smart navigation with bookmarks and fuzzy search${NC}"
    echo -e "${GRAY}   🤖 Claude Code integration for AI assistance${NC}"
    echo -e "${GRAY}   ✨ Beautiful, informative prompts with Starship${NC}"
    echo -e "${GRAY}   🔧 Automatic dependency management and recovery${NC}"
    echo -e "${GRAY}   🔍 Daily dependency checks and updates${NC}"
    echo ""
    echo -e "${CYAN}💙 Thank you for using PowerFlow!${NC}"
    echo -e "${GRAY}Repository: https://github.com/$POWERFLOW_REPO${NC}"
    echo ""
    
    # Show dependency management information
    echo -e "${BLUE}📊 Dependency Management:${NC}"
    echo -e "${GRAY}   • PowerFlow will check for missing tools daily${NC}"
    echo -e "${GRAY}   • Run ${CYAN}check_powerflow_dependencies${NC} to manually check${NC}"
    echo -e "${GRAY}   • Use ${CYAN}recovery${NC} command if you encounter issues${NC}"
    echo -e "${GRAY}   • Dependencies are installed with user confirmation${NC}"
    echo ""
    
    # Optional: Start zsh immediately
    read -p "$(echo -e "${YELLOW}Start zsh shell now? (y/n): ${NC}")" start_zsh
    if [[ "$start_zsh" == "y" || "$start_zsh" == "Y" ]]; then
        echo -e "${BLUE}⚡ Starting zsh shell with PowerFlow...${NC}"
        exec zsh
    fi
}

# Run main installation
main "$@"