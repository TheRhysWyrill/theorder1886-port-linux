#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Opens the launcher from the AppImage on a virtual display and checks it is still running a few
# seconds later: a missing glibc version, a library the bundle forgot or an unusable Tk stops it
# at import. Run as root in a fresh container of the distribution to check; it installs Xvfb and
# what a desktop has under it (.github/workflows/linux-appimage.yml).
# Usage: smoke-test.sh path/to/theorder-x86_64.AppImage
set -euo pipefail
[[ $# == 1 ]] || { echo "Usage: $0 path/to/theorder-x86_64.AppImage" >&2; exit 2; }
appimage=$(readlink -f -- "$1")
# What a desktop has and a bare container does not: an X server, the X client stack, fontconfig
# (its configuration and fonts are the host's) and a font. The image brings its own Python, Tk,
# Xft, fontconfig and freetype, which the check below holds it to.
if command -v apt-get >/dev/null; then
    apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        xvfb fontconfig fonts-dejavu-core \
        libx11-6 libxext6 libxrender1 libxi6 libxfixes3 libxrandr2 libxcursor1 >/dev/null
elif command -v dnf >/dev/null; then
    dnf install -y -q xorg-x11-server-Xvfb fontconfig dejavu-sans-fonts \
        libX11 libXext libXrender libXi libXfixes libXrandr libXcursor >/dev/null
elif command -v zypper >/dev/null; then
    zypper -nq install xorg-x11-server-Xvfb fontconfig dejavu-fonts \
        libX11-6 libXext6 libXrender1 libXi6 libXfixes3 libXrandr2 libXcursor1 >/dev/null
elif command -v pacman >/dev/null; then
    pacman -Sy --noconfirm --needed xorg-server-xvfb fontconfig ttf-dejavu \
        libx11 libxext libxrender libxi libxfixes libxrandr libxcursor >/dev/null
fi
grep -m1 PRETTY_NAME /etc/os-release
ldd --version | sed -n 1p  # head would end ldd with SIGPIPE (pipefail)
work=$(mktemp -d)
cd "$work"
"$appimage" --appimage-extract >/dev/null
# The launcher's text stack ships with it: without it, a system that is not a full desktop stops
# at `import tkinter` with "libfontconfig.so.1: cannot open shared object file".
tk=$(find squashfs-root -name '_tkinter*.so' -print -quit)
[[ -n $tk ]] || { echo 'FAIL: the image has no _tkinter' >&2; exit 1; }
tk_dir=$(dirname -- "$tk")
for name in libXft.so.2 libfontconfig.so.1 libfreetype.so.6 libexpat.so.1; do
    [[ -n $(find "$tk_dir" -name "$name" -print -quit) ]] || {
        echo "FAIL: the image has no $name next to _tkinter" >&2
        exit 1
    }
done
Xvfb :99 -screen 0 1280x800x24 >/dev/null 2>&1 &
export DISPLAY=:99 HOME=$work
sleep 2
status=0
timeout 20 squashfs-root/AppRun > launcher.log 2>&1 || status=$?
cat launcher.log
if [[ $status != 124 ]] || grep -qE 'GLIBC_|ImportError|Traceback' launcher.log; then
    # The usual cause: a library the image should have carried.
    find squashfs-root -name '_tkinter*.so' -exec ldd {} + 2>/dev/null | grep 'not found' || true
    echo "FAIL: the launcher exited ($status) instead of staying open" >&2
    exit 1
fi
echo 'OK: the launcher stayed open'
