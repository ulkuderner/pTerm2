#pragma once

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Runs a command through ios_system when that framework is linked; otherwise
/// returns -1 so Swift’s CommandRegistry can handle it.
int pad_ios_system(const char *command);

/// 1 when ios_system.framework was linked at build time.
int pad_ios_system_ready(void);

/// Initializes ios_system dictionaries when present. Safe to call when absent.
void pad_ios_system_initialize(const char *home);

/// Starts CPython 3.13 when the official iOS framework is embedded.
int pad_python3_main(int argc, const char * const *argv);

int pad_python3_ready(void);

#ifdef __cplusplus
}
#endif
