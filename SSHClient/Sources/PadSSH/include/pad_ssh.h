#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct PadSSHSession PadSSHSession;

/// Connects with password and/or PEM private key. Returns NULL on failure and
/// writes a UTF-8 message into errbuf.
PadSSHSession *pad_ssh_connect(const char *host,
                               int port,
                               const char *user,
                               const char *private_key_pem,
                               const char *password,
                               char *errbuf,
                               size_t errlen);

int pad_ssh_open_shell(PadSSHSession *session, int columns, int rows);
int pad_ssh_exec(PadSSHSession *session, const char *command, int columns, int rows);
int pad_ssh_exec_control(PadSSHSession *session, const char *command);
int pad_ssh_read(PadSSHSession *session, void *buffer, size_t length);
int pad_ssh_write(PadSSHSession *session, const void *buffer, size_t length);
int pad_ssh_resize(PadSSHSession *session, int columns, int rows);
void pad_ssh_set_timeout(PadSSHSession *session, long milliseconds);
void pad_ssh_disconnect(PadSSHSession *session);

int pad_scp_send(const char *host,
                 int port,
                 const char *user,
                 const char *private_key_pem,
                 const char *password,
                 const char *local_path,
                 const char *remote_path,
                 int recursive,
                 char *errbuf,
                 size_t errlen);

int pad_scp_recv(const char *host,
                 int port,
                 const char *user,
                 const char *private_key_pem,
                 const char *password,
                 const char *remote_path,
                 const char *local_path,
                 int recursive,
                 char *errbuf,
                 size_t errlen);

int pad_sftp_list(PadSSHSession *session,
                  const char *path,
                  char *out,
                  size_t outlen);

const char *pad_ssh_auth_methods(PadSSHSession *session);
const char *pad_ssh_banner(PadSSHSession *session);
int pad_ssh_backend_ready(void);

#ifdef __cplusplus
}
#endif
