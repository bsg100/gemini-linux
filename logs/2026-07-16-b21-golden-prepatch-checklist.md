# B-21 Stage W0b-2: pre-patch golden CONSYS capture — flash checklist

Goal: capture the vendor MCU ROM's CONSYS state **before** any WMT firmware
download happens, to get a clean pre-firmware reference (hypothesis 1 from
the build #247 session — all prior W0b golden numbers were captured
post-firmware). All `mtk w`/`mtk r` and serial capture commands below are
run by the user on the Mac, never by the assistant (project rule).

## 0. Pre-flight

- [ ] Confirm current flashed build via `uname -a` over SSH before touching
      anything (per feedback_verify_flash_image memory — don't assume).
- [ ] Note current `boot2` build number/banner and `linux` rootfs identity
      for the restore step later.

## 1. Backup current Debian rootfs (`linux`, p29) — non-destructive read

```bash
~/gemini-build/mtk-venv/bin/python3 ~/mtkclient/mtk.py r linux \
    ~/gemini-build/OUTPUT/debian13-rootfs-backup-$(date +%Y%m%d).img
```

- Device must be in preloader mode (power on, connect USB).
- This is a partition **read**, not a write — safe, reversible, just slow
  (~25.8 GiB partition, though only the used portion is real data on a
  sparse read).
- Rootfs customizations are mostly folded into `scripts/mkrootfs.sh`
  already (per boot.md), so this backup is belt-and-braces insurance for
  anything not yet folded in (e.g. SSH host keys, any ad-hoc live changes)
  rather than the primary safety net.

## 2. Flash vendor Kali stack (boot2 + linux)

```bash
# Kali kernel
~/gemini-build/mtk-venv/bin/python3 ~/mtkclient/mtk.py w boot2 planet/kali_boot.img

# Vendor Android/Kali userspace (slow, 5.5 GB)
~/gemini-build/mtk-venv/bin/python3 ~/mtkclient/mtk.py w linux planet/linux.img
```

- **Do not** use `mtk wl` or touch the GPT — targeted partition writes only
  (project flashing rules).
- Reboot into the vendor stack after both writes complete.

## 3. Capture serial boot log (mandatory — logging requirements)

```bash
python3 scripts/ftdi-monitor.py --interactive --log \
    logs/2026-07-1X-NNN-consys-prepatch-boot.log
```

- Capture from power-on, not just after login — the CONSYS MCU release
  happens early in the vendor boot chain, before WMT firmware is pushed by
  the `wmtWifi`/launcher userspace service.

## 4. Capture pre-patch state — race the WMT firmware push

This is the part that's different from the existing W0b golden harvest
(`scripts/consys-golden-harvest.sh`, which was run **after** WiFi was
already toggled on/off through the normal Android/Kali service path):

- [ ] As soon as the vendor userspace is reachable (serial or SSH), before
      manually toggling WiFi, check whether `wmt_launcher`/`wmt_loader` has
      already auto-started and pushed firmware (`dmesg | grep -i wmt`,
      `ps | grep wmt`). If the vendor init already races ahead of you here,
      the "pre-patch" window may only be observable by disabling the WMT
      launcher init script before boot (see step 4a) or by reading the ROM
      state extremely early in serial output.
- [ ] **4a (if needed):** if the vendor init starts WMT automatically, stop
      the relevant init/rc service (identify via `ps`/`init.rc` grep for
      `wmt_launcher`) immediately after boot, before any script runs it, to
      hold the MCU in its post-ROM/pre-firmware state.
- [ ] Run `sh scripts/consys-golden-harvest.sh > \
      logs/consys-prepatch-<timestamp>.txt 2>&1` in this held state.
- [ ] Specifically confirm: CPUPCR idle pattern (10 samples — is it the
      healthy `0x0009997A` steady value, or does it only reach that after
      firmware download?), BTIF HANDSHAKE/TRI_LVL pre-firmware, and
      AP2CONN_OSC_EN (0x10001f00) pre-firmware.
- [ ] Then let/trigger the normal WMT firmware push and immediately harvest
      again (`consys-post-patch-<timestamp>.txt`) for a same-session
      before/after diff — this is the actual deliverable, more reliable
      than comparing against the older W0b harvest taken in a different
      session.

## 5. Restore Debian 13 + our Linux 6.6 kernel

```bash
# Our kernel back on boot2 (use the current provenance dir's image, or
# rebuild via build-pack if patches have moved on)
~/gemini-build/mtk-venv/bin/python3 ~/mtkclient/mtk.py w boot2 \
    logs/<latest-build-dir>/new_kali_boot.img

# Debian rootfs restore
~/gemini-build/mtk-venv/bin/python3 ~/mtkclient/mtk.py w linux \
    ~/gemini-build/OUTPUT/debian13-rootfs.img
```

- If the step-1 backup turned out to matter (something not in
  `mkrootfs.sh`), restore from
  `~/gemini-build/OUTPUT/debian13-rootfs-backup-<date>.img` instead of the
  plain `mkrootfs.sh` output.
- After restore, confirm `uname -a` banner matches expected build and SSH
  connectivity is back (feedback_verify_flash_image).
- `resize2fs /dev/mmcblk0p29` if this was a fresh `mkrootfs.sh` image
  rather than the backup.

## 6. Document

- [ ] New `logs/YYYY-MM-DD-NNN-consys-prepatch/` provenance dir (raw
      harvest txt files + serial log).
- [ ] boot.md entry summarizing the pre/post-firmware diff.
- [ ] Update B-21 in blockers.md with the finding (confirms or kills
      hypothesis 1; feeds into whether hypothesis 2/3 or Stage W3 go/no-go
      is next).
