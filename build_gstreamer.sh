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
PYTHON=python3

# Get Python version for site-packages dir structure
PYTHON_VERSION=$($PYTHON --version | cut -d ' ' -f 2 | cut -d '.' -f 1,2)
echo "[build_gstreamer] Building GStreamer for Python $PYTHON_VERSION"

# Create directories
mkdir -p "$BUILD_DIR"
mkdir -p "$GST_PREFIX"

# Ensure ogg/vorbis are present in $DEPS_PREFIX, build if missing
#export PKG_CONFIG_PATH="$DEPS_PREFIX/lib/pkgconfig:$DEPS_PREFIX/lib64/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

if ! pkg-config --exists ogg; then
    echo "[build_gstreamer] Building libogg from source into $DEPS_PREFIX..."
    OGG_VERSION="1.3.5"
    cd "$BUILD_DIR"
    wget -q "https://downloads.xiph.org/releases/ogg/libogg-$OGG_VERSION.tar.gz"
    tar xf "libogg-$OGG_VERSION.tar.gz"
    cd "libogg-$OGG_VERSION"
    ./configure --prefix=$DEPS_PREFIX --enable-shared --enable-static --disable-docs --disable-examples
    make $MAKEFLAGS
    make install
    cd "$BUILD_DIR"
fi

if ! pkg-config --exists vorbis; then
    echo "[build_gstreamer] Building libvorbis from source into $DEPS_PREFIX..."
    VORBIS_VERSION="1.3.7"
    cd "$BUILD_DIR"
    wget -q "https://downloads.xiph.org/releases/vorbis/libvorbis-$VORBIS_VERSION.tar.gz"
    tar xf "libvorbis-$VORBIS_VERSION.tar.gz"
    cd "libvorbis-$VORBIS_VERSION"
    ./configure --prefix=$DEPS_PREFIX --enable-shared --enable-static --disable-docs --disable-examples
    make $MAKEFLAGS
    make install
    cd "$BUILD_DIR"
fi

if ! pkg-config --exists theora; then
    echo "[build_gstreamer] Building libtheora from source into $DEPS_PREFIX..."
    THEORA_VERSION="1.1.1"
    cd "$BUILD_DIR"
    wget -q "https://downloads.xiph.org/releases/theora/libtheora-$THEORA_VERSION.tar.gz"
    tar xf "libtheora-$THEORA_VERSION.tar.gz"
    cd "libtheora-$THEORA_VERSION"
    ./configure --prefix=$DEPS_PREFIX --enable-shared --enable-static --disable-examples --disable-docs
    make $MAKEFLAGS
    make install
    cd "$BUILD_DIR"
fi

# Set number of build jobs based on CPU cores for parallel build optimization
JOBS=$(nproc)
echo "[build_gstreamer] Using $JOBS parallel build jobs"
export MAKEFLAGS="-j$JOBS"
NINJA_OPTS="-j$JOBS"

# Find latest compatible versions in stable branches for CentOS 8 compatibility
echo "[build_gstreamer] Determining latest compatible package versions"
GLIB_BRANCH="2.66"  # Last branch compatible with glibc 2.28 (CentOS 8)
GST_BRANCH="1.18"   # Stable branch good for our needs
ORC_BRANCH="0.4"    # Compatible with GST_BRANCH
PYGOBJECT_BRANCH="3.38"  # Compatible with this GLIB and Python

# Always build from source since system GStreamer on CentOS 8 is too old and doesn't have required codecs
echo "[build_gstreamer] Building GStreamer from source for CentOS 8 compatibility..."

# Verify all required build tools and libraries are available before starting the build
REQUIRED_TOOLS=(meson ninja yasm nasm gcc g++ pkg-config)
REQUIRED_LIBS=(vorbisenc vorbisfile theoraenc theoradec)

for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
        echo "[build_gstreamer] ERROR: Required build tool '$tool' not found in PATH. Please run build_prereqs.sh first." >&2
        exit 1
    fi
done

for lib in "${REQUIRED_LIBS[@]}"; do
    if ! pkg-config --exists "$lib"; then
        echo "[build_gstreamer] ERROR: Required library '$lib' not found (pkg-config check failed). Please run build_prereqs.sh first." >&2
        exit 1
    fi
done

# Begin building all components from source
echo "[build_gstreamer] Starting source builds in $BUILD_DIR"
cd $BUILD_DIR

