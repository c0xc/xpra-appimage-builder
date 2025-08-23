#!/bin/bash
set -e

# fetch_src.sh: Fetch or extract the Xpra source code into the build workspace

# Workspace, build directories
BASE_DIR="/workspace"
SRC_DIR="$BASE_DIR/src"
REPO_URL="https://github.com/Xpra-org/xpra.git"
REPO_BRANCH="${REPO_BRANCH:-master}"
cd "$BASE_DIR"
mkdir -p "$SRC_DIR"

# Prefer zip archive if present, else tar, else clone
echo "[fetch_src] Looking for archives in $(pwd):"
ls -l
if ls xpra-*.zip 1>/dev/null 2>&1; then
    archive=$(ls xpra-*.zip | head -n1)
    echo "[fetch_src] Extracting $archive to $SRC_DIR"
    unzip "$archive" -d "$SRC_DIR"
    # Flatten if only one top-level dir
    subdirs=("$SRC_DIR"/*)
    if [ ${#subdirs[@]} -eq 1 ] && [ -d "${subdirs[0]}" ]; then
        echo "[fetch_src] Flattening single top-level directory: ${subdirs[0]}"
        shopt -s dotglob
        mv "${subdirs[0]}"/* "$SRC_DIR"/
        rmdir "${subdirs[0]}"
        shopt -u dotglob
    fi
elif ls xpra-*.tar.* 1>/dev/null 2>&1; then
    archive=$(ls xpra-*.tar.* | head -n1)
    echo "[fetch_src] Extracting $archive to $SRC_DIR"
    tar xf "$archive" -C "$SRC_DIR" --strip-components=1 || {
        # If --strip-components=1 fails, try without it and flatten manually
        echo "[fetch_src] Retrying extraction without --strip-components=1"
        tar xf "$archive" -C "$SRC_DIR"
        subdirs=("$SRC_DIR"/*)
        if [ ${#subdirs[@]} -eq 1 ] && [ -d "${subdirs[0]}" ]; then
            echo "[fetch_src] Flattening single top-level directory: ${subdirs[0]}"
            shopt -s dotglob
            mv "${subdirs[0]}"/* "$SRC_DIR"/
            rmdir "${subdirs[0]}"
            shopt -u dotglob
        fi
    }

elif [ -n "${REPO_COMMIT:-}" ]; then
    echo "[fetch_src] Cloning $REPO_URL to $SRC_DIR for commit $REPO_COMMIT"
    git clone "$REPO_URL" "$SRC_DIR"
    pushd "$SRC_DIR"
    git checkout "$REPO_COMMIT"
    popd
else
    echo "[fetch_src] Cloning $REPO_URL branch $REPO_BRANCH to $SRC_DIR"
    git clone --branch "$REPO_BRANCH" --depth 1 "$REPO_URL" "$SRC_DIR"
fi

# List top-level files in the checked out/extracted repo for debugging
ls_output=$(ls -1p "$SRC_DIR" | awk '{ printf("    %s\n", $0) }')
echo "[fetch_src] --- Top-level files in source directory: $SRC_DIR ---"
echo "$ls_output"
echo "[fetch_src] --------------------------------------------------------"
