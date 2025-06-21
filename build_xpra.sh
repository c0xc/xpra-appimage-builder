#!/bin/bash
set -e

# build_xpra.sh: Build and install xpra in the prepared Python environment

# This should run in activated virtualenv, initialized by container_init.sh
if [ -z "$VIRTUAL_ENV" ]; then
    echo "[build_xpra] ERROR: This script must be run in an activated virtual environment."
    echo "[build_xpra] Please source container_init.sh first to set up the environment."
    exit 1
fi

# Workspace, build directories
BASE_DIR="/workspace"
SRC_DIR="$BASE_DIR/src"
APPIMAGE_DIR="$BASE_DIR/appimage"
BUILD_DIR="$BASE_DIR/build"
cd "$SRC_DIR"

# Ensure linuxdeploy-x86_64.AppImage is available in $APPIMAGE_DIR
mkdir -p "$APPIMAGE_DIR"
cd "$APPIMAGE_DIR"
if [ ! -f linuxdeploy-x86_64.AppImage ]; then
    if [ -f "$BASE_DIR/linuxdeploy-x86_64.AppImage" ]; then
        echo "[build_xpra] Found linuxdeploy-x86_64.AppImage in $BASE_DIR, copying to $APPIMAGE_DIR."
        cp "$BASE_DIR/linuxdeploy-x86_64.AppImage" "$APPIMAGE_DIR/"
        chmod +x "$APPIMAGE_DIR/linuxdeploy-x86_64.AppImage"
    else
        echo "[build_xpra] Downloading linuxdeploy-x86_64.AppImage ..."
        wget -O linuxdeploy-x86_64.AppImage https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
        if [ $? -ne 0 ]; then
            echo "[build_xpra] ERROR: Failed to download linuxdeploy-x86_64.AppImage. Aborting." >&2
            exit 1
        fi
        chmod +x linuxdeploy-x86_64.AppImage
    fi
fi
# Return to source directory for build
cd "$SRC_DIR"

# Start build process
echo "[build_xpra] === Starting Xpra build process === ___________________________________________________"

# Ensure pkg-config can find both system and Homebrew .pc files
export PKG_CONFIG_PATH="/usr/lib64/pkgconfig:/usr/share/pkgconfig:/home/linuxbrew/.linuxbrew/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

# Detect Linuxbrew LLVM/Clang (may be newer than system version and if available, we prefer it)
if command -v clang | grep -q '/home/linuxbrew/.linuxbrew'; then
    export USE_BREW_HEADERS_LIBS=1
else
    export USE_BREW_HEADERS_LIBS=0
fi
# Set search paths so that pkg-config finds Homebrew X11 headers and libraries
if [ "$USE_BREW_HEADERS_LIBS" = "1" ]; then
    echo "[build_xpra] Homebrew LLVM/Clang detected: using Homebrew X11 headers and libraries."
    export LDFLAGS="-L/home/linuxbrew/.linuxbrew/lib ${LDFLAGS}"
    export CPPFLAGS="-I/home/linuxbrew/.linuxbrew/include ${CPPFLAGS}"
else
    echo "[build_xpra] Using system X11 headers and libraries (default include path)."
fi

# Check for Nvidia tools
if [ -z "${USE_NV+x}" ]; then
    if command -v nvcc >/dev/null 2>&1; then
        export USE_NV=1
    else
        export USE_NV=0
    fi
fi
XPRA_NV_BUILD_ARGS=""
if [ "$USE_NV" = "1" ]; then
    echo "[build_xpra] CUDA/nvcc detected: enabling NVIDIA/NVENC build options."
    XPRA_NV_BUILD_ARGS="--with-nvenc --with-nvidia"
fi

# Build wheel in build dir and install from there
mkdir -p "$BUILD_DIR"
WHEEL_FILE=$(ls "$BUILD_DIR"/xpra-*.whl 2>/dev/null | head -n1)
if [ -z "$WHEEL_FILE" ] || [ ! -f "$WHEEL_FILE" ]; then
    echo "[build_xpra] Building Xpra wheel in $BUILD_DIR ..."
    python -m build --wheel --outdir "$BUILD_DIR"
    WHEEL_FILE=$(ls "$BUILD_DIR"/xpra-*.whl 2>/dev/null | head -n1)
