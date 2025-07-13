#!/bin/bash

# ============================================================================
# PowerFlow Fish Shell Uninstallation Script
# ============================================================================
# Removes PowerFlow enhanced Fish profile and optionally cleans up dependencies.
# Supports both Fish shell and Bash configurations.
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

# Script version
UNINSTALL_VERSION="1.0.4"

echo -e "${CYAN}🗑️  PowerFlow Uninstallation${NC}"
echo -e "${CYAN}================================${NC}"
echo -e "${GRAY}Version: $UNINSTALL_VERSION${NC}"
echo -e "${GRAY}Target: Fish Shell & Bash profiles${NC}"
echo ""

# Detect what's installed
FISH_CONFIG_FILE="$HOME/.config/fish/config.fish"
BASH_CONFIG_FILE="$HOME/.bashrc"
HAS_FISH_CONFIG=false
HAS_BASH_CONFIG=false

# Check for Fish configuration
if [ -f "$FISH_CONFIG_FILE" ]; then
    if grep -q "PowerFlow\|Enhanced Fish Profile" "$FISH_CONFIG_FILE" 2>/dev/null; then
        HAS_FISH_CONFIG=true
        echo -e "${BLUE}🐠 Found PowerFlow Fish configuration${NC}"
    fi
fi

# Check for Bash configuration  
if [ -f "$BASH_CONFIG_FILE" ]; then
    if grep -q "PowerFlow\|WSL.*Profile\|Enhanced.*Profile" "$BASH_CONFIG_FILE" 2>/dev/null; then
        HAS_BASH_CONFIG=true
        echo -e "${BLUE}🐚 Found PowerFlow Bash configuration${NC}"
    fi
fi

# If nothing found
if [ "$HAS_FISH_CONFIG" = false ] && [ "$HAS_BASH_CONFIG" = false ]; then
    echo -e "${YELLOW}ℹ️  No PowerFlow configurations found${NC}"
    echo -e "${GRAY}Checking for any configuration files...${NC}"
    
    # Check for any config files
    if [ ! -f "$FISH_CONFIG_FILE" ] && [ ! -f "$BASH_CONFIG_FILE" ]; then
        echo -e "${GRAY}No configuration files found.${NC}"
        exit 0
    fi
    
    echo ""
    echo -e "${YELLOW}Found non-PowerFlow configuration files:${NC}"
    [ -f "$FISH_CONFIG_FILE" ] && echo -e "${GRAY}   • Fish: $FISH_CONFIG_FILE${NC}"
    [ -f "$BASH_CONFIG_FILE" ] && echo -e "${GRAY}   • Bash: $BASH_CONFIG_FILE${NC}"
    echo ""
    read -p "$(echo -e "${YELLOW}Remove these configurations anyway? (y/n): ${NC}")" continue_anyway
    if [[ "$continue_anyway" != "y" && "$continue_anyway" != "Y" ]]; then
        echo -e "${RED}❌ Uninstall cancelled${NC}"
        exit 0
    fi
    # Set flags to proceed with removal
    [ -f "$FISH_CONFIG_FILE" ] && HAS_FISH_CONFIG=true
    [ -f "$BASH_CONFIG_FILE" ] && HAS_BASH_CONFIG=true
fi

echo -e "${BLUE}📋 PowerFlow Uninstall Options:${NC}"
echo ""
echo -e "${GRAY}1. Remove PowerFlow configurations only (keep dependencies)${NC}"
echo -e "${GRAY}2. Remove PowerFlow + optional dependencies${NC}"
echo -e "${GRAY}3. Remove PowerFlow + all dependencies (complete cleanup)${NC}"
echo -e "${GRAY}4. Remove Fish shell completely${NC}"
echo -e "${GRAY}5. Cancel uninstall${NC}"
echo ""

