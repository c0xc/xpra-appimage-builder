#!/bin/bash
set -e

# build_env.sh: Prepare Python environment for xpra build

# Use version info from file if present, else from env or a default
PYTHON_VERSION_FILE="${PYTHON_VERSION_FILE:-/var/tmp/PYTHON_VERSION_INFO}"
if [ -f "$PYTHON_VERSION_FILE" ]; then
    source "$PYTHON_VERSION_FILE"
fi

# Set default or use provided Python version
PYTHON_VERSION="${PYTHON_VERSION:-3.10}"
echo "[build_env] Starting environment preparation for Python $PYTHON_VERSION"

# Check if we can write to the default location, if not use home directory
if [ ! -w "$(dirname "$PYTHON_VERSION_FILE")" ]; then
    # Default to home directory if original location is not writable
    PYTHON_VERSION_FILE="$HOME/.python_version_info"
    echo "[build_env] Warning: $(dirname "$PYTHON_VERSION_FILE") not writable, using $PYTHON_VERSION_FILE instead"
fi

# Find the latest Python build date
echo "[build_env] Finding latest release for Python $PYTHON_VERSION..."
LATEST_RELEASE=$(wget -q -O- https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest | grep tag_name | cut -d'"' -f4)
PYTHON_BUILD_DATE="${PYTHON_BUILD_DATE:-$LATEST_RELEASE}"
echo "[build_env] Using build date: $PYTHON_BUILD_DATE"

# Find the exact Python version if only the series is specified
if [[ "$PYTHON_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo "[build_env] Finding compatible version for Python $PYTHON_VERSION series..."
    
    # Get release assets from GitHub API
    RELEASE_DATA=$(wget -q -O- "https://api.github.com/repos/astral-sh/python-build-standalone/releases/tags/$PYTHON_BUILD_DATE")
    
    # Check if jq is available (required for JSON parsing)
    if ! command -v jq >/dev/null 2>&1; then
        echo "[build_env] ERROR: jq is required for parsing release data but not found"
        echo "[build_env] Please install jq in your container image"
        exit 1
    fi
    
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

# Set URL for Python download - at this point PYTHON_VERSION should be a full version
PYTHON_BS_URL="https://github.com/astral-sh/python-build-standalone/releases/download/${PYTHON_BUILD_DATE}/cpython-${PYTHON_VERSION}+${PYTHON_BUILD_DATE}-x86_64-unknown-linux-gnu-install_only.tar.gz"

echo "[build_env] Download URL: $PYTHON_BS_URL"

# Save version info for other scripts
if ! cat > "$PYTHON_VERSION_FILE" 2>/dev/null << EOF
PYTHON_VERSION=$PYTHON_VERSION
PYTHON_BUILD_DATE=$PYTHON_BUILD_DATE
PYTHON_BS_URL=$PYTHON_BS_URL
EOF
then
    # If writing fails, fall back to the home directory
    PYTHON_VERSION_FILE="$HOME/.python_version_info"
    echo "[build_env] Using $PYTHON_VERSION_FILE instead"
    mkdir -p $(dirname "$PYTHON_VERSION_FILE")
    cat > "$PYTHON_VERSION_FILE" << EOF
PYTHON_VERSION=$PYTHON_VERSION
PYTHON_BUILD_DATE=$PYTHON_BUILD_DATE
PYTHON_BS_URL=$PYTHON_BS_URL
EOF
fi

# Ensure the file is readable by anyone
chmod 644 "$PYTHON_VERSION_FILE"
echo "[build_env] Saved Python version info to $PYTHON_VERSION_FILE"

# Set Python installation paths - use user-writable locations
PYTHON_INSTALL_DIR="$HOME/python3"
VENV_DIR="$HOME/pyenv"

# Optionally set up Linuxbrew for modern build tools
#if [ -x /usr/local/bin/setup_linuxbrew.sh ]; then
#    echo "[build_env] Setting up Linuxbrew (Homebrew for Linux) for modern build tools..."
#    bash /usr/local/bin/setup_linuxbrew.sh
#else
#    echo "[build_env] [WARN] setup_linuxbrew.sh not found, skipping Homebrew setup."
#fi

# Download and extract python-build-standalone
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
else
    echo "[build_env] Using existing Python installation at $PYTHON_INSTALL_DIR"
fi

# Create virtualenv
PYTHON="$PYTHON_INSTALL_DIR/bin/python3"
if [ ! -d "$VENV_DIR" ]; then
    echo "[build_env] Creating virtualenv at $VENV_DIR..."
    $PYTHON -m venv "$VENV_DIR"
fi

# Activate virtualenv
source "$VENV_DIR/bin/activate"
echo "[build_env] Python environment ready: $($PYTHON --version) in $VENV_DIR"

# Install uv
if ! command -v uv >/dev/null 2>&1; then
    echo "[build_env] Installing uv package manager..."
    pip install uv
fi

# Install basic Python dependencies
echo "[build_env] Installing base Python dependencies..."
pip install --upgrade pip setuptools wheel

# Install Python dependencies for Xpra if requirements file exists
if [ -f "/usr/local/requirements.txt" ]; then
    echo "[build_env] Installing Python dependencies from /usr/local/requirements.txt"
    pip install -r /usr/local/requirements.txt
elif [ -f "/workspace/requirements.txt" ]; then
    echo "[build_env] Installing Python dependencies from /workspace/requirements.txt"
    pip install -r /workspace/requirements.txt
fi

echo "[build_env] Done."
