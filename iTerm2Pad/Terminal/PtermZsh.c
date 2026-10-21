#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>
#include <string.h>

extern int zsh_main(int argc, char **argv);
extern void pterm_bind_thread(int fd, int columns, int rows);
extern void pterm_activate_tty(void);
extern void pterm_mark_inprocess(void);

struct pterm_job {
    int fd;
    int columns;
    int rows;
};

static pthread_mutex_t pterm_zsh_lock = PTHREAD_MUTEX_INITIALIZER;
static int pterm_zsh_running = 0;
static char pterm_home_rc[1024];

void pterm_release_zsh(void) {
    pthread_mutex_lock(&pterm_zsh_lock);
    pterm_zsh_running = 0;
    pthread_mutex_unlock(&pterm_zsh_lock);
}

int pterm_try_chroot(const char *root) {
    if (!root || !*root || chroot(root) != 0) {
        return 0;
    }
    chdir("/home/mobile");
    return 1;
}

const char *pterm_zshrc_path(void) {
    return pterm_home_rc[0] ? pterm_home_rc : NULL;
}

void pterm_set_shell_home(const char *home) {
    if (!home || !*home) {
        return;
    }
    setenv("HOME", home, 1);
    setenv("ZDOTDIR", home, 1);
    snprintf(pterm_home_rc, sizeof(pterm_home_rc), "%s/.zshrc", home);
    setenv("PTERM_ZSHRC", pterm_home_rc, 1);
    char command_dir[1024];
    snprintf(command_dir, sizeof(command_dir), "%s/Library/Caches/pterm-cmd", home);
    setenv("PTERM_CMD_DIR", command_dir, 1);
}

static void *pterm_thread(void *raw) {
    struct pterm_job *job = raw;
    char name[] = "zsh";
    char interactive[] = "-i";
    char no_global[] = "-d";
    char *argv[] = {name, interactive, no_global, NULL};
    const char *home = getenv("HOME");
    int fd = job->fd;
    int columns = job->columns;
    int rows = job->rows;
    free(job);
    if (home && *home) {
        chdir(home);
    }
    pterm_bind_thread(fd, columns, rows);
    pterm_mark_inprocess();
    zsh_main(3, argv);
    pterm_release_zsh();
    pthread_mutex_lock(&pterm_zsh_lock);
    pterm_zsh_running = 0;
    pthread_mutex_unlock(&pterm_zsh_lock);
    return NULL;
}

int pterm_start_zsh(int fd, int columns, int rows) {
    struct pterm_job *job = malloc(sizeof(*job));
    pthread_t thread;
    pthread_attr_t attr;
    int result;
    if (!job) {
        return 1;
    }
    pthread_mutex_lock(&pterm_zsh_lock);
    if (pterm_zsh_running) {
        pthread_mutex_unlock(&pterm_zsh_lock);
        free(job);
        return EBUSY;
    }
    pterm_zsh_running = 1;
    pthread_mutex_unlock(&pterm_zsh_lock);
    job->fd = fd;
    job->columns = columns;
    job->rows = rows;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    result = pthread_create(&thread, &attr, pterm_thread, job);
    pthread_attr_destroy(&attr);
    if (result != 0) {
        free(job);
        pthread_mutex_lock(&pterm_zsh_lock);
        pterm_zsh_running = 0;
        pthread_mutex_unlock(&pterm_zsh_lock);
    }
    return result;
}

int pterm_enter_zsh(void) {
    char name[] = "zsh";
    char interactive[] = "-i";
    char no_global[] = "-d";
    char *argv[] = {name, interactive, no_global, NULL};
    const char *home = getenv("HOME");
    const char *columns = getenv("COLUMNS");
    const char *rows = getenv("LINES");
    int width = columns ? atoi(columns) : 80;
    int height = rows ? atoi(rows) : 24;
    if (home && *home) {
        chdir(home);
    }
    pterm_bind_thread(STDIN_FILENO, width, height);
    return zsh_main(3, argv);
}

extern void pterm_activate_tty(void);
