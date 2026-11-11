#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Print the newest Raspberry Pi OS kernel source version (without epoch), e.g. 6.18.60-1+rpt1.
# Only used to decide whether to build; the build itself fetches through verified apt.
set -euo pipefail
SUITE=${SUITE:-trixie}
curl -fsS "http://archive.raspberrypi.com/debian/dists/${SUITE}/main/source/Sources.gz" \
  | gzip -dc \
  | awk '/^Package: /{pkg=$2} /^Version: /&&pkg=="linux"{print $2}' \
  | sed 's/^[0-9]*://' \
  | sort -V | tail -1
