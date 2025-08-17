#!/bin/bash
set -e

# Build GStreamer stack from source

# We want to avoid codecs like opus and vpx from Linuxbrew
# because those are built with a newer glibc,
# causing linker errors when building GStreamer (e.g., on CentOS 8):
# //home/linuxbrew/.linuxbrew/Cellar/util-linux/2.40.4/lib/libmount.so.1: undefined reference to `fstat@GLIBC_2.33'
# (pyenv) pkg-config --libs vpx | grep linuxbrew && echo '!! Homebrew contamination detected in libvpx linkage path!'
# -L/home/linuxbrew/.linuxbrew/Cellar/libvpx/1.15.2/lib -lvpx -lm
# !! Homebrew contamination detected in libvpx linkage path!
# (pyenv) pkg-config --libs opus | grep linuxbrew && echo '!! Homebrew contamination detected in libopus linkage path!'
# -L/home/linuxbrew/.linuxbrew/Cellar/opus/1.5.2/lib -lopus
# !! Homebrew contamination detected in libopus linkage path!

# Base directories
GST_PREFIX="$DEPS_PREFIX"
BUILD_DIR="/opt/build/gst"
mkdir -p "$BUILD_DIR"
PYTHON=python3
cd "$BUILD_DIR"

# Get Python version for site-packages dir structure
PYTHON_VERSION=$($PYTHON --version | cut -d ' ' -f 2 | cut -d '.' -f 1,2)
echo "[build_gstreamer] Building GStreamer for Python $PYTHON_VERSION"

# Build parameters
JOBS=$(nproc)
echo "[build_gstreamer] Using $JOBS parallel build jobs"
export MAKEFLAGS="-j$JOBS"
NINJA_OPTS="-j$JOBS"
GST_BRANCH="1.18"
echo "[build_gstreamer] Using GStreamer branch $GST_BRANCH"

# Set environment variables for subsequent builds
export PATH="$GST_PREFIX/bin:$PATH"
export PKG_CONFIG_PATH="$GST_PREFIX/lib64/pkgconfig:$GST_PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export LD_LIBRARY_PATH="$GST_PREFIX/lib:$GST_PREFIX/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Build codec dependencies first
# We need to build FLAC and Vorbis before GStreamer
# because GStreamer plugins-base depends on them.

