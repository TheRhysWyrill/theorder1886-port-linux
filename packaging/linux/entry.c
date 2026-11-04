// SPDX-License-Identifier: GPL-2.0-or-later
// AppRun of the Linux AppImage: a static program that removes the host's library injection from
// the environment, then runs AppRun.sh beside it.
//
// Steam starts every non-Steam game with LD_PRELOAD=.../gameoverlayrenderer.so (any compatibility
// tool, Steam Deck included). Loaded into the AppImage's own glibc, the overlay cannot find its
// libGL.so.1 and the first dynamic program, bash, exits at once: "error while loading shared
// libraries: libGL.so.1". Being static, this program is not affected. LD_LIBRARY_PATH, GTK_PATH
// and the like name host libraries just as incompatible with the bundle; Steam's Vulkan layers
// (overlay, fossilize) are host libraries too.
//
// The shell script keeps the start-up logic (data directory, bundled libraries, launcher).
#define _GNU_SOURCE
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void drop(const char *name) {
    const char *value = getenv(name);
    if (!value || !*value) {
        unsetenv(name);
        return;
    }
    // Kept for diagnostics (the launcher's log shows the environment problems).
    static const char prefix[] = "THEORDER_HOST_";
    char saved[128];
    size_t length = strlen(name);
    if (length + sizeof prefix <= sizeof saved) {
        memcpy(saved, prefix, sizeof prefix - 1);
        memcpy(saved + sizeof prefix - 1, name, length + 1);
        setenv(saved, value, 1);
    }
    unsetenv(name);
}

int main(int argc, char **argv) {
    (void)argc;
    static const char *const host_only[] = {
        "LD_PRELOAD", "LD_LIBRARY_PATH", "LD_AUDIT", "GTK_PATH", "GTK_MODULES", "GTK_EXE_PREFIX",
        "GIO_EXTRA_MODULES", "GDK_PIXBUF_MODULEDIR", "PYTHONHOME", "PYTHONPATH",
    };
    for (size_t i = 0; i < sizeof host_only / sizeof host_only[0]; ++i) {
        drop(host_only[i]);
    }
    setenv("DISABLE_VK_LAYER_VALVE_steam_overlay_1", "1", 1);
    setenv("DISABLE_VK_LAYER_VALVE_steam_fossilize_1", "1", 1);

    char exe[PATH_MAX];
    ssize_t length = readlink("/proc/self/exe", exe, sizeof exe - 1);
    if (length <= 0 || (size_t)length >= sizeof exe - 1) {
        perror("theorder: /proc/self/exe");
        return 127;
    }
    exe[length] = '\0';
    char *slash = strrchr(exe, '/');
    if (!slash) {
        fprintf(stderr, "theorder: cannot find the AppImage folder\n");
        return 127;
    }
    *slash = '\0';

    static const char suffix[] = "/AppRun.sh";
    size_t dir_length = strlen(exe);
    char script[PATH_MAX];
    if (dir_length + sizeof suffix > sizeof script) {
        fprintf(stderr, "theorder: the AppImage path is too long\n");
        return 127;
    }
    memcpy(script, exe, dir_length);
    memcpy(script + dir_length, suffix, sizeof suffix);
    argv[0] = script;
    execv(script, argv);
    perror("theorder: AppRun.sh");
    return 127;
}
