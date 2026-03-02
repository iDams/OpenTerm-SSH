#ifndef SSH_CORE_H
#define SSH_CORE_H

#include "../../include/term_ssh.h"

struct term_ssh_session {
    void *ssh;
    term_ssh_log_callback_t log_callback;
    void *log_userdata;
    term_ssh_log_level_t log_level;
    term_ssh_hostkey_callback_t hostkey_callback;
    void *hostkey_userdata;
};

term_ssh_error_t ssh_core_init(term_ssh_session_t *session);
void ssh_core_cleanup(term_ssh_session_t *session);
void ssh_core_log(term_ssh_session_t *session, term_ssh_log_level_t level, const char *format, ...);

#endif /* SSH_CORE_H */
