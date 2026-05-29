#include "cpty.h"

#include <util.h>      /* forkpty */
#include <termios.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <stdlib.h>

pid_t alloy_pty_spawn(const char *path, int rows, int cols, int *out_master_fd) {
    struct winsize ws;
    ws.ws_row = (unsigned short)rows;
    ws.ws_col = (unsigned short)cols;
    ws.ws_xpixel = 0;
    ws.ws_ypixel = 0;

    int master = -1;
    pid_t pid = forkpty(&master, NULL, NULL, &ws);
    if (pid < 0) {
        return -1;
    }

    if (pid == 0) {
        /* Child: become an interactive login shell with a sane terminal env. */
        setenv("TERM", "xterm-256color", 1);
        setenv("COLORTERM", "truecolor", 1);
        char *const argv[] = { (char *)path, "-il", NULL };
        execvp(path, argv);
        _exit(127); /* exec failed */
    }

    if (out_master_fd) {
        *out_master_fd = master;
    }
    return pid;
}

void alloy_pty_set_size(int master_fd, int rows, int cols) {
    struct winsize ws;
    ws.ws_row = (unsigned short)rows;
    ws.ws_col = (unsigned short)cols;
    ws.ws_xpixel = 0;
    ws.ws_ypixel = 0;
    ioctl(master_fd, TIOCSWINSZ, &ws);
}
