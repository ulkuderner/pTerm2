#include <dlfcn.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/uio.h>
#include <termios.h>
#include <unistd.h>

/* Active only on a zsh thread. The interface thread keeps the system calls. */
static _Thread_local int pterm_tty_active = 0;
static _Thread_local int pterm_fd = -1;
static _Thread_local int pterm_stdio_ready = 0;
static _Thread_local dev_t pterm_out_dev = 0;
static _Thread_local ino_t pterm_out_ino = 0;
static _Thread_local dev_t pterm_err_dev = 0;
static _Thread_local ino_t pterm_err_ino = 0;
static _Thread_local dev_t pterm_in_dev = 0;
static _Thread_local ino_t pterm_in_ino = 0;
static _Thread_local struct termios saved_termios;
static _Thread_local struct winsize window_size = {40, 120, 0, 0};

/* Redirect only the original stdout/stderr. A pipe dup2'd onto fd 1 has a
 * different inode and must keep it, or `bindkey | while` prints the keymap
 * and the reader waits forever. */
static int pterm_redirect_fd(int fd) {
    struct stat st;
    if (!pterm_tty_active || pterm_fd < 0 || !pterm_stdio_ready || fstat(fd, &st) != 0) {
        return fd;
    }
    if (fd == STDOUT_FILENO && st.st_dev == pterm_out_dev && st.st_ino == pterm_out_ino) {
        return pterm_fd;
    }
    if (fd == STDERR_FILENO && st.st_dev == pterm_err_dev && st.st_ino == pterm_err_ino) {
        return pterm_fd;
    }
    return fd;
}

void pterm_activate_tty(void) {
    pterm_tty_active = 1;
}

void pterm_set_winsize(int fd, int columns, int rows);

void pterm_bind_thread(int fd, int columns, int rows) {
    struct stat st;
    pterm_tty_active = 1;
    pterm_fd = fd;
    if (fstat(STDOUT_FILENO, &st) == 0) {
        pterm_out_dev = st.st_dev;
        pterm_out_ino = st.st_ino;
    }
    if (fstat(STDERR_FILENO, &st) == 0) {
        pterm_err_dev = st.st_dev;
        pterm_err_ino = st.st_ino;
    }
    if (fstat(STDIN_FILENO, &st) == 0) {
        pterm_in_dev = st.st_dev;
        pterm_in_ino = st.st_ino;
    }
    pterm_stdio_ready = 1;
    pterm_set_winsize(fd, columns, rows);
}

int pterm_tty_fd(void) {
    return pterm_tty_active ? pterm_fd : -1;
}

struct pterm_size_slot {
    int fd;
    struct winsize size;
};

static struct pterm_size_slot pterm_sizes[16];
static pthread_mutex_t pterm_size_lock = PTHREAD_MUTEX_INITIALIZER;

void pterm_set_winsize(int fd, int columns, int rows) {
    struct winsize size = {40, 120, 0, 0};
    if (columns > 0) {
        size.ws_col = (unsigned short)columns;
    }
    if (rows > 0) {
        size.ws_row = (unsigned short)rows;
    }
    pthread_mutex_lock(&pterm_size_lock);
    for (int index = 0; index < 16; index++) {
        if (pterm_sizes[index].fd == fd || pterm_sizes[index].fd == 0) {
            pterm_sizes[index].fd = fd;
            if (pterm_sizes[index].size.ws_col > 0 && columns <= 0) {
                size.ws_col = pterm_sizes[index].size.ws_col;
            }
            if (pterm_sizes[index].size.ws_row > 0 && rows <= 0) {
                size.ws_row = pterm_sizes[index].size.ws_row;
            }
            pterm_sizes[index].size = size;
            break;
        }
    }
    pthread_mutex_unlock(&pterm_size_lock);
    window_size = size;
}

static struct winsize pterm_winsize(int fd) {
    struct winsize size = window_size;
    pthread_mutex_lock(&pterm_size_lock);
    for (int index = 0; index < 16; index++) {
        if (pterm_sizes[index].fd == fd) {
            size = pterm_sizes[index].size;
            break;
        }
    }
    pthread_mutex_unlock(&pterm_size_lock);
    return size;
}

__attribute__((constructor))
static void load_window_size(void) {
    const char *columns = getenv("COLUMNS");
    const char *lines = getenv("LINES");
    if (columns && atoi(columns) > 0) {
        window_size.ws_col = (unsigned short)atoi(columns);
    }
    if (lines && atoi(lines) > 0) {
        window_size.ws_row = (unsigned short)atoi(lines);
    }
}

ssize_t write(int fd, const void *buffer, size_t count) {
    fd = pterm_redirect_fd(fd);
    ssize_t (*real_write)(int, const void *, size_t) = dlsym(RTLD_NEXT, "write");
    return real_write ? real_write(fd, buffer, count) : -1;
}