## 1. Build GLib
#echo "[build_gstreamer] Building GLib from branch $GLIB_BRANCH..."
#GLIB_VERSION=$(wget -qO- "https://download.gnome.org/sources/glib/$GLIB_BRANCH/" | grep -o "glib-$GLIB_BRANCH\.[0-9]*\.tar.xz" | sort -V | tail -1 | sed "s/glib-//;s/\.tar\.xz//")
#echo "[build_gstreamer] Found GLib version $GLIB_VERSION"
#
#wget -q "https://download.gnome.org/sources/glib/$GLIB_BRANCH/glib-$GLIB_VERSION.tar.xz"
#tar xf "glib-$GLIB_VERSION.tar.xz"
#cd "glib-$GLIB_VERSION"
#mkdir -p build && cd build
#meson --prefix=$GST_PREFIX -Dbuildtype=release -Dman=false -Dgtk_doc=false ..
#ninja $NINJA_OPTS
#ninja install
#cd $BUILD_DIR
#
## 2. Build ORC (optional acceleration)
#echo "[build_gstreamer] Building ORC from branch $ORC_BRANCH..."
#ORC_VERSION=$(wget -qO- "https://gstreamer.freedesktop.org/src/orc/" | grep -o "orc-$ORC_BRANCH\.[0-9]*\.tar.xz" | sort -V | tail -1 | sed "s/orc-//;s/\.tar\.xz//")
#echo "[build_gstreamer] Found ORC version $ORC_VERSION"
#
#wget -q "https://gstreamer.freedesktop.org/src/orc/orc-$ORC_VERSION.tar.xz"
#tar xf "orc-$ORC_VERSION.tar.xz"
#cd "orc-$ORC_VERSION"
#mkdir -p build && cd build
#meson --prefix=$GST_PREFIX -Dbuildtype=release -Dgtk_doc=false ..
#ninja $NINJA_OPTS
#ninja install
#cd $BUILD_DIR

# Set environment variables for subsequent builds
export PATH="$GST_PREFIX/bin:$PATH"
export PKG_CONFIG_PATH="$GST_PREFIX/lib64/pkgconfig:$GST_PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export LD_LIBRARY_PATH="$GST_PREFIX/lib:$GST_PREFIX/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
# more written to setup-gst-env.sh below

# Set compiler optimization flags for security hardening and CentOS 8 compatibility
export CFLAGS="${CFLAGS} -O2 -D_FORTIFY_SOURCE=2"
export CXXFLAGS="${CXXFLAGS} -O2 -D_FORTIFY_SOURCE=2"

# 3. Build libvpx for VP8/VP9 video codec support (critical for WebRTC compatibility)
echo "[build_gstreamer] Building libvpx from source..."
LIBVPX_VERSION="1.11.0"  # Compatible with CentOS 8's glibc
wget -q "https://github.com/webmproject/libvpx/archive/v${LIBVPX_VERSION}.tar.gz"
tar xf "v${LIBVPX_VERSION}.tar.gz"
cd "libvpx-${LIBVPX_VERSION}"
# Configure with shared library support
./configure --prefix=$GST_PREFIX --enable-shared --enable-pic
make $MAKEFLAGS
make install
cd $BUILD_DIR

# 3b. Build libopus for high-quality, low-latency audio codec support (essential for WebRTC)
echo "[build_gstreamer] Building libopus from source..."
LIBOPUS_VERSION="1.3.1"  # Stable and widely compatible
wget -q "https://archive.mozilla.org/pub/opus/opus-${LIBOPUS_VERSION}.tar.gz"
tar xf "opus-${LIBOPUS_VERSION}.tar.gz"
cd "opus-${LIBOPUS_VERSION}"
./configure --prefix=$GST_PREFIX --enable-shared --enable-static
make $MAKEFLAGS
make install
cd $BUILD_DIR

## 4. Build gobject-introspection to enable Python bindings for GStreamer
#echo "[build_gstreamer] Building gobject-introspection..."
#GI_VERSION=$(wget -qO- "https://download.gnome.org/sources/gobject-introspection/1.66/" | grep -o "gobject-introspection-1.66\.[0-9]*\.tar.xz" | sort -V | tail -1 | sed "s/gobject-introspection-//;s/\.tar\.xz//")
#echo "[build_gstreamer] Found gobject-introspection version $GI_VERSION"
#
#wget -q "https://download.gnome.org/sources/gobject-introspection/1.66/gobject-introspection-$GI_VERSION.tar.xz"
#tar xf "gobject-introspection-$GI_VERSION.tar.xz"
#cd "gobject-introspection-$GI_VERSION"
#mkdir -p build && cd build
#meson --prefix=$GST_PREFIX -Dbuildtype=release -Dgtk_doc=false ..
#ninja $NINJA_OPTS
#ninja install
#cd $BUILD_DIR

