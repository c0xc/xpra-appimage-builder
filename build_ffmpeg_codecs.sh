#!/bin/bash
set -e

# build_ffmpeg_codecs.sh: Build and install ffmpeg (and codecs) from source as builder user

PREFIX="$HOME/.local"
NCORES=$(nproc || echo 2)

# Ensure install dirs exist
mkdir -p "$PREFIX"

# Optionally build and install codecs first (example: x264)
cd /tmp
if [ ! -d x264 ]; then
    git clone --depth 1 https://code.videolan.org/videolan/x264.git
fi
cd x264
./configure --prefix="$PREFIX" --enable-shared --disable-cli
make -j$NCORES
make install

# Build ffmpeg
cd /tmp
FFMPEG_VERSION=6.1.1
if [ ! -d ffmpeg-$FFMPEG_VERSION ]; then
    wget https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz
    tar xf ffmpeg-$FFMPEG_VERSION.tar.xz
fi
cd ffmpeg-$FFMPEG_VERSION

PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH" \
./configure --prefix="$PREFIX" --enable-shared --enable-gpl --enable-libx264
make -j$NCORES
make install

# Add to environment for subsequent build steps
export PATH="$PREFIX/bin:$PATH"
export LD_LIBRARY_PATH="$PREFIX/lib:$LD_LIBRARY_PATH"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH"

echo "[build_ffmpeg_codecs] ffmpeg and codecs installed to $PREFIX"
echo "[build_ffmpeg_codecs] Add the following to your environment for subsequent builds:"
echo "  export PATH=\"$PREFIX/bin:$PATH\""
echo "  export LD_LIBRARY_PATH=\"$PREFIX/lib:$LD_LIBRARY_PATH\""
echo "  export PKG_CONFIG_PATH=\"$PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH\""