# FLAC
flac_version=$(curl -s https://api.github.com/repos/xiph/flac/releases/latest | grep -oP '"tag_name":\s*"\K[^"]+')
flac_filename="flac-$flac_version.tar.xz"
flac_url="https://github.com/xiph/flac/releases/download/$flac_version/$flac_filename"
if [ -n "$flac_version" ]; then
    echo "[build_gstreamer] Downloading FLAC $flac_version from $flac_url"
    wget "$flac_url" && \
    tar xf "$flac_filename" && \
    pushd "flac-$flac_version"
    if [ $? -ne 0 ]; then
        echo "[build_gstreamer] ERROR: Failed to download or extract FLAC $flac_version"
        exit 1
    fi
    ./configure --prefix="$GST_PREFIX" --disable-examples --disable-docs && \
    make -j$(nproc) && \
    make install
    popd
else
    echo "[build_gstreamer] ERROR: Could not determine FLAC version from GitHub API"
fi

# Vorbis
vorbis_version=$(curl -s https://xiph.org/downloads/ | grep -oP 'libvorbis-\K[0-9.]+(?=\.tar\.xz)' | sort -V | tail -1)
vorbis_filename="libvorbis-$vorbis_version.tar.xz"
vorbis_url="https://downloads.xiph.org/releases/vorbis/$vorbis_filename"
if [ -n "$vorbis_version" ]; then
    echo "[build_gstreamer] Downloading Vorbis $vorbis_version from $vorbis_url"
    wget "$vorbis_url" && \
    tar xf "$vorbis_filename" && \
    pushd "libvorbis-$vorbis_version"
    if [ $? -ne 0 ]; then
        echo "[build_gstreamer] ERROR: Failed to download or extract Vorbis $vorbis_version"
        exit 1
    fi
    ./configure --prefix="$GST_PREFIX" --disable-examples --disable-docs && \
    make -j$(nproc) && \
    make install
    popd
else
    echo "[build_gstreamer] ERROR: Could not determine Vorbis version from GitHub API"
fi

# openh264
openh264_version=$(curl -s https://api.github.com/repos/cisco/openh264/releases/latest | grep -oP '"tag_name":\s*"\K[^"]+')
openh264_filename="openh264-$openh264_version.tar.gz"
openh264_url="https://github.com/cisco/openh264/archive/refs/tags/$openh264_version.tar.gz"
if [ -n "$openh264_version" ]; then
    echo "[build_gstreamer] Downloading openh264 $openh264_version from $openh264_url"
    mkdir -p "$BUILD_DIR/openh264"
    pushd "$BUILD_DIR/openh264"
    wget "$openh264_url" -O "$openh264_filename" && \
    tar xf "$openh264_filename" && \
    pushd "openh264-${openh264_version#v}" # remove 'v' prefix
    if [ $? -ne 0 ]; then
        echo "[build_gstreamer] ERROR: Failed to download or extract openh264 $openh264_version"
        exit 1
    fi
    make -j$(nproc) && \
    make install PREFIX="$GST_PREFIX"
    popd
    popd
else
    echo "[build_gstreamer] ERROR: Could not determine openh264 version from GitHub API"
fi

# libjpeg-turbo
jpeg_version=$(curl -s https://api.github.com/repos/libjpeg-turbo/libjpeg-turbo/releases/latest | grep -oP '"tag_name":\s*"\K[^"]+')
jpeg_filename="libjpeg-turbo-$jpeg_version.tar.gz"
jpeg_url="https://github.com/libjpeg-turbo/libjpeg-turbo/archive/refs/tags/$jpeg_version.tar.gz"
if [ -n "$jpeg_version" ]; then
    echo "[build_gstreamer] Downloading libjpeg-turbo $jpeg_version from $jpeg_url"
    wget "$jpeg_url" -O "$jpeg_filename" && \
    tar xf "$jpeg_filename" && \
    pushd "libjpeg-turbo-${jpeg_version#v}" # Remove 'v' prefix for directory name
    if [ $? -ne 0 ]; then
        echo "[build_gstreamer] ERROR: Failed to download or extract libjpeg-turbo $jpeg_version"
        exit 1
    fi
    mkdir -p build && pushd build
    cmake -DCMAKE_INSTALL_PREFIX="$GST_PREFIX" -DENABLE_SHARED=1 -DENABLE_STATIC=0 ..
    make -j$(nproc)
    make install
    popd
    popd
else
    echo "[build_gstreamer] ERROR: Could not determine libjpeg-turbo version from GitHub API"
fi

# libspng (for xpra.codecs.spng)
libspng_url="https://github.com/randy408/libspng.git"
echo "[build_gstreamer] Cloning libspng from $libspng_url"
git clone "$libspng_url" libspng-src
pushd libspng-src
cmake -DCMAKE_INSTALL_PREFIX="$GST_PREFIX" .
make -j$(nproc)
make install
popd

# libva (Video Acceleration API) >= 1.6
LIBVA_VERSION=$(curl -s https://api.github.com/repos/intel/libva/releases/latest | grep -oP '"tag_name":\s*"\K[^"]+')
LIBVA_API_URL="https://api.github.com/repos/intel/libva/releases/tags/${LIBVA_VERSION}"
LIBVA_ASSET_URL=$(curl -s $LIBVA_API_URL | grep browser_download_url | grep -E 'libva-.*\.tar\.(gz|bz2|xz|Z|lzma|zst)' | head -n1 | cut -d '"' -f 4)
LIBVA_TARBALL=$(basename "$LIBVA_ASSET_URL")
echo "[build_gstreamer] Downloading libva ${LIBVA_VERSION} from $LIBVA_ASSET_URL"
wget -O "$LIBVA_TARBALL" "$LIBVA_ASSET_URL" || { echo "[build_gstreamer] ERROR: Failed to download libva tarball"; exit 1; }
tar xf "$LIBVA_TARBALL" || { echo "[build_gstreamer] ERROR: Failed to extract libva tarball"; exit 1; }
pushd "libva-${LIBVA_VERSION}"
echo "[build_gstreamer] Building libva ${LIBVA_VERSION} ..."
./configure --prefix="$GST_PREFIX"
make -j$(nproc)
make install
popd
echo "[build_gstreamer] libva ${LIBVA_VERSION} installed to $GST_PREFIX"

# libyuv (for csc_libyuv plugin)
libyuv_url="https://chromium.googlesource.com/libyuv/libyuv"
echo "[build_gstreamer] Cloning libyuv from $libyuv_url"
git clone --branch stable "$libyuv_url" libyuv-src
pushd libyuv-src
cmake -DCMAKE_INSTALL_PREFIX="$GST_PREFIX" -DCMAKE_POLICY_VERSION_MINIMUM=3.5 .
make -j$(nproc)
make install
popd

###
# With some codecs in place, build GStreamer

# Determine latest patch version from the selected GStreamer branch
cd $BUILD_DIR
echo "[build_gstreamer] Finding GStreamer version from branch $GST_BRANCH..."
GST_VERSION=$(wget -qO- "https://gstreamer.freedesktop.org/src/gstreamer/" | grep -o "gstreamer-$GST_BRANCH\.[0-9]*\.tar.xz" | sort -V | tail -1 | sed "s/gstreamer-//;s/\.tar\.xz//")
echo "[build_gstreamer] Found GStreamer version $GST_VERSION"

# Build core GStreamer
echo "[build_gstreamer] Building GStreamer core $GST_VERSION..."
wget -q "https://gstreamer.freedesktop.org/src/gstreamer/gstreamer-$GST_VERSION.tar.xz"
tar xf "gstreamer-$GST_VERSION.tar.xz"
pushd "gstreamer-$GST_VERSION"
mkdir -p build && pushd build
meson --prefix=$GST_PREFIX -Dbuildtype=release -Dintrospection=enabled ..
ninja $NINJA_OPTS
ninja install
popd
popd

# Build GStreamer plugins-base
# Extend PKG_CONFIG_PATH to include OS pkg-config paths for this build to pick up pulse libs
echo "[build_gstreamer] Building GStreamer plugins-base..."
wget -q "https://gstreamer.freedesktop.org/src/gst-plugins-base/gst-plugins-base-$GST_VERSION.tar.xz"
tar xf "gst-plugins-base-$GST_VERSION.tar.xz"
pushd "gst-plugins-base-$GST_VERSION"
mkdir -p build && pushd build
PKG_CONFIG_PATH="$GST_PREFIX/lib64/pkgconfig:$GST_PREFIX/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig" \
    meson --prefix=$GST_PREFIX -Dbuildtype=release -Dintrospection=enabled ..
ninja $NINJA_OPTS
ninja install
popd
popd

# Build GStreamer plugins-good
# We should get pulseaudio support here (namely pulsesrc, pulsesink)
echo "[build_gstreamer] Building GStreamer plugins-good..."
wget -q "https://gstreamer.freedesktop.org/src/gst-plugins-good/gst-plugins-good-$GST_VERSION.tar.xz"
tar xf "gst-plugins-good-$GST_VERSION.tar.xz"
pushd "gst-plugins-good-$GST_VERSION"
mkdir -p build && pushd build
PKG_CONFIG_PATH="$GST_PREFIX/lib64/pkgconfig:$GST_PREFIX/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig" \
    meson --prefix=$GST_PREFIX -Dbuildtype=release ..
ninja $NINJA_OPTS
ninja install
popd
popd

# Build GStreamer plugins-bad (for openh264enc/dec)
# export CUDA_PATH=/usr/local/cuda
# export CUDA_HOME=/usr/local/cuda
echo "[build_gstreamer] Building GStreamer plugins-bad..."
wget -q "https://gstreamer.freedesktop.org/src/gst-plugins-bad/gst-plugins-bad-$GST_VERSION.tar.xz"
tar xf "gst-plugins-bad-$GST_VERSION.tar.xz"
pushd "gst-plugins-bad-$GST_VERSION"
mkdir -p build && pushd build
CUDA_PATH=/usr/local/cuda CUDA_HOME=/usr/local/cuda \
PKG_CONFIG_PATH="$GST_PREFIX/lib64/pkgconfig:$GST_PREFIX/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig" \
    meson --prefix=$GST_PREFIX -Dbuildtype=release ..
ninja $NINJA_OPTS
ninja install
popd
popd



# Create setup script for runtime environment variables needed by AppImage
cat > $GST_PREFIX/setup-gst-env.sh << EOF
#!/bin/bash
# Setup environment variables for GStreamer
export GST_PREFIX="$GST_PREFIX"
export PKG_CONFIG_PATH="\$GST_PREFIX/lib64/pkgconfig:\$GST_PREFIX/lib/pkgconfig:\$PKG_CONFIG_PATH"
export LD_LIBRARY_PATH="\$GST_PREFIX/lib:\$GST_PREFIX/lib64:\$LD_LIBRARY_PATH"
export PATH="\$GST_PREFIX/bin:\$PATH"
export GI_TYPELIB_PATH="\$GST_PREFIX/lib64/girepository-1.0:\$GST_PREFIX/lib/girepository-1.0:\$GI_TYPELIB_PATH"
export GST_PLUGIN_PATH="\$GST_PREFIX/lib64/gstreamer-1.0"
export PYTHONPATH="\$GST_PREFIX/lib/python$PYTHON_VERSION/site-packages:\$PYTHONPATH"
EOF
source $GST_PREFIX/setup-gst-env.sh

# Run check script to verify GStreamer installation and print available plugins/codecs
# Expect failure and flying pumpkins if GLib and gobject-introspection at 1.78 (see PyGObject etc.)
check_gst_codecs.py

echo "[build_gstreamer] Done building GStreamer in $GST_PREFIX"
