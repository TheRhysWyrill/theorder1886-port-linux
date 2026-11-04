The Order: 1886 for PC (theorder1886-port) - Linux AppImage
===========================================================

No game files are included. You need your own copy of The Order: 1886 as a folder that contains
eboot.bin, sce_module and sce_sys (tested: CUSA00035, version 01.02).

Running
1. chmod +x theorder-x86_64.AppImage
2. Run it: the launcher opens. On Game, choose the game folder (the one with eboot.bin), then PLAY
   on Home. The first start takes longer while the game image is prepared and the shaders are built.
   ./theorder-x86_64.AppImage --play starts the game with the saved settings and no window (this is
   what Steam and the desktop shortcut use).
3. Steam Deck / Game Mode: Advanced > Add to Steam writes a non-Steam shortcut with the artwork and
   the --play launch option; adding the AppImage as a non-Steam game by hand works too.

Requirements
- x86-64 Linux with glibc 2.39 or newer: Ubuntu 24.04+, Debian 13+, Fedora 40+, Arch, SteamOS 3.6+.
- A 64-bit processor with AVX. On CPUs without MOVBE, BMI1 or LZCNT the loader rewrites the game's
  instructions that use them (an ISA: line in the log); older CPUs stop at "STOP: this CPU lacks".
- A graphics card with Vulkan 1.3 and a current driver (Mesa, NVIDIA).
- An X11 or Wayland desktop (Wayland runs the window through XWayland). Python and the libraries
  are inside the AppImage.
- FUSE 2 or 3 to mount the AppImage. Without it: APPIMAGE_EXTRACT_AND_RUN=1 ./theorder-x86_64.AppImage

What is inside
- The same Tk launcher as the Windows package, frozen with PyInstaller: the game folder and the
  update folder, graphics (upscaler, preset, output resolution, display mode, vsync, frame limit,
  engine frame rate, aspect ratio, anisotropy), performance options, mods and their order, game
  patches, control remapping (keyboard and gamepad), save backups, the log and the diagnostic
  report, the desktop entry, the Steam shortcut and the update check.
- run.py and the preparation scripts, patches/, the port itself (theorder-probe,
  libtheordergpu.so) and the libraries a desktop may not have (SDL3, FFmpeg, xxHash, ...).
- glibc, the Vulkan loader and the GPU driver, X11/Wayland, audio and zlib come from the system,
  as for a native game.

Linux options (Advanced page)
- Menu entry and icon: writes theorder.desktop to ~/.local/share/applications so the launcher and
  the game show their icon in the dock and the menu; turning it off removes the entry.
- Window system: Automatic (SDL chooses), Wayland or X11 (pick X11 if the window misbehaves).
- GameMode and MangoHud when they are installed.
- Desktop shortcut: a .desktop file in the applications menu and on the desktop.
- Add to Steam: the shortcut, icon, capsules, background and logo for every Steam account of this
  user. Steam must be closed, or it rewrites its shortcuts when it exits.

Files
- User data lives in ~/.local/share/theorder (THEORDER_DATA_DIR overrides it): settings.json,
  theorder.ini, user/ (saves, shader and pipeline caches), mods/, patches.json, last_run.log.
- An AppImage is a single read-only file. "Check for updates" opens the release page: download the
  new AppImage and replace this one; saves, settings and mods stay in the data folder. A release
  that only has a Windows package is skipped, and pre-releases are never offered.

Building it yourself
  bash packaging/linux/ci-deps.sh   # Ubuntu 24.04: Vulkan-Headers 1.4, VMA, SDL3, PyInstaller
  bash build.sh
  PATH="$PWD/out/venv/bin:$PATH" bash packaging/linux/build.sh
The result is dist/theorder-x86_64.AppImage. .github/workflows/linux-appimage.yml does the same on
Ubuntu 24.04, opens the launcher on Debian 13, Fedora 42, Ubuntu 24.04, Arch and openSUSE
Tumbleweed, keeps the file as an artifact, and publishes it for a linux-v* tag.
