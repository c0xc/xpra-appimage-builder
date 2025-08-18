#!/bin/bash
# Global container initialization script - source this in all entrypoints
# Activate venv here

# Set up environment variables
export VENV_DIR="/opt/pyenv"
export DEPS_PREFIX="/opt/dep"
export PKG_CONFIG_PATH="$DEPS_PREFIX/lib/pkgconfig:$DEPS_PREFIX/lib64/pkgconfig:$PKG_CONFIG_PATH"
export LD_LIBRARY_PATH="$DEPS_PREFIX/lib:$DEPS_PREFIX/lib64:$LD_LIBRARY_PATH"
export GI_TYPELIB_PATH="$DEPS_PREFIX/lib/girepository-1.0:$DEPS_PREFIX/lib64/girepository-1.0:$GI_TYPELIB_PATH"
# /opt/python3/bin/python3-config needed for meson builds (gobject-introspection)
export PATH="$HOME/.local/bin:/opt/python3/bin:$PATH:/tiefkuehlfach"
# g-ir-scanner needs to be in PATH for gobject-introspection
export PATH="$DEPS_PREFIX/bin:$PATH"
# CFLAGS, CPPFLAGS, CXXFLAGS to include headers (also for Python build)
#export CFLAGS="-I${DEPS_PREFIX}/include $CFLAGS"
#export CPPFLAGS="-I${DEPS_PREFIX}/include $CPPFLAGS"
#export CXXFLAGS="-I${DEPS_PREFIX}/include $CXXFLAGS"

# Detect if we are in an interactive shell (for optional silent mode)
# SILENT_MODE suppresses output in non-interactive shells
if [[ $- != *i* ]]; then
    SILENT_MODE=true
else
    SILENT_MODE=false
fi

# Umask - allow group read/write permissions
umask 0002

# Linuxbrew
if [ -f "$HOME/.brew_profile" ]; then
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

