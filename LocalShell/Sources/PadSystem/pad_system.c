#include "pad_system.h"

#include <stdio.h>
#include <string.h>

#if defined(IT2PAD_HAS_IOS_SYSTEM)
#include <ios_system/ios_system.h>

int pad_ios_system(const char *command) {
    return ios_system(command);
}

int pad_ios_system_ready(void) {
    return 1;
}

void pad_ios_system_initialize(const char *home) {
    (void)home;
    initializeEnvironment();
    ios_setMiniRoot(home);
}

#else

int pad_ios_system(const char *command) {
    (void)command;
    return -1;
}

int pad_ios_system_ready(void) {
    return 0;
}

void pad_ios_system_initialize(const char *home) {
    (void)home;
}

#endif

#if defined(IT2PAD_HAS_PYTHON)

extern int python_main(int argc, char **argv);

int pad_python3_main(int argc, const char * const *argv) {
    return python_main(argc, (char **)argv);
}

int pad_python3_ready(void) {
    return 1;
}

#else

int pad_python3_main(int argc, const char * const *argv) {
    (void)argc;
    (void)argv;
    return 127;
}

int pad_python3_ready(void) {
    return 0;
}

#endif
