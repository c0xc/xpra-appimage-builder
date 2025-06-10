#!/bin/bash
# setup_linuxbrew.sh - Install and set up Homebrew/LinuxBrew for dependency management
set -e

echo "[setup_brew] Installing LinuxBrew package manager..."

# Configuration
BREW_DIR="$HOME/.linuxbrew"
BREW_REPO="https://github.com/Homebrew/brew"

# Check if we already have Homebrew installed
if [ -x "$BREW_DIR/bin/brew" ]; then
    echo "[setup_brew] LinuxBrew already installed at $BREW_DIR"
else
    echo "[setup_brew] Cloning LinuxBrew repository..."
    git clone --depth=1 $BREW_REPO $BREW_DIR

    # Update PATH in current session
    export PATH="$BREW_DIR/bin:$PATH"

    # Add to user profile for future sessions
    if [ ! -f "$HOME/.brew_profile" ]; then
        cat > "$HOME/.brew_profile" << EOF
# LinuxBrew environment setup
export HOMEBREW_PREFIX="$BREW_DIR"
export HOMEBREW_CELLAR="$BREW_DIR/Cellar"
export HOMEBREW_REPOSITORY="$BREW_DIR"
export PATH="$BREW_DIR/bin:$BREW_DIR/sbin:\$PATH"
export MANPATH="$BREW_DIR/share/man\${MANPATH+:}\$MANPATH"
export INFOPATH="$BREW_DIR/share/info:\${INFOPATH:-}"
export HOMEBREW_NO_ANALYTICS=1
EOF
    fi

    # Setup brew environment in profile if not already done
    if ! grep -q "HOMEBREW_PREFIX" "$HOME/.bashrc" 2>/dev/null; then
        echo "source ~/.brew_profile" >> "$HOME/.bashrc"
    fi

    echo "[setup_brew] LinuxBrew installation complete"
fi

# Source the brew environment
source "$HOME/.brew_profile" 2>/dev/null || true

# Update brew
#echo "[setup_brew] Updating brew..."
#brew update

# Install key dependencies via brew
echo "[setup_brew] Installing dependencies via brew..."
brew install xxhash
brew install lz4

# Install newer CMake version (slow)
if ! command -v cmake >/dev/null 2>&1; then
    echo "[setup_brew] Installing cmake..."
    brew install cmake
else
    echo "[setup_brew] CMake already installed, skipping..."
fi

# openssl@1.1 is deprecated and no longer supported upstream:
# As of October 2024, openssl@1.1 is no longer supported and has been disabled.
#brew install openssl@1.1

# Print installed versions
echo "[setup_brew] Installed package versions:"
brew list --versions xxhash
brew list --versions lz4
#brew list --versions openssl@1.1

echo "[setup_brew] Setting up library path for brew packages"
# Add brew libs to LD_LIBRARY_PATH if not already done
if ! grep -q "BREW_LD_PATH" "$HOME/.brew_profile" 2>/dev/null; then
    cat >> "$HOME/.brew_profile" << EOF
# Add brew libraries to library path
export BREW_LD_PATH="$BREW_DIR/lib"
export LD_LIBRARY_PATH="\$BREW_LD_PATH\${LD_LIBRARY_PATH:+:}\$LD_LIBRARY_PATH"
EOF
fi

echo "[setup_brew] LinuxBrew setup complete"
