#!/bin/bash
set -e

# build_prereqs.sh: Install Python and system prerequisites for Xpra build

# Install basic Python dependencies (redundant if already done, but safe)
echo "[build_prereqs] Installing base Python dependencies..."
pip install --upgrade pip setuptools wheel

# Workspace, build directories
BASE_DIR="/workspace"
cd "$BASE_DIR" || { echo "[build_prereqs] ERROR: Base directory $BASE_DIR does not exist."; exit 1; }
SRC_DIR="$BASE_DIR/src"
if [ -d "$SRC_DIR" ]; then
    pushd "$SRC_DIR"
else
    echo "[build_prereqs] ERROR: Source directory $SRC_DIR does not exist. Run fetch_src.sh first."
    exit 1
fi

# Install dependencies from pyproject.toml or requirements.txt
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

# Xpra dependencies for X11 via brew
echo "[build_prereqs] Installing X11 protocol headers and libraries via brew..."
brew install libxres
brew install xorgproto libx11 libxext libxrender libxfixes libxrandr libxinerama libxdamage libxcomposite libxkbfile libxdmcp

# Modern multimedia codecs and tools (for Xpra, video, audio, etc)
# These are too old or missing in CentOS 8 repos, so we use Homebrew.
echo "[setup_brew] Installing multimedia codecs and libraries via brew..."
brew install ffmpeg libvpx webp
brew install opus x264 #x265
brew install libxkbfile libxdmcp

# GStreamer and related audio/video dependencies
echo "[setup_brew] Installing GStreamer and audio/video dependencies via brew..."
brew install gstreamer gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-libav
brew install gobject-introspection pygobject3

popd

echo "[build_prereqs] Done."
