# portable-mariadb

Relocatable MariaDB **server** packages for every common OS / architecture. A package needs no
installation, no package manager and no system libraries except the OS C library: download, extract,
run. Built for [Pano](https://panomc.com) to offer a "built-in database" without asking users to
install MySQL / MariaDB, but usable by anything that needs a private MariaDB.

## Targets

| Target | Built on | Runs on |
|---|---|---|
| `linux-x64`, `linux-arm64`, `linux-x86` | manylinux_2_28 (AlmaLinux 8) | any distro with glibc ≥ 2.28 (Debian 10+, Ubuntu 20.04+, RHEL/Rocky/Alma 8+, Fedora, Arch, openSUSE 15+) |
| `linux-armv7` | manylinux_2_31 | glibc ≥ 2.31 (Raspberry Pi OS 11+, Debian 11+, Ubuntu 20.04+) |
| `linux-musl-x64`, `linux-musl-arm64`, `linux-musl-x86`, `linux-musl-armv7` | musllinux_1_2 (Alpine) | Alpine 3.18+ and other musl distros |
| `linux-ppc64le`, `linux-s390x`, `linux-riscv64` | manylinux (QEMU) | experimental, published when the build succeeds |
| `macos-arm64`, `macos-x64` | GitHub macOS runners | macOS 11+ |
| `windows-x64`, `windows-arm64` | MSVC 2022, static CRT | Windows 10+ / Server 2016+, no VC++ redistributable |
| `windows-x86` | MSVC 2022 | experimental |

## What is inside

`bin/` holds `mariadbd` plus the tools a host needs around it: `mariadb`, `mariadb-admin`,
`mariadb-dump`, `mariadb-upgrade`, `mariadb-check`, `my_print_defaults`, `resolveip` and (Windows)
`mariadb-install-db.exe`. `scripts/mariadb-install-db` on Linux / macOS, `share/` (messages,
charsets, bootstrap SQL), `lib/plugin/`, and on Linux `lib/` with the bundled shared libraries.

The build keeps InnoDB, Aria, MyISAM, performance_schema, JSON, PCRE2 regex and TLS (bundled
wolfSSL) and drops everything that needs an external library or a cluster: Galera, RocksDB, DuckDB,
ColumnStore, Mroonga, Spider, CONNECT, S3, OQGraph, PAM / GSSAPI auth, compression providers,
mariabackup and the embedded library.

How portability is ensured:

- **Linux**: built on an old glibc base, `libstdc++` / `libgcc` linked statically, every other
  non-libc dependency copied into `lib/` with an `$ORIGIN` RPATH (`scripts/bundle-linux-libs.sh`).
  No systemd, no libaio / liburing (InnoDB uses its thread-pool AIO).
- **macOS**: Homebrew / MacPorts prefixes are ignored at configure time, and
  `scripts/check-macos-links.sh` fails the build if anything outside `/usr/lib` or `/System` is linked.
- **Windows**: static CRT, and the build fails if a binary imports a non-system DLL.

Every package is smoke-tested in CI (bootstrap a data dir, start, queries over socket + TCP, dump,
shutdown). Linux packages are tested in bare containers of several distros
(`scripts/test-linux-distros.sh`).

## Releases and manifest

A release is tagged `v<mariadb version>-r<revision>`, e.g. `v11.8.9-r1`. Each one carries the
packages, `SHA256SUMS`, the exact MariaDB source tarball (GPL), and `manifest.json`:

```json
{
  "schema": 1,
  "mariadbVersion": "11.8.9",
  "revision": 1,
  "tag": "v11.8.9-r1",
  "openSslVersion": "3.5.9",
  "assets": [
    { "target": "linux-x64", "os": "linux", "arch": "x64", "libc": "glibc", "minGlibc": "2.28",
      "file": "portable-mariadb-11.8.9-r1-linux-x64.tar.gz", "format": "tar.gz",
      "url": "https://github.com/PanoMC/portable-mariadb/releases/download/v11.8.9-r1/…",
      "size": 0, "sha256": "…" }
  ]
}
```

Consumers fetch `https://github.com/PanoMC/portable-mariadb/releases/latest/download/manifest.json`,
pick the asset for their OS / arch / libc, download it and verify `sha256`.

## Building locally

```sh
scripts/build-linux.sh linux-x64            # Docker; other arches need QEMU binfmt
scripts/test-linux-distros.sh linux-x64     # smoke test in bare distro containers
scripts/build-unix.sh macos-arm64           # on a Mac (brew install bison ninja)
pwsh scripts/build-windows.ps1 -Target windows-x64   # VS 2022 + choco install winflexbison3
```

`JOBS`, `DOCKER_MEMORY` and `DOCKER_CPUS` limit the build. Output lands in `dist/`.

## New MariaDB version

Set `MARIADB_VERSION` + `MARIADB_SHA256` (from `archive.mariadb.org/mariadb-<v>/source/sha256sums.txt`)
in `versions.env`, reset `REVISION=1` and push to `main`. A build-only change bumps `REVISION`.
Releasing is automatic: when the version in `versions.env` has no release yet, CI creates the tag
`v<version>-r<revision>` and the release after every build passed. Pushes that keep the version only
build and test.

## License

MariaDB is GPL v2; so are these build scripts (see `LICENSE`). Each package contains MariaDB's
`COPYING`, and each release attaches the corresponding source.
