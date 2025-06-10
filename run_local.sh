#!/bin/bash
set -e

# This script runs the Xpra AppImage build container locally using Podman.
# Its main purpose is to select the base image and run the build process
# with a temporary workspace mounted if desired.


# Unset problematic DBUS_SESSION_BUS_ADDRESS for podman compatibility
# error running container: ... sd-bus call: Interactive authentication required.: Permission denied
unset DBUS_SESSION_BUS_ADDRESS

# Show help information
function show_help {
  echo "Usage: $0 [command] [options]"
  echo
  echo "Commands:"
  echo "  build     - Build the AppImage (default)"
  echo "  shell     - Enter interactive shell in the container"
  echo "  clear     - Clear all cached container images"
  echo "  help      - Show this help message"
  echo
  echo "Options:"
  echo "  --no-cache          - Build without using docker cache (full rebuild)"
  echo "  --no-script-cache   - Rebuild only scripts (faster than full rebuild)"
  echo
  echo "Examples:"
  echo "  $0                # Build AppImage with default base (centos8)"
  echo "  $0 clear          # Clear all cached images"
  echo "  $0 shell          # Build container and run shell"
}

# Script to run the xpra build container locally
COMMAND="${1:-build}"
shift || true

# Initialize variables
USE_SHELL=false
NO_CACHE=""
NO_SCRIPT_CACHE=""

# Internal: set base image (default to centos8, can override with BASE env)
BASE="${BASE:-centos8}"

# Help command
if [ "$COMMAND" = "help" ]; then
    show_help
    exit 0
fi

# Special commands that don't need a build
if [ "$COMMAND" = "clear" ]; then
    echo "Removing all xpra-appimg-builder images..."
    podman rmi $(podman images -q xpra-appimg-builder-* 2>/dev/null) 2>/dev/null || echo "No images to remove"
    echo "Build cache cleared"
    exit 0
fi

# Check if we want to enter shell mode
if [ "$COMMAND" = "shell" ]; then
    USE_SHELL=true
fi

# Only allow known commands
if [[ ! "$COMMAND" =~ ^(build|shell|clear|help)$ ]]; then
    echo "Error: Unknown command: $COMMAND"
    show_help
    exit 1
fi

# Parse additional options
while [[ "$1" == --* ]]; do
  case "$1" in
    --no-cache)
      NO_CACHE="--no-cache"
      ;;
    --no-script-cache)
      NO_SCRIPT_CACHE="--build-arg CACHE_BUST=$(date +%s)"
      ;;
  esac
  shift
done

# Set up workspace root (on the host) and timestamped build directory
# The timestamp ensures unique directories for each run, useful for debugging,
# but instead of a fixed ~/tmp, we use a configurable TMP_WORKSPACE_ROOT.
# Inside the container, the build directory is always /build, without a timestamp.
TMP_WORKSPACE_ROOT="${TMP_WORKSPACE_ROOT:-$HOME/tmp}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
WORKSPACE_DIR="$TMP_WORKSPACE_ROOT/xpra-build-$TIMESTAMP"
# Determine if we should mount the workspace
MOUNT_WORKSPACE=${MOUNT_WORKSPACE:-0}
PODMAN_RUN_ARGS=(--rm --security-opt label=disable)
if [ "$MOUNT_WORKSPACE" = "1" ]; then
    echo "Creating workspace directory: $WORKSPACE_DIR"
    mkdir -p "$WORKSPACE_DIR"
    PODMAN_RUN_ARGS+=( -v "$WORKSPACE_DIR":/workspace )
    MOUNT_MSG="[INFO] Mounting host workspace: $WORKSPACE_DIR -> /workspace"
fi

# Set Dockerfile and image based on BASE
if [ "$BASE" = "debian8" ]; then
    DOCKERFILE="Dockerfile.debian8"
    IMAGE="xpra-appimg-builder-debian8"
elif [ "$BASE" = "centos7" ]; then
    DOCKERFILE="Dockerfile.centos7"
    IMAGE="xpra-appimg-builder-centos7"
else
    DOCKERFILE="Dockerfile.centos8"
    IMAGE="xpra-appimg-builder-centos8"
fi

# Build the image (partially prepared for shell mode), run it with the entrypoint script
# Several steps: build_env, build_prereqs, build_xpra, check_xpra.
# It activates the environment. If not in shell mode, it runs the build script.
if [ "$USE_SHELL" = "true" ]; then
    if ! podman image exists "$IMAGE"; then
        echo "Building $IMAGE from $DOCKERFILE..."
        podman build $NO_CACHE $NO_SCRIPT_CACHE -f "$DOCKERFILE" -t "$IMAGE" . || exit $?
    else
        echo "Image $IMAGE already exists, skipping build."
    fi
    echo "Starting interactive shell in $IMAGE container..."
    podman run -it "${PODMAN_RUN_ARGS[@]}" "$IMAGE" shell || exit $?
else
    podman build $NO_CACHE $NO_SCRIPT_CACHE -f "$DOCKERFILE" -t "$IMAGE" . || exit $?
    podman run "${PODMAN_RUN_ARGS[@]}" "$IMAGE" || exit $?
fi

echo "Done: $WORKSPACE_DIR."
