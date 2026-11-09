#ifndef HERDER_PTY_SPAWN_H
#define HERDER_PTY_SPAWN_H

#include <sys/types.h>

/// Starts `path` with the terminal `slave` as its controlling terminal and its
/// standard streams, in a session of its own, in `directory`.
///
/// Returns 0 and sets `*pid`, or returns the error that stopped it: from
/// `fork`, or from starting the program, as `posix_spawn` would.
///
/// `pid_slot`, if not `NULL`, points into one of `envp`'s strings, at
/// `pid_slot_size` bytes the child overwrites with its own pid in decimal,
/// NUL-terminated, before it starts the program: a variable set to a pid
/// nobody knows until the fork.
int herder_pty_spawn(
    pid_t *pid,
    const char *path,
    char *const argv[],
    char *const envp[],
    const char *directory,
    int slave,
    char *pid_slot,
    size_t pid_slot_size
);

#endif
