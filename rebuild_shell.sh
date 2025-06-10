#!/bin/bash
# Quick helper to rebuild and run with a shell

# Clean and rebuild the container with shell access
echo "Forcing script cache update and rebuilding container..."
./run_local.sh shell --no-script-cache
