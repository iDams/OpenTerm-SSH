#ifndef SSH_HOSTKEY_H
#define SSH_HOSTKEY_H

#include "../../include/term_ssh.h"

term_ssh_key_type_t ssh_hostkey_type_from_libssh(int type);
term_ssh_error_t ssh_hostkey_get_info(term_ssh_session_t *session,
                                       void *ssh_session,
                                       const char *host,
                                       uint16_t port,
                                       char **fingerprint_sha256,
                                       char **fingerprint_md5,
                                       term_ssh_key_type_t *key_type);
term_ssh_error_t ssh_hostkey_write_to_known_hosts(void *ssh_session,
                                                   const char *host,
                                                   uint16_t port,
                                                   const char *known_hosts_file);

#endif /* SSH_HOSTKEY_H */
