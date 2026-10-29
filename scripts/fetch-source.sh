#!/bin/sh
# Downloads a source tarball into .cache/ and verifies its SHA-256 against versions.env.
# Usage: scripts/fetch-source.sh [mariadb|openssl]      Prints the path of the verified tarball.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/versions.env"

case "${1:-mariadb}" in
    mariadb)
        FILE="mariadb-$MARIADB_VERSION.tar.gz"
        URL="https://archive.mariadb.org/mariadb-$MARIADB_VERSION/source/$FILE"
        SHA256=$MARIADB_SHA256 ;;
    openssl)
        FILE="openssl-$OPENSSL_VERSION.tar.gz"
        URL="https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/$FILE"
        SHA256=$OPENSSL_SHA256 ;;
    *) echo "unknown source $1" >&2; exit 1 ;;
esac

CACHE="$ROOT/.cache"
TARBALL="$CACHE/$FILE"
mkdir -p "$CACHE"

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
    else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

if [ ! -f "$TARBALL" ] || [ "$(sha256_of "$TARBALL")" != "$SHA256" ]; then
    echo "Downloading $URL" >&2
    curl -fsSL --retry 5 --retry-delay 5 -o "$TARBALL.part" "$URL"
    mv "$TARBALL.part" "$TARBALL"
fi

ACTUAL=$(sha256_of "$TARBALL")
if [ "$ACTUAL" != "$SHA256" ]; then
    echo "SHA-256 mismatch for $TARBALL: expected $SHA256, got $ACTUAL" >&2
    exit 1
fi

echo "$TARBALL"
