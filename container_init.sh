#!/bin/bash
# Global container initialization script - source this in all entrypoints
# Activate venv here

# Set up environment variables
export VENV_DIR="/opt/pyenv"

# Ensure $HOME/.local/bin is in PATH for all scripts and shells
export PATH="$HOME/.local/bin:$PATH:/tiefkuehlfach"

# Detect if we are in an interactive shell (for optional silent mode)
# SILENT_MODE suppresses output in non-interactive shells
if [[ $- != *i* ]]; then
    SILENT_MODE=true
else
    SILENT_MODE=false
fi

# Umask - allow group read/write permissions
umask 0002

# Optionally set up LinuxBrew if enabled (one-time, but safe to check each session)
if [ "${USE_LINUXBREW:-false}" = "true" ] && [ -x "/usr/local/bin/setup_linuxbrew.sh" ]; then
    $SILENT_MODE || echo "[init] Setting up LinuxBrew package manager..."
    /usr/local/bin/setup_linuxbrew.sh
    if [ -f "$HOME/.brew_profile" ]; then
        $SILENT_MODE || echo "[init] Sourcing LinuxBrew profile..."
        source "$HOME/.brew_profile"
    fi
elif [ -f "$HOME/.brew_profile" ]; then
    $SILENT_MODE || echo "[init] Sourcing LinuxBrew profile..."
    source "$HOME/.brew_profile"
fi

# Ensure Python venv exists, create if missing
if [ ! -d "$VENV_DIR" ]; then
    $SILENT_MODE || echo "[init] Creating Python virtual environment at $VENV_DIR..."
    /usr/local/bin/build_env.sh
fi

# Always activate virtualenv for the current shell
if [ -d "$VENV_DIR" ] && [ -f "$VENV_DIR/bin/activate" ]; then
    $SILENT_MODE || echo "[init] Activating Python virtualenv at $VENV_DIR"
    source "$VENV_DIR/bin/activate"
    $SILENT_MODE || echo "[init] Python version: $(python --version)"
else
    $SILENT_MODE || echo "[init] WARNING: Python virtual environment not found at $VENV_DIR or activation script missing"
    $SILENT_MODE || echo "[init] Current system Python: $(which python3 2>/dev/null || echo 'not found')"
fi

