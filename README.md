# rpi-kernel-k8s

The Raspberry Pi OS kernel for the Raspberry Pi 5 (`rpi-2712` flavour), rebuilt
with **BTF** and **Landlock** enabled, as a signed apt repository.

The stock kernel is built with `CONFIG_DEBUG_INFO_NONE=y` and without Landlock:

- **No BTF** (`/sys/kernel/btf/vmlinux` is missing). eBPF tools that rely on
  CO-RE break or need hand-made BTF files. Cilium 1.20+, for example, can't
  load its socket-LB programs without it, and new pods get no networking.
- **No Landlock**, so sandboxes that use it (e.g. for coding agents or other
  untrusted workloads) can't enforce anything.
- **No UDP socket diag / `SOCK_DESTROY`** (`CONFIG_INET_UDP_DIAG`,
  `CONFIG_INET_DIAG_DESTROY`). Cilium's socket-LB then can't close sockets that
  still point at deleted service backends, and logs an error about it at startup.

Everything else is the stock kernel: same source package, same patches, same
package names and boot hooks. Only the options in
[`config/rpi-2712.config`](config/rpi-2712.config) are added.

## How it works

A daily workflow checks the
[Raspberry Pi archive](http://archive.raspberrypi.com/debian/) for a new `linux`
source package. When there is one, it

1. downloads it with `apt-get source` inside a `debian:trixie` arm64 container.
   apt verifies it against the archive's signed index, using the pinned key in
   [`keys/`](keys),
2. appends the config fragment, bumps the version to `…+rptN+k8sM` and builds
   the rpi-2712 package set ([`scripts/build.sh`](scripts/build.sh)),
3. attaches the packages, the full kernel config and the build log to a
   [GitHub release](../../releases),
4. publishes the newest three releases as an apt repository on GitHub Pages.

Packages built: `linux-image-<abi>-rpi-2712`, `linux-image-rpi-2712`,
`linux-base-<abi>-rpi-2712`, `linux-base-rpi-2712`,
`linux-headers-<abi>-rpi-2712`, `linux-headers-rpi-2712`,
`linux-headers-<abi>-common-rpi`, `linux-kbuild-<abi>`.
The stock meta packages pin each other to the exact version, so they are
replaced as a set.

## Install

Raspberry Pi 5 with Raspberry Pi OS trixie (64-bit) only.

```sh
sudo curl -fsSLo /etc/apt/keyrings/rpi-kernel-k8s.asc \
  https://max06.github.io/rpi-kernel-k8s/rpi-kernel-k8s.asc

sudo tee /etc/apt/sources.list.d/rpi-kernel-k8s.sources <<'EOF'
Types: deb
URIs: https://max06.github.io/rpi-kernel-k8s/
Suites: trixie
Components: main
Architectures: arm64
Signed-By: /etc/apt/keyrings/rpi-kernel-k8s.asc
EOF

sudo tee /etc/apt/preferences.d/rpi-kernel-k8s <<'EOF'
# Prefer the rebuilt kernel packages ...
Package: linux-image-*rpi-2712 linux-base-*rpi-2712 linux-headers-*rpi-2712 linux-headers-*-common-rpi linux-kbuild-*
Pin: release o=rpi-kernel-k8s
Pin-Priority: 990

# ... and don't install a new stock kernel before its rebuild exists.
Package: linux-image-*rpi-2712 linux-base-*rpi-2712 linux-headers-*rpi-2712 linux-headers-*-common-rpi linux-kbuild-*
Pin: release o=Raspberry Pi Foundation
Pin-Priority: -1
EOF

sudo apt update
sudo apt full-upgrade
sudo reboot
```

Check the result:

```sh
uname -v                          # ... Debian 1:6.18.60-1+rpt1+k8s1 ...
ls -l /sys/kernel/btf/vmlinux
cat /sys/kernel/security/lsm      # contains landlock
```

### Notes

- **Updates lag the stock kernel** by up to a day (daily check plus a build of
  about an hour). The second pin keeps a new stock kernel from being installed
  in the meantime.
- **`v8` headers get removed:** Raspberry Pi OS also installs the `rpi-v8`
  kernel, which a Pi 5 doesn't boot. Its headers (`linux-headers-rpi-v8`,
  `linux-headers-<abi>-rpi-v8`) depend on the exact stock version of the shared
  `linux-headers-<abi>-common-rpi` and `linux-kbuild-<abi>`, so apt removes them
  when it installs the rebuilt ones. The v8 kernel image itself stays.
- **Going back:** remove the two files above, then
  `sudo apt install --allow-downgrades linux-image-rpi-2712=<stock version> …`
  for the packages listed under [How it works](#how-it-works).

## Build it yourself

On a Pi 5 running Raspberry Pi OS (about an hour, ~20 GB of disk):

```sh
sudo apt-get install fakeroot dpkg-dev
mkdir src && cd src
# needs a deb-src line for http://archive.raspberrypi.com/debian/ trixie main
apt-get source --download-only linux=1:6.18.60-1+rpt1
sudo apt-get build-dep -P pkg.linux.nokerneldbg,pkg.linux.mintools,pkg.linux.nosource,nodoc linux=1:6.18.60-1+rpt1
cd .. && scripts/build.sh 6.18.60-1+rpt1 src out
```

## Forking

1. Create a signing key without a passphrase and store it as the secret
   `APT_SIGNING_KEY`:
   ```sh
   export GNUPGHOME=$(mktemp -d)
   gpg --batch --passphrase '' --quick-gen-key "rpi-kernel-k8s apt repository" ed25519 sign never
   gpg --armor --export-secret-keys | gh secret set APT_SIGNING_KEY -R <you>/rpi-kernel-k8s
   rm -rf "$GNUPGHOME"
   ```
2. Settings → Pages → Source: **GitHub Actions**.
3. Run the `build` workflow once by hand.
4. Replace `max06.github.io` in the install instructions.

GitHub disables scheduled workflows in public repositories after 60 days without
activity. Renovate's dependency updates usually keep the repository active.

## License

GPL-2.0-only, see [LICENSE](LICENSE), for this repository's scripts and config
and, as always, for the kernel. The kernel's corresponding source is the Raspberry Pi OS source
package named in each release, plus [`config/rpi-2712.config`](config/rpi-2712.config)
and the changelog version bump in [`scripts/build.sh`](scripts/build.sh).
