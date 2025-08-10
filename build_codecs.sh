#!/bin/bash

# build_codecs.sh: Build and install VP9 (libvpx) and AV1 (libaom) codecs into $DEPS_PREFIX
# This script is intended for use when NO_GSTREAMER=1 and USE_BREW_HEADERS_LIBS=0

DEPS_PREFIX="${DEPS_PREFIX:-/opt/dep}"
JOBS=$(nproc)

# Build libvpx (VP8/VP9) only if not present
if ! pkg-config --exists vpx; then
    VPX_VERSION="1.13.0"
    echo "[build_codecs] Building libvpx $VPX_VERSION..."
    mkdir -p /tmp/vpx_build
    cd /tmp/vpx_build
    wget -q "https://github.com/webmproject/libvpx/archive/v${VPX_VERSION}.tar.gz" -O libvpx-${VPX_VERSION}.tar.gz
    tar xf libvpx-${VPX_VERSION}.tar.gz
    cd libvpx-${VPX_VERSION}
    ./configure --prefix="$DEPS_PREFIX" --disable-examples --disable-docs --enable-vp9 --enable-shared
    make -j$JOBS
    make install
else
    echo "[build_codecs] libvpx already present, skipping build."
fi

# Build libaom (AV1) only if not present
#   Compatibility with CMake < 3.5 has been removed from CMake.
if ! pkg-config --exists aom; then
    echo "[build_codecs] Building libaom from mozilla/aom..."
    mkdir -p /tmp/aom_build
    cd /tmp/aom_build
    git clone --depth 1 https://github.com/mozilla/aom.git libaom || { echo "[build_codecs] ERROR: Failed to clone mozilla/aom repo"; exit 1; }
    cd libaom
    mkdir -p build && cd build
    cmake -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" -DBUILD_SHARED_LIBS=1 -DENABLE_DOCS=0 .. || { echo "[build_codecs] ERROR: libaom cmake failed"; exit 1; }
    make -j$JOBS || { echo "[build_codecs] ERROR: libaom make failed"; exit 1; }
    make install || { echo "[build_codecs] ERROR: libaom make install failed"; exit 1; }
else
    echo "[build_codecs] libaom already present, skipping build."
fi

# Build libavif (AV1 image format) only if not present
if ! pkg-config --exists avif; then
    echo "[build_codecs] Building libavif from AOMediaCodec/libavif..."
    mkdir -p /tmp/avif_build
    cd /tmp/avif_build
    git clone --depth 1 https://github.com/AOMediaCodec/libavif.git libavif || { echo "[build_codecs] ERROR: Failed to clone libavif repo"; exit 1; }
    cd libavif
    mkdir -p build && cd build
    cmake -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" -DBUILD_SHARED_LIBS=1 -DAVIF_BUILD_APPS=0 -DAVIF_BUILD_TESTS=0 -DAVIF_BUILD_EXAMPLES=0 -DAVIF_LIBYUV=LOCAL .. || { echo "[build_codecs] ERROR: libavif cmake failed"; exit 1; }
    make -j$JOBS || { echo "[build_codecs] ERROR: libavif make failed"; exit 1; }
    make install || { echo "[build_codecs] ERROR: libavif make install failed"; exit 1; }
else
    echo "[build_codecs] libavif already present, skipping build."
fi

# Build opus (audio codec) only if not present
if ! pkg-config --exists opus; then
    OPUS_VERSION="1.4"
    echo "[build_codecs] Building opus $OPUS_VERSION..."
    mkdir -p /tmp/opus_build
    cd /tmp/opus_build
    wget -q "https://archive.mozilla.org/pub/opus/opus-${OPUS_VERSION}.tar.gz" -O opus-${OPUS_VERSION}.tar.gz || { echo "[build_codecs] ERROR: Failed to download opus"; exit 1; }
    tar xf opus-${OPUS_VERSION}.tar.gz || { echo "[build_codecs] ERROR: Failed to extract opus archive"; exit 1; }
    cd opus-${OPUS_VERSION}
    ./configure --prefix="$DEPS_PREFIX" --enable-shared --disable-static || { echo "[build_codecs] ERROR: opus configure failed"; exit 1; }
    make -j$JOBS || { echo "[build_codecs] ERROR: opus make failed"; exit 1; }
    make install || { echo "[build_codecs] ERROR: opus make install failed"; exit 1; }
else
    echo "[build_codecs] opus already present, skipping build."
fi

# Optionally build other codecs (add here as needed)

cd "${SRC_DIR:-$PWD}"
echo "[build_codecs] Done building VP9 and AV1 codecs into $DEPS_PREFIX."
