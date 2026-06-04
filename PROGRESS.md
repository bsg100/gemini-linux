# Gemini PDA Linux Boot — Project Progress

## Goal
Boot a fresh Kali Linux arm64 installation on the Planet Computers Gemini PDA
(MediaTek MT6797X / Helio X25, kernel 3.18.41-kali+) by building a new rootfs
and flashing it alongside the existing 2019 kernel image.

---

## What Was Accomplished

### Rootfs built and flashed
- Built a fresh Kali arm64 rootfs using `mmdebstrap` (kali-rolling,
  kali-linux-headless) inside a QEMU arm64 VM with HVF acceleration
- Image: `~/gemini-build/OUTPUT/linux.img` (10 GB ext4), flashed to the
  `linux` partition (`/dev/mmcblk0p29`)

### ext4 compatibility fixed
Modern `mkfs.ext4` (1.47) enables features the 3.18 kernel cannot mount:
- `orphan_file` — requires kernel 5.15+
- `metadata_csum_seed` — requires kernel 4.4+

Fixed with:
```bash
tune2fs -O ^orphan_file,^metadata_csum_seed ~/gemini-build/OUTPUT/linux.img
```

### systemd incompatibility bypassed
systemd 260 (current Kali 2026) requires kernel 4.15+. The Gemini kernel is
3.18. Created a minimal custom init at `/sbin/init-gemini` that bypasses
systemd entirely:
- Mounts proc/sys/dev/pts/run/tmp
- Sets hostname
- Brings up loopback + eth0 (dhclient)
- Generates SSH host keys if missing
- Starts sshd
- Spawns agetty on ttyMT0 (921600 baud) and tty0
- Verified working via chroot in QEMU VM

### initcall_blacklist confirmed working
Patched the kernel cmdline in `kali_boot.img` by modifying the DTB bootargs
in-place (expanding into the 415-byte page padding before the ramdisk, so the
ramdisk page boundary is never disturbed). Also patched the Android boot image
header cmdline at offset 0x040 as belt-and-suspenders.

Blacklisting `alsps_init` successfully skipped that crash — confirmed by the
next boot log showing a *different* driver failing, proving the mechanism works.

---

## Where It Stalled

### Cascading MTK sensor driver crashes
The 3.18 kernel initialises all built-in sensor drivers during `kernel_init`,
before any userspace runs. In Linux boot mode the Android bootloader (LK) does
not initialise the I2C sensor hardware, so every sensor driver that attempts
`i2c_device_probe` triggers a page fault → `ipanic_die` →
`emergency_restart` → reboot loop.

Crash pattern (from `last_kmsg` via ADB):
```
[<ffffffc000939e10>] i2c_device_probe+0xe8/0x158
[<ffffffc0004bXXXX>] <driver>_local_init+...
[<ffffffc00129XXXX>] <sensor>_init+...
[<ffffffc000081bf8>] do_one_initcall+0xc0/0x1e8
[<ffffffc00126dc3c>] kernel_init_freeable+0x1c4/0x260
```

Confirmed crashes in order:
1. `alsps_init` → `stk3x1x_local_init` (ambient light/proximity)
2. `acc_init` → `lsm6ds3_local_init` (accelerometer)
3. (likely) `gyro_init`, `mag_init`, `baro_init`, and others

Each flash + boot cycle takes ~10 minutes (USB at ~5 MB/s in preloader mode),
making whack-a-mole impractical.

---

## Current State of Files

| File | Location | Status |
|------|-----------|--------|
| `linux.img` | `~/gemini-build/OUTPUT/linux.img` | Flashed to `linux` partition — rootfs is good |
| `kali_boot.img` | `~/gemini-build/OUTPUT/kali_boot.img` | Original 2019 boot image |
| `kali_boot_patched.img` | `~/gemini-build/OUTPUT/kali_boot_patched.img` | Patched with full sensor blacklist (ready to flash) |

