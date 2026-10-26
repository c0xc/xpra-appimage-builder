#!/bin/bash
# not using set -e, might cause silent failures (uncaught error skipping the rest of the script)

# build_env.sh: Prepare Python environment for build
# Some core tools are also installed - via Brew unless USE_BREW=0
# For example meson (missing in CentOS 8)
# No [pre-built] libraries are installed here, as this is still
# part of the Podman image build process, that decision is made later.

# Base env, build dir, common prefix for dependencies built from source
BUILD_DIR="/tmp/build"
mkdir -p "$BUILD_DIR"
DEPS_PREFIX="/opt/dep" # set here because build_env runs before container_init.sh
echo "[build_env] Setting up dependencies prefix: $DEPS_PREFIX"
mkdir -p "$DEPS_PREFIX"

# Build environment variables, duplicated from container_init.sh (because this runs earlier)
export PKG_CONFIG_PATH="$DEPS_PREFIX/lib/pkgconfig:$DEPS_PREFIX/lib64/pkgconfig:$PKG_CONFIG_PATH"
export LD_LIBRARY_PATH="$DEPS_PREFIX/lib:$DEPS_PREFIX/lib64:$LD_LIBRARY_PATH"
export GI_TYPELIB_PATH="$DEPS_PREFIX/lib/girepository-1.0:$DEPS_PREFIX/lib64/girepository-1.0:$GI_TYPELIB_PATH"

# Use gcc instead of clang
export CC=gcc
export CXX=g++
export GI_HOST_CC=gcc

# Check if jq is available
if ! command -v jq >/dev/null 2>&1; then
    echo "[build_env] ERROR: jq is required but not found"
    exit 1
fi

# Set Python version to be installed (can be overridden); OS Python is too old
# xpra >= 8.0 requires >= 3.12 (setup.py: check_python_version)
PYTHON_VERSION="${PYTHON_VERSION:-3.12}"
echo "[build_env] Starting environment preparation for Python $PYTHON_VERSION"

# Find the latest Python build date
echo "[build_env] Finding latest release for Python $PYTHON_VERSION..."
LATEST_RELEASE=$(wget -q -O- https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest | grep tag_name | cut -d'"' -f4)
PYTHON_BUILD_DATE="${PYTHON_BUILD_DATE:-$LATEST_RELEASE}"
echo "[build_env] Using build date: $PYTHON_BUILD_DATE"

