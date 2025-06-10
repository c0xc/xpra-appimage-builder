#!/bin/bash
set -e

# build_prereqs.sh: Install Python and system prerequisites for Xpra build

# Install basic Python dependencies (redundant if already done, but safe)
echo "[build_prereqs] Installing base Python dependencies..."
pip install --upgrade pip setuptools wheel

# Workspace, build directories
BASE_DIR="/workspace/xpra"
cd "$BASE_DIR" || { echo "[build_prereqs] ERROR: Base directory $BASE_DIR does not exist."; exit 1; }
SRC_DIR="$BASE_DIR/src"
if [ -d "$SRC_DIR" ]; then
    pushd "$SRC_DIR"
else
    echo "[build_prereqs] ERROR: Source directory $SRC_DIR does not exist. Run fetch_src.sh first."
    exit 1
fi

# Install Python dependencies for Xpra
if [ -f pyproject.toml ]; then
    echo "[build_prereqs] Installing dependencies from pyproject.toml using uv..."
    uv pip install -r <(uv pip compile pyproject.toml)
else
    if [ -f requirements.txt ]; then
        echo "[build_prereqs] Installing dependencies from requirements.txt..."
        pip install -r requirements.txt
    else
        echo "[build_prereqs] No pyproject.toml or requirements.txt found, skipping Python dependency installation."
    fi
fi

popd

echo "[build_prereqs] Done."
