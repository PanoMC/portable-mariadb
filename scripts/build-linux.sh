#!/bin/sh
# Builds one Linux target inside its build image with Docker.
# Usage: scripts/build-linux.sh <target>      (JOBS, DOCKER_MEMORY and DOCKER_CPUS are optional)
# Non-native targets need QEMU binfmt handlers (docker run --privileged tonistiigi/binfmt --install all).
set -eu

TARGET=${1:?target required}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/scripts/targets.sh"

IMAGE_PLATFORM=$(target_image "$TARGET") || { echo "unknown Linux target $TARGET" >&2; exit 1; }
IMAGE=${IMAGE_PLATFORM% *}
PLATFORM=${IMAGE_PLATFORM#* }

set -- --rm --platform "$PLATFORM" \
    -v "$ROOT:/src" -w /src \
    -e JOBS="${JOBS:-}" -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)"
[ -n "${DOCKER_MEMORY:-}" ] && set -- "$@" --memory "$DOCKER_MEMORY"
[ -n "${DOCKER_CPUS:-}" ] && set -- "$@" --cpus "$DOCKER_CPUS"

# 32-bit x86 images need linux32 so uname reports i686 to cmake.
case "$TARGET" in *-x86) WRAP=linux32 ;; *) WRAP= ;; esac

docker run "$@" "$IMAGE" $WRAP sh -c '
    scripts/build-unix.sh "$0"; status=$?
    chown -R "$HOST_UID:$HOST_GID" .work dist .cache 2>/dev/null
    exit $status' "$TARGET"