# 5. Determine latest patch version from the selected GStreamer branch
echo "[build_gstreamer] Finding GStreamer version from branch $GST_BRANCH..."
GST_VERSION=$(wget -qO- "https://gstreamer.freedesktop.org/src/gstreamer/" | grep -o "gstreamer-$GST_BRANCH\.[0-9]*\.tar.xz" | sort -V | tail -1 | sed "s/gstreamer-//;s/\.tar\.xz//")
echo "[build_gstreamer] Found GStreamer version $GST_VERSION"

# 6. Build core GStreamer
echo "[build_gstreamer] Building GStreamer core $GST_VERSION..."
wget -q "https://gstreamer.freedesktop.org/src/gstreamer/gstreamer-$GST_VERSION.tar.xz"
tar xf "gstreamer-$GST_VERSION.tar.xz"
cd "gstreamer-$GST_VERSION"
mkdir -p build && cd build
meson --prefix=$GST_PREFIX -Dbuildtype=release -Dintrospection=enabled -Dgst_debug=true -Dexamples=disabled -Dtests=disabled -Ddoc=disabled ..
ninja $NINJA_OPTS
ninja install
cd $BUILD_DIR

# 7. Build GStreamer plugins-base
echo "[build_gstreamer] Building GStreamer plugins-base..."
wget -q "https://gstreamer.freedesktop.org/src/gst-plugins-base/gst-plugins-base-$GST_VERSION.tar.xz"
tar xf "gst-plugins-base-$GST_VERSION.tar.xz"
cd "gst-plugins-base-$GST_VERSION"
mkdir -p build && cd build
meson --prefix=$GST_PREFIX -Dbuildtype=release -Dintrospection=enabled -Dexamples=disabled -Dtests=disabled -Ddoc=disabled ..
ninja $NINJA_OPTS
ninja install
cd $BUILD_DIR

# 8. Build GStreamer plugins-good
echo "[build_gstreamer] Building GStreamer plugins-good..."
wget -q "https://gstreamer.freedesktop.org/src/gst-plugins-good/gst-plugins-good-$GST_VERSION.tar.xz"
tar xf "gst-plugins-good-$GST_VERSION.tar.xz"
cd "gst-plugins-good-$GST_VERSION"
mkdir -p build && cd build
meson --prefix=$GST_PREFIX -Dbuildtype=release -Dexamples=disabled -Dtests=disabled -Ddoc=disabled ..
ninja $NINJA_OPTS
ninja install
cd $BUILD_DIR

# 9. Build GStreamer plugins-bad
echo "[build_gstreamer] Building GStreamer plugins-bad..."
wget -q "https://gstreamer.freedesktop.org/src/gst-plugins-bad/gst-plugins-bad-$GST_VERSION.tar.xz"
tar xf "gst-plugins-bad-$GST_VERSION.tar.xz"
cd "gst-plugins-bad-$GST_VERSION"
mkdir -p build && cd build
meson --prefix=$GST_PREFIX -Dbuildtype=release -Dintrospection=enabled -Dexamples=disabled -Dtests=disabled -Ddoc=disabled ..
ninja $NINJA_OPTS
ninja install
cd $BUILD_DIR

# 10. Build GStreamer plugins-ugly
echo "[build_gstreamer] Building GStreamer plugins-ugly..."
wget -q "https://gstreamer.freedesktop.org/src/gst-plugins-ugly/gst-plugins-ugly-$GST_VERSION.tar.xz"
tar xf "gst-plugins-ugly-$GST_VERSION.tar.xz"
cd "gst-plugins-ugly-$GST_VERSION"
mkdir -p build && cd build
meson --prefix=$GST_PREFIX -Dbuildtype=release -Dexamples=disabled -Dtests=disabled -Ddoc=disabled ..
ninja $NINJA_OPTS
ninja install
cd $BUILD_DIR

