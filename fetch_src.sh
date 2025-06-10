#!/bin/bash
set -e

# fetch_src.sh: Fetch or extract the Xpra source code into the build workspace

# Workspace, build directories
BASE_DIR="/workspace/xpra"
SRC_DIR="$BASE_DIR/src"
REPO_URL="https://github.com/Xpra-org/xpra.git"
REPO_BRANCH="${REPO_BRANCH:-master}"
cd "$BASE_DIR"
mkdir -p "$SRC_DIR"

# Check if we have an archive to extract
if ls xpra-*.zip xpra-*.tar.* 1>/dev/null 2>&1; then
    archive=$(ls xpra-*.zip xpra-*.tar.* | head -n1)
    echo "[fetch_src] Extracting $archive to $SRC_DIR"
    if [[ "$archive" == *.zip ]]; then
        unzip "$archive" -d "$SRC_DIR"
    else
        tar xf "$archive" -C "$SRC_DIR" --strip-components=1
    fi
else
    echo "[fetch_src] Cloning $REPO_URL branch $REPO_BRANCH to $SRC_DIR"
    git clone --branch "$REPO_BRANCH" --depth 1 "$REPO_URL" "$SRC_DIR"
fi

# List top-level files in the checked out/extracted repo for debugging
ls_output=$(ls -1p "$SRC_DIR" | awk '{ printf("    %s\n", $0) }')
echo "[fetch_src] --- Top-level files in source directory: $SRC_DIR ---"
echo "$ls_output"
echo "[fetch_src] --------------------------------------------------------"
