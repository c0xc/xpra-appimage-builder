#!/bin/bash
set -e

echo "==== [1/4] Fetching source ===="
/usr/local/bin/fetch_src.sh

echo "==== [2/4] Installing prerequisites ===="
/usr/local/bin/build_prereqs.sh

echo "==== [3/4] Building Xpra ===="
/usr/local/bin/build_xpra.sh

echo "==== [4/4] Running checks ===="
/usr/local/bin/check_xpra.sh

echo "==== Build pipeline complete ===="
