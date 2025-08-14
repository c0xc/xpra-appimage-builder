#!/bin/bash

# build_codecs.sh: Build and install VP9 (libvpx) and AV1 (libaom) codecs into $DEPS_PREFIX
# This script is intended for use when NO_GSTREAMER=1 and USE_BREW_HEADERS_LIBS=0

DEPS_PREFIX="${DEPS_PREFIX:-/opt/dep}"

JOBS=$(nproc)
BUILD_ROOT="/opt/build"
mkdir -p "$BUILD_ROOT"

# Build libvpx (VP8/VP9) only if not present
if ! pkg-config --exists vpx; then
    VPX_VERSION="1.13.0"
    echo "[build_codecs] Building libvpx $VPX_VERSION..."
    mkdir -p "$BUILD_ROOT/vpx"
    cd "$BUILD_ROOT/vpx"
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
if ! pkg-config --exists aom; then
    AOM_VERSION="3.9.0" # fails to build, linker error
    AOM_VERSION="3.12.1"
    echo "[build_codecs] Downloading and building libaom $AOM_VERSION..."
    mkdir -p "$BUILD_ROOT/aom"
    cd "$BUILD_ROOT/aom"
    wget -q "https://storage.googleapis.com/aom-releases/libaom-${AOM_VERSION}.tar.gz" -O libaom-${AOM_VERSION}.tar.gz || { echo "[build_codecs] ERROR: Failed to download libaom tarball"; exit 1; }
    tar xf libaom-${AOM_VERSION}.tar.gz || { echo "[build_codecs] ERROR: Failed to extract libaom tarball"; exit 1; }
    cd libaom-${AOM_VERSION}
    mkdir -p build && cd build
    cmake -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" -DBUILD_SHARED_LIBS=1 -DENABLE_DOCS=0 -DENABLE_EXAMPLES=0 .. || { echo "[build_codecs] ERROR: libaom cmake failed"; exit 1; }
    make -j$JOBS || { echo "[build_codecs] ERROR: libaom make failed"; exit 1; }
    make install || { echo "[build_codecs] ERROR: libaom make install failed"; exit 1; }
else
    echo "[build_codecs] libaom already present, skipping build."
fi

# Build libavif (AV1 image format) only if not present
if ! pkg-config --exists avif; then
    echo "[build_codecs] Building libavif from AOMediaCodec/libavif..."
    mkdir -p "$BUILD_ROOT/avif"
    cd "$BUILD_ROOT/avif"
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
    mkdir -p "$BUILD_ROOT/opus"
    cd "$BUILD_ROOT/opus"
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
