#include "pad_ssh.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(IT2PAD_HAS_LIBSSH2)
#include <libssh2.h>
#include <libssh2_sftp.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <sys/socket.h>
#include <unistd.h>

struct PadSSHSession {
    int sock;
    LIBSSH2_SESSION *session;
    LIBSSH2_CHANNEL *channel;
};

static int tcp_connect(const char *host, int port, char *errbuf, size_t errlen) {
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    char portbuf[16];
    snprintf(portbuf, sizeof(portbuf), "%d", port);
    struct addrinfo *res = NULL;
    int rc = getaddrinfo(host, portbuf, &hints, &res);
    if (rc != 0 || res == NULL) {
        snprintf(errbuf, errlen, "getaddrinfo: %s", gai_strerror(rc));
        return -1;
    }
    int sock = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    if (sock < 0) {
        snprintf(errbuf, errlen, "socket failed");
        freeaddrinfo(res);
        return -1;
    }
    if (connect(sock, res->ai_addr, res->ai_addrlen) != 0) {
        snprintf(errbuf, errlen, "connect failed");
        close(sock);
        freeaddrinfo(res);
        return -1;
    }
    freeaddrinfo(res);
    return sock;
}

static int authenticate(LIBSSH2_SESSION *session,
                        const char *user,
                        const char *private_key_pem,
                        const char *password,
                        char *errbuf,
                        size_t errlen) {
    if (private_key_pem && private_key_pem[0]) {
        int rc = libssh2_userauth_publickey_frommemory(session,
                                                       user,
                                                       strlen(user),
                                                       NULL,
                                                       0,
                                                       private_key_pem,
                                                       strlen(private_key_pem),
                                                       password);
        if (rc == 0) {
            return 0;
        }
    }
    if (password && password[0]) {
        int rc = libssh2_userauth_password(session, user, password);
        if (rc == 0) {
            return 0;
        }
    }
    snprintf(errbuf, errlen, "authentication failed");
    return -1;
}

PadSSHSession *pad_ssh_connect(const char *host,
                               int port,
                               const char *user,
                               const char *private_key_pem,
                               const char *password,
                               char *errbuf,
                               size_t errlen) {
    libssh2_init(0);
    int sock = tcp_connect(host, port, errbuf, errlen);
    if (sock < 0) {
        return NULL;
    }
    LIBSSH2_SESSION *session = libssh2_session_init();
    if (!session) {
        snprintf(errbuf, errlen, "libssh2_session_init failed");
        close(sock);
        return NULL;
    }
    libssh2_session_set_blocking(session, 1);
    if (libssh2_session_handshake(session, sock) != 0) {
        snprintf(errbuf, errlen, "SSH handshake failed");
        libssh2_session_free(session);
        close(sock);
        return NULL;
    }
    if (authenticate(session, user, private_key_pem, password, errbuf, errlen) != 0) {
        libssh2_session_disconnect(session, "auth");
        libssh2_session_free(session);
        close(sock);
        return NULL;
    }
    PadSSHSession *out = calloc(1, sizeof(*out));
    if (!out) {
        libssh2_session_free(session);
        close(sock);
        return NULL;
    }
    out->sock = sock;
    out->session = session;
    return out;
}

int pad_ssh_open_shell(PadSSHSession *session, int columns, int rows) {
    if (!session) {
        return -1;
    }
    session->channel = libssh2_channel_open_session(session->session);
    if (!session->channel) {
        return -1;
    }
    if (libssh2_channel_request_pty_size(session->channel, columns, rows) != 0) {
        libssh2_channel_request_pty(session->channel, "xterm-256color");
    } else {
        libssh2_channel_request_pty_size(session->channel, columns, rows);
    }
    libssh2_channel_request_pty(session->channel, "xterm-256color");
    libssh2_channel_request_pty_size(session->channel, columns, rows);
    return libssh2_channel_shell(session->channel);
}

int pad_ssh_exec(PadSSHSession *session, const char *command, int columns, int rows) {
    if (!session) {
        return -1;
    }
    session->channel = libssh2_channel_open_session(session->session);
    if (!session->channel) {
        return -1;
    }
    libssh2_channel_request_pty(session->channel, "xterm-256color");
    libssh2_channel_request_pty_size(session->channel, columns, rows);
    return libssh2_channel_exec(session->channel, command);
}

