#!/bin/bash
set -e

echo "Container ID: $(hostname)"
echo "Entrypoint called: $0 $@"

# Check if USE_SHELL is set, default to false
USE_SHELL="${USE_SHELL:-false}"
if [ "$1" = "shell" ]; then
    USE_SHELL=true
    echo "Running in shell mode"
else
    echo "Running in build mode ($1)"
fi


# Abort if run as root
if [ "$(id -u)" = "0" ]; then
    echo "[ERROR] Do not run this entrypoint as root. Use the builder user."
    exit 1
fi

# Activate our build environment
source /usr/local/bin/container_init.sh

# Run build or shell
if [ "$USE_SHELL" = "true" ]; then
    echo "Starting interactive shell with build environment..."
    echo
    echo "===================================================================="
    echo "[xpra-appimg] Running in shell mode"
    echo "You can run the following scripts to continue:"
    echo "    /usr/local/bin/build_env.sh      # (Re)initialize Python environment"
    echo "    /usr/local/bin/fetch_src.sh      # Fetch or update Xpra source (if present)"
    echo "    /usr/local/bin/build_prereqs.sh  # Install build prerequisites and Python deps"
    echo "    /usr/local/bin/build_xpra.sh     # Build Xpra and AppImage"
    echo "    /usr/local/bin/check_xpra.sh     # Run post-build checks"
    echo "    /usr/local/bin/build.sh          # Run the full build pipeline (all steps above)"
    echo
    echo "Current directory: $(pwd)"
    echo "Example: /usr/local/bin/build_xpra.sh"
    echo "===================================================================="
    echo

    exec bash -l
else
    /usr/local/bin/build.sh
fi
