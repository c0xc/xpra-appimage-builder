#!/bin/bash
set -e

# rebuild_shell.sh: Force rebuild of the container image and start a new shell

CLEAN=1 ./run_local.sh shell
