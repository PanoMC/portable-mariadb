#!/bin/sh
# Builds a portable MariaDB server package for one Linux or macOS target.
# Linux: run inside the target's build image (see build-linux.sh). macOS: run on the host.
#
# Usage: scripts/build-unix.sh <target>     e.g. linux-x64, linux-musl-arm64, macos-arm64
# Output: dist/portable-mariadb-<version>-r<rev>-<target>.tar.gz (+ .sha256)
set -eu

TARGET=${1:?target required}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/versions.env"

NAME="portable-mariadb-$MARIADB_VERSION-r$REVISION-$TARGET"
WORK="$ROOT/.work/$TARGET"
SRC="$WORK/src"
BUILD="$WORK/build"
STAGE="$WORK/stage"
PKG="$WORK/$NAME"
DIST="$ROOT/dist"
PREFIX=/usr/local/mysql

if [ -z "${JOBS:-}" ]; then
    JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
fi

install_build_deps() {
    if command -v dnf >/dev/null 2>&1; then
        dnf install -y -q bison ncurses-devel perl >/dev/null
    elif command -v yum >/dev/null 2>&1; then
        yum install -y -q bison ncurses-devel perl >/dev/null
    elif command -v apk >/dev/null 2>&1; then
        apk add -q bison ncurses-dev ncurses-static linux-headers perl
    elif command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq && apt-get install -y -qq bison libncurses-dev perl >/dev/null
    fi
    # ninja is optional, cmake falls back to make.
    command -v ninja >/dev/null 2>&1 || pipx install ninja >/dev/null 2>&1 || pip install -q ninja >/dev/null 2>&1 || true
}

case "$TARGET" in
    linux-*) [ "${SKIP_DEPS:-0}" = 1 ] || install_build_deps ;;
    macos-*) ;;
    *) echo "unknown target $TARGET" >&2; exit 1 ;;
esac

TARBALL=$("$ROOT/scripts/fetch-source.sh" mariadb)
OPENSSL_TARBALL=$("$ROOT/scripts/fetch-source.sh" openssl)

rm -rf "$WORK"
mkdir -p "$SRC" "$BUILD" "$STAGE" "$DIST" "$WORK/openssl-src"
tar -xzf "$TARBALL" -C "$SRC" --strip-components=1
tar -xzf "$OPENSSL_TARBALL" -C "$WORK/openssl-src" --strip-components=1

# fmt 12 (bundled by MariaDB) does not compile on 32-bit x86 (no operator~ on its uint128 fallback,
# hit by the 80-bit long double path). Use the fmt 11.0.2 that MariaDB already pins for old compilers.
case "$TARGET" in
    *-x86) sed -i.orig 's/CMAKE_CXX_COMPILER_VERSION VERSION_LESS "4.9"/TRUE/' "$SRC/cmake/libfmt.cmake" ;;
esac

# Static OpenSSL for the server and the client connector (the bundled wolfSSL would leave the
# connector without a TLS / hash backend on Unix).
OPENSSL="$WORK/openssl"
case "$TARGET" in
    linux-x64|linux-musl-x64) OPENSSL_TARGET=linux-x86_64 ;;
    linux-x86|linux-musl-x86) OPENSSL_TARGET=linux-x86 ;;
    linux-arm64|linux-musl-arm64) OPENSSL_TARGET=linux-aarch64 ;;
    linux-armv7|linux-musl-armv7) OPENSSL_TARGET=linux-armv4 ;;
    linux-ppc64le) OPENSSL_TARGET=linux-ppc64le ;;
    linux-s390x) OPENSSL_TARGET=linux64-s390x ;;
    linux-riscv64) OPENSSL_TARGET=linux64-riscv64 ;;
    macos-arm64) OPENSSL_TARGET=darwin64-arm64-cc ;;
    macos-x64) OPENSSL_TARGET=darwin64-x86_64-cc ;;
