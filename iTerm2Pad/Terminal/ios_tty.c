#include <dlfcn.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

/* Active only on a zsh thread. The interface thread keeps the system calls. */
static _Thread_local int pterm_tty_active = 0;
static _Thread_local int pterm_fd = -1;
static _Thread_local struct termios saved_termios;
static _Thread_local struct winsize window_size = {40, 120, 0, 0};

void pterm_activate_tty(void) {
    pterm_tty_active = 1;
}

void pterm_set_winsize(int fd, int columns, int rows);

void pterm_bind_thread(int fd, int columns, int rows) {
    pterm_tty_active = 1;
    pterm_fd = fd;
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
    if (pterm_tty_active && pterm_fd >= 0 && (fd == STDOUT_FILENO || fd == STDERR_FILENO)) {
        fd = pterm_fd;
    }
    ssize_t (*real_write)(int, const void *, size_t) = dlsym(RTLD_NEXT, "write");
    return real_write ? real_write(fd, buffer, count) : -1;
}

int isatty(int fd) {
    if (!pterm_tty_active) {
        int (*real)(int) = dlsym(RTLD_NEXT, "isatty");
        return real ? real(fd) : 0;
    }
    return fd == pterm_fd || (fd >= 0 && fd <= 2);
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
