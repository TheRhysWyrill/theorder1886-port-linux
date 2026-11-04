#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Second half of the AppImage entry point, started by the static AppRun (entry.c) with the host's
# LD_PRELOAD and other injected library paths already removed. Starts the frozen Tk launcher: the
# launcher picks the game folder, runs run.py and handles --play (the game without a window, for
# Steam and shortcuts).
# Usage: theorder-x86_64.AppImage [--play]
set -euo pipefail
here=$(dirname -- "$(readlink -f -- "$0")")
share=$here/usr/share/theorder

export LD_LIBRARY_PATH="$here/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
# The AppImage is read-only: settings, saves, caches and mods live in the user's data folder.
export THEORDER_DATA_DIR=${THEORDER_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/theorder}
mkdir -p "$THEORDER_DATA_DIR"

cd -- "$share"
exec "$share/theorder-launcher" "$@"
