#!/bin/bash
set -e

echo "==== [1/4] Fetching source ===="
if [ -x /usr/local/bin/fetch_src.sh ]; then
    /usr/local/bin/fetch_src.sh
else
    echo "[WARN] fetch_src.sh not found or not executable, skipping source fetch."
fi

echo "==== [2/4] Installing prerequisites ===="
/usr/local/bin/build_prereqs.sh

echo "==== [3/4] Building Xpra ===="
/usr/local/bin/build_xpra.sh

echo "==== [4/4] Running checks ===="
/usr/local/bin/check_xpra.sh

echo "==== Build pipeline complete ===="
