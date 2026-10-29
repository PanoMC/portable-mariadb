#!/usr/bin/env python3
"""Writes dist/manifest.json and dist/SHA256SUMS for the packages in dist/.

Usage: scripts/make-manifest.py <owner/repo>

Consumers (Pano) read manifest.json from the latest release to find the package for the current
OS / architecture, its download URL and its SHA-256.
"""
import hashlib
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"


def read_versions():
    values = {}
    for line in (ROOT / "versions.env").read_text().splitlines():
        match = re.match(r"^\s*([A-Z_]+)=(.*)$", line)
        if match:
            values[match.group(1)] = match.group(2).strip()
    return values


MIN_GLIBC = {"linux-armv7": "2.31", "linux-riscv64": "2.39"}


def describe(target):
    parts = target.split("-")
    os_name = parts[0]
    libc = None
    if os_name == "linux":
        libc = "musl" if parts[1] == "musl" else "glibc"
    arch = parts[-1]
    entry = {"target": target, "os": os_name, "arch": arch}
    if libc:
        entry["libc"] = libc
        if libc == "glibc":
            entry["minGlibc"] = MIN_GLIBC.get(target, "2.28")
    return entry


def main():
    repo = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("GITHUB_REPOSITORY", "PanoMC/portable-mariadb")
    versions = read_versions()
    version, revision = versions["MARIADB_VERSION"], versions["REVISION"]
    tag = f"v{version}-r{revision}"
    prefix = f"portable-mariadb-{version}-r{revision}-"

    assets = []
    sums = []
    for path in sorted(DIST.iterdir()):
        name = path.name
        if not name.startswith(prefix) or not (name.endswith(".tar.gz") or name.endswith(".zip")):
            continue
        target = name[len(prefix):].removesuffix(".tar.gz").removesuffix(".zip")
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        entry = describe(target)
        entry.update({
            "file": name,
            "format": "zip" if name.endswith(".zip") else "tar.gz",
            "url": f"https://github.com/{repo}/releases/download/{tag}/{name}",
            "size": path.stat().st_size,
            "sha256": digest,
        })
        assets.append(entry)
        sums.append(f"{digest}  {name}")

    if not assets:
        sys.exit("no packages in dist/")

    manifest = {
        "schema": 1,
        "mariadbVersion": version,
        "revision": int(revision),
        "tag": tag,
        "openSslVersion": versions["OPENSSL_VERSION"],
        "sources": [
            f"https://github.com/{repo}/releases/download/{tag}/mariadb-{version}.tar.gz",
            f"https://github.com/{repo}/releases/download/{tag}/openssl-{versions['OPENSSL_VERSION']}.tar.gz",
        ],
        "assets": assets,
    }
    (DIST / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (DIST / "SHA256SUMS").write_text("\n".join(sums) + "\n")
    print(f"manifest.json: {len(assets)} packages for {tag}")


if __name__ == "__main__":
    main()
