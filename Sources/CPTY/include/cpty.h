#pragma once
#include <sys/types.h>
#include <termios.h>

/// Opens a pseudo-terminal pair and forks a child running `shell`.
/// Returns master fd; sets *child_pid. Returns -1 on error.
int cpty_spawn(const char *shell, pid_t *child_pid, int cols, int rows);

/// Resize the terminal attached to master_fd.
int cpty_resize(int master_fd, int cols, int rows);
