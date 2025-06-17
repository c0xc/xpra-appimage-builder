#!/bin/bash
set -e

# check_xpra.sh: Test the built xpra binary and check codecs

# This should run in activated virtualenv, initialized by container_init.sh
if [ -z "$VIRTUAL_ENV" ]; then
  echo "[check_xpra] ERROR: This script must be run in an activated virtual environment."
  echo "[check_xpra] Please source container_init.sh first to set up the environment."
  exit 1
fi

# Workspace, build directories
BASE_DIR="/workspace"
SRC_DIR="$BASE_DIR/src"
APPIMAGE_DIR="$BASE_DIR/appimage"
BUILD_DIR="$BASE_DIR/build"

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
