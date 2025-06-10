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

# Ensure Python is available (venv should be activated by entrypoint)
command -v python >/dev/null || { echo "[build_xpra] ERROR: Python not found in PATH. Please activate the virtualenv before running this script."; exit 1; }

echo "[build_xpra] === Installing Python dependencies (uv preferred) === _____________________________"
cd "$SRC_DIR"
if [ -f pyproject.toml ]; then
    echo "[build_xpra] Installing from pyproject.toml using uv..."
    uv pip install .
elif [ -f requirements.txt ]; then
    echo "[build_xpra] Installing from requirements.txt using uv..."
    uv pip install -r requirements.txt
else
    echo "[build_xpra] ERROR: No pyproject.toml or requirements.txt found in repo!"
    exit 1
fi

echo "[build_xpra] === Build process (TODO) === ______________________________________________________"
# (Insert build logic here if needed)

# Optionally create and cd into build subdir for out-of-tree builds
BUILD_SUBDIR="$SRC_DIR/build"
mkdir -p "$BUILD_SUBDIR"
cd "$BUILD_SUBDIR"

echo "[build_xpra] === Packaging AppImage === ________________________________________________________"
# Download linuxdeploy and AppImage tools if not present
mkdir -p "$APPIMAGE_DIR"
cd "$APPIMAGE_DIR"
if [ ! -f linuxdeploy-x86_64.AppImage ]; then
  wget -O linuxdeploy-x86_64.AppImage https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
  chmod +x linuxdeploy-x86_64.AppImage
fi
if [ ! -f linuxdeploy-plugin-python-x86_64.AppImage ]; then
  wget -O linuxdeploy-plugin-python-x86_64.AppImage https://github.com/linuxdeploy/linuxdeploy-plugin-python/releases/download/continuous/linuxdeploy-plugin-python-x86_64.AppImage
  chmod +x linuxdeploy-plugin-python-x86_64.AppImage
fi

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
