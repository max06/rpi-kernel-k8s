#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Rebuild the Raspberry Pi OS kernel source package (rpi-2712 flavour) with the
# options in config/rpi-2712.config. Expects the source package files
# (.dsc, .orig.tar.xz, .debian.tar.xz) in SRC_DIR and the build dependencies installed.
#
# Usage: scripts/build.sh <version> <src-dir> <out-dir>
#   version: source version without epoch, e.g. 6.18.60-1+rpt1
# Env:     LOCAL_SUFFIX (default +k8s1), WORK_DIR (default: a temp dir)
set -euo pipefail

SRC_VERSION=$1
SRC_DIR=$(readlink -f "$2")
OUT_DIR=$(readlink -m "$3")
LOCAL_SUFFIX=${LOCAL_SUFFIX:-+k8s1}
UPSTREAM=${SRC_VERSION%%-*}
REPO_DIR=$(dirname "$(dirname "$(readlink -f "$0")")")
WORK_DIR=${WORK_DIR:-$(mktemp -d)}

if [ "$(id -u)" = 0 ]; then FAKEROOT=(); else FAKEROOT=(fakeroot); fi

mkdir -p "$WORK_DIR" "$OUT_DIR"
cd "$WORK_DIR"
rm -rf "linux-${UPSTREAM}"
dpkg-source -x "$SRC_DIR/linux_${SRC_VERSION}.dsc" "linux-${UPSTREAM}"
cd "linux-${UPSTREAM}"

# The rpi-2712 flavour config is the last file merged, so appended options win.
cat "$REPO_DIR/config/rpi-2712.config" >> debian/config/arm64/rpi/config.2712

# Bump the version in the top entry instead of adding one: a second changelog entry
# for the same upstream version makes gencontrol append "+1" to the ABI name,
# which renames every package and stops this from being a drop-in replacement.
sed -i "1s/(1:${SRC_VERSION})/(1:${SRC_VERSION}${LOCAL_SUFFIX})/" debian/changelog
head -1 debian/changelog | grep -qF "(1:${SRC_VERSION}${LOCAL_SUFFIX})" \
  || { echo "changelog version bump FAILED: $(head -1 debian/changelog)"; exit 1; }

debian/rules debian/control-real

abi="${UPSTREAM}+rpt"
# The whole rpi-2712 set: the stock meta packages pin each other with "=", so
# replacing only the image would break linux-image-rpi-2712 / linux-headers-rpi-2712.
packages=(
  "linux-image-${abi}-rpi-2712" "linux-image-rpi-2712"
  "linux-base-${abi}-rpi-2712" "linux-base-rpi-2712"
  "linux-headers-${abi}-rpi-2712" "linux-headers-rpi-2712"
  "linux-headers-${abi}-common-rpi" "linux-kbuild-${abi}"
)
for pkg in "${packages[@]}"; do
  grep -qx "Package: ${pkg}" debian/control \
    || { echo "package name check FAILED: ${pkg} not in debian/control"; exit 1; }
done
echo "package name check OK"

# mintools = only linux-kbuild, which the headers package depends on.
export DEB_BUILD_PROFILES="pkg.linux.nokerneldbg pkg.linux.mintools pkg.linux.nosource nodoc"
jobs=$(nproc)
export DEB_BUILD_OPTIONS="parallel=${jobs} nodoc"

"${FAKEROOT[@]}" make -f debian/rules.gen setup_arm64_rpi_2712

config=debian/build/build_arm64_rpi_2712/.config
while read -r want; do
  case $want in ''|'##'*) continue ;; esac
  grep -qxF "$want" "$config" || { echo "config check FAILED: $want missing in $config"; exit 1; }
done < "$REPO_DIR/config/rpi-2712.config"
echo "config check OK"

# debian/rules turns parallel=N into -jN; rules.gen called directly needs it explicitly.
time "${FAKEROOT[@]}" make -j"${jobs}" -f debian/rules.gen \
  binary-arch_arm64_rpi_2712 binary-arch_arm64_kbuild binary-indep_rpi_headers-common

for pkg in "${packages[@]}"; do
  ls ../"${pkg}"_*.deb >/dev/null 2>&1 || { echo "missing package: ${pkg}"; exit 1; }
done
cp -v ../*.deb "$OUT_DIR/"
cp debian/build/build_arm64_rpi_2712/.config "$OUT_DIR/config-${abi}-rpi-2712"
echo BUILD_DONE
