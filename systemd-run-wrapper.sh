#!/bin/bash
# systemd-run wrapper for AppImage
# This wrapper ensures environment variables are passed through systemd-run --scope
# Installed to AppDir/usr/libexec/xpra/systemd-run during build

# Collect XPRA_* environment variables to pass through
args=()
while IFS='=' read -r key value; do
    [[ "$key" == XPRA_* ]] && args+=("--setenv" "$key=$value")
done < <(env 2>/dev/null)

# Add critical path variables needed for AppImage runtime
for var in PYTHONPATH LD_LIBRARY_PATH PATH GI_TYPELIB_PATH GST_PLUGIN_PATH GST_PLUGIN_SCANNER VIRTUAL_ENV; do
    value="${!var}"
    [[ -n "$value" ]] && args+=("--setenv" "$var=$value")
done

# Execute real systemd-run with our environment variables
exec /usr/bin/systemd-run "${args[@]}" "$@"
