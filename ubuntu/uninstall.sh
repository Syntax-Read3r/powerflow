#!/bin/bash

# PowerFlow Ubuntu Uninstallation Script
# Removes PowerFlow enhanced bash profile and optionally cleans up dependencies

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Script version
UNINSTALL_VERSION="1.0.4"

echo -e "${CYAN}🗑️  PowerFlow Ubuntu Uninstall${NC}"
echo -e "${CYAN}====================================${NC}"
echo -e "${GRAY}Version: $UNINSTALL_VERSION${NC}"
echo ""

# Check if .bashrc exists
if [ ! -f "$HOME/.bashrc" ]; then
    echo -e "${YELLOW}ℹ️  No .bashrc file found at: $HOME/.bashrc${NC}"
    echo -e "${GRAY}Nothing to uninstall.${NC}"
    exit 0
fi

# Check if it's PowerFlow .bashrc
if ! grep -q "PowerFlow\|WSL.*Profile\|Enhanced.*Profile" "$HOME/.bashrc" 2>/dev/null; then
    echo -e "${YELLOW}ℹ️  .bashrc doesn't appear to be PowerFlow enhanced${NC}"
    echo -e "${GRAY}Current .bashrc may be a standard bash profile.${NC}"
    echo ""
    read -p "$(echo -e "${YELLOW}Remove anyway? (y/n): ${NC}")" continue_anyway
    if [[ "$continue_anyway" != "y" && "$continue_anyway" != "Y" ]]; then
        echo -e "${RED}❌ Uninstall cancelled${NC}"
        exit 0
    fi
fi

echo -e "${BLUE}📋 PowerFlow Uninstall Options:${NC}"
echo ""
echo -e "${GRAY}1. Remove PowerFlow .bashrc only (keep dependencies)${NC}"
echo -e "${GRAY}2. Remove PowerFlow + optional dependencies${NC}"
echo -e "${GRAY}3. Remove PowerFlow + all dependencies (complete cleanup)${NC}"
echo -e "${GRAY}4. Cancel uninstall${NC}"
echo ""

while true; do
    read -p "$(echo -e "${CYAN}Choose option (1-4): ${NC}")" option
    case $option in
        1)
            REMOVE_OPTIONAL=false
            REMOVE_ALL=false
            break
            ;;
        2)
            REMOVE_OPTIONAL=true
            REMOVE_ALL=false
            break
            ;;
        3)
            REMOVE_OPTIONAL=true
            REMOVE_ALL=true
            break
            ;;
        4)
            echo -e "${RED}❌ Uninstall cancelled${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option. Please choose 1-4.${NC}"
            ;;
    esac
done

echo ""
echo -e "${YELLOW}🔄 Starting PowerFlow uninstall...${NC}"

# Create backup before removal
backup_file="$HOME/.bashrc.backup.$(date +%Y%m%d_%H%M%S)"
echo -e "${BLUE}💾 Creating backup: $backup_file${NC}"
cp "$HOME/.bashrc" "$backup_file" 2>/dev/null || {
    echo -e "${RED}❌ Failed to create backup${NC}"
    exit 1
}

# Check if there's a previous .bashrc backup to restore
previous_backup=""
if [ -f "$HOME/.bashrc.backup" ]; then
    previous_backup="$HOME/.bashrc.backup"
elif find "$HOME" -maxdepth 1 -name ".bashrc.backup.*" -type f 2>/dev/null | head -1 | read -r backup_found; then
    previous_backup="$backup_found"
fi

if [ -n "$previous_backup" ]; then
    echo ""
    echo -e "${YELLOW}📦 Found previous .bashrc backup: $previous_backup${NC}"
    read -p "$(echo -e "${CYAN}Restore previous backup instead of removing .bashrc? (y/n): ${NC}")" restore_backup
    
    if [[ "$restore_backup" == "y" || "$restore_backup" == "Y" ]]; then
        cp "$previous_backup" "$HOME/.bashrc"
        echo -e "${GREEN}✅ Restored previous .bashrc from backup${NC}"
    else
        # Remove .bashrc completely
        rm -f "$HOME/.bashrc"
        echo -e "${GREEN}✅ PowerFlow .bashrc removed${NC}"
    fi
else
    # Remove .bashrc completely
    rm -f "$HOME/.bashrc"
    echo -e "${GREEN}✅ PowerFlow .bashrc removed${NC}"
fi

# Clean up PowerFlow-specific files
echo -e "${BLUE}🧹 Cleaning up PowerFlow files...${NC}"

# Remove PowerFlow bookmarks and config files
[ -f "$HOME/.wsl_bookmarks.json" ] && rm -f "$HOME/.wsl_bookmarks.json" && echo -e "${GRAY}   • Removed bookmarks file${NC}"
[ -f "$HOME/.wsl_init_check" ] && rm -f "$HOME/.wsl_init_check" && echo -e "${GRAY}   • Removed init check file${NC}"
[ -f "$HOME/.wsl_profile_update_check" ] && rm -f "$HOME/.wsl_profile_update_check" && echo -e "${GRAY}   • Removed update check file${NC}"
[ -f "$HOME/.nav_history" ] && rm -f "$HOME/.nav_history" && echo -e "${GRAY}   • Removed navigation history${NC}"

# Remove temp files
rm -f /tmp/.powerflow_* 2>/dev/null && echo -e "${GRAY}   • Removed temporary files${NC}"

