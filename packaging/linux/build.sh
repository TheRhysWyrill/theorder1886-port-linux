#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Builds dist/theorder-x86_64.AppImage from the Linux build (run `bash build.sh` in the repo root
# first).
#
# What is inside: theorder-probe, theorder-gpu-capabilities and libtheordergpu.so with the
# libraries a desktop may not have (SDL3, FFmpeg, xxHash, ...), a frozen copy of the same Tk
# launcher as the Windows package (PyInstaller: players need no Python), run.py and the
# preparation scripts, patches, and the documentation. The host provides glibc, the Vulkan loader
# and the GPU driver, X11/Wayland, audio and zlib, as for a native game.
#
# Usage: bash packaging/linux/build.sh
# Needs: a C compiler and static libc (the AppRun), ldd, patchelf, objdump, strip, curl
#        (appimagetool), PyInstaller, Pillow and iced-x86 (packaging/linux/ci-deps.sh).
set -euo pipefail
cd -- "$(dirname -- "$0")/../.."
[[ -f out/theorder-probe && -f out/theorder-gpu-capabilities && -f out/gpu/libtheordergpu.so ]] \
    || { echo 'Build first: bash build.sh' >&2; exit 1; }

appdir=out/AppDir
rm -rf "$appdir"
share=$appdir/usr/share/theorder
mkdir -p "$share/bin/gpu" "$appdir/usr/lib"

install -m755 out/theorder-probe out/theorder-gpu-capabilities "$share/bin/"
install -m755 out/gpu/libtheordergpu.so "$share/bin/gpu/"
cp run.py LICENSE README.md "$share/"
install -m644 packaging/linux/README-Linux.txt "$share/"
cp -r scripts patches "$share/"
mkdir -p "$share/launcher"
# The icon of the AppImage, the launcher and the game window: packaging/linux/theorder.png when it
# exists (a local choice), else the launcher's own.
icon=launcher/theorder.png
[[ -f packaging/linux/theorder.png ]] && icon=packaging/linux/theorder.png
install -m644 "$icon" "$share/launcher/theorder.png"

# The launcher also runs run.py (--run) and the preparation scripts (--script) itself, as on
# Windows: the standard modules those scripts import come along as hidden imports.
# iced-x86 (pip install iced-x86==1.21.0): scripts/isa_rewrite.py, CPUs without MOVBE/BMI1/LZCNT.
python=${PYTHON:-python3}
if ! "$python" -c 'import PyInstaller' >/dev/null 2>&1 && [[ -x out/venv/bin/python3 ]]; then
    python=$PWD/out/venv/bin/python3
fi
"$python" -c 'import PyInstaller, PIL, iced_x86' >/dev/null 2>&1 || {
    echo 'Need PyInstaller, Pillow and iced-x86: bash packaging/linux/ci-deps.sh, or put out/venv/bin first in PATH' >&2
    exit 1
}
hidden=()
for module in argparse base64 collections hashlib json re shutil socket struct tempfile threading uuid \
              xml.etree.ElementTree urllib.request iced_x86; do
    hidden+=(--hidden-import "$module")
done
"$python" -m PyInstaller --noconfirm --clean --log-level WARN --windowed --copy-metadata pillow \
    --name theorder-launcher --distpath out/pyi-dist --workpath out/pyi-work --specpath out/pyi-work \
    --paths "$PWD/scripts" "${hidden[@]}" "$PWD/launcher/port_launcher_win.py"
cp -r out/pyi-dist/theorder-launcher/. "$share/"
find "$share" -name __pycache__ -prune -exec rm -r {} +

# AppRun is static: Steam starts non-Steam games with its overlay in LD_PRELOAD, which the
# AppImage's glibc cannot load, and bash then exits with "libGL.so.1" before the launcher opens.
# The static program clears that environment, then runs the script that sets the data folder and
# the bundled libraries and starts the launcher.
cc=${CC:-cc}
"$cc" -O2 -Wall -Wextra -Werror -static packaging/linux/entry.c -o "$appdir/AppRun" || {
    echo 'Building the static AppRun failed: install a C compiler and the static libc (build-essential)' >&2
    exit 1
}
install -m755 packaging/linux/AppRun.sh "$appdir/AppRun.sh"
install -m644 packaging/linux/theorder.desktop "$appdir/theorder.desktop"
install -m644 "$icon" "$appdir/theorder.png"

# No game files and nothing a player made may ship (the same rule as the Windows package).
forbidden=$(find "$appdir" \( -iname eboot.bin -o -iname sce_module -o -iname sce_sys -o -iname savedata \
    -o -iname user -o -iname cache -o -iname '*.log' -o -iname theorder.ini -o -iname order1886.ini \
    -o -iname settings.json -o -iname mods.json -o -iname mods_presets.json -o -iname patches.json \
    -o -iname fsr4_shaders -o -iname 'nvngx_dlss*.dll' -o -iname '*.spv' -o -iname '*.pkg' \
    -o -iname '*.sprx' -o -iname '*.prx' \) -print)
if [[ -n $forbidden ]]; then
    echo 'The AppImage holds files that must not ship:' >&2
    echo "$forbidden" >&2
    exit 1
fi

