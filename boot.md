# Boot Log and Observations

## Milestone: Baseline Kali Boot Confirmed

**Date:** 2026-06-07

**State:** Original Planet Computers Kali Linux image, flashed via the official Gemini Flash Tool (SP Flash Tool, x86 Linux) using the scatter file `Scatter_Gemini_x25_x27_A30GB_L26GB_Multi_Boot.txt`.

**Result:** Device boots and user can log in to Kali Linux.

**Kernel:** 3.18.41-kali+ (vendor BSP kernel, built by Planet Computers)
- Built: Wed Apr 2019
- Builder: root@WOPR-Debian-II
- Compiler: gcc 4.9 20150123 (prerelease)
- Config: `#12 SMP PREEMPT`

**Significance:** This is the known-good baseline. Any regression during kernel bring-up can be recovered by reflashing this image. The partition layout on this device is the authoritative reference — do not modify it.

---

## Notes

- `mtk wl` (write-from-directory via mtkclient) corrupted the partition table during an earlier attempt. Recovery required a full reflash with the official Flash Tool. See CLAUDE.md Flashing section.
- The Kali userspace (`linux.img`) was built against kernel 3.18. Compatibility with Linux 6.6 is an open question — see CLAUDE.md Open Questions.
- The `boot2` partition holds the Kali kernel (`kali_boot.img`). This is the only partition that needs to be replaced when testing a new kernel for Kali.

---

## Boot-Chain Evidence Extracted from kali_boot.img (2026-06-10)

The vendor DTB and the known-good kernel's embedded config were re-extracted
from `planet/kali_boot.img` and committed to `docs/vendor-dtb/` (DTB is
byte-identical to the known-good reference recorded in archive/progress2.md —
130,745 bytes).

### Console (contradiction resolved)

The effective console on the known-good boot is **ttyMT0 = UART0 @ 0x11002000
@ 921600** (vendor DTB `chosen/bootargs`). The `ttyMT3` in the known-good
kernel's `CONFIG_CMDLINE` is a never-used fallback (`CONFIG_CMDLINE_FROM_BOOTLOADER=y`,
EXTEND/FORCE unset) — the archive/progress2.md ttyMT3 note is superseded.
Pinmux GPIO97=URXD0 / GPIO98=UTXD0 confirmed by both the vendor DTB pinctrl
nodes and MT6797 spec Table 2-7. Full table in [kernel.md](kernel.md).

### Android boot image header (boot2 / kali_boot.img)

| Field | Value |
|-------|-------|
| kernel | load 0x40080000, size 9,082,465 B (Image.gz + appended DTB at blob offset 8,951,720) |
| ramdisk | load 0x45000000, size 872,380 B (Mer Boat Loader) |
| tags | 0x44000000 |
| page size | 2048 |
| header cmdline | `bootopt=64S3,32N2,64N2 log_buf_len=4M` |
| DTB bootargs | `console=tty0 console=ttyMT0,921600n1 root=/dev/ram initrd=0x44000000,0x4B434E loglevel=8` |

### Vendor reserved-memory map (now reproduced in dts/0001)

Fixed-address regions (vendor DTB lines 317–409):

| Region | Address | Size | no-map (vendor) |
|--------|---------|------|------------------|
| spm-dummy | 0x40000000 | 0x1000 | no |
| RAM console | 0x44400000 | 0x10000 | no |
| pstore | 0x44410000 | 0xe0000 | no |
| minirdump | 0x444f0000 | 0x10000 | no |
| ATF | 0x44600000 | 0x10000 | **yes** |
| ATF ramdump | 0x44610000 | 0x30000 | **yes** |
| cache dump | 0x44640000 | 0x30000 | **yes** |
| preloader | 0x44800000 | 0x100000 | no |
| LK | 0x46000000 | 0x400000 | no |

Dynamic (size+alignment, allocated at boot by 3.18 drivers — omitted from our
DTS): ccci_md1 (0xa100000), ccci_share (0x600000), consys (0x200000),
spm (0x16000), scp_share (0x1000000).

Note: vendor DTB memory node is a **1 GB placeholder** (`0x40000000 +
0x40000000`) fixed up by preloader/LK at boot. Whether LK fixes up our DTB's
memory node the same way is open — see blockers.md B-3.

---

## First Serial Capture Attempt — UART alive, baud mismatch (2026-06-12)

**Rig:** USB-C breakout board in the left port + genuine FTDI TTL232R-3V3
(`/dev/cu.usbserial-FTBTA9WZ`). VBUS 5 V from the FTDI's red wire (VBUS
pass-through). FTDI RX→D+, TX→D−. Loopback via shorted D+/D− pads passed at
921600 (FTDI + wiring proven). Capture tooling:
`scripts/ftdi-monitor.py` (listen-only; logs hex+ASCII with timestamps).

**Result:** on plug-in (device previously off, Android `boot` partition
active), continuous structured bytes were received at 921600 for ~1 minute
(~300 KB raw, archived at
`docs/captures-2026-06-12-921600-garbled.bin`), then the stream stopped.

