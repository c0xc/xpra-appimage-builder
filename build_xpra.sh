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
BASE_DIR="/workspace/xpra"
SRC_DIR="$BASE_DIR/src"
APPIMAGE_DIR="$BASE_DIR/appimage"
BUILD_DIR="$BASE_DIR/build"
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
    export PKG_CONFIG_PATH="/home/linuxbrew/.linuxbrew/lib/pkgconfig:/home/linuxbrew/.linuxbrew/share/pkgconfig"
    echo "[build_xpra] PKG_CONFIG_PATH set to Linuxbrew only: $PKG_CONFIG_PATH"
    export LDFLAGS="-L/home/linuxbrew/.linuxbrew/lib ${LDFLAGS}"
    export CPPFLAGS="-I/home/linuxbrew/.linuxbrew/include ${CPPFLAGS}"
else
    echo "[build_xpra] Using system X11 headers and libraries (default include path)."
fi

# Build wheel in build dir and install from there
echo "[build_xpra] Building Xpra wheel in $BUILD_DIR ..."
mkdir -p "$BUILD_DIR"
python -m build --wheel --outdir "$BUILD_DIR"
echo "[build_xpra] Installing Xpra wheel into current Python environment ..."
uv pip install "$BUILD_DIR"/xpra-*.whl

echo "[build_xpra] === Packaging AppImage === ________________________________________________________"
# Download linuxdeploy and AppImage tools if not present
mkdir -p "$APPIMAGE_DIR"
cd "$APPIMAGE_DIR"

# Try to use pre-downloaded linuxdeploy files if present in workspace root or $APPIMAGE_DIR
for tool in linuxdeploy-x86_64.AppImage linuxdeploy-plugin-python-x86_64.AppImage; do
  if [ ! -f "$tool" ]; then
    if [ -f "/workspace/xpra/$tool" ]; then
      echo "[build_xpra] Found $tool in /workspace/xpra, copying to $APPIMAGE_DIR."
      cp "/workspace/xpra/$tool" "$APPIMAGE_DIR/"
      chmod +x "$APPIMAGE_DIR/$tool"
    elif [ -f "/workspace/xpra/appimage/$tool" ]; then
      echo "[build_xpra] Found $tool in /workspace/xpra/appimage, copying to $APPIMAGE_DIR."
      cp "/workspace/xpra/appimage/$tool" "$APPIMAGE_DIR/"
      chmod +x "$APPIMAGE_DIR/$tool"
    else
      # Download if not found locally
      if [ "$tool" = "linuxdeploy-x86_64.AppImage" ]; then
        echo "[build_xpra] Downloading $tool ..."
        wget -O "$tool" https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage && chmod +x "$tool"
      elif [ "$tool" = "linuxdeploy-plugin-python-x86_64.AppImage" ]; then
        echo "[build_xpra] Downloading $tool ..."
        wget -O "$tool" https://github.com/linuxdeploy/linuxdeploy-plugin-python/releases/download/continuous/linuxdeploy-plugin-python-x86_64.AppImage && chmod +x "$tool" || echo "[build_xpra] WARNING: $tool not found for download. Please provide it manually if needed."
      fi
    fi
  fi
done

# Create AppDir structure
APPDIR="$APPIMAGE_DIR/AppDir"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin"
cp -r "$SRC_DIR" "$APPDIR/usr/share/xpra"
ln -s /usr/share/xpra/scripts/xpra "$APPDIR/usr/bin/xpra"

# Create minimal desktop file
cat > "$APPDIR/xpra.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Xpra
Exec=xpra
Icon=xpra
Categories=Utility;
EOF

# Create minimal icon
convert -size 64x64 xc:lightgray "$APPDIR/xpra.png" || true

# Build AppImage using linuxdeploy and the official python plugin
./linuxdeploy-x86_64.AppImage --appdir "$APPDIR" \
  -d "$APPDIR/xpra.desktop" \
  -i "$APPDIR/xpra.png" \
  --plugin python \
  --output appimage

# Move AppImage to output
mv *.AppImage "$APPIMAGE_DIR/xpra-latest.AppImage"
echo "[build_xpra] AppImage created at $APPIMAGE_DIR/xpra-latest.AppImage"
