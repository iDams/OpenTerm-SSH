#include <assert.h>
#include <stdbool.h>
#include <string.h>
#include "term_ssh.h"
#include "ssh_auth.h"
#include "ssh_connection.h"
#include "ssh_sftp.h"

static void test_version_is_present(void) {
    const char *version = term_ssh_version();
    assert(version != NULL);
    assert(strlen(version) > 0);
}

static void test_session_lifecycle(void) {
    assert(term_ssh_init() == TERM_SSH_OK);

    term_ssh_session_t *session = term_ssh_session_new();
    assert(session != NULL);

    assert(term_ssh_session_set_log_level(session, TERM_SSH_LOG_DEBUG) == TERM_SSH_OK);
    term_ssh_session_free(session);
    term_ssh_cleanup();
}

static void test_invalid_arguments_fail_cleanly(void) {
    char *output = NULL;
    size_t output_len = 0;

    assert(term_ssh_connect(NULL, NULL, NULL) == TERM_SSH_ERROR);
    assert(term_ssh_execute(NULL, "uname -a", &output, &output_len) == TERM_SSH_ERROR);
    assert(term_ssh_execute(NULL, NULL, &output, &output_len) == TERM_SSH_ERROR);
    assert(term_ssh_sftp_init(NULL, NULL) == TERM_SSH_ERROR);
    assert(term_ssh_sftp_list(NULL, ".", NULL, NULL) == TERM_SSH_ERROR);
    assert(term_ssh_sftp_upload(NULL, "a", "b", NULL, NULL) == TERM_SSH_ERROR);
    assert(term_ssh_sftp_download(NULL, "a", "b", NULL, NULL) == TERM_SSH_ERROR);
}

static void test_connection_configuration_path(void) {
    term_ssh_session_t *session = term_ssh_session_new();
    assert(session != NULL);

    term_ssh_connection_t *conn = NULL;
    term_ssh_config_t config = {
        .host = "example.com",
        .port = 2222,
        .username = "alice",
        .password = "secret",
        .private_key_path = "/tmp/id_ed25519",
        .passphrase = NULL,
        .timeout_ms = 5000,
        .auth_methods = TERM_SSH_AUTH_PASSWORD | TERM_SSH_AUTH_INTERACTIVE,
        .strict_host_key = true,
        .known_hosts_file = "/tmp/known_hosts",
    };

    assert(ssh_connection_create(&conn, session) == TERM_SSH_OK);
    assert(conn != NULL);
    assert(ssh_connection_configure(conn, &config) == TERM_SSH_OK);
    assert(conn->config.host == config.host);
    assert(conn->config.port == config.port);
    assert(conn->config.username == config.username);
    assert(conn->config.password == config.password);
    assert(term_ssh_is_connected(conn) == false);

    term_ssh_connection_free(conn);
    term_ssh_session_free(session);
}

static void test_auth_helpers_fail_cleanly_without_real_remote(void) {
    term_ssh_session_t *session = term_ssh_session_new();
    assert(session != NULL);

    term_ssh_connection_t *conn = NULL;
    assert(ssh_connection_create(&conn, session) == TERM_SSH_OK);

    assert(ssh_auth_password(NULL, "secret") == TERM_SSH_ERROR);
    assert(ssh_auth_publickey(NULL, "/tmp/id_ed25519", NULL) == TERM_SSH_ERROR);
    assert(ssh_auth_interactive(NULL) == TERM_SSH_ERROR);
    assert(ssh_auth_publickey(conn, "/tmp/does-not-exist", NULL) == TERM_SSH_ERROR_AUTH);

    term_ssh_connection_free(conn);
    term_ssh_session_free(session);
}

static void test_exec_requires_live_connection(void) {
    term_ssh_session_t *session = term_ssh_session_new();
    assert(session != NULL);

    term_ssh_connection_t *conn = NULL;
    assert(ssh_connection_create(&conn, session) == TERM_SSH_OK);

    char *output = NULL;
    size_t output_len = 0;
    assert(term_ssh_execute(conn, "uname -a", &output, &output_len) == TERM_SSH_ERROR);

    term_ssh_connection_free(conn);
    term_ssh_session_free(session);
}

static void test_sftp_list_requires_live_connection(void) {
    term_ssh_session_t *session = term_ssh_session_new();
    assert(session != NULL);

    term_ssh_connection_t *conn = NULL;
    assert(ssh_connection_create(&conn, session) == TERM_SSH_OK);

    term_ssh_sftp_t *sftp = NULL;
    char **files = NULL;
    size_t count = 0;

    assert(term_ssh_sftp_init(&sftp, conn) == TERM_SSH_ERROR);
    assert(term_ssh_sftp_list(NULL, ".", &files, &count) == TERM_SSH_ERROR);

    term_ssh_connection_free(conn);
    term_ssh_session_free(session);
}

int main(void) {
    test_version_is_present();
    test_session_lifecycle();
    test_invalid_arguments_fail_cleanly();
    test_connection_configuration_path();
    test_auth_helpers_fail_cleanly_without_real_remote();
    test_exec_requires_live_connection();
    test_sftp_list_requires_live_connection();
    return 0;
}
