#!/bin/sh
# Fails if any Mach-O file in a package links against a library outside the macOS system paths
# (e.g. a Homebrew copy of OpenSSL that would not exist on the user's machine).
set -eu

PKG=${1:?package dir required}
bad=0
for f in $(find "$PKG/bin" "$PKG/lib" -type f); do
    file "$f" | grep -q 'Mach-O' || continue
    otool -L "$f" | tail -n +2 | awk '{print $1}' | while read -r dep; do
        case "$dep" in
            /usr/lib/*|/System/Library/*|@rpath/*|@loader_path/*|@executable_path/*) ;;
            *) echo "$f links non-system library $dep" >&2; exit 1 ;;
        esac
    done || bad=1
done
[ "$bad" = 0 ]
