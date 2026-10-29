#!/bin/sh
# Runs smoke-test.sh for a built Linux package inside a set of bare distro containers, to prove the
# package needs nothing from the host but its C library.
# Usage: scripts/test-linux-distros.sh <target> [image ...]
set -eu

TARGET=${1:?target required}
shift
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/versions.env"
. "$ROOT/scripts/targets.sh"

NAME="portable-mariadb-$MARIADB_VERSION-r$REVISION-$TARGET"
PLATFORM=$(target_image "$TARGET" | cut -d' ' -f2)

if [ $# -eq 0 ]; then
    case "$TARGET" in
        linux-musl-*) set -- alpine:3.18 alpine:3.20 alpine:latest ;;
        linux-armv7) set -- debian:11-slim ubuntu:22.04 debian:12-slim ;;
        linux-riscv64) set -- ubuntu:24.04 debian:13-slim ;;
        linux-x86) set -- debian:10-slim debian:12-slim ;;
        *) set -- debian:10-slim ubuntu:20.04 ubuntu:24.04 debian:13-slim rockylinux:8 \
                  fedora:latest archlinux:latest opensuse/leap:15 ;;
    esac
fi

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
tar -xzf "$ROOT/dist/$NAME.tar.gz" -C "$T"

failed=
for image in "$@"; do
    echo "######## $image ($PLATFORM)"
    if docker run --rm --platform "$PLATFORM" -v "$T/$NAME:/pkg:ro" -v "$ROOT/scripts:/scripts:ro" \
        "$image" sh /scripts/smoke-test.sh /pkg; then
        :
    else
        failed="$failed $image"
    fi
done

if [ -n "$failed" ]; then
    echo "FAILED on:$failed" >&2
    exit 1
fi
echo "All distros passed: $*"