# Host-provided libraries: bundling any of these breaks drivers or the display connection.
excluded='^(ld-linux.*|libc|libm|libdl|librt|libpthread|libresolv|libutil|libnsl|libanl|libvulkan|libGL|libGLX|libGLdispatch|libEGL|libOpenGL|libgbm|libdrm.*|libX11|libX11-xcb|libxcb.*|libXau|libXdmcp|libXext|libXfixes|libXrender|libXi|libXcursor|libXrandr|libwayland-.*|libasound|libudev|libpulse.*|libfontconfig|libfreetype|libOpenCL|libva.*|libvdpau|libvpl|libnvidia-.*|libcuda|libz|libstdc\+\+|libgcc_s)\.so'
declare -A seen
bundle() {
    local elf=$1 line lib name
    while read -r line; do
        lib=$(awk '/=> \//{print $3}' <<<"$line")
        [[ -n $lib ]] || continue
        name=$(basename -- "$lib")
        [[ ${seen[$name]:-} ]] && continue
        seen[$name]=1
        [[ $name =~ $excluded ]] && continue
        install -m755 "$lib" "$appdir/usr/lib/$name"
        bundle "$lib"
    done < <(ldd "$elf")
}
bundle out/gpu/libtheordergpu.so
bundle out/theorder-probe
bundle out/theorder-gpu-capabilities
# libstdc++/libgcc/libz come from the build host: the same glibc generation as the one that runs
# the AppImage is assumed, and a newer libstdc++ than Mesa's is the safe direction.
for name in libstdc++.so.6 libgcc_s.so.1; do
    install -m755 "$(ldd out/gpu/libtheordergpu.so | awk -v n="$name" '$1==n{print $3}')" "$appdir/usr/lib/$name"
done
# $ORIGIN/gpu is already the probe's RUNPATH; the libraries it needs sit in usr/lib via AppRun.
find "$appdir/usr/lib" -name '*.so*' -exec strip --strip-unneeded {} + 2>/dev/null || true

# The frozen launcher's Tk needs Xft (fontconfig, freetype) and their own dependencies: a desktop
# has them, a bare container does not, and _tkinter then stops at import with
# "libfontconfig.so.1: cannot open shared object file". They go next to the Tk library, which
# finds them through $ORIGIN; X11 and zlib stay the host's, as for the game.
patchelf_bin=${PATCHELF:-$(command -v patchelf || true)}
[[ -n $patchelf_bin ]] || { echo 'Need patchelf: apt-get install patchelf' >&2; exit 1; }
tk=$(find "$share" -name '_tkinter*.so' -print -quit)
[[ -n $tk ]] || { echo 'The frozen launcher has no _tkinter (python3-tk missing?)' >&2; exit 1; }
pylib=$(dirname -- "$tk")
launcher_host='^(ld-linux.*|libc|libm|libdl|librt|libpthread|libresolv|libutil|libnsl|libanl|libGL.*|libEGL.*|libOpenGL.*|libvulkan|libX11.*|libxcb.*|libXau|libXdmcp|libXext|libXrender|libXi|libXfixes|libXrandr|libXcursor|libwayland-.*|libz|libstdc\+\+|libgcc_s)\.so'
declare -A launcher_seen
collect_launcher_libs() {
    local elf=$1 line lib name
    while read -r line; do
        lib=$(awk '/=> \//{print $3}' <<<"$line")
        [[ -n $lib ]] || continue
        name=$(basename -- "$lib")
        [[ ${launcher_seen[$name]:-} ]] && continue
        launcher_seen[$name]=1
        [[ $name =~ $launcher_host ]] && continue
        [[ -e $pylib/$name ]] && continue
        cp -L "$lib" "$pylib/$name"
        chmod 644 "$pylib/$name"
        "$patchelf_bin" --set-rpath '$ORIGIN' "$pylib/$name" 2>/dev/null || true
        echo "  bundled $name (launcher)"
        collect_launcher_libs "$pylib/$name"
    done < <(ldd "$elf" | grep '=>')
}
for elf in "$pylib"/_tkinter*.so "$pylib"/libtcl*.so "$pylib"/libtk*.so; do
    [[ -e $elf ]] || continue  # a glob that matched nothing stays literal
    collect_launcher_libs "$elf"
done

# The newest glibc symbol in the bundle is the oldest glibc players can have. Built on a rolling
# distro it follows the host's and the AppImage stops starting on SteamOS, Debian and Fedora:
# release builds come from .github/workflows/linux-appimage.yml (Ubuntu 24.04).
# THEORDER_MAX_GLIBC raises the limit for local builds.
max_glibc=${THEORDER_MAX_GLIBC:-2.39}
need=$(find "$appdir" -type f \( -name '*.so*' -o -perm -u+x \) -exec objdump -T {} + 2>/dev/null |
       grep -o 'GLIBC_2\.[0-9.]*' | sed 's/GLIBC_//' | sort -uV | tail -1 || true)  # objdump fails on scripts
if [[ $(printf '%s\n' "$need" "$max_glibc" | sort -V | tail -1) != "$max_glibc" ]]; then
    echo "The bundle needs glibc $need, newer than $max_glibc: build on Ubuntu 24.04 (packaging/linux/ci-deps.sh) or set THEORDER_MAX_GLIBC" >&2
    exit 1
fi
echo "Minimum glibc: $need"

tool=${APPIMAGETOOL:-$(command -v appimagetool || true)}
if [[ -z $tool ]]; then
    tool=out/appimagetool-x86_64.AppImage
    [[ -x $tool ]] || {
        curl -fL -o "$tool" https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
        chmod +x "$tool"
    }
fi
mkdir -p dist
# Written aside and moved over: replacing a running AppImage in place fails ("Text file busy").
ARCH=x86_64 "$tool" --appimage-extract-and-run "$appdir" dist/theorder-x86_64.AppImage.new
mv -f dist/theorder-x86_64.AppImage.new dist/theorder-x86_64.AppImage
ls -lh dist/theorder-x86_64.AppImage
