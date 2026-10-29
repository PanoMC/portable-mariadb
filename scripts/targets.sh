#!/bin/sh
# Target table for the Linux builds: target -> build image + docker platform.
# Usage: . scripts/targets.sh; target_image linux-x64
#
# glibc targets use the pypa manylinux images (old glibc, current gcc, patchelf preinstalled), so the
# binaries run on every distro with an equal or newer glibc. musl targets use musllinux (Alpine).

target_image() {
    case "$1" in
        linux-x64)         echo "quay.io/pypa/manylinux_2_28_x86_64 linux/amd64" ;;
        linux-x86)         echo "quay.io/pypa/manylinux_2_28_i686 linux/386" ;;
        linux-arm64)       echo "quay.io/pypa/manylinux_2_28_aarch64 linux/arm64" ;;
        linux-armv7)       echo "quay.io/pypa/manylinux_2_31_armv7l linux/arm/v7" ;;
        linux-ppc64le)     echo "quay.io/pypa/manylinux_2_28_ppc64le linux/ppc64le" ;;
        linux-s390x)       echo "quay.io/pypa/manylinux_2_28_s390x linux/s390x" ;;
        linux-riscv64)     echo "quay.io/pypa/manylinux_2_39_riscv64 linux/riscv64" ;;
        linux-musl-x64)    echo "quay.io/pypa/musllinux_1_2_x86_64 linux/amd64" ;;
        linux-musl-x86)    echo "quay.io/pypa/musllinux_1_2_i686 linux/386" ;;
        linux-musl-arm64)  echo "quay.io/pypa/musllinux_1_2_aarch64 linux/arm64" ;;
        linux-musl-armv7)  echo "quay.io/pypa/musllinux_1_2_armv7l linux/arm/v7" ;;
        *) return 1 ;;
    esac
}

# Minimum glibc of a target (shown in the manifest); empty for musl.
target_min_glibc() {
    case "$1" in
        linux-musl-*) echo "" ;;
        linux-armv7) echo "2.31" ;;
        linux-riscv64) echo "2.39" ;;
        linux-*) echo "2.28" ;;
    esac
}
