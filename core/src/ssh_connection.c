#include "ssh_connection.h"
#include "ssh_auth.h"
#include "ssh_core.h"
#include "ssh_hostkey.h"
#include <libssh/libssh.h>
#include <stdlib.h>
#include <string.h>

term_ssh_error_t term_ssh_connect(term_ssh_connection_t **conn,
                                  term_ssh_session_t *session,
                                  const term_ssh_config_t *config) {
  if (!conn || !session || !config || !config->host) {
    return TERM_SSH_ERROR;
  }

  term_ssh_error_t ret;

  ret = ssh_connection_create(conn, session);
  if (ret != TERM_SSH_OK) {
    return ret;
  }

  ret = ssh_connection_configure(*conn, config);
  if (ret != TERM_SSH_OK) {
    term_ssh_connection_free(*conn);
    *conn = NULL;
    return ret;
  }

  ssh_core_log(session, TERM_SSH_LOG_INFO, "Conectando a %s:%d", config->host,
               config->port);

  int ssh_ret = ssh_connect((*conn)->session->ssh);
  if (ssh_ret != SSH_OK) {
    ssh_core_log(session, TERM_SSH_LOG_ERROR, "Error al conectar: %s",
                 ssh_get_error((*conn)->session->ssh));
    term_ssh_connection_free(*conn);
    *conn = NULL;
    return TERM_SSH_ERROR_CONNECTION;
  }

  if (config->strict_host_key) {
    int state = ssh_is_server_known((*conn)->session->ssh);
    term_ssh_hostkey_state_t hk_state;

    switch (state) {
    case SSH_SERVER_KNOWN_OK:
      break;
    case SSH_SERVER_KNOWN_CHANGED:
      hk_state = TERM_SSH_HOSTKEY_CHANGED;
      goto handle_hostkey_callback;
    case SSH_SERVER_FOUND_OTHER:
      hk_state = TERM_SSH_HOSTKEY_OTHER;
      goto handle_hostkey_callback;
    case SSH_SERVER_NOT_KNOWN:
      hk_state = TERM_SSH_HOSTKEY_NEW;
      goto handle_hostkey_callback;
    case SSH_SERVER_FILE_NOT_FOUND:
      hk_state = TERM_SSH_HOSTKEY_FILE_NOT_FOUND;
      goto handle_hostkey_callback;
    case SSH_SERVER_ERROR:
      ssh_core_log(session, TERM_SSH_LOG_ERROR, "Error verificando host key");
      term_ssh_disconnect(*conn);
      return TERM_SSH_ERROR_AUTH;
    default:
      break;
    }
    goto auth_continue;

  handle_hostkey_callback:;
    char *fp_sha256 = NULL;
    char *fp_md5 = NULL;
    term_ssh_key_type_t key_type = TERM_SSH_KEY_UNKNOWN;

    ssh_hostkey_get_info(session, (*conn)->session->ssh, config->host,
                         config->port, &fp_sha256, &fp_md5, &key_type);

    if (session->hostkey_callback) {
      term_ssh_hostkey_decision_t decision = session->hostkey_callback(
          hk_state, config->host, config->port, key_type, fp_sha256, fp_md5,
          session->hostkey_userdata);

      if (fp_sha256)
        ssh_string_free_char(fp_sha256);
      if (fp_md5)
        ssh_string_free_char(fp_md5);

      switch (decision) {
      case TERM_SSH_HOSTKEY_REJECT:
        ssh_core_log(session, TERM_SSH_LOG_INFO,
                     "Host key rechazada por el usuario");
        term_ssh_disconnect(*conn);
        return TERM_SSH_ERROR_AUTH;
      case TERM_SSH_HOSTKEY_ACCEPT_ONCE:
        ssh_core_log(session, TERM_SSH_LOG_INFO,
                     "Host key aceptada temporalmente");
        break;
      case TERM_SSH_HOSTKEY_ACCEPT_AND_SAVE:
        ssh_core_log(session, TERM_SSH_LOG_INFO,
                     "Guardando host key en known_hosts");
        term_ssh_error_t save_result = ssh_hostkey_write_to_known_hosts(
            (*conn)->session->ssh, config->host, config->port,
            config->known_hosts_file);
        if (save_result != TERM_SSH_OK) {
          ssh_core_log(session, TERM_SSH_LOG_ERROR,
                       "Error guardando host key en known_hosts");
          term_ssh_disconnect(*conn);
          return TERM_SSH_ERROR_FILE;
        }
        ssh_core_log(session, TERM_SSH_LOG_INFO,
                     "Host key guardada exitosamente");
        break;
      }
    } else {
      ssh_core_log(session, TERM_SSH_LOG_ERROR,
                   "Host key no verificada. Agrega el host a known_hosts antes "
                   "de conectar.");
      if (fp_sha256)
        ssh_string_free_char(fp_sha256);
      if (fp_md5)
        ssh_string_free_char(fp_md5);
      term_ssh_disconnect(*conn);
      return TERM_SSH_ERROR_AUTH;
    }
  }

auth_continue:

  ret = ssh_connection_authenticate(*conn);
  if (ret != TERM_SSH_OK) {
    term_ssh_disconnect(*conn);
    return ret;
  }

  (*conn)->connected = true;
  ssh_core_log(session, TERM_SSH_LOG_INFO, "Conexión establecida exitosamente");

  return TERM_SSH_OK;
}

