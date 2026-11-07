#include "PTYSpawn.h"

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <spawn.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <unistd.h>

// `posix_spawn` alone cannot do this. It runs its file actions before it
// starts the new session, so the terminal it opens is opened by a process
// that is not yet a session leader and never becomes the controlling one.
// Without a controlling terminal a resize sends no SIGWINCH, and closing the
// terminal hangs up nobody.
//
// So: fork, start the session and take the terminal, then hand the rest to
// `posix_spawn` with `POSIX_SPAWN_SETEXEC`, which replaces the child in place
// and does the descriptors, the directory and the signals in one call. Between
// the fork and that call the child makes system calls and nothing else, since
// another thread of the parent may have held a lock when it forked.
int herder_pty_spawn(
    pid_t *pid,
    const char *path,
    char *const argv[],
    char *const envp[],
    const char *directory,
    int slave
) {
    posix_spawn_file_actions_t actions;
    int error = posix_spawn_file_actions_init(&actions);
    if (error != 0) return error;
    posix_spawnattr_t attributes;
    error = posix_spawnattr_init(&attributes);
    if (error != 0) {
        posix_spawn_file_actions_destroy(&actions);
        return error;
    }

    posix_spawn_file_actions_adddup2(&actions, slave, 0);
    posix_spawn_file_actions_adddup2(&actions, slave, 1);
    posix_spawn_file_actions_adddup2(&actions, slave, 2);
    posix_spawn_file_actions_addchdir(&actions, directory);

    sigset_t defaults, empty;
    sigfillset(&defaults);
    sigemptyset(&empty);
    posix_spawnattr_setsigdefault(&attributes, &defaults);
    posix_spawnattr_setsigmask(&attributes, &empty);
    // CLOEXEC_DEFAULT: the child gets the three descriptors above and nothing
    // else the app happens to have open.
    posix_spawnattr_setflags(
        &attributes,
        POSIX_SPAWN_SETEXEC | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT
    );

    // How the child says it could not start: anything written here is the
    // error, and the pipe closing unwritten, at the exec, is success.
    int report[2];
    if (pipe(report) != 0) {
        error = errno;
        posix_spawnattr_destroy(&attributes);
        posix_spawn_file_actions_destroy(&actions);
        return error;
    }
    fcntl(report[0], F_SETFD, FD_CLOEXEC);
    fcntl(report[1], F_SETFD, FD_CLOEXEC);

    // Blocked over the fork, so that no handler of the parent's runs in the
    // child. The spawn's own mask unblocks them all again.
    sigset_t all, previous;
    sigfillset(&all);
    pthread_sigmask(SIG_SETMASK, &all, &previous);

    pid_t child = fork();
    if (child == 0) {
        int status;
        // Cleared because a spawn that execs in place will not copy a
        // close-on-exec descriptor. CLOEXEC_DEFAULT still closes this one.
        if (setsid() < 0 || ioctl(slave, TIOCSCTTY, 0) < 0 || fcntl(slave, F_SETFD, 0) < 0) {
            status = errno;
        } else {
            status = posix_spawn(NULL, path, &actions, &attributes, argv, envp);
        }
        write(report[1], &status, sizeof status);
        _exit(127);
    }

    error = child < 0 ? errno : 0;
    pthread_sigmask(SIG_SETMASK, &previous, NULL);
    close(report[1]);
    posix_spawnattr_destroy(&attributes);
    posix_spawn_file_actions_destroy(&actions);

    if (error == 0) {
        int status = 0;
        ssize_t count;
        do {
            count = read(report[0], &status, sizeof status);
        } while (count < 0 && errno == EINTR);
        if (count == sizeof status) {
            while (waitpid(child, NULL, 0) < 0 && errno == EINTR) {}
            error = status;
        } else {
            *pid = child;
        }
    }
    close(report[0]);
    return error;
}
