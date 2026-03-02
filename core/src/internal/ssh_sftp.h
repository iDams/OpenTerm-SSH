#ifndef SSH_SFTP_H
#define SSH_SFTP_H

#include "../../include/term_ssh.h"

struct term_ssh_sftp {
    term_ssh_connection_t *conn;
    void *sftp_session;
};

term_ssh_error_t ssh_sftp_create(term_ssh_sftp_t **sftp, term_ssh_connection_t *conn);
term_ssh_error_t ssh_sftp_get_file_info(term_ssh_sftp_t *sftp, const char *path, uint64_t *size, uint32_t *permissions);

#endif /* SSH_SFTP_H */