term_ssh_error_t term_ssh_disconnect(term_ssh_connection_t *conn) {
  if (!conn || !conn->connected) {
    return TERM_SSH_OK;
  }

  if (conn->channel) {
    ssh_channel_close(conn->channel);
    ssh_channel_free(conn->channel);
    conn->channel = NULL;
  }

  if (conn->session && conn->session->ssh) {
    ssh_disconnect(conn->session->ssh);
  }

  conn->connected = false;
  ssh_core_log(conn->session, TERM_SSH_LOG_INFO, "Desconectado");

  return TERM_SSH_OK;
}

void term_ssh_connection_free(term_ssh_connection_t *conn) {
  if (!conn) {
    return;
  }

  term_ssh_disconnect(conn);
  free(conn);
}

bool term_ssh_is_connected(term_ssh_connection_t *conn) {
  return conn && conn->connected;
}

term_ssh_error_t term_ssh_execute(term_ssh_connection_t *conn,
                                  const char *command, char **output,
                                  size_t *output_len) {
  if (!conn || !conn->connected || !command || !output || !output_len) {
    return TERM_SSH_ERROR;
  }

  ssh_channel channel = ssh_channel_new(conn->session->ssh);
  if (!channel) {
    return TERM_SSH_ERROR_ALLOC;
  }

  if (ssh_channel_open_session(channel) != SSH_OK) {
    ssh_channel_free(channel);
    return TERM_SSH_ERROR;
  }

  if (ssh_channel_request_exec(channel, command) != SSH_OK) {
    ssh_channel_close(channel);
    ssh_channel_free(channel);
    return TERM_SSH_ERROR;
  }

  char buffer[4096];
  size_t total_len = 0;
  char *result = NULL;
  int nbytes;

  while ((nbytes = ssh_channel_read(channel, buffer, sizeof(buffer), 0)) > 0) {
    char *new_result = realloc(result, total_len + nbytes + 1);
    if (!new_result) {
      free(result);
      ssh_channel_close(channel);
      ssh_channel_free(channel);
      return TERM_SSH_ERROR_ALLOC;
    }

    result = new_result;
    memcpy(result + total_len, buffer, nbytes);
    total_len += nbytes;
    result[total_len] = '\0';
  }

  ssh_channel_send_eof(channel);
  ssh_channel_close(channel);
  ssh_channel_free(channel);

  *output = result;
  *output_len = total_len;

  return TERM_SSH_OK;
}

term_ssh_error_t ssh_connection_create(term_ssh_connection_t **conn,
                                       term_ssh_session_t *session) {
  if (!conn || !session) {
    return TERM_SSH_ERROR;
  }

  *conn = calloc(1, sizeof(term_ssh_connection_t));
  if (!*conn) {
    return TERM_SSH_ERROR_ALLOC;
  }

  (*conn)->session = session;
  (*conn)->connected = false;

  return TERM_SSH_OK;
}

term_ssh_error_t ssh_connection_configure(term_ssh_connection_t *conn,
                                          const term_ssh_config_t *config) {
  if (!conn || !config) {
    return TERM_SSH_ERROR;
  }

  memcpy(&conn->config, config, sizeof(term_ssh_config_t));

  if (config->port > 0) {
    unsigned int port = config->port;
    ssh_options_set(conn->session->ssh, SSH_OPTIONS_PORT, &port);
  }

  if (config->host) {
    ssh_options_set(conn->session->ssh, SSH_OPTIONS_HOST, config->host);
  }

  if (config->username) {
    ssh_options_set(conn->session->ssh, SSH_OPTIONS_USER, config->username);
  }

  if (config->timeout_ms > 0) {
    int timeout_sec = config->timeout_ms / 1000;
    ssh_options_set(conn->session->ssh, SSH_OPTIONS_TIMEOUT, &timeout_sec);
  }

  if (config->strict_host_key) {
    ssh_options_set(conn->session->ssh, SSH_OPTIONS_STRICTHOSTKEYCHECK, "yes");
  } else {
    ssh_options_set(conn->session->ssh, SSH_OPTIONS_STRICTHOSTKEYCHECK, "no");
  }

  if (config->known_hosts_file) {
    ssh_options_set(conn->session->ssh, SSH_OPTIONS_KNOWNHOSTS,
                    config->known_hosts_file);
  }

  if (config->private_key_path) {
    ssh_options_set(conn->session->ssh, SSH_OPTIONS_IDENTITY,
                    config->private_key_path);
  }

  return TERM_SSH_OK;
}

