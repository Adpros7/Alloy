#include "include/cpty.h"
#include <util.h>        // openpty / forkpty (macOS)
#include <unistd.h>
#include <sys/ioctl.h>
#include <stdlib.h>
#include <string.h>

int cpty_spawn(const char *shell, pid_t *child_pid, int cols, int rows) {
    struct winsize ws = { .ws_row = (unsigned short)rows,
                          .ws_col = (unsigned short)cols };
    int master_fd = -1;
    pid_t pid = forkpty(&master_fd, NULL, NULL, &ws);
    if (pid < 0) return -1;
    if (pid == 0) {
        // Child: exec the shell.
        char *args[] = { (char *)shell, NULL };
        execvp(shell, args);
        _exit(127);
    }
    if (child_pid) *child_pid = pid;
    return master_fd;
}

int cpty_resize(int master_fd, int cols, int rows) {
    struct winsize ws = { .ws_row = (unsigned short)rows,
                          .ws_col = (unsigned short)cols };
    return ioctl(master_fd, TIOCSWINSZ, &ws);
}
