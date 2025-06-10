# Xpra AppImage Builder

This project builds the latest [Xpra](https://github.com/Xpra-org/xpra) as an AppImage in a reproducible container, for use on many Linux distributions.

## Usage

### Local Build

1. Ensure you have [Podman](https://podman.io/) installed.
2. Run:
   ```bash
   ./run_local.sh           # Build and output AppImage to a timestamped subdir under ~/tmp (or $TMP_WORKSPACE_ROOT)
   MOUNT_WORKSPACE=1 ./run_local.sh   # Mounts the build output to /workspace for inspection
   ./run_local.sh shell     # Build container and drop into shell for debugging
   ```
3. The resulting AppImage will be in the timestamped build directory (e.g., ~/tmp/xpra-build-YYYYMMDD-HHMMSS) if mounted, or inside the container's /build directory.

The container always builds in /build (or a subdir). The /workspace mount is only used for local debugging or to persist build output to the host. For CI and most builds, /workspace is not mounted and all output remains in the container.

### Interactive Shell for Development

When you run `./run_local.sh shell`, you enter an interactive shell with the Python environment already initialized:

1. Verify the Python environment is active:
   ```bash
   which python  # Should show /pyenv/bin/python
   python --version  # Should show Python 3.10.x
   ```

2. Manually run build steps:
   ```bash
   # Run the complete build process
   /usr/local/bin/build_xpra.sh
   
   # Run just the verification steps
   /usr/local/bin/check_xpra.sh
   
   # Check the Python environment
   pip list
   ```

3. Debug or modify the build:
   ```bash
   # Edit a file
   vi /usr/local/bin/build_xpra.sh
   
   # Test specific xpra features
   xpra --version
   xpra codec-info
   ```

The container environment is fully prepared for development and testing. All changes made to files in the mounted `/workspace` directory will persist on your host system.

### GitHub Actions

- The workflow in `.github/workflows/build-xpra.yml` runs daily and on manual dispatch.
- The AppImage artifact will be available in the workflow run.

## Customization

- To build a different branch, set the `XPRA_BRANCH` environment variable locally, or use the workflow input in GitHub Actions.
- To specify a different Python version, modify the `PYTHON_VERSION` variable in the Dockerfile or set it as an environment variable.

## Notes

- This builder does not require Qt and is tailored for Xpra's Python-based build.
- All build logic is split between `build_env.sh` (environment setup) and `build_xpra.sh` (xpra build and AppImage creation).
- See [ENTRYPOINTS.md](ENTRYPOINTS.md) for details on container initialization and execution flow.
- SELinux issues are handled by using `--security-opt label=disable` in the container run command. This disables SELinux confinement for the container, allowing it to work with mounted volumes.

## Troubleshooting

### SELinux Permission Issues

If you encounter permission errors related to SELinux when running the container:

1. The script uses `--security-opt label=disable` to avoid SELinux issues with mounted volumes.
2. If you need stricter SELinux settings, you can modify `run_local.sh` to use `:z` or `:Z` volume mount options instead.
3. For persistent issues, try temporarily disabling SELinux: `sudo setenforce 0`

See the [SELINUX.md](SELINUX.md) document for detailed information on handling SELinux with container volume mounts.
