#include "ssh_hostkey.h"
#include "ssh_core.h"
#include <libssh/libssh.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

term_ssh_key_type_t ssh_hostkey_type_from_libssh(int type) {
    switch (type) {
        case SSH_KEYTYPE_RSA:
            return TERM_SSH_KEY_RSA;
        case SSH_KEYTYPE_RSA_CERT01:
            return TERM_SSH_KEY_RSA_CERT;
        case SSH_KEYTYPE_ECDSA_P256:
        case SSH_KEYTYPE_ECDSA_P384:
        case SSH_KEYTYPE_ECDSA_P521:
            return TERM_SSH_KEY_ECDSA;
        case SSH_KEYTYPE_ECDSA_P256_CERT01:
        case SSH_KEYTYPE_ECDSA_P384_CERT01:
        case SSH_KEYTYPE_ECDSA_P521_CERT01:
            return TERM_SSH_KEY_ECDSA_CERT;
        case SSH_KEYTYPE_ED25519:
            return TERM_SSH_KEY_ED25519;
        case SSH_KEYTYPE_ED25519_CERT01:
            return TERM_SSH_KEY_ED25519_CERT;
        default:
            return TERM_SSH_KEY_UNKNOWN;
    }
}

term_ssh_error_t ssh_hostkey_get_info(term_ssh_session_t *session,
                                       void *ssh_sess,
                                       const char *host,
                                       uint16_t port,
                                       char **fingerprint_sha256,
                                       char **fingerprint_md5,
                                       term_ssh_key_type_t *key_type) {
    (void)host;
    (void)port;
    
    if (!ssh_sess) {
        return TERM_SSH_ERROR;
    }

    ssh_key server_key = NULL;
    int rc = ssh_get_server_publickey((ssh_session)ssh_sess, &server_key);
    if (rc != SSH_OK) {
        ssh_core_log(session, TERM_SSH_LOG_ERROR, "No se pudo obtener la clave del servidor");
        return TERM_SSH_ERROR;
    }

    if (key_type) {
        *key_type = ssh_hostkey_type_from_libssh(ssh_key_type(server_key));
    }

    if (fingerprint_sha256) {
        unsigned char *hash = NULL;
        size_t hash_len = 0;
        rc = ssh_get_publickey_hash(server_key, SSH_PUBLICKEY_HASH_SHA256, &hash, &hash_len);
        if (rc != SSH_OK) {
            ssh_key_free(server_key);
            return TERM_SSH_ERROR;
        }
        char *b64 = NULL;
        rc = ssh_pki_export_pubkey_base64(server_key, &b64);
        if (rc == SSH_OK && b64) {
            size_t fp_len = 64 + hash_len * 2;
            *fingerprint_sha256 = malloc(fp_len);
            if (*fingerprint_sha256) {
                char *p = *fingerprint_sha256;
                *p++ = 'S';
                *p++ = 'H';
                *p++ = 'A';
                *p++ = '2';
                *p++ = '5';
                *p++ = '6';
                *p++ = ':';
                for (size_t i = 0; i < hash_len; i++) {
                    static const char hex[] = "0123456789abcdef";
                    *p++ = hex[(hash[i] >> 4) & 0xf];
                    *p++ = hex[hash[i] & 0xf];
                    if (i + 1 < hash_len) *p++ = ':';
                }
                *p = '\0';
            }
            ssh_string_free_char(b64);
        }
        ssh_clean_pubkey_hash(&hash);
    }

    if (fingerprint_md5) {
        unsigned char *hash = NULL;
        size_t hash_len = 0;
        rc = ssh_get_publickey_hash(server_key, SSH_PUBLICKEY_HASH_MD5, &hash, &hash_len);
        if (rc != SSH_OK) {
            ssh_key_free(server_key);
            if (fingerprint_sha256 && *fingerprint_sha256) {
                free(*fingerprint_sha256);
                *fingerprint_sha256 = NULL;
            }
            return TERM_SSH_ERROR;
        }
        size_t fp_len = 8 + hash_len * 3;
        *fingerprint_md5 = malloc(fp_len);
        if (*fingerprint_md5) {
            char *p = *fingerprint_md5;
            *p++ = 'M';
            *p++ = 'D';
            *p++ = '5';
            *p++ = ':';
            for (size_t i = 0; i < hash_len; i++) {
                static const char hex[] = "0123456789abcdef";
                *p++ = hex[(hash[i] >> 4) & 0xf];
                *p++ = hex[hash[i] & 0xf];
                if (i + 1 < hash_len) {
                    *p++ = ':';
                }
            }
            *p = '\0';
        }
        ssh_clean_pubkey_hash(&hash);
    }

    ssh_key_free(server_key);
    return TERM_SSH_OK;
}

term_ssh_error_t ssh_hostkey_write_to_known_hosts(void *ssh_sess,
                                                   const char *host,
                                                   uint16_t port,
                                                   const char *known_hosts_file) {
    (void)host;
    (void)port;
    (void)known_hosts_file;
    
    if (!ssh_sess) {
        return TERM_SSH_ERROR;
    }

    int rc = ssh_write_knownhost((ssh_session)ssh_sess);
    if (rc != SSH_OK) {
        return TERM_SSH_ERROR_FILE;
    }

    return TERM_SSH_OK;
}

term_ssh_error_t term_ssh_hostkey_get_fingerprint(term_ssh_session_t *session,
                                                   const char *host,
                                                   uint16_t port,
                                                   char **fingerprint_sha256,
                                                   char **fingerprint_md5,
                                                   term_ssh_key_type_t *key_type) {
    if (!session || !session->ssh || !host) {
        return TERM_SSH_ERROR;
    }

    ssh_session ssh = (ssh_session)session->ssh;

    bool need_disconnect = false;
    if (!ssh_is_connected(ssh)) {
        ssh_options_set(ssh, SSH_OPTIONS_HOST, host);
        ssh_options_set(ssh, SSH_OPTIONS_PORT, &port);

        int rc = ssh_connect(ssh);
        if (rc != SSH_OK) {
            ssh_core_log(session, TERM_SSH_LOG_ERROR, "No se pudo conectar para obtener host key: %s", host);
            return TERM_SSH_ERROR_CONNECTION;
        }
        need_disconnect = true;
    }

    term_ssh_error_t ret = ssh_hostkey_get_info(session, ssh, host, port,
                                                 fingerprint_sha256, fingerprint_md5, key_type);

    if (need_disconnect) {
        ssh_disconnect(ssh);
    }

    return ret;
}

term_ssh_error_t term_ssh_hostkey_save_to_known_hosts(term_ssh_session_t *session,
                                                       const char *host,
                                                       uint16_t port,
                                                       const char *known_hosts_file) {
    (void)host;
    (void)port;
    
    if (!session || !session->ssh) {
        return TERM_SSH_ERROR;
    }

    ssh_session ssh = (ssh_session)session->ssh;

    if (known_hosts_file && known_hosts_file[0] != '\0') {
        ssh_options_set(ssh, SSH_OPTIONS_KNOWNHOSTS, known_hosts_file);
    }

    return ssh_hostkey_write_to_known_hosts(ssh, host, port, known_hosts_file);
}
