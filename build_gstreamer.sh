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
BUILD_DIR="/opt/gst-build"
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
cd $BUILD_DIR
echo "[build_gstreamer] Building GStreamer plugins-base..."
wget -q "https://gstreamer.freedesktop.org/src/gst-plugins-base/gst-plugins-base-$GST_VERSION.tar.xz"
tar xf "gst-plugins-base-$GST_VERSION.tar.xz"
cd "gst-plugins-base-$GST_VERSION"
mkdir -p build && cd build
meson --prefix=$GST_PREFIX -Dbuildtype=release -Dintrospection=enabled ..
ninja $NINJA_OPTS
ninja install
cd $BUILD_DIR

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
