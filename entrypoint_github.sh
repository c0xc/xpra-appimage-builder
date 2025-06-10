#!/bin/bash
set -e

echo "Container ID: $(hostname)"

source /usr/local/bin/container_init.sh

su -l builder -c "/usr/local/bin/build_xpra.sh"
su -l builder -c "/usr/local/bin/check_xpra.sh"