while true; do
    read -p "$(echo -e "${CYAN}Choose option (1-5): ${NC}")" option
    case $option in
        1)
            REMOVE_OPTIONAL=false
            REMOVE_ALL=false
            REMOVE_FISH=false
            break
            ;;
        2)
            REMOVE_OPTIONAL=true
            REMOVE_ALL=false
            REMOVE_FISH=false
            break
            ;;
        3)
            REMOVE_OPTIONAL=true
            REMOVE_ALL=true
            REMOVE_FISH=false
            break
            ;;
        4)
            REMOVE_OPTIONAL=true
            REMOVE_ALL=true
            REMOVE_FISH=true
            break
            ;;
        5)
            echo -e "${RED}❌ Uninstall cancelled${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option. Please choose 1-5.${NC}"
            ;;
    esac
done

echo ""
echo -e "${YELLOW}🔄 Starting PowerFlow uninstall...${NC}"

# Function to create backup and remove configuration
remove_config_with_backup() {
    local config_file="$1"
    local config_type="$2"
    local backup_file="${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [ -f "$config_file" ]; then
        echo -e "${BLUE}💾 Creating $config_type backup: $backup_file${NC}"
        cp "$config_file" "$backup_file" 2>/dev/null || {
            echo -e "${RED}❌ Failed to create $config_type backup${NC}"
            return 1
        }
        
        # Check if there's a previous backup to restore
        local previous_backup=""
        local backup_base="${config_file}.backup"
        if [ -f "$backup_base" ]; then
            previous_backup="$backup_base"
        elif find "$(dirname "$config_file")" -maxdepth 1 -name "$(basename "$config_file").backup.*" -type f 2>/dev/null | head -1 | read -r backup_found; then
            previous_backup="$backup_found"
        fi
        
        if [ -n "$previous_backup" ]; then
            echo ""
            echo -e "${YELLOW}📦 Found previous $config_type backup: $previous_backup${NC}"
            read -p "$(echo -e "${CYAN}Restore previous backup instead of removing $config_type? (y/n): ${NC}")" restore_backup
            
            if [[ "$restore_backup" == "y" || "$restore_backup" == "Y" ]]; then
                cp "$previous_backup" "$config_file"
                echo -e "${GREEN}✅ Restored previous $config_type from backup${NC}"
            else
                # Remove config completely
                rm -f "$config_file"
                echo -e "${GREEN}✅ PowerFlow $config_type removed${NC}"
            fi
        else
            # Remove config completely
            rm -f "$config_file"
            echo -e "${GREEN}✅ PowerFlow $config_type removed${NC}"
        fi
    fi
}

# Remove Fish configuration if exists
if [ "$HAS_FISH_CONFIG" = true ]; then
    echo -e "${BLUE}🐠 Removing Fish configuration...${NC}"
    remove_config_with_backup "$FISH_CONFIG_FILE" "Fish config"
    
    # Remove Fish completions and functions
    if [ -d "$HOME/.config/fish/completions" ]; then
        echo -e "${BLUE}🧹 Removing Fish completions...${NC}"
        rm -f "$HOME/.config/fish/completions/nav.fish"
        echo -e "${GRAY}   • Removed nav.fish completions${NC}"
    fi
    
    if [ -d "$HOME/.config/fish/functions" ]; then
        echo -e "${BLUE}🧹 Cleaning Fish functions directory...${NC}"
        # Remove any PowerFlow-specific functions (if any were created)
        find "$HOME/.config/fish/functions" -name "*powerflow*" -type f -delete 2>/dev/null
    fi
fi

# Remove Bash configuration if exists
if [ "$HAS_BASH_CONFIG" = true ]; then
    echo -e "${BLUE}🐚 Removing Bash configuration...${NC}"
    remove_config_with_backup "$BASH_CONFIG_FILE" "Bash config"
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
    
    # Add Fish to removal list if requested
    if [ "$REMOVE_FISH" = true ]; then
        deps_to_remove=("fish" "${deps_to_remove[@]}")
        echo -e "${YELLOW}⚠️  Fish shell will be completely removed${NC}"
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

# Report what was removed
removed_configs=()
[ "$HAS_FISH_CONFIG" = true ] && removed_configs+=("Fish")
[ "$HAS_BASH_CONFIG" = true ] && removed_configs+=("Bash")

