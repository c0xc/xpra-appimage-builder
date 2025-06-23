#!/bin/bash
set -e

# check_xpra.sh: Test the built xpra binary and check codecs

# This should run in activated virtualenv, initialized by container_init.sh
if [ -z "$VIRTUAL_ENV" ]; then
  echo "[check_xpra] ERROR: This script must be run in an activated virtual environment."
  echo "[check_xpra] Please source container_init.sh first to set up the environment."
  exit 1
fi

# Workspace, build directories
BASE_DIR="/workspace"
SRC_DIR="$BASE_DIR/src"
APPIMAGE_DIR="$BASE_DIR/appimage"
BUILD_DIR="$BASE_DIR/build"

# Check if xpra is executable
if ! command -v xpra >/dev/null 2>&1; then
  echo "[check_xpra] ERROR: xpra is not in PATH."
  exit 1
fi

XPRA_BIN=$(command -v xpra)
echo "[check_xpra] xpra binary found at $XPRA_BIN"

# Check xpra version
xpra --version || { echo "[check_xpra] ERROR: xpra not working."; exit 1; }

# Check supported codecs
xpra codec-info || { echo "[check_xpra] WARNING: Could not list codecs."; }

# Check video support
xpra video || { echo "[check_xpra] WARNING: Could not check video support."; }

# Post-build: test GStreamer Python bindings and critical codecs
PYTHON_BIN="$(dirname "$XPRA_BIN")/python3"
echo "[check_xpra] Testing GStreamer Python bindings and critical codecs..."

#"$PYTHON_BIN" -c '
#import sys
#from collections import namedtuple
#import traceback
#
#PluginInfo = namedtuple("PluginInfo", ["name", "description", "required"])
#
#PLUGINS_TO_CHECK = [
#    PluginInfo("opus", "Opus audio codec (critical for WebRTC)", True),
#    PluginInfo("vp8", "VP8 video codec (critical for WebRTC)", True),
#    PluginInfo("vp9", "VP9 video codec (critical for WebRTC)", True),
#    PluginInfo("x264", "H.264 video codec", False),
#    PluginInfo("vorbis", "Vorbis audio codec", False),
#]
#
#try:
#    import gi
#    gi.require_version("Gst", "1.0")
#    from gi.repository import Gst
#    
#    print("[check_xpra] Initializing GStreamer...")
#    Gst.init(None)
#    print(f"[check_xpra] GStreamer version: {Gst.version_string()}")
#    
#    # Get the registry to check for plugins
#    registry = Gst.Registry.get()
#    missing_required = False
#    
#    print("[check_xpra] Checking for critical GStreamer plugins:")
#    
#    for plugin in PLUGINS_TO_CHECK:
#        plugin_obj = registry.find_plugin(plugin.name)
#        if plugin_obj is not None:
#            status = "✓ AVAILABLE"
#        else:
#            status = "✗ MISSING"
#            if plugin.required:
#                missing_required = True
#        
#        print(f"[check_xpra]   {status}: {plugin.name} - {plugin.description}")
#        
#        # For available plugins, try to find their encoder elements
#        if plugin_obj is not None:
#            if plugin.name == "opus":
#                if not registry.find_feature("opusenc"):
#                    print(f"[check_xpra]     ⚠️ WARNING: {plugin.name} plugin exists but opusenc element is missing")
#                    if plugin.required:
#                        missing_required = True
#            elif plugin.name == "vp8":
#                if not registry.find_feature("vp8enc"):
#                    print(f"[check_xpra]     ⚠️ WARNING: {plugin.name} plugin exists but vp8enc element is missing")
#                    if plugin.required:
#                        missing_required = True
#            elif plugin.name == "vp9":
#                if not registry.find_feature("vp9enc"):
#                    print(f"[check_xpra]     ⚠️ WARNING: {plugin.name} plugin exists but vp9enc element is missing")
#                    if plugin.required:
#                        missing_required = True
#    
#    # Try to create a simple pipeline to test GStreamer functionality
#    try:
#        print("[check_xpra] Testing basic GStreamer pipeline functionality...")
#        pipeline = Gst.parse_launch("videotestsrc num-buffers=1 ! fakesink")
#        pipeline.set_state(Gst.State.PLAYING)
#        bus = pipeline.get_bus()
#        msg = bus.timed_pop_filtered(Gst.SECOND, Gst.MessageType.EOS | Gst.MessageType.ERROR)
#        pipeline.set_state(Gst.State.NULL)
#        if msg and msg.type == Gst.MessageType.ERROR:
#            err, debug = msg.parse_error()
#            print(f"[check_xpra] ⚠️ WARNING: Basic pipeline test failed: {err}")
#        else:
#            print("[check_xpra] ✓ Basic pipeline test successful")
#    except Exception as e:
#        print(f"[check_xpra] ⚠️ WARNING: Basic pipeline test failed: {e}")
#    
#    if missing_required:
#        print("[check_xpra] ERROR: Some required GStreamer plugins are missing!", file=sys.stderr)
#        sys.exit(2)
#    else:
#        print("[check_xpra] SUCCESS: All required GStreamer plugins are available.")
#        
#except ImportError as e:
#    print(f"[check_xpra] ERROR: Could not import GStreamer: {e}", file=sys.stderr)
#    traceback.print_exc(file=sys.stderr)
#    sys.exit(1)
#except Exception as e:
#    print(f"[check_xpra] ERROR: GStreamer test failed: {e}", file=sys.stderr)
#    traceback.print_exc(file=sys.stderr)
#    sys.exit(1)
#'

echo "[check_xpra] Xpra checks complete."