else
    echo "[build_xpra] Found existing wheel: $WHEEL_FILE, skipping build."
fi
if [ -z "$WHEEL_FILE" ] || [ ! -f "$WHEEL_FILE" ]; then
    echo "[build_xpra] ERROR: Xpra wheel not found after build step." >&2
    exit 1
fi
echo "[build_xpra] Installing Xpra wheel into current Python environment ..."
pip install "$WHEEL_FILE"

# Initialize AppDir structure
APPDIR="$APPIMAGE_DIR/AppDir"
export APPDIR
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share"
if [ $? -ne 0 ]; then
    echo "[build_xpra] ERROR: Failed to create AppDir structure at $APPDIR." >&2
    exit 1
fi

# Copy the entire python3 directory to AppDir for a fully self-contained Python
cp -a /opt/python3 "$APPDIR/usr/python3"

# Copy the venv from /opt/pyenv
cp -a /opt/pyenv "$APPDIR/usr/pyenv"

# Patch venv/bin symlinks to avoid dead links
VENV_BIN="$APPDIR/usr/pyenv/bin"
if [ -d "$VENV_BIN" ]; then
    # Fix python3 symlink to point to AppImage-internal python3 using a relative path
    if [ -L "$VENV_BIN/python3" ]; then
        rm "$VENV_BIN/python3"
        ln -s ../../python3/bin/python3 "$VENV_BIN/python3"
    fi
    # Fix python symlink to point to python3 (relative)
    if [ -L "$VENV_BIN/python" ]; then
        rm "$VENV_BIN/python"
        ln -s python3 "$VENV_BIN/python"
    fi
    # Fix python3.x symlink to point to python3 (relative)
    for pyver in "$VENV_BIN"/python3.*; do
        [ -e "$pyver" ] || continue
        if [ -L "$pyver" ]; then
            rm "$pyver"
            ln -s python3 "$pyver"
        fi
    done
fi

# Patch shebangs in venv/bin to use /usr/bin/env python3 for portability
find "$VENV_BIN" -type f -exec sed -i '1s|^#!.*/python3$|#!/usr/bin/env python3|' {} \;

# Patch pyvenv.cfg to remove or fix absolute paths
VENV_CFG="$APPDIR/usr/pyenv/pyvenv.cfg"
if [ -f "$VENV_CFG" ]; then
    sed -i 's|^home = .*|home = /usr/python3/bin|' "$VENV_CFG"
    sed -i '/^include-system-site-packages/d' "$VENV_CFG"
fi

# Patch .pth files to remove build-time absolute paths
find "$APPDIR/usr/pyenv/lib" -name '*.pth' -exec sed -i 's|/home/[^: ]*||g' {} \;

# Symlink xpra entrypoint to /usr/bin (avoiding duplicate)
ln -sf ../pyenv/bin/xpra "$APPDIR/usr/bin/xpra"
chmod +x "$APPDIR/usr/pyenv/bin/xpra"

# Create minimal desktop file and icon for linuxdeploy
cat > "$APPDIR/xpra.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Xpra
Exec=xpra
Icon=xpra
Categories=Utility;
EOF
convert -size 64x64 xc:lightgray "$APPDIR/xpra.png" || true

