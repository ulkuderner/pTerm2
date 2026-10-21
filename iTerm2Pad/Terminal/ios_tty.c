#include <dlfcn.h>
#include <stdarg.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

/* Active only inside the zsh child. The app process keeps the system calls. */
static int pterm_tty_active = 0;
static struct termios saved_termios;
static struct winsize window_size = {40, 120, 0, 0};

void pterm_activate_tty(void) {
    pterm_tty_active = 1;
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

int isatty(int fd) {
    if (!pterm_tty_active) {
        int (*real)(int) = dlsym(RTLD_NEXT, "isatty");
        return real ? real(fd) : 0;
    }
    return fd >= 0 && fd <= 2;
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
            *size = window_size;
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
