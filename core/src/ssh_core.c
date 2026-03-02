#include "ssh_core.h"
#include <libssh/libssh.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>

static bool g_initialized = false;

term_ssh_error_t term_ssh_init(void) {
    if (g_initialized) {
        return TERM_SSH_OK;
    }
    
    if (ssh_init() != SSH_OK) {
        return TERM_SSH_ERROR;
    }
    
    g_initialized = true;
    return TERM_SSH_OK;
}

void term_ssh_cleanup(void) {
    if (g_initialized) {
        ssh_finalize();
        g_initialized = false;
    }
}

const char *term_ssh_version(void) {
    static char version[64];
    snprintf(version, sizeof(version), "%d.%d.%d",
             TERM_SSH_VERSION_MAJOR,
             TERM_SSH_VERSION_MINOR,
             TERM_SSH_VERSION_PATCH);
    return version;
}

term_ssh_session_t *term_ssh_session_new(void) {
    term_ssh_session_t *session = calloc(1, sizeof(term_ssh_session_t));
    if (!session) {
        return NULL;
    }
    
    session->log_level = TERM_SSH_LOG_WARNING;
    
    if (ssh_core_init(session) != TERM_SSH_OK) {
        free(session);
        return NULL;
    }
    
    return session;
}

void term_ssh_session_free(term_ssh_session_t *session) {
    if (!session) {
        return;
    }
    
    ssh_core_cleanup(session);
    free(session);
}

term_ssh_error_t term_ssh_session_set_log_callback(term_ssh_session_t *session, 
                                                    term_ssh_log_callback_t callback, 
                                                    void *userdata) {
    if (!session) {
        return TERM_SSH_ERROR;
    }
    
    session->log_callback = callback;
    session->log_userdata = userdata;
    return TERM_SSH_OK;
}

term_ssh_error_t term_ssh_session_set_log_level(term_ssh_session_t *session, 
                                                 term_ssh_log_level_t level) {
    if (!session) {
        return TERM_SSH_ERROR;
    }
    
    session->log_level = level;
    return TERM_SSH_OK;
}

term_ssh_error_t term_ssh_session_set_hostkey_callback(term_ssh_session_t *session,
                                                        term_ssh_hostkey_callback_t callback,
                                                        void *userdata) {
    if (!session) {
        return TERM_SSH_ERROR;
    }
    
    session->hostkey_callback = callback;
    session->hostkey_userdata = userdata;
    return TERM_SSH_OK;
}

term_ssh_error_t ssh_core_init(term_ssh_session_t *session) {
    if (!session) {
        return TERM_SSH_ERROR;
    }
    
    session->ssh = ssh_new();
    if (!session->ssh) {
        return TERM_SSH_ERROR_ALLOC;
    }
    
    return TERM_SSH_OK;
}

void ssh_core_cleanup(term_ssh_session_t *session) {
    if (!session || !session->ssh) {
        return;
    }
    
    ssh_free(session->ssh);
    session->ssh = NULL;
}

void ssh_core_log(term_ssh_session_t *session, term_ssh_log_level_t level, const char *format, ...) {
    if (!session || !session->log_callback || level > session->log_level) {
        return;
    }
    
    char buffer[1024];
    va_list args;
    va_start(args, format);
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    
    session->log_callback(level, buffer, session->log_userdata);
}
