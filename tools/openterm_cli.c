#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "term_ssh.h"

typedef struct {
    const char *host;
    const char *username;
    const char *command;
    const char *password;
    const char *private_key_path;
    uint16_t port;
} cli_options_t;

static void print_usage(const char *program_name) {
    printf("Uso: %s [--host HOST] [--user USER] [--command CMD] [--password PASS] [--port PORT] [--key PATH]\n", program_name);
    printf("     %s <host> <usuario> [comando] [password]\n", program_name);
    printf("Opciones:\n");
    printf("  --host HOST        Host SSH\n");
    printf("  --user USER        Usuario SSH\n");
    printf("  --command CMD      Comando remoto\n");
    printf("  --password PASS    Password SSH\n");
    printf("  --port PORT        Puerto SSH (default: 22)\n");
    printf("  --key PATH         Ruta a llave privada\n");
    printf("  --help             Muestra esta ayuda\n");
    printf("Tambien puedes usar OPENTERM_PASSWORD o dejar que use tu llave por defecto en ~/.ssh.\n");
}

static int parse_port(const char *value, uint16_t *port) {
    char *end = NULL;
    unsigned long parsed = strtoul(value, &end, 10);
    if (!value || *value == '\0' || !end || *end != '\0' || parsed == 0 || parsed > 65535) {
        return 0;
    }

    *port = (uint16_t)parsed;
    return 1;
}

static int parse_arguments(int argc, char *argv[], cli_options_t *options) {
    int positional_index = 0;

    options->command = "uname -a";
    options->port = 22;

    for (int i = 1; i < argc; i++) {
        const char *argument = argv[i];

        if (strcmp(argument, "--help") == 0) {
            print_usage(argv[0]);
            return 0;
        }

        if (strcmp(argument, "--host") == 0 && i + 1 < argc) {
            options->host = argv[++i];
            continue;
        }

        if (strcmp(argument, "--user") == 0 && i + 1 < argc) {
            options->username = argv[++i];
            continue;
        }

        if (strcmp(argument, "--command") == 0 && i + 1 < argc) {
            options->command = argv[++i];
            continue;
        }

        if (strcmp(argument, "--password") == 0 && i + 1 < argc) {
            options->password = argv[++i];
            continue;
        }

        if (strcmp(argument, "--port") == 0 && i + 1 < argc) {
            if (!parse_port(argv[++i], &options->port)) {
                fprintf(stderr, "Puerto invalido: %s\n", argv[i]);
                return -1;
            }
            continue;
        }

        if (strcmp(argument, "--key") == 0 && i + 1 < argc) {
            options->private_key_path = argv[++i];
            continue;
        }

        if (strncmp(argument, "--", 2) == 0) {
            fprintf(stderr, "Opcion no reconocida: %s\n", argument);
            return -1;
        }

        switch (positional_index) {
            case 0:
                options->host = argument;
                break;
            case 1:
                options->username = argument;
                break;
            case 2:
                options->command = argument;
                break;
            case 3:
                options->password = argument;
                break;
            default:
                fprintf(stderr, "Argumento inesperado: %s\n", argument);
                return -1;
        }
        positional_index++;
    }

    if (!options->host || !options->username) {
        print_usage(argv[0]);
        return -1;
    }

    return 1;
}

static const char *find_default_private_key(const char *home, char *buffer, size_t buffer_size) {
    static const char *candidates[] = {
        ".ssh/id_ed25519",
        ".ssh/id_ecdsa",
        ".ssh/id_rsa",
    };

    if (!home) {
        return NULL;
    }

    for (size_t i = 0; i < sizeof(candidates) / sizeof(candidates[0]); i++) {
        snprintf(buffer, buffer_size, "%s/%s", home, candidates[i]);
        if (access(buffer, R_OK) == 0) {
            return buffer;
        }
    }

    return NULL;
}

