#!/bin/sh
# Copies every shared library a package's binaries need, except the libc family that every Linux
# system has, into <pkg>/lib and points the binaries at it with an $ORIGIN-relative RPATH.
# Fails if a dependency cannot be resolved.
set -eu

PKG=${1:?package dir required}
LIB="$PKG/lib"
mkdir -p "$LIB"

# Libraries that are part of glibc / musl themselves: always taken from the host.
is_system_lib() {
    case "$1" in
        linux-vdso.so.*|linux-gate.so.*|ld-linux*.so*|ld64.so.*|ld-musl-*.so*|libc.so*|libc.musl-*.so*|\
        libm.so*|libdl.so*|libpthread.so*|librt.so*|libresolv.so*|libutil.so*|libanl.so*) return 0 ;;
    esac
    return 1
}

elf_files() {
    find "$PKG/bin" "$PKG/lib" -type f | while read -r f; do
        if head -c 4 "$f" 2>/dev/null | grep -q 'ELF'; then echo "$f"; fi
    done
}

# Repeat until no new library gets copied (bundled libraries can have dependencies of their own).
changed=1
while [ "$changed" = 1 ]; do
    changed=0
    for f in $(elf_files); do
        deps=$(ldd "$f" 2>/dev/null || true)
        if echo "$deps" | grep -q 'not found'; then
            # A dependency already bundled in lib/ may only be found after the RPATH is set below.
            missing=$(echo "$deps" | awk '/not found/ {print $1}')
            for m in $missing; do
                [ -f "$LIB/$m" ] || { echo "Unresolved dependency $m of $f" >&2; exit 1; }
            done
        fi
        for path in $(echo "$deps" | awk '/=> \// {print $3}'); do
            base=$(basename "$path")
            is_system_lib "$base" && continue
            if [ ! -f "$LIB/$base" ]; then
                echo "Bundling $base (needed by ${f#$PKG/})"
                cp -L "$path" "$LIB/$base"
                chmod 755 "$LIB/$base"
                changed=1
            fi
        done
    done
done

for f in $(elf_files); do
    case "$f" in
        "$PKG"/bin/*) rpath='$ORIGIN/../lib' ;;
        "$PKG"/lib/plugin/*) rpath='$ORIGIN/..' ;;
        *) rpath='$ORIGIN' ;;
    esac
    # Static binaries / libraries without a dynamic section are left alone.
    patchelf --print-needed "$f" >/dev/null 2>&1 || continue
    patchelf --set-rpath "$rpath" "$f"
done

# Final check: nothing may be left unresolved.
for f in $(elf_files); do
    if ldd "$f" 2>/dev/null | grep -q 'not found'; then
        echo "Unresolved dependencies in $f:" >&2
        ldd "$f" >&2
        exit 1
    fi
done