int pad_ssh_read(PadSSHSession *session, void *buffer, size_t length) {
    if (!session || !session->channel) {
        return -1;
    }
    return (int)libssh2_channel_read(session->channel, buffer, length);
}

int pad_ssh_write(PadSSHSession *session, const void *buffer, size_t length) {
    if (!session || !session->channel) {
        return -1;
    }
    return (int)libssh2_channel_write(session->channel, buffer, length);
}

int pad_ssh_resize(PadSSHSession *session, int columns, int rows) {
    if (!session || !session->channel) {
        return -1;
    }
    return libssh2_channel_request_pty_size(session->channel, columns, rows);
}

void pad_ssh_disconnect(PadSSHSession *session) {
    if (!session) {
        return;
    }
    if (session->channel) {
        libssh2_channel_close(session->channel);
        libssh2_channel_free(session->channel);
    }
    if (session->session) {
        libssh2_session_disconnect(session->session, "bye");
        libssh2_session_free(session->session);
    }
    if (session->sock >= 0) {
        close(session->sock);
    }
    free(session);
}

int pad_scp_send(const char *host,
                 int port,
                 const char *user,
                 const char *private_key_pem,
                 const char *password,
                 const char *local_path,
                 const char *remote_path,
                 int recursive,
                 char *errbuf,
                 size_t errlen) {
    (void)recursive;
    char err[256];
    PadSSHSession *session = pad_ssh_connect(host, port, user, private_key_pem, password, err, sizeof(err));
    if (!session) {
        snprintf(errbuf, errlen, "%s", err);
        return -1;
    }
    FILE *fp = fopen(local_path, "rb");
    if (!fp) {
        snprintf(errbuf, errlen, "cannot open %s", local_path);
        pad_ssh_disconnect(session);
        return -1;
    }
    fseek(fp, 0, SEEK_END);
    long size = ftell(fp);
    fseek(fp, 0, SEEK_SET);
    LIBSSH2_CHANNEL *channel = libssh2_scp_send(session->session, remote_path, 0644, (size_t)size);
    if (!channel) {
        snprintf(errbuf, errlen, "scp send failed");
        fclose(fp);
        pad_ssh_disconnect(session);
        return -1;
    }
    char buf[4096];
    size_t n;
    while ((n = fread(buf, 1, sizeof(buf), fp)) > 0) {
        size_t sent = 0;
        while (sent < n) {
            ssize_t rc = libssh2_channel_write(channel, buf + sent, n - sent);
            if (rc < 0) {
                fclose(fp);
                libssh2_channel_free(channel);
                pad_ssh_disconnect(session);
                snprintf(errbuf, errlen, "scp write failed");
                return -1;
            }
            sent += (size_t)rc;
        }
    }
    fclose(fp);
    libssh2_channel_send_eof(channel);
    libssh2_channel_wait_eof(channel);
    libssh2_channel_free(channel);
    pad_ssh_disconnect(session);
    return 0;
}

int pad_scp_recv(const char *host,
                 int port,
                 const char *user,
                 const char *private_key_pem,
                 const char *password,
                 const char *remote_path,
                 const char *local_path,
                 int recursive,
                 char *errbuf,
                 size_t errlen) {
    (void)recursive;
    char err[256];
    PadSSHSession *session = pad_ssh_connect(host, port, user, private_key_pem, password, err, sizeof(err));
    if (!session) {
        snprintf(errbuf, errlen, "%s", err);
        return -1;
    }
    libssh2_struct_stat stat;
    LIBSSH2_CHANNEL *channel = libssh2_scp_recv2(session->session, remote_path, &stat);
    if (!channel) {
        snprintf(errbuf, errlen, "scp recv failed");
        pad_ssh_disconnect(session);
        return -1;
    }
    FILE *fp = fopen(local_path, "wb");
    if (!fp) {
        snprintf(errbuf, errlen, "cannot create %s", local_path);
        libssh2_channel_free(channel);
        pad_ssh_disconnect(session);
        return -1;
    }
    libssh2_struct_stat_size got = 0;
    char buf[4096];
    while (got < stat.st_size) {
        ssize_t rc = libssh2_channel_read(channel, buf, sizeof(buf));
        if (rc <= 0) {
            break;
        }
        fwrite(buf, 1, (size_t)rc, fp);
        got += rc;
    }
    fclose(fp);
    libssh2_channel_free(channel);
    pad_ssh_disconnect(session);
    return 0;
}