**Analysis:** not noise and not USB signalling — 46 % `0x00` bytes with the
remainder dominated by single-set-bit values (`0x80 0x40 0x20 0x82 …`) is the
oversampling signature of a UART transmitting **slower than 921600**. Volume
(~75–100 KB of real text) is consistent with a full verbose boot log. So the
preloader USB-UART mux works and the device transmits console output on D+;
only the baud assumption was wrong for whatever boot stage was talking.

**Follow-up same day (baud sweep + line swap — all garbled):** capturing at
115200 was equally garbled, and run-length analysis of the bitstream shows
*both* sub-bit-period pulses and long dead-low stretches at both rates — not
a baud mismatch signature. Swapping FTDI RX to D− (TX disconnected) gave the
same garbage (58 % zeros, single-set-bit bytes, zero readable fragments).
Captures: `/tmp/gemini-uart-115200.log`, `/tmp/gemini-uart-swapped.log`
(session-local). No boot text was recovered at any setting.

**Root-cause candidates at session end:**
1. ~~**VBUS sag**~~ — **ruled out** (measured same day: 4.9 V at the breakout
   *with the Gemini attached and charging*, 5.10 V unloaded — the FTDI VCC
   wire holds the rail; preloader cable-detect has solid VBUS).
2. **1.8 V signal levels** — front-runner: if the mux passes raw SoC-level
   UART, it is marginal against the FTDI 3V3's ~1.5 V input threshold.

**Next session protocol:**
1. Charge fully on a real charger first (device off the rig).
2. Multimeter at boot logo: D+↔GND and D−↔GND —
   steady ~3.3 V = UART idle (good), ~1.8 V = level shifter needed
   (BSS138-type bidirectional board between breakout and FTDI),
   bouncing ≈0–0.7 V = mux never switched.
3. Re-capture at 921600 with FTDI RX on whichever line idles high.

**Caution learned:** each VBUS plug-in boots the device into charging mode,
but the FTDI's 5 V line (~75 mA budget) cannot actually charge it. Repeated
test cycles drained the battery to 1 % and caused boot-looping (logo screens
then reset — brownout signature; resolved after user reflash + real charge).
Recharge on a real charger between test sessions; do not leave the device
running off the rig.

---

## First Clean Serial Capture — console confirmed working (2026-07-04)

**Rig:** USB-C breakout in the left port + selectable-voltage FTDI-style
adapter, previously set to 1.8 V (matching the SoC's native UART pad voltage,
but wrong for this mux path — see kernel.md), switched to **3.3 V** per the
documented USB-C mux requirement. VBUS 5 V fed from the adapter's 5 V pin.
Capture: `scripts/ftdi-monitor.py --log logs/2026-07-04-01-first-serial-attempt.log`,
`/tmp/ftdi-venv` (pyserial 3.5), 921600 baud, listen-only.

**Result:** fully clean, readable text from first byte — no garbling, no
level-mismatch symptoms. This resolves the 2026-06-12 root-cause open
question in favour of candidate 2 (1.8 V signal levels): the earlier garbled
captures were the FTDI's 3.3 V threshold misreading marginal/1.8 V-ish
levels, exactly as hypothesised. Switching the adapter's own I/O rail to
3.3 V (rather than adding a discrete level shifter) was sufficient.

**Content:** log captures the full stock MediaTek preloader → PMIC/DRAM
init → GPT parse → LK bootloader → ATF (BL31) chain, ending at the jump to
the Linux kernel (`[LK]jump to K64 0x40080000` / `el3_exit`, log line ~1944).
LK explicitly loads the **`boot`** partition (line 572: `[PART_LK][get_part]
boot`), i.e. this is the **stock Android 3.18 kernel**, not the Kali
`boot2` kernel — no partition was reflashed this session. Confirms:
- cmdline: `console=tty0 console=ttyMT0,921600n1 root=/dev/ram vmalloc=496M
  slub_max_order=0 ... androidboot.hardware=mt6797 ...` — consistent with
  kernel.md's documented UART0/921600 console.
- GPT partition table matches hardware.md/CLAUDE.md's documented layout
  exactly (`boot`, `boot2`, `linux`, etc., same offsets).
- DRAM: 2 ranks, 0x40000000 + 0x80000000 (1 GiB) plus a further 1 GiB rank at
  0x100000000 — 4 GB total, consistent with `[Enable 4GB Support]`.

Log ends at the kernel jump because capture was stopped there, not because
of a hang — the vendor 3.18 kernel's own console output was not captured
this session (not needed: this run's purpose was cable/console validation,
not a 6.6 boot attempt).

**Significance:** this is the Phase 3 milestone the driver-work freeze
(CLAUDE.md, blockers.md B-1) was gating on. Cable, wiring, VBUS mux, and
baud are now all proven end-to-end on real hardware. The freeze can be
revisited — next step is flashing a Linux 6.6 `boot2` image and capturing
its console output the same way.

---

## Future Entries

Boot logs from kernel bring-up attempts will be appended here as Phase 3 progresses.

**First entry on FTDI cable arrival (per blockers.md B-1):** baseline serial
capture of the known-good 3.18 Kali boot — validates cable/wiring/baud before
any 6.6 flash.