if [ ${#removed_configs[@]} -gt 0 ]; then
    echo -e "${GRAY}   • PowerFlow configurations removed: ${removed_configs[*]}${NC}"
fi

echo -e "${GRAY}   • PowerFlow configuration files cleaned up${NC}"

if [ "$REMOVE_OPTIONAL" = true ] || [ "$REMOVE_ALL" = true ]; then
    echo -e "${GRAY}   • Dependencies removed based on selection${NC}"
fi

if [ "$REMOVE_FISH" = true ]; then
    echo -e "${GRAY}   • Fish shell completely removed${NC}"
fi

echo ""
echo -e "${CYAN}🔄 Next steps:${NC}"

# Provide appropriate next steps based on what was removed
if [ "$REMOVE_FISH" = true ]; then
    echo -e "${GRAY}   • Fish shell has been removed${NC}"
    echo -e "${GRAY}   • Your default shell should revert to bash${NC}"
    echo -e "${GRAY}   • Restart your terminal or log out/in${NC}"
elif [ "$HAS_FISH_CONFIG" = true ]; then
    echo -e "${GRAY}   • Restart Fish shell or run: fish${NC}"
    echo -e "${GRAY}   • Fish shell is still installed (use 'which fish' to verify)${NC}"
fi

if [ "$HAS_BASH_CONFIG" = true ]; then
    echo -e "${GRAY}   • Restart your terminal or run: source ~/.bashrc${NC}"
fi

# Show backup locations
if [ "$HAS_FISH_CONFIG" = true ]; then
    echo -e "${GRAY}   • Fish config backup: ${FISH_CONFIG_FILE}.backup.$(date +%Y%m%d)_*${NC}"
fi
if [ "$HAS_BASH_CONFIG" = true ]; then
    echo -e "${GRAY}   • Bash config backup: ${BASH_CONFIG_FILE}.backup.$(date +%Y%m%d)_*${NC}"
fi

echo ""
echo -e "${BLUE}🙏 Thank you for trying PowerFlow!${NC}"
echo -e "${GRAY}   Repository: https://github.com/Syntax-Read3r/powerflow${NC}"

# Optional: Show system info after uninstall
echo ""
echo -e "${CYAN}📊 System Status After Uninstall:${NC}"

# Show shell information
if command -v bash >/dev/null 2>&1; then
    echo -e "${GRAY}   • Bash version: $(bash --version | head -1 | cut -d' ' -f4)${NC}"
fi

if command -v fish >/dev/null 2>&1; then
    echo -e "${GRAY}   • Fish version: $(fish --version)${NC}"
else
    echo -e "${GRAY}   • Fish: Not installed${NC}"
fi

echo -e "${GRAY}   • Current shell: $SHELL${NC}"

# Check if any PowerFlow traces remain
remaining_tools=()
for tool in starship zoxide lsd fzf jq fish; do
    if command -v "$tool" >/dev/null 2>&1; then
        remaining_tools+=("$tool")
    fi
done

if [ ${#remaining_tools[@]} -gt 0 ]; then
    echo -e "${GRAY}   • Remaining tools: ${remaining_tools[*]}${NC}"
else
    echo -e "${GRAY}   • All PowerFlow tools removed${NC}"
fi

# Check for remaining configuration files
remaining_configs=()
[ -f "$FISH_CONFIG_FILE" ] && remaining_configs+=("Fish")
[ -f "$BASH_CONFIG_FILE" ] && remaining_configs+=("Bash")

if [ ${#remaining_configs[@]} -gt 0 ]; then
    echo -e "${GRAY}   • Remaining configs: ${remaining_configs[*]}${NC}"
else
    echo -e "${GRAY}   • All configurations removed${NC}"
fi

echo ""
echo -e "${GREEN}🎉 PowerFlow uninstall process complete!${NC}"
echo ""
echo -e "${BLUE}💡 Tips for what's next:${NC}"
echo -e "${GRAY}   • You can reinstall PowerFlow anytime with: ./install.sh${NC}"
echo -e "${GRAY}   • Your backups are preserved for easy restoration${NC}"
echo -e "${GRAY}   • Consider using standard bash if you removed Fish${NC}"