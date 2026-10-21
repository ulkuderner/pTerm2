#include <TargetConditionals.h>
#include <stddef.h>

#if !TARGET_OS_SIMULATOR
extern int zsh_main(int argc, char **argv);

int pterm_enter_zsh(void) {
    char name[] = "zsh";
    char interactive[] = "-i";
    char noGlobal[] = "-d";
    char *argv[] = {name, interactive, noGlobal, NULL};
    return zsh_main(3, argv);
}
#endif