The patched image blacklists:
```
alsps_init, acc_init, gyro_init, mag_init, baro_init,
step_c_init, step_d_init, pdr_init, fusion_init, batch_init,
sar_init, hw_motion_sensor_init
```

---

## Fastest Path to Success

### Option A — Flash the ready image (one more attempt)
`kali_boot_patched.img` is built and waiting. It just needs a successful flash:
```bash
~/.local/bin/mtk w boot2 ~/gemini-build/OUTPUT/kali_boot_patched.img
```
Power the Gemini fully off, plug in USB without pressing buttons (preloader
mode). If the sensor blacklist is comprehensive enough, Linux will boot and SSH
will come up on the DHCP address (root / toor).

If it crashes again, check `last_kmsg` via ADB for the new failing
`<sensor>_init` function and add it to the blacklist in
`/tmp/patch_dtb_bootargs.py`, rebuild, and reflash.

### Option B — Recompile the kernel (permanent fix)
Disable the crashing drivers in the kernel config:
```
CONFIG_CUSTOM_KERNEL_ALSPS=n
CONFIG_CUSTOM_KERNEL_ACCELEROMETER=n
CONFIG_CUSTOM_KERNEL_GYROSCOPE=n
CONFIG_CUSTOM_KERNEL_MAGNETOMETER=n
CONFIG_CUSTOM_KERNEL_BAROMETER=n
CONFIG_CUSTOM_KERNEL_STEP_COUNTER=n
```
Kernel source: `github.com/Re4son/gemini-kali-linux-kernel-3.18`
Build environment: QEMU arm64 VM at `~/gemini-build/vm/gemini-build.qcow2`
(snapshot `baseline` available).

This eliminates the crash loop entirely and is the correct long-term fix.

---

## Lessons Learned — Token / Time Efficiency

### Diagnose the kernel first, before building anything
The sensor driver crash was the entire blocker. A single boot attempt with the
*existing* 2019 rootfs would have surfaced this before any rootfs building or
VM setup. Cost: 1 flash + 1 ADB log read.

### Anticipate whack-a-mole on sensor drivers
After the first sensor crash (`alsps_init`), the right move was to immediately
blacklist *all* ~12 MTK sensor init functions. They all follow the same pattern
(`<sensor>_init` → `<driver>_local_init` → `i2c_device_probe` → crash).
Doing it one at a time cost 3 extra flash cycles (~30 minutes, many tokens).

### Read logs selectively
```bash
# Crash identification needs only the bottom of last_kmsg:
adb shell cat /proc/last_kmsg | tail -50
# Or grep directly for the crashing function:
adb shell cat /proc/last_kmsg | grep -E "_init\+|arch_reset"
# Flash completion needs only the last line:
tail -5 /tmp/flash.log
```
Reading full output files (2500+ lines of `"Port - Hint..."`) into context
was expensive and unnecessary.

### Validate the kernel can reach userspace before building a full rootfs
Boot a minimal busybox initramfs (~10 MB) to confirm the kernel survives
`kernel_init` before committing to a 10 GB rootfs build pipeline.

### Get the boot image format right first, test second
Three iterations of the cmdline patch script (UnicodeDecodeError → broken
ramdisk alignment → working) could have been one with upfront analysis of the
Android boot image page structure.

---

## Key Technical Notes

- **Boot partition**: `boot2` (sector 62683136) — not `boot` (Android)
- **Linux partition**: `/dev/mmcblk0p29` — hardcoded in Mer Boat Loader ramdisk
- **Flash tool**: `~/.local/bin/mtk` (mtkclient) — preloader mode only; BROM
  mode not reliably accessible without volume buttons
- **Flash speed**: ~5 MB/s (preloader DA); official MTK DA gets 40 MB/s but
  requires BROM mode
- **DTB bootargs patch script**: `/tmp/patch_dtb_bootargs.py` — modifies
  original `kali_boot.img`, safe to re-run
- **SSH auth**: key `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAUngFg1mnm1tFGY3CSFe4zgDF0vk0HvDxUgLNwXGX0D` in rootfs authorized_keys; password: toor
