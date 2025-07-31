#!/bin/bash
# PowerFlow Essential Tools - One-liner installer
# Copy and paste this entire script into your terminal

echo "⚡ Installing PowerFlow Essential Tools..."

# Update system
sudo apt update -qq

# Install essential tools
sudo apt install -y git curl wget jq xclip tree

# Install fzf (fuzzy finder)
if ! command -v fzf >/dev/null 2>&1; then
    if ! sudo apt install -y fzf 2>/dev/null; then
        echo "📦 Installing fzf from git..."
        git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
        ~/.fzf/install --all --no-bash --no-fish
    fi
fi

# Install zoxide (smart cd)
if ! command -v zoxide >/dev/null 2>&1; then
    echo "📦 Installing zoxide..."
    curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
fi

# Install lsd (modern ls)
if ! command -v lsd >/dev/null 2>&1; then
    if ! sudo apt install -y lsd 2>/dev/null; then
        echo "📦 Installing lsd from GitHub..."
        LSD_VERSION=$(curl -s "https://api.github.com/repos/Peltoche/lsd/releases/latest" | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4 || echo "v0.23.1")
        curl -sL "https://github.com/Peltoche/lsd/releases/download/${LSD_VERSION}/lsd_${LSD_VERSION#v}_amd64.deb" -o /tmp/lsd.deb
        sudo dpkg -i /tmp/lsd.deb
        rm -f /tmp/lsd.deb
    fi
fi

# Install ripgrep (better grep)
if ! command -v rg >/dev/null 2>&1; then
    if ! sudo apt install -y ripgrep 2>/dev/null; then
        echo "📦 Installing ripgrep from GitHub..."
        curl -sL "https://github.com/BurntSushi/ripgrep/releases/download/13.0.0/ripgrep_13.0.0_amd64.deb" -o /tmp/ripgrep.deb
        sudo dpkg -i /tmp/ripgrep.deb
        rm -f /tmp/ripgrep.deb
    fi
fi

echo "✅ PowerFlow essential tools installed!"
echo "🔄 Restart your terminal or run: source ~/.zshrc"