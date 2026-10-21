#include <pthread.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>

extern int zsh_main(int argc, char **argv);
extern void pterm_bind_thread(int fd, int columns, int rows);
extern void pterm_activate_tty(void);

struct pterm_job {
    int fd;
    int columns;
    int rows;
};

static void *pterm_thread(void *raw) {
    struct pterm_job *job = raw;
    char name[] = "zsh";
    char interactive[] = "-i";
    char no_global[] = "-d";
    char *argv[] = {name, interactive, no_global, NULL};
    pterm_bind_thread(job->fd, job->columns, job->rows);
    if (job->fd >= 0) {
        dup2(job->fd, STDOUT_FILENO);
    }
    free(job);
    zsh_main(3, argv);
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
    job->fd = fd;
    job->columns = columns;
    job->rows = rows;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    result = pthread_create(&thread, &attr, pterm_thread, job);
    pthread_attr_destroy(&attr);
    if (result != 0) {
        free(job);
    }
    return result;
}

int pterm_enter_zsh(void) {
    char name[] = "zsh";
    char interactive[] = "-i";
    char no_global[] = "-d";
    char *argv[] = {name, interactive, no_global, NULL};
    pterm_activate_tty();
    return zsh_main(3, argv);
}

extern void pterm_activate_tty(void);
