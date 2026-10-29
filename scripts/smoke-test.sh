#!/bin/sh
# Smoke test for an extracted Linux / macOS package: creates a data dir, starts the server, runs a few
# queries over TCP and the socket, and shuts it down. Uses only POSIX sh, so it runs in bare distro
# containers (see test-linux-distros.sh).
# Usage: scripts/smoke-test.sh <extracted package dir>
set -eu

B=$(cd "${1:?package dir required}" && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/pmdb-smoke.XXXXXX")
PORT=${SMOKE_PORT:-33071}
SOCK="$T/mysql.sock"
USER_OPT=
[ "$(id -u)" = 0 ] && USER_OPT=--user=root

cleanup() {
    if [ -n "${PID:-}" ] && kill -0 "$PID" 2>/dev/null; then kill "$PID" 2>/dev/null || true; fi
    rm -rf "$T"
}
trap cleanup EXIT

echo "== $(cat "$B/VERSION")"
echo "== $(uname -srm)"
[ -r /etc/os-release ] && . /etc/os-release && echo "== ${PRETTY_NAME:-unknown}"

if command -v ldd >/dev/null 2>&1 && [ "$(uname -s)" = Linux ]; then
    if ldd "$B/bin/mariadbd" 2>&1 | grep -q 'not found'; then
        ldd "$B/bin/mariadbd"
        echo "FAIL: unresolved libraries" >&2
        exit 1
    fi
fi

"$B/bin/mariadbd" --version

"$B/scripts/mariadb-install-db" --no-defaults --basedir="$B" --datadir="$T/data" \
    --auth-root-authentication-method=normal --skip-test-db --skip-name-resolve $USER_OPT \
    > "$T/install.log" 2>&1 || { cat "$T/install.log"; echo "FAIL: mariadb-install-db" >&2; exit 1; }

"$B/bin/mariadbd" --no-defaults --basedir="$B" --datadir="$T/data" $USER_OPT \
    --port="$PORT" --bind-address=127.0.0.1 --socket="$SOCK" --skip-name-resolve \
    --log-error="$T/error.log" &
PID=$!

i=0
until "$B/bin/mariadb-admin" --no-defaults -uroot --socket="$SOCK" ping >/dev/null 2>&1; do
    i=$((i + 1))
    if [ $i -gt 120 ] || ! kill -0 "$PID" 2>/dev/null; then
        cat "$T/error.log" >&2 || true
        echo "FAIL: server did not start" >&2
        exit 1
    fi
    sleep 0.5
done

Q="SELECT VERSION();
CREATE DATABASE smoke CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE TABLE smoke.t (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(64), doc JSON, created TIMESTAMP DEFAULT CURRENT_TIMESTAMP) ENGINE=InnoDB;
INSERT INTO smoke.t (name, doc) VALUES ('ğüşıöç 日本', '{\"a\": 1}') ON DUPLICATE KEY UPDATE name = VALUES(name);
SELECT id, name, JSON_EXTRACT(doc, '\$.a'), REGEXP_REPLACE(name, '[a-z]', '') FROM smoke.t;
SELECT LAST_INSERT_ID(), @@have_ssl, @@version_ssl_library;
SELECT SHA2('pano', 256), COMPRESS('x') IS NOT NULL;"

"$B/bin/mariadb" --no-defaults -uroot --socket="$SOCK" -e "$Q"
# TCP as well, which is how Pano connects.
"$B/bin/mariadb" --no-defaults -uroot -h127.0.0.1 -P"$PORT" --protocol=TCP -e "SELECT 'tcp ok'"
"$B/bin/mariadb-dump" --no-defaults -uroot --socket="$SOCK" smoke > "$T/dump.sql"
grep -q 'CREATE TABLE `t`' "$T/dump.sql"

"$B/bin/mariadb-admin" --no-defaults -uroot --socket="$SOCK" shutdown
wait "$PID"
PID=
echo "PASS"
