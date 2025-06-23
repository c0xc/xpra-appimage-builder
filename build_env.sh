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
pip install pycairo pygobject

# Install meson etc. which we'll need for gobject-introspection
echo "[build_env] Installing core build tools via uv..."
#uv pip install meson ninja yasm nasm pkg-config cmake autoconf automake libtool wget
pip install meson ninja yasm nasm 

# Set common prefix for dependencies built from source
# TODO 
DEPS_PREFIX="/opt/dep"
mkdir -p "$DEPS_PREFIX"

# Check for girepository-2.0, build it unless USE_BREW_HEADERS_LIBS=1 (installing via brew)
if [ "${USE_BREW_HEADERS_LIBS:-0}" != "1" ]; then
    # Build PCRE2 for gobject-introspection
    PCRE2_VERSION="10.42"
    mkdir -p /tmp/pcre2_build && pushd /tmp/pcre2_build
    wget https://github.com/PCRE2Project/pcre2/releases/download/pcre2-$PCRE2_VERSION/pcre2-$PCRE2_VERSION.tar.gz
    tar xf pcre2-$PCRE2_VERSION.tar.gz
    cd pcre2-$PCRE2_VERSION
    ./configure --prefix=/opt/pcre2
    make -j4
    make install
    popd
    # Export paths
    export PKG_CONFIG_PATH="/opt/pcre2/lib/pkgconfig:$PKG_CONFIG_PATH"
    export LD_LIBRARY_PATH="/opt/pcre2/lib:$LD_LIBRARY_PATH"

    # girepository-2.0 / gobject-introspection
    if ! pkg-config --exists girepository-2.0; then
        echo "[build_env] girepository-2.0 not found, installing gobject-introspection..."
        old_wd=$PWD
        # Build and install gobject-introspection in /opt/gobject-introspection if not present
        GI_PREFIX="/opt/gobject-introspection"
        GI_VERSION="1.84"
        # Use gcc instead of clang
        export CC=gcc
        export CXX=g++
        export GI_HOST_CC=gcc
        echo "[build_env] Building gobject-introspection $GI_VERSION in $GI_PREFIX..."
        mkdir -p /tmp/gi_build && cd /tmp/gi_build
        wget https://download.gnome.org/sources/gobject-introspection/$GI_VERSION/gobject-introspection-$GI_VERSION.0.tar.xz
        tar xf gobject-introspection-$GI_VERSION.0.tar.xz
        cd gobject-introspection-$GI_VERSION.0
        meson setup builddir --prefix="$GI_PREFIX"
        ninja -C builddir
        ninja -C builddir install
        [ -n "$old_wd" ] && cd "$old_wd"
        # Export paths for pkg-config and libraries (for this shell and child processes)
        export PKG_CONFIG_PATH="$GI_PREFIX/lib/pkgconfig:$GI_PREFIX/lib64/pkgconfig:$PKG_CONFIG_PATH"
        export LD_LIBRARY_PATH="$GI_PREFIX/lib:$GI_PREFIX/lib64:$LD_LIBRARY_PATH"
        export GI_TYPELIB_PATH="$GI_PREFIX/lib/girepository-1.0:$GI_PREFIX/lib64/girepository-1.0:$GI_TYPELIB_PATH"
        echo "[build_env] gobject-introspection built and environment variables set."

        # Install Python module - requires gobject-introspection to be built first
        # ../meson.build:31:9: ERROR: Dependency 'girepository-2.0' is required but not found.
        echo "[build_env] Installing pygobject"
        pip install pygobject
        if [ $? -ne 0 ]; then
            echo "[build_env] ERROR: Failed to install pygobject"
            exit 1
        fi
    fi
fi

# Set up Linuxbrew to install more dependencies if USE_BREW is not explicitly set to 0
# Note we may install tools like meson here but no libraries yet, see build_prereqs.sh
if [ "${USE_BREW:-1}" != "0" ]; then
    echo "[build_env] Setting up Linuxbrew..."
    bash /usr/local/bin/setup_linuxbrew.sh
else
    echo "[build_env] USE_BREW=0, skipping Homebrew setup."
fi

echo "[build_env] Done."
