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
cd "$BUILD_DIR"
flac_version=$(curl -s https://api.github.com/repos/xiph/flac/releases/latest | grep -oP '"tag_name":\s*"\K[^"]+')
flac_filename="flac-$flac_version.tar.xz"
flac_url="https://github.com/xiph/flac/releases/download/$flac_version/$flac_filename"
if [ -n "$flac_version" ]; then
    echo "[build_gstreamer] Downloading FLAC $flac_version from $flac_url"
    wget "$flac_url" && \
    tar xf "$flac_filename" && \
    cd "flac-$flac_version"
    if [ $? -ne 0 ]; then
        echo "[build_gstreamer] ERROR: Failed to download or extract FLAC $flac_version"
        exit 1
    fi
    ./configure --prefix="$GST_PREFIX" --disable-examples --disable-docs && \
    make -j$(nproc) && \
    make install
else
    echo "[build_gstreamer] ERROR: Could not determine FLAC version from GitHub API"
fi
cd "$BUILD_DIR"

# Vorbis
cd "$BUILD_DIR"
vorbis_version=$(curl -s https://xiph.org/downloads/ | grep -oP 'libvorbis-\K[0-9.]+(?=\.tar\.xz)' | sort -V | tail -1)
vorbis_filename="libvorbis-$vorbis_version.tar.xz"
vorbis_url="https://downloads.xiph.org/releases/vorbis/$vorbis_filename"
if [ -n "$vorbis_version" ]; then
    echo "[build_gstreamer] Downloading Vorbis $vorbis_version from $vorbis_url"
    wget "$vorbis_url" && \
    tar xf "$vorbis_filename" && \
    cd "libvorbis-$vorbis_version"
    if [ $? -ne 0 ]; then
        echo "[build_gstreamer] ERROR: Failed to download or extract Vorbis $vorbis_version"
        exit 1
    fi
    ./configure --prefix="$GST_PREFIX" --disable-examples --disable-docs && \
    make -j$(nproc) && \
    make install
else
    echo "[build_gstreamer] ERROR: Could not determine Vorbis version from GitHub API"
fi
cd "$BUILD_DIR"

# Determine latest patch version from the selected GStreamer branch
cd $BUILD_DIR
echo "[build_gstreamer] Finding GStreamer version from branch $GST_BRANCH..."
GST_VERSION=$(wget -qO- "https://gstreamer.freedesktop.org/src/gstreamer/" | grep -o "gstreamer-$GST_BRANCH\.[0-9]*\.tar.xz" | sort -V | tail -1 | sed "s/gstreamer-//;s/\.tar\.xz//")
echo "[build_gstreamer] Found GStreamer version $GST_VERSION"

# Build core GStreamer
cd $BUILD_DIR
echo "[build_gstreamer] Building GStreamer core $GST_VERSION..."
wget -q "https://gstreamer.freedesktop.org/src/gstreamer/gstreamer-$GST_VERSION.tar.xz"
tar xf "gstreamer-$GST_VERSION.tar.xz"
cd "gstreamer-$GST_VERSION"
mkdir -p build && cd build
meson --prefix=$GST_PREFIX -Dbuildtype=release -Dintrospection=enabled ..
ninja $NINJA_OPTS
ninja install
cd $BUILD_DIR

# Build GStreamer plugins-base
# Extend PKG_CONFIG_PATH to include OS pkg-config paths for this build to pick up pulse libs
cd $BUILD_DIR
echo "[build_gstreamer] Building GStreamer plugins-base..."
wget -q "https://gstreamer.freedesktop.org/src/gst-plugins-base/gst-plugins-base-$GST_VERSION.tar.xz"
tar xf "gst-plugins-base-$GST_VERSION.tar.xz"
cd "gst-plugins-base-$GST_VERSION"
mkdir -p build && cd build
PKG_CONFIG_PATH="$GST_PREFIX/lib64/pkgconfig:$GST_PREFIX/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig" \
  meson --prefix=$GST_PREFIX -Dbuildtype=release -Dintrospection=enabled ..
ninja $NINJA_OPTS
ninja install
cd $BUILD_DIR

# Build GStreamer plugins-good
# We should get pulseaudio support here (namely pulsesrc, pulsesink)
echo "[build_gstreamer] Building GStreamer plugins-good..."
wget -q "https://gstreamer.freedesktop.org/src/gst-plugins-good/gst-plugins-good-$GST_VERSION.tar.xz"
tar xf "gst-plugins-good-$GST_VERSION.tar.xz"
cd "gst-plugins-good-$GST_VERSION"
mkdir -p build && cd build
PKG_CONFIG_PATH="$GST_PREFIX/lib64/pkgconfig:$GST_PREFIX/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig" \
  meson --prefix=$GST_PREFIX -Dbuildtype=release ..
ninja $NINJA_OPTS
ninja install



# Create setup script for runtime environment variables needed by AppImage
cat > $GST_PREFIX/setup-gst-env.sh << EOF
#!/bin/bash
# Setup environment variables for GStreamer
export GST_PREFIX="$GST_PREFIX"
export PKG_CONFIG_PATH="\$GST_PREFIX/lib64/pkgconfig:\$GST_PREFIX/lib/pkgconfig:\$PKG_CONFIG_PATH"
export LD_LIBRARY_PATH="\$GST_PREFIX/lib:\$GST_PREFIX/lib64:\$LD_LIBRARY_PATH"
export PATH="\$GST_PREFIX/bin:\$PATH"
export GI_TYPELIB_PATH="\$GST_PREFIX/lib/girepository-1.0:\$GI_TYPELIB_PATH"
export GST_PLUGIN_PATH="\$GST_PREFIX/lib/gstreamer-1.0"
export PYTHONPATH="\$GST_PREFIX/lib/python$PYTHON_VERSION/site-packages:\$PYTHONPATH"
EOF
chmod +x $GST_PREFIX/setup-gst-env.sh

echo "[build_gstreamer] Done building minimal GStreamer stack in $GST_PREFIX"
echo "Use 'source $GST_PREFIX/setup-gst-env.sh' to set up the environment"
