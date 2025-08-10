#!/bin/bash
set -e

# build_prereqs.sh: Install Python and system prerequisites for Xpra build
# Here, we install or build missing dependencies,
# using the prepared Python environment.

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

# libxxhash
if ! pkg-config --exists xxhash; then
    echo "[build_prereqs] Building libxxhash from source into $DEPS_PREFIX..."
    XXHASH_VERSION="0.8.2"
    mkdir -p "/tmp/xxhash_build"
    cd "/tmp/xxhash_build"
    wget -q "https://github.com/Cyan4973/xxHash/archive/v$XXHASH_VERSION.tar.gz" -O xxhash-$XXHASH_VERSION.tar.gz
    tar xf xxhash-$XXHASH_VERSION.tar.gz
    cd xxHash-$XXHASH_VERSION
    make
    make PREFIX=$DEPS_PREFIX install
    cd "$SRC_DIR"
fi

# X11 dependencies
# TODO check compatibility
# Pulling those via Brew might introduce a dependency on a newer glibc (2.33+)
if [ "${USE_BREW_HEADERS_LIBS:-0}" = "1" ]; then
    echo "[build_prereqs] Installing X11 protocol headers and libraries via brew..."
    brew install libxres
    brew install xorgproto libx11 libxext libxrender libxfixes libxrandr libxinerama libxdamage libxcomposite libxkbfile libxdmcp
    brew install libxkbfile libxdmcp
else
    echo "[build_prereqs] USE_BREW_HEADERS_LIBS=0, skipping X11 headers installation via brew."
fi

# Multimedia codecs, ffmpeg
# These are too old or missing in CentOS 8 repos
# We pull them via Brew if USE_BREW_HEADERS_LIBS=1
# note that would introduce a dependency on a newer glibc (2.33+)
# By default we build GStreamer from source for compatibility
if [ "${USE_BREW_HEADERS_LIBS:-0}" = "1" ]; then
    echo "[build_prereqs] USE_BREW_HEADERS_LIBS=1, installing codecs via brew..."
    brew install ffmpeg libvpx webp
    brew install opus x264 #x265
    brew install gstreamer gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-libav
else
    if [ "$NO_GSTREAMER" = "1" ]; then
        echo "[build_prereqs] NO_GSTREAMER=1, skipping GStreamer build."
        /usr/local/bin/build_codecs.sh # experimental, build codecs only (unfinished)
    else
        echo "[build_prereqs] Building GStreamer from source"
        /usr/local/bin/build_gstreamer.sh
    fi
fi

echo "[build_prereqs] Done."
popd