term_ssh_error_t ssh_connection_authenticate(term_ssh_connection_t *conn) {
  return ssh_auth_try_methods(conn);
}

/* Interactive Channel / PTY functions implementation */

term_ssh_channel_t *
term_ssh_channel_new_interactive(term_ssh_connection_t *conn) {
  if (!conn || !conn->connected || !conn->session || !conn->session->ssh)
    return NULL;
  ssh_channel channel = ssh_channel_new(conn->session->ssh);
  return (term_ssh_channel_t *)channel;
}

void term_ssh_channel_free_interactive(term_ssh_channel_t *channel) {
  if (channel) {
    ssh_channel_free((ssh_channel)channel);
  }
}

term_ssh_error_t
term_ssh_channel_open_session_interactive(term_ssh_channel_t *channel) {
  if (!channel)
    return TERM_SSH_ERROR;
  int rc = ssh_channel_open_session((ssh_channel)channel);
  return (rc == SSH_OK) ? TERM_SSH_OK : TERM_SSH_ERROR;
}

term_ssh_error_t term_ssh_channel_request_pty_interactive(
    term_ssh_channel_t *channel, const char *terminal, int cols, int rows) {
  if (!channel || !terminal)
    return TERM_SSH_ERROR;

  // GUI apps don't have a local TTY, so encode_current_tty_opts fails in
  // libssh. Explicitly send an empty modes array (just TTY_OP_END = 0), which
  // makes the remote server use its default sensible PTY options (ECHO, ONLCR,
  // etc).
  unsigned char empty_modes[1] = {0};
  int rc = ssh_channel_request_pty_size_modes((ssh_channel)channel, terminal,
                                              cols, rows, empty_modes, 1);
  return (rc == SSH_OK) ? TERM_SSH_OK : TERM_SSH_ERROR;
}

term_ssh_error_t
term_ssh_channel_change_pty_size_interactive(term_ssh_channel_t *channel,
                                             int cols, int rows) {
  if (!channel)
    return TERM_SSH_ERROR;
  int rc = ssh_channel_change_pty_size((ssh_channel)channel, cols, rows);
  return (rc == SSH_OK) ? TERM_SSH_OK : TERM_SSH_ERROR;
}

term_ssh_error_t
term_ssh_channel_request_shell_interactive(term_ssh_channel_t *channel) {
  if (!channel)
    return TERM_SSH_ERROR;
  int rc = ssh_channel_request_shell((ssh_channel)channel);
  return (rc == SSH_OK) ? TERM_SSH_OK : TERM_SSH_ERROR;
}

int term_ssh_channel_read_interactive(term_ssh_channel_t *channel, void *buffer,
                                      uint32_t count, int is_stderr) {
  if (!channel || !buffer)
    return -1;
  return ssh_channel_read((ssh_channel)channel, buffer, count, is_stderr);
}

int term_ssh_channel_read_nonblocking_interactive(term_ssh_channel_t *channel,
                                                  void *buffer, uint32_t count,
                                                  int is_stderr) {
  if (!channel || !buffer)
    return -1;
  return ssh_channel_read_nonblocking((ssh_channel)channel, buffer, count,
                                      is_stderr);
}

int term_ssh_channel_poll_timeout_interactive(term_ssh_channel_t *channel,
                                              int timeout, int is_stderr) {
  if (!channel)
    return -1;
  return ssh_channel_poll_timeout((ssh_channel)channel, timeout, is_stderr);
}

int term_ssh_channel_write_interactive(term_ssh_channel_t *channel,
                                       const void *data, uint32_t len) {
  if (!channel || !data)
    return -1;
  return ssh_channel_write((ssh_channel)channel, data, len);
}

void term_ssh_channel_send_eof_interactive(term_ssh_channel_t *channel) {
  if (channel) {
    ssh_channel_send_eof((ssh_channel)channel);
  }
}

int term_ssh_channel_is_eof_interactive(term_ssh_channel_t *channel) {
  if (!channel)
    return 1;
  return ssh_channel_is_eof((ssh_channel)channel);
}

int term_ssh_channel_is_open_interactive(term_ssh_channel_t *channel) {
  if (!channel)
    return 0;
  return ssh_channel_is_open((ssh_channel)channel);
}
