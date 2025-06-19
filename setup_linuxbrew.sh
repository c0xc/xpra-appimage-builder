#!/bin/bash
# setup_linuxbrew.sh - Install and set up Homebrew/LinuxBrew for other/newer dependencies
set -e

echo "[setup_brew] Installing LinuxBrew package manager..."

# Linuxbrew location
BREW_DIR="$HOME/.linuxbrew"
BREW_REPO="https://github.com/Homebrew/brew"
# Pick up system-wide Homebrew if already installed
GLOBAL_BREW_DIR="/home/linuxbrew/.linuxbrew"
GLOBAL_BREW="$GLOBAL_BREW_DIR/bin/brew"
if [ -x "$GLOBAL_BREW" ]; then
    # Found it, activate it
    echo "[setup_brew] System-wide Homebrew found at $GLOBAL_BREW, using it."
    export PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:$PATH"
    export HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
    export HOMEBREW_CELLAR="/home/linuxbrew/.linuxbrew/Cellar"
    export HOMEBREW_REPOSITORY="/home/linuxbrew/.linuxbrew"
    export HOMEBREW_NO_ANALYTICS=1
    export HOMEBREW_NO_AUTO_UPDATE=1
    export HOMEBREW_NO_ENV_HINTS=1
    # Optionally symlink to user bin for convenience
    mkdir -p "$HOME/.local/bin"
    #ln -sf "$GLOBAL_BREW" "$HOME/.local/bin/brew"
    ln -s "$GLOBAL_BREW_DIR" "$HOME/.linuxbrew" # for convenience
    exit 0
fi

# Check if we already have Homebrew installed
if [ -x "$BREW_DIR/bin/brew" ]; then
    echo "[setup_brew] Homebrew already installed, activating environment only (skipping installs)..."
    # Source the brew environment
    source "$HOME/.brew_profile" 2>/dev/null || true
    exit 0
fi

# Download
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
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_ENV_HINTS=1
export BREW_LD_PATH="$BREW_DIR/lib"
export LD_LIBRARY_PATH="\$BREW_LD_PATH\${LD_LIBRARY_PATH:+:}\$LD_LIBRARY_PATH"
EOF
fi

# Setup brew environment in profile if not already done
if ! grep -q "HOMEBREW_PREFIX" "$HOME/.bashrc" 2>/dev/null; then
    echo "source ~/.brew_profile" >> "$HOME/.bashrc"
fi

# Source the brew environment
source "$HOME/.brew_profile" 2>/dev/null || true

# After local install, also symlink to user bin for convenience
mkdir -p "$HOME/.local/bin"
ln -sf "$BREW_DIR/bin/brew" "$HOME/.local/bin/brew"

# Install build-time tools and libraries (prebuilt bottles)
echo "[setup_brew] Installing build-time tools and libraries via brew..."
brew install cmake
brew install llvm
brew install xxhash
brew install lz4
brew install gobject-introspection
brew install py3cairo
brew install pygobject3

# Install newer CMake if not already installed
if ! command -v cmake >/dev/null 2>&1; then
    echo "[setup_brew] Installing cmake..."
    brew install cmake
else
    echo "[setup_brew] CMake already installed, skipping..."
fi

# Install clang with LLVM
if ! command -v clang >/dev/null 2>&1; then
    echo "[setup_brew] Installing clang with LLVM..."
    brew install llvm
    # Add LLVM to PATH
    export PATH="/home/linuxbrew/.linuxbrew/opt/llvm/bin:$PATH"
    export LDFLAGS="-L/home/linuxbrew/.linuxbrew/opt/llvm/lib"
    export CPPFLAGS="-I/home/linuxbrew/.linuxbrew/opt/llvm/include"
fi

# Install gobject-introspection for meson build
# ../meson.build:31:9: ERROR: Dependency 'girepository-2.0' is required but not found.
# OS package gobject-introspection-devel too old or not working -> brew
if ! pkg-config --exists girepository-2.0; then
    echo "[setup_brew] Installing gobject-introspection..."
    brew install gobject-introspection
fi

# Install GTK3 development files
brew install gtk+3 # for gdk-3.0.pc (GTK3 development files)

# Print installed versions
echo "[setup_brew] Installed package versions:"
brew list --versions xxhash
brew list --versions lz4


echo "[setup_brew] LinuxBrew setup complete"