ssize_t writev(int fd, const struct iovec *iov, int iovcnt) {
    fd = pterm_redirect_fd(fd);
    ssize_t (*real_writev)(int, const struct iovec *, int) = dlsym(RTLD_NEXT, "writev");
    return real_writev ? real_writev(fd, iov, iovcnt) : -1;
}

/* In-process zsh keeps the UI process stdin. Keystrokes arrive on the socket.
 * Remap reads of the original stdin (including a dup zsh made of it) onto that
 * socket. A pipe or a sourced file has a different inode and is left alone. */
static int pterm_redirect_read_fd(int fd) {
    struct stat st;
    if (!pterm_tty_active || pterm_fd < 0 || !pterm_stdio_ready || fd < 0 || fstat(fd, &st) != 0) {
        return fd;
    }
    if (st.st_dev == pterm_in_dev && st.st_ino == pterm_in_ino) {
        return pterm_fd;
    }
    return fd;
}

ssize_t read(int fd, void *buffer, size_t count) {
    fd = pterm_redirect_read_fd(fd);
    ssize_t (*real_read)(int, void *, size_t) = dlsym(RTLD_NEXT, "read");
    return real_read ? real_read(fd, buffer, count) : -1;
}

ssize_t readv(int fd, const struct iovec *iov, int iovcnt) {
    fd = pterm_redirect_read_fd(fd);
    ssize_t (*real_readv)(int, const struct iovec *, int) = dlsym(RTLD_NEXT, "readv");
    return real_readv ? real_readv(fd, iov, iovcnt) : -1;
}

int isatty(int fd) {
    if (!pterm_tty_active) {
        int (*real)(int) = dlsym(RTLD_NEXT, "isatty");
        return real ? real(fd) : 0;
    }
    if (fd == pterm_fd || (fd >= 0 && fd <= 2)) {
        return 1;
    }
    struct stat st, tty;
    if (pterm_fd >= 0 && fstat(fd, &st) == 0 && fstat(pterm_fd, &tty) == 0 &&
        st.st_dev == tty.st_dev && st.st_ino == tty.st_ino) {
        return 1;
    }
    return 0;
}

int tcgetattr(int fd, struct termios *termios) {
    if (!pterm_tty_active) {
        int (*real)(int, struct termios *) = dlsym(RTLD_NEXT, "tcgetattr");
        return real ? real(fd, termios) : -1;
    }
    if (!termios) {
        return -1;
    }
    *termios = saved_termios;
    termios->c_lflag |= ECHO | ICANON | ISIG;
    return 0;
}

int tcsetattr(int fd, int action, const struct termios *termios) {
    if (!pterm_tty_active) {
        int (*real)(int, int, const struct termios *) = dlsym(RTLD_NEXT, "tcsetattr");
        return real ? real(fd, action, termios) : -1;
    }
    if (termios) {
        saved_termios = *termios;
    }
    return 0;
}

int tcsetpgrp(int fd, pid_t pgrp) {
    if (!pterm_tty_active) {
        int (*real)(int, pid_t) = dlsym(RTLD_NEXT, "tcsetpgrp");
        return real ? real(fd, pgrp) : -1;
    }
    (void)fd;
    (void)pgrp;
    return 0;
}

int tcgetpgrp(int fd) {
    if (!pterm_tty_active) {
        pid_t (*real)(int) = dlsym(RTLD_NEXT, "tcgetpgrp");
        return real ? real(fd) : -1;
    }
    (void)fd;
    return getpgrp();
}

int ioctl(int fd, unsigned long request, ...) {
    va_list args;
    va_start(args, request);
    void *argument = va_arg(args, void *);
    va_end(args);

    if (pterm_tty_active && request == TIOCGWINSZ) {
        struct winsize *size = argument;
        if (size) {
            *size = pterm_winsize(pterm_fd);
        }
        return 0;
    }
    if (pterm_tty_active && request == TIOCSWINSZ) {
        struct winsize *size = argument;
        if (size) {
            window_size = *size;
        }
        return 0;
    }

    typedef int (*ioctl_fn)(int, unsigned long, void *);
    ioctl_fn real_ioctl = (ioctl_fn)dlsym(RTLD_NEXT, "ioctl");
    if (!real_ioctl) {
        return -1;
    }
    return real_ioctl(fd, request, argument);
}

int tgetent(char *buffer, const char *name) {
    (void)buffer;
    (void)name;
    return 0;
}

int tgetnum(char *id) {
    (void)id;
    return -1;
}

int tgetflag(char *id) {
    (void)id;
    return 0;
}

char *tgetstr(char *id, char **area) {
    (void)id;
    (void)area;
    return 0;
}

char *tgoto(const char *cap, int column, int row) {
    (void)column;
    (void)row;
    return (char *)cap;
}

int tputs(const char *text, int lines, int (*output)(int)) {
    (void)lines;
    if (!text || !output) {
        return 0;
    }
    for (const char *cursor = text; *cursor; cursor++) {
        output((unsigned char)*cursor);
    }
    return 0;
}
