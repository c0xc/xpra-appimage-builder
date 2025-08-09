#!/bin/bash
set -e

# build_xpra.sh: Build and install Xpra

# This should run in activated virtualenv, initialized by container_init.sh
if [ -z "$VIRTUAL_ENV" ]; then
    echo "[build_xpra] ERROR: This script must be run in an activated virtual environment."
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

# Prepare build environment (parameters, paths)
echo "[build_xpra] === Preparing Xpra build env params === ___________________________________________________"

# Set search paths so that pkg-config finds Linuxbrew X11 headers and libraries
: "${USE_BREW_HEADERS_LIBS:=0}" # off by default
export USE_BREW_HEADERS_LIBS
if [ "$USE_BREW_HEADERS_LIBS" = "1" ]; then
    echo "[build_xpra] USE_BREW_HEADERS_LIBS=1 - setting up env for Linuxbrew paths (CPPFLAGS, LDFLAGS, PKG_CONFIG_PATH)"
    export LDFLAGS="-L/home/linuxbrew/.linuxbrew/lib ${LDFLAGS}"
    export CPPFLAGS="-I/home/linuxbrew/.linuxbrew/include ${CPPFLAGS}"
    # Ensure pkg-config can find both system and Linuxbrew .pc files
    export PKG_CONFIG_PATH="/usr/lib64/pkgconfig:/usr/share/pkgconfig:/home/linuxbrew/.linuxbrew/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
else
    # Use dev headers from Brew as fallback
    # TODO use X11 dev headers
    export PKG_CONFIG_PATH="${PKG_CONFIG_PATH:+$PKG_CONFIG_PATH:}$BREW_PREFIX/lib/pkgconfig:$BREW_PREFIX/lib64/pkgconfig"
    export CPATH="${CPATH:+$CPATH:}$BREW_PREFIX/include"
fi

# Check for Nvidia tools (nvcc) and set XPRA_NV_BUILD_ARGS
if [ -z "${USE_NV+x}" ]; then
    if command -v nvcc >/dev/null 2>&1; then
        export USE_NV=1
        echo "[build_xpra] CUDA/nvcc detected: enabling NVIDIA/NVENC build options."
    else
        export USE_NV=0
    fi
fi
XPRA_NV_BUILD_ARGS=""
if [ "$USE_NV" = "1" ]; then
    XPRA_NV_BUILD_ARGS="--with-nvenc --with-nvidia"
fi

# Start build process
echo "[build_xpra] === Starting Xpra build process === ___________________________________________________"

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

# Create blank AppDir
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

# Copy venv from /opt/pyenv
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
#find "$APPDIR/usr/pyenv/lib" -name '*.pth' -exec sed -i 's|/home/[^: ]*||g' {} \;

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

# TODO Gstreamer, ffmpeg, opus, vpx, webp, etc. libraries

# Helper function to copy files (resolving symlinks)
copy_dep_files() {
    local src_dir="$1" # $BREW_LIB
    local pattern="$2" # "*.so*", "*.typelib", "*.so"
    local dest_dir="$3" # $APPDIR/usr/lib

    mkdir -p "$dest_dir"
    for src_file in "$src_dir"/$pattern; do
        # Construct dest_file = source file, relative to src_dir
        local resolved_src_file="$src_file"
        local dest_file="$dest_dir/$(basename "$src_file")"
        # If the source file is a symlink, resolve it to the real file
        if [ -L "$src_file" ]; then
            resolved_src_file=$(readlink -f "$src_file")
            echo "[build_xpra] Resolving symlink: $src_file -> $resolved_src_file"
        fi

        # Copy the resolved file to the destination
        if [ -f "$resolved_src_file" ]; then
            cp -vf "$resolved_src_file" "$dest_file"
            echo "[build_xpra] Copied: $resolved_src_file -> $dest_file"
        elif ! [ -d "$resolved_src_file" ]; then
            echo "[build_xpra] WARNING: Skipping non-file source: $src_file" >&2
        fi
    done
}

