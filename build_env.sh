#!/bin/bash
# not using set -e, might cause silent failures (uncaught error skipping the rest of the script)

# build_env.sh: Prepare Python environment for build
# Some core tools are also installed - via Brew unless USE_BREW=0
# For example meson (missing in CentOS 8)
# No [pre-built] libraries are installed here, as this is still
# part of the Podman image build process, that decision is made later.

# Check if jq is available
if ! command -v jq >/dev/null 2>&1; then
    echo "[build_env] ERROR: jq is required but not found"
    exit 1
fi

# Set Python version to be installed (can be overridden); OS Python is too old
PYTHON_VERSION="${PYTHON_VERSION:-3.10}"
echo "[build_env] Starting environment preparation for Python $PYTHON_VERSION"

# Find the latest Python build date
echo "[build_env] Finding latest release for Python $PYTHON_VERSION..."
LATEST_RELEASE=$(wget -q -O- https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest | grep tag_name | cut -d'"' -f4)
PYTHON_BUILD_DATE="${PYTHON_BUILD_DATE:-$LATEST_RELEASE}"
echo "[build_env] Using build date: $PYTHON_BUILD_DATE"

# Find the exact Python version if only the series is specified
# so if 3.10 is specified, find a matching 3.10.x release
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
#pip install nasm 

# Common prefix for dependencies built from source, set in container_init.sh
DEPS_PREFIX="/opt/dep" # set here because build_env runs before container_init.sh
echo "[build_env] Setting up dependencies prefix: $DEPS_PREFIX"
if [ -z "$DEPS_PREFIX" ]; then
    echo "[build_env] ERROR: DEPS_PREFIX is not set, please set it in container_init.sh"
    exit 1
fi
mkdir -p "$DEPS_PREFIX"
# Build environment variables, duplicated from container_init.sh # TODO
export PKG_CONFIG_PATH="$DEPS_PREFIX/lib/pkgconfig:$DEPS_PREFIX/lib64/pkgconfig:$PKG_CONFIG_PATH"
export LD_LIBRARY_PATH="$DEPS_PREFIX/lib:$DEPS_PREFIX/lib64:$LD_LIBRARY_PATH"
export GI_TYPELIB_PATH="$DEPS_PREFIX/lib/girepository-1.0:$DEPS_PREFIX/lib64/girepository-1.0:$GI_TYPELIB_PATH"

# Use gcc instead of clang
export CC=gcc
export CXX=g++
export GI_HOST_CC=gcc