static const char *resolve_password(int argc, char *argv[]) {
    const char *password = getenv("OPENTERM_PASSWORD");
    if (password && password[0] != '\0') {
        return password;
    }

    if (argc > 4 && argv[4][0] != '\0') {
        return argv[4];
    }

    return NULL;
}

static void log_callback(term_ssh_log_level_t level, const char *message, void *userdata) {
    (void)userdata;

    const char *level_str;
    switch (level) {
        case TERM_SSH_LOG_ERROR: level_str = "ERROR"; break;
        case TERM_SSH_LOG_WARNING: level_str = "WARN"; break;
        case TERM_SSH_LOG_INFO: level_str = "INFO"; break;
        case TERM_SSH_LOG_DEBUG: level_str = "DEBUG"; break;
        default: level_str = "UNKNOWN"; break;
    }
    printf("[%s] %s\n", level_str, message);
}

int main(int argc, char *argv[]) {
    cli_options_t options = {0};
    int parse_result = parse_arguments(argc, argv, &options);
    if (parse_result <= 0) {
        return parse_result == 0 ? 0 : 1;
    }

    const char *password = options.password ? options.password : resolve_password(argc, argv);
    const char *home = getenv("HOME");
    char known_hosts_path[1024] = {0};
    char private_key_path[1024] = {0};
    const char *default_private_key = options.private_key_path
        ? options.private_key_path
        : find_default_private_key(home, private_key_path, sizeof(private_key_path));

    if (home) {
        snprintf(known_hosts_path, sizeof(known_hosts_path), "%s/.ssh/known_hosts", home);
    }

    printf("OpenTerm SSH CLI\n");
    printf("================\n\n");

    if (term_ssh_init() != TERM_SSH_OK) {
        fprintf(stderr, "Error inicializando libssh\n");
        return 1;
    }

    term_ssh_session_t *session = term_ssh_session_new();
    if (!session) {
        fprintf(stderr, "Error creando sesion\n");
        term_ssh_cleanup();
        return 1;
    }

    term_ssh_session_set_log_callback(session, log_callback, NULL);
    term_ssh_session_set_log_level(session, TERM_SSH_LOG_DEBUG);

    term_ssh_config_t config = {
        .host = options.host,
        .port = options.port,
        .username = options.username,
        .password = password,
        .private_key_path = default_private_key,
        .passphrase = NULL,
        .timeout_ms = 10000,
        .auth_methods = password
            ? (TERM_SSH_AUTH_PASSWORD | TERM_SSH_AUTH_INTERACTIVE)
            : (TERM_SSH_AUTH_PASSWORD | TERM_SSH_AUTH_PUBLICKEY | TERM_SSH_AUTH_INTERACTIVE),
        .strict_host_key = true,
        .known_hosts_file = known_hosts_path[0] != '\0' ? known_hosts_path : NULL,
    };

    term_ssh_connection_t *conn = NULL;
    term_ssh_error_t ret = term_ssh_connect(&conn, session, &config);
    if (ret == TERM_SSH_ERROR_AUTH && !password) {
        char *prompt_password = getpass("Password SSH: ");
        if (prompt_password && prompt_password[0] != '\0') {
            config.password = prompt_password;
            ret = term_ssh_connect(&conn, session, &config);
        }
    }

    if (ret != TERM_SSH_OK) {
        fprintf(stderr, "Error conectando: %d\n", ret);
        term_ssh_session_free(session);
        term_ssh_cleanup();
        return 1;
    }

    char *output = NULL;
    size_t output_len = 0;
    ret = term_ssh_execute(conn, options.command, &output, &output_len);
    if (ret == TERM_SSH_OK && output) {
        printf("%s\n", output);
        free(output);
    } else if (ret != TERM_SSH_OK) {
        fprintf(stderr, "Error ejecutando comando\n");
    }

    term_ssh_disconnect(conn);
    term_ssh_connection_free(conn);
    term_ssh_session_free(session);
    term_ssh_cleanup();

    return 0;
}
