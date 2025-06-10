#!/bin/bash
set -e

echo "Container ID: $(hostname)"

source /usr/local/bin/container_init.sh

if [ "$1" = "shell" ] || [ "$USE_SHELL" = "true" ]; then
  echo "Starting interactive shell with initialized Xpra build environment..."
  su -l builder
else
  su -l builder -c "/usr/local/bin/build_xpra.sh"
  su -l builder -c "/usr/local/bin/check_xpra.sh"
fi
