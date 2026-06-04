# Gemini PDA Linux Build Project

## Project Goal
Boot a fresh Kali Linux arm64 installation on the Planet Computers Gemini PDA
(MediaTek MT6797X / Helio X25, kernel 3.18.41-kali+). The existing Kali
installation was too old to upgrade in-place, so a new rootfs was built from
scratch. See `PROGRESS.md` for full status.

---

## Current State (as of 2026-06-03)

### What is flashed on the device
| Partition | File | Status |
|-----------|------|--------|
| `boot2` | `~/gemini-build/OUTPUT/kali_boot_patched.img` | Last flashed — has sensor blacklist |
| `linux` (`/dev/mmcblk0p29`) | `~/gemini-build/OUTPUT/linux.img` | Flashed — rootfs is good |

### Boot status
Linux boots past the initial MTK sensor crashes but may still crash on
additional sensor drivers. Android boots normally. See **Unresolved Issue**
below.

---

## Host Environment
- **Machine**: Apple Mac Studio M4 Max
- **Host OS**: macOS (Apple Silicon / ARM64)
- **Acceleration**: QEMU uses HVF (Hypervisor.framework) — near-native ARM64 speed
- **VM Tool**: QEMU via Homebrew (`brew install qemu`)
- **Flash tool**: `~/.local/bin/mtk` (mtkclient) — preloader mode, ~5 MB/s

---

## VM Environment
- **Arch**: aarch64 (ARM64) — matches Gemini hardware natively
- **Base OS**: Kali Linux Rolling (arm64) — matches target distro
- **Machine type**: `virt` with HVF acceleration
- **SSH port**: `localhost:5522` → VM port 22
- **Shared folder**: `~/gemini-build/` on host ↔ `/mnt/host/` in VM (virtfs)
- **Disk image**: `~/gemini-build/vm/gemini-build.qcow2`
- **RAM**: 8GB | **CPUs**: 8
- **Snapshots**: `baseline` (clean install + deps), `pre-build`, `good-rootfs`

### Start VM
```bash
qemu-system-aarch64 \
  -machine virt,accel=hvf \
  -cpu host \
  -smp 8 \
  -m 8G \
  -bios /opt/homebrew/share/qemu/edk2-aarch64-code.fd \
  -drive if=none,file=~/gemini-build/vm/gemini-build.qcow2,format=qcow2,id=hd0 \
  -device virtio-blk-device,drive=hd0 \
  -device virtio-net-pci,netdev=net0 \
  -netdev user,id=net0,hostfwd=tcp:127.0.0.1:5522-:22 \
  -virtfs local,path=$HOME/gemini-build,mount_tag=hostshare,security_model=mapped \
  -nographic
```

### SSH into VM
```bash
ssh -p 5522 root@localhost
```

---

## VM Snapshot Commands
```bash
qemu-img snapshot -c <name> ~/gemini-build/vm/gemini-build.qcow2   # save
qemu-img snapshot -l ~/gemini-build/vm/gemini-build.qcow2          # list
qemu-img snapshot -a <name> ~/gemini-build/vm/gemini-build.qcow2   # restore
qemu-img snapshot -d <name> ~/gemini-build/vm/gemini-build.qcow2   # delete
```

---

## Flashing

### Flash tool
```bash
~/.local/bin/mtk w <partition> <file>
```
Power device fully off, plug USB without pressing buttons (preloader mode).
No volume buttons on Gemini = no easy BROM mode; preloader mode is the only
reliable path, limited to ~5 MB/s.

### Partition names
| Partition | Purpose |
|-----------|---------|
| `boot2` | Linux kernel boot image |
| `linux` | Linux rootfs (ext4) |
| `boot` | Android boot (do not touch) |

### Flash the current patched boot image
```bash
~/.local/bin/mtk w boot2 ~/gemini-build/OUTPUT/kali_boot_patched.img
```

### Flash the rootfs
```bash
~/.local/bin/mtk w linux ~/gemini-build/OUTPUT/linux.img
```

---

## Unresolved Issue — MTK Sensor Driver Crashes

