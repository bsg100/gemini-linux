# Gemini PDA Linux

Boot a fresh Kali Linux arm64 installation on the [Planet Computers Gemini PDA](https://www.planetcom.co.uk/gemini-pda) (MediaTek MT6797X / Helio X25, kernel 3.18.41-kali+).

The existing Kali installation was too old to upgrade in-place, so a new rootfs was built from scratch alongside the original 2019 kernel image.

See [`PROGRESS.md`](PROGRESS.md) for full status, technical notes, and lessons learned.

---

## Current Status

- **Rootfs**: Built with `mmdebstrap`, flashed to the `linux` partition. SSH comes up via a custom minimal init that bypasses systemd 260 (incompatible with kernel 3.18).
- **Boot image**: Patched with `initcall_blacklist` to skip all MTK sensor drivers that crash on i2c probe before userspace starts.
- **Blocker**: Each sensor driver crash requires a flash cycle (~10 min at 5 MB/s). The permanent fix is recompiling the kernel with sensor drivers disabled.

---

## Repository Contents

| Path | Description |
|------|-------------|
| `FlashToolLinux/` | SP Flash Tool (Linux) for flashing via USB |
| `Scatter_Gemini_x25_x27_A30GB_L26GB_Multi_Boot.txt` | MTK scatter file — partition layout |
| `PROGRESS.md` | Full build log, current state, and next steps |
| `claude.md` | Build environment reference |

Large binary files (rootfs image, boot images, firmware dumps, zips) are excluded from this repo — see `.gitignore`.

---

## Hardware

| Component | Detail |
|-----------|--------|
| Device | Planet Computers Gemini PDA |
| SoC | MediaTek MT6797X (Helio X25) |
| Kernel | 3.18.41-kali+ (MTK + Wi-Fi injection patches) |
| Boot mode | Preloader (USB, no volume buttons needed) |
| Flash speed | ~5 MB/s via preloader DA |

---

## Flashing

Power the device fully off, plug in USB without pressing buttons (preloader mode), then:

```bash
# Flash boot image
~/.local/bin/mtk w boot2 ~/gemini-build/OUTPUT/kali_boot_patched.img

# Flash rootfs
~/.local/bin/mtk w linux ~/gemini-build/OUTPUT/linux.img
```

Flash tool: [mtkclient](https://github.com/bkerler/mtkclient)

---

## Debugging a Boot Crash

Boot Android, then:

```bash
adb shell cat /proc/last_kmsg | tail -80
```

Look for `<function>_init` in the call trace. Add it to the `initcall_blacklist` in the DTB bootargs patch script, rebuild, and reflash `boot2`.

---

## Key Repositories

| Repo | Purpose |
|------|---------|
| [Re4son/gemini-kali-linux-kernel-3.18](https://github.com/Re4son/gemini-kali-linux-kernel-3.18) | Kernel 3.18 with MTK + Wi-Fi injection patches |
| [Re4son/kali-gemini-multistrap-config](https://github.com/Re4son/kali-gemini-multistrap-config) | Rootfs build scripts |
| [Re4son/kali-gemini-linux](https://github.com/Re4son/kali-gemini-linux) | Kernel modules Debian package |
| [gemian/gemini-linux-kernel-3.18](https://github.com/gemian/gemini-linux-kernel-3.18) | Alternative kernel tree |
| [osm0sis/mkbootimg](https://github.com/osm0sis/mkbootimg) | Boot image creation tool |