# Copy Linuxbrew libs
if [ "${USE_BREW_HEADERS_LIBS:-0}" = "1" ]; then
    echo "[build_xpra] USE_BREW_HEADERS_LIBS=1: bundling Linuxbrew libraries into AppDir..."
    BREW_LIB="/home/linuxbrew/.linuxbrew/lib"
    APPDIR_LIB="$APPDIR/usr/lib"
    mkdir -p "$APPDIR_LIB"

    # --- Explicitly include libraries needed by Python/Cython modules ---
    echo "[build_xpra] Copying codec libraries for Python modules..."
    # Video codecs
    copy_dep_files "$BREW_LIB" "libvpx.so*" "$APPDIR_LIB"
    copy_dep_files "$BREW_LIB" "libx264.so*" "$APPDIR_LIB"
    copy_dep_files "$BREW_LIB" "libwebp.so*" "$APPDIR_LIB"
    
    # Audio codecs
    copy_dep_files "$BREW_LIB" "libopus.so*" "$APPDIR_LIB"
    copy_dep_files "$BREW_LIB" "libvorbis.so*" "$APPDIR_LIB"
    copy_dep_files "$BREW_LIB" "libogg.so*" "$APPDIR_LIB"
    copy_dep_files "$BREW_LIB" "libspeex.so*" "$APPDIR_LIB"
    
    # GStreamer core libraries
    copy_dep_files "$BREW_LIB" "libgstreamer-1.0.so*" "$APPDIR_LIB"
    copy_dep_files "$BREW_LIB" "libgstbase-1.0.so*" "$APPDIR_LIB" 
    copy_dep_files "$BREW_LIB" "libgstaudio-1.0.so*" "$APPDIR_LIB"
    copy_dep_files "$BREW_LIB" "libgstvideo-1.0.so*" "$APPDIR_LIB"
    copy_dep_files "$BREW_LIB" "libgstpbutils-1.0.so*" "$APPDIR_LIB"
    copy_dep_files "$BREW_LIB" "libgsttag-1.0.so*" "$APPDIR_LIB"
    
    # Audio system libraries
    copy_dep_files "$BREW_LIB" "libpulse*.so*" "$APPDIR_LIB"
    copy_dep_files "$BREW_LIB" "libsndfile*.so*" "$APPDIR_LIB"
    copy_dep_files "$BREW_LIB" "libasound*.so*" "$APPDIR_LIB"
    
    # GObject and Cairo libraries for Python bindings
    copy_dep_files "$BREW_LIB" "libcairo*.so*" "$APPDIR_LIB"
    copy_dep_files "$BREW_LIB" "libgirepository-1.0.so*" "$APPDIR_LIB"
    copy_dep_files "$BREW_LIB" "libgobject-2.0.so*" "$APPDIR_LIB"
    copy_dep_files "$BREW_LIB" "libglib-2.0.so*" "$APPDIR_LIB"
    copy_dep_files "$BREW_LIB" "libgmodule-2.0.so*" "$APPDIR_LIB"  # Required for GStreamer plugin loading
    
    # --- System libraries needed by Python FFI and GStreamer ---
    echo "[build_xpra] Copying system libraries needed by Python modules..."
    
    # libffi is critical for Python's ctypes and many GStreamer plugins
    copy_dep_files "$BREW_LIB" "libffi.so.6*" "$APPDIR_LIB"
    copy_dep_files "$BREW_LIB" "libffi.so" "$APPDIR_LIB"
    echo "[build_xpra] Using libffi.so.6 from Linuxbrew"
    

    # You can optionally copy all .so* files, but we'll include specific ones above for better control
    # copy_dep_files "$BREW_LIB" "*.so*" "$APPDIR_LIB"

    # --- GStreamer: Typelib files for GObject Introspection ---
    copy_dep_files "$BREW_LIB/girepository-1.0" "*.typelib" "$APPDIR_LIB/girepository-1.0"

    # --- GStreamer: Minimal audio codecs (Opus, Vorbis, Ogg, Pulse/ALSA) ---
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgstopus.so" "$APPDIR_LIB/gstreamer-1.0"
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgstvorbis.so" "$APPDIR_LIB/gstreamer-1.0"
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgstogg.so" "$APPDIR_LIB/gstreamer-1.0"
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgstpulseaudio.so" "$APPDIR_LIB/gstreamer-1.0"
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgstalsa.so" "$APPDIR_LIB/gstreamer-1.0"
    # Audio helpers
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgstwavparse.so" "$APPDIR_LIB/gstreamer-1.0"
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgstvolume.so" "$APPDIR_LIB/gstreamer-1.0"

    # --- GStreamer: Core plugins (pipeline, conversion, etc.) ---
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgstaudioconvert.so" "$APPDIR_LIB/gstreamer-1.0"
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgstaudioresample.so" "$APPDIR_LIB/gstreamer-1.0"
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgstcoreelements.so" "$APPDIR_LIB/gstreamer-1.0"
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgstplayback.so" "$APPDIR_LIB/gstreamer-1.0"
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgsttypefindfunctions.so" "$APPDIR_LIB/gstreamer-1.0"
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgstapp.so" "$APPDIR_LIB/gstreamer-1.0"

    # --- GStreamer: Video codecs (H264, Theora, VPX) ---
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgstx264.so" "$APPDIR_LIB/gstreamer-1.0"
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgstopenh264.so" "$APPDIR_LIB/gstreamer-1.0"
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgsttheora.so" "$APPDIR_LIB/gstreamer-1.0"
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgstvpx.so" "$APPDIR_LIB/gstreamer-1.0"
    # Video helpers
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgstautodetect.so" "$APPDIR_LIB/gstreamer-1.0"
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgstvideotestsrc.so" "$APPDIR_LIB/gstreamer-1.0"

    # --- GStreamer: Parsers and helpers ---
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgstaudioparsers.so" "$APPDIR_LIB/gstreamer-1.0"
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgstvideoparsersbad.so" "$APPDIR_LIB/gstreamer-1.0"
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgstvideoconvert.so" "$APPDIR_LIB/gstreamer-1.0"
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgstvideoscale.so" "$APPDIR_LIB/gstreamer-1.0"
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgstvideorate.so" "$APPDIR_LIB/gstreamer-1.0"

    # --- GStreamer: Miscellaneous ---
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgstudp.so" "$APPDIR_LIB/gstreamer-1.0"
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgstrtp.so" "$APPDIR_LIB/gstreamer-1.0"
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgstrtpmanager.so" "$APPDIR_LIB/gstreamer-1.0"
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgstfaac.so" "$APPDIR_LIB/gstreamer-1.0"
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgstaac.so" "$APPDIR_LIB/gstreamer-1.0"
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgstspeex.so" "$APPDIR_LIB/gstreamer-1.0"
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgstmulaw.so" "$APPDIR_LIB/gstreamer-1.0"
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgstalaw.so" "$APPDIR_LIB/gstreamer-1.0"
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgstresample.so" "$APPDIR_LIB/gstreamer-1.0"
    copy_dep_files "$BREW_LIB/gstreamer-1.0" "libgstsegmentclip.so" "$APPDIR_LIB/gstreamer-1.0"

    # --- GStreamer: Plugin scanner binary ---
    echo "[build_xpra] Copying GStreamer plugin scanner..."
    # Check for Homebrew Cellar install or fallback to other locations
    GST_SCANNER_PATHS=(
        "/home/linuxbrew/.linuxbrew/Cellar/gstreamer/*/libexec/gstreamer-1.0/gst-plugin-scanner"
        "/home/linuxbrew/.linuxbrew/libexec/gstreamer-1.0/gst-plugin-scanner"
    )
    
    SCANNER_FOUND=0
    # First try the cellar wildcard path which may return multiple matches
    CELLAR_SCANNERS=( /home/linuxbrew/.linuxbrew/Cellar/gstreamer/*/libexec/gstreamer-1.0/gst-plugin-scanner )
    if [ -f "${CELLAR_SCANNERS[0]}" ]; then
        scanner_path="${CELLAR_SCANNERS[0]}"
        echo "[build_xpra] Found GStreamer plugin scanner at: $scanner_path"
        mkdir -p "$APPDIR/usr/libexec/gstreamer-1.0"
        cp -vf "$scanner_path" "$APPDIR/usr/libexec/gstreamer-1.0/"
        chmod +x "$APPDIR/usr/libexec/gstreamer-1.0/gst-plugin-scanner"
        echo "[build_xpra] GStreamer plugin scanner copied to AppImage"
        SCANNER_FOUND=1
    fi
    
    if [ $SCANNER_FOUND -eq 0 ]; then
        echo "[build_xpra] ERROR: Could not find GStreamer plugin scanner in any standard location!"
        echo "[build_xpra] GStreamer plugin loading will not work correctly!"
    fi

    # --- GStreamer: Additional dependencies ---
    echo "[build_xpra] Copying additional GStreamer dependencies..."
    # GLib's gio modules (needed by GStreamer for various operations)
    copy_dep_files "$BREW_LIB" "libgio-2.0.so*" "$APPDIR_LIB"
    # GLib module system (needed for GStreamer plugins)
    copy_dep_files "$BREW_LIB" "libgmodule-2.0.so*" "$APPDIR_LIB"
    # Core GLib libraries - ensure we have all required versions
    copy_dep_files "$BREW_LIB" "libgobject-2.0.so*" "$APPDIR_LIB"
    copy_dep_files "$BREW_LIB" "libglib-2.0.so*" "$APPDIR_LIB"
    # GStreamer core registry and helpers
    copy_dep_files "$BREW_LIB" "libgstcheck-1.0.so*" "$APPDIR_LIB"
    copy_dep_files "$BREW_LIB" "libgstcontroller-1.0.so*" "$APPDIR_LIB"
    copy_dep_files "$BREW_LIB" "libgstnet-1.0.so*" "$APPDIR_LIB"
    
    # --- Special handling for libffi.so.6 ---
    echo "[build_xpra] Explicitly handling libffi.so.6 which is required by Python modules..."
    
    # Many Python modules need libffi.so.6 specifically
    # First check if Linuxbrew has it (unlikely as it usually has newer versions)
    LIBFFI_FOUND=0
    if [ -f "$BREW_LIB/libffi.so.6" ]; then
        echo "[build_xpra] Found libffi.so.6 in Linuxbrew, copying..."
        copy_dep_files "$BREW_LIB" "libffi.so.6*" "$APPDIR_LIB"
        LIBFFI_FOUND=1
    fi
    
    # If not in Linuxbrew, try to find it in system locations
    if [ $LIBFFI_FOUND -eq 0 ]; then
        echo "[build_xpra] Looking for libffi.so.6 in system locations..."
        for LIBFFI_PATH in /usr/lib/libffi.so.6 /usr/lib64/libffi.so.6 /lib/libffi.so.6 /lib64/libffi.so.6; do
            if [ -f "$LIBFFI_PATH" ]; then
                echo "[build_xpra] Found libffi.so.6 at $LIBFFI_PATH, copying to AppDir..."
                cp -vf "$LIBFFI_PATH" "$APPDIR_LIB/"
                # Also copy any symbolic link targets
                if [ -L "$LIBFFI_PATH" ]; then
                    LIBFFI_TARGET=$(readlink -f "$LIBFFI_PATH")
                    echo "[build_xpra] Copying libffi target: $LIBFFI_TARGET"
                    cp -vf "$LIBFFI_TARGET" "$APPDIR_LIB/"
                fi
                LIBFFI_FOUND=1
                break
            fi
        done
    fi
    
    # Also copy newer libffi versions if available (for newer libraries that need them)
    copy_dep_files "$BREW_LIB" "libffi.so.*" "$APPDIR_LIB"
    
    if [ $LIBFFI_FOUND -eq 0 ]; then
        echo "[build_xpra] WARNING: libffi.so.6 not found in any standard location!"
        echo "[build_xpra] Python modules requiring libffi.so.6 may not work correctly!"
    fi
    
    # Add any other missing GStreamer libraries you find in ldd

    # Done copying Linuxbrew libraries
    # Make copied files in AppDir writable (because the source files are not)
    chmod -R u+w "$APPDIR_LIB" 2>/dev/null || true

    echo "[build_xpra] Linuxbrew libraries and GStreamer components copied."

else
    # Find and copy libraries
    echo "[build_xpra] Using self-built dependencies from DEPS_PREFIX=$DEPS_PREFIX"

    # Copy GStreamer plugin scanner if it exists in self-built deps
    if [ -f "$DEPS_PREFIX/libexec/gstreamer-1.0/gst-plugin-scanner" ]; then
        echo "[build_xpra] Found GStreamer plugin scanner in DEPS_PREFIX"
        mkdir -p "$APPDIR/usr/libexec/gstreamer-1.0"
        cp -vf "$DEPS_PREFIX/libexec/gstreamer-1.0/gst-plugin-scanner" "$APPDIR/usr/libexec/gstreamer-1.0/"
        chmod +x "$APPDIR/usr/libexec/gstreamer-1.0/gst-plugin-scanner"
    fi

    # Copy all ELF binaries and libraries from DEPS_PREFIX for linuxdeploy to scan
    echo "[build_xpra] Copying ELF binaries and libraries from DEPS_PREFIX to AppDir for linuxdeploy dependency detection..."
    cp -a $DEPS_PREFIX/bin/* "$APPDIR/usr/bin/" 2>/dev/null || true
    cp -a $DEPS_PREFIX/lib/*.so* "$APPDIR/usr/lib/" 2>/dev/null || true
    cp -a $DEPS_PREFIX/lib64/*.so* "$APPDIR/usr/lib64/" 2>/dev/null || true
    cp -a $DEPS_PREFIX/libexec/* "$APPDIR/usr/libexec/" 2>/dev/null || true
    cp -a $DEPS_PREFIX/lib/gstreamer-1.0 "$APPDIR/usr/lib/" 2>/dev/null || true
    cp -a $DEPS_PREFIX/lib64/gstreamer-1.0 "$APPDIR/usr/lib64/" 2>/dev/null || true

    # Copy typelibs from both self-built DEPS_PREFIX and system locations
    # TODO /usr should be optional but some of our files seem to be missing in DEPS_PREFIX
    echo "[build_xpra] Copying typelibs from DEPS_PREFIX and system locations to AppDir..."
    copy_dep_files "/usr/lib64/girepository-1.0" "*.typelib" "$APPDIR/usr/lib64/girepository-1.0"
    copy_dep_files "/usr/lib/girepository-1.0" "*.typelib" "$APPDIR/usr/lib/girepository-1.0"
    copy_dep_files "$DEPS_PREFIX/lib/girepository-1.0" "*.typelib" "$APPDIR/usr/lib/girepository-1.0"
    copy_dep_files "$DEPS_PREFIX/lib64/girepository-1.0" "*.typelib" "$APPDIR/usr/lib64/girepository-1.0"

fi

# Overwrite AppRun script to launch Xpra using bundled Python and venv
cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/bash
HERE="$(dirname "$(readlink -f "$0")")"
export VIRTUAL_ENV="$HERE/usr/pyenv"
export PATH="$VIRTUAL_ENV/bin:$HERE/usr/python3/bin:$HERE/usr/bin:$PATH"

# Setup library paths (include both /usr/lib and /usr/lib64 for CentOS compatibility)
export LD_LIBRARY_PATH="$HERE/usr/lib:$HERE/usr/lib64:$HERE/usr/python3/lib:$LD_LIBRARY_PATH"

# Check for --debug flag first and set XPRA_DEBUG if present
if [ "$1" = "--debug" ]; then
    export XPRA_DEBUG=1
    shift
fi

# GStreamer: Look for plugins in all possible directories
GST_PLUGIN_DIRS=()
GI_TYPELIB_DIRS=()

# Check for plugins in standard locations
for gst_dir in "$HERE/usr/lib/gstreamer-1.0" "$HERE/usr/lib64/gstreamer-1.0"; do
    if [ -d "$gst_dir" ]; then
        GST_PLUGIN_DIRS+=("$gst_dir")
    fi
done

# Check for typelib files in standard locations
for typelib_dir in "$HERE/usr/lib/girepository-1.0" "$HERE/usr/lib64/girepository-1.0"; do
    if [ -d "$typelib_dir" ]; then
        GI_TYPELIB_DIRS+=("$typelib_dir")
    fi
done

# Set the GStreamer environment variables if directories were found
if [ ${#GST_PLUGIN_DIRS[@]} -gt 0 ]; then
    export GST_PLUGIN_PATH="$(IFS=:; echo "${GST_PLUGIN_DIRS[*]}")"
    [ "${XPRA_DEBUG:-0}" = "1" ] && echo "GST_PLUGIN_PATH=$GST_PLUGIN_PATH"
fi

if [ ${#GI_TYPELIB_DIRS[@]} -gt 0 ]; then
    export GI_TYPELIB_PATH="$(IFS=:; echo "${GI_TYPELIB_DIRS[*]}")${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
    [ "${XPRA_DEBUG:-0}" = "1" ] && echo "GI_TYPELIB_PATH=$GI_TYPELIB_PATH"
fi

# GStreamer plugin scanner - try standard locations
for scanner in "$HERE/usr/libexec/gstreamer-1.0/gst-plugin-scanner" "$HERE/usr/lib/gstreamer-1.0/gst-plugin-scanner"; do
    if [ -f "$scanner" ]; then
        export GST_PLUGIN_SCANNER="$scanner"
        [ "${XPRA_DEBUG:-0}" = "1" ] && echo "GST_PLUGIN_SCANNER=$GST_PLUGIN_SCANNER"
        break
    fi
done

# Enable debug mode if XPRA_DEBUG is set (either from flag or environment)
if [ "${XPRA_DEBUG:-0}" = "1" ]; then
    # Enable GStreamer debugging
    export GST_DEBUG=3
    export GST_DEBUG_FILE=/tmp/xpra-gst-debug.log
    
    # Create a temporary log directory for all Xpra/GStreamer logs
    LOG_DIR="/tmp/xpra-debug-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$LOG_DIR"
    
    # Selectively disable codecs if needed for debugging
    if [ "${XPRA_DISABLE_H264:-0}" = "1" ]; then
        echo "Disabling H.264 codec support for debugging"
        export XPRA_ENCODING_BLACKLIST="${XPRA_ENCODING_BLACKLIST},h264"
    fi
    if [ "${XPRA_DISABLE_GSTREAMER:-0}" = "1" ]; then
        echo "Disabling GStreamer for debugging"
        export XPRA_SOUND_COMMAND=""
        export XPRA_GSTREAMER="0"
    fi
    
    # Capture library load errors for diagnostics
    LD_DEBUG=libs LD_DEBUG_OUTPUT="$LOG_DIR/ld-debug" "$HERE/usr/bin/xpra" "$@" 2>"$LOG_DIR/stderr.log" || {
        echo "Xpra crashed with exit code $?. Debug logs saved to $LOG_DIR"
        echo "You can examine missing libraries with: grep 'cannot open' $LOG_DIR/ld-debug*"
    }
    exit $?
else
    # Regular execution
    
    # Suppress Gtk/GLib critical/warning messages
    export G_MESSAGES_DEBUG="none"

    # Create writable cache directory for GStreamer registry
    export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
    mkdir -p "$XDG_CACHE_HOME/gstreamer-1.0"
    
    # GStreamer initialization options
    export GST_REGISTRY="$XDG_CACHE_HOME/gstreamer-1.0/registry-$(uname -m).bin"
    export GST_REGISTRY_UPDATE=yes
    
    exec "$HERE/usr/bin/xpra" "$@"
fi
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
    so_dir=$(dirname "$sofile")
    if file "$sofile" | grep -q 'ELF'; then
        LD_LIBRARY_PATH="$so_dir:$LD_LIBRARY_PATH" ldd "$sofile" | grep 'not found' && { echo "  [MISSING] in $sofile"; MISSING=1; }
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

# If gobject introspection bindings are missing or incomplete,
# the following command will fail (but xpra --video-decoders=help won't)
# (pyenv) xpra attach --encoding=help
# ImportError: unable to import 'Gtk' version='3.0': Namespace Gtk not available
# Possible cause: Missing typelib files like Gtk-3.0.typelib were not installed in DEP_PREFIX
# but if those from the OS were copied into the AppDir:
# GI_TYPELIB_PATH=$HERE/usr/lib/girepository-1.0:$HERE/usr/lib64/girepository-1.0

# Test if compiled appimage detects any codec
if ! "$APPIMAGE_FILE" attach --encoding=help >/dev/null; then
    echo "[build_xpra] ERROR: AppImage failed to detect codecs. Build may be incomplete." >&2
    exit 1
fi

echo "[build_xpra] === Xpra build process completed successfully! ==="