int pad_sftp_list(PadSSHSession *session, const char *path, char *out, size_t outlen) {
    if (!session) {
        return -1;
    }
    LIBSSH2_SFTP *sftp = libssh2_sftp_init(session->session);
    if (!sftp) {
        return -1;
    }
    LIBSSH2_SFTP_HANDLE *handle = libssh2_sftp_opendir(sftp, path);
    if (!handle) {
        libssh2_sftp_shutdown(sftp);
        return -1;
    }
    size_t used = 0;
    char name[512];
    LIBSSH2_SFTP_ATTRIBUTES attrs;
    while (libssh2_sftp_readdir(handle, name, sizeof(name), &attrs) > 0) {
        int n = snprintf(out + used, outlen > used ? outlen - used : 0, "%s\n", name);
        if (n < 0) {
            break;
        }
        used += (size_t)n;
        if (used >= outlen) {
            break;
        }
    }
    libssh2_sftp_closedir(handle);
    libssh2_sftp_shutdown(sftp);
    return 0;
}

int pad_ssh_backend_ready(void) {
    return 1;
}

#else

struct PadSSHSession {
    int unused;
};

static int unavailable(char *errbuf, size_t errlen) {
    if (errbuf && errlen) {
        snprintf(errbuf, errlen,
                 "libssh2 is not linked. Run iPad/tools/download_frameworks.sh");
    }
    return -1;
}

PadSSHSession *pad_ssh_connect(const char *host,
                               int port,
                               const char *user,
                               const char *private_key_pem,
                               const char *password,
                               char *errbuf,
                               size_t errlen) {
    (void)host; (void)port; (void)user; (void)private_key_pem; (void)password;
    unavailable(errbuf, errlen);
    return NULL;
}

int pad_ssh_open_shell(PadSSHSession *session, int columns, int rows) {
    (void)session; (void)columns; (void)rows;
    return -1;
}

int pad_ssh_exec(PadSSHSession *session, const char *command, int columns, int rows) {
    (void)session; (void)command; (void)columns; (void)rows;
    return -1;
}

int pad_ssh_read(PadSSHSession *session, void *buffer, size_t length) {
    (void)session; (void)buffer; (void)length;
    return -1;
}

int pad_ssh_write(PadSSHSession *session, const void *buffer, size_t length) {
    (void)session; (void)buffer; (void)length;
    return -1;
}

int pad_ssh_resize(PadSSHSession *session, int columns, int rows) {
    (void)session; (void)columns; (void)rows;
    return -1;
}

void pad_ssh_disconnect(PadSSHSession *session) {
    (void)session;
}

int pad_scp_send(const char *host,
                 int port,
                 const char *user,
                 const char *private_key_pem,
                 const char *password,
                 const char *local_path,
                 const char *remote_path,
                 int recursive,
                 char *errbuf,
                 size_t errlen) {
    (void)host; (void)port; (void)user; (void)private_key_pem; (void)password;
    (void)local_path; (void)remote_path; (void)recursive;
    return unavailable(errbuf, errlen);
}

int pad_scp_recv(const char *host,
                 int port,
                 const char *user,
                 const char *private_key_pem,
                 const char *password,
                 const char *remote_path,
                 const char *local_path,
                 int recursive,
                 char *errbuf,
                 size_t errlen) {
    (void)host; (void)port; (void)user; (void)private_key_pem; (void)password;
    (void)remote_path; (void)local_path; (void)recursive;
    return unavailable(errbuf, errlen);
}

int pad_sftp_list(PadSSHSession *session, const char *path, char *out, size_t outlen) {
    (void)session; (void)path; (void)out; (void)outlen;
    return -1;
}

int pad_ssh_backend_ready(void) {
    return 0;
}

#endif
