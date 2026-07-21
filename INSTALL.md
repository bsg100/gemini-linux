# Installing Linux 6.6 on the Gemini PDA

This guide covers flashing a working Linux 6.6 build to your Gemini PDA
(MediaTek Helio X27). It assumes you are starting from the vendor Android
firmware and want to install this project's kernel + rootfs onto the
device's secondary boot slot, keeping the ability to boot back into stock
Android at any time.

**Read this entire document, especially "Safety rules," before flashing
anything.**

## What you get

- Linux 6.6 LTS, mostly-upstream drivers, booting to a full Debian 13
  (trixie) userspace over SSH.
- Working: serial console, eMMC storage, display (panel), keyboard,
  charging, USB gadget (left port) and USB host/ethernet (right port),
  audio, touchscreen.
- Not working / not attempted: internal WiFi and Bluetooth (see
  `blockers.md` B-21 — permanently parked, use a USB WiFi dongle on the
  right port instead), Fn keyboard layer, camera, GPS, LTE, suspend/resume.

See `CLAUDE.md`'s phase table for the current status of every subsystem,
and `hardware.md` / `driver_ports.md` for per-component detail.

## Why this is safe to try

The Gemini has two bootable slots:

- `boot` / `system` — stock Android (untouched by this project).
- `boot2` / `linux` — the slot this project flashes.

Flashing `boot2` and `linux` never touches your Android install. If
anything goes wrong on the Linux side, you still boot to stock Android
normally. A full factory recovery path also exists (see "Recovery" below)
if the device becomes unresponsive.

## Requirements

**Hardware:**
- A Gemini PDA (Helio X27 model).
- A USB cable capable of data (not charge-only).
- Optional but strongly recommended for bring-up/debug: a 3.3V FTDI USB-serial
  adapter — this project uses a genuine
  [FTDI TTL-232R-3V3](https://ftdichip.com/products/ttl-232r-3v3/) cable —
  wired through a USB-C breakout board into the Gemini's left port (which
  exposes the debug UART on the D+/D− pins: UART0 @ 921600 baud, RX=GPIO97,
  TX=GPIO98). Without it you have no visibility if boot fails silently.

**Software (on a Linux or macOS host):**
- Python 3 with a virtualenv, for `mtkclient`
  (https://github.com/bkerler/mtkclient) — used to flash partitions.
- This repo, cloned locally.
- Either a prebuilt `boot.img` + rootfs image (see Releases), or a Linux
  build environment to build your own (see `CLAUDE.md` "Build Environment"
  if you want to build from source instead of using a release).

## Safety rules — read before touching mtkclient

- **Never run `mtk wl` (write-from-directory), or anything that rewrites
  the GPT/partition table.** Doing this once during this project's
  development corrupted the partition table badly enough to require a full
  firmware reinstall via the official flash tool. Only ever flash single,
  named partitions.
- **Only flash `boot2` and `linux`.** These are the only partitions this
  project touches. Never flash `boot` or `system` (stock Android) unless
  you are deliberately restoring them.
- Keep the device in preloader mode when flashing: power it on and connect
  USB — no button combo is needed if the preloader is intact.

## Step 1 — get the images

Download `new_kali_boot.img` (kernel) and `debian13-rootfs.img.gz`
(rootfs, gzip-compressed) from this repo's
[Releases page](../../releases), or build your own from source — see
`CLAUDE.md` for the full build-VM workflow if you want to build rather
than flash a release.

Verify the download against `SHA256SUMS.txt` (also attached to the
release) before flashing:

```bash
shasum -a 256 -c SHA256SUMS.txt
```

Decompress the rootfs image before flashing:

```bash
gunzip debian13-rootfs.img.gz
```

## Step 2 — set up mtkclient

```bash
python3 -m venv ~/mtk-venv
~/mtk-venv/bin/pip install -r ~/mtkclient/requirements.txt
```

(Clone `mtkclient` first if you haven't: `git clone
https://github.com/bkerler/mtkclient`.)

Always invoke it as `python3 ~/mtkclient/mtk.py ...` — the installed
`mtk` console-script entrypoint is broken in some checkouts.

## Step 3 — flash the kernel (`boot2`)

Connect the Gemini via USB in preloader mode, then from your host:

```bash
~/mtk-venv/bin/python3 ~/mtkclient/mtk.py w boot2 /path/to/new_kali_boot.img
```

## Step 4 — flash the rootfs (`linux`)

```bash
~/mtk-venv/bin/python3 ~/mtkclient/mtk.py w linux /path/to/debian13-rootfs.img
```

This image is several GB; the write is slow (some minutes). Do not
interrupt it.

## Step 5 — first boot

Power-cycle the device. If you have the FTDI serial rig connected, monitor
it — this is the only way to see what's happening before networking comes
up:

```bash
python3 scripts/ftdi-monitor.py --log firstboot.log --interactive
```

Serial console: UART0, 921600 baud 8N1.

On a healthy boot you'll see the kernel banner, storage mount, and
`systemd` reach `running`. The rootfs image ships smaller than the full
partition — grow it once, on-device, after first boot:

```bash
resize2fs /dev/mmcblk0p29
```

**Note on the on-device panel:** the kernel log stays on the physical
screen throughout boot and afterward (`console=tty0` is kept on
permanently in this build, by design — it's the only console output once
the USB mux switches away from serial). This is expected, not a fault,
and it's genuinely useful for a first boot: if something goes wrong, the
error is sitting right there on the panel with no serial rig required. If
you'd rather quiet it down once you're satisfied the device boots
cleanly, run this over SSH or the console after logging in:

```bash
dmesg -n 1
```

This stops new kernel messages from printing to the panel; text already
on screen isn't cleared (`clear`, or starting the desktop with `startx`,
takes care of that).

## Step 6 — connect

The rootfs ships with SSH enabled and DHCP on the USB gadget interface. On
your host, bring up the USB gadget network interface (on macOS this
usually appears as an "RNDIS/Ethernet Gadget" interface and needs a
manual static IP alias, e.g. `10.15.19.1/24`, before it can reach the
device). Then:

```bash
ssh <user>@10.15.19.82
```

Default credentials are whatever was set at rootfs build time — check
`scripts/mkrootfs.sh` if you built your own image, or the release notes
if you downloaded one.

## Recovery — reverting to stock Android

The vendor `boot`/`system` slot is never modified by this project, so a
simple reboot without any of the above gets you back to stock Android.

If the device becomes unresponsive to the point that even the vendor slot
won't boot, do a full reflash using the official SP Flash Tool (x86 Linux)
with the Gemini's scatter file and the original factory images. This is
the same recovery path documented for this project's own development in
`CLAUDE.md` ("Recovery (Full Reflash)").

## Getting help / reporting issues

This is a hobbyist hardware-bring-up project, not a supported product.
Check `blockers.md` and `boot.md` first — they document, in detail, every
issue found during development and whether it was resolved. If you hit
something not covered there, open an issue with your serial log attached;
without a serial capture, a silent boot failure is very hard to diagnose.