# Handle dependencies based on user choice
if [ "$REMOVE_OPTIONAL" = true ] || [ "$REMOVE_ALL" = true ]; then
    echo ""
    echo -e "${YELLOW}🔧 Removing PowerFlow dependencies...${NC}"
    
    # Define dependency lists
    if [ "$REMOVE_ALL" = true ]; then
        # All dependencies including system tools
        deps_to_remove=("starship" "zoxide" "lsd" "fzf" "jq")
        optional_deps=("curl" "wget" "git" "xclip")
    else
        # Only optional/PowerFlow-specific dependencies
        deps_to_remove=("starship" "zoxide" "lsd")
        optional_deps=()
    fi
    
    # Remove dependencies
    for dep in "${deps_to_remove[@]}"; do
        if command -v "$dep" >/dev/null 2>&1; then
            case "$dep" in
                "starship")
                    # Starship might be installed via curl script
                    if [ -f "$HOME/.local/bin/starship" ]; then
                        rm -f "$HOME/.local/bin/starship"
                        echo -e "${GRAY}   • Removed starship${NC}"
                    elif command -v apt >/dev/null 2>&1; then
                        sudo apt remove -y starship 2>/dev/null && echo -e "${GRAY}   • Removed starship via apt${NC}"
                    fi
                    ;;
                "zoxide")
                    # Zoxide might be installed via curl script
                    if [ -f "$HOME/.local/bin/zoxide" ]; then
                        rm -f "$HOME/.local/bin/zoxide"
                        echo -e "${GRAY}   • Removed zoxide${NC}"
                    elif command -v apt >/dev/null 2>&1; then
                        sudo apt remove -y zoxide 2>/dev/null && echo -e "${GRAY}   • Removed zoxide via apt${NC}"
                    fi
                    ;;
                "lsd")
                    # lsd might be installed via deb package
                    if command -v apt >/dev/null 2>&1; then
                        sudo apt remove -y lsd 2>/dev/null && echo -e "${GRAY}   • Removed lsd${NC}"
                    fi
                    ;;
                *)
                    # Standard apt packages
                    if command -v apt >/dev/null 2>&1; then
                        sudo apt remove -y "$dep" 2>/dev/null && echo -e "${GRAY}   • Removed $dep${NC}"
                    fi
                    ;;
            esac
        fi
    done
    
    # Handle optional dependencies with confirmation
    if [ ${#optional_deps[@]} -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}⚠️  The following tools may be used by other applications:${NC}"
        for dep in "${optional_deps[@]}"; do
            if command -v "$dep" >/dev/null 2>&1; then
                echo -e "${GRAY}   • $dep${NC}"
            fi
        done
        echo ""
        read -p "$(echo -e "${YELLOW}Remove these as well? (y/n): ${NC}")" remove_optional
        
        if [[ "$remove_optional" == "y" || "$remove_optional" == "Y" ]]; then
            for dep in "${optional_deps[@]}"; do
                if command -v "$dep" >/dev/null 2>&1 && command -v apt >/dev/null 2>&1; then
                    sudo apt remove -y "$dep" 2>/dev/null && echo -e "${GRAY}   • Removed $dep${NC}"
                fi
            done
        fi
    fi
    
    # Clean up package cache
    if command -v apt >/dev/null 2>&1; then
        echo -e "${BLUE}🧹 Cleaning package cache...${NC}"
        sudo apt autoremove -y >/dev/null 2>&1
        sudo apt autoclean >/dev/null 2>&1
        echo -e "${GRAY}   • Package cleanup completed${NC}"
    fi
fi

echo ""
echo -e "${GREEN}✅ PowerFlow uninstall completed successfully!${NC}"
echo ""
echo -e "${BLUE}📋 Summary:${NC}"
echo -e "${GRAY}   • PowerFlow .bashrc removed${NC}"
echo -e "${GRAY}   • Backup saved to: $backup_file${NC}"
echo -e "${GRAY}   • PowerFlow configuration files cleaned up${NC}"

if [ "$REMOVE_OPTIONAL" = true ] || [ "$REMOVE_ALL" = true ]; then
    echo -e "${GRAY}   • Dependencies removed based on selection${NC}"
fi

echo ""
echo -e "${CYAN}🔄 Next steps:${NC}"
echo -e "${GRAY}   • Restart your terminal or run: source ~/.bashrc${NC}"
echo -e "${GRAY}   • Your backup is available at: $backup_file${NC}"

if [ -n "$previous_backup" ] && [[ "$restore_backup" == "y" || "$restore_backup" == "Y" ]]; then
    echo -e "${GRAY}   • Previous .bashrc configuration has been restored${NC}"
fi

echo ""
echo -e "${BLUE}🙏 Thank you for trying PowerFlow!${NC}"
echo -e "${GRAY}   Repository: https://github.com/Syntax-Read3r/powerflow${NC}"

# Optional: Show system info after uninstall
echo ""
echo -e "${CYAN}📊 System Status After Uninstall:${NC}"
echo -e "${GRAY}   • Bash version: $(bash --version | head -1 | cut -d' ' -f4)${NC}"
echo -e "${GRAY}   • Current shell: $SHELL${NC}"

# Check if any PowerFlow traces remain
remaining_tools=()
for tool in starship zoxide lsd fzf jq; do
    if command -v "$tool" >/dev/null 2>&1; then
        remaining_tools+=("$tool")
    fi
done

if [ ${#remaining_tools[@]} -gt 0 ]; then
    echo -e "${GRAY}   • Remaining tools: ${remaining_tools[*]}${NC}"
fi

echo ""
echo -e "${GREEN}🎉 Uninstall process complete!${NC}"