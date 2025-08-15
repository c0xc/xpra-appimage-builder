# Xpra AppImage Builder

> This repository provides an unofficial AppImage build of Xpra.

**Disclaimer**

This builder was created for a private project with specific requirements. As such, not all features of Xpra are included or supported - completeness was not the primary goal. This repository is unofficial and is explicitly not intended as a replacement for the official Xpra downloads, which should be preferred for general use:
[Xpra download](https://github.com/Xpra-org/xpra/wiki/Download#-for-rpm-distributions)

Use at your own risk. Not all features are guaranteed to work - especially server functionality, which was not the focus of this build.

This project builds the latest [Xpra](https://github.com/Xpra-org/xpra) as an AppImage in a reproducible container, for use on many Linux distributions.

## Download

You can find pre-built AppImage binaries on the [GitHub Releases page](https://github.com/c0xc/xpra-appimage-builder/releases).

## Usage example

...

### GitHub Actions

- The workflow in `.github/workflows/build-xpra.yml` runs daily and on manual dispatch.
- The AppImage artifact will be available in the workflow run.

## Customization

- To build a different branch, set the `XPRA_BRANCH` environment variable locally, or use the workflow input in GitHub Actions.