# Copy Homebrew libs
cp -r "$SRC_DIR" "$APPDIR/usr/share/xpra"
if [ "${USE_BREW_HEADERS_LIBS:-0}" = "1" ]; then
    echo "[build_xpra] USE_BREW_HEADERS_LIBS=1: bundling Homebrew libraries into AppDir..."
    BREW_LIB="/home/linuxbrew/.linuxbrew/lib"
    APPDIR_LIB="$APPDIR/usr/lib"
    mkdir -p "$APPDIR_LIB"
    find "$BREW_LIB" -maxdepth 1 -type f -name '*.so*' -exec cp -a {} "$APPDIR_LIB/" \;
    find "$BREW_LIB" -maxdepth 1 -type l -name '*.so*' -exec cp -a {} "$APPDIR_LIB/" \;
    cp -a /home/linuxbrew/.linuxbrew/include "$APPDIR/usr/" 2>/dev/null || true
    cp -a /home/linuxbrew/.linuxbrew/lib/pkgconfig "$APPDIR/usr/lib/" 2>/dev/null || true
    BREW_LIB_TARGET="$APPDIR/home/linuxbrew/.linuxbrew/lib"
    mkdir -p "$(dirname "$BREW_LIB_TARGET")"
    ln -sf "$APPDIR_LIB" "$BREW_LIB_TARGET"
    echo "[build_xpra] Symlinked $BREW_LIB_TARGET -> $APPDIR_LIB for RPATH compatibility."
fi

# Overwrite AppRun script to launch Xpra using bundled Python and venv
cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/bash
HERE="$(dirname "$(readlink -f "$0")")"
export VIRTUAL_ENV="$HERE/usr/pyenv"
export PATH="$VIRTUAL_ENV/bin:$HERE/usr/python3/bin:$PATH"
export LD_LIBRARY_PATH="$HERE/usr/lib:$HERE/usr/python3/lib:$LD_LIBRARY_PATH"
exec "$HERE/usr/bin/xpra" "$@"
EOF
chmod +x "$APPDIR/AppRun"

# Change to $APPIMAGE_DIR to ensure linuxdeploy/appimagetool output goes here
cd "$APPIMAGE_DIR"

# Run linuxdeploy to create the AppImage
# Skip fuse (device not found)
export APPIMAGE_EXTRACT_AND_RUN=1
echo "[build_xpra] [AppImage] Step 3: AppImage packaging"
"$APPIMAGE_DIR/linuxdeploy-x86_64.AppImage" --appdir "$APPDIR" \
    -d "$APPDIR/xpra.desktop" \
    -i "$APPDIR/xpra.png" \
    --output appimage

# Find the created Xpra AppImage (exclude linuxdeploy-x86_64.AppImage)
APPIMAGE_FILE=""
for candidate in *.AppImage; do
    if [ -f "$candidate" ] && [[ "$candidate" != "linuxdeploy-x86_64.AppImage" ]]; then
        APPIMAGE_FILE="$APPIMAGE_DIR/$candidate"
        break
    fi
done
if [ -z "$APPIMAGE_FILE" ] || [ ! -f "$APPIMAGE_FILE" ]; then
    echo "[build_xpra] ERROR: No Xpra AppImage file found in $APPIMAGE_DIR after linuxdeploy run." >&2
    exit 1
fi
chmod +x "$APPIMAGE_FILE"
export APPIMAGE_FILE
cp "$APPIMAGE_FILE" "$BUILD_DIR/"
echo "[build_xpra] AppImage copied to $BUILD_DIR/$(basename "$APPIMAGE_FILE") and set executable"

# Check for missing shared libraries in AppDir
# This is a post-build diagnostic to help ensure portability
MISSING=0
echo "[build_xpra] Checking for missing shared libraries in AppDir..."
find "$APPDIR" -type f \( -name '*.so' -o -name '*.so.*' -o -name 'xpra' \) | while read sofile; do
    if file "$sofile" | grep -q 'ELF'; then
        ldd "$sofile" | grep 'not found' && { echo "  [MISSING] in $sofile"; MISSING=1; }
    fi
done
echo "[build_xpra] Shared library check complete."
if [ "$MISSING" -eq 1 ]; then
    echo "[build_xpra] WARNING: One or more shared libraries are missing in the AppImage. See above for details." >&2
else
    echo "[build_xpra] All shared libraries appear to be bundled."
fi

# Sanity check: run the built AppImage with --version and exit if it fails
if ! "$APPIMAGE_FILE" --version >/dev/null; then
    echo "[build_xpra] ERROR: AppImage failed to run with --version. Build is not valid." >&2
    exit 1
fi
echo "[build_xpra] === Xpra build process completed successfully! ==="