#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "term_ssh.h"

static const char *required_env(const char *name) {
    const char *value = getenv(name);
    if (!value || value[0] == '\0') {
        fprintf(stderr, "Missing required env var: %s\n", name);
        exit(2);
    }
    return value;
}

int main(void) {
    const char *host = required_env("OPENTERM_TEST_HOST");
    const char *username = required_env("OPENTERM_TEST_USER");
    const char *private_key_path = required_env("OPENTERM_TEST_KEY");
    const char *known_hosts_path = required_env("OPENTERM_TEST_KNOWN_HOSTS");
    const char *command = getenv("OPENTERM_TEST_COMMAND");
    if (!command || command[0] == '\0') {
        command = "printf integration_ok";
    }

    if (term_ssh_init() != TERM_SSH_OK) {
        fprintf(stderr, "term_ssh_init failed\n");
        return 1;
    }

    term_ssh_session_t *session = term_ssh_session_new();
    if (!session) {
        fprintf(stderr, "term_ssh_session_new failed\n");
        term_ssh_cleanup();
        return 1;
    }

    term_ssh_config_t config = {
        .host = host,
        .port = (uint16_t)atoi(getenv("OPENTERM_TEST_PORT") ? getenv("OPENTERM_TEST_PORT") : "22222"),
        .username = username,
        .password = NULL,
        .private_key_path = private_key_path,
        .passphrase = NULL,
        .timeout_ms = 5000,
        .auth_methods = TERM_SSH_AUTH_PUBLICKEY,
        .strict_host_key = true,
        .known_hosts_file = known_hosts_path,
    };

    term_ssh_connection_t *conn = NULL;
    term_ssh_error_t ret = term_ssh_connect(&conn, session, &config);
    if (ret != TERM_SSH_OK) {
        fprintf(stderr, "term_ssh_connect failed: %d\n", ret);
        term_ssh_session_free(session);
        term_ssh_cleanup();
        return 1;
    }

    char *output = NULL;
    size_t output_len = 0;
    ret = term_ssh_execute(conn, command, &output, &output_len);
    if (ret != TERM_SSH_OK) {
        fprintf(stderr, "term_ssh_execute failed: %d\n", ret);
        term_ssh_connection_free(conn);
        term_ssh_session_free(session);
        term_ssh_cleanup();
        return 1;
    }

    if (!output || strcmp(output, "integration_ok") != 0) {
        fprintf(stderr, "unexpected command output: %s\n", output ? output : "(null)");
        free(output);
        term_ssh_connection_free(conn);
        term_ssh_session_free(session);
        term_ssh_cleanup();
        return 1;
    }
    free(output);

    term_ssh_sftp_t *sftp = NULL;
    ret = term_ssh_sftp_init(&sftp, conn);
    if (ret != TERM_SSH_OK) {
        fprintf(stderr, "term_ssh_sftp_init failed: %d\n", ret);
        term_ssh_connection_free(conn);
        term_ssh_session_free(session);
        term_ssh_cleanup();
        return 1;
    }

    char **files = NULL;
    size_t count = 0;
    ret = term_ssh_sftp_list(sftp, ".", &files, &count);
    if (ret != TERM_SSH_OK) {
        fprintf(stderr, "term_ssh_sftp_list failed: %d\n", ret);
        term_ssh_sftp_free(sftp);
        term_ssh_connection_free(conn);
        term_ssh_session_free(session);
        term_ssh_cleanup();
        return 1;
    }

    for (size_t i = 0; i < count; i++) {
        free(files[i]);
    }
    free(files);

    term_ssh_sftp_free(sftp);
    term_ssh_connection_free(conn);
    term_ssh_session_free(session);
    term_ssh_cleanup();
    return 0;
}