# Check for girepository-2.0, build it unless USE_BREW_HEADERS_LIBS=1 (installing via brew)
if [ "${USE_BREW_HEADERS_LIBS:-0}" != "1" ]; then
    # Build PCRE2, required for gobject-introspection
    PCRE2_VERSION="10.42"
    mkdir -p /tmp/pcre2_build && pushd /tmp/pcre2_build
    wget https://github.com/PCRE2Project/pcre2/releases/download/pcre2-$PCRE2_VERSION/pcre2-$PCRE2_VERSION.tar.gz
    tar xf pcre2-$PCRE2_VERSION.tar.gz
    cd pcre2-$PCRE2_VERSION
    #./configure --prefix=/opt/pcre2
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

    # girepository-2.0 / gobject-introspection
    # Dependency glib-2.0 found: NO. Found 2.56.4 but need: '>=2.82.0'
    # Run-time dependency glib-2.0 found: NO (tried pkgconfig and cmake)
    if ! pkg-config --exists girepository-2.0; then
        echo "[build_env] girepository-2.0 not found, installing gobject-introspection..."
        old_wd=$PWD
        GI_VERSION="1.84"
        echo "[DEBUG] pkg-config --cflags libpcre2-8: $(PKG_CONFIG_PATH="$PKG_CONFIG_PATH" pkg-config --cflags libpcre2-8 2>&1)"
        echo "[DEBUG] pkg-config --libs libpcre2-8: $(PKG_CONFIG_PATH="$PKG_CONFIG_PATH" pkg-config --libs libpcre2-8 2>&1)"
        echo "[build_env] Building gobject-introspection $GI_VERSION..."
        mkdir -p /tmp/gi_build && cd /tmp/gi_build
        wget https://download.gnome.org/sources/gobject-introspection/$GI_VERSION/gobject-introspection-$GI_VERSION.0.tar.xz
        tar xf gobject-introspection-$GI_VERSION.0.tar.xz
        cd gobject-introspection-$GI_VERSION.0
        (
            export CC=gcc CXX=g++ GI_HOST_CC=gcc
            meson setup --wipe builddir --prefix="$DEPS_PREFIX" && \
            ninja -C builddir && \
            ninja -C builddir install
            # We need GLib-2.0.typelib later but apparently, those options will prevent it from being built:
            # -Ddoctool=disabled -Dtests=false 
        )
        #meson setup builddir --prefix="$DEPS_PREFIX" && \
        #ninja -C builddir && \
        #ninja -C builddir install
        rc=$?
        [ -n "$old_wd" ] && cd "$old_wd"
        if [ $rc -ne 0 ]; then
            echo "[build_env] ERROR: Failed to build gobject-introspection"
            exit $rc
        fi
        echo "[build_env] gobject-introspection built and environment variables set."

        # Sometimes GLib-2.0.typelib is not installed automatically
        # This is a workaround to ensure it is installed
        # [142/149] /tmp/gi_build/gobject-introspection-1.84.0/builddir/tools/g-ir-compiler -o gir/GLib-2.0.typelib gir/GLib-2.0.gir --includedir /tmp/gi_build/gobject-introspection-1.84.0/builddir/gir --includedir /tmp/gi_build/gobject-introspection-1.84.0/gir
        #echo "[build_env] Manually installing typelib files..."
        ## Make sure we have a directory to install them to
        #mkdir -p "$DEPS_PREFIX/lib64/girepository-1.0/"
        #cd /tmp/gi_build/gobject-introspection-1.84.0
        ## Copy all the generated .typelib files to our prefix
        #echo "[build_env] Copying typelib files from builddir/gir/ to $DEPS_PREFIX/lib/girepository-1.0/"
        #find builddir/gir/ -name "*.typelib" -exec cp {} "$DEPS_PREFIX/lib/girepository-1.0/" \;
        #cd "$old_wd"
        #echo "[build_env] Installed typelib files:"
        #find "$DEPS_PREFIX/lib/girepository-1.0/" -name "*.typelib" | sort

        # Install Python module - requires gobject-introspection to be built first
        # ../meson.build:31:9: ERROR: Dependency 'girepository-2.0' is required but not found.
        echo "[build_env] Installing pygobject"
        pip install pygobject
        if [ $? -ne 0 ]; then
            echo "[build_env] ERROR: Failed to install pygobject"
            exit 1
        fi

    fi

    # Build pycairo to provide py3cairo
    if ! pkg-config --exists py3cairo; then
        echo "[build_env] py3cairo not found, building pycairo..."
        old_wd=$PWD
        PYCAIRO_VERSION="1.24.0"
        mkdir -p /tmp/pycairo_build
        cd /tmp/pycairo_build
        wget https://github.com/pygobject/pycairo/releases/download/v$PYCAIRO_VERSION/pycairo-$PYCAIRO_VERSION.tar.gz
        tar xf pycairo-$PYCAIRO_VERSION.tar.gz
        cd pycairo-$PYCAIRO_VERSION
        meson setup builddir --prefix="$DEPS_PREFIX" && \
        ninja -C builddir && \
        ninja -C builddir install
        rc=$?
        [ -n "$old_wd" ] && cd "$old_wd"
        if [ $rc -ne 0 ]; then
            echo "[build_env] ERROR: Failed to build pycairo"
            exit $rc
        fi
        echo "[build_env] pycairo built and installed to $DEPS_PREFIX"
        # Ensure PKG_CONFIG_PATH includes the new .pc file
        #export PKG_CONFIG_PATH="$DEPS_PREFIX/lib/pkgconfig:$DEPS_PREFIX/lib64/pkgconfig:$PKG_CONFIG_PATH"
    fi

    # Build PyGObject to provide pygobject-3.0.pc for build-time integration
    if ! pkg-config --exists pygobject-3.0; then
        echo "[build_env] pygobject-3.0.pc not found, building PyGObject from source..."
        old_wd=$PWD
        PYGOBJECT_VERSION="3.46.0"
        mkdir -p /tmp/pygobject_build
        cd /tmp/pygobject_build
        wget https://download.gnome.org/sources/pygobject/${PYGOBJECT_VERSION%.*}/pygobject-$PYGOBJECT_VERSION.tar.xz
        tar xf pygobject-$PYGOBJECT_VERSION.tar.xz
        cd pygobject-$PYGOBJECT_VERSION
        meson setup builddir --prefix="$DEPS_PREFIX" -Dtests=false && \
        ninja -C builddir && \
        ninja -C builddir install
        rc=$?
        [ -n "$old_wd" ] && cd "$old_wd"
        if [ $rc -ne 0 ]; then
            echo "[build_env] ERROR: Failed to build PyGObject"
            exit $rc
        fi
        echo "[build_env] PyGObject built and installed to $DEPS_PREFIX"
        # Ensure PKG_CONFIG_PATH includes the new .pc file
        #export PKG_CONFIG_PATH="$DEPS_PREFIX/lib/pkgconfig:$DEPS_PREFIX/lib6
    fi

fi

# Set up Linuxbrew to install more dependencies if USE_BREW is not explicitly set to 0
# Note we may install tools like meson here but no libraries yet, see build_prereqs.sh
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
else
    echo "[build_env] USE_BREW=0, skipping Homebrew setup."
fi

# Careful with libs from Brew
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
