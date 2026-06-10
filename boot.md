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

## Future Entries

Boot logs from kernel bring-up attempts will be appended here as Phase 3 progresses.

**First entry on FTDI cable arrival (per blockers.md B-1):** baseline serial
capture of the known-good 3.18 Kali boot — validates cable/wiring/baud before
any 6.6 flash.
