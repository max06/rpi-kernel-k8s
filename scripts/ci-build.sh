#!/bin/bash
# Runs as root inside a debian:trixie arm64 container: fetches the kernel source
# package from the Raspberry Pi archive through apt (verified against the signed
# index with the pinned archive key), installs build deps, then runs build.sh.
#
# Usage: scripts/ci-build.sh <version> <out-dir>
set -euo pipefail

SRC_VERSION=$1
OUT_DIR=$(readlink -m "$2")
REPO_DIR=$(dirname "$(dirname "$(readlink -f "$0")")")
PROFILES=pkg.linux.nokerneldbg,pkg.linux.mintools,pkg.linux.nosource,nodoc
export DEBIAN_FRONTEND=noninteractive

install -m 0644 "$REPO_DIR/keys/raspberrypi-archive-keyring.pgp" /usr/share/keyrings/
cat > /etc/apt/sources.list.d/raspberrypi.sources <<'EOF'
Types: deb deb-src
URIs: http://archive.raspberrypi.com/debian/
Suites: trixie
Components: main
Signed-By: /usr/share/keyrings/raspberrypi-archive-keyring.pgp
EOF

apt-get update -q
apt-get install -y -q --no-install-recommends ca-certificates dpkg-dev fakeroot xz-utils

src_dir=$(mktemp -d)
(cd "$src_dir" && apt-get source -q --download-only "linux=1:${SRC_VERSION}")
apt-get build-dep -y -q -P "$PROFILES" "linux=1:${SRC_VERSION}"

df -h /
"$REPO_DIR/scripts/build.sh" "$SRC_VERSION" "$src_dir" "$OUT_DIR"
df -h /
