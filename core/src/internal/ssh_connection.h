#ifndef SSH_CONNECTION_H
#define SSH_CONNECTION_H

#include "../../include/term_ssh.h"

struct term_ssh_connection {
    term_ssh_session_t *session;
    void *channel;
    term_ssh_config_t config;
    bool connected;
};

term_ssh_error_t ssh_connection_create(term_ssh_connection_t **conn, term_ssh_session_t *session);
term_ssh_error_t ssh_connection_configure(term_ssh_connection_t *conn, const term_ssh_config_t *config);
term_ssh_error_t ssh_connection_authenticate(term_ssh_connection_t *conn);

#endif /* SSH_CONNECTION_H */
