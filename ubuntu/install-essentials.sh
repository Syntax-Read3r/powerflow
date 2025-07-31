#!/bin/bash

# ============================================================================
# PowerFlow Essential Tools Installation Script
# ============================================================================
# Installs the core tools needed for PowerFlow: fuzzy finder, zoxide, lsd, git
# This script ensures all essential PowerFlow dependencies are available
#
# Repository: https://github.com/Syntax-Read3r/powerflow
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

echo -e "${CYAN}⚡ PowerFlow Essential Tools Installation${NC}"
echo -e "${CYAN}===========================================${NC}"
echo -e "${GRAY}Installing: git, fzf, zoxide, lsd${NC}"
echo ""

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
        if sudo apt update -qq && sudo apt install -y "$package" >/dev/null 2>&1; then
            echo -e "${GREEN}✅ $description installed successfully${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠️  Failed to install $description via apt${NC}"
            return 1
        fi
    else
        echo -e "${GRAY}ℹ️  $description already installed${NC}"
        return 0
    fi
}

# Function to install via curl with confirmation
install_via_curl() {
    local name="$1"
    local description="$2"
    local install_command="$3"
    
    if ! command_exists "$name"; then
        echo -e "${BLUE}📦 Installing $description...${NC}"
        if eval "$install_command" >/dev/null 2>&1; then
            echo -e "${GREEN}✅ $description installed successfully${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠️  Failed to install $description${NC}"
            return 1
        fi
    else
        echo -e "${GRAY}ℹ️  $description already installed${NC}"
        return 0
    fi
}

# Update package list
echo -e "${BLUE}🔄 Updating package list...${NC}"
sudo apt update -qq

# Install Git (essential for PowerFlow)
echo -e "${BOLD}📋 Installing Git${NC}"
install_apt_package "git" "Git version control system"

# Install fzf (fuzzy finder)
echo -e "${BOLD}🔍 Installing Fuzzy Finder (fzf)${NC}"
if ! install_apt_package "fzf" "Fuzzy finder"; then
    echo -e "${BLUE}📦 Trying alternative fzf installation...${NC}"
    if git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf 2>/dev/null; then
        if ~/.fzf/install --all --no-bash --no-fish >/dev/null 2>&1; then
            echo -e "${GREEN}✅ fzf installed successfully via git${NC}"
        else
            echo -e "${YELLOW}⚠️  fzf installation failed${NC}"
        fi
    fi
fi

# Install zoxide (smart cd)
echo -e "${BOLD}🧭 Installing zoxide (smart navigation)${NC}"
install_via_curl "zoxide" "Smart directory navigation" "curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash"

# Install lsd (modern ls)
echo -e "${BOLD}📁 Installing lsd (modern ls)${NC}"
if ! install_apt_package "lsd" "Modern ls replacement"; then
    echo -e "${BLUE}📦 Trying manual lsd installation...${NC}"
    # Get latest release version
    LSD_VERSION=$(curl -s "https://api.github.com/repos/Peltoche/lsd/releases/latest" | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4 2>/dev/null || echo "v0.23.1")
    LSD_URL="https://github.com/Peltoche/lsd/releases/download/${LSD_VERSION}/lsd_${LSD_VERSION#v}_amd64.deb"
    
    if curl -sL "$LSD_URL" -o /tmp/lsd.deb 2>/dev/null; then
        if sudo dpkg -i /tmp/lsd.deb >/dev/null 2>&1; then
            echo -e "${GREEN}✅ lsd installed successfully${NC}"
        else
            echo -e "${YELLOW}⚠️  lsd installation failed${NC}"
        fi
        rm -f /tmp/lsd.deb
    else
        echo -e "${YELLOW}⚠️  Failed to download lsd${NC}"
    fi
fi

# Install additional useful tools
echo -e "${BOLD}🔧 Installing Additional Tools${NC}"
install_apt_package "jq" "JSON processor"
install_apt_package "curl" "HTTP client"
install_apt_package "wget" "HTTP downloader"
install_apt_package "tree" "Directory tree viewer"
install_apt_package "xclip" "Clipboard utility"

# Install ripgrep (better grep)
if ! install_apt_package "ripgrep" "Fast grep alternative"; then
    echo -e "${BLUE}📦 Trying alternative ripgrep installation...${NC}"
    RG_VERSION="13.0.0"
    RG_URL="https://github.com/BurntSushi/ripgrep/releases/download/${RG_VERSION}/ripgrep_${RG_VERSION}_amd64.deb"
    
    if curl -sL "$RG_URL" -o /tmp/ripgrep.deb 2>/dev/null; then
        if sudo dpkg -i /tmp/ripgrep.deb >/dev/null 2>&1; then
            echo -e "${GREEN}✅ ripgrep installed successfully${NC}"
        fi
        rm -f /tmp/ripgrep.deb
    fi
fi

# Test installation
echo ""
echo -e "${BOLD}🧪 Testing Installation${NC}"
echo -e "${CYAN}========================${NC}"

# Test each tool
tools=("git:Git" "fzf:Fuzzy finder" "zoxide:Smart navigation" "lsd:Modern ls")

all_installed=true
for tool_info in "${tools[@]}"; do
    tool_name="${tool_info%%:*}"
    tool_desc="${tool_info##*:}"
    
    if command_exists "$tool_name"; then
        echo -e "${GREEN}✅ $tool_desc ($tool_name)${NC}"
    else
        echo -e "${RED}❌ $tool_desc ($tool_name) - Missing${NC}"
        all_installed=false
    fi
done

# Additional tools check
echo -e "${GRAY}Additional tools:${NC}"
additional_tools=("jq:JSON processor" "curl:HTTP client" "tree:Directory tree" "xclip:Clipboard")

for tool_info in "${additional_tools[@]}"; do
    tool_name="${tool_info%%:*}"
    tool_desc="${tool_info##*:}"
    
    if command_exists "$tool_name"; then
        echo -e "${GREEN}✅ $tool_desc ($tool_name)${NC}"
    else
        echo -e "${YELLOW}⚠️  $tool_desc ($tool_name) - Optional${NC}"
    fi
done

echo ""
if $all_installed; then
    echo -e "${GREEN}🎉 All essential PowerFlow tools installed successfully!${NC}"
    echo ""
    echo -e "${BLUE}🚀 Next Steps:${NC}"
    echo -e "${GRAY}   1. Restart your terminal or run: source ~/.zshrc${NC}"
    echo -e "${GRAY}   2. Test fuzzy finder: Ctrl+R for command search${NC}"
    echo -e "${GRAY}   3. Test zoxide: z <directory> for smart navigation${NC}"
    echo -e "${GRAY}   4. Test lsd: ls for enhanced directory listing${NC}"
    echo ""
else
    echo -e "${YELLOW}⚠️  Some tools failed to install. PowerFlow will still work but with reduced functionality.${NC}"
    echo -e "${GRAY}You can manually install missing tools or run this script again.${NC}"
fi

echo -e "${CYAN}💙 PowerFlow Essential Tools Installation Complete!${NC}"
echo -e "${GRAY}Repository: https://github.com/Syntax-Read3r/powerflow${NC}"
echo ""