#include "ssh_auth.h"
#include "ssh_core.h"
#include "ssh_connection.h"
#include <libssh/libssh.h>
#include <string.h>

term_ssh_error_t ssh_auth_try_methods(term_ssh_connection_t *conn) {
    if (!conn || !conn->session) {
        return TERM_SSH_ERROR;
    }
    
    ssh_core_log(conn->session, TERM_SSH_LOG_INFO, "Intentando autenticar...");

    /* Ask the server for the supported auth methods before choosing one. */
    int none_ret = ssh_userauth_none(conn->session->ssh, NULL);
    if (none_ret == SSH_AUTH_SUCCESS) {
        ssh_core_log(conn->session, TERM_SSH_LOG_INFO, "Autenticación no requerida");
        return TERM_SSH_OK;
    }

    int methods = ssh_userauth_list(conn->session->ssh, NULL);
    ssh_core_log(conn->session, TERM_SSH_LOG_DEBUG, "Métodos auth disponibles: 0x%x", methods);
    
    if (methods & SSH_AUTH_METHOD_NONE) {
        ssh_core_log(conn->session, TERM_SSH_LOG_INFO, "Autenticación no requerida");
        return TERM_SSH_OK;
    }
    
    if ((methods & SSH_AUTH_METHOD_PASSWORD) && 
        (conn->config.auth_methods & TERM_SSH_AUTH_PASSWORD) &&
        conn->config.password) {
        
        ssh_core_log(conn->session, TERM_SSH_LOG_INFO, "Intentando autenticación con contraseña");
        
        if (ssh_auth_password(conn, conn->config.password) == TERM_SSH_OK) {
            return TERM_SSH_OK;
        }
    }
    
    if ((methods & SSH_AUTH_METHOD_INTERACTIVE) &&
        (conn->config.auth_methods & TERM_SSH_AUTH_INTERACTIVE)) {
        ssh_core_log(conn->session, TERM_SSH_LOG_INFO, "Intentando autenticación interactiva");
        
        if (ssh_auth_interactive(conn) == TERM_SSH_OK) {
            return TERM_SSH_OK;
        }
    }

    if ((methods & SSH_AUTH_METHOD_PUBLICKEY) && 
        (conn->config.auth_methods & TERM_SSH_AUTH_PUBLICKEY) &&
        conn->config.private_key_path) {
        
        ssh_core_log(conn->session, TERM_SSH_LOG_INFO, "Intentando autenticación con clave pública");
        
        if (ssh_auth_publickey(conn, conn->config.private_key_path, conn->config.passphrase) == TERM_SSH_OK) {
            return TERM_SSH_OK;
        }
    }
    
    ssh_core_log(conn->session, TERM_SSH_LOG_ERROR, "Todos los métodos de autenticación fallaron");
    return TERM_SSH_ERROR_AUTH;
}

term_ssh_error_t ssh_auth_password(term_ssh_connection_t *conn, const char *password) {
    if (!conn || !password) {
        return TERM_SSH_ERROR;
    }
    
    int ret = ssh_userauth_password(conn->session->ssh, NULL, password);
    if (ret != SSH_AUTH_SUCCESS) {
        ssh_core_log(conn->session, TERM_SSH_LOG_ERROR, "Autenticación por contraseña fallida");
        return TERM_SSH_ERROR_AUTH;
    }
    
    ssh_core_log(conn->session, TERM_SSH_LOG_INFO, "Autenticación por contraseña exitosa");
    return TERM_SSH_OK;
}

term_ssh_error_t ssh_auth_publickey(term_ssh_connection_t *conn, 
                                     const char *private_key, 
                                     const char *passphrase) {
    if (!conn || !private_key) {
        return TERM_SSH_ERROR;
    }
    
    ssh_key key = NULL;
    
    if (passphrase) {
        int ret = ssh_pki_import_privkey_file(private_key, passphrase, NULL, NULL, &key);
        if (ret != SSH_OK) {
            ssh_core_log(conn->session, TERM_SSH_LOG_ERROR, "Error cargando clave privada con passphrase");
            return TERM_SSH_ERROR_AUTH;
        }
    } else {
        int ret = ssh_pki_import_privkey_file(private_key, NULL, NULL, NULL, &key);
        if (ret != SSH_OK) {
            ssh_core_log(conn->session, TERM_SSH_LOG_ERROR, "Error cargando clave privada");
            return TERM_SSH_ERROR_AUTH;
        }
    }
    
    int ret = ssh_userauth_publickey(conn->session->ssh, NULL, key);
    ssh_key_free(key);
    
    if (ret != SSH_AUTH_SUCCESS) {
        ssh_core_log(conn->session, TERM_SSH_LOG_ERROR, "Autenticación por clave pública fallida");
        return TERM_SSH_ERROR_AUTH;
    }
    
    ssh_core_log(conn->session, TERM_SSH_LOG_INFO, "Autenticación por clave pública exitosa");
    return TERM_SSH_OK;
}

term_ssh_error_t ssh_auth_interactive(term_ssh_connection_t *conn) {
    if (!conn) {
        return TERM_SSH_ERROR;
    }
    
    int ret = ssh_userauth_kbdint(conn->session->ssh, NULL, NULL);
    if (ret != SSH_AUTH_SUCCESS && ret != SSH_AUTH_INFO && ret != SSH_AUTH_AGAIN) {
        ssh_core_log(conn->session, TERM_SSH_LOG_ERROR, "Autenticación interactiva fallida");
        return TERM_SSH_ERROR_AUTH;
    }
    
    while (ret == SSH_AUTH_INFO) {
        const char *name = ssh_userauth_kbdint_getname(conn->session->ssh);
        const char *instruction = ssh_userauth_kbdint_getinstruction(conn->session->ssh);
        int nprompts = ssh_userauth_kbdint_getnprompts(conn->session->ssh);
        
        ssh_core_log(conn->session, TERM_SSH_LOG_DEBUG, "KB-INT: %s - %s", name ? name : "", instruction ? instruction : "");
        
        for (int i = 0; i < nprompts; i++) {
            char echo = 0;
            const char *prompt = ssh_userauth_kbdint_getprompt(conn->session->ssh, i, &echo);
            ssh_core_log(conn->session, TERM_SSH_LOG_DEBUG, "Prompt: %s", prompt ? prompt : "");

            if (!conn->config.password) {
                ssh_core_log(conn->session, TERM_SSH_LOG_ERROR, "No hay password configurada para autenticacion interactiva");
                return TERM_SSH_ERROR_AUTH;
            }

            if (ssh_userauth_kbdint_setanswer(conn->session->ssh, i, conn->config.password) < 0) {
                ssh_core_log(conn->session, TERM_SSH_LOG_ERROR, "No se pudo responder prompt interactivo");
                return TERM_SSH_ERROR_AUTH;
            }
        }
        
        ret = ssh_userauth_kbdint(conn->session->ssh, NULL, NULL);
    }
    
    if (ret != SSH_AUTH_SUCCESS) {
        return TERM_SSH_ERROR_AUTH;
    }
    
    ssh_core_log(conn->session, TERM_SSH_LOG_INFO, "Autenticación interactiva exitosa");
    return TERM_SSH_OK;
}
