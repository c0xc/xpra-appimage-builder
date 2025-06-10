#!/bin/bash
set -e

# check_xpra.sh: Test the built xpra binary and check codecs

# Always source python version info
PYTHON_VERSION_FILE="/var/tmp/PYTHON_VERSION_INFO"
if [ -f "$PYTHON_VERSION_FILE" ]; then
  source "$PYTHON_VERSION_FILE"
fi

VENV_DIR="/pyenv"
WORKSPACE="${WORKSPACE:-/build}"
APPIMAGE_OUTPUT="$WORKSPACE/xpra-latest.AppImage"

# Activate virtualenv
if [ -d "$VENV_DIR" ] && [ -f "$VENV_DIR/bin/activate" ]; then
  echo "[check_xpra] Activating Python virtualenv at $VENV_DIR"
  source "$VENV_DIR/bin/activate"
  echo "[check_xpra] Using Python: $(which python) ($(python --version))"
else
  echo "[check_xpra] ERROR: Python virtual environment not found at $VENV_DIR or activation script missing"
  exit 1
fi

# Check if xpra is executable
if ! command -v xpra >/dev/null 2>&1; then
  echo "[check_xpra] ERROR: xpra is not in PATH."
  exit 1
fi

XPRA_BIN=$(command -v xpra)
echo "[check_xpra] xpra binary found at $XPRA_BIN"

# Check xpra version
xpra --version || { echo "[check_xpra] ERROR: xpra not working."; exit 1; }

# Check supported codecs
xpra codec-info || { echo "[check_xpra] WARNING: Could not list codecs."; }

# Check video support
xpra video || { echo "[check_xpra] WARNING: Could not check video support."; }

echo "[check_xpra] Xpra checks complete."