# 11. Build GStreamer libav (optional, for additional codecs)
echo "[build_gstreamer] Building GStreamer libav..."
wget -q "https://gstreamer.freedesktop.org/src/gst-libav/gst-libav-$GST_VERSION.tar.xz"
tar xf "gst-libav-$GST_VERSION.tar.xz"
cd "gst-libav-$GST_VERSION"
mkdir -p build && cd build
meson --prefix=$GST_PREFIX -Dbuildtype=release -Dexamples=disabled -Dtests=disabled -Ddoc=disabled ..
ninja $NINJA_OPTS
ninja install
cd $BUILD_DIR

# 12. Install PyGObject into Python environment for GStreamer Python bindings
echo "[build_gstreamer] Installing PyGObject into Python venv..."
$PYTHON -m pip install --upgrade pip
$PYTHON -m pip install pycairo  # PyGObject dependency

# Check if PyGObject is already installed
if $PYTHON -c "import gi" &>/dev/null; then
    echo "[build_gstreamer] PyGObject already installed in Python environment"
else
    # Try using pip for pygobject (simplest approach)
    echo "[build_gstreamer] Installing PyGObject via pip..."
    PKG_CONFIG_PATH="$GST_PREFIX/lib64/pkgconfig:$GST_PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH" \
    $PYTHON -m pip install pygobject
    
    if ! $PYTHON -c "import gi" &>/dev/null; then
        echo "[build_gstreamer] Pip install failed, building PyGObject from source..."
        # Build from source if pip install fails
        PYGOBJECT_VERSION=$(wget -qO- "https://download.gnome.org/sources/pygobject/$PYGOBJECT_BRANCH/" | grep -o "pygobject-$PYGOBJECT_BRANCH\.[0-9]*\.tar.xz" | sort -V | tail -1 | sed "s/pygobject-//;s/\.tar\.xz//")
        echo "[build_gstreamer] Found PyGObject version $PYGOBJECT_VERSION"
        
        wget -q "https://download.gnome.org/sources/pygobject/$PYGOBJECT_BRANCH/pygobject-$PYGOBJECT_VERSION.tar.xz"
        tar xf "pygobject-$PYGOBJECT_VERSION.tar.xz"
        cd "pygobject-$PYGOBJECT_VERSION"
        mkdir -p build && cd build
        
        # Configure environment for PyGObject build
        export XDG_DATA_DIRS="$GST_PREFIX/share:$XDG_DATA_DIRS"
        PKG_CONFIG_PATH="$GST_PREFIX/lib64/pkgconfig:$GST_PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH" \
        meson --prefix=$GST_PREFIX -Dbuildtype=release -Dpython=$PYTHON ..
        ninja $NINJA_OPTS
        ninja install
        
        # Create symbolic link in Python site-packages
        SITE_PACKAGES_DIR=$($PYTHON -c "import site; print(site.getsitepackages()[0])")
        echo "[build_gstreamer] Python site-packages directory: $SITE_PACKAGES_DIR"
        
        ln -sf "$GST_PREFIX/lib/python$PYTHON_VERSION/site-packages/gi" "$SITE_PACKAGES_DIR/"
    fi
fi

# Create setup script for runtime environment variables needed by AppImage
echo "[build_gstreamer] Creating setup script for environment variables..."
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

# Test GStreamer CLI
echo "[build_gstreamer] Testing GStreamer CLI..."
source $GST_PREFIX/setup-gst-env.sh
$GST_PREFIX/bin/gst-inspect-1.0 --version

# Test Python bindings
echo "[build_gstreamer] Testing Python GI with GStreamer..."
source $GST_PREFIX/setup-gst-env.sh
$PYTHON -c "import gi; from gi.repository import Gst; Gst.init(None); print('GStreamer version:', Gst.version_string())"

# Test for critical codecs (simplify to just check VP8/VP9 and Opus)
echo "[build_gstreamer] Checking for VP8/VP9 and Opus support..."
if $GST_PREFIX/bin/gst-inspect-1.0 opusenc &>/dev/null && \
   $GST_PREFIX/bin/gst-inspect-1.0 vp8enc &>/dev/null && \
   $GST_PREFIX/bin/gst-inspect-1.0 vp9enc &>/dev/null; then
    echo "[build_gstreamer] SUCCESS: VP8/VP9 and Opus codecs are available"
else
    echo "[build_gstreamer] WARNING: Some video/audio codecs may be missing. AppImage may have limited media support."
fi

echo "[build_gstreamer] Done building GStreamer stack in $GST_PREFIX"
echo "Use 'source $GST_PREFIX/setup-gst-env.sh' to set up the environment"
