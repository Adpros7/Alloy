/*
 * cpty.h — tiny pseudo-terminal spawn helper.
 *
 * The fork/exec dance is awkward and unsafe to express in Swift, so we keep it in
 * C: `alloy_pty_spawn` calls forkpty(), sets TERM, and execs the shell. Swift then
 * reads/writes the returned master fd.
 */
#ifndef ALLOY_CPTY_H
#define ALLOY_CPTY_H

#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Spawn `path` (e.g. "/bin/zsh") connected to a new PTY of size rows x cols.
 * On success returns the child pid and writes the master fd to *out_master_fd.
 * Returns -1 on failure.
 */
pid_t alloy_pty_spawn(const char *path, int rows, int cols, int *out_master_fd);

/* Update the PTY window size (sends SIGWINCH to the child). */
void alloy_pty_set_size(int master_fd, int rows, int cols);

#ifdef __cplusplus
}
#endif

#endif /* ALLOY_CPTY_H */