The 3.18 kernel initialises all built-in MTK sensor drivers during
`kernel_init`, before any userspace runs. In Linux boot mode the bootloader
does not initialise I2C sensor hardware, so every sensor driver that calls
`i2c_device_probe` triggers a page fault → `ipanic_die` → reboot loop.

**Workaround in place**: `initcall_blacklist` in the DTB bootargs blacklists
the known-crashing init functions. The current patched image includes:
```
alsps_init, acc_init, gyro_init, mag_init, baro_init,
step_c_init, step_d_init, pdr_init, fusion_init, batch_init,
sar_init, hw_motion_sensor_init
```

**To debug a new crash**: boot Android, then:
```bash
adb shell cat /proc/last_kmsg | tail -80
```
Look for `<function>_init` in the call trace. Add it to the blacklist in
`/tmp/patch_dtb_bootargs.py` and rebuild + reflash `boot2`.

**Permanent fix**: recompile the kernel with sensor drivers disabled:
```
CONFIG_CUSTOM_KERNEL_ALSPS=n
CONFIG_CUSTOM_KERNEL_ACCELEROMETER=n
CONFIG_CUSTOM_KERNEL_GYROSCOPE=n
CONFIG_CUSTOM_KERNEL_MAGNETOMETER=n
CONFIG_CUSTOM_KERNEL_BAROMETER=n
CONFIG_CUSTOM_KERNEL_STEP_COUNTER=n
```
Kernel source: `github.com/Re4son/gemini-kali-linux-kernel-3.18`

---

## Rootfs Details

- Built with `mmdebstrap` (replaced defunct multistrap)
- Kernel modules from the original 2019 `linux.img`
- `/sbin/init` → `/sbin/init-gemini` (custom minimal init, bypasses systemd 260)
- SSH: authorized key for `benhamilton@mac-studio.local`; password: `toor`
- ext4 incompatible features removed: `orphan_file`, `metadata_csum_seed`

### Re-patch ext4 features if rebuilding rootfs
```bash
tune2fs -O ^orphan_file,^metadata_csum_seed ~/gemini-build/OUTPUT/linux.img
```

### Re-patch boot image cmdline
```bash
python3 /tmp/patch_dtb_bootargs.py
# then flash boot2
```

---

## Key Source Repositories

| Repo | Purpose |
|------|---------|
| `github.com/Re4son/kali-gemini-multistrap-config` | Rootfs build scripts |
| `github.com/Re4son/gemini-kali-linux-kernel-3.18` | Kernel 3.18 with MTK + Wi-Fi injection patches |
| `github.com/Re4son/kali-gemini-linux` | Kernel modules Debian package |
| `github.com/gemian/gemini-linux-kernel-3.18` | Alternative kernel tree (more recent fixes) |
| `github.com/osm0sis/mkbootimg` | Boot image creation tool |

---

## Architecture Notes

### Why the kernel cannot be tested in the VM
The Gemini kernel (3.18) targets MediaTek MT6797X hardware and requires Android
hardware blobs for display, GPU, modem, and sensors. QEMU's `virt` machine does
not emulate this hardware. The VM is used for:
- ✅ Building the kernel and rootfs
- ✅ Testing userspace packages and scripts
- ✅ Chrooting into the built rootfs via `qemu-user-static`
- ❌ Booting the actual Gemini kernel
- ❌ Testing hardware-dependent features (display, Wi-Fi, modem)

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `accel=hvf` fails | Ensure macOS 13+ and QEMU 7+. Try `-machine virt,accel=tcg` as fallback |
| Kernel module version mismatch | Ensure kernel source and modules package are the same commit |
| `mmdebstrap` GPG error | Add `--skip=check/gpg` flag or import Kali signing keys |
| Linux boot crash loop | Check `adb shell cat /proc/last_kmsg`, identify crashing `_init` function, add to blacklist |
| mtkclient `OSError: Unable to find libfuse` | Already patched in `~/mtkclient/mtkclient/Library/Filesystem/mtkdafs.py` |
| Stale DA session blocking flash | `rm ~/gemini-build/OUTPUT/.state ~/gemini-build/OUTPUT/hwparam.json` then power cycle |
| Build fills disk | `qemu-img resize gemini-build.qcow2 +20G` then `resize2fs` in VM |