# Find the exact Python version if only the series is specified
# So if 3.10 is specified, find a matching 3.10.x release
if [[ "$PYTHON_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo "[build_env] Finding compatible version for Python $PYTHON_VERSION series..."

    # Get release assets from GitHub API
    RELEASE_DATA=$(wget -q -O- "https://api.github.com/repos/astral-sh/python-build-standalone/releases/tags/$PYTHON_BUILD_DATE")
    echo "[build_env] Parsing release data using jq..."

    # Extract asset names into a bash array
    readarray -t PYTHON_ASSETS < <(echo "$RELEASE_DATA" | 
        jq -r --arg series "$PYTHON_VERSION" \
        '.assets[] | 
         select(.name | 
           contains("cpython-"+$series+".") and 
           contains("x86_64-unknown-linux-gnu") and 
           contains("install_only") and 
           (endswith(".tar.gz") or endswith(".tar.zst")) and 
           (contains(".sha256") | not)
         ) | .name')

    # Check if we found any matching assets
    if [ ${#PYTHON_ASSETS[@]} -eq 0 ]; then
        echo "[build_env] ERROR: No Python $PYTHON_VERSION.x assets found in release $PYTHON_BUILD_DATE"
        echo "[build_env] Please check available versions at: https://github.com/astral-sh/python-build-standalone/releases"
        exit 1
    fi

    # Debug: Show found assets
    echo "[build_env] Found ${#PYTHON_ASSETS[@]} compatible Python versions:"
    for asset in "${PYTHON_ASSETS[@]}"; do
        echo "[build_env]   - $asset"
    done
    
    # Extract version from the first compatible asset found
    # Extract full version like 3.10.12, set PYTHON_VERSION
    SELECTED_ASSET="${PYTHON_ASSETS[0]}"
    MATCHING_VERSION=$(echo "$SELECTED_ASSET" | sed -E "s/.*cpython-($PYTHON_VERSION\.[0-9]+).*/\1/")
    if [ -n "$MATCHING_VERSION" ]; then
        PYTHON_VERSION="$MATCHING_VERSION"
        echo "[build_env] Selected version: $PYTHON_VERSION"
    else
        echo "[build_env] ERROR: Could not extract version number from asset name"
        echo "[build_env] Asset name: $SELECTED_ASSET"
        exit 1
    fi
fi

# Set URL for Python download - at this point PYTHON_VERSION is a full version
PYTHON_BS_URL="https://github.com/astral-sh/python-build-standalone/releases/download/${PYTHON_BUILD_DATE}/cpython-${PYTHON_VERSION}+${PYTHON_BUILD_DATE}-x86_64-unknown-linux-gnu-install_only.tar.gz"
echo "[build_env] Download URL: $PYTHON_BS_URL"

# Set Python installation path - use system root for container portability
PYTHON_INSTALL_DIR="/opt/python3"
VENV_DIR="/opt/pyenv"

# Download and extract python-build-standalone if not already present
if [ ! -d "$PYTHON_INSTALL_DIR" ]; then
    echo "[build_env] Downloading Python $PYTHON_VERSION..."
    if ! wget -O /tmp/python.tar.gz "$PYTHON_BS_URL"; then
        echo "[build_env] ERROR: Failed to download Python from $PYTHON_BS_URL"
        exit 1
    fi
    mkdir -p "$PYTHON_INSTALL_DIR"
    echo "[build_env] Extracting Python tarball..."
    if ! tar -xzf /tmp/python.tar.gz -C "$PYTHON_INSTALL_DIR" --strip-components=1; then
        echo "[build_env] ERROR: Failed to extract Python tarball"
        exit 1
    fi
    rm /tmp/python.tar.gz
    echo "[build_env] Python installed at $PYTHON_INSTALL_DIR"
    # No need to create symlink in $HOME/.local/bin anymore
else
    echo "[build_env] Using existing Python installation at $PYTHON_INSTALL_DIR"
fi

# Create virtualenv
PYTHON="$PYTHON_INSTALL_DIR/bin/python3"
if [ ! -d "$VENV_DIR" ]; then
    echo "[build_env] Creating virtualenv at $VENV_DIR..."
    $PYTHON -m venv "$VENV_DIR"
fi

# Activate virtualenv now
# Next time, it'll be activated automatically by container_init.sh
source "$VENV_DIR/bin/activate"
echo "[build_env] Python environment ready: $($PYTHON --version) in $VENV_DIR"

# Install uv
if ! command -v uv >/dev/null 2>&1; then
    echo "[build_env] Installing uv package manager..."
    pip install uv
fi

# Install core Python tools
echo "[build_env] Installing base Python dependencies..."
pip install --upgrade pip setuptools wheel
pip install --upgrade build
pip install pycairo

# Install meson etc. which we'll need for gobject-introspection
echo "[build_env] Installing core build tools via uv..."
pip install meson ninja yasm
#pip install nasm # nasm from pip is not sufficient
# Install cmake from pip: manylinux2014 wheel, built against glibc 2.17,
# compatible with CentOS 8 (glibc 2.28). System cmake 3.20.2 is too old
# for current libavif (needs >= 3.22); brew cmake would need glibc 2.33+.
pip install cmake

# WARNING:
# I'm building gobject-introspection and, to fix errors when running
# check_gst-codecs in the build container, I'm now trying to also build glib.
# Observation: these two appear to have circular dependencies.
#
# gobject-introspection seems to depend on glib being installed because,
# without it, the build printed:
#   Dependency glib-2.0 found: NO. Found 2.78.0 but need: '>=2.82.0'
# Even though it then continued to build the glib subproject, the file
#   /opt/dep/lib64/girepository-1.0/GObject-2.0.typelib
# was missing at the end, causing the error.
#
# However, when I try to build glib earlier to address that, the build prints:
#   Run-time dependency gobject-introspection-1.0 found: YES 1.84.0
#   Dependency gobject-introspection-1.0 found: YES 1.84.0 (cached)
#   Program /opt/dep/bin/g-ir-scanner found: YES (/opt/dep/bin/g-ir-scanner)
# indicating it might not build before gobject-introspection.

# Starting with GLib 2.79.0 and gobject-introspection 1.79.0, there is a circular dependency between the two projects.
# https://discourse.gnome.org/t/dealing-with-glib-and-gobject-introspection-circular-dependency/18701
# => Let's build 2.78 and 1.78 max...?

# Build GLib [with introspection support] function (called twice)
build_glib() {
    local glib_version="${1:-2.78.0}" # e.g., 2.78.0
    local glib_minor="${glib_version#2.}" # strips '2.'
    local glib_minor="${glib_minor%%.*}" # strips '.0'

    #local with_introspection="${2:-1}"
    echo "[build_env] Building GLib $glib_version"
    pushd "$BUILD_DIR"
    wget -nc https://download.gnome.org/sources/glib/${glib_version%.*}/glib-$glib_version.tar.xz
    tar xf glib-$glib_version.tar.xz
    pushd glib-$glib_version

    local meson_opts=(--wipe builddir --prefix="$DEPS_PREFIX" -Dselinux=disabled)
    # For GLib < 2.66 or < 2.74, introspection must be explicitly enabled
    #if [ "$with_introspection" = "1" ]; then
    #    if [ "$glib_minor" -lt 74 ]; then
    #        meson_opts+=(-Dintrospection=enabled) # meson.build:1:0: ERROR: Unknown options: "introspection"
    #    fi
    #fi
    meson setup "${meson_opts[@]}" && ninja -C builddir && ninja -C builddir install
    rc=$?

    popd
    popd
    if [ $rc -ne 0 ]; then
        echo "[build_env] ERROR: Failed to build GLib"
        return $rc
    fi
    echo "[build_env] GLib $glib_version built and installed to $DEPS_PREFIX"
}

# Set up Linuxbrew to install more dependencies if USE_BREW is not explicitly set to 0
# Note we may install tools like meson here but no libraries yet, see build_prereqs.sh
# nasm from brew (not pip package) for openh264
if [ "${USE_BREW:-1}" != "0" ]; then
    echo "[build_env] Setting up Linuxbrew..."
    bash /usr/local/bin/setup_linuxbrew.sh
    # Install build-time tools and libraries (prebuilt bottles)
    echo "[setup_brew] Installing build-time tools and libraries via brew..."
    brew install cmake
    brew install llvm
    brew install xxhash
    brew install lz4
    brew install yasm
    brew install nasm
    brew install diffutils
    # NOTE: brew's ld binary poisons the link path. It is pulled in by brew install
    # of cmake/llvm (binutils is a transitive dep of brew's gcc/git). brew's ld was
    # built against newer glibc and embeds the brew Cellar/opt dirs as its default
    # search libs for NEEDED deps, so it silently links brew's libresolv/libmount/
    # libz/etc. instead of the CentOS 8 ones. The build error was:
    #   ld: /home/linuxbrew/.linuxbrew/opt/glibc/lib/libresolv.so.2: undefined
    #       reference to `dn_skipname@GLIBC_2.34'
    #   ld: /home/linuxbrew/.linuxbrew/lib/libmount.so.1: undefined reference to
    #       `fstat@GLIBC_2.33'  (etc, GLIBC_2.34/2.36/2.38 vs host glibc 2.28)
    # Unlinking binutils keeps the newer brew tools (cmake, clang, ...) first in
    # PATH while letting gcc's collect2 find the system ld (binutils 2.30).
    brew unlink binutils 2>/dev/null || true
else
    echo "[build_env] USE_BREW=0, skipping Homebrew setup."
fi

# Check for girepository-2.0, build it unless USE_BREW_HEADERS_LIBS=1 (installing via brew)
if [ "${USE_BREW_HEADERS_LIBS:-0}" != "1" ]; then

    # Build PCRE2, required for gobject-introspection
    PCRE2_VERSION="10.42"
    pushd "$BUILD_DIR"
    wget -nc https://github.com/PCRE2Project/pcre2/releases/download/pcre2-$PCRE2_VERSION/pcre2-$PCRE2_VERSION.tar.gz
    tar xf pcre2-$PCRE2_VERSION.tar.gz
    cd pcre2-$PCRE2_VERSION
    ./configure --prefix="$DEPS_PREFIX" && \
    make -j4 && \
    make install
    rc=$?
    popd
    if [ $rc -ne 0 ]; then
        echo "[build_env] ERROR: Failed to build PCRE2"
        exit $rc
    fi
    echo "[build_env] PCRE2 $PCRE2_VERSION built and installed to $DEPS_PREFIX"

    # Version of GI (gobject-introspection) + GLib
    # We build GLib twice to break the historical GLib ↔ gobject‑introspection bootstrap loop.
    GI_VERSION="1.78"
    GI_VERSION="1.82"
    GI_VERSION="1.64"
    GI_VERSION="1.56"
    GI_VERSION_MINOR="${GI_VERSION#*.}"
    GI_VERSION_MICRO="1"
    GLIB_VERSION="2.82.0"
    GLIB_VERSION="2.64.0"
    GLIB_VERSION="2.56.0"
    OS_GLIB_VERSION="$(pkg-config --modversion glib-2.0 2>/dev/null)"
    OS_GLIB_MINOR="$(echo "$OS_GLIB_VERSION" | cut -d. -f2)"

    # Build GLib (required for gobject-introspection)
    # 1st GLib build (introspection disabled):
    #   Purpose: Provide the GLib headers, pkg‑config files, and core shared libs
    #   (libglib-2.0.so, libgobject-2.0.so, libgio-2.0.so, etc.) that
    #   gobject‑introspection needs to compile itself.
    #   GI’s scanner/compilation tools link to and use these libs at build time.
    if [ "${GI_VERSION_MINOR:-0}" -gt "${OS_GLIB_MINOR:-0}" ]; then # using GLib from OS, if possible
        echo "[build_env] GLib $GLIB_VERSION > ${OS_GLIB_VERSION:-0}, building GLib $GLIB_VERSION..."
    fi
    if [ "${GI_VERSION_MINOR:-0}" -gt 56 ]; then # 56 hardcoded for now, see patch for GI 1.56
        build_glib "$GLIB_VERSION"
    fi

    # IMPORTANT: We intentionally do NOT ship GLib from the toolchain prefix.
    # Reason: We rely on the target's system GLib to keep the ABI floor low.
    # Shipping a newer libglib-2.0.so* (or friends) would silently raise the
    # minimum GLib requirement and can break older targets.

    # Build gobject-introspection to provide girepository-2.0
    # gobject-introspection-1.84.0:
    # Dependency glib-2.0 found: NO. Found 2.56.4 but need: '>=2.82.0'
    # gobject-introspection-1.78.0 + GLib-2.78.0:
    # Run-time dependency glib-2.0 found: YES 2.78.0
    echo "[build_env] girepository-2.0 not found, installing gobject-introspection..."
    echo "[DEBUG] pkg-config --cflags libpcre2-8: $(PKG_CONFIG_PATH="$PKG_CONFIG_PATH" pkg-config --cflags libpcre2-8 2>&1)"
    echo "[DEBUG] pkg-config --libs libpcre2-8: $(PKG_CONFIG_PATH="$PKG_CONFIG_PATH" pkg-config --libs libpcre2-8 2>&1)"
    echo "[build_env] Building gobject-introspection $GI_VERSION..."
    pushd "$BUILD_DIR"
    wget -nc https://download.gnome.org/sources/gobject-introspection/$GI_VERSION/gobject-introspection-$GI_VERSION.$GI_VERSION_MICRO.tar.xz
    tar xf gobject-introspection-$GI_VERSION.$GI_VERSION_MICRO.tar.xz
    pushd gobject-introspection-$GI_VERSION.$GI_VERSION_MICRO
    # Patch gobject-introspection < 1.82 to fix build errors
    if [ "$GI_VERSION_MINOR" -eq 56 ]; then
        echo "[build_env] Applying patches for version 56..."
        patch -p0 </var/tmp/gi-156-fix-msvc-bug.patch
        patch -p0 </var/tmp/gi-156-fix-xml-bug.patch
        cp -vf /var/tmp/python-config-wrapper.sh /opt/pyenv/bin/python-config # for configure expecting python-config
    elif [ "$GI_VERSION_MINOR" -lt 82 ]; then
        echo "[build_env] Applying gi-178-fix-msvc-bug.patch to giscanner/ccompiler.py..."
        patch -p0 -N </var/tmp/gi-178-fix-msvc-bug.patch || true # TODO
    fi
    # cc1: warning: /install/include/python3.10: No such file or directory [-Wmissing-include-dirs]
    # => PKG_CONFIG_PATH
    if [ "$GI_VERSION_MINOR" -eq 56 ]; then
        # giscanner 1.56 does not build on Python 3.12:
        #   giscanner/giscannermodule.c:68:20: error: lvalue required as left operand of assignment
        #        Py_TYPE(&type) = &PyType_Type;
        #        ^
        # and giscanner/libtoolimporter.py:26 does `import imp`, removed in 3.12.
        # Build this build-time tool with the distro's platform Python 3.6;
        # it has no effect on the bundled libraries or their ABI floor.
        CC=gcc CXX=g++ GI_HOST_CC=gcc \
        PKG_CONFIG_PATH=$DEPS_PREFIX/lib64/pkgconfig:$DEPS_PREFIX/lib/pkgconfig:/usr/lib64/pkgconfig \
        ./configure --prefix="$DEPS_PREFIX" --disable-tests --disable-gtk-doc \
            --with-python=/usr/libexec/platform-python && \
        make -j4 && \
        make install
    else
        CC=gcc CXX=g++ GI_HOST_CC=gcc \
        PKG_CONFIG_PATH=$DEPS_PREFIX/lib64/pkgconfig:$DEPS_PREFIX/lib/pkgconfig:/usr/lib64/pkgconfig \
        meson setup --wipe builddir --prefix="$DEPS_PREFIX" && \
        ninja -C builddir && \
        ninja -C builddir install
    fi
    rc=$?
    popd
    popd
    if [ $rc -ne 0 ]; then
        echo "[build_env] ERROR: Failed to build gobject-introspection"
        exit $rc
    fi
    echo "[build_env] gobject-introspection built and environment variables set."

    # Install Python module - requires gobject-introspection to be built first
    # ../meson.build:31:9: ERROR: Dependency 'girepository-2.0' is required but not found.
    echo "[build_env] Installing pygobject"
    pip install pygobject
    if [ $? -ne 0 ]; then
        echo "[build_env] ERROR: Failed to install pygobject"
        echo "[build_env] will try to build it from source"
    fi

    # 2nd GLib build (introspection enabled):
    #   Purpose: Generate and install GLib’s own introspection data
    #   (.gir XML and .typelib binaries for GLib-2.0, GObject-2.0, Gio-2.0)
    #   using g-ir-scanner / g-ir-compiler from the just‑built gobject‑introspection.
    #   Without this rebuild, those typelibs would be missing.
    if [ "${GI_VERSION_MINOR:-0}" -gt 56 ]; then
        build_glib "$GLIB_VERSION"
    fi

    # After second GLib build, verify GObject-2.0.typelib exists
    # Usually in lib64, but gobject-introspection 1.56 installs it to lib
    if [ ! -f "$DEPS_PREFIX/lib/girepository-1.0/GObject-2.0.typelib" ] && [ ! -f "$DEPS_PREFIX/lib64/girepository-1.0/GObject-2.0.typelib" ]; then
        echo "[build_env] WARNING: GObject-2.0.typelib is missing after GLib rebuild!"
        echo "[build_env] This may prevent Python GObject introspection and GStreamer plugin detection."
        echo "[build_env] Check your build logs and ensure gobject-introspection tools are available during GLib build."
        exit 1
    fi

    # Build pycairo to provide py3cairo
    # fails (pkg-config) if GI/GLib is 1.78
    if ! pkg-config --exists py3cairo; then
        echo "[build_env] py3cairo not found, building pycairo..."
        PYCAIRO_VERSION="1.24.0"
        pushd "$BUILD_DIR"
        wget -nc https://github.com/pygobject/pycairo/releases/download/v$PYCAIRO_VERSION/pycairo-$PYCAIRO_VERSION.tar.gz
        tar xf pycairo-$PYCAIRO_VERSION.tar.gz
        cd pycairo-$PYCAIRO_VERSION
        meson setup builddir --prefix="$DEPS_PREFIX" && \
        ninja -C builddir && \
        ninja -C builddir install
        rc=$?
        popd
        if [ $rc -ne 0 ]; then
            echo "[build_env] ERROR: Failed to build pycairo"
            exit $rc
        fi
        echo "[build_env] pycairo built and installed to $DEPS_PREFIX"
    fi

    # Build PyGObject to provide pygobject-3.0.pc for build-time integration
    if ! pkg-config --exists pygobject-3.0; then
        echo "[build_env] pygobject-3.0.pc not found, building PyGObject from source..."
        PYGOBJECT_VERSION="3.46.0"
        PYGOBJECT_VERSION="3.34.0" # error: call to undeclared function '_PyUnicode_AsStringAndSize';
        PYGOBJECT_VERSION="3.40.0" # to remain compatible with gobject-introspection 1.56
        PYGOBJECT_VERSION="3.44.2" # Python 3.12 support while still accepting GI 1.56 / glib 2.56
        pushd "$BUILD_DIR"
        wget -nc https://download.gnome.org/sources/pygobject/${PYGOBJECT_VERSION%.*}/pygobject-$PYGOBJECT_VERSION.tar.xz
        tar xf pygobject-$PYGOBJECT_VERSION.tar.xz
        cd pygobject-$PYGOBJECT_VERSION
        meson setup builddir --prefix="$DEPS_PREFIX" -Dtests=false && \
        ninja -C builddir && \
        ninja -C builddir install
        rc=$?
        pip install .
        popd
        if [ $rc -ne 0 ]; then
            echo "[build_env] ERROR: Failed to build PyGObject"
            exit $rc
        fi
        pip show pygobject
        echo "[build_env] PyGObject built and installed to $DEPS_PREFIX"
    fi

fi

# Careful with libs from Brew:
# (pyenv) /usr/bin/xz --version
# xz (XZ Utils) 5.2.4
# liblzma 5.2.4
# (pyenv) which xz
# /home/linuxbrew/.linuxbrew/bin/xz
# (pyenv) /home/linuxbrew/.linuxbrew/bin/xz --version
# /home/linuxbrew/.linuxbrew/bin/xz: /lib64/libc.so.6: version `GLIBC_2.32' not found (required by /home/linuxbrew/.linuxbrew/bin/xz)
# /home/linuxbrew/.linuxbrew/bin/xz: /lib64/libc.so.6: version `GLIBC_2.33' not found (required by /home/linuxbrew/.linuxbrew/bin/xz)
# /home/linuxbrew/.linuxbrew/bin/xz: /lib64/libc.so.6: version `GLIBC_2.34' not found (required by /home/linuxbrew/.linuxbrew/bin/xz)
# /home/linuxbrew/.linuxbrew/bin/xz: /lib64/libc.so.6: version `GLIBC_2.32' not found (required by /home/linuxbrew/.linuxbrew/Cellar/xz/5.8.1/lib/liblzma.so.5)
# /home/linuxbrew/.linuxbrew/bin/xz: /lib64/libc.so.6: version `GLIBC_2.34' not found (required by /home/linuxbrew/.linuxbrew/Cellar/xz/5.8.1/lib/liblzma.so.5)

echo "[build_env] Done."
