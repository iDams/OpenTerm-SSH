#ifndef SSH_AUTH_H
#define SSH_AUTH_H

#include "../../include/term_ssh.h"

term_ssh_error_t ssh_auth_try_methods(term_ssh_connection_t *conn);
term_ssh_error_t ssh_auth_password(term_ssh_connection_t *conn, const char *password);
term_ssh_error_t ssh_auth_publickey(term_ssh_connection_t *conn, const char *private_key, const char *passphrase);
term_ssh_error_t ssh_auth_interactive(term_ssh_connection_t *conn);

#endif /* SSH_AUTH_H */
