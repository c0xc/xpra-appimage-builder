#!/bin/bash
# set -e might cause silent failures (uncaught error skipping the rest of the script)

# build_env.sh: Prepare Python environment for xpra build

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

# Set Python installation path - use user-writable location
PYTHON_INSTALL_DIR="$HOME/python3"
VENV_DIR="$HOME/pyenv"

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
    # Create/update symlink for python3 in $HOME/.local/bin
    mkdir -p "$HOME/.local/bin"
    ln -sf "$PYTHON_INSTALL_DIR/bin/python3" "$HOME/.local/bin/python3"
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

# Set up Linuxbrew to install more dependencies
if [ -x /usr/local/bin/setup_linuxbrew.sh ]; then
    echo "[build_env] Setting up Linuxbrew..."
    bash /usr/local/bin/setup_linuxbrew.sh
else
    echo "[build_env] [WARN] setup_linuxbrew.sh not found, skipping Homebrew setup."
fi

# Install core dependencies via brew
echo "[setup_brew] Installing dependencies via brew..."
brew install xxhash
brew install lz4

# Install newer CMake version (slow)
if ! command -v cmake >/dev/null 2>&1; then
    echo "[setup_brew] Installing cmake..."
    brew install cmake
else
    echo "[setup_brew] CMake already installed, skipping..."
fi

# Modern multimedia codecs and tools (for Xpra, video, audio, etc)
# These are too old or missing in CentOS 8 repos, so we use Homebrew.
# -----------------------------------------------------------------------------
echo "[setup_brew] Installing multimedia codecs and libraries via brew..."
brew install ffmpeg libvpx webp
brew install opus x264 #x265

# Print installed versions
echo "[setup_brew] Installed package versions:"
brew list --versions xxhash
brew list --versions lz4

# Optionally build ffmpeg and codecs from source if needed
if [ -x /usr/local/bin/build_ffmpeg_codecs.sh ]; then
    # echo "[build_env] Optionally building ffmpeg and codecs from source (see build_ffmpeg_codecs.sh)..."
    # bash /usr/local/bin/build_ffmpeg_codecs.sh
else
    echo "[build_env] build_ffmpeg_codecs.sh not found, skipping source build of ffmpeg/codecs."
fi

echo "[build_env] Done."
