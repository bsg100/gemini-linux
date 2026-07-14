#!/bin/bash
# mkrootfs.sh — build a Debian 13 (trixie) arm64 root filesystem image for
# the Gemini PDA's `linux` partition (p29). Run INSIDE the build VM (native
# arm64 — no emulation needed).
#
# Usage: ./scripts/mkrootfs.sh
# Output: /mnt/host/OUTPUT/debian13-rootfs.img (sparse ext4, 4 GiB virtual)
#
# Boot-chain facts this relies on (verified 2026-07-05, boot.md):
#  - The vendor kali_boot ramdisk ("Mer Boat Loader") mounts /dev/mmcblk0p29
#    with a bare busybox `mount` (kernel fs autodetect, no options) and then
#    `exec switch_root /target /sbin/init --log-target=kmsg`. It prefers
#    /sbin/preinit if executable — Debian does not ship one. So a plain
#    ext4 image with a standard systemd /sbin/init needs no ramdisk changes.
#  - systemd auto-spawns serial-getty@ttyS0 from console=ttyS0,921600n1.
#  - The image may be smaller than the 25.8 GiB partition; grow on device
#    with: resize2fs /dev/mmcblk0p29
#
# Flash from the Mac (device in preloader mode; NEVER `mtk wl`):
#   /tmp/mtk-venv/bin/python3 ~/mtkclient/mtk.py w linux ~/gemini-build/OUTPUT/debian13-rootfs.img
# Recovery: reflash the 2019 image, planet/linux.img, the same way.

set -euo pipefail

SUITE=trixie
TARGET=/root/rootfs-build/debian13
IMG_TMP=/root/rootfs-build/debian13-rootfs.img
IMG_OUT=/mnt/host/OUTPUT/debian13-rootfs.img
IMG_SIZE=4G          # build size (headroom for mkfs -d)
IMG_SHRUNK=1536M     # shipped size after resize2fs shrink
LINUX_SRC="${LINUX_SRC:-$HOME/linux-6.6}"

PKGS_BASE=systemd,systemd-sysv,udev,dbus,kmod,util-linux,e2fsprogs,ca-certificates,apt
PKGS_NET=openssh-server,iproute2,ifupdown,isc-dhcp-client
# busybox-static: loadkmap (gemini-keymap.service) + devmem/base64 debug
# tools; iputils-ping: basic connectivity checks (was missing on minbase)
PKGS_TOOLS=i2c-tools,mmc-utils,evtest,usbutils,less,vim-tiny,htop,busybox-static,iputils-ping,sudo

command -v mmdebstrap >/dev/null || apt-get install -y mmdebstrap

echo "==> [1/5] mmdebstrap $SUITE -> $TARGET"
rm -rf "$TARGET" "$IMG_TMP"
mkdir -p "$(dirname "$TARGET")"
mmdebstrap --variant=minbase \
    --include="$PKGS_BASE,$PKGS_NET,$PKGS_TOOLS" \
    "$SUITE" "$TARGET"

echo "==> [2/5] Configure target"
echo gemini > "$TARGET/etc/hostname"
cat > "$TARGET/etc/hosts" <<'EOF'
127.0.0.1	localhost
127.0.1.1	gemini
EOF
cat > "$TARGET/etc/fstab" <<'EOF'
/dev/mmcblk0p29  /  ext4  defaults,noatime  0  1
EOF
echo 'root:toor' | chroot "$TARGET" chpasswd
mkdir -p "$TARGET/etc/ssh/sshd_config.d"
echo 'PermitRootLogin yes' > "$TARGET/etc/ssh/sshd_config.d/gemini.conf"
# Mac SSH key for passwordless scripted sessions (installed live 2026-07-14;
# mirrored here so reflashes keep it — see B-17 for why that matters)
mkdir -p "$TARGET/root/.ssh"
chmod 700 "$TARGET/root/.ssh"
echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAUngFg1mnm1tFGY3CSFe4zgDF0vk0HvDxUgLNwXGX0D benhamilton@mac-studio.local' \
    > "$TARGET/root/.ssh/authorized_keys"
