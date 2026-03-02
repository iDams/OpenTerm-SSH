#ifndef TERM_SSH_H
#define TERM_SSH_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Version */
#define TERM_SSH_VERSION_MAJOR 0
#define TERM_SSH_VERSION_MINOR 1
#define TERM_SSH_VERSION_PATCH 0

/* Error codes */
typedef enum {
  TERM_SSH_OK = 0,
  TERM_SSH_ERROR = -1,
  TERM_SSH_ERROR_ALLOC = -2,
  TERM_SSH_ERROR_TIMEOUT = -3,
  TERM_SSH_ERROR_AUTH = -4,
  TERM_SSH_ERROR_CONNECTION = -5,
  TERM_SSH_ERROR_PROTOCOL = -6,
  TERM_SSH_ERROR_FILE = -7,
} term_ssh_error_t;

/* Auth methods */
typedef enum {
  TERM_SSH_AUTH_NONE = 0,
  TERM_SSH_AUTH_PASSWORD = 1 << 0,
  TERM_SSH_AUTH_PUBLICKEY = 1 << 1,
  TERM_SSH_AUTH_INTERACTIVE = 1 << 2,
} term_ssh_auth_method_t;

/* Key types */
typedef enum {
  TERM_SSH_KEY_UNKNOWN = 0,
  TERM_SSH_KEY_RSA,
  TERM_SSH_KEY_ECDSA,
  TERM_SSH_KEY_ED25519,
  TERM_SSH_KEY_RSA_CERT,
  TERM_SSH_KEY_ECDSA_CERT,
  TERM_SSH_KEY_ED25519_CERT,
} term_ssh_key_type_t;

/* Host key verification states */
typedef enum {
  TERM_SSH_HOSTKEY_OK = 0,
  TERM_SSH_HOSTKEY_NEW,
  TERM_SSH_HOSTKEY_CHANGED,
  TERM_SSH_HOSTKEY_OTHER,
  TERM_SSH_HOSTKEY_FILE_NOT_FOUND,
} term_ssh_hostkey_state_t;

/* Host key verification decision */
typedef enum {
  TERM_SSH_HOSTKEY_REJECT = 0,
  TERM_SSH_HOSTKEY_ACCEPT_ONCE,
  TERM_SSH_HOSTKEY_ACCEPT_AND_SAVE,
} term_ssh_hostkey_decision_t;

/* Log levels */
typedef enum {
  TERM_SSH_LOG_NONE = 0,
  TERM_SSH_LOG_ERROR,
  TERM_SSH_LOG_WARNING,
  TERM_SSH_LOG_INFO,
  TERM_SSH_LOG_DEBUG,
} term_ssh_log_level_t;

/* Forward declarations */
typedef struct term_ssh_session term_ssh_session_t;
typedef struct term_ssh_connection term_ssh_connection_t;
typedef struct term_ssh_sftp term_ssh_sftp_t;

/* Connection config */
typedef struct {
  const char *host;
  uint16_t port;
  const char *username;
  const char *password;
  const char *private_key_path;
  const char *passphrase;
  int timeout_ms;
  term_ssh_auth_method_t auth_methods;
  bool strict_host_key;
  const char *known_hosts_file;
} term_ssh_config_t;

/* Callback types */
typedef void (*term_ssh_log_callback_t)(term_ssh_log_level_t level,
                                        const char *message, void *userdata);
typedef int (*term_ssh_progress_callback_t)(unsigned long current,
                                            unsigned long total,
                                            void *userdata);
typedef term_ssh_hostkey_decision_t (*term_ssh_hostkey_callback_t)(
    term_ssh_hostkey_state_t state, const char *host, uint16_t port,
    term_ssh_key_type_t key_type, const char *fingerprint_sha256,
    const char *fingerprint_md5, void *userdata);

/* Session functions */
term_ssh_error_t term_ssh_init(void);
void term_ssh_cleanup(void);
const char *term_ssh_version(void);

/* Session management */
term_ssh_session_t *term_ssh_session_new(void);
void term_ssh_session_free(term_ssh_session_t *session);
term_ssh_error_t
term_ssh_session_set_log_callback(term_ssh_session_t *session,
                                  term_ssh_log_callback_t callback,
                                  void *userdata);