esac
(
    cd "$WORK/openssl-src"
    ./Configure "$OPENSSL_TARGET" no-shared no-module no-dso no-tests no-docs no-apps -fPIC \
        --prefix="$OPENSSL" --libdir=lib --openssldir=/usr/local/ssl >/dev/null
    make -s -j"$JOBS" >/dev/null
    make -s install_dev >/dev/null
)

# Server + the few client tools a host needs to bootstrap, upgrade, dump and stop it. Every engine or
# plugin that needs an external library (or is irrelevant for a single-node embedded server) is off,
# and OpenSSL (static, above), zlib and PCRE2 are built in, so the result only links against libc.
set -- \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DINSTALL_LAYOUT=STANDALONE \
    -DWITH_SSL="$OPENSSL" \
    -DOPENSSL_ROOT_DIR="$OPENSSL" \
    -DOPENSSL_USE_STATIC_LIBS=TRUE \
    -DWITH_ZLIB=bundled \
    -DWITH_PCRE=bundled \
    -DWITH_JEMALLOC=no \
    -DWITH_SYSTEMD=no \
    -DWITH_WSREP=OFF \
    -DWITH_EMBEDDED_SERVER=OFF \
    -DWITH_UNIT_TESTS=OFF \
    -DCONC_WITH_UNIT_TESTS=OFF \
    -DWITH_MARIABACKUP=OFF \
    -DWITH_URING=no \
    -DWITH_LIBFMT=bundled \
    -DPLUGIN_ROCKSDB=NO \
    -DPLUGIN_DUCKDB=NO \
    -DPLUGIN_MROONGA=NO \
    -DPLUGIN_SPIDER=NO \
    -DPLUGIN_CONNECT=NO \
    -DPLUGIN_COLUMNSTORE=NO \
    -DPLUGIN_S3=NO \
    -DPLUGIN_OQGRAPH=NO \
    -DPLUGIN_SPHINX=NO \
    -DPLUGIN_TOKUDB=NO \
    -DPLUGIN_AUTH_GSSAPI=NO \
    -DPLUGIN_AUTH_GSSAPI_CLIENT=NO \
    -DPLUGIN_AUTH_PAM=NO \
    -DPLUGIN_AUTH_PAM_V1=NO \
    -DPLUGIN_CRACKLIB_PASSWORD_CHECK=NO \
    -DPLUGIN_HASHICORP_KEY_MANAGEMENT=NO \
    -DPLUGIN_AWS_KEY_MANAGEMENT=NO \
    -DPLUGIN_PROVIDER_BZIP2=NO \
    -DPLUGIN_PROVIDER_LZ4=NO \
    -DPLUGIN_PROVIDER_LZMA=NO \
    -DPLUGIN_PROVIDER_LZO=NO \
    -DPLUGIN_PROVIDER_SNAPPY=NO \
    -DPLUGIN_PERFSCHEMA=YES \
    -DWITH_READLINE=ON \
    -DCMAKE_DISABLE_FIND_PACKAGE_Boost=ON \
    -DCMAKE_DISABLE_FIND_PACKAGE_LibXml2=ON \
    -DCMAKE_DISABLE_FIND_PACKAGE_CURL=ON

