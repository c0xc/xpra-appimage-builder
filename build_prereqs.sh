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

# Install dependencies from pyproject.toml
# Pin PyGObject version if already installed because rebuild after source build fails
PYGOBJECT_VERSION="$(pip show pygobject 2>/dev/null | awk '/^Version: /{print $2}')"
if [ -n "$PYGOBJECT_VERSION" ]; then
    echo "[build_prereqs] Detected PyGObject version $PYGOBJECT_VERSION, pinning in pyproject.toml..."
    sed -i "s/\"PyGObject\"/\"PyGObject==$PYGOBJECT_VERSION\"/" pyproject.toml
fi
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
        /usr/local/bin/build_codecs.sh # build libaom (AV1) and libvpx (VP9) for GStreamer
        /usr/local/bin/build_gstreamer.sh
    fi
fi

# NVidia specific dependencies
# Header files:
# nvidia-video-sdk/Interface/cuviddec.h  nvidia-video-sdk/Interface/nvcuvid.h  nvidia-video-sdk/Interface/nvEncodeAPI.h
# Libraries:
# -lnvidia-encode ...
if [ "${USE_NVIDIA:-0}" = "1" ]; then
    echo "[build_prereqs] USE_NVIDIA=1, installing NVIDIA dependencies..."
    NVIDIA_SDK_DIR="/opt/nvidia-video-sdk"
    if [ -d "$NVIDIA_SDK_DIR" ]; then
        echo "[build_prereqs] NVIDIA Video Codec SDK found at $NVIDIA_SDK_DIR"
        # Copy headers and libraries
        cp "$NVIDIA_SDK_DIR/Interface/"*.h "$DEPS_PREFIX/include/"
        cp "$NVIDIA_SDK_DIR/Samples/common/inc/"*.h "$DEPS_PREFIX/include/"
        cp "$NVIDIA_SDK_DIR/Lib/"*.so* "$DEPS_PREFIX/lib64/"
        cp "$NVIDIA_SDK_DIR/Samples/common/lib/"*.so* "$DEPS_PREFIX/lib64/"

        # PyCuda (if CUDA is installed)
        # https://github.com/Xpra-org/xpra/blob/master/docs/Usage/NVENC.md
        if command -v nvcc >/dev/null 2>&1; then
            echo "[build_prereqs] Building PyCuda..."
            if ! pip show pycuda >/dev/null 2>&1; then
                pip install pycuda || { echo "[build_prereqs] ERROR: Failed to install PyCuda"; exit 1; }
            else
                echo "[build_prereqs] PyCuda already installed, skipping."
            fi
        fi

        # Ensure nvenc.pc is available for pkg-config (for NVENC detection)
        NVENC_SRC_PC="$SRC_DIR/fs/lib/pkgconfig/nvenc.pc"
        NVENC_PKGCONFIG_DIR="$DEPS_PREFIX/lib64/pkgconfig"
        if [ -f "$NVENC_SRC_PC" ]; then
            mkdir -p "$NVENC_PKGCONFIG_DIR"
            # Fix prefix in nvenc.pc to match our install location
            sed "s|^prefix=.*$|prefix=$DEPS_PREFIX|" "$NVENC_SRC_PC" > "$NVENC_PKGCONFIG_DIR/nvenc.pc"
            echo "[build_prereqs] Copied and fixed nvenc.pc for pkg-config: $NVENC_PKGCONFIG_DIR/nvenc.pc"
        else
            echo "[build_prereqs] WARNING: nvenc.pc not found in $NVENC_SRC_PC, NVENC support may not be detected."
        fi

        # Ensure nvdec.pc is available for pkg-config (for NVDEC detection)
        NVDEC_SRC_PC="$SRC_DIR/fs/lib/pkgconfig/nvdec.pc"
        if [ -f "$NVDEC_SRC_PC" ]; then
            mkdir -p "$NVENC_PKGCONFIG_DIR"
            # Fix prefix in nvdec.pc to match our install location
            sed "s|^prefix=.*$|prefix=$DEPS_PREFIX|" "$NVDEC_SRC_PC" > "$NVENC_PKGCONFIG_DIR/nvdec.pc"
            echo "[build_prereqs] Copied and fixed nvdec.pc for pkg-config: $NVENC_PKGCONFIG_DIR/nvdec.pc"
        else
            echo "[build_prereqs] WARNING: nvdec.pc not found in $NVDEC_SRC_PC, NVDEC support may not be detected."
        fi

        # Ensure nvjpeg.pc is available for pkg-config (for NVJPEG detection)
        NVJPEG_SRC_PC="$SRC_DIR/fs/lib/pkgconfig/nvjpeg.pc"
        if [ -f "$NVJPEG_SRC_PC" ]; then
            mkdir -p "$NVENC_PKGCONFIG_DIR"
            # Fix cudaroot in nvjpeg.pc to match our CUDA install location
            sed "s|^cudaroot=.*$|cudaroot=/usr/local/cuda|" "$NVJPEG_SRC_PC" > "$NVENC_PKGCONFIG_DIR/nvjpeg.pc"
            echo "[build_prereqs] Copied and fixed nvjpeg.pc for pkg-config: $NVENC_PKGCONFIG_DIR/nvjpeg.pc"
        else
            echo "[build_prereqs] WARNING: nvjpeg.pc not found in $NVJPEG_SRC_PC, NVJPEG support may not be detected."
        fi

        # Ensure cuda.pc is available for pkg-config (for CUDA detection)
        CUDA_SRC_PC="$SRC_DIR/fs/lib/pkgconfig/cuda.pc"
        if [ -f "$CUDA_SRC_PC" ]; then
            mkdir -p "$NVENC_PKGCONFIG_DIR"
            # Fix cudaroot in cuda.pc to match our CUDA install location
            sed "s|^cudaroot=.*$|cudaroot=/usr/local/cuda|" "$CUDA_SRC_PC" > "$NVENC_PKGCONFIG_DIR/cuda.pc"
            echo "[build_prereqs] Copied and fixed cuda.pc for pkg-config: $NVENC_PKGCONFIG_DIR/cuda.pc"
        else
            echo "[build_prereqs] WARNING: cuda.pc not found in $CUDA_SRC_PC, CUDA support may not be detected."
        fi

    fi
fi

echo "[build_prereqs] Done."
popd
