#!/bin/bash
# Build a signed apt repository from a directory of .deb files.
#
# Usage: scripts/publish-repo.sh <debs-dir> <site-dir>
# Env:   SIGNING_KEY  key id/fingerprint to sign with (default: the only secret key)
#        SUITE (trixie), ORIGIN (rpi-kernel-k8s)
set -euo pipefail

DEBS_DIR=$(readlink -f "$1")
SITE_DIR=$(readlink -m "$2")
SUITE=${SUITE:-trixie}
ORIGIN=${ORIGIN:-rpi-kernel-k8s}
SIGNING_KEY=${SIGNING_KEY:-$(gpg --batch --list-secret-keys --with-colons | awk -F: '/^fpr/{print $10; exit}')}
[ -n "$SIGNING_KEY" ] || { echo "no signing key"; exit 1; }

dist="dists/${SUITE}"
mkdir -p "$SITE_DIR/pool/main" "$SITE_DIR/$dist/main/binary-arm64"
cp "$DEBS_DIR"/*.deb "$SITE_DIR/pool/main/"
cd "$SITE_DIR"

# Arch-all packages (headers-common) are listed with the arm64 ones.
apt-ftparchive packages pool > "$dist/main/binary-arm64/Packages"
gzip -9kf "$dist/main/binary-arm64/Packages"

apt-ftparchive \
  -o "APT::FTPArchive::Release::Origin=${ORIGIN}" \
  -o "APT::FTPArchive::Release::Label=${ORIGIN}" \
  -o "APT::FTPArchive::Release::Suite=${SUITE}" \
  -o "APT::FTPArchive::Release::Codename=${SUITE}" \
  -o "APT::FTPArchive::Release::Architectures=arm64" \
  -o "APT::FTPArchive::Release::Components=main" \
  -o "APT::FTPArchive::Release::Description=Raspberry Pi OS kernels rebuilt with BTF and Landlock" \
  release "$dist" > "$dist/Release.tmp"
mv "$dist/Release.tmp" "$dist/Release"

gpg --batch --yes --local-user "$SIGNING_KEY" --clearsign -o "$dist/InRelease" "$dist/Release"
gpg --batch --yes --local-user "$SIGNING_KEY" --armor --detach-sign -o "$dist/Release.gpg" "$dist/Release"
gpg --batch --armor --export "$SIGNING_KEY" > "${ORIGIN}.asc"

{
  echo "<!doctype html><meta charset=utf-8><title>${ORIGIN}</title>"
  echo "<h1>${ORIGIN}</h1><p>apt repository. Setup: <a href=\"https://github.com/${GITHUB_REPOSITORY:-max06/rpi-kernel-k8s}\">README</a>.</p>"
  echo "<pre>"
  for deb in pool/main/*.deb; do basename "$deb"; done
  echo "</pre>"
} > index.html