chmod 600 "$TARGET/root/.ssh/authorized_keys"
# Unprivileged user (user request 2026-07-14): gemini/gemini, sudoer
chroot "$TARGET" useradd -m -s /bin/bash -G sudo gemini
echo 'gemini:gemini' | chroot "$TARGET" chpasswd
# Persistent journal: keep dmesg/journal from boots where SSH/serial were
# unavailable (B-20 diagnosis) readable on the next good boot
mkdir -p "$TARGET/var/log/journal" "$TARGET/etc/systemd/journald.conf.d"
printf '[Journal]\nStorage=persistent\n' \
    > "$TARGET/etc/systemd/journald.conf.d/persistent.conf"
# The vendor initramfs runs `mdev -s` on the shared devtmpfs before
# switch_root; busybox mdev's default rule chmods nodes to 0660 root:root,
# which broke dbus (first unprivileged /dev/null open) until udev coldplug
# caught up. Restore standard modes early via tmpfiles.d (runs in
# systemd-tmpfiles-setup-dev-early, well before dbus). See boot.md dbus RCA.
cat > "$TARGET/etc/tmpfiles.d/gemini-devnodes.conf" <<'EOF'
z /dev/null    0666 root root -
z /dev/zero    0666 root root -
z /dev/full    0666 root root -
z /dev/random  0666 root root -
z /dev/urandom 0666 root root -
z /dev/tty     0666 root tty  -
z /dev/ptmx    0666 root tty  -
EOF
# usb0 config for SSH over USB gadget ethernet (g_ether, kernel #40+);
# inert while the interface is absent. Mac side: 10.15.19.1/24.
cat > "$TARGET/etc/systemd/network/usb0.network" <<'EOF'
[Match]
Name=usb0
[Network]
Address=10.15.19.82/24
EOF
chroot "$TARGET" systemctl enable systemd-networkd >/dev/null 2>&1

# Gemini console keymap: Fn key = AltGr (DTS maps it to KEY_RIGHTALT), and
# this busybox bkeymap adds the Fn/AltGr layer + US-silkscreen shift fixes
# (derived from Gemian's XKB planet_vndr/gemini "us" variant — see boot.md
# 2026-07-12 "Fn layer"). Loaded at boot by gemini-keymap.service; needs
# busybox (loadkmap applet). rootfs-files/ lives in the repo next to
# scripts/; the rsync to the VM carries it.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "$SCRIPT_DIR/../rootfs-files/gemini.bkmap" "$TARGET/etc/gemini.bkmap"
cp "$SCRIPT_DIR/../rootfs-files/gemini-keymap.service" \
   "$TARGET/etc/systemd/system/gemini-keymap.service"
chroot "$TARGET" systemctl enable gemini-keymap.service >/dev/null 2>&1

# run-once diagnostic harness: executes /root/run-once.sh at boot if present,
# logs to /var/log/run-once/ (see rootfs-files/run-once-exec header)
install -m 755 "$SCRIPT_DIR/../rootfs-files/run-once-exec" \
    "$TARGET/usr/local/sbin/run-once-exec"
cp "$SCRIPT_DIR/../rootfs-files/run-once.service" \
   "$TARGET/etc/systemd/system/run-once.service"
mkdir -p "$TARGET/var/log/run-once"
chroot "$TARGET" systemctl enable run-once.service >/dev/null 2>&1

echo "==> [3/5] Install kernel modules from $LINUX_SRC"
make -C "$LINUX_SRC" ARCH=arm64 modules_install \
    INSTALL_MOD_PATH="$TARGET" INSTALL_MOD_STRIP=1 >/dev/null
ls "$TARGET/lib/modules/"

echo "==> [4/5] Pack sparse ext4 image ($IMG_SIZE)"
truncate -s "$IMG_SIZE" "$IMG_TMP"
mkfs.ext4 -q -L gemini-root -d "$TARGET" "$IMG_TMP"
rm -rf "$TARGET"

echo "==> [5/5] Shrink to minimize flash time, copy to host share"
# mtk w transfers the full logical file size over slow preloader USB, so
# shrink the fs to a snug size; first boot runs resize2fs to grow to the
# full 25.8 GiB partition.
e2fsck -fy "$IMG_TMP" >/dev/null
resize2fs "$IMG_TMP" "$IMG_SHRUNK"
truncate -s "$IMG_SHRUNK" "$IMG_TMP"
e2fsck -fn "$IMG_TMP" >/dev/null
cp --sparse=always "$IMG_TMP" "$IMG_OUT"
rm -f "$IMG_TMP"
fstrim / >/dev/null 2>&1 || true
sha256sum "$IMG_OUT"
echo "Done. Flash with: mtk w linux ~/gemini-build/OUTPUT/debian13-rootfs.img"
