# Install Fish if not already installed
sudo apt update && sudo apt install -y fish

# Add Fish to valid shells
echo /usr/bin/fish | sudo tee -a /etc/shells

# Set Fish as your default shell
chsh -s /usr/bin/fish

# Start Fish immediately (or restart terminal)
fish