term_ssh_error_t term_ssh_session_set_log_level(term_ssh_session_t *session,
                                                term_ssh_log_level_t level);
term_ssh_error_t
term_ssh_session_set_hostkey_callback(term_ssh_session_t *session,
                                      term_ssh_hostkey_callback_t callback,
                                      void *userdata);

/* Host key management */
term_ssh_error_t
term_ssh_hostkey_get_fingerprint(term_ssh_session_t *session, const char *host,
                                 uint16_t port, char **fingerprint_sha256,
                                 char **fingerprint_md5,
                                 term_ssh_key_type_t *key_type);

term_ssh_error_t
term_ssh_hostkey_save_to_known_hosts(term_ssh_session_t *session,
                                     const char *host, uint16_t port,
                                     const char *known_hosts_file);

/* Connection functions */
term_ssh_error_t term_ssh_connect(term_ssh_connection_t **conn,
                                  term_ssh_session_t *session,
                                  const term_ssh_config_t *config);
term_ssh_error_t term_ssh_disconnect(term_ssh_connection_t *conn);
void term_ssh_connection_free(term_ssh_connection_t *conn);
bool term_ssh_is_connected(term_ssh_connection_t *conn);

/* Execute commands */
term_ssh_error_t term_ssh_execute(term_ssh_connection_t *conn,
                                  const char *command, char **output,
                                  size_t *output_len);

/* Interactive Channel / PTY functions */
typedef void term_ssh_channel_t;

term_ssh_channel_t *
term_ssh_channel_new_interactive(term_ssh_connection_t *conn);
void term_ssh_channel_free_interactive(term_ssh_channel_t *channel);
term_ssh_error_t
term_ssh_channel_open_session_interactive(term_ssh_channel_t *channel);
term_ssh_error_t term_ssh_channel_request_pty_interactive(
    term_ssh_channel_t *channel, const char *terminal, int cols, int rows);
term_ssh_error_t
term_ssh_channel_change_pty_size_interactive(term_ssh_channel_t *channel,
                                             int cols, int rows);
term_ssh_error_t
term_ssh_channel_request_shell_interactive(term_ssh_channel_t *channel);
int term_ssh_channel_read_interactive(term_ssh_channel_t *channel, void *buffer,
                                      uint32_t count, int is_stderr);
int term_ssh_channel_read_nonblocking_interactive(term_ssh_channel_t *channel,
                                                  void *buffer, uint32_t count,
                                                  int is_stderr);
int term_ssh_channel_poll_timeout_interactive(term_ssh_channel_t *channel,
                                              int timeout, int is_stderr);
int term_ssh_channel_write_interactive(term_ssh_channel_t *channel,
                                       const void *data, uint32_t len);
void term_ssh_channel_send_eof_interactive(term_ssh_channel_t *channel);
int term_ssh_channel_is_eof_interactive(term_ssh_channel_t *channel);
int term_ssh_channel_is_open_interactive(term_ssh_channel_t *channel);

/* SFTP functions */
term_ssh_error_t term_ssh_sftp_init(term_ssh_sftp_t **sftp,
                                    term_ssh_connection_t *conn);
void term_ssh_sftp_free(term_ssh_sftp_t *sftp);
term_ssh_error_t term_ssh_sftp_upload(term_ssh_sftp_t *sftp,
                                      const char *local_path,
                                      const char *remote_path,
                                      term_ssh_progress_callback_t callback,
                                      void *userdata);
term_ssh_error_t term_ssh_sftp_download(term_ssh_sftp_t *sftp,
                                        const char *remote_path,
                                        const char *local_path,
                                        term_ssh_progress_callback_t callback,
                                        void *userdata);
term_ssh_error_t term_ssh_sftp_list(term_ssh_sftp_t *sftp, const char *path,
                                    char ***files, size_t *count);
term_ssh_error_t term_ssh_sftp_mkdir(term_ssh_sftp_t *sftp, const char *path);
term_ssh_error_t term_ssh_sftp_remove(term_ssh_sftp_t *sftp, const char *path);
term_ssh_error_t term_ssh_sftp_rename(term_ssh_sftp_t *sftp,
                                      const char *old_path,
                                      const char *new_path);

#ifdef __cplusplus
}
#endif

#endif /* TERM_SSH_H */