case "$TARGET" in
    linux-*)
        # libstdc++ / libgcc are linked in, everything else non-libc is bundled by bundle-linux-libs.sh.
        # The static libcrypto needs pthread / dl in every module that pulls it in.
        set -- "$@" \
            -DCMAKE_EXE_LINKER_FLAGS="-static-libstdc++ -static-libgcc" \
            -DCMAKE_SHARED_LINKER_FLAGS="-static-libstdc++ -static-libgcc" \
            -DCMAKE_MODULE_LINKER_FLAGS="-static-libstdc++ -static-libgcc" \
            -DCMAKE_C_STANDARD_LIBRARIES="-lpthread -ldl" \
            -DCMAKE_CXX_STANDARD_LIBRARIES="-lpthread -ldl" \
            -DCMAKE_DISABLE_FIND_PACKAGE_PkgConfig=ON
        ;;
    macos-*)
        # Never pick up Homebrew / MacPorts libraries: only /usr/lib and system frameworks may be linked.
        set -- "$@" \
            -DCMAKE_OSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-11.0}" \
            -DCMAKE_IGNORE_PREFIX_PATH="/opt/homebrew;/usr/local;/opt/local" \
            -DCMAKE_FIND_FRAMEWORK=LAST
        case "$TARGET" in
            macos-arm64) set -- "$@" -DCMAKE_OSX_ARCHITECTURES=arm64 ;;
            macos-x64) set -- "$@" -DCMAKE_OSX_ARCHITECTURES=x86_64 ;;
        esac
        ;;
esac

if command -v ninja >/dev/null 2>&1; then set -- -G Ninja "$@"; fi

cmake -S "$SRC" -B "$BUILD" "$@"
cmake --build "$BUILD" --parallel "$JOBS"
DESTDIR="$STAGE" cmake --install "$BUILD" >/dev/null

# Assemble the package from an allowlist of the install tree.
I="$STAGE$PREFIX"
mkdir -p "$PKG/bin" "$PKG/scripts" "$PKG/lib"
for tool in mariadbd mariadb mariadb-admin mariadb-dump mariadb-upgrade mariadb-check my_print_defaults resolveip; do
    cp -p "$I/bin/$tool" "$PKG/bin/"
done
cp -p "$I/scripts/mariadb-install-db" "$PKG/scripts/"
# mariadb-install-db looks for the server and tools next to its basedir.
cp -R "$I/share" "$PKG/share"
rm -rf "$PKG/share/man" "$PKG/share/doc" "$PKG/share/mysql-test" "$PKG/share/aclocal" 2>/dev/null || true
if [ -d "$I/lib/plugin" ]; then
    mkdir -p "$PKG/lib/plugin"
    find "$I/lib/plugin" -maxdepth 1 -type f \( -name '*.so' -o -name '*.dylib' \) -exec cp -p {} "$PKG/lib/plugin/" \;
    # Test / example plugins from the MariaDB test suite.
    for p in $(cat "$ROOT/package/excluded-plugins.txt"); do rm -f "$PKG/lib/plugin/$p.so" "$PKG/lib/plugin/$p.dylib"; done
fi
cp -p "$I/COPYING" "$PKG/COPYING" 2>/dev/null || cp -p "$SRC/COPYING" "$PKG/COPYING"
cp -p "$I/CREDITS" "$PKG/CREDITS" 2>/dev/null || true
cp -p "$ROOT/package/README.txt" "$PKG/README.txt"
printf '%s\n' "MariaDB $MARIADB_VERSION, portable-mariadb r$REVISION, target $TARGET" > "$PKG/VERSION"

case "$TARGET" in
    linux-*)
        "$ROOT/scripts/bundle-linux-libs.sh" "$PKG"
        find "$PKG/bin" "$PKG/lib" -type f \( -perm -u+x -o -name '*.so*' \) -exec strip --strip-unneeded {} \; 2>/dev/null || true
        ;;
    macos-*)
        find "$PKG/bin" "$PKG/lib" -type f \( -perm -u+x -o -name '*.so' -o -name '*.dylib' \) -exec strip -x {} \; 2>/dev/null || true
        "$ROOT/scripts/check-macos-links.sh" "$PKG"
        ;;
esac

tar -C "$WORK" -czf "$DIST/$NAME.tar.gz" "$NAME"
(cd "$DIST" && { sha256sum "$NAME.tar.gz" 2>/dev/null || shasum -a 256 "$NAME.tar.gz"; } > "$NAME.tar.gz.sha256")
echo "Built $DIST/$NAME.tar.gz ($(du -h "$DIST/$NAME.tar.gz" | cut -f1))"
