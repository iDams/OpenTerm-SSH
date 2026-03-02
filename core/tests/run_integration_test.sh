#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${1:-$SCRIPT_DIR/../build-tests}"
TEST_BIN="$BUILD_DIR/tests/core_integration_test"

if [[ ! -x "$TEST_BIN" ]]; then
    echo "Missing integration test binary: $TEST_BIN" >&2
    exit 1
fi

TMP_DIR="$(mktemp -d)"
PORT="${OPENTERM_TEST_PORT:-22222}"
USER_NAME="$(whoami)"
HOST="127.0.0.1"
HOST_KEY_RSA="$TMP_DIR/ssh_host_rsa_key"
HOST_KEY_ECDSA="$TMP_DIR/ssh_host_ecdsa_key"
HOST_KEY_ED25519="$TMP_DIR/ssh_host_ed25519_key"
CLIENT_KEY="$TMP_DIR/client_ed25519"
AUTHORIZED_KEYS="$TMP_DIR/authorized_keys"
KNOWN_HOSTS="$TMP_DIR/known_hosts"
SSHD_CONFIG="$TMP_DIR/sshd_config"
SSHD_LOG="$TMP_DIR/sshd.log"
SSHD_PID="$TMP_DIR/sshd.pid"

cleanup() {
    local exit_code=$?
    if [[ -f "$SSHD_PID" ]]; then
        kill "$(cat "$SSHD_PID")" >/dev/null 2>&1 || true
    fi
    if [[ $exit_code -ne 0 && -f "$SSHD_LOG" ]]; then
        echo "--- sshd log ---" >&2
        cat "$SSHD_LOG" >&2 || true
    fi
    if [[ "${OPENTERM_TEST_KEEP_TMP:-0}" == "1" ]]; then
        echo "Keeping temp dir: $TMP_DIR" >&2
    else
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

ssh-keygen -q -t rsa -b 3072 -N "" -f "$HOST_KEY_RSA" >/dev/null
ssh-keygen -q -t ecdsa -N "" -f "$HOST_KEY_ECDSA" >/dev/null
ssh-keygen -q -t ed25519 -N "" -f "$HOST_KEY_ED25519" >/dev/null
ssh-keygen -q -t ed25519 -N "" -f "$CLIENT_KEY" >/dev/null
cp "$CLIENT_KEY.pub" "$AUTHORIZED_KEYS"
chmod 600 "$AUTHORIZED_KEYS"

cat > "$SSHD_CONFIG" <<EOF
Port $PORT
ListenAddress $HOST
PidFile $SSHD_PID
HostKey $HOST_KEY_RSA
HostKey $HOST_KEY_ECDSA
HostKey $HOST_KEY_ED25519
AuthorizedKeysFile $AUTHORIZED_KEYS
PasswordAuthentication no
PubkeyAuthentication yes
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
UsePAM no
PermitRootLogin no
StrictModes no
LogLevel DEBUG2
Subsystem sftp /usr/libexec/sftp-server
EOF

/usr/sbin/sshd -D -f "$SSHD_CONFIG" -E "$SSHD_LOG" &
SSHD_PROCESS=$!

for _ in {1..50}; do
    if nc -z "$HOST" "$PORT" >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done

if ! nc -z "$HOST" "$PORT" >/dev/null 2>&1; then
    echo "sshd did not start" >&2
    cat "$SSHD_LOG" >&2 || true
    kill "$SSHD_PROCESS" >/dev/null 2>&1 || true
    exit 1
fi

ssh-keyscan -t rsa,ecdsa,ed25519 -p "$PORT" "$HOST" > "$KNOWN_HOSTS" 2>/dev/null

OPENTERM_TEST_HOST="$HOST" \
OPENTERM_TEST_PORT="$PORT" \
OPENTERM_TEST_USER="$USER_NAME" \
OPENTERM_TEST_KEY="$CLIENT_KEY" \
OPENTERM_TEST_KNOWN_HOSTS="$KNOWN_HOSTS" \
OPENTERM_TEST_COMMAND="printf integration_ok" \
"$TEST_BIN"
