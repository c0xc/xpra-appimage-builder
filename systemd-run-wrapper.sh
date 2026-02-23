#!/bin/bash
# systemd-run wrapper for AppImage
# This wrapper ensures environment variables are passed through systemd-run --scope
# Installed to AppDir/usr/bin/systemd-run during build

# Collect XPRA_* environment variables to pass through
args=()
for var in $(env | grep "^XPRA_" | cut -d= -f1); do
    args+=("--setenv" "$var=${!var}")
done

# Add critical path variables needed for AppImage runtime
for var in PYTHONPATH LD_LIBRARY_PATH PATH GI_TYPELIB_PATH GST_PLUGIN_PATH GST_PLUGIN_SCANNER VIRTUAL_ENV; do
    if [ -n "${!var}" ]; then
        args+=("--setenv" "$var=${!var}")
    fi
done

# Execute real systemd-run with our environment variables
exec /usr/bin/systemd-run "${args[@]}" "$@"
