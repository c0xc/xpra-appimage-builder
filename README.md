# Xpra AppImage Builder

> This repository provides an unofficial AppImage build of Xpra.

## Motivation

The primary motivation for this builder was to make it easy to start and use Xpra for an internal project across several workstations running a variety of Linux desktop distributions.
On some systems, official Xpra packages do not exist - such as certain Debian-based distros where neither Debian nor Ubuntu packages work.
Manually building Python and Xpra was a significant, time-consuming effort: Upgrading the OS, installing a newer Python, and repeatedly running the Xpra build only to hit missing development headers, then identifying and installing the required packages (or providing headers another way), and repeating this cycle many times. Eventually, a working Xpra environment could be achieved, but the workstation would be reinstalled and all these many development packages were not meant to remain installed.

Additionally, it was necessary to try different Xpra versions for different scenarios. This builder makes that possible.

### Addressing AppImage/Flatpak Concerns

I am aware of and share many widely cited concerns about AppImages and Flatpaks (e.g., large image files, dependency issues, outdated libraries, etc.). However, when you need to run an application on a Linux distro for which official packages are not available, these concerns are secondary: The AppImage files produced by this builder were used to get Xpra running without installing development packages first.

Notice: None of this is officially supported or recommended. This builder is not intended for production use, and AppImage files released here are not fit for unlimited use of Xpra.

## Motivation: Why AppImage?

AppImage is used here to provide a portable, self-contained binary for Xpra on Linux distributions where official packages are missing or outdated. While installing from source via pip is possible, it requires many system libraries and sometimes a newer Python version, making it non-trivial and not easily repeatable. AppImage solves this by bundling everything needed in one go, despite known drawbacks like bundling too much and lacking update mechanisms.

Snap is not supported due to concerns about its distributor (Canonical) and its tracking of usage data.

**Disclaimer**

This builder was created for a private project with specific requirements. As such, not all features of Xpra are included or supported - completeness was not the primary goal. This repository is unofficial and is explicitly not intended as a replacement for the official Xpra downloads, which should be preferred for general use:
[Xpra download](https://github.com/Xpra-org/xpra/wiki/Download#-for-rpm-distributions)

Use at your own risk. Not all features are guaranteed to work - especially server functionality, which was not the focus of this build.

This project builds the latest [Xpra](https://github.com/Xpra-org/xpra) as an AppImage in a reproducible container, for use on many Linux distributions.

## Download

You can find pre-built AppImage binaries on the [GitHub Releases page](https://github.com/c0xc/xpra-appimage-builder/releases).

## Usage example

...

## Codecs (decoder)

```
$ ./Xpra-x86_64.AppImage encoding | grep 264
 x264enc, vp8enc, vp9enc
* dec_openh264         : /tmp/.mount_Xpra-xjcdMJO/usr/pyenv/lib/python3.10/site-packages/xpra/codecs/openh264/decoder.cpython-310-x86_64-linux-gnu.so
* enc_openh264         : /tmp/.mount_Xpra-xjcdMJO/usr/pyenv/lib/python3.10/site-packages/xpra/codecs/openh264/encoder.cpython-310-x86_64-linux-gnu.so
* enc_x264             : No module named 'xpra.codecs.x264'
* openh264                        : 2.6.0
```

## GitHub Actions

- The workflow in `.github/workflows/build-xpra.yml` runs daily and on manual dispatch.
- The AppImage artifact will be available in the workflow run.

## Customization

- To build a different branch, set the `XPRA_BRANCH` environment variable locally, or use the workflow input in GitHub Actions.


