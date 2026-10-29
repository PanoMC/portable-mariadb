portable-mariadb
================

A relocatable MariaDB server build. It needs no installation and no system libraries beyond the
operating system's C library: extract it anywhere and run it from that folder.

Layout
  bin/        mariadbd (server), mariadb (client), mariadb-admin, mariadb-dump, mariadb-upgrade,
              mariadb-check, my_print_defaults, resolveip
  scripts/    mariadb-install-db (Linux / macOS) - creates a new data directory
  share/      error messages, character sets, system table SQL
  lib/        bundled shared libraries (Linux) and server plugins

Quick start (Linux / macOS)
  B=/path/to/this/folder
  $B/scripts/mariadb-install-db --no-defaults --basedir=$B --datadir=$HOME/mdb-data \
      --auth-root-authentication-method=normal --skip-test-db
  $B/bin/mariadbd --no-defaults --basedir=$B --datadir=$HOME/mdb-data \
      --port=3307 --bind-address=127.0.0.1 --socket=$HOME/mdb.sock
  $B/bin/mariadb -uroot --socket=$HOME/mdb.sock
  $B/bin/mariadb-admin -uroot --socket=$HOME/mdb.sock shutdown

  mariadbd refuses to run as root unless --user=root is given.

Quick start (Windows)
  bin\mariadb-install-db.exe --datadir=C:\mdb-data --password=secret --port=3307
  bin\mariadbd.exe --defaults-file=C:\mdb-data\my.ini --console

MariaDB is licensed under the GNU GPL v2 (see COPYING). The exact source this package was built from
is attached to the same release (mariadb-<version>.tar.gz), the build scripts are at
https://github.com/PanoMC/portable-mariadb.
