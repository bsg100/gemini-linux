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

## 6.6 boot.img Packaged — ready to flash (2026-07-04)

**Goal:** produce the first Linux 6.6 `boot2` image for B-2 (blockers.md).

**Build (already validated 2026-06-10, commit `19e91dc`):** clean
`~/linux-6.6` (tag `v6.6`) + full patch set from `gemini_linux` commit
`808ec2a`, built in the Debian 13 VM — `Image.gz`, `mt6797-gemini-pda.dtb`,
and all ported-driver modules, 0 build errors. Outputs are in
`~/gemini-build/OUTPUT/` on the Mac host (VM build artifacts, not committed
to the repo). No patches changed since that build, so no rebuild was
required for this packaging step.

**Packaging:** new script `scripts/pack-boot-img.py` copies the boot.img
header and ramdisk unchanged from `planet/kali_boot.img` (confirmed by
direct hex inspection to be a standard AOSP v0 header — magic `ANDROID!` at
offset 0, no MTK per-section wrapper — with `kernel_addr=0x40080000`,
`ramdisk_addr=0x45000000`, `tags_addr=0x44000000`, `page_size=2048`,
`cmdline="bootopt=64S3,32N2,64N2 log_buf_len=4M"`, all matching the header
table recorded above), and substitutes only the kernel blob with our
`Image.gz` + appended `mt6797-gemini-pda.dtb`.

**Result:** `logs/2026-07-04-02-first-6.6-flash/new_kali_boot.img`
(13,993,984 bytes: header page + kernel blob padded to page size + ramdisk
padded to page size). `.config` copied alongside as
`logs/2026-07-04-02-first-6.6-flash/config`.

**Checksums:**

| File | SHA-256 |
|------|---------|
| `new_kali_boot.img` | `5e42fdc070d7c4919b6b80b168afd981ff6a9870357fc83b92931522620328fb` |
| `Image.gz` | `7ad197fb3e321ca8367fa2cca136b7e4580914f91976d6d5d03728f30b3bd78b` |
| `mt6797-gemini-pda.dtb` | `ccc9b8e21f57d0e6af2e534b05591f50acf1a37cb1c647ac5d4339fc118607e1` |
| `.config` | `c4228181736abacf2cd458631ac46fc81af6fb91e71660f368c0e5f9ace775c6` |

**Not yet done (needs hands on the physical rig):** start
`scripts/ftdi-monitor.py --log logs/2026-07-04-02-first-6.6-flash.log`
listening *before* touching the device, flash with `mtk w boot2
logs/2026-07-04-02-first-6.6-flash/new_kali_boot.img`, then power on and
capture. See blockers.md B-2 for the full remaining checklist and the
diagnostic ladder if the boot is silent.

---

## First 6.6 Flash — flashed, captured, silent after el3_exit (2026-07-04)

**Flash:** `mtk w boot2` of `new_kali_boot.img` (checksums above) via
`mtkclient`, direct USB-C to the Mac (preloader/BROM mode, distinct from the
FTDI console rig). Reported success (EMMC CID/size info logged by mtkclient
matches expected device).

**Capture:** `logs/2026-07-04-02-first-6.6-flash.log`, FTDI rig unchanged
from B-1 (3.3 V adapter, left port).

**Result:** preloader → LK preamble is **byte-for-byte identical** to the
B-1 stock-Android baseline (same PMIC/DRAM/mblock dump, same injected
cmdline, same `bootprof` timings within noise). LK reads our new kernel,
jumps to it, ATF (`BL3-1`) prepares EL3 exit to `0x40080000`, logs
`el3_exit` — **then nothing.** Capture was left running well past this
point with no further bytes.

**Critical control:** the B-1 baseline (known-good stock 3.18 kernel) goes
silent on this same UART at the **exact same point** — `el3_exit` is the
last line in `logs/2026-07-04-01-first-serial-attempt.log` too. So this is
**not evidence of a 6.6 failure** — post-handoff silence is the expected,
already-observed behaviour of this UART, not a new divergence.

**Root cause of the silence (both boots):** LK constructs its own kernel
cmdline independent of our DTS and injects it at handoff:

```
console=tty0 console=ttyMT0,921600n1 root=/dev/ram ... printk.disable_uart=1 ...
```

`ttyMT0` is the vendor MTK console name; mainline's `CONFIG_SERIAL_8250_MT6577`
driver registers as `ttySx`, not `ttyMT0`, so mainline never attaches a
console to the UART no matter what our own DTS `chosen/bootargs` says — LK's
injected cmdline wins. `printk.disable_uart=1` is a vendor-kernel-only
early param (harmless no-op for mainline, but confirms the vendor kernel
also intentionally silences this console post-LK). Checked
`logs/2026-07-04-02-first-6.6-flash/config`: `CONFIG_CMDLINE=""`, no
`CONFIG_CMDLINE_FORCE` — so nothing overrides LK's injected value.

**Conclusion:** this run is **inconclusive on whether 6.6 actually booted**,
not a failure. The UART capture methodology itself can't currently
distinguish "6.6 silently running" from "6.6 crashed at entry", because the
console argument mainline receives is never valid. Need a second attempt
with a forced cmdline before this test means anything either way.

**Next action (updates B-2):** rebuild with
`CONFIG_CMDLINE="console=ttyS0,921600n1 earlycon=uart8250,mmio32,0x11002000"`
and `CONFIG_CMDLINE_FORCE=y` in `.config`, so mainline ignores LK's injected
`ttyMT0` cmdline and always attaches an 8250 console/earlycon to
`0x11002000` regardless of what the bootloader passes. Reflash and recapture
— *this* run is the one that will actually distinguish "6.6 boots" from
"6.6 hangs at entry".

---

## Cmdline Fix Retested — same silence; root cause found (2026-07-04)

**Rebuilt** with the `CONFIG_CMDLINE_FORCE` fix above (`configs/gemini-cmdline.config`,
new `scripts/build.sh` support for merging config fragments after
`defconfig`), reflashed, recaptured. **Identical silence at the exact same
point** (`el3_exit`) — this was the third attempt with the exact same
result, which falsified the console-naming hypothesis: if the kernel had
started executing at all, `earlycon` output happens within the first few
instructions of `start_kernel`, long before any DTB/cmdline parsing that
could be affected by a wrong console name. Total silence across 3 identical
runs means **the CPU is not executing our kernel's code at all** after the
jump.

**Root cause found by inspecting the Image header directly, not the
Kconfig:** `arch/arm64/kernel/head.S` (v6.6) hardcodes the Image header's
load-offset field to `.quad 0` unconditionally, for every mainline arm64
kernel — this is **not affected by `CONFIG_RELOCATABLE` or
`CONFIG_RANDOMIZE_BASE`** (confirmed empirically: disabled both, rebuilt,
`text_offset` in the decompressed header was still `0x0`). Comparing
against the vendor 3.18 kernel's own decompressed Image header:

| | text_offset | flags | protocol |
|---|---|---|---|
| vendor 3.18 kernel | `0x80000` | `0x0` | legacy (pre-v4.6): must be loaded at *2MB-aligned RAM base + 0x80000* |
| our 6.6 kernel | `0x0` | `0xa` (`PHYS_BASE=1`) | modern: may be loaded at **any 2MB-aligned physical address** |

`0xa` is not evidence of relocatability specifically — `PHYS_BASE=1` has
been unconditional in mainline since v4.6, so this flag value is what
*every* mainline arm64 kernel reports, regardless of KASLR/RELOCATABLE
config. The actual defect: our packaged boot.img's `kernel_addr` header
field is `0x40080000` (copied byte-for-byte from the vendor's known-good
header, since LK doesn't reparse the arm64 Image header itself — it just
jumps to whatever `kernel_addr` the *boot.img* header declares). `0x40080000`
is `dram_base (0x40000000, 2MB-aligned) + 0x80000` — correct under the
*old* protocol the vendor kernel uses, but **`0x80000` is not a multiple of
`0x200000` (2MB)**, so this address is not 2MB-aligned. Loading a modern
(`PHYS_BASE=1`) kernel at a non-2MB-aligned address is a boot protocol
violation with undefined (in practice: silent-crash) behaviour — consistent
with all three identical failures.

**Fix (packaging-only, no kernel rebuild needed):** `scripts/pack-boot-img.py`
now accepts `--kernel-addr` to override the boot.img header's load address
independent of the reference image. New image packaged at `kernel_addr =
0x40200000` (2MB-aligned, clear of the `spm-dummy` carve-out at
`0x40000000` and well below the ATF/`tags` region at `0x44000000` and the
ramdisk at `0x45000000` even accounting for the ~34 MB decompressed kernel
size):
`logs/2026-07-04-04-aligned-kernel-addr/new_kali_boot.img`
(sha256 `280a24296043f6cc5a3637ff6b95a15a9ea2a6ab2ea3c485896820a5d39d6901`).

**Next action:** flash this image to `boot2` and recapture. If the CPU
actually starts executing this time, `earlycon` output (from the
`CONFIG_CMDLINE_FORCE` fix, still in effect) should appear within
milliseconds of the jump — that's the signal to watch for.

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

## Aligned kernel_addr Retested — LK ignores the boot.img header field (2026-07-04)

**Test:** flashed `logs/2026-07-04-04-aligned-kernel-addr/new_kali_boot.img`
(built with `pack-boot-img.py --kernel-addr 0x40200000`, 2MB-aligned) to
`boot2`, captured with `scripts/ftdi-monitor.py --log
logs/2026-07-04-04-aligned-kernel-addr.log`.

**Result:** identical silent failure — log still reads `[LK]jump to K64
0x40080000` and ATF's `pc=0x40080000, r0=0x44000000, r1=0x0`, i.e. **LK
loaded the kernel at 0x40080000 regardless of the boot.img header's
`kernel_addr` field.** This MediaTek LK build hardcodes the load address
(`dram_base + 0x80000`) rather than reading it from the header — the
override was silently ignored. Falsifies the "just repackage at an aligned
address" fix.

**Real root cause identified:** 0x40080000 is not 2MB-aligned, and since LK
cannot be told to load elsewhere via the header, the *kernel* must handle
being loaded at a misaligned address itself. This is exactly what
`CONFIG_RELOCATABLE=y` (arch/arm64 default) is for: early boot code in
`head.S` detects a misaligned load address and self-relocates to a valid
2MB boundary before continuing. The previous session's fix attempt had
**disabled** `CONFIG_RELOCATABLE` (chasing an unrelated `text_offset=0x0`
red herring, itself a hardcoded/harmless field — see prior entry) — which
removed the one mechanism that makes booting at this fixed, misaligned
address possible at all. That is the most likely reason every attempt so
far has died silently right after `el3_exit`.

**Fix applied:** `configs/gemini-cmdline.config` reverted to leave
`CONFIG_RELOCATABLE` and `CONFIG_RANDOMIZE_BASE` at their defconfig defaults
(`y`); `CONFIG_CMDLINE_FORCE`/`CONFIG_CMDLINE` kept. Rebuilt in the VM
(`~/build-6.6-reloc-restored.log`, "Build complete", no errors). Repackaged
at the *original* `kernel_addr=0x40080000` (no override — packaging-layer
alignment is moot since LK ignores it):

- `logs/2026-07-04-05-relocatable-restored/new_kali_boot.img`
  sha256 `c8bb8f6bbf13b434efb351ca48d9a41dddfd7dec18c07c2d920cb24db7f43134`
  (13,983,744 bytes), `.config` copied alongside.

**Next (needs hands on hardware):** flash this image to `boot2` and
recapture. If `CONFIG_RELOCATABLE` was indeed the missing piece, this
should show the kernel's self-relocation succeeding and progressing past
`el3_exit` — ideally as far as `earlycon` output.

---

## Vendor Baseline — silence after el3_exit is not diagnostic (2026-07-04)

**Test:** flashed the unmodified vendor `planet/kali_boot.img` (sha256
`4fd3fc081388fbdf083120d0f4e0a4df2eb9a0fb6f66e3d046baaf9986ba95c0`) to
`boot2` and captured a full, uninterrupted boot with
`scripts/ftdi-monitor.py --log logs/2026-07-04-06-vendor-baseline.log`.

**Result:** the known-good vendor 3.18 kernel is **also completely silent**
after `el3_exit` — byte-for-byte the same cutoff point as every 6.6 attempt
(`[LK]jump to K64 0x40080000` ... `el3_exit`, then nothing).

**Why this doesn't clear 6.6:** LK's own dumped cmdline for this boot
includes `printk.disable_uart=1` — a MediaTek 3.18-fork-specific kernel
parameter that deliberately disables the UART console after handoff.
Mainline 6.6 doesn't implement that parameter at all, so it cannot explain
our kernel's silence the same way. **The comparison between vendor silence
and our silence is invalid** — they have different (or at least unproven)
causes. This retracts the earlier working assumption that "silence matches
the known-good baseline, therefore inconclusive-but-not-regressed"; we
never actually had a baseline of *successful* post-`el3_exit` console
output on this hardware to compare against.

**Follow-up analysis:** confirmed our 6.6 build's `CONFIG_CMDLINE_FORCE=y`
correctly overrides LK's injected cmdline (and the DTS `/chosen/bootargs`),
so our own `earlycon=...` is what's in effect, not the vendor one. But the
explicit-address form we were using (`earlycon=uart8250,mmio32,0x11002000`)
always dispatches to the **generic** `early_serial8250_setup`
(`drivers/tty/serial/8250/8250_early.c`), never the **MediaTek-specific**
`early_mtk8250_setup` (`8250_mtk.c`), which is only reachable via
`OF_EARLYCON_DECLARE(mtk8250, "mediatek,mt6577-uart", ...)` — a DT-node
match, not an explicit-address one. Confirmed in
`arch/arm64/boot/dts/mediatek/mt6797.dtsi`: `uart0` (at `0x11002000`) has
`compatible = "mediatek,mt6797-uart", "mediatek,mt6577-uart"`, reachable via
`/aliases/serial0` and `mt6797-gemini-pda.dts`'s `/chosen/stdout-path`. The
generic form may be missing MTK-specific baud/highspeed-divisor register
handling.

**Next variant:** switched `configs/gemini-cmdline.config` to the bare
DT-node form (`CONFIG_CMDLINE="console=ttyS0,921600n1 earlycon"`, no
explicit address), which should resolve via `stdout-path` to `uart0` and
pick up `early_mtk8250_setup`. Rebuilt clean
(`~/build-6.6-mtk-earlycon.log`, "Build complete"). Repackaged at the
LK-honored `kernel_addr=0x40080000`:

- `logs/2026-07-04-07-mtk-earlycon/new_kali_boot.img`
  sha256 `37a64a6d14b05f0f5aa8cbe18cd81647a92750844ae25dd45d12b7d9f19bc166`

**Reminder:** `boot2` currently has the vendor baseline image flashed — must
reflash our 6.6 image before this test, not the vendor one.

---

## MTK earlycon Variant Retested — still identical silence (2026-07-04)

**Test:** flashed `logs/2026-07-04-07-mtk-earlycon/new_kali_boot.img`
(bare DT-node `earlycon`, resolving to `early_mtk8250_setup` via uart0's
compatible string) to `boot2`, captured (log landed in the reused
`2026-07-04-06-vendor-baseline.log` filename by mistake, but confirmed with
the user this capture is of the mtk-earlycon image, not the vendor one).

**Result:** identical silence after `el3_exit`, byte-for-byte the same as
every previous variant.

**Status:** four independent kernel-side variables have now been tested and
falsified without changing the outcome: `CONFIG_CMDLINE_FORCE` (console
naming), `CONFIG_RANDOMIZE_BASE`/`CONFIG_RELOCATABLE` (on and off), boot.img
`kernel_addr` alignment (irrelevant — LK ignores the field), and the
earlycon driver (generic 8250 vs MediaTek-specific). This strongly suggests
the problem is not in kernel config/cmdline at all, but something structural
in the EL3→EL1 handoff or peripheral access permissions that no amount of
kernel-side tuning can work around.

**New hypothesis (untested, needs a different diagnostic approach):**
MediaTek's `DEVAPC` peripheral firewall (`[DEVAPC] sec_post_init` /
`platform_sec_post_init - SMC call to ATF from LK`, visible in every capture
right before the final DRAM/cmdline dump and jump) may restrict UART0 MMIO
access to the secure world only once ATF hands off to a non-secure EL1
kernel. ATF and LK both write UART0 registers directly throughout boot, so
their output says nothing about whether the *next*, non-secure stage retains
access. This is not configurable from Linux or DTS — mainline has no DEVAPC
driver for this SoC, and the permission state is set by the closed vendor
LK/ATF blobs before the jump, not by anything we control.

**Implication:** further guessing at kernel Kconfig/cmdline combinations is
unlikely to help. The needed next step is a diagnostic signal that doesn't
depend on UART access — e.g. confirming the kernel is even executing at all
via some other observable side effect (GPIO/LED toggle, watchdog reset
timing, whether the device becomes unresponsive vs re-enters BROM/fastboot
mode) — before continuing to iterate blind on cmdline variants.

---

## Boot Mode Ruled Out (2026-07-04)

**Test:** with the mtk-earlycon 6.6 image still on `boot2` (unchanged from
the previous entry), powered on with the **power button held** rather than
via USB VBUS insertion. Confirms in the log: `boot_reason=4`,
`androidboot.bootreason=wdt_by_pass_pwk`, `lk boot mode = 0` — a genuine
power-button boot, not MediaTek's USB charger boot mode (`boot mode 8`,
seen in earlier captures) which the vendor Android/Kali userspace treats
specially (charge-only UI, battery icon only — this is what the user was
seeing and is unrelated to the 6.6 bring-up work; see chat, 2026-07-04).

**Result:** identical silence after `el3_exit` regardless. Rules out boot
mode/reason as a variable in the diagnostic chain.

**Still needed:** an actual full vendor-kernel boot capture (vendor
`planet/kali_boot.img` on `boot2`, power button held, capture continued
well past `el3_exit`) has not yet been obtained — every vendor-image test
so far was either deliberately stopped early (B-1) or used USB charge-mode
boot (silent by design, see "Vendor Baseline" entry above). This is the
next action.

---

## Pivotal Result: Silence After el3_exit Is Not a Failure Signal (2026-07-04)

**Test:** flashed unmodified `planet/kali_boot.img` to `boot2`, held the
power button (confirmed real boot: `boot_reason=0`,
`androidboot.bootreason=power_key`, `lk boot mode = 0`), captured with
`scripts/ftdi-monitor.py --log logs/2026-07-04-08-vendor-full-boot.log`.
User confirmed **the device fully booted to the Android desktop UI** —
visually verified, not inferred.

**Result:** the serial capture still ends at the exact same point as every
prior attempt — `[LK]jump to K64 0x40080000` ... `el3_exit`, then **nothing**,
despite the boot being a complete, confirmed success.

**Conclusion — this invalidates the diagnostic method used throughout this
session.** "Silence after `el3_exit`" was being treated as inconclusive
(or, in some entries, suggestive of failure) for our 6.6 kernel builds. It
is neither: it is what *every* boot looks like on this UART, success or
failure alike, vendor or mainline. All of the following conclusions drawn
earlier today are now suspect and should not be trusted for their original
stated reasoning (though the underlying config changes were not harmful):
- "the CONFIG_RELOCATABLE fix should show it progressing past el3_exit" —
  no capture could ever have shown that, regardless of correctness.
- "the earlycon driver mismatch is the next candidate" — still plausible
  in principle, but the negative test result (still silent) carries no
  weight either way.

**Updated root-cause model:** MediaTek's `DEVAPC` peripheral firewall
(`[DEVAPC] sec_post_init` / `platform_sec_post_init - SMC call to ATF from
LK`, present in every capture right before the jump) most likely restricts
UART0 MMIO access to the secure world once ATF exits to a non-secure EL1
kernel — for *any* OS, not just ours. This is consistent with literally
every capture obtained today, including a confirmed-successful vendor boot.
Not configurable from Linux/DTS; the permission state is set by the closed
LK/ATF blobs before the jump.

**Practical implication for B-2:** we cannot use this UART for post-handoff
kernel diagnosis at all. We need a different observable to tell whether our
6.6 kernel is executing:
- **Display/framebuffer**: LK/ATF already initialise the panel and show a
  boot logo before the jump (`videolfb`/`DDP` lines in every capture). If
  our 6.6 kernel probes the display (or even just leaves/clears the
  framebuffer differently on panic vs normal execution vs hang), the panel
  itself becomes a possible signal — worth watching the physical screen
  after the next 6.6 flash rather than relying on serial alone.
  Compare: does the logo freeze (kernel never ran), stay frozen (early
  hang, same as freeze — ambiguous), go blank (kernel touched the display
  hardware), or show DRM garbage/output (kernel display driver probed)?
- Alternative signals to consider if the screen is inconclusive: USB
  re-enumeration behaviour visible from the host Mac, watchdog-triggered
  reboot timing (a hang vs a clean parked state may differ), or eventually
  a JTAG/SWD probe if available.
- The FTDI/UART rig remains valid for everything **before** the kernel
  jump (preloader/LK/ATF) — B-1's console proof stands. It's specifically
  post-jump OS console output that is unusable as a signal on this
  hardware without further investigation (e.g. whether DEVAPC can be
  reconfigured to permit non-secure UART access, which would need
  LK/ATF-side changes, well outside kernel scope).

---

## ROOT CAUSE OF ALL 2026-07-04 SILENT RESULTS: wrong partition booted (2026-07-04)

**Trigger:** after flashing the 6.6 mtk-earlycon image to `boot2` and doing a
power-button boot for the display test, the device **booted normally into
Android** — impossible if LK had loaded our image from `boot2`.

**Verification:** every single capture from today — all the "6.6 tests" and
both vendor baselines — contains the same lines:

```
[756] Loading DTB from partition boot
[760] [PART_LK][get_part] boot
```

LK loaded the **`boot`** partition (stock Android) in every run. **`boot2`
was never booted at any point today.** The Gemini's multi-boot LK selects
the OS by button combination at power-on; plain power-button and
USB-plug boots both select OS 1 (`boot`/Android). Booting `boot2` requires
the alternate combo (the left-end silver button held together with power —
confirm against Planet's multi-boot documentation before relying on the
exact combo).

**Consequences — the following entries above are void, not merely
inconclusive:**
- "First 6.6 Flash", "Cmdline Fix Retested", "Aligned kernel_addr
  Retested", "MTK earlycon Variant Retested", "Boot Mode Ruled Out": none
  of these ever executed our kernel. No hypothesis about our image was
  actually tested. The identical silence in every run is fully explained by
  the *stock Android kernel* honouring LK's `printk.disable_uart=1`.
- The DEVAPC secure-world UART theory ("Pivotal Result" entry) is
  unnecessary and withdrawn — the "confirmed-successful vendor boot with
  silent UART" was the Android kernel muting itself by design.
- The config changes made along the way (`CONFIG_CMDLINE_FORCE` + bare
  `earlycon`, RELOCATABLE back at defaults) are all still present in
  `configs/gemini-cmdline.config` and are reasonable defaults — but none
  has ever been exercised on hardware.

**What still stands:** the FTDI rig (B-1), the packaging tool and its
verified header layout, the flashing workflow, and the LK-side observations
(LK ignores the header `kernel_addr`; LK's injected cmdline; the memory
map). Also newly learned: `mtk w boot2` writes were verified but never
consumed, so nothing today validated (or invalidated) LK's ability to boot
`boot2` at all — even the *vendor* `boot2` image hasn't been proven to boot
this way today.

**Confirmed boot-slot map** (from `planet/Gemini_x25_x27_A30GB_L26GB_Multi_Boot.txt`,
the official scatter, 2026-07-04):
- `boot`  ← `boot.img`      = stock **Android** (default, no key)
- `boot2` ← `kali_boot.img` = **Kali 3.18** (our 6.6 test slot)
- `boot3` ← `boot.img`      = stock **Android again** (selected by the single
  silver side button — confirmed: holding it loads `boot3`, `zimage_size
  0x802d2b` = Android kernel size, which is why "the combo always boots
  Android"). So the silver button is NOT the Kali selector.

`boot2` (Kali) requires a **keyboard-key** boot trigger, not the side button.
Key→slot mapping is held in LK and not recorded in the scatter; probe it
empirically with serial running and check which partition LK reports loading
(`Loading DTB from partition boot2` + `zimage_size:0x8a9661` = success).
This device has only one silver side button (right side).

**Next test (the real first 6.6 attempt):**
1. `boot2` currently holds the 6.6 mtk-earlycon image
   (`logs/2026-07-04-07-mtk-earlycon/new_kali_boot.img`) — already flashed.
2. Start a capture: `python3 scripts/ftdi-monitor.py --log
   logs/2026-07-04-09-first-real-6.6-boot.log`
3. Power on with the **boot2 button combo** (silver + power).
4. The capture must show `Loading DTB from partition boot2` / `[get_part]
   boot2` — that line is now a mandatory check before interpreting any
   result. If it still says `boot`, the combo was wrong; fix that first.
5. Sanity option: first do a combo-boot with the *vendor* image on `boot2`
   to confirm the combo works and to finally capture what a successful
   Kali 3.18 boot looks like on serial (it does NOT set
   printk.disable_uart... to be verified — its cmdline comes from the
   boot.img header: `bootopt=64S3,32N2,64N2 log_buf_len=4M`, plus whatever
   LK injects).

---

## FIRST REAL 6.6 EXECUTION ATTEMPT — LK infinite-loops on our DTB (2026-07-04)

**Approach change:** stopped fighting the `boot2` selector combo. Flashed the
6.6 mtk-earlycon image to the **default `boot` slot** (`mtk w boot
logs/2026-07-04-07-mtk-earlycon/new_kali_boot.img`) so a plain power-on loads
it with no key combo. Full stock reflash (SP Flash Tool, official scatter) was
done first, so all slots were pristine.

**Capture:** `logs/2026-07-04-13-boot-slot-6.6.log` (1.8 MB — first non-trivial
6.6 capture). Power-on, no buttons.

**Result — LK finally loaded OUR kernel, then hung in LK before the jump:**
```
[756] Loading DTB from partition boot
[826] Kernel(1) zimage_size:0xc7fb32,dtb_addr:0x4611223e(dtb_size:0x3b9c)
[3450] target_fdt_cpus: cpu 228 clock-frequency not found   (×54366)
[12287] lk_wdt_dump(): watchdog timeout in LK....
BOOT_REASON: 4   (watchdog reset)
```
- `zimage_size:0xc7fb32` (13.1 MB) = **our 6.6 Image.gz**, not Android's
  `0x802d2b`. Proof LK loaded our image — a genuine first.
- `jump to K64` **never appears.** LK spun **54,366 times** in
  `target_fdt_cpus` ("cpu 228 clock-frequency not found"), its own watchdog
  fired at ~12 s, and the SoC reset (`BOOT_REASON: 4`). Loops forever.

**Root cause:** the vendor LK runs `target_fdt_cpus()` over the DTB `/cpus`
node before jumping and **requires a `clock-frequency` property on every cpu
node**. Mainline `mt6797.dtsi` omits it (Linux derives CPU clocks from
cpufreq/clk nodes). With it missing, LK's fixup loops instead of skipping.
The vendor DTB (`docs/vendor-dtb/gemini_kali_boot.dts`) gives every cpu a
`clock-frequency`, which is why stock images boot.

**Fix (validated on Mac, not yet on hardware):** added `clock-frequency` to
all 10 cpu nodes in `mt6797-gemini-pda.dts` (patch
`patches/v6.6/dts/0001-...`), per-cluster values copied from the vendor DTB:
- cpu0–3 (A53 little): `0x52e8f9c0` (1.391 GHz)
- cpu4–7 (A53 big):    `0x743aa380` (1.95 GHz)
- cpu8–9 (A72):        `0x88601c00` (2.288 GHz)

DTB recompiles cleanly with all patches applied; all 10 props confirmed
present in the compiled blob. **Next:** rebuild Image.gz+DTB in the VM,
repack to `boot`, reflash, recapture — expect LK to reach `jump to K64` and,
for the first time, the possibility of real Linux 6.6 serial output.

**Note on the boot2/combo hunt:** now moot for bring-up. Booting from the
default `boot` slot sidesteps the selector entirely. Restore stock Android
anytime with `mtk w boot planet/boot.img`.

---

## SECOND 6.6 ATTEMPT — CPU loop fixed, LK now panics on missing ATF node (2026-07-04)

**Image:** `logs/2026-07-04-14-cpu-clkfreq/new_boot.img` (cpu clock-frequency
fix), flashed to `boot`. **Capture:** `logs/2026-07-04-15-cpu-clkfreq-boot.log`.

**Result — CPU loop gone, LK gets much further, then panics:**
- `target_fdt_cpus` count: **0** (was 54,366). The clock-frequency fix
  worked — LK cleanly parsed `/cpus`.
- LK progressed through DRAM setup and memory-DTS fixup:
  `[4381] PASS memory DTS node` → `platform_fdt_scp()` →
  `Can not find atf ram dump!` →
  `panic (caller 0x46027661): ASSERT at (app/mt_boot/mt_boot.c:1226): 0`
  → `lk_wdt_dump(): watchdog timeout in LK` → reset (`BOOT_REASON: 4`).
- Still no `jump to K64`.

**Root cause:** before the kernel jump, LK locates the ATF ramdump reserved
region by scanning the DTB for `compatible = "mediatek,mt6797-atf-ramdump-memory"`.
Our board DTS defined the reserved-memory node (`atf-ramdump@44610000`) but
**dropped the `compatible` string**, so LK's search failed → "Can not find
atf ram dump!" → hard ASSERT at `mt_boot.c:1226`. The vendor DTB
(`docs/vendor-dtb/gemini_kali_boot.dts:390`) carries the compatible.

**Fix (validated on Mac):** restored the vendor `compatible` strings on the
ATF/cache reserved-memory nodes in `mt6797-gemini-pda.dts` (patch 0001):
`mediatek,mt6797-atf-reserved-memory`, `mediatek,mt6797-atf-ramdump-memory`,
`mediatek,cache-dump-memory`. Node names realigned to the vendor form too.
DTB recompiles cleanly; all three compatibles confirmed present.

**Lesson:** the Gemini's LK does a series of DTB fixups that hard-depend on
vendor node shapes (cpu `clock-frequency`, ATF reserved-memory compatibles).
Each missing piece is a separate LK panic before handoff. We are peeling
these off one boot at a time. Rebuilt image:
`logs/2026-07-04-16-atf-compat/new_boot.img` (sha256 9ab4ce2b…).

---

## THIRD 6.6 ATTEMPT — ATF fixed, LK now panics in platform_fdt_scp() (2026-07-04)

Flashed `logs/2026-07-04-16-atf-compat/new_boot.img` to `boot`; captured
`logs/2026-07-04-17-atf-compat-boot.log`.

**Result:** the ATF fix worked — `Can not find atf ram dump!` is gone (0
occurrences), and LK advanced past the ATF ramdump fixup. The CPU
`clock-frequency` loop stayed fixed (no `target_fdt_cpus` spam). Our kernel
still loads (`zimage_size:0xc7fc76`). LK now progresses to:

```
[4168] PASS memory DTS node
[4168] platform_fdt_scp()
[4170] panic (caller 0x46027661): ASSERT at (app/mt_boot/mt_boot.c:1226): 0
```

followed by `aee_wdt_dump` and watchdog reset (reboot loop).

**Root cause:** LK's `platform_fdt_scp()` searches the DTB for the SCP shared
memory reserved-memory node by compatible `mediatek,reserve-memory-scp_share`
before handoff. Our DTS omitted it (it was one of the "dynamic size/alignment"
vendor entries we had deliberately dropped as unclaimed by 6.6 drivers). Absent
node → assert → same panic line as ATF, different caller.

**Fix:** added the `scp-share` node to `mt6797-gemini-pda.dts`, verbatim from
the vendor DTB (compatible `mediatek,reserve-memory-scp_share`, dynamic
`size = 0x1000000`, `alignment = 0x1000000`, `alloc-ranges` in the
0x40000000–0x90000000 window). Patch 0001 regenerated. Rebuilt image:
`logs/2026-07-04-18-scp-share/new_boot.img`
(sha256 ee0167294c0caab95295feed4932b715063e3db679d752fcf45056000b930824,
kernel blob 13106465 = Image.gz 13090710 + dtb 15755). Pending hardware test.

---

## FOURTH 6.6 ATTEMPT — scp_share node NOT enough; LK needs the scp *device* node (2026-07-04)

Flashed `logs/2026-07-04-18-scp-share/new_boot.img`; captured
`logs/2026-07-04-19-scp-share-boot.log`. **Identical panic** at
`platform_fdt_scp()` → mt_boot.c:1226, same caller `0x46027661`. Adding the
`mediatek,reserve-memory-scp_share` reserved-memory node had **zero effect** —
the assert fires before that node is consulted.

**Correct root cause (found by diffing against the stock boot):** on a stock
boot the line immediately after `platform_fdt_scp()` is `status=okay`. LK looks
up the SCP **device** node by compatible `mediatek,scp` and patches its
`status`. Mainline `mt6797.dtsi` has **no scp node at all** (only `scpsys`, the
power-domain controller — a different block). Node absent → assert.

**Fix:** added a root-level `scp@10020000` device node, compatible
`mediatek,scp`, reg/interrupts verbatim from the vendor DTB
(`docs/vendor-dtb/gemini_kali_boot.dts:3119`), `status = "disabled"` (no 6.6
driver drives it; the node exists purely for the LK fixup). Patch 0001
regenerated. Rebuilt image: `logs/2026-07-04-20-scp-node/new_boot.img`
(sha256 ee857030a4628992dced0f568ef658b1f8acac0cd59d5a33c5d2321817361355,
kernel blob 13106628 = Image.gz 13090713 + dtb 15915). Pending hardware test.
(The scp_share reserved-memory node from attempt 3 is kept — harmless and
likely also consulted once LK gets past the device-node lookup.)

**Running tally of LK pre-jump DTB dependencies peeled off:** (1) cpu
`clock-frequency` ×10 → infinite loop; (2) `mediatek,mt6797-atf-ramdump-memory`
→ mt_boot.c:1226 panic; (3) `mediatek,scp` device node → mt_boot.c:1226 panic in
platform_fdt_scp(). Next checkpoint remains the first `jump to K64`.

---

## FIFTH 6.6 ATTEMPT — FIRST jump to K64: Linux 6.6 RUNS, hangs at SMP secondary bringup (2026-07-04)

**MILESTONE.** The `mediatek,scp` device node fix worked. LK's
`platform_fdt_scp()` printed `status=okay`, then
`[LK]jump to K64 0x40080000` — the first-ever handoff to our kernel — and
Linux 6.6 executed. Raw log: `logs/2026-07-04-21-scp-node-boot.log`.
Image: `logs/2026-07-04-20-scp-node/new_boot.img`
(sha256 ee857030a4628992dced0f568ef658b1f8acac0cd59d5a33c5d2321817361355).

What Linux printed over earlycon mtk8250 @ 0x11002000 (921600n8):
- `Booting Linux on physical CPU 0x0000000000 [0x410fd034]`
- `Linux version 6.6.0-dirty ... #10 SMP PREEMPT Sat Jul 4 ...`
- `Machine model: MT6797X`
- All reserved-memory nodes parsed cleanly (scp-share, atf-*, mblock-*).
- `earlycon: mtk8250 at MMIO32 0x0000000011002000` — the MTK-specific
  earlycon attached (validates the bare-`earlycon`/DT-node approach in
  configs/gemini-cmdline.config).
- PSCI v0.2 detected, GICv3 (352 SPIs), arch timer 13 MHz, memory 3738 MB.
- Reached `smp: Bringing up secondary CPUs ...` at `[0.016897]`.

**Failure:** kernel HANGS on CPU1 bringup. Kernel timestamps stop dead at
`[0.016897]`; ~14s later ATF's `aee_wdt_dump: on cpu1` /
`Kernel WDT not ready. cpu1` fires and the hardware watchdog resets the SoC
→ preloader restarts → reboot loop (the on-screen colour flashing is the
framebuffer re-initialising each loop). So this is a genuine early hang in
secondary-CPU PSCI bringup, not merely a watchdog timeout.

**Confirmed:** LK overrides the DT `/chosen` bootargs. Printed
`Kernel command line: console=ttyS0,921600n1 earlycon` = our
`CONFIG_CMDLINE` (CMDLINE_FORCE), NOT the DTS `bootargs`
(`earlycon console=ttyS0,921600n8`). Kernel-side config is the only reliable
place to set boot args.

## SIXTH 6.6 ATTEMPT — single-core boot to clear the SMP hang (2026-07-04)

Added `maxcpus=1` to `CONFIG_CMDLINE` (configs/gemini-cmdline.config) to boot
CPU0 only and get past the CPU1 PSCI stall — bootability first (CLAUDE.md
principle 5); SMP bring-up is a separate problem to fix on a stable single-CPU
base. Rebuilt in VM (#? build, GCC 14.2).
Image: `logs/2026-07-04-22-maxcpus1/new_boot.img`
(sha256 6ec9ada83a8f94c2f575959aac75cacab0b64244bf2cf614415c23e97556e200,
kernel blob 13108601 = Image.gz 13092686 + dtb 15915). Pending hardware test:
expect the kernel to sail past `smp: Bringing up secondary CPUs` and proceed
into device/driver init — where the next stall (likely the un-petted MTK
watchdog, or a missing clock/regulator) will appear.

## SIXTH RESULT + SEVENTH ATTEMPT — single-core boots through ALL driver init; hangs at "Disabling unused clocks" (2026-07-04)

`maxcpus=1` worked. Raw log: `logs/2026-07-04-23-maxcpus1-boot.log`
(image `logs/2026-07-04-22-maxcpus1/new_boot.img`,
sha256 6ec9ada83a8f94c2f575959aac75cacab0b64244bf2cf614415c23e97556e200).
- `smp: Brought up 1 node, 1 CPU` — past the CPU1 PSCI hang.
- Full driver init ran: real console handed off from earlycon to `ttyS0`
  (`11002000.serial ... is a ST16650V2`); **mtk-wdt driver took over the
  hardware watchdog** (`10007000.watchdog: Watchdog enabled (timeout=31 sec,
  nowayout=0)`) — so the reset is now the kernel's own un-petted watchdog, not
  ATF's aee.
- Non-fatal: `mtk-scpsys: probe of 10006000.power-controller failed with
  error -22` (EINVAL) — power-domain controller; revisit later.

**Failure:** kernel goes SILENT at exactly `[0.475319] clk: Disabling unused
clocks`. No `Freeing unused kernel memory`, no root mount, no panic. ~31s
later the un-petted mtk-wdt fires → preloader loop (RTC jumps 0:44→0:45 in the
log). Textbook incomplete-clock-tree hang: mainline mt6797 clk driver gates a
clock the hardware silently needs because nothing in our DT claims it.

**SEVENTH attempt:** added `clk_ignore_unused` to `CONFIG_CMDLINE` to keep all
clocks on and get past this into userspace. Image:
`logs/2026-07-04-24-clk-ignore/new_boot.img`
(sha256 8dcfe7d85385ba2881a3454ef11b65890ab6d4600a8c25e5bdda337aa3950acb,
kernel blob 13108512 = Image.gz 13092597 + dtb 15915). Pending hardware test:
expect boot to proceed past clk-disable to `Freeing unused kernel memory` and
the root-mount / `Run /init` stage — where the rootfs-compat question
(3.18 Kali userspace vs 6.6, see CLAUDE.md Open Questions) becomes live.

---

## SEVENTH RESULT — MILESTONE: first full Linux 6.6 boot to userspace; panics in switch_root (no eMMC node) (2026-07-04)

**`clk_ignore_unused` cleared the clock hang.** Raw log:
`logs/2026-07-04-25-clk-ignore-boot.log` (image
`logs/2026-07-04-24-clk-ignore/new_boot.img`, sha256
8dcfe7d85385ba2881a3454ef11b65890ab6d4600a8c25e5bdda337aa3950acb). This is
the first time a Linux 6.6 kernel has run end-to-end on the Gemini PDA:

- `[0.475709] clk: Not disabling unused clocks` — hang cleared.
- `[0.478451] Freeing unused kernel memory: 2624K`
- `[0.484556] Run /init as init process` — **userspace reached.**
- init's script runs (`+ exec`), then:
  ```
  [2.638712] /dev/mmcblk0p29: Can't lookup blockdev   (x3)
  [2.708462] Kernel panic - not syncing: Attempted to kill init! exitcode=0x00000100
  ```
  CPU0 PID1 `switch_root`. ~33s later (no watchdog pet after panic) ATF's
  `aee_wdt_dump: on cpu0` / `Kernel WDT not ready` fires and the SoC resets →
  preloader loop. This is the *userspace* panic, not a kernel bug — the
  kernel itself is stable to this point.

**Root cause:** grepped both `mt6797.dtsi` (mainline) and our
`mt6797-gemini-pda.dts` — **no MMC/eMMC/SDHCI controller node exists
anywhere in the device tree.** Confirmed no `mtk-msdc`/`sdhci-pltfm` probe
ever occurs in the log (only the `sdhci`/`sdhci-pltfm` *driver framework*
registers, no device binds to it) and no `mmcblk0` device node is ever
created. init's script (from the 2019 Kali `linux.img` ramdisk) unconditionally
tries `switch_root` onto `/dev/mmcblk0p29` (the Kali rootfs partition on
eMMC), which cannot exist without an eMMC controller node — hence the panic.

**This is the storage-enablement problem (Phase 4 / B-7), not a Phase 3
blocker.** Phase 3's goal (bootable kernel with diagnostic serial output) is
now met. Adding an MT6797 MSDC/eMMC device-tree node (mainline has an
`mtk-sd` driver, `drivers/mmc/host/mtk-sd.c`, that supports MT6797-family
SoCs) is the next concrete step, together with settling B-7 (rootfs choice:
reuse 2019 Kali userspace vs. fresh debootstrap/mmdebstrap image).

## EIGHTH RESULT — MILESTONE: clean boot to interactive shell, MSDC/eMMC deferred (2026-07-04)

Following the SEVENTH RESULT panic (init's `switch_root` onto
`/dev/mmcblk0p29` failing with no eMMC controller node), three MSDC0
bring-up attempts were made and are recorded in blockers.md B-7:
bare-compatible node → added required `state_uhs` pinctrl state → added
`assigned-clocks`/`assigned-clock-parents` (no effect, ruled out the
CKSTB-clock-wait theory). All three hung silently post-probe; root cause
undetermined.

**Decision:** defer MSDC/eMMC entirely rather than block Phase 4's first
milestone on it (CLAUDE.md principle 5, bootability first; the Gemini also
has a removable SD card as a future alternate path). Changes:
- `mt6797-gemini-pda.dts`: `msdc0` node set `status = "disabled"` (left in
  place, DTS comment points back to blockers.md B-7 for whoever resumes it).
- `configs/gemini-cmdline.config`: added `rdinit=/bin/sh` to skip the vendor
  2019 Kali ramdisk's `/init` script (which unconditionally does
  `switch_root`) and exec a shell directly from the initramfs instead. Also
  added `nokaslr` (diagnostic aid for the next MSDC attempt — without it,
  the ATF watchdog dump's PC/LR can't be symbolicated against `System.map`
  since KASLR's runtime slide doesn't match the static vmlinux addresses).

**Result** (`logs/2026-07-04-33-defer-msdc-rdinit-sh-boot.log`, image
`logs/2026-07-04-32-defer-msdc-rdinit-sh/new_boot.img`, sha256
`f05225d5fe21728a45b2bf43055973ccb43d373f54c48b1440117476748a8b97`):

```
[    0.485391] Freeing unused kernel memory: 2624K
[    0.485391] Run /bin/sh as init process
/bin/sh: can't access tty; job control turned off
~ # [6n[   10.734210] platform lcd-avee-regulator: deferred probe pending
```

**First interactive userspace shell on this port.** The `[6n` is a terminal
device-attributes query the shell's prompt-drawing sent to the (nonexistent,
since this is a raw serial capture, not a real terminal) TTY — harmless.
`job control turned off` is expected: `rdinit=/bin/sh` runs the shell as PID
1 directly with no controlling tty setup, not a bug.

The subsequent `lcd-avee-regulator: deferred probe pending` line is a
display-power-rail driver waiting on a dependency — expected, since Phase 5
(display) has not started and no panel/backlight driver work has been done
yet. **No output on the physical display is expected at this stage** and is
not itself a new finding.

**Phase 4 status:** first half of the milestone (kernel boot to live
userspace, independent of storage) is met. eMMC/switch_root remains open
per B-7 and is the next concrete piece of Phase 4 to resume.

---

## NINTH RESULT — Phase 5 first display pipeline test: scpsys probe failure blocks DRM bind, LK splash misattributed (2026-07-05)

First hardware test of the display pipeline documented as code-complete in
driver_ports.md since 2026-06-10 (MMSYS/DDP, MT6797 DSI variant, MIPITX PHY,
R63419 panel driver). Enabled the whole chain in the board DTS: `disp_ovl0`,
`disp_rdma0`, `disp_color0`, `disp_ccorr0`, `disp_aal0`, `disp_gamma0`,
`disp_od0`, `disp_dither0`, `mutex`, `dsi0` (+ panel node), `mipi_tx0`, all
`status = "okay"`. Added `configs/gemini-display.config` forcing
`CONFIG_DRM=y`, `CONFIG_DRM_KMS_HELPER=y`, `CONFIG_MTK_MMSYS=y`,
`CONFIG_MTK_CMDQ=y`, `CONFIG_MTK_CMDQ_MBOX=y`, `CONFIG_DRM_MEDIATEK=y`,
`CONFIG_PHY_MTK_MIPI_DSI=y`, `CONFIG_DRM_PANEL_RENESAS_R63419=y`,
`CONFIG_BACKLIGHT_CLASS_DEVICE=y` — all previously `=m` or unset in
defconfig, which matters because the `rdinit=/bin/sh` initramfs (B-7 / Phase
4) has no modprobe path, so anything not built-in would never load.

Two build-time issues fixed along the way (not hardware issues):
- `CONFIG_MTK_MMSYS`/`CONFIG_DRM_MEDIATEK` silently reverted to `=m` after
  `olddefconfig` because `MTK_MMSYS` transitively depends on
  `MTK_CMDQ || MTK_CMDQ=n` and `MTK_CMDQ` defaulted to `=m` — a `y` symbol
  cannot depend on an `=m` one. Fixed by also forcing `CONFIG_MTK_CMDQ=y` /
  `CONFIG_MTK_CMDQ_MBOX=y`.
- Link failure `undefined reference to devm_of_find_backlight` in
  `panel-renesas-r63419.o` — `CONFIG_BACKLIGHT_CLASS_DEVICE` was `=m` while
  the panel driver (now built-in) needs it built-in too. Fixed by forcing it
  `=y`.
- Initial board-DTS edit enabled the `disp_*`/`dsi0` nodes but missed
  `mipi_tx0` (still `status = "disabled"`, leftover from the pre-Phase-5
  placeholder) — caught by decompiling the built DTB with `dtc -I dtb -O
  dts` and grepping every node for `status`, not by assumption. Fixed and
  rebuilt.

**Result** (`logs/2026-07-05-02-phase5-display-boot.log`, image
`logs/2026-07-05-01-phase5-display/new_boot.img`, sha256
`3e48c7ed9b8ee5f970772cc06417b0bf0b71d66e9cc1f5d86a953e97ecbc3724`):

Kernel booted cleanly to the `/bin/sh` shell exactly as in the EIGHTH
RESULT milestone — **no regression, no hang**. However the display driver
chain did not bind:

```
[    0.283996] mediatek-mipi-tx 10215000.mipi-dphy: can't get nvmem_cell_get, ignore it
[    0.313933] mtk-mmsys 14000000.syscon: error -2 can't parse gce-client-reg property (0)
[    0.320092] get() with no identifier
[    0.320587] mtk-scpsys: probe of 10006000.power-controller failed with error -22
...
[    0.370139] mediatek-drm mediatek-drm.1.auto: Failed to find disp-mutex node
...
[   10.738979] platform lcd-avee-regulator: deferred probe pending
[   10.739758] platform lcd-avdd-regulator: deferred probe pending
[   10.740509] platform 1401c000.dsi: deferred probe pending
```

Root-caused to a genuine upstream Linux 6.6 bug, not a Gemini DTS mistake —
full analysis in blockers.md **B-13**. Short version: `mtk-scpsys.c`'s MT6797
domain table has 5 unpopulated (zero-initialized) slots for GPU domains
(`MFG`, `MFG_CORE0-3`); the probe loop iterates all of them unconditionally
and calls `devm_regulator_get_optional()` with a NULL supply name for the
gaps, which the regulator core treats as fatal (`-EINVAL`), aborting the
*entire* scpsys device — including the `MM` domain that every display
component depends on.

**A splash screen was visible on the physical display during this boot**,
but confirmed (asked the user directly, timing was "appeared early, static
throughout") to be the vendor LK bootloader's own `logo`-partition splash,
rendered before Linux even starts — **not** evidence of our kernel DRM/panel
code working. This is an important distinction: the screen lighting up at
all during a test session is easy to mistake for progress, but LK has
always rendered this splash regardless of what the Linux side does; it is
static and unrelated to the `dsi0`/panel patches under test.

**Phase 5 status:** DTS wiring, build config and patch set are all
confirmed correct (no DT or compile-time errors); the remaining blocker is
purely the upstream scpsys driver bug (B-13). Next step is patching
`mtk-scpsys.c`'s `init_scp()` to skip domain-table slots with `data->name ==
NULL` (recommended: lowest-risk, doesn't touch GPU register state, doesn't
require unverified MFG SPM offsets) rather than sourcing real MFG domain
register values, per B-13's fix-path discussion.

---

## TENTH RESULT — msdc0 re-enable attempt: silent 0.52s hang traced to mm-clk driver (B-13), not MSDC; display fragment disabled for Phase 4 (2026-07-05)

**Build:** `logs/2026-07-05-22-msdc0-hclk-fix/` (`new_kali_boot.img` sha256
`50e52d3c…650e`, `.config` + `System.map` alongside). Flashed with
`mtk.py w boot2`. **Capture:** `logs/2026-07-05-23-msdc0-hclk-fix-boot.log`
(monitor ran for several minutes).

Changes under test:
1. **msdc0 hclk DTS bug fixed** — `hclk` had been wired to
   `CLK_TOP_MUX_MSDC50_0` (the *source* mux) instead of
   `CLK_TOP_MUX_MSDC50_0_HCLK`; corrected, node set `status = "okay"`
   (patch `dts/0001` regenerated).
2. **mtk-sd.c instrumented** (`patches/v6.6/mmc/0001-mmc-mtk-sd-gemini-debug-instrumentation.patch`):
   probe-stage markers, clock rates at ungate, and the *infinite*
   CKSTB `readl_poll_timeout(…, 0, 0)` in `msdc_set_mclk()` bounded to 1s.
3. Prior conclusion invalidated: the "identical hang PC" from the 07-04
   ATF `aee_wdt_dump` is **garbage** — kallsyms recovered from the exact
   failing `Image.gz` (vmlinux-to-elf) shows the dumped PC lands past
   `_etext`, in rodata, and the dump itself says "Kernel WDT not ready".
   The CKSTB infinite-poll theory is back in play, untested.

**Result: the MSDC test never ran.** The log ends abruptly at
`[0.515614] mtk-dsi … engine clk get failed: -517` — byte-for-byte the
same final line and timestamp as `2026-07-05-21-mmsys-fix-boot.log`. A
minutes-long capture with no further output (and no ATF watchdog dump)
proves the earlier "captures end at 0.5s" observations were not
early-stopped captures: **every build with
`CONFIG_COMMON_CLK_MT6797_MMSYS=y` hard-hangs silently at ~0.52s**, right
where the mm clk driver registers MM-domain clocks. This is B-13's
signature — with the scpsys MT6797 domain table broken, the `MM` power
domain is unmanaged, and the first MM-domain register access wedges the
bus (no printk, no WDT rescue). It also answers the parked Phase 5
question: the mmsys clk config fix cannot be evaluated until B-13 is
fixed, because adding the mm clk driver introduces this hang.

No `GEMINI-DEBUG` msdc lines, no `11230000.mmc` output at all — msdc0
probe was never reached, so the hclk fix and instrumentation remain
untested.

**Action:** `configs/gemini-display.config` renamed to
`gemini-display.config.disabled-b13` (build.sh merges `*.config` only), so
Phase 4 headless builds exclude the entire display stack. Rebuilt:
`logs/2026-07-05-24-msdc0-headless/new_kali_boot.img` (sha256
`20e91db21afcd26d76c0d8c2d7c6f409a1b96199d3af4b41e94744bc35aedb3e`),
`MMC_MTK=y`, mm-clk configs off, DRM back to =m (inert under
`rdinit=/bin/sh`). Awaiting flash + capture.

---

## ELEVENTH RESULT — stale-slot detour resolved; headless build boots, MSDC probes, then MSDC IRQ storm hangs CPU0 until HW watchdog (2026-07-05)

**Detour first (logs -25/-26):** captures `2026-07-05-25` and `-26` again
showed the old `#29` kernel banner and the same 0.5158s mm-clk hang, despite a
verified-good flash of the `-24` headless image to boot2 (readback sha256
matched). Readback of the **boot** partition
(`/tmp/boot-readback.img`, sha256 `6108e1d2…f2653e`) proved it contained the
stale `#29` test kernel — plain power-on boots the `boot` slot, so the recent
boot2 flashes were never actually tested. Resolution: the headless image was
also flashed to `boot` (targeted `mtk w boot …`, no GPT touch; stock Android
boot.img remains available in `Gemini_x25_x27_06052019/` and in the readback).
Lesson: **always check the `Linux version` banner build number against the
provenance dir before trusting a capture.**

**Real result (log `2026-07-05-27-msdc0-headless-boot.log`, kernel `#32`
from `logs/2026-07-05-24-msdc0-headless/`):**

- Correct kernel booted (`#32 SMP PREEMPT Sun Jul 5 03:15:17 UTC 2026`).
- The mm-clk 0.52s hang is gone — confirms TENTH RESULT's B-13 attribution.
- msdc0 probed for the first time:
  `GEMINI-DEBUG: ungate: src=191999939Hz hclk=273000000Hz MSDC_CFG=02200199`,
  `msdc_init_hw done` at 0.435s. The hclk fix works (hclk now 273 MHz).
  Known pinctrl group-122 config failure still present (non-fatal).
- Then a **silent hang at ~0.437s** (last line `ledtrig-cpu`). At 36s the
  hardware watchdog fired and ATF dumped real CPU0 state:
  `pc:<ffff8000801048e4>` = inside `__irq_resolve_mapping` (System.map `#32`),
  `x20 = 0x6f` = hwirq 111 = **GIC SPI 79 + 32 = msdc0's interrupt**.
  Diagnosis: level-high MSDC IRQ storm. `msdc_irq()` always returns
  `IRQ_HANDLED`, so the generic spurious-IRQ detector never trips; with
  `maxcpus=1` the storm starves printk forever — hence silence.

**Action:** added a storm guard to
`patches/v6.6/mmc/0001-mmc-mtk-sd-gemini-debug-instrumentation.patch`: after
100k handler entries it masks MSDC_INTEN, clears MSDC_INT, disables the irq
line and dev_err's the raw `MSDC_INT/MSDC_INTEN/MSDC_PS` values, so the next
boot survives and names the stuck status bit. Rebuilt headless:
`logs/2026-07-05-28-msdc0-irqstorm-guard/new_kali_boot.img` (kernel `#33
04:05:05 UTC`, sha256
`7323aba227cb339d0a5386706cbfb587a71167a7b512221271ef0013a7d03789`), with
`.config` + `System.map` alongside. Flash to **both** `boot` and `boot2`.
Awaiting capture (`logs/2026-07-05-29-msdc0-irqstorm-guard-boot.log`).

---

## TWELFTH RESULT — storm guard fires, first shell prompt over serial; storm root cause = wrong IRQ polarity in DTS (2026-07-05)

**Raw log:** `logs/2026-07-05-29-msdc0-irqstorm-guard-boot.log`
**Flashed:** `logs/2026-07-05-28-msdc0-irqstorm-guard/new_kali_boot.img` (`#33`) to both `boot` and `boot2`.

**Observations:**
- Correct banner (`#33 ... 04:05:05 UTC`). msdc0 probe markers all present
  (hclk 273 MHz, `msdc_init_hw done` at 0.449s).
- At 0.690s the storm guard fired:
  `IRQ storm (100000 hits): MSDC_INT=00000000 MSDC_INTEN=00000000
  MSDC_PS=81ff0002 -- irq disabled`.
- With the line disabled, boot **completed for the first time**:
  `Run /bin/sh as init process` and a live `~ #` prompt on serial.
  MMC requests then time out every ~5s (`msdc_request_timeout`, CMD52/0/8/5/55/1)
  because the controller now has no working interrupt.

**Diagnosis — the register dump exonerates the MSDC event logic:**
`MSDC_INT=0` and `MSDC_INTEN=0` while the line storms means the assertion is
not coming from the controller's interrupt-status machinery at all — it's a
polarity problem. The vendor DTB (`docs/vendor-dtb/gemini_kali_boot.dts`,
msdc0 node) declares `interrupts = <0 0x4f 0x08>` = SPI 79 **IRQ_TYPE_LEVEL_LOW**
(MT6797 routes peripheral IRQs through the `sysirq` intpol inverter). Our DTS
said `IRQ_TYPE_LEVEL_HIGH`, so the idle (de-asserted) line level was read as
permanently asserted — an unconditional storm the instant the IRQ was enabled,
independent of any MSDC register state. `MSDC_PS=81ff0002` (WP + CMD + all DAT
lines high, CDSTS set) is consistent with an idle bus. This also likely
retires the mt6795-register-layout-mismatch hypothesis as the storm cause.

**Action:** changed msdc0 `interrupts` to `IRQ_TYPE_LEVEL_LOW` in
`mt6797-gemini-pda.dts` (vendor-sourced), regenerated
`patches/v6.6/dts/0001-arm64-dts-mediatek-add-gemini-pda-board.patch`
(checked: patches 0006–0008 only touch `mt6797.dtsi`, so no layering
conflict; SPI 199 on the disabled scp stub is level-high in the vendor DTB
too, so unchanged). Rebuilt headless:
`logs/2026-07-05-30-msdc0-irq-levellow/new_kali_boot.img` (kernel `#34
04:13:39 UTC`, sha256
`cafa7d7b3ba3ab206a54dc2044aa130598f88fc26200334faad60707602e1f0f`),
`.config` + `System.map` alongside; built DTB verified to contain
`interrupts = <0x00 0x4f 0x08>`, storm guard still in (as a tripwire — it
should now stay silent). Flash to **both** slots:

```bash
/tmp/mtk-venv/bin/python3 ~/mtkclient/mtk.py w boot  logs/2026-07-05-30-msdc0-irq-levellow/new_kali_boot.img
/tmp/mtk-venv/bin/python3 ~/mtkclient/mtk.py w boot2 logs/2026-07-05-30-msdc0-irq-levellow/new_kali_boot.img
```

Expected next capture (`logs/2026-07-05-31-msdc0-irq-levellow-boot.log`):
banner `#34`, no storm-guard message, `mmc0: new ... eMMC` card enumeration
and `mmcblk0` partitions.

---

## THIRTEENTH RESULT — polarity fix verified, storm gone; card init now fails on empty OCR (no vmmc-supply) (2026-07-05)

**Log:** `logs/2026-07-05-31-msdc0-irq-levellow-boot.log`
**Kernel:** `#34 SMP PREEMPT Sun Jul 5 04:13:39 UTC 2026` (build dir
`logs/2026-07-05-30-msdc0-irq-levellow/`, flashed to both `boot` and `boot2`
after one aborted attempt caused by a relative path run from inside `logs/` —
DAXFlash "Filename doesn't exists"; no write occurred, no corruption).

**Observed:**

- Storm-guard tripwire **silent** — the LEVEL_LOW polarity fix is confirmed.
  `msdc_init_hw done` at 0.447s, `mmc_add_host returned 0` at 0.477s, no
  `IRQ storm` line anywhere in the capture.
- Boot completes to shell again (`Run /bin/sh as init process`, `~ #`).
- New failure, repeating every retry:
  `mtk-msdc 11230000.mmc: no support for card's volts` followed by
  `mmc0: error -22 whilst initialising MMC card`.

**Diagnosis:** the card responds now (we got far enough to compare OCRs — an
interrupt-level win), but the host advertises an empty voltage window. Our
msdc0 node had no `vmmc-supply`/`vqmmc-supply`; with no regulator and no
fallback, `ocr_avail` is empty, so `mmc_select_voltage()` fails with -EINVAL.
The vendor DTB has no regulator properties either — the 3.18 vendor driver
drove the MT6351 PMIC rails from hardcoded platform code, an interface the
upstream driver doesn't have.

**Fix (build `#35`):** fixed always-on regulators in the board DTS, honest
because LK boots from this eMMC so both rails are provably up at handoff:

- `vemc_fixed` 3.0 V (PMIC MT6351 VEMC) → `vmmc-supply`
- existing `vdd_fixed_1v8` stub (PMIC VIO18) → `vqmmc-supply`

Patch `dts/0001` regenerated; built DTB verified to contain both
`*-supply` properties.

**Build:** `logs/2026-07-05-32-msdc0-vmmc-supply/new_kali_boot.img`, kernel
`#35 SMP PREEMPT Sun Jul 5 04:21:10 UTC 2026`, sha256
`c016f1dba0ebba43404a4a167d337caca3f10b25b104825ecbe1e89a812a43c5`, `.config`
+ `System.map` alongside; storm guard still present as tripwire. Flash to
**both** slots (absolute paths):

```bash
/tmp/mtk-venv/bin/python3 ~/mtkclient/mtk.py w boot  /Volumes/extdata/github/gemini_linux/logs/2026-07-05-32-msdc0-vmmc-supply/new_kali_boot.img
/tmp/mtk-venv/bin/python3 ~/mtkclient/mtk.py w boot2 /Volumes/extdata/github/gemini_linux/logs/2026-07-05-32-msdc0-vmmc-supply/new_kali_boot.img
```

Expected next capture (`logs/2026-07-05-33-msdc0-vmmc-supply-boot.log`):
banner `#35`, no volts error, `mmc0: new ... eMMC` and `mmcblk0` partitions
(which would clear B-7).

---

## FOURTEENTH RESULT — vmmc fix verified; CRC -84 traced to wrong compat data (mt6795 vs MT6797 register layout) + unsupported pinconf (2026-07-05)

**Log:** `logs/2026-07-05-33-msdc0-vmmc-supply-boot.log`
**Kernel:** `#35 SMP PREEMPT Sun Jul 5 04:21:10 UTC 2026`
(`logs/2026-07-05-32-msdc0-vmmc-supply/`, flashed to both slots).

**Observed:**

- The `no support for card's volts` / -22 error is **gone** — the
  vmmc/vqmmc fixed-regulator fix is confirmed.
- New failure: `mmc0: error -84 whilst initialising MMC card` (EILSEQ =
  CRC error), 4 retries then the MMC core gives up. Boot still reaches the
  serial shell.
- Pinctrl noise around each retry:
  `pin_config_group_set op failed for group 122` during the *default*
  state apply at probe, then
  `pin GPIO125 already requested by ; cannot claim for 11230000.mmc` on
  every subsequent state switch.

**Diagnosis (two independent defects):**

1. **Wrong MSDC compat data.** The vendor MT6797 `msdc_reg.h`
   (lukefor/gemini-linux-kernel-3.18,
   `drivers/mmc/host/mediatek/mt6797/msdc_reg.h`) defines
   `MSDC_PAD_TUNE0 = 0xf0` (nothing at 0xec) and
   `MSDC_CFG_CKDIV = 0xfff << 8` (**12-bit** divider). Our
   `mediatek,mt6795-mmc` substitution selects `mt6795_compat` with
   `clk_div_bits = 8` and `pad_tune_reg = 0xec`: the driver wrote the
   clock-mode bits (CKMOD, bits 16–17 in the 8-bit layout) into the middle
   of the real 12-bit CKDIV field (bits 8–19), producing a wrong card
   clock and CRC on every command — exactly the failure mode the original
   substitution comment predicted. `mt2701_compat` matches the vendor
   layout (`clk_div_bits = 12`, `pad_tune_reg = PAD_TUNE0`, async_fifo,
   data_tune). **Fix: `compatible = "mediatek,mt2701-mmc"`.**
2. **Unsupported pinconf.** Upstream `pinctrl-mt6797.c` implements only
   mode/dir/di/do field ranges — no bias or input-enable. Every pinconf
   property in our msdc0 pin groups failed, reverting the whole state
   apply (leaking the GPIO125 claim, hence "already requested by ;").
   **Fix: pinmux-only pin groups**; pad bias stays as the bootloader
   configured it (known-good — LK boots from this eMMC).

**Build `#37`** (first produced via the new `scripts/build-pack.sh`):
`logs/2026-07-05-34-msdc0-mt2701-compat/new_kali_boot.img`, sha256
`3d964c61dbd22c99432c9f0600351b0bf6a06edbc27df6f842e0837b8c1b244a`,
banner `#37 SMP PREEMPT Sun Jul 5 04:33:25 UTC 2026`; DTB verified to
contain `mediatek,mt2701-mmc`. Flash to **both** slots:

```bash
/tmp/mtk-venv/bin/python3 ~/mtkclient/mtk.py w boot  /Volumes/extdata/github/gemini_linux/logs/2026-07-05-34-msdc0-mt2701-compat/new_kali_boot.img
/tmp/mtk-venv/bin/python3 ~/mtkclient/mtk.py w boot2 /Volumes/extdata/github/gemini_linux/logs/2026-07-05-34-msdc0-mt2701-compat/new_kali_boot.img
```

Expected next capture (`logs/2026-07-05-35-msdc0-mt2701-compat-boot.log`):
banner `#37`, no -84/CRC errors, no group-122/GPIO125 pinctrl errors,
`mmc0: new ... MMC card` + `mmcblk0` partitions (clears B-7).

---

## Future Entries

Boot logs from kernel bring-up attempts will be appended here as Phase 3 progresses.

**First entry on FTDI cable arrival (per blockers.md B-1):** baseline serial
capture of the known-good 3.18 Kali boot — validates cable/wiring/baud before
any 6.6 flash.

## FIFTEENTH RESULT — eMMC ENUMERATES: mt2701-compat + pinmux-only fix confirmed, all 33 partitions visible (2026-07-05)

**Log:** `logs/2026-07-05-35-msdc0-mt2701-compat-boot.log`
**Kernel:** `#37 SMP PREEMPT Sun Jul 5 04:33:25 UTC 2026`
(`logs/2026-07-05-34-msdc0-mt2701-compat/`, sha256
`3d964c61dbd22c99432c9f0600351b0bf6a06edbc27df6f842e0837b8c1b244a`,
flashed to both `boot` and `boot2` with targeted `mtk w`).

**Observed:**

- Banner matches the flashed build. Storm guard silent, zero `error -84`,
  zero pinctrl failures (no `group 122`, no `GPIO125 already requested`).
- Probe clean: hclk 273 MHz, `msdc_init_hw` done, `mmc_add_host` returned 0.
- `Run /bin/sh as init process` → live shell, then asynchronously:
  - `mmc0: new high speed MMC card at address 0001`
  - `mmcblk0: mmc0:0001 DF4064 58.2 GiB` with partitions **p1–p33**
    (including p29, the Kali rootfs target)
  - `mmcblk0boot0/boot1` (4 MiB each) and `mmcblk0rpmb` chardev.

**Conclusions:**

- The CRC -84 root cause was exactly the register-layout mismatch: MT6797's
  MSDC is mt2701-generation (12-bit CKDIV, PAD_TUNE0 @ 0xf0), not
  mt6795-generation. `mediatek,mt2701-mmc` is the correct upstream compat.
- Stripping bias/input-enable pinconf (unsupported by `pinctrl-mt6797.c`)
  cleared the state-apply failures and the GPIO125 pin-claim leak.
- Card negotiated legacy "high speed" (52 MHz, per `cap-mmc-highspeed`).
  HS200/HS400 needs tuning support + pad-tune values — deferred optimisation.
- **The eMMC half of B-7 is resolved.** Next: drop `rdinit=/bin/sh` from the
  cmdline and let the vendor ramdisk `switch_root` onto `/dev/mmcblk0p29`,
  to answer the original B-7 question (does the 2019 Kali userspace boot
  under 6.6?).

## BUILD #38 — switch_root test: rdinit=/bin/sh removed, vendor init will try /dev/mmcblk0p29 (2026-07-05)

**Provenance:** `logs/2026-07-05-36-switchroot-p29/` — sha256
`0592142d48f62a437b4a0552a8a7f9bc3877b2ab9fb2fa6d1551e578e4a2d2d3`,
banner `#38 SMP PREEMPT Sun Jul 5 04:39:41 UTC 2026`.

**Change:** only `configs/gemini-cmdline.config` — dropped `rdinit=/bin/sh`
so the vendor 2019 Kali ramdisk's `/init` runs and does its unconditional
`switch_root` onto `/dev/mmcblk0p29` (now exists — FIFTEENTH RESULT). This is
the remaining half of B-7: does the 2019 Kali (3.18-era) userspace boot
under Linux 6.6?

**Expected capture** (`logs/2026-07-05-37-switchroot-p29-boot.log`):
banner `#38`; possible outcomes:
- **Best:** switch_root succeeds, systemd/init from p29 starts, maybe a
  login prompt on ttyS0 → 2019 userspace works, B-7 fully resolved.
- **Race risk:** the card enumerated asynchronously ~40 ms after init
  started last boot; if the vendor init doesn't wait for the device,
  switch_root may race enumeration and fail even though eMMC works —
  distinguishable from a userspace failure by whether `mmcblk0p29` had
  appeared before the panic/error.
- **Userspace failure:** switch_root succeeds but init from p29 crashes or
  stalls (3.18-era assumptions) → go the fresh-mmdebstrap route.

## SIXTEENTH RESULT — FULL KALI USERSPACE BOOTS: switch_root works, login prompt on ttyS0; vendor charger daemon then forces rootfs read-only (2026-07-05)

**Log:** `logs/2026-07-05-37-switchroot-p29-boot.log`
**Kernel:** `#38 SMP PREEMPT Sun Jul 5 04:39:41 UTC 2026`
(`logs/2026-07-05-36-switchroot-p29/`, flashed to both slots).

**Observed:**

- eMMC enumerates again (0.54s), vendor init's `switch_root` succeeds:
  `EXT4-fs (mmcblk0p29): mounted filesystem ... r/w` at 2.73s.
- **systemd 239 starts, "Welcome to Kali GNU/Linux Rolling!"**, hostname
  `kali`, all core services up (journald, udev, D-Bus, sshd, connman,
  login service). `kali login:` **prompt on ttyS0 at 22.5s**. Multi-User +
  Graphical targets reached; `Startup finished in 3.129s (kernel) +
  23.809s (userspace)`.
- Then the Android-side stack (droid-hal-init / `kpoc_charger`) runs:
  `charger: is_charging_source_available(), usb:0 ac:0 wireless:0` — the
  vendor charger daemon decides no power source is present and initiates
  its power-off path: `sysrq: Emergency Remount R/O` at 28.6s (all ext4
  volumes remounted ro, one benign ext4 WARN during the forced remount),
  `lxc@android.service` fails. The power-off itself never completes, so
  the system limps on with a read-only root (`ext4_do_writepages ...
  err -30` repeating). Minor: `haveged.service` failed;
  "Initialize lights on Gemini" failed; android `system` partition lookup
  failed (`/dev/block/platform/mtk-msdc.0/...` vendor path, expected).

**Conclusions:**

- **B-7 is answered: the 2019 Kali userspace runs fine under 6.6.** glibc,
  systemd 239, udev, getty all work. No fresh rootfs is required for
  Phase 4.
- The remaining defect is the vendor charger/Android compatibility layer:
  it misreads the charging state (no vendor battery/charger drivers exist
  under 6.6 — `/sys/devices/platform/battery_meter/...` missing) and
  emergency-remounts the disk. Fix is in userspace: disable
  `droid-hal-init`/`lxc@android`/charger units on p29 (mount it from the
  initramfs shell or via a boot with `rdinit=/bin/sh` and edit), or mask
  the services. Alternatively test with a charger plugged in, but
  disabling is the right long-term move — the Android container is dead
  weight under this kernel.

## SEVENTEENTH RESULT — clean stable boot: Android units masked, no emergency remount, login prompt persists (2026-07-05)

**Log:** `logs/2026-07-05-38-masked-android-boot.log`
**Kernel:** same `#38` build (no reflash; userspace change only —
`droid-hal-init`/`lxc@android` masked on p29 from the live serial session).

**Observed:**

- Boot reached `kali login:` on ttyS0 and **stayed healthy**: no
  `sysrq: Emergency Remount`, no `err -30` writeback spam, no charger
  daemon output. The rootfs remains read-write. lxc@android shows
  `masked/failed` in `--failed` (expected for a masked unit), plus the two
  known-benign failures (haveged, gemini-lights).
- **User logged into Kali over serial** — first interactive login of the
  project (previous boot, same build).
- Software `reboot` untested: the user had to drop the tty session to
  start the FTDI capture and hard-reset instead. PSCI reboot path remains
  an open test item.
- The only remaining log noise is the GEMINI-DEBUG instrumentation
  (32 lines, mostly the mtk-msdc runtime-PM `ungate` print firing on every
  MMC runtime resume). Its diagnostic purpose (msdc bring-up) is complete.

**Conclusions:** Phase 4 storage/userspace is functionally complete on the
2019 Kali image. Cleanup candidates for the next build: drop the four
temporary GEMINI-DEBUG patches (mmc instrumentation incl. storm guard,
pinctrl, gpiolib-of, regulator-fixed debug) and update build-pack.sh's
`IRQ storm` tripwire check accordingly. Open items: software-reboot test,
`maxcpus=1`, `clk_ignore_unused`, `nokaslr` removal, B-13 (display).

## EIGHTEENTH RESULT — software `reboot` does NOT reset the SoC: hang after `reboot: Restarting system` (2026-07-05)

**Log:** `logs/2026-07-05-39-reboot-test-boot.log`
**Kernel:** same `#38` build (no reflash). First use of
`ftdi-monitor.py --interactive` — logged in, ran `reboot`, and captured the
whole shutdown in one session (the tty-vs-capture port conflict is solved).

**Observed:**

- Orderly, complete systemd shutdown: all units stopped, filesystems
  unmounted cleanly (p29 remounted ro, loop/system.img detached, swaps off),
  `Reached target Final Step`, `Starting Reboot...`.
- `[  296.945] watchdog: watchdog0: watchdog did not stop!` — systemd-shutdown
  takes over the hardware watchdog (`Hardware watchdog 'mtk-wdt', version 0`)
  as its reboot backstop.
- Final line: `[  297.111] reboot: Restarting system` — this is
  `machine_restart()` invoking the PSCI `SYSTEM_RESET` SMC into ATF.
  **Nothing after it.** The device never re-entered the boot chain (no
  preloader/LK output); the user power-cycled manually.
- The armed mtk-wdt also never fired (no reset ~30s later), so either the
  restart path disabled it (mtk_wdt has a restart handler that reprograms
  WDT_MODE) or the SoC is wedged at a level below the watchdog.

**Analysis:** two candidate mechanisms, not yet distinguished:

1. **ATF PSCI SYSTEM_RESET broken/hung** under our boot state. The vendor
   ATF's reset path may depend on SoC state (e.g. SPM/clock state the vendor
   kernel maintains) that our 6.6 boot — with `clk_ignore_unused`, no scpsys
   domains, `maxcpus=1` — leaves different.
2. **mtk-wdt restart handler** — mainline registers a restart_handler that
   resets via the toprgu WDT_SWRST register; if the kernel is using that
   (priority 128) rather than PSCI, the failure is in the toprgu path
   instead. Which handler actually ran is not visible in the log; adding
   `reboot=` debug or checking `/sys/kernel/reboot` on the next boot would
   disambiguate.

**Conclusions:** filed as blocker **B-14** (low severity — hard power-cycle
works, this costs convenience not progress; likely tangled with the same
SMP/PSCI oddity behind `maxcpus=1`). Not a Phase 4 gate. The interactive
capture workflow is validated.

## BUILD #39 — debug-instrumentation cleanup (2026-07-05, not yet flashed)

**Provenance:** `logs/2026-07-05-39-debug-cleanup/` — sha256
`0f1140a78d54272e7db42f578ae50aab88caf2d501b979ef3b33dc4f567c1c13`, banner
`#39 SMP PREEMPT Sun Jul  5 05:01:02 UTC 2026`.

**Changes vs #38:** removed the four temporary GEMINI-DEBUG patches
(`mmc/0001` instrumentation incl. IRQ-storm guard, `pinctrl/0001`,
`gpio/0002`, `regulator/0002`) — their msdc bring-up diagnostic purpose is
complete (FIFTEENTH–SEVENTEENTH RESULTs). 15 patches remain. build-pack.sh
updated: the `IRQ storm` presence tripwire is now inverted to a
`GEMINI-DEBUG` **absence** check (fails if any instrumentation sneaks back
in), and the patches rsync gained `--delete` so patch removals propagate to
the VM. No functional kernel changes expected; boot should be identical to
#38 minus the 32 debug lines.

**Companion change:** first Debian 13 rootfs image built by the new
`scripts/mkrootfs.sh` (see next entry when flashed) — the #39 flash and the
p29 rootfs flash can be done in the same preloader session.

## ROOTFS IMAGE — Debian 13 (trixie) arm64, first build (2026-07-05, not yet flashed)

**Built by:** `scripts/mkrootfs.sh` (new; runs in the build VM, native
arm64, mmdebstrap minbase).
**Image:** `~/gemini-build/OUTPUT/debian13-rootfs.img` — 1.5 GiB shipped
(built at 4 GiB, resize2fs-shrunk to cut preloader-USB flash time; grow on
device with `resize2fs /dev/mmcblk0p29`). sha256
`9426af99deb0407639ae83ffe43358c58d087d4414ef19e70a76a64e4a26ece4`.
e2fsck clean after shrink.

**Contents verified by loop-mount in the VM:** systemd 257
(`/sbin/init` → `../lib/systemd/systemd`), fstab `/dev/mmcblk0p29 / ext4
defaults,noatime`, kernel modules `6.6.0-dirty` (from the #39 tree),
root password `toor`, sshd `PermitRootLogin yes`, hostname `gemini`.
Packages: base (systemd,udev,dbus,kmod,util-linux,e2fsprogs,apt) + net
(openssh-server,iproute2,ifupdown,isc-dhcp-client — idle until Phase 8) +
tools (i2c-tools,mmc-utils,evtest,usbutils,less,vim-tiny,htop).

**Pre-check (vendor ramdisk, unchanged in our boot images):** its Mer Boat
Loader `/init` mounts p29 with bare busybox `mount` (kernel autodetect) and
`exec switch_root /target /sbin/init --log-target=kmsg`; prefers
`/sbin/preinit` if executable (Debian ships none). So no ramdisk/boot-chain
change is needed for the rootfs swap.

**Flash plan (same preloader session as kernel #39):**
```
/tmp/mtk-venv/bin/python3 ~/mtkclient/mtk.py w boot  logs/2026-07-05-39-debug-cleanup/new_kali_boot.img
/tmp/mtk-venv/bin/python3 ~/mtkclient/mtk.py w boot2 logs/2026-07-05-39-debug-cleanup/new_kali_boot.img
/tmp/mtk-venv/bin/python3 ~/mtkclient/mtk.py w linux ~/gemini-build/OUTPUT/debian13-rootfs.img
```
Recovery: `mtk w linux planet/linux.img` restores the 2019 Kali userspace.

**First-boot expectations:** `gemini login:` on ttyS0; root/toor; systemd
257; `systemctl --failed` should be clean or near-clean (no droid-hal,
kpoc_charger, haveged or gemini-lights — none exist on this image); rootfs
rw; then run `resize2fs /dev/mmcblk0p29` and confirm `df -h /` ≈ 25 GiB.
Capture: `python3 scripts/ftdi-monitor.py --interactive --log
logs/2026-07-05-40-debian13-first-boot.log`.

## NINETEENTH RESULT — DEBIAN 13 FIRST BOOT: works first try; dbus failure root-caused to vendor-initramfs mdev clobbering devtmpfs modes (2026-07-05)

**Flashed:** build #39 (`boot`+`boot2`, sha256 `0f1140a7…c13`) and
`debian13-rootfs.img` (`linux` p29, sha256 `9426af99…ce4`). User-driven flash
and first-boot session (interactive capture); follow-up diagnosis run by
Claude directly over the FTDI serial line (scripted pyserial commands against
the logged-in root shell).

**Outcome:** Debian 13 boots first try — `gemini login:` on ttyS0, root/toor
works, systemd 257, rootfs read-write. `resize2fs /dev/mmcblk0p29` grew the
fs to the full 25.8 GiB partition. Only failures: `dbus.socket` +
`dbus.service`.

**dbus RCA (confirmed):**
- Symptom: `dbus-daemon: fatal error setting up standard fds: Failed to open
  /dev/null: Permission denied`, 5× between t=11.1s and t=17.5s, then
  `service-start-limit-hit` — dbus stays failed forever.
- `/dev` IS devtmpfs and `/dev/null` IS `crw-rw-rw- 1,3` once boot settles;
  `runuser -u messagebus -- head -c0 /dev/null` succeeds; manual
  `dbus-daemon --system` starts fine. So the denial was transient.
- Cause: the vendor Mer boat loader initramfs runs
  `echo /sbin/mdev > /proc/sys/kernel/hotplug; mdev -s` (its `/init` lines
  126–127) against the kernel devtmpfs — the same instance the booted system
  inherits. Busybox mdev with no `/etc/mdev.conf` re-creates/chmods nodes to
  **0660 root:root**. Fingerprint: mdev-style `179:N -> ../mmcblk0pN`
  symlinks litter `/dev`. systemd-udevd's coldplug eventually restores 0666
  (trigger finishes t=10.6s but the queue drains slowly on `maxcpus=1`),
  and dbus — the first *unprivileged* opener of `/dev/null` — loses the race.
- Fix (applied live + in `scripts/mkrootfs.sh`): `/etc/tmpfiles.d/gemini-devnodes.conf`
  with `z` (adjust-existing) lines restoring 0666 on
  null/zero/full/random/urandom/tty/ptmx. Runs in
  `systemd-tmpfiles-setup-dev-early.service` (t≈7s), safely before dbus.
  Verified live: `systemctl reset-failed && start` → both units active,
  `systemctl --failed` clean. Cold-boot verification pending next power cycle.
- Also enabled: `systemd-networkd` + `/etc/systemd/network/usb0.network`
  (10.15.19.82/24) on the live system and in mkrootfs.sh, ready for the
  USB-gadget SSH work (build #40).

**Lesson:** the vendor initramfs shares devtmpfs with the final system;
anything it does to `/dev` (modes, stray symlinks) persists across
switch_root. Any userspace that races udev's coldplug must not assume
default node modes.

## BUILD #40 — USB gadget ethernet (SSH over USB-C), first mtu3/T-PHY build (2026-07-05, not yet flashed)

**Goal:** `ssh root@gemini` over the left USB-C port via g_ether — fast-track
of Phase 8, no WiFi driver needed.

**Changes:**
- `patches/v6.6/dts/0009-arm64-dts-mediatek-add-gemini-ssusb-gadget.patch`:
  SSUSB (mtu3) + generic-tphy-v1 nodes in the board DTS. Values from the
  vendor DTB (`usb3@11270000`/sif/sif2/usb3_phy) mapped onto the MT8173 mtu3
  layout: MAC 0x11271000, IPPC 0x11280700, T-PHY 0x11290000 (u2port0 at
  +0x800). IRQ SPI 127 level-low. Clocks infracfg SSUSB_SYS/SSUSB_REF.
  No power-domains — MT6797 scpsys has no USB domain (infra fabric), so
  this does NOT depend on B-13. dr_mode="peripheral", high-speed only
  (u3port deliberately unwired for first light).
- `configs/gemini-usb.config`: USB_MTU3_GADGET (peripheral-only choice),
  USB_ETH=y (g_ether built-in, CDC ECM + RNDIS).
- Rootfs side already live (NINETEENTH RESULT): usb0 = 10.15.19.82/24 via
  systemd-networkd; sshd enabled with root login.

**Provenance:** `logs/2026-07-05-40-usb-gadget/` — sha256
`ebdeb140522ffc1994c1780bcaa1ce7e1fbe886ab0b464fb7bbb41337daccf11`, banner
`#40 SMP PREEMPT Sun Jul  5 06:32:05 UTC 2026`. DTB grep confirms
`usb@11271000`; packed kernel contains g_ether/mtu3/mtk-tphy/CDC-Ethernet
strings; GEMINI-DEBUG absent, display absent. 16 patches applied.

**Test plan:** flash boot+boot2 → serial capture of one boot (confirm no
regression, mtu3 probes, "using random self ethernet address" from g_ether)
→ unplug FTDI (left port is shared with the UART mux!) → USB-C data cable to
Mac → CDC ECM interface appears; give it 10.15.19.1/24 → `ssh
root@10.15.19.82`. Serial and USB cannot be used simultaneously on that port.

## TWENTIETH RESULT — build #40 hangs at mtu3 probe: missing SSUSB bus clock, watchdog boot-loop (2026-07-05)

**Flashed:** #40 (`ebdeb140…c11`) to boot+boot2. Capture appended to
`logs/2026-07-05-40-debian13-first-boot.log` (same interactive session file).

**Observed:** boot proceeds normally to t=0.404s, last line
`mtu3 11271000.usb: u2p_dis_msk: 0, u3p_dis_msk: 0`, then total silence;
watchdog resets the SoC and it loops to the same point (both slots carry
#40). `dr_mode: 2` confirms the DT parsed correctly.

**RCA (source-confirmed):** after that print, `mtu3_probe` →
`ssusb_rscs_init` → `clk_bulk_prepare_enable` → `ssusb_phy_init` — the
T-PHY register write at 0x11290800 is the first access into SSUSB address
space. The dts/0009 node wired only `sys_ck`/`ref_ck` (infra SSUSB_SYS/REF)
and omitted **CLK_INFRA_SSUSB_BUS** ("infra_ssusb_bus", parent axi_sel,
clk-mt6797.c:516) — the wrapper's AXI/register-bus clock and the *first*
clock in the vendor usb3_phy list. With it gated, the PHY write stalls the
bus: silent hang, no exception, ATF watchdog reset — the exact MSDC-CKSTB
failure mode again. LK never enables SSUSB clocks (Android gates USB until
a cable event), so `clk_ignore_unused` cannot preserve them.

**Fix (build #41, dts/0009 revised):** add `mcu_ck = CLK_INFRA_SSUSB_BUS`
to the mtu3 clock bulk (enabled before `ssusb_phy_init`, so it also clocks
the PHY bank), and route the `ssusb_top_sys_sel` mux (parent of
infra_ssusb_sys) to `univpll3_d2` via assigned-clocks, per the vendor clock
list — the same explicit-mux-routing lesson as MSDC (2026-07-04-29).

**Lesson (recurring, now twice):** on MT6797, any new IP block needs its
*bus/hclk gate* wired explicitly, not just the functional clocks — the
symptom of a missing one is always a silent hang at the first register
access, ~36s before a watchdog reset. Check the vendor clock list for a
`*_bus_clk` entry first.

**Build #41 provenance:** `logs/2026-07-05-41-ssusb-bus-clk/` — sha256
`f64e94acf6f3584bf528aa02bb32c7fb077f14935baa6f5a1a9f9fe41accf397`, banner
`#41 SMP PREEMPT Sun Jul  5 06:39:24 UTC 2026`. DTB grep confirms
`clock-names = "sys_ck", "ref_ck", "mcu_ck"`; GEMINI-DEBUG absent, display
absent.

## TWENTY-FIRST RESULT — build #41 still hangs at the same point: bus clock was not (the only) missing enable (2026-07-05)

**Raw log:** `logs/2026-07-05-42-ssusb-bus-clk-boot.log` (banner confirms `#41`,
so the flash took and the mcu_ck DTS was running).

**Observation:** identical failure signature to #40 — last line is
`[0.404240] mtu3 11271000.usb: u2p_dis_msk: 0, u3p_dis_msk: 0`, then silence
and watchdog reboot. Adding `CLK_INFRA_SSUSB_BUS` (mcu_ck) plus the
`ssusb_top_sys_sel → univpll3_d2` mux routing did not move the hang point.

**What this rules out / confirms:**
- The clock set now matches the vendor `usb3_phy` node exactly
  (`ssusb_bus_clk` 0x45, `ssusb_sys_clk` 0x4b, `ssusb_ref_clk` 0x4c, top-sys
  mux to univpll3_d2) — vendor DTB `usb3_phy` node is the source of truth.
- The register map is confirmed correct against the MT6797 Functional Spec
  §5.17 memory map: `ssusb_sifslv_ippc` = 0x11280700,
  `ssusb_sifslv_u2phy_com` = 0x11290800, shared SIF bank base 0x11290000.
  (Spec text extracted to scratchpad; table lists all SSUSB sub-banks.)
- MT6797 scpsys has no USB power domain, so no power-domains property applies.
- Therefore something *undocumented in the vendor DT* still gates the SSUSB
  SIF bank (candidates: an infracfg module reset held, an IPPC-level power
  state the BROM/preloader leaves different from MT8173, or the hang is not
  where assumed).

**Next step (build #42):** stop guessing; instrument. Pure trace build —
`patches/v6.6/debug/0001-GEMINI-DEBUG-ssusb-probe-trace.patch` adds dev_info
brackets around every step of `ssusb_rscs_init` (clk enable / phy_init /
power_on / ip_sw_reset) and `mtk_phy_init` (clk / efuse / first SIF
read-modify-write at U2PHYDTM0 = 0x11290868). The serial log will name the
exact access that stalls the bus. Built with `ALLOW_DEBUG=1` (build-pack
tripwire override); the debug patch must be deleted again once diagnosis is
done.

**Trace-build provenance:** `logs/2026-07-05-42-ssusb-probe-trace/` — sha256
`ee09efb01fc7d6fd8b163f448667235504df389831cd0afdeefade4bdeeab8b8`, banner
`#43 SMP PREEMPT Sun Jul 5 06:51:19 UTC 2026`. GEMINI-DEBUG present
(deliberate, ALLOW_DEBUG=1). Same DTS/config as #41. (An earlier identical
trace build, banner #42, was rebuilt and overwritten before flashing; the
sha256 above is the image on disk.)

## TWENTY-SECOND RESULT — trace build pins the hang to the first U2-PHY SIF read (2026-07-05)

**Raw log:** `logs/2026-07-05-43-ssusb-probe-trace-boot.log` (banner `#43`).

**Observation:** all GEMINI-DEBUG brackets before the PHY register access
printed; the last line ever printed is
`mtk-tphy: GEMINI-DEBUG: u2 init, first SIF read @... (U2PHYDTM0)` at
t=0.410s. So `clk_bulk_prepare_enable` (mtu3 and tphy) succeeds and the hang
is exactly the first read of the U2-PHY com bank at 0x11290868.

**Conclusion:** the SSUSB SIF slave for the PHY does not decode even with the
full vendor clock set on. Working hypothesis: on MT6797 the PHY SIF bank sits
behind the SSUSB IP power/reset state controlled from IPPC
(`SSUSB_IP_SW_RST` / `SSUSB_IP_DEV_PDN`), which LK never initialises (Android
powers USB only on cable events). Mainline mtu3 touches IPPC only *after*
phy_init — an order that works on MT8173 where the bootloader brings USB up
for fastboot.

**Next (build #44, `logs/2026-07-05-44-ssusb-ippc-first/`):** debug patch v2
reads and prints `IP_PW_CTRL0`/`IP_PW_CTRL2` right after clock enable, then
pulses `SSUSB_IP_SW_RST` and clears `SSUSB_IP_DEV_PDN` *before* phy_init.
Outcomes: (a) IPPC read also hangs → the whole SSUSB IP is dead (infracfg
reset / undocumented gate); (b) IPPC responds and the PHY read then works →
root cause found, fix = do the IPPC power-up before phy init (proper patch to
follow); (c) IPPC responds but PHY still hangs → PHY bank gated by something
else. sha256
`65cc5047c8a1d2b732158232048cbbd82618a9185f4fccc50985fb9319087314`, banner
`#44 SMP PREEMPT Sun Jul 5 06:56:05 UTC 2026`, GEMINI-DEBUG present
(deliberate).

## TWENTY-THIRD RESULT — IPPC is alive; IP unreset+unPDN does NOT unblock the PHY SIF (2026-07-05)

**Log:** `logs/2026-07-05-45-ssusb-ippc-first-boot.log` (build #44, sha
`65cc5047…9314`, banner confirmed `#44 SMP PREEMPT Sun Jul 5 06:56:05 UTC 2026`).

Outcome (c) from the TWENTY-SECOND entry's three-way experiment:

```
[0.407] GEMINI-DEBUG: IP_PW_CTRL0=00011001 IP_PW_CTRL2=00000001
[0.408] GEMINI-DEBUG: IPPC alive, IP unreset+unPDN, ssusb_phy_init...
[0.412] mtk-tphy: GEMINI-DEBUG: u2 init, first SIF read @... (U2PHYDTM0)   <- last line, hang + WDT
```

Findings:
- The IPPC bank (0x11280700) reads fine — the SSUSB wrapper is clocked and
  decoding. Only the PHY SIF bank (0x11290800) hangs.
- LK leaves the IP held in reset: `IP_PW_CTRL0` bit0 (`SSUSB_IP_SW_RST`) = 1
  and `IP_PW_CTRL2` bit0 (`SSUSB_IP_DEV_PDN`) = 1 at probe. Clearing both
  (with a reset pulse) is evidently necessary-but-not-sufficient: the very
  next U2PHYDTM0 read still hangs.
- Remaining gate candidates: the per-port power-downs
  (`SSUSB_U2_PORT_DIS|PDN` in `U3D_SSUSB_U2_CTRL_0P`, likewise U3), which
  mainline mtu3 only clears in `mtu3_device_enable()` — long after phy_init —
  and/or the MAC clock-stable handshake (`IP_PW_STS1/2`).

**BUILD #45 (dir `logs/2026-07-05-46-ssusb-port-unpdn/`):** extends the
experiment — after IP unreset+unPDN it also clears U2/U3 port
DIS|PDN|HOST_SEL, waits 100µs, and prints `IP_PW_STS1/STS2` before phy_init.
sha256
`0ec038b36a610b8e91f3599557dfce237bc84a5f5a247f837f7ae917981a1667`, banner
`#45 SMP PREEMPT Sun Jul 5 07:01:36 UTC 2026`, GEMINI-DEBUG present
(deliberate, ALLOW_DEBUG=1). Capture to
`logs/2026-07-05-47-ssusb-port-unpdn-boot.log`.

## TWENTY-FOURTH RESULT — port unPDN + MAC clocks confirmed running; PHY SIF still dead → PMIC rails hypothesis (2026-07-05)

**Log:** `logs/2026-07-05-47-ssusb-port-unpdn-boot.log` (build #45, sha
`0ec038b3…1667`, banner confirmed).

Build #45 cleared U2/U3 port DIS|PDN|HOST_SEL and dumped the IP power status
before phy_init:

```
[0.407] GEMINI-DEBUG: ports unPDN, IP_PW_STS1=01000d0e STS2=00000001
[0.412] mtk-tphy: GEMINI-DEBUG: u2 init, first SIF read @... (U2PHYDTM0)   <- last line, hang + WDT
```

`STS1` bit10 (`SSUSB_SYS125_RST_B_STS`) and bit8 (`SSUSB_REF_RST_B_STS`) set,
`STS2` bit0 (`SSUSB_U2_MAC_SYS_RST_B_STS`) set — **the entire SSUSB MAC is
clocked and out of reset**, yet the SIF2 PHY bank (0x11290800) still stalls
the bus. IPPC/port state fully exonerated alongside clocks.

**New evidence — vendor 3.18 mu3phy driver** (Meizu MX6 tree
`github.com/mirsys/mt6797`, `drivers/misc/mediatek/mu3phy/mt6797/mtk-phy-asic.c`,
saved to scratchpad): `phy_init_soc()` (and even the SIB debug helpers)
unconditionally enable **PMIC MT6351 rails before any SIF access**:
`RG_VUSB33_EN` (reg 0x0A16 bit1), `RG_VA10_EN` (0x0A6E bit1),
`RG_VA10_VOSEL=1` → 0.95V (0x0B10 bits[10:8]) — then clocks, 50µs, first SIF
write. VA10 is the USB PHY analog supply ("VDD10_USB_P0"); the vendor treats
rails-on as a hard prerequisite of SIF register access. Our boots never power
them (mtu3 vusb33 = dummy regulator; with FTDI on the left-port mux the
preloader can't have brought USB up either). Hypothesis: **the PHY macro
including its APB register file sits in the VA10/VUSB33 power domain — rails
off = SIF slave doesn't respond = AXI stall.**

Mainline support check: pwrap driver supports mt6797 host + mt6351 slave protocol,
but there is **no MT6351 MFD/regulator driver in mainline 6.6** — a proper fix
needs a small regulator patch or a port. pwrap probe also wants a "pwrap"
reset line mainline mt6797 doesn't provide (though init is skipped when the
preloader already did it — INIT_DONE2).

**BUILD #46 (dir `logs/2026-07-05-48-ssusb-pmic-rails/`):** verification
experiment — mtu3 probe pokes MT6351 directly via raw pwrap WACS2 transactions
(ioremap 0x1000d000; preloader-initialized, clk_ignore_unused keeps it
sha256
`2a45b0d7f2517ca68b72341c48f12f6b76d2cfe8acd3e948f8b0bd6c52548749`. Prints VUSB33_CON0/VA10_CON0/VA10_ANA_CON0 before and after setting
the three fields, 300µs settle, then phy_init. Banner
`#46 SMP PREEMPT Sun Jul 5 07:13:09 UTC 2026`, GEMINI-DEBUG present
(deliberate). If the SIF read survives, root cause = unpowered PHY rails and
the proper fix is pwrap + MT6351 regulator support (new driver_ports.md
entry). Capture to `logs/2026-07-05-49-ssusb-pmic-rails-boot.log`.

## TWENTY-FIFTH RESULT — PMIC rails ruled out; bisection narrows the "hang" to the mux itself; recovery test proves it's not a hang at all (2026-07-05)

**Logs:** `2026-07-05-49` (build #47, banner `#47 ... 07:18:09`),
`-51` (#48, `07:23:57`), `-53` (#49, `07:36:44`), `-55` (#50, `07:45:58`),
`-57` (#51, `07:49:50`), `-59` (#52, `07:55:36`).
Images/sha256: `logs/2026-07-05-48-ssusb-pmic-rails` `c9fe88bb…67264d`,
`-50-ssusb-iso-en` `1f7d5758…f340bc96e`, `-52-ssusb-bisect`
`86f44aab…56da2dfa0fdb`, `-54-ssusb-dtm0-write` `5a6ba701…c537e8da`,
`-56-ssusb-bit-split` `12724149…823fec05a86b982ed64`,
`-58-ssusb-mux-recovery-test` `c205d56d…c7cee692038bee7d666a5b8`.

Build #47 turns the MT6351 rails on directly (raw pwrap WACS2 writes:
`VUSB33_CON0=da62 VA10_CON0=da62 VA10_ANA_CON0=0100`) before `phy_init` — and
the SIF read still stalls at the same instruction. **PMIC rails hypothesis
falsified.** From here the debugging narrows methodically:

- **#48 (iso-en):** forcing `RG_USB20_ISO_EN=0` (isolation cell) before the
  SIF read — no change, still stalls at the identical `U2PHYDTM0` read.
- **#49 (bisect):** reads every T-PHY probe-time register offset (`+0x00`
  through `+0x68`) one at a time before the real init path touches anything —
  **all offsets survive** ("bisection complete, all offsets survived"). The
  SIF bus itself is fine; the stall is specific to something the *real* init
  sequence does that the read-only bisection doesn't.
- **#50 (dtm0-write):** isolates further — reads `U2PHYDTM0` (survives, val
  `56be00dc`), then does a **no-op writeback** of the same value (survives).
  So even a write to the exact register that "hangs" in normal boot survives
  when it doesn't change any bits.
- **#51 (bit-split):** splits the real init's `clear_bits(FORCE_UART_EN |
  FORCE_SUSPENDM)` into two separate single-bit clears to find which one
  "hangs." Clearing `FORCE_UART_EN` alone is the one that reproduces the
  symptom (console goes dark at that exact line).
- **#52 (mux-recovery-test, the key result):** after clearing `FORCE_UART_EN`
  and losing the console, the code waits, then **re-sets** `FORCE_UART_EN`
  and writes a debug line. That line **appears** in the log 250ms later:
  `FORCE_UART_EN re-set survived, val=56be00dc -- if you can read this, the
  write never hung, only the console mux dropped`. It then clears
  `FORCE_SUSPENDM` (a PLL kick) and that also completes and logs
  successfully.

**Conclusion: there was never a hang.** `FORCE_UART_EN` is a real hardware
mux control bit in the T-PHY block — clearing it (as mainline `mtk-tphy`
correctly does during normal U2 PHY init) switches the shared UART/USB-C pin
mux away from the debug console, which is exactly the documented hardware
behaviour (CLAUDE.md Phase 8 note: "the left USB-C port is shared with the
UART console mux: serial and USB are mutually exclusive"). Twenty-four
"results" of PHY/clock/PMIC forensics were chasing a false hang caused by our
own instrumentation methodology (expecting continuous serial output through a
mux transition that mainline code is supposed to cause). The driver was
correct the whole time; test methodology needed to change, not the driver.
See B-15 in blockers.md for the reusable diagnostic-methodology write-up.

## TWENTY-SIXTH RESULT — clean build (no debug instrumentation) confirmed: gadget enumerates, IP works, SSH login succeeds (2026-07-05/2026-07-06)

**Build #53** (dir `logs/2026-07-05-60-ssusb-clean-no-debug/`, sha256
`6d399133…5bb0e33`) reverts all `GEMINI-DEBUG` instrumentation added across
builds #40–#52 back to plain upstream-style `mtk-tphy`/`mtu3` init, per the
TWENTY-FIFTH RESULT conclusion that no workaround was ever needed. Flashed to
both `boot` and `boot2`.

**Capture `logs/2026-07-05-61-ssusb-clean-no-debug-boot.log`:** boots
normally; console goes dark at `mtu3 11271000.usb: u2p_dis_msk: 0,
u3p_dis_msk: 0` (t≈0.4s) exactly as predicted — this is the mux switching
away from UART, not a fault.

**Verification on the Mac (2026-07-06), single-cable swap protocol** (FTDI
and direct-to-Mac USB-C cannot be connected simultaneously — same physical
mux):
1. With FTDI connected: serial capture confirms kernel reaches the same
   `mtu3 ... u2p_dis_msk` line then goes dark, consistent with #52's finding.
2. Cable swapped to a direct Gemini→Mac USB-C connection (FTDI unplugged):
   `ioreg -p IOUSB` shows a new **RNDIS/Ethernet Gadget** device; macOS
   brings it up as `en12`.
3. `sudo ifconfig en12 inet 10.15.19.1 netmask 255.255.255.0` (en12 had no
   address — macOS had parked it under the Internet Sharing `bridge100`).
4. `ping 10.15.19.82` succeeds (sub-1ms RTT, confirms it's a direct USB link,
   not a bridge/NAT path).
5. `ssh root@10.15.19.82` (password `toor`, set by `mkrootfs.sh`) succeeds:
   ```
   gemini
   Linux gemini 6.6.0-dirty #53 SMP PREEMPT Sun Jul 5 07:59:03 UTC 2026 aarch64 GNU/Linux
   ```

**Phase 8 SSH-over-USB fast-track is fully verified working end-to-end**:
kernel gadget driver, host-side RNDIS enumeration, static IP, ping, and SSH
login all confirmed on real hardware. See CLAUDE.md Phase 8 status update.

## TWENTY-SEVENTH RESULT — clarification: console going dark at the mtu3 mux switch is not a boot stall (2026-07-06)

Recurring user-facing question worth recording explicitly: does the boot
process stop/wait at the `mtu3 ... u2p_dis_msk` line, resuming only once a
USB cable is attached?

**No.** The kernel does not pause or block there. Boot continues
unconditionally, straight through rootfs mount, systemd, networkd and sshd
coming up — all silently as far as UART is concerned. What actually happens:

- The left USB-C port is a single physical mux shared between the UART debug
  console (FTDI) and the USB device/gadget controller.
- When the `mtu3`/`mtk-tphy` USB gadget driver initializes (~0.4s in), it
  switches that port's signal lines from UART over to USB. The FTDI serial
  link goes dark at that instant — not because the kernel stopped, but
  because its only observation channel was just switched away.
- Because it's a hardware mux, not a software toggle, FTDI serial and a
  direct Gemini→Mac USB-C connection can never be observed at the same time.
  Seeing the rest of boot requires physically swapping the cable from FTDI to
  a direct-to-Mac connection (the "single-cable-swap protocol" used in the
  TWENTY-SIXTH RESULT above) — at which point an RNDIS/Ethernet gadget
  appears on the host, static IP + ping + SSH all succeed, proving the kernel
  had already booted fully to a login-capable userspace.

This is the same root cause as B-15 (documented mux behavior, not a driver
defect) — recorded here separately because it answers a recurring "did it
hang?" question distinct from the original build #40–#52 investigation.

## BUILD #62 — clk-disable-unused tracer, prepared for Phase 4 workaround root-cause (2026-07-06, not yet flashed)

Remaining Phase 4 technical debt (CLAUDE.md): the `maxcpus=1` CPU1 PSCI hang
and the `clk_ignore_unused` "Disabling unused clocks" hang (first seen SIXTH
RESULT, 2026-07-04) have only ever been worked around, never root-caused.
Checked whether this is the same bug as B-13 (scpsys MT6797 domain-table
gap): **it is not** — the clk hang predates all display/scpsys work by a day,
and in this headless config `mtk-scpsys` fails its probe entirely (no domain
gets genpd-managed at all), so there is no "touch an unpowered domain's
register" path available the way there was for B-13's MM-domain hang. The two
issues are coincidentally close in boot timestamp but structurally unrelated;
this entry supersedes any assumption of a shared cause.

**New patch:** `patches/v6.6/clk/0001-GEMINI-DEBUG-clk-trace-disable-unused-clock-names.patch`
— adds `pr_info` before/after the `.disable_unused`/`.disable` call in
`clk_disable_unused_subtree()` (`drivers/clk/clk.c`), printing the clock core
name. Since `clk_ignore_unused` short-circuits `clk_disable_unused()` before
this code path runs at all, the tracer is inert unless that cmdline flag is
removed — so this build drops `clk_ignore_unused` from `CONFIG_CMDLINE`
(VM-local edit only, not synced back to the repo's `configs/gemini-cmdline.config`)
while keeping `maxcpus=1` in place, to isolate the clk hang from the SMP hang
in one capture.

**Build:** patched clean (all 17 project patches applied, including this new
one), headless (`gemini-display.config` absent → B-13 guard active),
`CONFIG_CMDLINE="console=ttyS0,921600n1 earlycon maxcpus=1 nokaslr"`.
Image: `logs/2026-07-06-62-clk-debug-trace/new_kali_boot.img`
(sha256 `5cf9e3db051eed6c8832567a87ed40ff6bf4881b76129ed5ba33afd5c09bd2c2`).
Verified: banner `#1 SMP PREEMPT Mon Jul  6 05:36:27 UTC 2026`, GEMINI-DEBUG
instrumentation present (expected, deliberate debug build), display driver
absent (B-13 guard confirmed).

**Expected outcome on hardware:** boot should proceed as before through
driver init, `mtk-scpsys` probe failure (`-22`, pre-existing/unrelated), and
"clk: Disabling unused clocks" — but now interleaved with
`GEMINI-DEBUG: clk_disable_unused: disabling '<name>'` /
`... disabled '<name>' OK` pairs for every clock actually gated. The last
"disabling" line with **no matching "OK" line** names the clock whose
`.disable`/`.disable_unused` callback wedges the bus (or, if the hang is
lower down in the register write itself, it's simply the last line printed
before silence).

**Not yet flashed** — this is a `boot`/`boot2` slot test image; flashing and
FTDI capture require the physical single-cable-swap protocol (B-15) since the
device is presently reachable over the USB gadget as a live SSH host. Flash:
```
/tmp/mtk-venv/bin/python3 ~/mtkclient/mtk.py w boot2 logs/2026-07-06-62-clk-debug-trace/new_kali_boot.img
```
Capture: `python3 scripts/ftdi-monitor.py --log logs/2026-07-06-63-clk-debug-trace-boot.log`
(FTDI cable, not the direct-to-Mac USB cable — see B-15).

## BUILD #62/#65/#67/#69 — ROOT CAUSE FOUND AND FIXED: `clk_ignore_unused` workaround was masking a real 8250_mtk driver bug (2026-07-06)

**Detour (build #62 capture, `logs/2026-07-06-63-...`):** first capture attempt
showed zero `GEMINI-DEBUG` lines and died at the same `mtu3 ...
u2p_dis_msk` line as every Phase 8 build — this build still had
`gemini-usb.config` merged in (oversight), so the T-PHY/mux switch (B-15)
stole the console before boot ever reached the clk-disable code. Also
flashed to `boot2` first, which is never loaded on plain power-on (repeat of
the ELEVENTH RESULT lesson) — corrected to flash `boot`.

**Detour 2 (build #65, `logs/2026-07-06-66-...`):** rebuilt with
`gemini-usb.config` removed, but `CONFIG_USB_MTU3_GADGET` unset alone still
left `CONFIG_USB_MTU3_DUAL_ROLE=y` as the defconfig default — the `mtu3`
T-PHY controller driver probes and touches the port mux for *any* enabled
role, gadget or not, because our board DTS's ssusb node
(`patches/v6.6/dts/0009`) is unconditionally `status = "okay"`. Same mux
dead-end, same line. Fix: `scripts/config --disable CONFIG_USB_MTU3` +
`make olddefconfig` to remove the driver from the build entirely, not just
its gadget role.

**Build #67 (`logs/2026-07-06-67-clk-debug-no-mtu3/`, capture
`logs/2026-07-06-68-clk-debug-no-mtu3-boot.log`) — tracer finally worked:**
with `mtu3` fully out of the build, the console survived past 0.4s and the
`GEMINI-DEBUG: clk_disable_unused:` tracer (patches/v6.6/clk/0001-...) ran
cleanly. Last lines:
```
[    0.630513] GEMINI-DEBUG: clk_disable_unused: disabled 'infra_uart1' OK
[    0.631355] GEMINI-DEBUG: clk_disable_unused: disabling 'infra_uart0'
```
No matching "OK" line, no further output ever. **The clock the framework
hangs on disabling is `infra_uart0` — the debug console's own baud clock.**

**Root cause (read from driver source, not guessed):**
`drivers/tty/serial/8250/8250_mtk.c`'s `mtk8250_probe_of()` fetches the
`"baud"` clock (our board DTS: `clocks = <&infrasys CLK_INFRA_UART0>, <&infrasys
CLK_INFRA_AP_DMA>; clock-names = "baud", "bus";` — confirmed mainline-style
binding, already correct) with plain `devm_clk_get()`, and only ever calls
`clk_get_rate()` on it (line 560) — it is **never enabled by the driver**,
unlike the `"bus"` clock which correctly uses `devm_clk_get_enabled()`. The
hardware clock is left running by the bootloader/earlycon, so
`clk_core_is_enabled(core)` reads true, but Linux's own refcount
(`enable_count`) stays 0 the whole boot. `late_initcall`'s
`clk_disable_unused_subtree()` sees `enable_count == 0` and calls
`.disable_unused()` on a clock still serving the only console — silently
killing it (indistinguishable from a hang, since it's also the only
diagnostic channel). This is a genuine upstream driver gap in
`8250_mtk.c`, not MT6797-specific — any board relying on the named
`"baud"`/`"bus"` binding without an always-on `CLK_IS_CRITICAL` flag at the
SoC clk-driver level would hit it.

**Fix:** `patches/v6.6/serial/0001-serial-8250_mtk-hold-baud-clock-enabled.patch`
— changes both the `"baud"` and the legacy-unnamed-fallback `devm_clk_get()`
calls to `devm_clk_get_enabled()`, matching the existing `"bus"` clock
handling in the same function.

**Validation (build #69, `logs/2026-07-06-69-uart-clk-fix-validation/`,
capture `logs/2026-07-06-70-uart-clk-fix-validation-boot.log`):** built with
the real fix in place of `clk_ignore_unused` (still `maxcpus=1`, still no
`mtu3`, as isolation). Result: `clk_disable_unused` runs to completion —
`infra_uart3`/`infra_uart2`/`infra_uart1` disabled and OK, then **`infra_uart0`
is silently skipped** (its `enable_count > 0` now trips the framework's
own "still in use" early-exit before the trace point is even reached), then
`infra_disp_pwm`, `pwm_sel`, `infra_pmic_tmr` disabled OK, and boot continues
uninterrupted through eMMC mount, systemd, `systemd-udevd`,
`systemd-networkd`, `crng init done`, all the way into normal userspace.
**`clk_ignore_unused` is no longer needed.** (Note: capture files in this
session had stray non-UTF8 bytes near the very start from the preloader's
own binary log preamble, which made plain `grep`/`grep -n` silently treat
the whole file as binary and match nothing — use `LC_ALL=C grep -a` on these
raw FTDI logs, not plain `grep`.)

**Status:** one of Phase 4's two remaining workarounds (CLAUDE.md) is now a
real, upstream-quality fix rather than a boot flag. `maxcpus=1` (CPU1 PSCI
hang) remains open — same tracer methodology (targeted instrumentation +
isolate-one-variable-at-a-time builds) should be applied next.

---

## BUILD #71 — fix folded back into production build (USB gadget re-added)

**Goal:** confirm the `8250_mtk.c` clock fix holds with `gemini-usb.config`
(mtu3 gadget) re-enabled, and make this the new baseline —
`configs/gemini-cmdline.config` updated on the Mac-tracked repo to drop
`clk_ignore_unused` for real (previously only a VM-local edit during
diagnostics).

**Build:** clean patch set — removed the diagnostic-only
`clk/0001-GEMINI-DEBUG-...` tracer patch entirely (superseded by the real
fix); all DTS/DRM/GPIO/panel/phy/regulator/pmdomain/serial/usb patches
applied. `gemini-usb.config` merged back in alongside `gemini-cmdline.config`
(cmdline now `console=ttyS0,921600n1 earlycon maxcpus=1 nokaslr` — no
`clk_ignore_unused`). Packed as
`logs/2026-07-06-71-usb-gadget-plus-uart-clk-fix/` (sha256
`c38e176bf18870a17636d66d22081c2e463384f9587c322bd4de2d8fe484d98e`). Verified
pre-flash: banner `#5 SMP PREEMPT Mon Jul 6 06:22:43 UTC 2026`, no
`GEMINI-DEBUG` instrumentation, no display driver strings (headless per
B-13).

**Outcome:** flashed to both `boot` and `boot2`; FTDI capture
(`logs/2026-07-06-72-usb-gadget-plus-uart-clk-fix-boot.log`) shows the
expected UART→USB console mux switch once `mtu3`/the gadget activates
(`u2p_dis_msk` line — per B-15, not a hang). Cable swapped to direct
USB-to-Mac per the documented single-cable-swap protocol; `en12` brought up
with `sudo ifconfig en12 inet 10.15.19.1 netmask 255.255.255.0`; device
reachable at `ssh root@10.15.19.82` (password `toor`). Confirmed over SSH:

- `uname -a`: `Linux gemini 6.6.0-dirty #5 SMP PREEMPT Mon Jul 6 06:22:43 UTC 2026 aarch64`
- `/proc/cmdline`: `console=ttyS0,921600n1 earlycon maxcpus=1 nokaslr` — **no `clk_ignore_unused`**
- `dmesg`: `clk: Disabling unused clocks` at `[0.501525]` followed
  immediately by `Freeing unused kernel memory: 2624K` at `[0.514334]` — no
  hang, no gap (contrast with the original bug, which went silent forever at
  exactly this point)
- Full boot to `graphical.target` in 19.029s total (4.020s kernel +
  15.008s userspace); `usb-gadget.target` reached at `[19.616431]`
- `g_ether` gadget up (`HOST MAC`/`MAC` assigned, `mtu3 ... gadget
  (high-speed) pullup D+`), matching build #53's working RNDIS setup

**Conclusion:** the clock fix and the USB gadget coexist with no
regression. This build supersedes build #53 as the production baseline —
same working SSH-over-USB path, plus the real (non-workaround)
`clk_ignore_unused` fix, plus the display/DRM component-matching code from
Phase 5 (headless; the `GEMINI-DEBUG: engine clk get failed` line from that
work is expected/harmless and unrelated to B-13).
`configs/gemini-cmdline.config` updated on the Mac repo to match. `maxcpus=1`
remains the one open Phase 4 item — same tracer methodology should be
applied next.

---

## PSCI CPU_ON diagnostic — SMP hang isolated to the A72 cluster boundary (2026-07-06)

**Goal:** root-cause the `maxcpus=1` SMP secondary-CPU hang (open since Phase
3, boot.md "SIXTH RESULT") using the same targeted-instrumentation approach
that solved the clk hang, instead of leaving it as a permanent workaround.

**Method:** instrumented `arch/arm64/kernel/psci.c`'s `cpu_psci_cpu_boot()`
with `pr_info` immediately before and after the `psci_ops.cpu_on()` SMC call
(VM-local, not committed — same disposable-tracer pattern as the earlier
`clk/0001-GEMINI-DEBUG-...` patch, reverted once the finding was captured).
Tested incrementally: `maxcpus=2` first (does CPU1 alone still hang?), then
no limit at all (which CPU is the real boundary?).

**maxcpus=2 result** (`logs/2026-07-06-73-psci-cpu1-diag/`,
`logs/2026-07-06-74-psci-cpu1-diag-boot.log`): CPU1 came up cleanly —
`CPU_ON cpu1 returned 0` in under 2ms, `smp: Brought up 1 node, 2 CPUs`, full
boot to userspace, SSH-over-USB confirmed. This contradicts the original
2026-07-04 hang, which stalled dead at exactly `smp: Bringing up secondary
CPUs`. That original hang is now believed to have actually been the same
underlying issue as the `clk_ignore_unused` bug (some other clock cut before
CPU1 could come up), not a genuine CPU1-specific PSCI defect — it was never
isolated from the clk hang at the time, since both bugs were live
simultaneously in the same kernel.

**No-limit result** (`logs/2026-07-06-75-smp-full-diag/`,
`logs/2026-07-06-76-smp-full-diag-boot.log`): CPU0–7 (both Cortex-A53
clusters, mt6797's tri-cluster layout) all bring up cleanly in ~35ms total.
The hang is precisely at **CPU8**, the first core of the third cluster (2x
Cortex-A72 "big" cores):

```
[0.052146] psci: GEMINI-DEBUG: about to CPU_ON cpu8 mpidr=0x200 entry=0x41cbd36c
                                                        (no "returned" line ever prints)
[14.273152] ATF: aee_wdt_dump: on cpu1
[14.284316] Kernel WDT not ready. cpu1
```

The PSCI `CPU_ON` SMC for cpu8 never returns — the boot CPU blocks inside the
SMC instruction itself, i.e. ATF (BL31) firmware hangs, not a Linux-side
defect. (The aee dump reports "cpu1" because that's whichever core services
the watchdog dump, not the core that's actually stuck.)

**Root cause hypothesis:** this lines up with B-13 (Phase 5's blocker) —
upstream `mtk-scpsys.c` has an MT6797 domain-table bug that breaks shared
power domains (`mtk-scpsys: probe of 10006000.power-controller failed`,
already observed in Phase 4 driver init). The A72 cluster's power domain
almost certainly needs to be enabled via SCPSYS before ATF's `CPU_ON` can
proceed; since that domain never gets enabled, the SMC blocks forever waiting
on a power rail that never comes up. Both the SMP hang and the display
blocker trace back to the same upstream driver bug.

**Instrumentation disposition:** reverted from both trees after capturing
the finding (`git checkout -- arch/arm64/kernel/psci.c` on Mac and VM) — not
kept as a permanent patch, consistent with how the clk tracer was handled.

---

## BUILD — `maxcpus=8`: full A53 SMP without requiring the B-13 fix (2026-07-06)

**Goal:** given the SMP hang is isolated to the A72 cluster (cpu8/9), boot
with all 8 A53 cores instead of the previous single-core workaround —
recovers 8x the CPU capacity without needing B-13 fixed first.

**Build:** `configs/gemini-cmdline.config` changed from `maxcpus=1` to
`maxcpus=8`. Packed as `logs/2026-07-06-77-maxcpus8/new_kali_boot.img` (sha256
`4643f685358efdaca7db5ac12e5ab8721f35c081ece18821801b8de46dc28078`).

**Outcome:** flashed to `boot` + `boot2`; FTDI capture
(`logs/2026-07-06-78-maxcpus8-boot.log`) shows the expected mtu3 mux-switch
point with no earlier hang. Cable swapped to direct USB; confirmed over SSH
(`root@10.15.19.82`):

- `/proc/cmdline`: `console=ttyS0,921600n1 earlycon maxcpus=8 nokaslr`
- `cat /sys/devices/system/cpu/online`: `0-7`
- `dmesg`: `smp: Brought up 1 node, 8 CPUs` / `SMP: Total of 8 processors
  activated.`
- `systemctl is-system-running`: `running`

**Conclusion:** `maxcpus=8` is the new baseline, superseding `maxcpus=1`.
Full 10-core SMP (bringing up the A72 cluster) is blocked on the same
upstream `mtk-scpsys.c` MT6797 domain-table fix as Phase 5 display (B-13) —
tracked there rather than as a separate Phase 4 item.

## BUILD #79 — B-13 domain-table fix re-tested with display enabled: hang moved later, not resolved (2026-07-06)

**Goal:** re-test `patches/v6.6/pmdomain/0001-pmdomain-mediatek-skip-unpopulated-mt6797-domain-slots.patch`
(committed 2026-07-04 but never actually flash-tested with the display
fragment enabled) now that it exists, since blockers.md B-13 hypothesized it
as the "safe workaround" fix path. `configs/gemini-display.config` (the B-13
guard on `gemini-display.config.disabled-b13`) was re-enabled and
`scripts/build-pack.sh`'s hard-coded "drop the display fragment" guard and
"display driver must be absent" verification check were removed, since B-13
was believed fixed.

**Build:** kernel #10, packed as
`logs/2026-07-06-79-scpsys-b13-fix/new_kali_boot.img` (sha256
`0e44900c02540b529e24d145314af319ce9d43c9775b6b35f02e68a097f7193a`). DTB
confirmed to contain `disp-ovl0@1400b000` and the rest of the display chain
(note: DT node names use hyphens, `disp-ovl0`, not the underscore form used in
earlier grep attempts).

**Outcome:** flashed to `boot` + `boot2`
(`logs/2026-07-06-80-scpsys-b13-fix-boot.log`). Boot progressed one step
further than the original 2026-07-05 B-13 discovery (TENTH RESULT) — now
reaching:

```
[    0.366538] mediatek-drm mediatek-drm.1.auto: Adding component match for /disp-ovl0@1400b000
...
[    0.373350] platform 14017000.disp-od0: error -2 can't parse gce-client-reg property (0)
[    0.374423] platform 14018000.disp-dither0: error -2 can't parse gce-client-reg property (0)
[    0.376247] mipi-dsi 1401c000.dsi.0: Fixed dependency cycle(s) with /dsi@1401c000/port/endpoint
[    0.379044] panel-renesas-r63419 1401c000.dsi.0: Renesas R63419 WQHD DSI panel registered
```

— but then hard-hangs with no further kernel output. The board then entered
a genuine watchdog-driven reboot loop: FTDI capture caught the preloader
banner repeating 5 times in a row, each cycle reaching the identical
`panel-renesas-r63419 ... registered` line before dying. One cycle produced
an ATF `aee_wdt_dump`, symbolicated against this build's `System.map`:

```
[ATF](1)[14.487066]aee_wdt_dump: on cpu1
[ATF](1)[14.487523](1) pc:<ffff800081099d18> lr:<ffff800081099d2c> ...
```

`ffff800081099d18` falls inside `cpu_do_idle`/`arch_cpu_idle`
(`System.map`: `ffff800081099d10 T cpu_do_idle`) — CPU1 was legitimately idle
when the dump fired. The `inter-cpu-call interrupt is triggered` lines for
every other CPU immediately before it are ATF's own IPI broadcast used to
collect a whole-system crash dump once *some* CPU's watchdog trips, not
evidence that CPU1 itself is the stuck core. The actual hang is presumed to
still be on whichever CPU is running the boot thread (CPU0), inside the
MM-domain power-on register access — consistent with B-13's original
hard-hang description, just a little later in the sequence than the
2026-07-05 test (which hung before any component-match printk at all).

**Recovery:** device did not self-recover from the loop. Re-flashed both
`boot` and `boot2` with the known-good `logs/2026-07-06-77-maxcpus8/new_kali_boot.img`
(build #8, no display, `maxcpus=8`). First re-flash attempt appeared to not
take (capture still showed build #10's banner and the same hang/loop
signature) — a second attempt succeeded: capture showed build #8's banner,
boot proceeded past the point build #10 hung at, mtu3 initialized, and the
device was confirmed reachable over SSH-over-USB (`root@10.15.19.82`,
`systemctl is-system-running` = `running`, `cpu/online` = `0-7`). Lesson: do
not assume an `mtk w` flash succeeded from the command having been run —
verify with a fresh capture showing the expected kernel banner before relying
on the device being recovered.

**Conclusion:** the `init_scp()`/`mtk_register_power_domains()` NULL-name
skip fix is necessary but not sufficient — it stops the scpsys *driver probe*
from aborting on the sparse MT6797 domain table, and does measurably move
the boot further (component-match/panel registration now happens, which
didn't happen at all before), but something in the actual MM domain power-on
sequence (or a downstream consumer's first register access once the domain
claims to be live) still wedges the bus. B-13 remains open. `gemini-display.config`
is left enabled in the repo (the fix is real progress and worth keeping
patched in), but is not yet safe to rely on for a stable boot — the
`build-pack.sh` verification step no longer blocks on the display driver's
presence, so future iterations should manually confirm the outcome on
hardware before treating a display build as safe to leave flashed.

---

## BUILD #11 — scpsys fix does not affect the CPU8 PSCI hang; A72 cluster bring-up is a separate blocker (2026-07-06)

**Goal:** after BUILD #79 showed the scpsys NULL-name skip fix wasn't
sufficient for display, re-test the same fix in isolation against the other
half of the original B-13 hypothesis — the CPU8 (first Cortex-A72 core)
PSCI `CPU_ON` hang documented in "PSCI CPU_ON diagnostic" above. That entry
speculated the A72 cluster's power domain was gated by the same scpsys bug.
Built with the scpsys fix applied (as always, it's a committed patch),
display fragment excluded (to isolate the variable), and the `maxcpus=8`
cmdline cap temporarily removed so all 10 cores attempt bring-up. Packed as
`logs/2026-07-06-82-cpu8-scpsys-retest/new_kali_boot.img` (kernel #11, sha256
`4fd0920af2c2da4301d1d147a1a25c8025e7e71e8f304155170e189fa969a29e`).

**Before building, checked the actual MT6797 scpsys domain table**
(`drivers/pmdomain/mediatek/mtk-scpsys.c`, `scp_domain_data_mt6797[]`): it
only defines `VDEC`, `VENC`, `ISP`, `MM`, `AUDIO`, `MFG_ASYNC`, `MJC` — there
is no CPU-cluster/MP power-domain entry at all. This means the A72 cluster's
power-on was never gated by the scpsys probe-abort bug in the first place;
the original hypothesis linking the CPU8 hang to B-13 rested only on both
symptoms sharing a hand-wavy "power domain" explanation, not on any code path
connecting them.

**Result** (`logs/2026-07-06-83-cpu8-scpsys-retest-boot.log`, 8 reboot cycles
captured): identical signature to the pre-fix "PSCI CPU_ON diagnostic"
finding, byte-for-byte —
```
[    0.017141] smp: Bringing up secondary CPUs ...
                                    (14s of silence)
[ATF](1)[14.361720]aee_wdt_dump: on cpu1
[ATF](1)[14.372887]Kernel WDT not ready. cpu1
```
followed by a watchdog reboot. The scpsys fix made no observable difference.

**Conclusion:** the CPU8 PSCI `CPU_ON` hang is a **separate blocker from
B-13**, not the same root cause. It's an ATF (BL31)-side hang specific to
bringing up the Cortex-A72 cluster, and — per the domain-table check above —
not something the Linux `mtk-scpsys` driver has any code path to influence.
Whatever gates the A72 cluster's power/clock (MCUCFG, a separate SPM
sequence, or something ATF-internal not exposed to Linux at all) is unknown
and needs its own investigation; it should not be assumed fixed alongside
B-13. Recovered to the known-good `maxcpus=8` build
(`logs/2026-07-06-77-maxcpus8/`, sha256
`4643f685358efdaca7db5ac12e5ab8721f35c081ece18821801b8de46dc28078`) — second
flash attempt succeeded, verified via banner (`#8 SMP PREEMPT`,
`logs/2026-07-06-84-recovery-boot.log`) and a live SSH session
(`systemctl is-system-running` = `running`, `cpu/online` = `0-7`).

---

## B-16 research pass — vendor Debian/Halium kernel strings reveal named A72 hotplug subsystem (2026-07-06)

**Goal:** with B-16 (CPU8 PSCI `CPU_ON` hang) marked "root cause unknown,
possibly ATF-internal," look for any available vendor-side evidence before
giving up on it being fixable from Linux. The 3.18 vendor kernel source
(`~/gemini-kernel`) that would normally be the first place to check no longer
exists on this machine (deleted with the pre-2026-06-10 build VM). The user
separately downloaded a Planet Computers Gemini "Debian" firmware release
(`debian_boot.img` + `linux.img`, ~3.8 GB total) to
`/Volumes/extdata/scratch/debian/` (outside this repo) as a possible
alternative source of vendor evidence.

**Method (read-only extraction, no code changes):** `debian_boot.img` is a
standard Android bootimg, same format as our own `kali_boot.img`/build
outputs — unpacked with a one-off Python script (page-size-aware header
parse) to pull the kernel blob and ramdisk. The kernel blob decompresses
(`zlib`, 31-window) to a 3.18.41 kernel (`Linux version 3.18.41+
(dguidi@nowhere) ... #7 SMP PREEMPT Fri Mar 29 10:39:03 GMT 2019`), with a DTB
appended after the gzip stream (`zlib.decompressobj.unused_data`) — decompiles
cleanly with `dtc`, confirming the same MT6797/`mt6351` PMIC/`bq24261`
charger platform. Ramdisk (`cpio`) is a Halium-style "Mer Boat Loader" init,
same architecture as our own known-good ramdisk — no kernel modules (`.ko`)
present, so the kernel is monolithic and all driver code (and its debug
strings) is baked into the single decompressed kernel binary.

**This build's kernel was compiled with debug info retaining full source
paths** (`/home/dguidi/Desktop/Kernel/kernel-3.18/drivers/...`), recovered via
plain `strings -n 8` on the decompressed kernel — this is the only vendor
"source" evidence available (no actual `.c` file contents, just paths and
adjacent log-format strings compiled into the binary).

**Panel check (ruled out a false lead):** this vendor build's only compiled-in
LCM driver is `aeon_nt36672_fhd_dsi_vdo_x600_xinli` (Novatek NT36672), not the
Renesas R63419 our Phase 5 work targets. Checked against our own vendor DTB
(`docs/vendor-dtb/gemini_kali_boot.dts`, extracted from **this specific
device's own flash**, not this generic community image) — it explicitly
declares `lcm_params-r63419_wqhd_truly_phantom_2k_cmd_ok` and
`atag,videolfb-lcmname = "r63419_wqhd_truly_phantom_2k_cmd_ok"`. So R63419 is
confirmed correct for our hardware; the Debian image's NT36672 driver is for
a different Gemini panel revision/variant. Not a correction to our patches —
noted here so this isn't re-litigated later.

**A72 cluster finding:** see blockers.md B-16 for the full writeup. In short,
`strings` on the decompressed kernel reveals an entire vendor subsystem for
A72 cluster power sequencing that has no mainline (or our) equivalent:
`mt_hotplug_strategy_*.c` (load-based online/offline governor, not
unconditional boot-time bring-up), `mt_idvfs.c` (SRAM LDO + PLL setup over
I2C6, log strings confirm it's a hard precondition — `"FAILED TO PREPARE I2C
CLOCK... iDVFS only 750MHz"`), `mt_cpufreq{,_hybrid}.c`, and a CPU-HVFS
hardware sequencer kicked via a `swctrl` register
(`"[CPUHVFS] (%u) [%08x] cluster%u on, pause = 0x%x, swctrl = 0x%x (0x%x)"`,
`cspm_cluster_notify_on`). None of this exists in mainline's `mt6797.dtsi` or
our `mt6797-gemini-pda.dts` (previously confirmed by grep in the "PSCI CPU_ON
diagnostic" entry above).

**Conclusion:** B-16's status moves from "root cause unknown, maybe
unfixable without vendor ATF source" to "root cause narrowed — ATF's
`CPU_ON` for the A72 cluster plausibly blocks waiting on a voltage/PLL
precondition that vendor Linux drives via `mt_idvfs`/CPU-HVFS and our kernel
never touches." Still unconfirmed at the register level — no actual
addresses or I2C/PMIC-wrap sequence were extracted, only the log-string
evidence that these subsystems exist and gate cluster power-on. No code
changes made or planned yet; next step (if pursued) is register-level detail
via the vendor DTB's existing `mcucfg`/`ptp3_idvfs` nodes
(`docs/vendor-dtb/gemini_kali_boot.dts`) and/or further binary analysis of the
Debian kernel image before writing any kernel-side sequencing patch.

**WiFi/display cross-check (same vendor kernel binary, same method):** no new
findings that change existing project conclusions — both corroborate what
hardware.md/research.md already document.

- **WiFi:** confirmed integrated AHB hard-IP (`mediatek,mt6797-consys`
  compatible, `consys@18070000`/`wifi@180f0000` in the vendor DTB;
  `wmt_ic_soc.c`/`wmt_plat_alps.c` source paths, not an SDIO combo-chip
  driver), matching hardware.md's row 34 "AHB bus (not SDIO)" finding.
  `mt6631`-prefixed strings turned out to be the **FM radio** tuner path
  (`[FM_ALT | CHIP] mt6631_tune`), not WiFi — a separate chip/subsystem, not
  a correction to the WiFi architecture finding. No new mainline-portability
  information beyond what research.md already has (~75–103 KLOC vendor
  stack, last working out-of-tree port at kernel 5.6).
- **Display:** vendor stack confirmed to be MediaTek's proprietary "DDP"
  (`drivers/misc/mediatek/video/mt6797/dispsys/ddp_*.c`,
  `videox/primary_display.c`) plus a **CMDQ v2** command-queue engine
  (`drivers/misc/mediatek/cmdq/v2/{cmdq_core,cmdq_driver,mt6797/cmdq_mdp}.c`)
  — architecturally unrelated to mainline's GCE mailbox+cmdq binding (the
  MT8173-and-later `gce-client-reg` DT scheme our BUILD #79 hang partially
  exercised: `"error -2 can't parse gce-client-reg property"`). This is
  consistent with — not a new explanation of — B-13: MT6797 never had a GCE
  mailbox controller design, so there's no vendor reference implementation of
  the binding mainline's `mediatek-drm` expects; a real port needs new
  MT6797-specific DDP/CMDQ-aware code, matching hardware.md row 135's
  existing conclusion that four mainline files need new MT6797 variants.
  Panel identity (R63419) reconfirmed correct for this hardware, as above.

---

## BUILD #81/#82 — second-infracfg-block hypothesis for B-13, tested and falsified (2026-07-06)

Same read-only vendor-DTB analysis above turned up a concrete register-level
lead for B-13: the vendor DTB shows MT6797 has two separate infracfg blocks
(`infracfg_ao@10001000`, matching mainline's sole `infrasys` node, plus a
second `infracfg@10201000` the vendor's own `scpsys` node also spans).
Hypothesis: mainline's `scpsys` phandle points bus-protection register
writes (`INFRA_TOPAXI_PROTECTEN` etc.) at the wrong block.

Build #81 (`patches/v6.6/dts/0010-arm64-dts-mediatek-add-mt6797-real-infracfg-node.patch`)
added a plain-`syscon` node for the second block and repointed `scpsys`'s
`infracfg` phandle at it. Also folded in a cleanup: patch 0004's
`GEMINI-DEBUG` diagnostic prints (tagged "remove once B-15 is resolved" —
B-15 has been resolved since earlier the same day) were removed, regenerating
the patch from a clean VM tree diff rather than hand-editing hunk headers.

Flash-tested (capture `logs/2026-07-06-82-scpsys-b13-real-infracfg-boot.log`,
image/`.config`/sha256 in `logs/2026-07-06-81-scpsys-b13-real-infracfg/`):
**no behavioural change.** Boot reaches the identical point as the untested
build #79 —

```
[    0.380807] panel-renesas-r63419 1401c000.dsi.0: Renesas R63419 WQHD DSI panel registered
```

— then hard-hangs with the same ATF watchdog signature (`aee_wdt_dump: on
cpu1` at 14.2s, `on cpu3` at 18.1s, then silence; same red-herring
inter-cpu-call IPI broadcast pattern as build #79, not evidence of which CPU
is actually stuck).

**Conclusion:** the second-infracfg-block hypothesis is not confirmed by
this test. Either it's the wrong block for bus protection specifically (the
vendor DTB's three regions on one `scpsys` node don't prove all three feed
the bus-protection sub-function), or bus protection was never the actual
hang cause and the real stall is inside `scpsys_power_on()`'s SRAM/power-on
register sequencing itself, now provably reached (given the panel registers
successfully) but stalling somewhere past that point. Full writeup in
blockers.md B-13. Patch 0010 is retained (harmless, still directionally
justified) but does not close B-13; DTS-only guessing is not a productive
next step — register-level instrumentation of the actual `scpsys_power_on`/
`scpsys_bus_protect_enable` code path is.

Device was left in the hung/watchdog-loop state after this test; recovery to
the known-good `maxcpus=8`, no-display build (`logs/2026-07-06-77-maxcpus8/`)
is required before further work, per the same recovery procedure used after
build #79.

## BUILD #84/#85 — scpsys power-on per-step trace: scpsys EXONERATED, hang is in DRM bind (2026-07-06)

**Build:** #84 `scpsys-b13-step-trace` — identical display-enabled config to
build #81 plus temporary instrumentation patch
`patches/v6.6/pmdomain/0002-GEMINI-DEBUG-scpsys-power-on-step-trace.patch`
(`dev_info` before every step of `scpsys_power_on()`). Provenance:
`logs/2026-07-06-84-scpsys-b13-step-trace/` (image sha256
`f1c74d61e530fc...`, banner `#14 SMP PREEMPT Mon Jul  6 08:45:36 UTC 2026`).
Flashed to both `boot` and `boot2` (first flash attempt didn't take — the
first boot captured in the log below is the old recovery build `#8`; the
second boot in the same file is the real test, banner `#14 ... -dirty`).

**Capture:** `logs/2026-07-06-85-scpsys-b13-step-trace-boot.log` (two boots
in one file).

**Result:** every power domain — vdec, venc, isp, **mm**, audio, mfg_async,
mjc — completes ALL power-on steps cleanly: regulator, clk_enable, PWR_ON
write, PWR_ACK poll, CLK_DIS/ISO/RST_B, sram_enable, bus_protect_disable,
done. MM finishes at 0.3548s. MM's ctl register read `0xe0d` before the
kernel wrote anything — PWR_ACK already set: **the vendor LK bootloader
leaves the MM domain powered for its splash**, so the kernel's MM power-on
rides an already-live domain.

**Conclusion:** the display hang is NOT in `scpsys_power_on()` /
bus-protection / SRAM sequencing. The last line is still
`panel-renesas-r63419 1401c000.dsi.0: ... registered` (0.4569s) followed by
the ATF watchdog dump — that is the point where the final component match
completes and the mediatek-drm component master binds. The stall is inside
the DRM bind path: first real register access to the 0x14xxxxxx mmsys range
(mmsys routing writes / ddp comp init), or a clock/SMI dependency of it.
Side-finding: the DTS declares `mediatek,mt6797-smi-larb`/`-common` but no
driver implements those compatibles (upstream mtk-smi.c has no MT6797
support; nothing SMI probes in any log). Next: per-step trace of
`mtk_drm_bind()` / `mtk_drm_kms_init()` / `mtk_mmsys_ddp_connect()`.
See blockers.md B-13 update of the same date. Device left hung; needs the
standard recovery reflash of `logs/2026-07-06-77-maxcpus8/`.

## BUILD #86/#87 — DRM bind step trace: bind never entered, hang pinned to mtk_dsi_probe tail (2026-07-06)

**Build:** #86 `drm-bind-step-trace` (`logs/2026-07-06-86-drm-bind-step-trace/`,
banner `#15 SMP PREEMPT Mon Jul  6 08:57:13 UTC 2026`, temporary patch
`patches/v6.6/drm/0005-GEMINI-DEBUG-drm-bind-step-trace.patch` bracketing
`mtk_drm_bind()`/`mtk_drm_kms_init()`). Flashed to both `boot` and `boot2`.
**Capture:** `logs/2026-07-06-87-drm-bind-step-trace-boot.log`.

**Result:** banner matches; boot identical to #82/#85 — last line
`panel-renesas-r63419 ... registered` (0.4486s) then ATF watchdog. **None of
the bind/kms_init trace lines printed**, so the component master bind never
even started. Two decisive deductions:

1. The panel driver prints "registered" only *after* `mipi_dsi_attach()`
   returns, so DSI attach / component_add / any synchronous bind attempt has
   already completed by that point. The hang window is therefore the
   remainder of `mtk_dsi_probe()` after `mipi_dsi_host_register()` returns:
   clk_get engine/digital/hs → ioremap → devm_phy_get →
   **devm_request_irq**.
2. The ATF dump's `pc:<ffff800081099f18>` resolves against this build's
   System.map to `cpu_do_idle+0x8` (lr `arch_cpu_idle+0x10`) — the dumped
   CPU (cpu1) was idle. cpu0, running the probe, never produced a dump: it
   is the wedged CPU (cpu4's dump at 18.4s cut off at device reset).

**Hypothesis for #88:** `devm_request_irq` unmasks the DSI interrupt while
the vendor LK bootloader has left the DSI engine live (splash). A stale or
screaming DSI interrupt then wedges cpu0 inside `mtk_dsi_irq()`, which does
`readl(DSI_INTSTA)` with no clock guaranteed and spins unbounded on
`while (tmp & DSI_BUSY)`. Build #88 `dsi-probe-tail-trace`
(`logs/2026-07-06-88-dsi-probe-tail-trace/`, banner `#16 ... 09:03:57`,
patch `patches/v6.6/drm/0006-GEMINI-DEBUG-dsi-probe-tail-and-irq-trace.patch`)
brackets each probe-tail step and adds ratelimited entry markers in
`mtk_dsi_irq()`.

## BUILD #88/#89 — dsi probe tail CLEAN, IRQ-storm hypothesis refuted; wedge is outside the display stack (2026-07-06)

- Build: `logs/2026-07-06-88-dsi-probe-tail-trace/` (banner
  `#16 SMP PREEMPT Mon Jul 6 09:03:57 UTC 2026`), flashed to both `boot`
  and `boot2`. Capture: `logs/2026-07-06-89-dsi-probe-tail-trace-boot.log`
  (banner verified).
- Result — every probe-tail step completes:
  - `dsi_probe: host registered, clk_get engine` → `clks ok, ioremap` →
    `ioremap ok, phy_get` → `phy ok, request_irq 15` → `irq ok, probe
    complete` (0.4466–0.4507s).
  - The DSI interrupt fires exactly ONCE: `mtk_dsi_irq: entry (pre-readl)`
    then `mtk_dsi_irq: INTSTA=0x2` (CMD_DONE_INT_FLAG) — read succeeds, no
    storm, no repeat, handler returns. The unclocked-readl/screaming-IRQ
    hypothesis from #86/#87 is refuted.
  - `panel-renesas-r63419 ... registered` at 0.4533s, then total silence
    until ATF `aee_wdt_dump` at 14.16s and device reset.
- Key ordering insight: `mipi_dsi_attach()` (line 398 in the panel driver,
  before the 405 dev_info) calls `mtk_dsi_host_attach()` →
  `devm_drm_of_get_bridge` + `drm_bridge_add` + `component_add` — i.e. the
  DRM master bind attempt happened and returned (deferred, no IOMMU on the
  platform bus) BEFORE the panel print appeared. The entire synchronous
  display path — scpsys (#84), DRM bind (#86), dsi probe tail + IRQ (#88) —
  is now exonerated.
- ATF dump again shows only idle bystanders: cpu1
  pc `ffff80008109afd8` = `cpu_do_idle+0x8` (resolved against this build's
  System.map). cpu0 never dumps → cpu0 wedged with IRQs masked, ~50ms after
  the panel print, in code with no markers.
- Next: build #90 `initcall-debug-b13`
  (`logs/2026-07-06-90-initcall-debug-b13/`, banner `#17 ... 09:11:35`) adds
  `initcall_debug` to CONFIG_CMDLINE (see gemini-cmdline.config comment) —
  the last `calling <fn>` line in the capture will name the wedging
  function directly, no more driver-by-driver guessing.

## BUILD #90–#93 — initcall_debug: wedging initcall is cacheinfo_sysfs_init, NOT display code (2026-07-06)

- Build #90 `initcall-debug-b13` (`logs/2026-07-06-90-initcall-debug-b13/`,
  banner `#17 ... 09:11:35`): added `initcall_debug` to CONFIG_CMDLINE.
  Capture `logs/2026-07-06-91-initcall-debug-b13-boot.log` — flag confirmed
  on the kernel command line but ZERO "calling" lines: initcall_debug prints
  at KERN_DEBUG, suppressed by the default console loglevel. One new datum:
  cpu0 began an ATF dump at 18.2s (first time ever) but the capture cut off
  at the header before the registers.
- Build #92 `initcall-debug-loglevel` (`logs/2026-07-06-92-initcall-debug-loglevel/`,
  banner `#18 ... 09:15:36`): added `ignore_loglevel`. Capture
  `logs/2026-07-06-93-initcall-debug-loglevel-boot.log` — DECISIVE:
  - The entire display path completes and RETURNS:
    `probe of 1401c000.dsi.0 returned 0 after 1683 usecs`,
    `initcall r63419_driver_init returned 0 after 2476 usecs`.
  - `topology_sysfs_init` returns 0.
  - Last kernel line: `[2.423287] calling cacheinfo_sysfs_init+0x0/0x40 @ 1`
    — then silence until ATF `aee_wdt_dump` at 14.2s (cpu1 idle again:
    pc = `cpu_do_idle+0x8`).
- Interpretation: `cacheinfo_sysfs_init` →
  `cpuhp_setup_state(CPUHP_AP_BASE_CACHEINFO_ONLINE, ...)` runs
  `cacheinfo_cpu_online()` on EVERY online CPU via that CPU's hotplug
  thread, waiting for each in turn. cpu0 isn't the culprit — it's blocked
  waiting on a secondary CPU whose hotplug thread never responds. Something
  the display build does earlier (scpsys domain writes / display clk
  enables are the obvious candidates) silently wedges a secondary CPU
  before 2.4s. This retro-explains builds #86/#88: the "hang after panel
  registered" was always this initcall, running silently a few ms later.
- Next: build #94 `cacheinfo-cpuhp-trace`
  (`logs/2026-07-06-94-cacheinfo-cpuhp-trace/`, banner `#19 ... 09:21:26`,
  patch `patches/v6.6/base/0001-GEMINI-DEBUG-cacheinfo-cpuhp-per-cpu-trace.patch`)
  prints enter/exit per CPU in `cacheinfo_cpu_online()` to identify which
  CPU wedges, plus `rcupdate.rcu_cpu_stall_timeout=6` so RCU names the
  stuck CPU with a backtrace before the ~12s ATF watchdog.

## BUILD #94/#95 — RCU names the wedged CPU: it is cpu0 itself, unresponsive to IRQs (2026-07-06)

**Build:** #94 `cacheinfo-cpuhp-trace` — banner `#19 SMP PREEMPT Mon Jul 6 09:21:26 UTC 2026`
(verified in capture). Provenance `logs/2026-07-06-94-cacheinfo-cpuhp-trace/`.
Adds `patches/v6.6/base/0001-GEMINI-DEBUG-cacheinfo-cpuhp-per-cpu-trace.patch`
(enter/exit prints in `cacheinfo_cpu_online()`) and
`rcupdate.rcu_cpu_stall_timeout=6` on the cmdline.
**Capture:** `logs/2026-07-06-95-cacheinfo-cpuhp-trace-boot.log` (both `boot`
and `boot2` flashed with `mtk w`).

**Result — the "unresponsive secondary CPU" hypothesis is REFUTED; the wedged
CPU is cpu0 itself:**

- Wedge point identical to #93: last initcall line is
  `[2.423697] calling cacheinfo_sysfs_init+0x0/0x40 @ 1`.
- **Not one** `GEMINI-DEBUG cacheinfo_cpu_online` print appears — not even
  cpu0's `enter`. The strings are confirmed present in the packed kernel
  (zlib-scanned the boot.img), so the hang is inside `cpuhp_setup_state()`
  *before the first per-CPU callback runs*: init blocks waiting for the
  `cpuhp/0` thread, which is pinned to cpu0 — and cpu0 never runs it.
- **RCU stall report fired at 8.42s** (the new 6s timeout works, well before
  the ~14s ATF watchdog): `rcu: INFO: rcu_preempt detected stalls on
  CPUs/tasks: 0-...0: (1 GPs behind) idle=0a1c/1/0x4000000000000002
  softirq=29/31 fqs=750 (detected by 4, t=1502 jiffies)`. **cpu0 is the
  stalled CPU, detected by cpu4** — cpu4 (and the rest of the system) is
  alive and healthy at 8.4s. RCU's 750 forced-quiescent-state attempts on
  cpu0 all failed → cpu0 is not taking interrupts.
- The remote task dump for cpu0 is useless (`swapper/0 running`,
  `__switch_to+0xdc` then `0x0`) — arm64 has no NMI by default, so a stack
  trace of a running remote CPU can't be taken.
- ATF dump: cpu1 first (`pc ffff80008109af98` = `cpu_do_idle+0x8`, idle
  bystander again), cpu4 dump header at 18.38s truncated by reset. The
  earlier dumps "on cpu1"/"on cpu6"/"on cpu4" across builds are just
  whichever CPU services ATF's broadcast — not the culprit.

**Interpretation:** in display-enabled builds, cpu0 stops responding to
interrupts at ~2.42s, right as init hands work to `cpuhp/0` and cpu0 should
wake from idle. Everything before that (scpsys domain power-ons at
2.08–2.12s, all display probes, all initcalls) completes on time. cpus 1–7
stay healthy indefinitely. So the defect is something that kills interrupt
delivery/wakeup specifically for cpu0 — GIC redistributor for cpu0, cpu0's
arch timer, or a lost wakeup — plausibly a side effect of the scpsys
power-domain writes (wrong MT6797 bus-protect bits are the known B-13 bug)
or a display clock parent/gate change.

**Next (build #96, banner `#20 SMP PREEMPT Mon Jul 6 09:35:24 UTC 2026`):**
GIC is v3 (`arm,gic-v3` in mt6797.dtsi), so pseudo-NMI can interrupt cpu0
even with IRQs masked. `CONFIG_ARM64_PSEUDO_NMI=y`
(`configs/gemini-debug-b13.config`, TEMPORARY) +
`irqchip.gicv3_pseudo_nmi=1` on the cmdline → the RCU stall handler can
NMI-backtrace cpu0 and show its real PC. Provenance
`logs/2026-07-06-96-pseudo-nmi-cpu0-backtrace/`.

## BUILD #96/#97 — pseudo-NMI REVERTED: broke boot earlier than the bug it was meant to diagnose (2026-07-06)

**Build:** #96 `pseudo-nmi-cpu0-backtrace` — banner `#20 SMP PREEMPT Mon Jul 6
09:35:24 UTC 2026` (confirmed in `logs/2026-07-06-96-pseudo-nmi-cpu0-backtrace/config`:
`CONFIG_ARM64_PSEUDO_NMI=y`). Added `irqchip.gicv3_pseudo_nmi=1` to the
cmdline, intending to let the RCU stall handler NMI-backtrace cpu0 (which
build #94/#95 identified as the wedged CPU).

**Capture:** `logs/2026-07-06-97-pseudo-nmi-cpu0-backtrace-boot.log`.

**Result — regression, reverted:**

- After `el3_exit` at `[ATF](0)[4.373587]`, **total silence** until the ATF
  watchdog fires at `14.377204` — no earlycon banner, no `Linux version`
  line, nothing. Every prior build (going back to Phase 3) printed the full
  earlycon log within milliseconds of `el3_exit`; this is a strictly worse
  and earlier failure than the 2.42s `cacheinfo_sysfs_init` hang this change
  was meant to diagnose.
- cpu1's ATF register dump is the same idle bystander as always:
  `pc:<ffff8000810a1358>` = `cpu_do_idle+0x48`, `lr` = `arch_cpu_idle+0x10`
  (symbolicated against `logs/2026-07-06-96-pseudo-nmi-cpu0-backtrace/System.map`).
  No new information from ATF.
- The capture also shows a second preloader/LK cycle (device watchdog-reset
  after the first hang) whose LK splash sequence (DDP overlay init,
  `SSD2092` LCM i2c writes, framebuffer fill) is what the user saw on-screen
  as "garbage" — this is the vendor LK bootloader's own splash draw,
  unrelated to our kernel/DRM work (same caveat as the Phase 5 status note).
  The second cycle's own `cmdline:` LK diagnostic print
  (`androidboot.hardware=mt6797 ... console=ttyMT0,921600n1 ...`) is LK's
  record of the boot-image header cmdline, not evidence of booting the stock
  `boot` partition — both `boot` and `boot2` were flashed with the same
  #96 image per protocol.
- **Interpretation:** `CONFIG_ARM64_PSEUDO_NMI` + `gicv3_pseudo_nmi=1`
  configure GICv3 priority-mask-based IRQ disabling very early — before UART
  console/earlycon setup — and this device's ATF/GIC combination does not
  tolerate it (likely traps or hangs on the `ICC_PMR_EL1`/`ICC_CTLR_EL3`
  priority setup). **Reverted**: removed
  `configs/gemini-debug-b13.config` and the `irqchip.gicv3_pseudo_nmi=1`
  cmdline flag (see `configs/gemini-cmdline.config` comment). Do not retry
  pseudo-NMI without independently validating ATF support first.

**Next:** abandon NMI-based backtracing of cpu0. Instead, add a heartbeat
probe: a kthread pinned to a healthy CPU (e.g. cpu1) that calls
`smp_call_function_single(0, ping, NULL, 1)` on a timer (~50ms) starting
from an early initcall, printing ok/timeout with a timestamp each time. This
uses the existing (working, cpu1-7 healthy) IPI/scheduler mechanism instead
of touching NMI/GIC priority masking, and will pinpoint the exact moment
cpu0 stops acking IPIs relative to the already-known scpsys domain-power
writes (2.08–2.12s) and display probes (2.39–2.42s).

## BUILD #98/#99 — IPI heartbeat pinpoints cpu0's death to a 60ms window inside cacheinfo_sysfs_init (2026-07-06)

**Build:** #98 `cpu0-ipi-heartbeat` — banner `#21 SMP PREEMPT Mon Jul 6
09:44:43 UTC 2026`. Adds `patches/v6.6/smp/0001-GEMINI-DEBUG-cpu0-ipi-heartbeat-probe.patch`:
a kthread pinned to cpu1 pings cpu0 every 50ms via non-blocking
`smp_call_function_single` and logs ok/MISS with jiffies. Pseudo-NMI
artifacts (`configs/gemini-debug-b13.config`, `irqchip.gicv3_pseudo_nmi=1`)
fully reverted per build #96/#97.

**Capture:** `logs/2026-07-06-99-cpu0-ipi-heartbeat-boot.log` (both `boot`
and `boot2` flashed). No LK splash garbage observed on screen this attempt
(unlike #96/#97) — expected: that garbage was the vendor LK bootsplash on a
watchdog-triggered *second* boot cycle, which does not always get far enough
to draw before the capture/observation window ends; its presence or absence
is incidental to our kernel work, not a regression signal.

**Result — decisive timing, new mechanism-level conclusion:**

```
[2.479900] GEMINI-DEBUG cpu0 heartbeat ok at jiffies=4294892899 (seq=30)
[2.539896] GEMINI-DEBUG cpu0 heartbeat MISS #1 at jiffies=4294892914 (sent=31 seen=30)
```

- 30 consecutive clean heartbeats from 0.72s to 2.48s (every ~60ms including
  scheduling overhead), then failure by 2.54s. cpu0's death window is
  **~2.48s–2.54s**, landing squarely inside `cacheinfo_sysfs_init`, which was
  called at 2.4237s (build #93's `initcall_debug` trace) — cpu0 is
  demonstrably alive and IPI-responsive well after that initcall starts, so
  the hang is not immediate.
- **Mechanism-level conclusion**: `cacheinfo_cpu_online()`'s own `enter
  cpu0`/`exit cpu0` trace prints (added in build #94) never fired despite the
  strings being confirmed present in the binary — yet this heartbeat's
  completely different IPI mechanism (generic `smp_call_function_single`,
  not the `cpuhp/0` thread wakeup cacheinfo needs) *also* fails in the same
  ~60ms window. Two independent interrupt-delivery paths to cpu0 die
  together, so the defect is **cpu0 losing the ability to take any interrupt
  at all**, not a bug specific to the cacheinfo code path.
- This also re-dates the trigger: the scpsys domain-power-on writes (all
  done by 2.12s, per build #84 traces) are now ~360ms before cpu0's death,
  while the DSI/panel probes (irq request 2.412s, panel "registered"
  2.4189s) are only ~60–120ms before it — proximity now favours the display
  probe path (or a side effect surfacing shortly after it) over the scpsys
  writes as the immediate trigger, though the scpsys domain bug remains the
  leading root-cause candidate for *why* the display path leaves something
  broken.

**Next (build #100):** tighten the ping interval to 10ms for a sharper
death timestamp, and add a periodic read of cpu0's GICv3 redistributor
`GICR_WAKER` register (RD_base 0x19200000 + 0x14, per mt6797.dtsi's GICR reg
range) alongside each heartbeat. If `ProcessorSleep`/`ChildrenAsleep` flips
in the same window, the display build is putting cpu0's redistributor to
sleep — directly implicating the known B-13 MT6797 scpsys domain-table bug
(wrong bus-protect/register bits landing on adjacent MMIO) as the mechanism,
independent of which specific initcall happens to be running when cpu0 dies.

## BUILD #100/#101 — GICR_WAKER refuted; death window tightened to 20ms (2026-07-06)

**Build:** #100 `gicr-waker-10ms-heartbeat` — banner `#22 SMP PREEMPT Mon Jul 6
09:51:04 UTC 2026`. Heartbeat interval tightened to 10ms; adds a periodic
read of cpu0's GICv3 redistributor `GICR_WAKER` (RD_base 0x19200000 + 0x14)
alongside each ping.

**Capture:** `logs/2026-07-06-101-gicr-waker-10ms-heartbeat-boot.log`.

**Result:**

- `gicr0_waker=0x0` on every single reading, from the first ping through the
  final MISS — **the redistributor never goes to sleep.** This refutes the
  "display build corrupts/sleeps cpu0's GIC redistributor" hypothesis from
  build #96's proposal.
- Death window tightened: last good ping at `[2.513317]` (seq 90), first
  `MISS #1` at `[2.533325]` (seq 91) — only ~20ms, versus build #98/#99's
  ~60ms window (build-to-build timing jitter, same general location just
  after `cacheinfo_sysfs_init`).
- **Interpretation:** with the redistributor confirmed awake and correctly
  configured throughout, cpu0 losing responsiveness to a raw IRQ-context IPI
  callback (this heartbeat) *and* the `cpuhp/0` kernel-thread dispatch
  (`cpuhp_invoke_ap_callback` → `__cpuhp_kick_ap` → `wait_for_ap_thread`,
  `kernel/cpu.c`) at the same moment now looks like cpu0 either (a) is stuck
  in genuine WFI/idle without properly waking (a cpuidle/PSCI CPU_SUSPEND
  class bug), or (b) is actually running/spinning with interrupts
  effectively undeliverable (e.g. an unbalanced `irqsave`/masked-IRQ-forever
  bug) rather than powered down by a GIC-level fault.

**Next (build #102):** add `idle_cpu(0)` to each heartbeat round (cheap,
non-invasive scheduler-state read, no IPI needed) to distinguish the two:
`idle_cpu(0)==1` after the miss starts implicates WFI/cpuidle; `==0`
implicates a spin/masked-IRQ bug.

## BUILD #102/#103 — cpu0 wakes normally then hard-locks within 20ms, before reaching cacheinfo (2026-07-06)

**Build:** #102 `idle-cpu0-check` — banner `#23 SMP PREEMPT Mon Jul 6
09:56:27 UTC 2026`. Adds `idle_cpu(0)` to each heartbeat round (cheap
scheduler-state read, no IPI needed).

**Capture:** `logs/2026-07-06-103-idle-cpu0-check-boot.log`.

**Result — decisive, rules out the WFI/cpuidle-never-wakes hypothesis:**

```
[2.383466] ... ok seq=84  idle_cpu0=0   (cpu0 busy, normal init work)
[2.423455] ... ok seq=86  idle_cpu0=1   (cpu0 goes idle -- matches build #93's
                                          cacheinfo_sysfs_init call at 2.4237s)
[2.443466]..[2.503461] ... ok seq=87-90 idle_cpu0=1  (idle for ~100ms -- unusually
                                                        long for a normal wakeup)
[2.523458] ... ok seq=91  idle_cpu0=0   (cpu0 wakes normally, now busy)
[2.543468] ... MISS #1 sent=92 seen=91  idle_cpu0=0  (still "busy" -- NOT asleep)
```

- cpu0 goes idle almost exactly when `cacheinfo_sysfs_init` dispatches work
  (2.4235s vs. 2.4237s) — expected, nothing else to run.
- It sits idle for ~100ms, then **wakes normally** (`idle_cpu0` flips back to
  0) at 2.523s. The wake mechanism itself works.
- Within 20ms of waking (the next heartbeat check), it's already
  unresponsive — and `idle_cpu0=0` at the miss, meaning the scheduler still
  considers cpu0 busy/running, **not asleep**. So this is not a
  WFI-never-wakes bug (refuting that half of build #100/#101's proposal):
  cpu0 wakes, then hard-locks while actively running, before it ever reaches
  `cacheinfo_cpu_online()`'s first `printk` (the `GEMINI-DEBUG cacheinfo
  cpu0` entry trace still never fired — confirmed absent from this capture
  despite `patches/v6.6/base/0001-...cacheinfo...patch` being applied).
- The ~100ms idle-to-wake gap is itself unusual and worth noting: a routine
  scheduler wakeup should take microseconds. This is consistent with cpu0's
  wake path (broadcast timer / local arch timer reprogram / tick_nohz exit)
  already being disturbed before the hard lock, rather than the lock being a
  sudden, unrelated event.

**Next (build #104):** determine whether cpu0 is fully halted after the
lock or just unable to take cross-CPU IPIs/SGIs specifically. Arm a
periodic hrtimer pinned directly to cpu0 (independent of the existing
cross-CPU heartbeat), printing every ~20ms from cpu0's own local-timer
interrupt context. If it also stops at the same instant, cpu0 is truly
halted (a genuine CPU-level hang). If it keeps firing after the IPI
heartbeat dies, the SGI/IPI delivery path specifically is broken while
cpu0's local timer interrupt still works — narrowing the fault to the
interrupt-controller's inter-processor signaling rather than the whole CPU.

## BUILD #104/#105 — cpu0's own local timer dies too: a genuine full CPU hard lock, not an SGI/IPI-specific fault (2026-07-06)

**Build:** #104 `cpu0-local-hrtimer-probe` — banner `#24 SMP PREEMPT Mon Jul 6
10:01:04 UTC 2026`. Adds an hrtimer (`HRTIMER_MODE_REL_PINNED`, 20ms period)
armed by a kthread `kthread_bind`-pinned directly to cpu0, printing
`GEMINI-DEBUG cpu0 local-timer tick #%d` from inside cpu0's own local-timer
interrupt context — independent of the existing cross-CPU IPI heartbeat.

**Capture:** `logs/2026-07-06-105-cpu0-local-hrtimer-probe-boot.log`.

**Result — decisive:**

```
[2.444437] heartbeat ok seq=87                          (last "normal" pair)
[2.484439] heartbeat ok seq=89
[2.504412] local-timer tick #91                          idle_cpu0=1
[2.504431] heartbeat ok seq=90
[2.524413] local-timer tick #92                          idle_cpu0=1
[2.524437] heartbeat ok seq=91
[2.544413] local-timer tick #93
[2.544435] heartbeat ok seq=92
[2.564413] local-timer tick #94
[2.564434] heartbeat ok seq=93
[2.584414] local-timer tick #95    <-- LAST local-timer tick, ever
[2.584437] heartbeat ok seq=94
[2.604452] heartbeat ok seq=95     <-- last heartbeat "ok" (no local-timer tick paired with it)
[2.624443] heartbeat MISS #1 sent=96 seen=95
```

- cpu0's own local-timer interrupt (delivered via its private per-CPU timer,
  not the GIC's inter-processor SGI mechanism at all) **stops dead after
  tick #95 at [2.584414]** — no tick #96 ever appears.
- The cross-CPU IPI heartbeat gets one more "ok" at `[2.604452]` (seq=95) —
  almost certainly a `smp_call_function_single` that was already in flight
  microseconds before the lock, not evidence cpu0 was still alive 20ms after
  its own timer died — then MISSes at `[2.624443]`.
- **This refutes the SGI/IPI-specific-fault hypothesis from build
  #100–#103.** Cpu0's own local timer (a completely different interrupt
  source/path from the GIC SGI redistributor mechanism the heartbeat uses)
  stops at essentially the same instant, slightly *before* the last
  cross-CPU heartbeat reply, not after. Both interrupt paths die together.
  This is a genuine full CPU hard lock: cpu0 stops taking *any* interrupt at
  all, not a GIC/SGI-delivery-specific defect.

**Conclusion:** the fault is a CPU-core-level lockup — most likely
interrupts get masked (or the core wedges in a way no interrupt can
preempt) inside whatever code runs on cpu0 immediately after its build
#103-confirmed clean wake at ~2.523s, and it never recovers. This still
happens before cpu0 ever reaches `cacheinfo_cpu_online()`'s own entry
`printk` (confirmed absent again this capture), so the actual wedging code
path remains unidentified — it runs in the ~60-100ms window between cpu0's
wake and the ~2.58-2.62s death, doing something that is not yet
instrumented.

**Next:** narrow what runs on cpu0 in that window. Candidates: (a) whatever
`do_idle()` / `cpu_startup_entry()` dispatches right after the wake (tick
re-arm, `tick_nohz_idle_exit`, `rebalance_domains`, RCU idle exit) — none of
these should be able to permanently mask IRQs, so a bug in one of them (or
memory corruption reached via one) is plausible; (b) capture cpu0's PSTATE/
DAIF bits directly at the moment of the last successful local-timer tick and
again from a *different* CPU's perspective (e.g. read cpu0's saved
`regs->pstate` if an NMI/watchdog fires) to check whether IRQs are even
enabled going into the lock; (c) since ordinary printk-based instrumentation
cannot execute once cpu0 is wedged, the next productive step is likely an
external observable — e.g. arm the ARM64 hardware lockup detector
(`CONFIG_HARDLOCKUP_DETECTOR`) or a watchdog-NMI-class mechanism *validated
to not regress boot the way pseudo-NMI did* (build #96/#97), so the kernel
itself dumps cpu0's PC/registers at the instant of the lock instead of us
inferring it from silence.

## BUILD #106/#107 — SMI larb0/smi_common enablement: NO CHANGE, hang is bit-for-bit identical (2026-07-06)

**Hypothesis under test:** the vendor Kali 3.18 kernel source (extracted
from `kali_boot.img`'s embedded strings, no separate GPL archive available —
see the SMI-angle discussion this session) showed the display pipeline
gates `CG_MM_SMI_COMMON`/`DISP0_SMI_LARB0` clocks distinct from scpsys's own
`CLK_MM`. Mainline's `larb0`/`smi_common` DTS nodes (added in patch 0006)
were left `status = "disabled"`, and mainline's `mtk-smi.c` had zero MT6797
compatible entries at all, so those clocks were never claimed by any
driver. Patched:
- `patches/v6.6/memory/0001-memory-mtk-smi-add-mt6797-support.patch` — adds
  `mediatek,mt6797-smi-larb`/`-common` to `mtk-smi.c`'s of_device_id tables,
  reusing MT6795 (Helio X10, MT6797's direct architectural predecessor,
  already fully supported upstream)'s existing ops verbatim — no new logic.
- `patches/v6.6/dts/0011-arm64-dts-mediatek-enable-mt6797-smi-larb0-common.patch`
  — flips `&larb0`/`&smi_common` to `status = "okay"`.

**Build:** #106 `smi-mt6797-fix` (`logs/2026-07-06-106-smi-mt6797-fix/`,
banner `#25 SMP PREEMPT Mon Jul 6 10:32:43 UTC 2026`, `ALLOW_DEBUG=1` —
B-13's existing GEMINI-DEBUG step-trace/heartbeat patches retained).
Flashed to both `boot` and `boot2`. **Capture:**
`logs/2026-07-06-107-smi-mt6797-fix-boot.log` (banner confirmed).

**Result — no change whatsoever.** DTB dump confirms both nodes compiled
with `status = "okay"` and correct `reg`/`clocks` (`larb@14020000`,
`smi@14022000`), and `strings` on the built `vmlinux` confirms both new
compatible strings are present. But **neither device ever appears in a
`probe of ... returned` line** anywhere in the capture — the generic
`driver_probe_device()` trace (visible via `ignore_loglevel` for every
other platform device: regulators, phy, clk, syscon, serial, DRM, DSI) never
fires for `14020000.larb` or `14022000.smi`, i.e. no bind attempt is
observable at all, successful or otherwise. Whether or not the driver
silently bound, the **outcome is bit-for-bit identical** to every build
since #92: same last initcall (`cacheinfo_sysfs_init`), same final
local-timer tick (#96 at `jiffies=4294892930`, matching #104/105's #95 to
within one tick), same heartbeat-miss signature, same ATF watchdog timing
(cpu1 dump at 14.16s, cpu2 dump at 18.04s).

**Conclusion:** the SMI-gating hypothesis is falsified as a *practical* fix
— enabling the larb0/smi_common path changed nothing observable. Combined
with builds #84/85 (scpsys exonerated) and #88/89 (DSI probe path
exonerated), every register-level hypothesis for B-13 sourced from the
vendor kernel or mainline's own display stack has now been tested and
found not to move the hang. The wedge is not in any of: scpsys power-on,
DSI probe tail, DRM component bind, or (per this test) the SMI bus-master
path. It remains pinned to the same instruction window this session's
CPU-forensics chain already isolated: cpu0 hard-locks (all interrupt
sources, including its own local timer) a few tens of ms after
`cacheinfo_sysfs_init` starts, with no printk reachable from inside the
lock. See the "Next" paragraph above (#104/105) — an external observable
(hardware lockup detector or a validated NMI-class watchdog) is the only
remaining productive avenue; further register-sequence hypotheses (vendor
or mainline) are no longer a good use of time without new evidence pointing
at a specific one. Per CLAUDE.md principle 5 (bootability first, display
optional), deferring B-13 and moving to another phase is also a reasonable
call at this point. Device left in the watchdog reboot-loop; recover with
`logs/2026-07-06-77-maxcpus8/new_kali_boot.img` (no display, known-good).

## BUILD #108/#109 — SMI larb MMU-bypass fix (vendor Halium cross-check): NO CHANGE, confirmed over two captures (2026-07-06)

**Hypothesis under test:** cross-referencing the real vendor kernel source
(`/Volumes/extdata/github/gemini-android-kernel-3.18`, `dguidipc`'s Halium
tree — see CLAUDE.md "Vendor reference source") found
`drivers/misc/mediatek/video/mt6797/dispsys/ddp_drv.c` unconditionally
forcing `DISP_REG_SMI_LARB0_MMU_EN`/`..._LARB5_MMU_EN` to 0 (IOMMU bypass)
whenever M4U support isn't configured. Mainline has no MT6797 `mtk_iommu`
driver at all, so `mtk_smi_larb_bind()` (which normally sets `larb->mmu` to
a live per-port mask) never runs, leaving `larb->mmu` **NULL** — and
`mtk_smi_larb_resume()` unconditionally calls `config_port()`, which
dereferences `*larb->mmu`. This is a latent NULL-pointer-deref bug on any
IOMMU-less SoC reusing this larb ops table, not just a missing bypass
write.

**Fix:** `patches/v6.6/memory/0002-memory-mtk-smi-default-mmu-bypass-when-no-iommu-bound.patch`
adds a `mmu_bypass` field to `struct mtk_smi_larb` and points `larb->mmu`
at it (zero-initialized) in `mtk_smi_larb_probe()`, so the default state is
an implicit IOMMU bypass rather than NULL — matching the vendor's forced
behavior generically, with no effect on SoCs where a real IOMMU still binds
and overwrites the pointer.

**Build:** #108 `smi-mmu-bypass` (`logs/2026-07-06-108-smi-mmu-bypass/`,
banner `#27 SMP PREEMPT Mon Jul 6 11:28:49 UTC 2026`, `ALLOW_DEBUG=1`).
Note: the first build attempt picked up a stale `configs/gemini-debug-b13.config`
left on the VM from the reverted pseudo-NMI experiment (build #96/#97) —
never deleted by a prior `rsync` that lacked `--delete`. Caught before
flashing (config merge log showed `CONFIG_ARM64_PSEUDO_NMI=y` being
re-enabled) and fixed by re-syncing `configs/` with `--delete`; the flashed
image has no pseudo-NMI config.

**Captures:** two boots landed in `logs/2026-07-06-109-smi-mmu-bypass-boot.log`
(same file, second capture appended after the first — default `ftdi-monitor.py`
behavior is to truncate on each run, so this was likely an explicit
`--append`; going forward each capture should get its own filename per the
one-file-per-attempt provenance convention). Both confirmed banner `#27`.

- **First boot in the file:** DSI probe never completes — no panel
  registration, last trace is the IRQ handler (`INTSTA=0x2`) at `[2.551796]s`,
  heartbeat MISS at `jiffies=4294892926`. Notably *earlier* and structurally
  different from every prior build (which always reached panel registration
  before hanging near `cacheinfo_sysfs_init`).
- **Second boot in the file (repeat capture, same flashed image):**
  matches the #106/#107 baseline signature exactly — panel registers
  (`panel-renesas-r63419 ... registered`), `topology_sysfs_init` and
  `cacheinfo_sysfs_init` both run, heartbeat MISS at `jiffies=4294892927`
  (within a few jiffies of #106/#107's `4294892937` — consistent with the
  run-to-run jitter already seen elsewhere in this investigation).
- In **both** captures, the SMI larb (`14020000.larb`) and common
  (`14022000.smi`) devices still never show a `probe of ... returned` line
  — identical to #106/#107. The code path our fix touches
  (`config_port()`, only reached via `pm_runtime_get_sync` on an
  already-probed larb) was very likely never exercised on either boot.

**Conclusion:** the first boot's earlier/different hang point does not
reproduce and is best explained as run-to-run boot jitter, not a
fix-induced change — the second capture of the *same* flashed image matches
baseline exactly. **The SMI larb MMU-bypass fix does not change the B-13
outcome.** The underlying question — why the larb/common devices never
complete probe at all, for or against — remains open and is now the more
fundamental unanswered question (independent of whether IOMMU bypass would
help once/if they did probe). The `mtk-smi.c` NULL-deref fix itself is
still worth keeping (it's a genuine latent bug fix, harmless on other SoCs),
but it does not resolve B-13. No further register-level hypothesis is
queued; per CLAUDE.md principle 5, B-13 remains deferred. See blockers.md
B-13 for the consolidated status.

## Vendor-console test — LK hardcodes `printk.disable_uart=1`, no vendor dmesg obtainable (2026-07-06)

Tried to get a real vendor-kernel dmesg/display-bring-up trace to compare
against our mainline failure logs, since the one full vendor boot capture
on file (`logs/2026-07-04-08-vendor-full-boot.log`, visually-confirmed
successful boot with working display) shows nothing past `el3_exit` (the
"Pivotal Result" from 2026-07-04).

Traced the cause: the vendor kernel's merged cmdline carries
`printk.disable_uart=1`. This is neither in the boot.img header's own
cmdline field (`bootopt=64S3,32N2,64N2 log_buf_len=4M`) nor in the DTB
`bootargs` (`docs/vendor-dtb/gemini_kali_boot.dts:11`) — it's injected by
the LK bootloader itself, tied to `buildvariant=user`.

Built `scripts/patch-vendor-cmdline.py` (patches only the boot.img header
cmdline field — kernel and ramdisk byte-identical to
`planet/kali_boot.img`, confirmed via sha256) and produced
`OUTPUT/vendor-uart-test.img` with the header cmdline appended
`printk.disable_uart=0 ignore_loglevel`. Flashed to both `boot`/`boot2`,
captured over two power cycles in
`logs/2026-07-06-111-vendor-uart-test-boot.log` (overwritten once —
second capture is the one analyzed; `boot_reason=1` then `boot_reason=4`).

LK's own log confirms it read the header override
(`[LK_BOOT] Android Boot IMG Hdr - Command Line: ...printk.disable_uart=0
ignore_loglevel`), but appends its own `printk.disable_uart=1` afterward in
the final merged cmdline handed to the kernel — the later occurrence wins,
so the override has no effect. Both captured boots end at `el3_exit` with
zero further output, identical to every prior vendor-kernel capture.

**Conclusion:** no vendor-kernel dmesg comparison is obtainable via
boot.img header patching. LK enforces the flag itself for `user` builds.
Getting one would require patching LK's own binary (out of scope, high
risk, proprietary blob) or a different channel (`pstore`, `adb logcat`).
See blockers.md B-13 for full detail. **Device intentionally left flashed
with `vendor-uart-test.img` on both `boot`/`boot2` — not recovered to the
known-good mainline build.**

## B-13 bare-metal payload — never executes, ATF hangs pre-`el3_exit`; harness parked, replaced by in-kernel poll-loop diagnostic (2026-07-06/07)

To settle whether B-13's cpu0 hard-lock is a genuine hardware/bus lock or
Linux-software-specific, a from-scratch EL1 bare-metal diagnostic payload was
built (`baremetal/display-hang-test/` — own GICv3 bring-up, EL1 phys-timer
heartbeat, raw UART0 console, scpsys MM power-on as first-cut control).

**Result: the payload never executed.** Six packaging variants all hang
identically inside ATF/BL31 before `el3_exit` — same PC ~`0x46026020`, same
~12.3s watchdog window, x07 always exactly mirroring the kernel_size fed in:

| Variant | Image (sha256 in dir) | Capture |
|---|---|---|
| v1 gzip, no ARM64 Image header | `logs/2026-07-06-113-b13-baremetal/` | `-114` |
| v2 correct 64-byte header (magic @56) | `-115-…-v2/` | `-116` |
| v3 raw uncompressed | `-117-…-v3-raw/` | `-118` |
| v4 raw zero-padded to 1 MB | `-119-…-v4-padded/` | `-120` |
| v5 gzip + real project DTB | `-121-…-v5-realdtb/` | `-122`, reboot `-123` |
| v6 `--kernel-addr 0x40200000` | `-124-…-v6-stagedaddr/` | `-125` |

Control: reflash of the known-good mainline build
(`logs/2026-07-06-77-maxcpus8/new_kali_boot.img`) booted clean
(`-126-control-maxcpus8-retest-boot.log`, `el3_exit` at 4.14s, full Linux
6.6 boot) — so the hang is specific to our payload/packaging, not a
device/environment regression. Hypotheses disproven: malformed header, gzip
handling, size thresholds, missing DTB, first-boot flakiness, header
kernel_addr (a no-op anyway — LK ignores it, see "Aligned kernel_addr
Retested"). A `text_offset=0x80000` theory was reverted un-flashed
(contradicted by the same prior findings). The constant ~12.3s
size-independent timing suggests ATF/LK polls for something the blob never
satisfies. Root cause open; full detail in
`baremetal/display-hang-test/README.md` "Known issue".

**Decision:** stop spending flash cycles on the boot-chain mystery. The same
experiment runs inside the proven-bootable Linux kernel: new debug patch
`patches/v6.6/drm/0007-GEMINI-DEBUG-cpu0-irqsoff-poll-loop.patch` hijacks
cpu0 immediately after `mtk_drm_kms_init()` completes (the last step known
to finish cleanly before the hang) and spins forever with local IRQs
masked, raw-MMIO only: `CNTPCT_EL0` read + `[GEMINI-HB]` heartbeat line to
UART0 every ~100 ms, each beat dumping every nonzero `GICD_ISPENDR`/
`GICD_ISACTIVER` word and cpu0's `GICR_WAKER`.

Interpretation matrix for the next capture:
- **Heartbeat dies, cntpct frozen between last beats** → genuine
  hardware/bus lock; display stays deferred, B-13 becomes a
  hardware-errata question.
- **Heartbeat survives indefinitely** → cpu0 keeps executing with IRQs
  masked; the "hard lock" is interrupt-delivery/GIC-side or triggered by
  later Linux activity this loop pre-empts. GICD dumps should name the
  culprit INTID → targeted fix, cross-checked against the vendor 3.18
  source's interrupt/SMI handling.
- **Pending-storm visible in GICD dumps before death** → interrupt storm
  starving cpu0 (likely at EL3) → same targeted-fix path.

Control comparison: same build without the display fragment must heartbeat
forever.

## BUILD #129 — cpu0 irqs-off poll loop SURVIVES the B-13 window: NOT a hardware lock (2026-07-07)

Two builds of the in-kernel diagnostic (see previous entry):

- **Build #127** (`logs/2026-07-07-127-b13-cpu0-irqsoff-poll/`, sha256
  `0b5449c5…`, banner `#29`, capture `-128`): hook at end of
  `mtk_drm_kms_init()` **never armed** — the hang fires before component
  bind ever runs. Boot reproduced B-13 exactly: `mediatek-drm` probe
  returns 0 at 2.540s, `cacheinfo_sysfs_init` called at 2.567s, cpu0
  heartbeat MISS at 2.579s, RCU stall report from cpu5 at 8.5s (cpu0 dead,
  cpus 3/4/6/7 "false positive" — alive), ATF `aee_wdt_dump` at 14.3s.
  Bonus finding: LK logged `[LK]jump to K64 0x40200000` — LK **honors**
  the boot.img header `kernel_addr` (see the bare-metal README "Known
  issue" update; this retroactively explains all six bare-metal failures:
  linked at 0x40080000, executed at 0x40200000).

- **Build #129** (`logs/2026-07-07-129-b13-cpu0-poll-probe-hook/`, banner
  `#30`, capture `-130`): hook moved to end of `mtk_drm_probe()` (returns
  27ms before the hang). **Armed successfully** at 2.554s (caller cpu2,
  IPI to cpu0). Result:

  - `[GEMINI-HB]` beats 1–71, one per ~100ms (~7.1s continuous), `cntpct`
    advancing linearly the whole time — straight through and far past the
    ~2.6s point where cpu0 normally dies.
  - GICD_ISPENDR pattern large but **constant** from beat 1 to beat 71 —
    no interrupt storm develops. GICR_WAKER(cpu0)=0 throughout.
  - Run ends at ~10s when the unfed MTK hardware watchdog resets the SoC
    (expected — cpu0 was sacrificed, nothing feeds the WDT). At the ATF
    watchdog FIQ, **cpu0 responds first** (`[ATF](0) inter-cpu-call
    interrupt is triggered`) — the core was executing and able to take
    EL3 interrupts the entire time, even with EL1 PSTATE.I masked.

**Conclusion: B-13 is NOT a hardware/AXI/bus lock.** With the display
config enabled and all display-probe register activity already done, cpu0
executes, reads GIC/UART MMIO, and its arch counter runs, indefinitely
(bounded only by the watchdog). What fails in a normal boot is interrupt
*delivery to* cpu0 (its local timer PPI included) — or something cpu0
only does when it is allowed to proceed past this point (idle/cpuidle
entry, a specific EL1 sysreg write, an unhandled IRQ path) — not the core
or the bus. This reopens B-13 as a tractable software/GIC-state problem.

Next diagnostic candidates (not yet built):
1. Observe instead of pre-empt: run the poll loop on **cpu1**, let cpu0
   boot normally, and dump cpu0's GICR frame (WAKER/ISENABLER0/
   IPRIORITYR) plus GICD state every beat — catch what *changes* at the
   moment cpu0's heartbeat stops.
2. Suspect list for "something cpu0 does when allowed to proceed":
   cpuidle/WFI entry (does cpu0 ever come back from its first deep-idle
   with the MM domain registered?) — test `cpuidle.off=1` /
   `nohlt` cmdline with the display config; vendor 3.18 kernel notably
   keeps its own idle-driver hacks for MT6797.

## BUILD #131 — cpuidle.off=1 + nohlt does NOT prevent the B-13 hang: interrupt-triggered, not idle-triggered (2026-07-07)

Provenance `logs/2026-07-07-131-b13-cpuidle-off-test/`, capture
`logs/2026-07-07-132-b13-cpuidle-off-test-boot.log`. Display config
enabled, poll-loop patch disabled (cpu0 boots normally), cmdline plus
`cpuidle.off=1 nohlt` (both confirmed in the captured cmdline; `nohlt` is
the generic `cpu_idle_force_poll` switch — cpu0 never executes WFI).

Result: **identical hang** — `cacheinfo_sysfs_init` called at 2.603s,
cpu0 heartbeat MISS at 2.631s, RCU stall at 8.6s, ATF `aee_wdt_dump` at
14.4s. cpuidle/WFI is ruled out.

Combined with build #129, the discriminator is now sharp:
- irqs **masked**, cpu0 spinning → survives indefinitely (#129)
- irqs **enabled**, cpu0 running normally, never WFI → dies at ~2.6s (#131)

The wedge is triggered by cpu0 **taking an interrupt** (or the work an
interrupt schedules), not by idle entry, not by the bus, not by any
display register write per se. Prime suspect (already on file,
blockers.md B-13 discussion of the DSI IRQ): an IRQ unmasked by the
display stack while LK's splash left the engine live wedges its handler
or the GIC ack path on cpu0.

Next: patch reworked to **observer mode** (v3,
`patches/v6.6/drm/0007-GEMINI-DEBUG-gic-observer-loop.patch`, replaces
the hijack variant): cpu0 boots normally, a sacrificial A53 (cpu7) spins
irqs-off dumping nonzero GICD_ISPENDR/ISACTIVER words + cpu0's GICR
ISENABLER0/ISPENDR0/ISACTIVER0 + WAKER every ~20ms. Whatever INTID is
ACTIVE at heartbeat-MISS time names the wedged handler.

## BUILD #133 — GIC observer names the culprit: DSI0 IRQ (SPI 229) stuck ACTIVE at hang time (2026-07-07)

Provenance `logs/2026-07-07-133-b13-gic-observer/`, capture
`logs/2026-07-07-134-b13-gic-observer-boot.log` (observer patch v3,
`0007-GEMINI-DEBUG-gic-observer-loop.patch`: cpu0 boots normally, cpu7
sacrificed into an irqs-off raw-MMIO loop dumping GICD pending/active +
cpu0's GICR SGI-frame state every ~20ms). Note: the device rebooted after
the watchdog reset and appended a second boot to the same capture before
the FTDI was disconnected — only the first boot section is analyzed.

352 observer beats. Two decisive observations:

1. `GICD_ISACTIVER` word 8 bit 5 — **INTID 261 = GIC SPI 229 = dsi0@1401c000's
   interrupt** (`patches/v6.6/dts/0006`, `IRQ_TYPE_LEVEL_LOW`) — is stuck
   **ACTIVE** on essentially every beat from the hang moment (observer
   start ≈ heartbeat MISS, ~2.6s) until the watchdog reset ~7s later.
   An SPI stuck active = acked by a CPU whose handler never EOI'd.
2. cpu0's redistributor across the same window: `ISENABLER0=0x4000007f`
   (SGIs + PPI30 arch timer enabled, unchanged), `ISPENDR0` shows the
   timer PPI and incoming SGIs **pending but never delivered**,
   `ISACTIVER0=0` (no local handler running), `WAKER=0`.

That is the textbook GIC signature of an acked-never-EOI'd interrupt
holding cpu0's running priority: every equal/lower-priority interrupt
(all of them, local timer included) is blocked from delivery while the
core itself keeps executing — reconciling builds #129 (irqs-off spin
survives) and #131 (irqs-on dies) exactly.

**Mechanism hypothesis:** cpu0 takes the level-low DSI IRQ and
`mtk_dsi_irq()`'s DSI_INTSTA read stalls forever on the bus — the classic
MediaTek unclocked-IP MMIO stall — because by then something (prime
candidate: the late-boot clk cleanup running right around
`cacheinfo_sysfs_init`) has gated the DSI/MM clocks while the IRQ was
left enabled from probe with the engine still in LK's leftover state.

**Test built (#135):** `0008-GEMINI-DEBUG-dsi-keep-irq-disabled-b13-test.patch`
— `disable_irq()` immediately after `devm_request_irq()` in
`mtk_dsi_probe()`. If boot completes with the display config enabled,
SPI 229 is confirmed as B-13's trigger; the real fix is then to
request/enable the IRQ only around power-on (or guarantee clocks before
any DSI register access), upstream-style.

## BUILD #135 — disable_irq-after-request is too late: wedge is INSIDE request_irq's unmask (2026-07-07)

Provenance `logs/2026-07-07-135-b13-dsi-irq-disabled/`, capture
`logs/2026-07-07-136-b13-dsi-irq-disabled-boot.log`. Same hang (heartbeat
MISS 2.637s, wdt 14.5s), and the observer again shows SPI 229 stuck
ACTIVE on all 353 beats. But the dsi probe trace pins it tighter: cpu0's
last output is `dsi_probe: phy ok, request_irq 15` at 2.609s — the
post-request `disable_irq()` line never printed. The level-low DSI line
is already asserted (LK leftover engine state), so the IRQ fires and
wedges cpu0 the instant `devm_request_irq()` unmasks it. (Earlier
builds' "one benign CMD_DONE irq then hang ~50ms later" reading was
evidently a race that this boot lost immediately.)

Fix attempt v2 (build #137): `irq_set_status_flags(irq_num, IRQ_NOAUTOEN)`
*before* `devm_request_irq()` — the IRQ is never unmasked at probe.

## BUILD #137 — IRQ_NOAUTOEN on the DSI IRQ DEFEATS the B-13 hang: root cause CONFIRMED (2026-07-07)

Provenance `logs/2026-07-07-137-b13-dsi-irq-noautoen/`, capture
`logs/2026-07-07-138-b13-dsi-irq-noautoen-boot.log`. Patch 0008 v2:
`irq_set_status_flags(irq, IRQ_NOAUTOEN)` before `devm_request_irq()` in
`mtk_dsi_probe()` — the DSI IRQ (SPI 229) is requested but never
unmasked. Observer (cpu7) still running.

Result:
- `dsi_probe: irq 15 requested, left disabled (B-13 test), probe
  complete` at 2.610s; R63419 panel registered at 2.616s.
- `cacheinfo_sysfs_init` — the invariant point-of-death of every prior
  display-enabled boot — **completed**: all 8 CPUs' cacheinfo_cpu_online
  hooks enter/exit cleanly at 2.62–2.64s.
- cpu0 heartbeats continue unbroken to seq=449 at 9.69s (~7s past the old
  death point); the observer's GICD ISACTIVER scan shows **SPI 229 never
  goes active** (0 hits in 352 beats, vs stuck-active in 100% of beats in
  builds #133/#135).
- SoC still resets at ~10s via the unfed watchdog — expected and
  unrelated: the observer intentionally sacrifices cpu7 into an irqs-off
  spin (same as #129's cpu0 sacrifice). Clean confirmation build #139
  (observer patch disabled, NOAUTOEN kept) is the userspace test.

**B-13 root cause (diagnostic level): the mtk_dsi driver requests its
level-low IRQ at probe time, unmasking it while LK's leftover DSI engine
state has the line asserted; cpu0 acks it and the handler wedges without
EOI (status-register read stalls on the DSI block), permanently blocking
all interrupt delivery to cpu0.** The proper fix (not this DEBUG hack) is
to keep the IRQ masked until DSI power-on guarantees clocks/engine state
— to be written as a real patch once #139 validates userspace.

## BUILD #139 — B-13 DEFEATED: first clean boot to running userspace with the display stack enabled (2026-07-07)

Provenance `logs/2026-07-07-139-b13-dsi-noautoen-clean/` (banner `#35 SMP
PREEMPT Tue Jul 7 07:01:17 UTC 2026`), capture
`logs/2026-07-07-140-b13-dsi-noautoen-clean-boot.log`. Same as #137 but
with the GIC observer patch disabled (all 8 CPUs boot normally); the only
B-13 intervention left is patch 0008 (DSI IRQ requested with
IRQ_NOAUTOEN, never unmasked).

Serial: `dsi_probe … left disabled … probe complete` 2.630s, panel
registered, `cacheinfo_sysfs_init returned 0 after 13378 usecs` at 2.655s
— the first time this initcall has ever completed with the display config
on. Capture ends 2.97s at the mtu3 probe — the documented UART/USB
console-mux switchover (B-15), cable swapped to USB per the single-cable
protocol.

USB/SSH validation on the live system (`ssh root@10.15.19.82`):
- RNDIS gadget enumerated on the Mac (en12), ping OK
- `systemctl is-system-running` → **running**; nproc=8; uptime 2min+
- cpu0 heartbeat debug still ticking at 163s uptime (seq 8143, no misses)
- `/sys/class/drm` has only `version`: the DRM master bind still ends in
  the pre-existing deferred-probe chain (panel regulators etc.) — that is
  the *next* problem, and it is an ordinary driver-bringup problem, not a
  hard-lock.

One transient `heartbeat MISS #1` at 2.479s (sent=88 seen=87) recovered
immediately — one-beat jitter, unrelated to the B-13 pattern (which was
always MISS followed by total cpu0 death).

**B-13 status: root-caused and neutralized.** Remaining follow-ups:
1. Replace DEBUG patch 0008 with a proper fix: request the DSI IRQ
   masked (or at power-on) and enable it only in the DSI power-on path
   with clocks guaranteed — upstream-worthy change to mtk_dsi.c.
2. Work the ordinary deferred-probe chain to get the DRM master bound
   (panel regulators, mipi_tx, mutex…), then actual display output.
3. Strip the B-13 debug instrumentation (cacheinfo/cpuhp trace flooding
   dmesg at 100Hz, initcall_debug/ignore_loglevel/rcu timeout cmdline).
4. Retest CPU8/9 (A72 cluster, B-16) — previously attributed to B-13.

## BUILD #141 — proper DSI IRQ fix validated (2026-07-07)

Replaces DEBUG patch drm/0008 (permanent IRQ-off) with the upstream-shaped
fix: `patches/v6.6/drm/0008-drm-mediatek-dsi-enable-irq-only-while-powered.patch`.
`mtk_dsi_probe()` sets `IRQ_NOAUTOEN` before `devm_request_irq()` (so the
LK-asserted level-low line is never unmasked against an unclocked engine —
the B-13 wedge); `mtk_dsi_poweron()` calls `enable_irq()` after clocks are
on, the engine is reset and `mtk_dsi_set_interrupt_enable()` has run;
`mtk_dsi_poweroff()` calls `disable_irq()` after `mtk_dsi_disable()` and
before the clocks are cut. This makes command-mode/vblank interrupts usable
once the display actually powers on, unlike the #139 test patch.

- Provenance: `logs/2026-07-07-141-dsi-irq-proper-fix/` (image sha256
  `cb8195070018…`, banner `#36 SMP PREEMPT Tue Jul  7 07:14:21 UTC 2026`)
- Flash: `mtk w boot`/`mtk w boot2` with that image
- Capture: `logs/2026-07-07-142-dsi-irq-proper-fix-boot.log`

**Result — identical to #139, no regression.** DSI probe survives the fatal
window (`GEMINI-DEBUG dsi_probe: phy ok, request_irq 15` → `irq ok, probe
complete` at 2.608s, R63419 panel registered), serial ends at the mtu3 mux
switch at 2.94s (B-15, by design). SSH over the USB gadget confirms:
`systemctl is-system-running` = **running**, nproc=8, cpu0 heartbeat alive
(687 beats at 1 min uptime). `/proc/interrupts` shows the fix operating as
designed: `15: 0 … MT_SYSIRQ 229 Level 1401c000.dsi` — registered, zero
counts, still masked because `mtk_dsi_poweron()` hasn't run (DRM master not
yet bound; `/sys/class/drm` still only `version`).

B-13's interim workaround is now a proper fix. Next: the deferred-probe
chain to bind the DRM master (follow-up 2 from #139).

## BUILD #143 — mt6797 DDP components bind; master blocked only on mutex clock (2026-07-07)

The reason the DRM master never bound was found by live sysfs inspection of
build #141 over SSH: every DDP component device (ovl0/2l0, rdma0, color0,
ccorr0, aal0, gamma0, mutex) had **no driver at all** — patch drm/0003 only
taught `mtk_drm_drv.c` to recognize the nodes; the component drivers
themselves had no mt6797 compat entries, so `component_add()` never ran and
the master waited forever (not deferred — unmatched).

New patches (all values sourced from the vendor 3.18 tree):
- `soc/0001` mtk-mutex: mt6797 data — MOD reg 0x2c / SOF 0x30, module bits
  from vendor `module_mutex_map` (OVL0=10, OVL0_2L=12, RDMA0=13, COLOR0=18,
  CCORR=19, AAL=20, GAMMA=21, OD=22, DITHER=23), SOF_DSI0=1.
- `soc/0002` mtk-mmsys: mt6797 routing table (OVL0_SOUT 0x098, OVL0_SEL_IN
  0x09c, OVL0_MOUT 0x034, COLOR0_SEL_IN 0x068, DITHER_MOUT 0x03c,
  RDMA0_SOUT 0x090, DSI0_SEL_IN 0x07c; values = vendor sel-map indices).
- `drm/0009` — mt6797 compat entries in all six component drivers
  (mt8173-generation data, each vendor-verified: OVL addr 0xf40 + 8-bit GMC,
  RDMA 8 KiB FIFO, COLOR +0xc00, CCORR v1.0/mt8183 data, AAL and GAMMA
  without built-in gamma/dither since mt6797 has separate blocks).
- **Fixed drm/0001 main-path order**: vendor PRIMARY_DISP puts RDMA0 at the
  *end* (… DITHER → RDMA0 → DSI0), not after OVL as mt8173 does.
- **Fixed dts/0001**: `disp_ovl_2l0` was never enabled; it is a hardwired
  stage of the vendor primary path (OVL0 cascades into OVL0_2L).

Provenance `logs/2026-07-07-143-mt6797-ddp-components/` (sha256 `34a6f54c…`,
banner #37); capture `logs/2026-07-07-144-mt6797-ddp-components-boot.log`.

**Result — one step from bind.** All seven driver-backed components probe
and register (benign `gce-client-reg` warnings — no CMDQ in our DTS); the
master adds all component matches and OD0/DITHER0 init as clock-only comps.
Boot is clean to `running`, SSH OK. `devices_deferred` contains only
`mediatek-drm.1.auto`. Manual re-bind of the mutex exposed the blocker:
`mediatek-mutex 1401f000.mutex: error -ENOENT: Failed to get clock` — our
mutex node has no clocks property because **mt6797 has no mutex clock gate**
(absent from both mainline clk-mt6797-mm.c and vendor ddp_clkmgr). Fix:
`.no_clk = true` in the mt6797 mutex data (build #145).

## BUILD #145 — mutex binds; master's silent defer traced to iommu_present() (2026-07-07)

`.no_clk = true` added to the mt6797 mutex data (soc/0001) — mt6797 has no
mutex clock gate in mainline clk-mt6797-mm.c or the vendor ddp_clkmgr.
Provenance `logs/2026-07-07-145-mutex-noclk-fix/` (banner #38); capture
`logs/2026-07-07-146-mutex-noclk-fix-boot.log`. Boot clean to `running`.

**Result:** mutex now binds (`1401f000.mutex -> mediatek-mutex`), but
`devices_deferred` still lists only `mediatek-drm.1.auto`, deferring with
no message even on manual re-bind. Code reading found the silent gate:
`mtk_drm_bind()` opens with `if (!iommu_present(&platform_bus_type))
return -EPROBE_DEFER;`. On the device `/sys/class/iommu/` is empty —
CONFIG_MTK_IOMMU=y but mainline mtk-iommu has **no MT6797 support** and our
DTS has no m4u node, so the check can never pass. Two further gaps noted in
passing: patch drm/0003 never added `mediatek,mt6797-dsi` to
`mtk_ddp_matches` (no component match is added for the DSI — to fix if bind
shows DSI0 missing; DSI comp init may still work via comp_node scan), and
CMA is 32 MiB (fits 2 WQHD ARGB buffers at 14.7 MiB each; raise via `cma=`
when we get past first light).

Fix for the gate (build #147): new patch
`drm/0010-GEMINI-drm-mediatek-allow-bind-without-iommu.patch` — demote the
check to a warning; the bring-up runs SMI larbs in MMU-bypass with
contiguous CMA buffers, which mtk_drm GEM handles via dma_alloc_attrs().

## BUILD #147 — DRM MASTER BINDS for the first time; panic exposes mutex probe-ordering race (2026-07-07)

Two fixes in `drm/0010-GEMINI-drm-mediatek-allow-bind-without-iommu.patch`:
demote `mtk_drm_bind()`'s `iommu_present()` gate to a warning (no mainline
MT6797 IOMMU; SMI in MMU-bypass + CMA buffers), and add
`mediatek,mt6797-dsi` to `mtk_ddp_matches` (0003 had missed it — the DSI
was invisible to the master). Provenance
`logs/2026-07-07-147-drm-no-iommu-dsi-match/` (banner #40); capture
`logs/2026-07-07-148-drm-no-iommu-dsi-match-boot.log`. (An intermediate
`147-drm-no-iommu-bind` build without the DSI match was never flashed and
its provenance dir was removed.)

**Result — the display bind chain ran end-to-end for the first time:**
master probe returns 0 with all 8 component matches (incl. `/dsi@1401c000`);
r63419 panel probe → `mipi_dsi_attach` → `component_add` →
`try_to_bring_up_aggregate_device` → `mtk_drm_bind` → "no IOMMU, using
contiguous CMA buffers" → `component_bind_all` **binds all 8 components**
(ovl0, ovl2l0, rdma0, color0, ccorr0, aal0, gamma0, dsi) → crtc_create main
→ **Oops**: NULL deref at 0x19 in `mtk_mutex_get+0xc`, panic (init killed),
device reset by watchdog.

Root cause of the panic: `mtk_drm_bind()` only checks the mutex *device*
exists (`of_find_device_by_node`); at 2.64s the mutex driver's probe was
still deferred on the MM power domain, so its drvdata was NULL and
`mtk_mutex_get()` dereferenced it. The stock `iommu_present()` defer had
been masking this ordering hole. Fix (build #149, added to drm/0010): defer
the bind until `platform_get_drvdata(mutex_pdev)` is non-NULL.

## BUILD #149 — full KMS stack up and STABLE; flip_done timeout exposes the real blocker: WRONG PANEL (2026-07-07)

One fix over #147 in `drm/0010`: `mtk_drm_bind()` now defers until the
disp-mutex driver has actually bound (`platform_get_drvdata(mutex_pdev)`
non-NULL) instead of oopsing on its NULL drvdata. Provenance
`logs/2026-07-07-149-drm-wait-mutex-bound/` (banner #41, sha256
7937871d93eb…); capture `logs/2026-07-07-150-drm-wait-mutex-bound-boot.log`.

**Result — the ordering fix works and the whole KMS stack comes up:**
first bind attempt logs "Waiting for disp-mutex driver /mutex@1401f000"
and defers (serial, 2.64s); after the MM domain powers on, the deferred
retry binds everything. SSH-verified: `systemd is-system-running` =
`running`, `devices_deferred` EMPTY, `/dev/dri/card0` exists,
`card0-DSI-1` is **connected + enabled**, fb0 registered
("mediatekdrmfb"), DSI IRQ 229 fired 4 times (the proper drm/0008
enable-at-poweron path exercised on hardware for the first time — no
B-13 lockup). No panic, no watchdog reset.

**Remaining failure:** every atomic commit ends in
`[drm] *ERROR* flip_done timed out` (+ vblank-wait WARN in
`drm_atomic_helper_wait_for_vblanks`) — frames never complete; screen
dark.

**Root cause found — we've been driving the wrong panel all along.**
LK's runtime probe in every capture (incl. the stock vendor baselines
-06/-08) says `we will use lcm: aeon_ssd2092_fhd_dsi_solomon` with panel
ID read 0x01572098. The "r63419_wqhd_truly_phantom_2k_cmd" name in
`docs/vendor-dtb/gemini_kali_boot.dts`'s videolfb atag is a build-time
template default that LK overwrites after probing — we built the panel
driver from the wrong LCM. The real panel is a Solomon SSD2092, FHD
1080x2160, **video mode** (SYNC_PULSE_VDO_MODE), 4-lane RGB888,
VSA/VBP/VFP=1/43/76, HSA/HBP/HFP=4/20/26, PLL 502 MHz — vendor source
found in `/Volumes/extdata/github/gemini-android-kernel-3.18-android8`
(`drivers/misc/mediatek/lcm/aeon_ssd2092_fhd_dsi_solomon/`). A
command-mode WQHD driver on a video-mode FHD panel explains both the
dark screen and (plausibly) the flip_done timeouts.

Fix (build #151): `panel/0005` rewritten as `panel-solomon-ssd2092.c`
(vendor-exact init table script-converted, vendor reset dance, video-mode
flags, 154.584 MHz mode); DTS panel node compatible →
`solomon,ssd2092`; `gemini-display.config` →
`CONFIG_DRM_PANEL_SOLOMON_SSD2092=y`.

---

## BUILD #151 (banner #42) — ssd2092 panel validated at DSI level; live forensics find TWO further blockers: SMI runtime-PM gating + backlight architecture (2026-07-07)

- Provenance: `logs/2026-07-07-151-ssd2092-panel/` (sha256 8de7198f…), capture `logs/2026-07-07-152-ssd2092-panel-boot.log`; later same-flash reboot observed via `logs/2026-07-07-153-reboot-observe-boot.log` (clean boot to the usual mtu3 console-mux cutoff at 2.97s — B-15).
- KMS stack still healthy (as #149); flip_done timeouts persist. All further debugging done live over SSH with a static `devmem2` tool (built in the VM, deployed to `/usr/local/bin/devmem2`).

**Finding 1 — SMI clock-gated at runtime (root cause of the frozen pipeline).**
MMSYS CG0 (0x14000100) read `0xe0757fff`: SMI_COMMON (bit0) + SMI_LARB0 (bit1)
**gated** while every DDP engine clock was ungated. Mainline only
runtime-resumes SMI larbs through mtk_iommu device links; with no MT6797 M4U
driver, nothing ever powers them, so OVL0 stalls on its first framebuffer
fetch. Live proof: `echo on > .../14022000.smi/power/control` + same for
`14020000.larb`, then fb blank/unblank → DSI IRQ 229 streams at ~60 Hz
(1 → 383+). OVL0's IRQ stays wedged at 71 — stuck from the pre-resume stall,
not recoverable live; needs the fix at boot.

**Finding 2 — backlight.** Chain verified end-to-end on hardware:
vendor DTB `led@6` led_mode=<5> = CUST_BLS_PWM → DISP_PWM0 @ 0x1100f000
(mt8173 register layout, confirmed against vendor `ddp_reg.h` and LK's
leftover full-duty config in the live registers); source = infra CG1 bit17
(CLK_INFRA_DISP_PWM) ← topckgen `pwm_sel` MUX_GATE (0x10000050, mux 0 =
clk26m); output pin = GPIO178 func1 (only DISP_PWM-capable pin muxed; DWS
default). As-booted, **both clocks were gated by the kernel's late
clk_disable_unused sweep** — this is what kills the bootloader-lit backlight
("Planet logo flashes, then dark", user-observed; logo IS lit during LK, so
the hardware path works). Ungating everything + full/50% duty + COMMIT was
still dark — but sampling the pin's DIN register (0x10005250 bit18, 20
samples: 10 high/10 low) **proves the 25 kHz waveform is physically present
on the ball**. Conclusion (backed by the gemian r63419_fhd LCM source's
"config output high, enable backlight drv chip" comment ahead of the DSI init
table, and no LED-EN GPIO / no I2C backlight chip existing for this board —
DWS + real-DTB + `GPIO_LCM_LED_EN` undefined): the LED boost on the display
flex is enabled by proper panel initialization; DISP_PWM only dims it. Dark
therefore couples back to the panel/pipeline not being fully up.

**Side finding:** all four mt65xx I2C buses probe empty and `i2cget` on
known-present chips (rt9466 @0/0x53, lp3101 @1/0x3e) fails — I2C is not
transacting (likely missing pinmux; parked, tracked for Phase 9).

## BUILD #154 (banner #43) — fix set: SMI larbs pinned active + mt6797-disp-pwm backlight stack (2026-07-07)

- Provenance: `logs/2026-07-07-154-smi-pin-backlight/` (sha256 1d3f1ae8…).
- New patches:
  - `memory/0003-memory-mtk-smi-pin-larbs-active-when-no-iommu-driver.patch` —
    when `CONFIG_MTK_IOMMU` isn't built, `pm_runtime_resume_and_get()` at larb
    probe pins the larb (and, via the DL_FLAG_PM_RUNTIME link, smi-common)
    active for life. Boot-time version of the live fix from #151 debugging.
  - `pwm/0001-pwm-mtk-disp-add-mt6797-compatible.patch` — `mediatek,mt6797-disp-pwm`
    reusing `mt8173_pwm_data` (layout hardware-verified).
  - `dts/0001` extended: `disp_pwm0@1100f000` node (clocks main=pwm_sel,
    mm=CLK_INFRA_DISP_PWM), `pwm-backlight` node (period 39385 ns ≈ vendor
    25.4 kHz), GPIO178 DISP_PWM pinmux, panel `backlight = <&backlight_lcd>`
    (panel driver already calls devm_of_find_backlight + backlight_enable in
    enable()).
  - `configs/gemini-display.config`: +CONFIG_PWM=y, CONFIG_PWM_MTK_DISP=y,
    CONFIG_BACKLIGHT_PWM=y.
- Expectation: OVL0 fetches from boot (flip_done completes), backlight comes
  on at panel enable and survives clk_disable_unused (driver holds the clocks).
- Result: flashed and captured. Backlight fix confirmed hardware-effective:
  `devmem2` register readback of DISP_PWM0 (0x1100f000 EN=1, 0x1100f014
  CON1=0x032303ff nonzero duty) matches sysfs (`brightness=200`,
  `actual_brightness=200`, `max_brightness=255`) exactly, and the user
  visually confirmed the backlight is genuinely lit (easy to miss in a
  lit room — check in the dark). But the SMI pin-active fix **silently
  no-op'd**: live check found `.../14022000.smi/power/runtime_status` =
  `suspended` even after flashing #154. Root cause: the guard tested
  `IS_ENABLED(CONFIG_MTK_IOMMU)` — a Kconfig symbol compiled in generally
  for the build — instead of checking whether *this specific larb's* DT
  node has an `iommus` phandle that could ever resolve to a bound driver.
  Since MT6797 has no mainline M4U compat, the phandle never resolves, but
  the Kconfig symbol was still `=y`, so the guard's `if` branch was always
  false and the `pm_runtime_resume_and_get()` call never ran. Screen
  remained blank, `flip_done timed out` persisted — same failure mode as
  #151, now with working backlight layered on top.

## BUILD #155 (banner #46) — corrected SMI pin-active guard (`iommus` DT property) — CAUSED A NEW MM-DOMAIN HANG, REVERTED (2026-07-07)

- Provenance: `logs/2026-07-07-155-smi-iommus-property-fix/` (sha256
  8d33e5d8…), capture `logs/2026-07-07-156-smi-iommus-property-fix-boot.log`.
- Fix: `memory/0003` guard changed from `IS_ENABLED(CONFIG_MTK_IOMMU)` to
  `!of_property_present(dev->of_node, "iommus")` — larb0's DT node (added in
  `dts/0006`) has no `iommus` property at all, so this correctly identifies
  that no IOMMU will ever claim it and makes the pin-active call actually
  execute for the first time.
- Result: **regression.** The serial log itself looked completely normal
  (boots cleanly through the standard initcall sequence, cuts off at the
  expected mtu3/USB-mux switch ~2.9s, same as every prior build — B-15). But
  the USB gadget failed to enumerate on the host across multiple polling
  rounds totalling well over 5 minutes (vs. 15–35s in every prior successful
  build), across two separate reboots, and the user directly observed "device
  looks to have crashed and rebooted." Since the mux switch means anything
  after the ~2.9s cutoff is invisible on serial, the crash itself couldn't be
  seen — only inferred from the absence of USB enumeration plus the physical
  observation.
- **Root cause (hypothesis, confirmed by revert test below):** SMI larb0's
  power domain is `MT6797_POWER_DOMAIN_MM` (`power-domains =
  <&scpsys MT6797_POWER_DOMAIN_MM>` in `dts/0006`) — the exact domain
  implicated in the prior BUILD #79 finding (`configs/gemini-display.config`
  comment): enabling `COMMON_CLK_MT6797_MMSYS` there "hard-hangs and
  watchdog-reboot-loops, presumed in MM-domain power-on register access
  itself." Build #154's buggy guard never actually called
  `pm_runtime_resume_and_get()` on the larb (see above), so it never touched
  the MM domain and merely left the pipeline stalled-but-stable. Build #155's
  *corrected* guard made that call execute for the first time, at probe
  time, and appears to trigger the same class of MM-domain hard-hang.

## BUILD #157 (banner #47) — SMI larb pin-active fully reverted; stable baseline confirmed (2026-07-07)

- Provenance: `logs/2026-07-07-157-smi-revert-mm-domain-hang/` (sha256
  877b3ef5…), capture
  `logs/2026-07-07-158-smi-revert-mm-domain-hang-boot.log`.
- Change: `memory/0003` patch removed from the stack entirely —
  `drivers/memory/mtk-smi.c`'s `mtk_smi_larb_probe()` reverted to stock
  upstream (plain `pm_runtime_enable()`, no eager resume, no pin-active
  logic at all). Regenerating the patch against a clean tree produced a
  zero-line diff, confirming the revert was complete.
- Result: **stable, confirms the MM-domain-hang hypothesis.** Serial log
  normal, same expected mtu3 cutoff ~2.93s, cpu0 GEMINI-DEBUG heartbeat
  ticking cleanly right up to the cutoff (no stall). USB gadget (en12)
  enumerated normally (~20s) and came link-active promptly, unlike #155.
  SSH-confirmed live: `uptime` = 1 min post-boot with no crash;
  `dmesg | grep flip_done` shows the same `flip_done timed out` /
  `commit wait timed out` errors as #151/#154 (pipeline still stalled, as
  expected since the pin-active fix is now absent); `.../14022000.smi/power/
  runtime_status` = `suspended` (confirms larb not pinned, consistent with
  the revert); backlight `brightness=200/200/255` still correct. User
  reports "USB connected, nothing on screen" — consistent with expected
  behavior (backlight on but dim/needs dark-room check, pipeline stalled,
  no crash).
- **Conclusion:** the SMI-larb pin-active fix is confirmed to be the trigger
  of the #155 MM-domain hang, not USB-gadget slowness. We're back to the
  #154-equivalent stable baseline (backlight fix retained and working,
  SMI larb correctly left unpinned). The problem of safely powering the
  SMI larb (and hence the MM domain) without hitting the B-13/BUILD #79
  hang class is now the open blocker for actually getting `flip_done` to
  complete. See blockers.md B-13.

## BUILD #159 (banner #48) — OVL→SMI-larb runtime-PM device link (safe alternative to pin-active) (2026-07-07)

- Provenance: `logs/2026-07-07-159-ovl-larb-devicelink/` (sha256
  `09b2ea91…`), capture `logs/2026-07-07-160-ovl-larb-devicelink-boot.log`.
- Fix: `drm/0011-drm-mediatek-ovl-link-smi-larb-runtime-pm.patch` — instead
  of pinning the SMI larb active unconditionally at its own probe time
  (the #155 approach that hard-hung the MM domain), `mtk_disp_ovl_probe()`
  now resolves its existing-but-previously-unconsumed `"mediatek,larb"` DT
  phandle and calls `device_link_add(dev, &larb_pdev->dev, DL_FLAG_STATELESS
  | DL_FLAG_PM_RUNTIME)` (no `DL_FLAG_RPM_ACTIVE`). This ties the larb's
  runtime-PM state to OVL's own, so the larb only resumes when OVL is
  runtime-resumed by the normal DRM atomic-commit path — not eagerly at
  link-creation/probe time. Since OVL's own resume timing was already
  proven safe (it's the thing driving the MM domain in every prior build),
  this sidesteps the early/eager-resume MM-domain hang class entirely.
  Still carries the debug instrumentation stack (GEMINI-DEBUG heartbeat,
  initcall_debug) — not yet stripped in this build.
- Result: **works, confirmed live over SSH** (build banner #48,
  `6.6.0-dirty`). `/sys/devices/platform/14022000.smi/power/runtime_status`
  and `14020000.larb/power/runtime_status` both read `active` (previously
  permanently `suspended`). `/proc/interrupts` shows OVL0 (SPI 213) and
  OVL2L0 (SPI 215) both incrementing (71/70 counts after ~3 min uptime,
  previously frozen at 0) — the OVL engines are genuinely receiving and
  servicing frame-fetch interrupts. No MM-domain hang, no crash, no
  regression from the #157 stable baseline. `dmesg` couldn't be checked for
  `flip_done` status directly in this session (see USB investigation below —
  the ring buffer had already evicted early lines by the time this was
  re-checked a day later), but the practical result — SMI larb now actively
  participating in the display pipeline instead of sitting inert — is the
  key confirmation this approach is sound.
- **Conclusion:** *when* the larb's runtime-PM resume happens (tied to a
  component whose own resume timing is already safe) matters more than
  *whether* it happens at all. This is the correct general pattern for
  powering an SMI larb with no mainline M4U/IOMMU driver bound. See
  blockers.md B-13.

## BUILD #161 (banner #49) — GEMINI-DEBUG instrumentation stripped; `-517` DSI probe-defer surfaces (2026-07-07)

- Provenance: `logs/2026-07-07-161-debug-cleanup-clean-dsi-trace/` (sha256
  `1c93eba0…`), captures
  `logs/2026-07-07-162-debug-cleanup-clean-dsi-trace-boot.log` and
  `logs/2026-07-07-163-usb-hang-investigate-boot.log`.
- Change: all `GEMINI-DEBUG` printk/dev_info instrumentation removed now
  that B-13 (its original purpose) is root-caused and fixed (`drm/0008`).
  Retired debug patches (cacheinfo/cpuhp trace, cpu0 IPI heartbeat, scpsys
  step trace, DRM bind step trace, DSI probe-tail/IRQ trace, GIC observer)
  moved to a new sibling directory `patches/_retired-debug-v6.6/`, **outside**
  `patches/v6.6` — `build.sh` globs and applies every `*.patch` found
  anywhere under `patches/v6.6`, and an earlier attempt to park them in a
  `patches/v6.6/_retired-debug/` subdirectory broke the build because the
  leading underscore sorts alphabetically before `drm/`, applying the
  retired patches first and corrupting line offsets for the real ones.
  `configs/gemini-cmdline.config` also dropped
  `initcall_debug`/`ignore_loglevel`/`rcu_cpu_stall_timeout=6` (B-13
  diagnostics, no longer needed) — these were flooding the 4MB dmesg ring
  buffer fast enough to evict early-boot output (panel/DSI probe lines)
  within about 2 minutes of uptime.
- Result: with the flood gone, the serial log for the first time shows the
  DSI/panel probe sequence cleanly, including:
  ```
  [drm:mtk_dsi_host_attach] *ERROR* failed to add dsi_host component: -517
  panel-solomon-ssd2092 1401c000.dsi.0: failed to attach DSI: -517
  ```
  alongside `mediatek-drm mediatek-drm.1.auto: Waiting for disp-mutex driver
  /mutex@1401f000`. `-517` is `-EPROBE_DEFER`, a standard Linux deferred-probe
  return — **not confirmed benign vs. a real block** in this session, because
  the serial capture always cuts off shortly after this point at the known
  mtu3/USB-gadget mux switch (B-15), before any retry could be observed.
- **Not yet resolved:** whether the DSI host eventually attaches successfully
  on a deferred retry (the normal case for `-EPROBE_DEFER`) or whether
  something upstream of it (the `disp-mutex` wait) never completes and the
  attach never retries. Needs either a full post-boot dmesg dump over SSH
  (this build wasn't the one flashed when SSH access was restored — see USB
  investigation below) or a way to extend serial visibility past the mux
  cutoff. **First task for the next session.**

## USB gadget enumeration investigation, 2026-07-07 (host-side, not a kernel regression)

After flashing build #161, the RNDIS/Ethernet gadget stopped enumerating on
the Mac — initially suspected as a possible new kernel-side regression
(perhaps interacting with the `-517` DSI finding above). Extended
troubleshooting (`ifconfig -l` polling, `ping`, `ssh`, all failing) escalated
across several data points:

- A Mac reboot during the investigation caused the gadget interface to
  disappear from `ifconfig -l` entirely (not just fail to go link-active).
- The Gemini was discovered to be connected via a Thunderbolt hub/dock
  (itself showing "not connected" in macOS Network prefs) rather than
  directly into a Mac USB port — a very plausible culprit, since many
  Thunderbolt hubs mishandle non-standard USB gadget device profiles.
- Reflashing to the last known-SSH-good build (#159) and connecting directly
  to the Mac still showed **zero** trace of any USB device in
  `ioreg -p IOUSB -w0` — more severe than a simple driver-mismatch (which
  would normally still show *some* raw device entry).
- Resolution: switched the serial capture over to the **FTDI** cable
  (`/dev/tty.usbserial-B001VBPM`) to get kernel-side visibility independent
  of the USB gadget. The capture (`logs/2026-07-07-164-159-reflash-serial-recheck-boot.log`)
  showed a **completely normal boot** — all initcalls succeed
  (dwc3/dwc2/mtu3 USB driver init all return 0) up to the expected
  mtu3-mux-switch cutoff at ~2.97s — confirming the kernel itself was never
  the problem. Switching the physical cable back to USB afterward, the
  gadget then enumerated correctly (`ioreg` showed `RNDIS/Ethernet
  Gadget@00143000` and `FT232R USB UART@00144000` both present on the same
  hub), `en12` came up `status: active`, and after `sudo ifconfig en12 inet
  10.15.19.1/24`, `ping 10.15.19.82` and `ssh` (password auth — the
  publickey attempt failed, root cause not investigated, low priority)
  both succeeded.
- **Conclusion:** this was a host/cable/enumeration-timing issue on the Mac
  side (possibly related to the Thunderbolt-hub detour, possibly a simple
  transient enumeration race), **not a kernel or driver regression** — every
  serial capture across every build in this saga showed a normal, unhung
  boot. No project code changes are implicated. Device confirmed alive and
  reachable at end of session, running build #159 (`6.6.0-dirty`, banner
  #48, `uname -r` confirmed via live SSH).
- **Next step queued:** reflash `boot2` with build #161
  (`logs/2026-07-07-161-debug-cleanup-clean-dsi-trace/new_kali_boot.img`,
  sha256 `1c93eba0…`) now that USB is working again, and get a clean
  post-boot `dmesg` over SSH to resolve whether the `-517` DSI probe-defer
  is benign.

## BUILD #161 recheck / new blocker found: mtk_mipi_tx D-PHY probe EBUSY (2026-07-08)

Start of session: attempted to flash build #161 and reflash both `boot`/
`boot2` with build #159 (last known-SSH-good) after a fresh USB-gadget
enumeration scare (see below) that turned out to be the same
host/cable-side symptom as 2026-07-07, not a kernel regression — resolved
the same way, by capturing over FTDI first
(`logs/2026-07-08-159-known-good-recheck-boot.log`, 5232 lines, cuts off
normally at the expected mtu3/USB-mux switch point) to prove the kernel
boot itself was fine, then re-seating the USB-C cable until the gadget
enumerated and `ssh` (password auth, `sshpass -p toor`, publickey still
rejected for an uninvestigated reason) succeeded.

With live SSH access on build #159, pulled `journalctl -k -b` (the `dmesg`
ring buffer itself had already wrapped past the boot-time DSI messages,
overwritten by the still-present GEMINI-DEBUG cpu0 heartbeat spam — build
#159 predates the debug-instrumentation strip that #161 has). This finally
answers the open question from the previous session:

**`-517` on `mtk_dsi_host_attach` is confirmed benign — the DSI host
attaches successfully on a later deferred-probe retry:**
```
probe of 1401c000.dsi.0 returned 0 after 62276826 usecs
```
(i.e. ~62 seconds after the initial `-517`/EPROBE_DEFER). Following that:
`mtk_drm_bind` completes, `panel-solomon-ssd2092 1401c000.dsi.0: Solomon
SSD2092 FHD DSI panel registered`, `mediatek-drm mediatek-drm.1.auto: [drm]
fb0: mediatekdrmfb frame buffer device`, and a `GEMINI-DEBUG bind: complete`
marker. So the `disp-mutex` wait does resolve, and the whole DRM/panel bind
chain finishes correctly. **B-13 (as originally scoped: cpu0 hard-lock +
DSI probe) is now fully closed** — no lock, no permanent probe failure.

**New blocker, found immediately after:** the MIPI DSI D-PHY driver fails
to probe:
```
calling  mtk_mipi_tx_driver_init+0x0/0xfe8 [phy_mtk_mipi_dsi_drv] @ 247
initcall mtk_mipi_tx_driver_init+0x0/0xfe8 [phy_mtk_mipi_dsi_drv] returned -16 after 1011 usecs
```
`-16` is `-EBUSY`. Without a working D-PHY, DSI can bind logically but
cannot actually clock data out to the panel — consistent with the observed
symptom (screen stays completely dark). This manifests as a continuous loop
of DRM atomic-commit failures, repeating roughly every 10 seconds
indefinitely:
```
mediatek-drm mediatek-drm.1.auto: [drm] *ERROR* flip_done timed out
mediatek-drm mediatek-drm.1.auto: [drm] *ERROR* [CRTC:51:crtc-0] commit wait timed out
mediatek-drm mediatek-drm.1.auto: [drm] *ERROR* [PLANE:33:plane-0] commit wait timed out
mediatek-drm mediatek-drm.1.auto: [drm] *ERROR* [CONNECTOR:32:DSI-1] commit wait timed out
[drm:mtk_drm_crtc_atomic_begin] *ERROR* new event while there is still a pending event
WARNING: ... drm_atomic_helper_wait_for_vblanks.part.0+0x23c/0x260
```
i.e. every atomic commit (via `drm_fbdev_generic_client_hotplug` /
`drm_client_dev_hotplug`) times out waiting for vblank/flip completion,
because the CRTC/connector never actually produces a frame without a
working PHY, and this repeats forever as the fbdev helper keeps retrying.

**Tracked as the next concrete blocker (not yet numbered — will become
B-17 or folded into B-13's remaining scope, see blockers.md).** Likely
cause of the `-16`/EBUSY: a resource (clock, regulator, or MMIO region)
the D-PHY driver requests is already held by something else — worth
checking probe order against the vendor 3.18 `mtk_mipi_tx`/DSI PHY driver
source for a specific clock/reset sequencing requirement. Not yet
investigated further this session.

**Full serial provenance:** kernel base v6.6, repo commit `f7e5cd5` (build
#159 unchanged from 2026-07-07), `.config` at
`logs/2026-07-07-159-ovl-larb-devicelink/config`, image sha256
`09b2ea91…` (unchanged), partition `boot2` (and `boot`, both flashed
identically this session), captures:
`logs/2026-07-08-159-known-good-recheck-boot.log` (FTDI, cuts off at mux
switch as expected) + live `journalctl -k -b` over SSH (password auth) for
post-cutoff visibility.

## B-17 D-PHY EBUSY reassessed: it's noise, not the blocker (2026-07-08, same session)

Went to investigate B-17 further, on the same live build #159 SSH session
(password auth via `sshpass`, no new flash/capture — the device was already
booted from the recheck above). Checked `/proc/iomem` and
`/sys/kernel/debug/clk/clk_summary`:

```
10215000-1021508f : 10215000.mipi-dphy mipi-dphy@10215000
mipi_tx0_pll   1  1  1  927504000  0  0  50000  ?
```

The D-PHY *is* bound and its PLL is running live at 927.5 MHz — the real,
built-in copy of `mediatek-mipi-tx` (`CONFIG_PHY_MTK_MIPI_DSI=y`) probed
successfully. Re-reading the exact `journalctl -k -b` context around the
`-16`/EBUSY line shows it's `Error: Driver 'mediatek-mipi-tx' is already
registered, aborting...` — a **second** registration attempt on top of an
already-successful one, not the only attempt. The culprit: a stale leftover
`.ko` still present on the rootfs from an earlier build when this driver was
`CONFIG_PHY_MTK_MIPI_DSI=m` —
`/lib/modules/6.6.0-dirty/kernel/drivers/phy/mediatek/phy-mtk-mipi-dsi-drv.ko`
— which module autoload/coldplug tries to insert after the built-in copy
already owns the driver name. Harmless duplicate-load noise; **not** the
reason the panel stays dark. blockers.md B-17 has been corrected in place to
reflect this (previous framing around D-PHY EBUSY struck through/replaced).

**Real symptom, root cause still open:** with the D-PHY confirmed working and
the full DSI/panel bind chain completing (`panel-solomon-ssd2092
1401c000.dsi.0: Solomon SSD2092 FHD DSI panel registered`, `probe of
1401c000.dsi.0 returned 0`, `fb0: mediatekdrmfb`, `GEMINI-DEBUG bind:
complete`), the DRM atomic commit loop still never produces a real frame —
`flip_done timed out` / `commit wait timed out` on CRTC, PLANE and CONNECTOR
in turn, repeating every ~10s indefinitely. No panel `prepare`/`enable`
activity is visible at default log level (expected — no dyndbg enabled for
`mtk_dsi.c` or `panel-solomon-ssd2092.c`, so this doesn't mean they didn't
run). Next concrete steps (see blockers.md B-17 for full detail): enable
dynamic debug on `mtk_dsi.c` + `panel-solomon-ssd2092.c` to see whether the
panel's DSI init command sequence actually executes/succeeds; confirm the
DSI IRQ (masked-until-power-on per the B-13 fix patch) is correctly
unmasked again once the pipeline reaches enable, since a permanently-masked
IRQ would prevent vblank/TE delivery by construction; check whether
`disp_ovl0`/`mutex`/`disp_rdma0` reach real runtime configuration versus
just `status = "okay"` in DT.

No new flash/capture this entry — investigation was done entirely via live
SSH (`journalctl -k -b`, `/proc/iomem`, `clk_summary`) on the already-booted
build #159 from the recheck above.

## BUILD #164: DSI IRQ/panel debug trace — no USB gadget across multiple boots (2026-07-08)

Built and packed `patches/v6.6/zz-debug/0001-GEMINI-DEBUG-dsi-panel-enable-trace.patch`
(candidate #1 from B-17's investigation list): `pr_info()` on every
`mtk_dsi_irq()` fire, plus `dev_info()`/`pr_info()` traces in
`mtk_dsi_poweron`, `mtk_output_dsi_enable`, the DSI bridge's
`atomic_enable`/`atomic_pre_enable`, and the panel's `prepare`/`enable`/
`get_modes`. Applied cleanly on top of the full patch stack (had to move it
into a new `patches/v6.6/zz-debug/` directory — `build.sh patch` applies
`find | sort` across *all* subdirectories, so a `debug/` directory sorted
before `drm/`/`panel/` alphabetically and broke the apply order; `zz-debug`
sorts last). Packed as build #164 (banner `#53`, image sha256
`119db7db3a8a4a7768e35a16781a4c689fbfebf1286da924d84780a5366e2ce3`,
`ALLOW_DEBUG=1` required and correctly enforced by the pack script's
verification gate). Flashed to both `boot`/`boot2`.

**Result across several flash/power-cycle attempts: no USB gadget ever
appeared.** `ioreg -p IOUSB` showed only the always-attached FTDI serial
adapter (on dedicated GPIO97/98 UART test pins, separate from the USB-C
data port — confirmed this session that both can be connected
simultaneously without conflict, since the mux is an internal SoC register
flip, not a physical cable contention). No RNDIS/Ethernet Gadget device,
at any point, across multiple attempts — restarting macOS's `usbd`, deleting
the stale RNDIS network service in System Settings, toggling the `en12`
interface, and reapplying the static IP all had no effect, ruling out
Mac-side/cable state as the cause.

Tried capturing the full boot on FTDI serial without swapping to USB this
time (`logs/2026-07-08-166-dsi-panel-enable-trace-full-serial-boot.log`),
hoping to see further than usual — but it cut off at the identical point as
every previous capture (`mtu3 11271000.usb: u2p_dis_msk: 0, u3p_dis_msk: 0`
at kernel time 0.4448s). This confirms the B-15 cutoff is driven by the
`mtu3` driver itself flipping the UART/USB mux register during its own
probe — a software event at a fixed point in boot, independent of which
cable happens to be physically connected. So there is currently no way to
observe boot past ~0.44s on this hardware for *any* build, debug or not.

**Control test:** reflashed build #159 (banner `#48`, no debug
instrumentation, sha256 `09b2ea91…` — the established known-good baseline)
onto both partitions with no other change, same cable/setup.
`logs/2026-07-08-167-159-rndis-recheck-boot.log` confirms a clean boot,
cutting off at the same expected point (2.99s). RNDIS gadget enumerated
normally this time, `en12` came up, `ping 10.15.19.82` and
`ssh root@10.15.19.82` both succeeded immediately (`uname -a` confirmed
banner `#48`). This isolates the stall specifically to build #164 — not a
Mac/cable/network-service problem.

**Working hypothesis, feeding back into B-17:** the unconditional
`pr_info()` inside `mtk_dsi_irq()` fires on every interrupt. If DSI's IRQ
(SPI 229) is storming — one of B-17's own leading candidates — a
synchronous console print on every fire from interrupt context could be
starving the CPU badly enough that boot never reaches USB gadget
configuration (a userspace step, well after kernel init). If confirmed,
this is actually a positive result for B-17 (proves the IRQ is storming),
but the trace as currently written can't surface that finding, since it
may itself be the reason nothing further happens. See blockers.md B-17
"Update 2026-07-08 (evening)" for the full writeup and next step
(rate-limit the trace).

## BUILDS #168/#170/#172/#174: IRQ-storm isolation inconclusive; known-good #159 also fails; battery hypothesis (2026-07-08, later)

Followed up build #164 with three further isolation builds of
`patches/v6.6/zz-debug/0001-GEMINI-DEBUG-dsi-panel-enable-trace.patch`,
each flashed to both partitions and captured on hardware:

- **#168** (banner `#54`, sha256 `a63b23f8dae2561073b740814bf296ccc55e36559acdb6e963a8e2393868e847`):
  rate-limited the `mtk_dsi_irq` print via a lock-free `atomic_long_t` fire
  counter (log only the 1st and every 4096th fire) — same rest of the trace
  set as #164. Still no USB gadget across attempts.
- **#170** (banner `#55`, sha256 `0dbc951d7099dd2077ec25427404850ce5c03f08e5eea340a7668fb18d4eeb7e`):
  stripped down to *only* the rate-limited IRQ counter, every other trace
  point removed, to isolate the print itself from everything else. Capture:
  `logs/2026-07-08-171-dsi-irq-only-minimal-trace-boot.log`. Still no USB
  gadget; device also self-reset during this session.
- **#172** (banner `#56`, sha256 `b5535e5068a4c1101d2c413e433dc927efa0ab33091c183abe045157bdff64ae`)
  and **#174** (banner `#58`, sha256 `fcbff6a8e42cc3abd55b63fc0c4f26b0da3b961f0f206a79d69de103d9f76475`):
  added an IRQ-storm circuit breaker to `mtk_dsi_irq()` — `disable_irq_nosync()`
  once the fire count crosses `GEMINI_DEBUG_IRQ_STORM_LIMIT` (200000),
  guarded by `atomic_xchg` so it trips only once — intended to force boot
  past a genuine storm regardless of root cause. #174 also carried the new
  `configs/gemini-pstore.config` (see below). Neither reached USB gadget
  networking. Capture: `logs/2026-07-08-176-159-pstore-recheck-boot.log`
  (this particular capture was actually a #159 recheck, see next).

**Critical pivot — known-good build #159 also failed.** As a sanity check
after #174, reflashed `logs/2026-07-07-159-ovl-larb-devicelink/new_kali_boot.img`
(banner `#48`, zero debug instrumentation, the same image that cleanly
isolated #164 in the very first control test above) — and it **also**
failed to bring up a USB gadget, and the device self-reset unprompted. Since
#159 carries none of the suspect debug code, this rules out the debug
patches as the sole explanation for the run of failures across
#164/#168/#170/#172/#174. A dedicated serial-only sanity capture,
**#177** (`logs/2026-07-08-177-159-hardware-sanity-check-boot.log`, still
banner `#48`), confirmed the board itself boots completely normally — clean
banner, reaches the expected `mtu3`/mux cutoff at ~2.99s, no panics — so
this is not a boot-level kernel hang. The board boots; specifically USB-C
data enumeration/link-up was failing intermittently for every build tried
late in this session, including the known-good one.

**Revised working hypothesis: marginal/low battery, not software.** The
user noted the device's battery had not been charging throughout the
session's many flash/power-cycle operations and was very low. A
marginal battery explains the pattern without any code change: brownout
resets under a current spike (gadget enumeration, display init, CPU ramp),
USB data-line negotiation being the first casualty of a sagging rail, and a
previously-reliable build suddenly failing. This supersedes the IRQ-storm
hypothesis as the leading suspect for the late-session failures (though the
IRQ-storm circuit breaker remains available in `patches/v6.6/zz-debug/` if
needed again — it does no harm and was never proven to be the cause).
**Not yet confirmed** — pending retest after a proper charge.

**Also folded in this session (unrelated to the above investigation) —
build #178:** two independent fixes packed together once the debug patch
was removed and the tree returned to a clean state:
1. **Stable gadget MAC.** `CONFIG_USB_ETH=y` is built in, so `g_ether` had no
   persistent MAC and randomized a new one every boot; since macOS keys its
   Ethernet "service" identity off the MAC, every boot produced a brand-new
   `enNN` interface, making "is the gadget up" hard to tell from "it's a
   different interface than last time." Fixed with
   `g_ether.dev_addr=42:00:15:19:82:01 g_ether.host_addr=42:00:15:19:82:00`
   added to `CONFIG_CMDLINE` in `configs/gemini-cmdline.config` (built-in
   drivers still honor `<modname>.<param>=` on the cmdline). Verified on the
   next boot: `en12` in `ioreg`/`ifconfig` showed the expected fixed MAC
   `42:00:15:19:82:00`.
2. **pstore/ramoops actually enabled.** The `ramoops@44410000`
   reserved-memory node already existed in `dts/0001` (matching the
   vendor's own pstore region, for dual-boot safety) but
   `CONFIG_PSTORE_RAM` had never been turned on. Added
   `configs/gemini-pstore.config` (`CONFIG_PSTORE=y`, `CONFIG_PSTORE_RAM=y`,
   `CONFIG_PSTORE_CONSOLE=y`, `CONFIG_PSTORE_PMSG=y`) so kernel log output
   now survives a crash/panic/watchdog reset, readable from
   `/sys/fs/pstore/` on the *next* boot of our own kernel.

Packed as **build #178** (banner `#63 SMP PREEMPT Wed Jul 8 04:49:15 UTC
2026`, `logs/2026-07-08-178-stable-boot-fixed-mac/new_kali_boot.img`, sha256
`eeca62d1ef9cddbbdc825c63b708568870f2b669e407eb43f55448c00c2e1b7c`), debug
instrumentation confirmed absent by the pack script's verification gate.
Flashed to both partitions; capture
`logs/2026-07-08-179-stable-boot-fixed-mac-boot.log` shows a normal boot to
the expected mux cutoff. Post-flash, the RNDIS gadget did enumerate with the
correct fixed MAC — genuine progress — but link then went `inactive` and
later the interface disappeared from macOS entirely, consistent with the
battery hypothesis above rather than a problem with this build. This is the
current baseline pending the battery-recharge retest.

**Dead end investigated along the way:** checked whether stock Android's
`/proc/last_kmsg` (via `adb shell`, no root available — production build)
held anything from the #159 self-reset. It returned only an empty
ram-console header (`hw_status: 0`, "Not Clear, old status is 0" — no crash
recorded), and `/sys/fs/pstore/` was inaccessible without root
(`adb root` refused: "cannot run as root in production builds"). Android's
proprietary ram-console format is unrelated to the Linux pstore/ramoops
format just enabled in build #178 — even sharing the same physical
reserved-memory region, the two don't cross-read each other's data — so
this can't retroactively explain the #159 reset. Only a future crash
followed by *our own* kernel's `/sys/fs/pstore/` mount would be
informative.

### BUILD #159 (presumed) — B-17 cross-host isolation test, 2026-07-08, Linux workstation

No new build or flash in this entry — Gemini already on `boot2` from prior session. Plugged into the Linux workstation (the machine identified as the next isolation step in B-17's pending test block) via USB-C.

Result: USB gadget (`ID 0525:a4a2 Linux-USB Ethernet/RNDIS Gadget`) enumerated on the Linux host, `cdc_ether` bound, interface `enx3ad74925ce01` created. Host-side MAC `3a:d7:49:25:ce:01` (random — does not match #178's fixed MAC, suggesting this is build #159 or older on boot2). Static IP `10.15.19.1/24` configured. **No carrier: `NO-CARRIER`/`Link detected: no` throughout; `ping 10.15.19.82` — Destination Host Unreachable.** Identical failure to what was seen on the Mac.

Conclusion: Mac-specific cause conclusively ruled out. Problem is on the Gemini's own side. See B-17 "Update 2026-07-08 — cross-host isolation complete" for full command output and interpretation.

**Root cause subsequently identified:** the SP Flash Tool scatter-file restore wiped p29 (`linux` partition), replacing the Debian 13 rootfs (which had `usb0.network` + systemd-networkd) with the factory Kali image, which has no USB networking config. All kernel builds since the scatter restore appear broken because the device-side networking stack was never there — the kernel was always fine. Fix: rebuild and reflash Debian 13 rootfs via `scripts/mkrootfs.sh`, then `mtk w linux debian13-rootfs.img`. See B-17 for the full procedure.

### FRESH DEBIAN 13 ROOTFS REFLASH — B-17 gadget/SSH fix confirmed, 2026-07-08, Mac

Built a new rootfs image in the build VM (`scripts/mkrootfs.sh`,
`debian13-rootfs.img`, sha256
`a87d4780e7ccbbdba0a281b7e174c60f0eff181c1e470c5bdc8c5b3e8cd8c79e`), flashed
to `linux` (p29) with `mtk w linux ...`. `boot2` untouched (build #71,
banner #5, the earliest ever validated build — deliberately left as-is to
isolate the rootfs as the only variable).

Serial capture `logs/2026-07-09-185-freshrootfs-boot-check.log` (2112
lines): clean boot, kernel init proceeds normally through `mtu3
11271000.usb: u2p_dis_msk: 0, u3p_dis_msk: 0` — the expected UART/USB mux
handoff point (B-15) — with no new errors versus prior known-good captures.

Post-boot: macOS `en12` (RNDIS/Ethernet Gadget) came up `status: active`,
100baseTX full-duplex — carrier now asserts, unlike every attempt since the
scatter restore. Mac-side static IP added manually
(`sudo ifconfig en12 alias 10.15.19.1 netmask 255.255.255.0`, since the
interface only self-assigned an APIPA `169.254.x.x` address). `ping
10.15.19.82` and `ssh root@10.15.19.82` (password `toor`, fresh host key —
expected one-time `ssh-keygen -R 10.15.19.82` warning, not a real MITM)
both succeeded:

```
Linux gemini 6.6.0-dirty #5 SMP PREEMPT Mon Jul  6 06:22:43 UTC 2026 aarch64 GNU/Linux
Debian GNU/Linux 13 (trixie)
```

Confirms the root-cause diagnosis end-to-end: the gadget/SSH failure was a
rootfs problem introduced by the scatter-file restore, not a kernel or
driver regression — no code change was needed. B-17's gadget-networking
sub-thread is now closed; the DRM/display sub-issue that gives B-17 its
title remains open separately.

### BUILD #195/#197 — B-17 DSI IRQ bounded-timeout fix, first attempt (regression: watchdog reset), 2026-07-09

Wrote `patches/v6.6/drm/0012-drm-mediatek-dsi-bound-irq-busy-wait-timeout.patch`:
replaces the unbounded `do { mtk_dsi_mask(RACK); tmp = readl(INTSTA); } while
(tmp & DSI_BUSY);` spin in `mtk_dsi_irq()` with a bounded
`readl_poll_timeout_atomic()` (1us poll / 20ms timeout), intended to prevent
an infinite hardirq-context spin if `DSI_BUSY` never deasserts after RACK
(the working theory for what causes the B-13-adjacent cpu0 hard-lock to
recur).

Build #195 (`logs/2026-07-09-195-b17-dsi-irq-timeout-plus-trace`, banner #69)
included this fix **plus** the parked `zz-debug`
`0001-GEMINI-DEBUG-b17-dsi-panel-enable-trace.patch`. Flashed and captured
(`logs/2026-07-09-196-...-boot.log`): reproduced a hard failure — device
fell back to booting the Android `boot` partition instead of `boot2`,
serial showed watchdog-reset markers (`RGU STA: A0000000`, `"SW reset with
bypass power key flag"`, `"[PLFM] WDT reboot bypass power key!"`,
`androidboot.bootreason=wdt_by_pass_pwk`).

To isolate whether the regression was the new IRQ-timeout patch or the debug
trace patch, built #197 (`logs/2026-07-09-197-b17-dsi-irq-timeout-only`,
banner #70) with the debug patch temporarily held out
(`patches/v6.6/zz-debug/` moved to a scratch dir for the build, restored
immediately after). Same watchdog-reset failure signature reproduced
(`logs/2026-07-09-198-...-boot.log`). **This exonerates the debug trace
patch and implicates patch 0012 (or its interaction with 0008) as the
regression.**

Root-cause analysis of patch 0012 (code review, no hardware cycle spent):
the timeout branch returned `IRQ_HANDLED` **without** clearing/masking
`DSI_INTSTA` or waking `dsi->irq_wait_queue`. Since the IRQ line is
level-triggered, leaving `status` set means the handler re-fires
immediately — turning the intended one-shot bounded 20ms poll into an
**unbounded storm of hardirq re-entries with no forward progress**, which
would still trip the hardware watchdog, just spread across many entries
instead of one spin. Patch rewritten to always clear/mask `DSI_INTSTA` and
call `wake_up_interruptible()` even on timeout, leaving recovery to
`mtk_dsi_wait_for_irq_done()`'s existing timeout + `mtk_dsi_reset_engine()`
path.

Device recovered by reflashing `boot2` to the build #71 baseline both times
(`logs/2026-07-08-194-baseline-restore-boot.log` after #196,
`logs/2026-07-09-199-baseline-restore-boot.log` after #198) — both captures
match the known-good build #71 serial signature exactly, SSH reconfirmed.

### BUILD #200 — B-17 DSI IRQ bounded-timeout fix, corrected (intermittent, still unresolved), 2026-07-09

Rebuilt with the corrected patch 0012 (clears/masks status and wakes the
waiter on both the normal and timeout paths), debug trace patch again held
out (`logs/2026-07-09-200-b17-dsi-irq-timeout-fixed`, banner #71, sha256
`c077b3bc6613fb746d9c089a963bd67be581d36a3470f7381c39bed63bf2738c`).

Capture `logs/2026-07-09-201-b17-dsi-irq-timeout-fixed-boot.log` spans
**three** power-on attempts on the same flashed image, with three different
outcomes:

1. First attempt: hung. No kernel console output ever appeared; ATF's own
   hang detector fired 10s after `el3_exit` (`aee_wdt_dump: on cpu0`,
   `pc == lr == 0xffffffc000087fa8`, i.e. cpu0 stuck executing a tight
   loop). Capture ends mid register-dump.
2. Second attempt (after the user power-cycled): booted **cleanly** —
   banner #71, SMP brought up all 8 CPUs, DRM component matching, the
   expected benign `-517 EPROBE_DEFER` on `mtk_dsi_host_attach`, through to
   the normal `mtu3`/UART-USB mux-switch cutoff. Indistinguishable from a
   working baseline boot on serial. But `en12` never came up
   (`status: inactive`, no USB device visible to `system_profiler
   SPUSBDataType` at all on the Mac) even after ~45s of polling with the
   gadget cable connected — so despite a clean-looking kernel log, the
   device never actually finished bringing up USB gadget networking this
   cycle either.
3. Third attempt (another power-cycle): also booted cleanly on serial
   (identical pattern, cut off normally at `mtu3`), and again no USB
   gadget enumeration observed.

**Conclusion: patch 0012 (corrected version) does not reliably fix the
hang.** Same image produces three different outcomes across three power-on
attempts — full watchdog-class hang, clean-looking serial boot with silent
USB-gadget failure, clean-looking serial boot with silent USB-gadget
failure again. This is consistent with a **timing-dependent race**, not a
deterministic logic bug reachable by reading the C code alone — the exact
window in which LK's leftover DSI engine state happens to still be
asserting the IRQ line relative to when Linux's `mtk_dsi` driver first
touches it likely varies boot to boot.

Checked `/sys/fs/pstore/` after reflashing back to the build #71 baseline
(`logs/2026-07-09-202-baseline-restore-boot.log`, SSH confirmed, banner #5):
empty (`total 0`), and `dmesg | grep -i ramoops` showed only the
reserved-memory registration line, no "found existing... buffer" message at
all — meaning the ramoops region came back completely fresh. **No crash
record survived** any of the three build #200 attempts. This is expected
for the watchdog-hang failure mode: `aee_wdt_dump` is ATF's own hang
detector firing on a wedged cpu0, which never reaches Linux's panic/oops
path, so pstore/ramoops (which only captures kernel oops/panic output, or
console output if `CONFIG_PSTORE_CONSOLE` state survives a *warm* reset)
never gets a chance to write anything — and the physical power-cycles the
user performed likely dropped DRAM self-refresh entirely, wiping even that.

**Baseline restored and confirmed working** (`logs/2026-07-09-202-...`, SSH
banner #5, matches build #71 exactly). Patch 0012 held out of the patch
stack pending further diagnosis. See blockers.md B-17 for the updated
status and next-step plan (stress-test 0008 alone; add unconditional
non-ratelimited debug printk trace points around `mtk_dsi_irq()` so any run
leaves a trail viewable via pstore/console-ramoops after the fact).

### BUILD #203 — B-17 stress test: patch 0008 alone + pstore trace; hang RE-ATTRIBUTED to Android fallback boots, 2026-07-09

Build `logs/2026-07-09-203-b17-0008-only-plus-pstore-trace` (banner #73,
sha256 `3eda93ee165eb4cb6a37fa2d6eab5647483df618d61e655af7ba5d46f0f87344`):
drm stack with patch 0012 **held out** (0008 only), plus
`patches/v6.6/zz-debug/0002-GEMINI-DEBUG-dsi-irq-poweron-poweroff-trace.patch`
(unconditional `pr_info` trace in `mtk_dsi_irq`/`poweron`/`poweroff`,
mirrored to pstore via `CONFIG_PSTORE_CONSOLE=y`).

Multiple power-on sessions were captured, but **all to the same log path**
(`logs/2026-07-09-204-b17-0008-only-plus-pstore-trace-boot.log`), so each
relaunch of `ftdi-monitor.py` overwrote the previous session — only the
final (clean) session survives as raw evidence. Observed across sessions
(details preserved in blockers.md, "Update 2026-07-09 (later)"):

1. Clean boot, `RGU STA: 0`, normal `mtu3` cutoff — but the silent
   USB-gadget failure again (`en12` inactive, zero USB devices in
   `system_profiler`). Third occurrence of this pattern.
2. A hang session: `el3_exit`, no kernel output, `aee_wdt_dump: on cpu0`,
   `pc == lr == 0xffffffc000087fa8`, followed by a ~33s watchdog bootloop —
   **but that session's LK line read `jump to K64 0x40080000`** (Android
   `boot` partition), and the hang PC resolves to the *3.18-era* arm64 VA
   layout (`0xffffffc000080000` text base), not our 6.6 kernel
   (`0xffff800080000000` per this build's System.map). The hang was almost
   certainly the **Android kernel**, silent because LK sets
   `printk.disable_uart=1` for Android boots.
3. Final session (surviving log): genuine cold start (`RGU STA: 0` line
   111), `jump to K64 0x40200000` (line 1819), correct `#73` banner (line
   1828), clean serial boot to the `mtu3` cutoff (line 2111) — and again no
   USB gadget enumeration, SSH timeout.

**Conclusions:** (a) no confirmed hang of *our* kernel exists in the
#200/#203 data — every `0x40200000` boot was serially clean; the "early
cpu0 hard-lock" evidence points at Android-fallback cycles; (b) the
reproducible open problem is the clean-boot silent USB-gadget failure;
(c) the GEMINI-DEBUG trace never fired (expected — DSI defers with -517 and
poweron is never reached at this stage). Next capture: button-controlled
power-on test, fresh log file per attempt, checking `jump to K64` each
time. See blockers.md for the full revised next-step list.

### B-17 ROOT-CAUSED AND FIXED — OVL leftover-IRQ NULL-deref panic; builds #212/#218/#221, 2026-07-10

**The full crash chain (supersedes the "hang re-attributed" entry's open
questions):** journal evidence (`journalctl --list-boots` on the shared
Debian rootfs: 10 boots, *all* banner #5) proved build #203 never once
reached userspace — its "clean serial boots" were an artifact of the
console-mux cutoff at ~0.45s (mtu3 init switches the left-port mux away
from UART). The crash lives in the invisible 0.5–6s window. Also observed:
boot2 briefly drove a **green screen** before resetting — first pixels ever
from the mainline display stack (uninitialized framebuffer scan-out).

**pstore dead end (important negative result):** ramoops at the vendor's
own `mediatek,pstore` region (0x44410000, 0xe0000 — exactly what
`docs/vendor-dtb/gemini_kali_boot.dts` reserves) does NOT survive any
reset on this device. Readout kernel = build #212 (banner #75,
`CONFIG_PSTORE_RAM=y`, `CONFIG_DRM_MEDIATEK=m` so display can't bind;
sha256 540d345a…). A controlled test (marker into `/dev/pmsg0`, plain
`reboot`, next boot checks `/sys/fs/pstore` + `/var/lib/systemd/pstore`)
came back empty — the preloader re-initializes DRAM on every boot path,
warm or cold. A sysrq-c panic test (same #212 image flashed to boot2,
`sysctl kernel.panic=5`, `echo c > /proc/sysrq-trigger`) confirmed the
panic→auto-reboot path works but the buffer arrives as garbage
("found existing invalid buffer"). RAM-based crash capture is a dead end;
serial visibility is the vehicle that works (below).

**Build #218 (banner #76, `logs/2026-07-10-218-b17-crasher-serial-visible/`,
sha256 bf6d3628…):** the #203 config with USB/mtu3 **disabled**
(`CONFIG_USB_MTU3/GADGET/ETH` off via a temp fragment) so the console mux
never switches — serial stays live through the crash window. First boot
attempt landed in the `boot` slot (banner #75 — always verify the banner);
after reflash+boot2, capture `logs/2026-07-10-219-…` caught the death live:

```
[0.554] Unable to handle kernel NULL pointer dereference at 0000000000000150
[0.566] pc : mtk_crtc_ddp_config+0x3c/0x244   lr : mtk_crtc_ddp_irq+0xd0/0xd4
        mtk_disp_ovl_irq_handler → __handle_irq_event_percpu → … → el1h_64_irq
[0.595] Kernel panic - not syncing: Oops: Fatal exception in interrupt
```

Root cause: LK leaves the OVL running (boot splash — hence the green
screen) with `OVL_INTEN` armed. `mtk_disp_ovl_probe()` requests the IRQ
with that leftover state live; the interrupt fires during component bind —
after the vblank callback is registered but **before the CRTC has an atomic
state** — and `mtk_crtc_ddp_config()` dereferences
`mtk_crtc->base.state` (NULL, offset 0x150 = `pending_config`). Panic in
IRQ context → hardware watchdog → LK falls back to the Android `boot`
slot. Same disease class as the B-13 DSI IRQ (patch 0008), one engine over.

**Fix — `patches/v6.6/drm/0012-drm-mediatek-quiesce-ovl-irq-at-probe-and-guard-null-crtc-state.patch`:**
(a) in `mtk_disp_ovl_probe()`, clear `OVL_INTEN`/`OVL_INTSTA` (clock held
via `clk_prepare_enable`) before `devm_request_irq`; (b) defensive early
return in `mtk_crtc_ddp_irq()` when `crtc->state` is NULL. Both hunks
upstreamable.

**Build #221 (banner #77, `logs/2026-07-10-221-b17-ovl-irq-quiesce-fix/`,
sha256 563ff6c7…, still USB-free for serial visibility) — VALIDATED,
capture `logs/2026-07-10-222-…`:** sails through 0.55s, DRM fully bound,
no oops, GEMINI-DEBUG shows one clean DSI IRQ (`spins=1`), kernel alive at
93+s. The panic is fixed. **Next blocker now exposed:** repeating
`[drm] *ERROR* flip_done timed out` + `vblank wait timed out` every ~10s
from the fbdev client (PID 68 worker) — atomic commits never complete
because the OVL frame-done interrupt never fires post-enable, i.e. no
frames flow through the pipeline (panel dark); systemd never appears on
serial, suggesting the fbcon takeover retry loop stalls boot. Lead: LK's
DDP log configures the path as `vido_mode`; verify our DSI/panel mode
(video vs command), TE/trigger and mutex SOF configuration against the
vendor 3.18 source.

**Ops notes:** (1) booting with the USB cable in from power-on breaks
gadget enumeration; the reliable protocol is FTDI in at boot, swap to USB
after the mtu3 line (adopted as standard). (2) relaunching
`ftdi-monitor.py` onto an existing log path OVERWRITES it — always a fresh
NN-numbered file. (3) `mtk w` to boot2 while the device sits in a
just-booted state can be followed by an accidental default-slot boot —
always verify the banner before analysing.

### BUILD #223 — mutex EOF fix for flip_done timeout (banner #78), 2026-07-10

**Hypothesis:** the post-fix blocker on build #221 (`flip_done timed out` /
`vblank wait timed out` every ~10s, OVL frame-done never firing, panel dark,
boot stalled before systemd) is a DDP mutex misconfiguration: our
`mt6797_mutex_driver_data` (patches/v6.6/soc/0001) borrowed
`mt2712_mutex_sof`, which programs only the SOF field (value 1 for DSI0).
The vendor 3.18 `ddp_get_mutex_src()`
(kernel-3.18/drivers/misc/mediatek/video/mt6797/dispsys/ddp_path.c) sets
**both** SOF and EOF to DSI0 for a video-mode DSI path — EOF field is
`REG_FLD(3, 6)`, i.e. register value 0x41, per ddp_reg.h
(`SOF_VAL_MUTEX0_EOF_FROM_DSI0 == 1`). Mainline's mt8183 table has the
identical construction with the comment "Add EOF setting so overlay
hardware can receive frame done irq" — exactly our symptom. Without EOF the
mutex never cycles on DSI end-of-frame, so OVL frame-done never fires and
every atomic commit times out.

**Change:** added `mt6797_mutex_sof[]` (SOF | SOF<<6 for DSI0/DSI1/DPI0) to
`patches/v6.6/soc/0001-soc-mediatek-mtk-mutex-add-mt6797-mutex-data.patch`
and pointed `mt6797_mutex_driver_data.mutex_sof` at it. Verified
`git apply --check` clean on pristine v6.6.

**Build:** #223, banner `#78 SMP PREEMPT Fri Jul 10 05:23:18 UTC 2026`,
sha256 `d535cb7201645cacf5739ad2c0cf06b2ad77bdaa14040ee92e0e4e394da0680b`,
provenance `logs/2026-07-10-223-b17-mutex-eof-fix/`. Still the no-USB debug
config (serial visible throughout) + GEMINI-DEBUG DSI trace, on top of the
#221 patch set (drm/0012 OVL quiesce fix included).

**Flash/capture:** `mtk w boot2 .../223.../new_kali_boot.img`, capture
`logs/2026-07-10-224-b17-mutex-eof-fix-boot.log`.

**Expected outcome if correct:** no flip_done/vblank WARNs, fbcon commits
complete, boot proceeds to systemd on serial — and possibly first pixels on
the panel.

### CAPTURE 224 result + BUILD #225 — DSI cmd-mode quiesce (banner #79), 2026-07-10

Capture `logs/2026-07-10-224-b17-mutex-eof-fix-boot.log` (build #223, banner
#78 verified): the mutex EOF fix alone did **not** clear the timeouts
(flip_done ×9, vblank ×4). But the capture exposed the next layer: at 1.13s
`[drm] Wait DSI IRQ(0x00000008) Timeout` → `failed to switch cmd mode` →
`panel-solomon-ssd2092: DSI write (cmd 0x28) failed: -62` → `init sequence
failed: -62`. Root cause: LK leaves `DSI_MODE_CTRL` in video mode from the
splash; `mtk_dsi_reset_engine()` (DSI_CON_CTRL soft reset) does not clear
it, so `mtk_dsi_host_transfer()` sees MODE set, tries to stop a video
stream that isn't running and waits for a VM_DONE that never comes — every
panel init command fails with -62. Third instance of the
"never-trust-LK-leftover-display-state" class (after B-13 DSI IRQ and the
OVL leftover-IRQ crash).

**Fix:** new `patches/v6.6/drm/0013-drm-mediatek-dsi-force-cmd-mode-at-poweron.patch`
— force `mtk_dsi_set_cmd_mode(dsi)` in `mtk_dsi_poweron()` right after
`mtk_dsi_reset_engine()`. Build #225, banner #79, provenance
`logs/2026-07-10-225-b17-dsi-cmd-mode-quiesce/` (sha256 `45f10d5afc42ddc7…`).

### CAPTURE 226 result + BUILD #227 — mipitx PLL prepare fix (banner #80), 2026-07-10

Capture `logs/2026-07-10-226-b17-dsi-cmd-mode-quiesce-boot.log` (banner #79
verified): **drm/0013 validated on hardware** — all init-sequence/-62/
cmd-mode errors gone; GEMINI-DEBUG dsi trace shows a CMD_DONE IRQ (status
0x2) per panel command. flip_done/vblank timeouts persist. New finding
(present in captures 222/224/226 alike, i.e. pre-existing): `BUG: scheduling
while atomic: kworker/u20:2` at 0.53s — our MT6797 mipitx PHY driver had
`usleep_range()` in clk_ops `.enable`, which runs under the CCF enable
spinlock (trace: `mt6797_mipi_tx_pll_enable → clk_core_enable → …
phy_power_on → mtk_dsi_poweron`); a second BUG (preempt_count underflow to
0) followed inside the panel's `msleep`. Sleeping ops belong in
`.prepare/.unprepare` — exactly what mainline mt8173 mipi_tx does; caller
uses `clk_prepare_enable` so behaviour is preserved.

**Fix:** `patches/v6.6/phy/0004-…-mt6797-mipitx-phy-driver.patch` reworked:
pll `.enable/.disable` → `.prepare/.unprepare` (functions renamed
`mt6797_mipi_tx_pll_prepare/_unprepare`). Build #227, banner #80,
provenance `logs/2026-07-10-227-b17-mipitx-pll-prepare-fix/`.

### CAPTURE 228 result + BUILD #229 — DDP register dump diagnostic (banner #81), 2026-07-10

Capture `logs/2026-07-10-228-b17-mipitx-pll-prepare-fix-boot.log` (banner
#80 verified): **phy fix validated** — `scheduling while atomic` count 0
(was 2). Panel init completes cleanly (187 CMD_DONE IRQs, last at 0.79s),
`mtk_output_dsi_enable`'s poweron at 0.85s, then **silence**: no frame-done
or vblank interrupt ever arrives; flip_done ×9 / vblank ×4 timeouts
unchanged; panel registered at 62.7s after the fbcon retry ladder. The
pipeline (OVL0→…→RDMA0→DSI0) is now configured with no software errors at
all, but the hardware produces no frames — we are blind to which block is
stalled.

**Diagnostic:** new `patches/v6.6/zz-debug/0003-GEMINI-DEBUG-ddp-register-dump.patch`
— standalone `drivers/soc/mediatek/gemini-ddp-dump.c` (obj-y), delayed work
at t≈8s (while the stuck commit still holds the pipeline powered) dumps raw
registers of mmsys CG_CON0/1, mutex0 (INTEN/INTSTA/EN/MOD/SOF), OVL0
(STA/INTEN/INTSTA/EN/ROI/SRC_CON/L0/RDMA0_CTRL/L0_ADDR), RDMA0
(INT_EN/INT_STA/GLOBAL_CON/SIZE/FIFO_CON) and DSI0 (START/INTEN/INTSTA/
CON_CTRL/MODE_CTRL/TXRX/PSCTRL/VDO timings/PHY_LCCON/LD0CON/state-debug
0x148–0x168), twice 500ms apart so moving status bits show. A banner line
precedes each block so a bus hang on a gated block identifies itself.

Build #229, banner `#81 SMP PREEMPT Fri Jul 10 05:54:43 UTC 2026`, sha256
`aac1824f4f2ff0587de265f6e2b67f92f6910b245fb5665d3b55fc8fa5bf69df`,
provenance `logs/2026-07-10-229-b17-ddp-register-dump/`.

**Interpretation matrix for capture 230:**
- `DSI_MODE_CTRL != 1` (not sync-pulse video mode) or `DSI_START == 0` →
  DSI never started streaming; look at mtk_output_dsi_enable ordering.
- DSI streaming but `RDMA0 GLOBAL_CON` engine off / SIZE zero → RDMA never
  configured/started; mutex or comp-config issue.
- OVL0 `INTEN` without FRAME_COMPLETE bit → vblank enable path never armed
  OVL (check drm/0012 interaction).
- All engines running, INTSTA counters advancing between passes → IRQ
  delivery problem, not a pipeline stall.
- Dump hangs at a block banner → that block's clock/power domain is gated.

### CAPTURE 230 result + BUILD #231 — extended DDP dump (banner #82), 2026-07-10

Capture `logs/2026-07-10-230-b17-ddp-register-dump-boot.log` (banner #81;
note: user's capture overwrote the intended 228 file, renamed to 230 — the
original build #227 capture is lost but was fully analysed in the entry
above). Dump analysis:

- mutex: EN=1, SOF=0x41 (SOF+EOF from DSI0 — EOF fix confirmed in hardware),
  MOD=0x05fcb400 (ours OR'd over LK leftovers; extra bits 15/24/26 =
  OVL1_2L/UFOE/PWM0 are LK's).
- OVL0: EN=1, ROI 1080x2160, INTEN=0x2 (FME_CPL armed), SRC_CON=0 (no
  layers — expected pre-first-vblank: plane config is applied from the OVL
  irq, which never fires), **INTSTA=0x2014 = FME_UND + FME_HWRST_DONE +
  ABNORMAL_SOF, FME_CPL never latched** — OVL receives SOFs, starts frames,
  never completes them: output blocked downstream.
- RDMA0: EN, size correct, INT_STA=0x7e (frame start/end + **EOF abnormal +
  FIFO underflow**) — running but starved/disrupted.
- DSI0: START=1, MODE_CTRL=1 (video sync-pulse), INTSTA bit31 (BUSY),
  state-debug 0x168 changes between passes — DSI actively streaming.
- MMSYS CG_CON0=0x00110000: only OVL1/RDMA1 gated (not in path) — clocks OK.

Vendor `ddp_path.c` reveals the mt6797 primary path muxes (OVL0_VIRTUAL
stage, DITHER_MOUT, RDMA0_SOUT, DSI0_SEL_IN). A routing table covering our
path was **already present and applying**
(`patches/v6.6/soc/0002-…mtk-mmsys-add-mt6797-routing-table.patch`, from an
earlier session) — a duplicate written this session was removed. So the
routing registers *should* hold: DITHER→RDMA0, RDMA0→DSI0 direct (bypassing
LK's PATH0/UFOE), OVL0_2L→VIRTUAL→COLOR0. But this has never been verified
in hardware, and the stall signature (OVL blocked at its output) is exactly
what a routing mismatch would produce.

**Build #231** (banner `#82 SMP PREEMPT Fri Jul 10 06:12:19 UTC 2026`,
sha256 `fb5f09caac13f86018b68ba7271808cd276342f9598129f73fd93ce9211e4617`,
provenance `logs/2026-07-10-231-b17-ddp-dump-extended/`): zz-debug/0003
extended to also dump the mmsys routing muxes (0x034/0x038/0x03c/0x040/
0x068/0x07c/0x088/0x08c/0x090/0x098/0x09c), the OVL_2L0 block (0x1400d000,
incl. DATAPATH_CON to check BGCLR_SEL_IN), OD0 (0x14017000) and DITHER0
(0x14018000), plus OVL RDMA_CTRL(0)/ROI_BGCLR. Expected reads if routing is
correct: mmsys+0x03c=0x1, +0x090=0x2, +0x07c=0x2, +0x068=0x1, +0x098=0x0,
+0x09c=0x0, +0x034=0x1; ovl2l0+0x024 bit2 set (BGCLR_SEL_IN), ovl2l0+0x00c=1.
Any deviation fingers the broken link.

### CAPTURE 232 result + BUILD #233 — OVL0 layer-poke experiment (banner #83), 2026-07-10

Capture `logs/2026-07-10-232-b17-ddp-dump-extended-boot.log` (banner #82
verified). Extended dump eliminates every config hypothesis:

- **Routing muxes all correct**: 0x034=1 (VIRTUAL→COLOR0), 0x03c=1
  (DITHER→RDMA0), 0x068=1 (COLOR0←VIRTUAL), 0x07c=2 (DSI0←RDMA0), 0x090=2
  (RDMA0→DSI0), 0x098=0/0x09c=0 (OVL0_2L→VIRTUAL) — the pre-existing
  soc/0002 routing table works. (0x040=1 UFOE_MOUT is an LK leftover,
  harmless since DSI0 selects RDMA0.)
- **OVL_2L0 cascade correct**: EN=1, DATAPATH_CON=0x5 (BGCLR_SEL_IN set),
  ROI right — and it has FME_CPL *latched* (completed at least one frame).
- OD0 EN=1 CFG=0x4 and DITHER0 EN=1 CFG=0x2 — exactly what mainline's
  mtk_od_config/mtk_dither_config write (OD relay is overwritten by
  mtk_dither_set's DISP_DITHERING; same as working mt8173). OD INTSTA=0xf:
  processing frames.
- Vendor ovl_connect() confirms cascade needs only BGCLR_SEL_IN on the
  downstream OVL — nothing missing on OVL0's side.
- Mutex MOD bit map verified identical to vendor module_mutex_map.

So every register our driver writes is right, the whole downstream chain
shows frame activity — only OVL0 (cascade head, the CRTC's vblank source)
never latches FME_CPL, with FME_UND + ABNORMAL_SOF instead, and SRC_CON=0.

**Remaining hypothesis:** this OVL IP doesn't complete background-only
frames. Mainline leaves all layers off at first enable (plane config is
applied from the vblank irq) — chicken-and-egg: no layer → no FME_CPL → no
irq → plane config never applied. mt8173's OVL tolerates layerless frames;
MT6797's may not (vendor never runs OVL without a layer).

**Build #233** (zz-debug/0003 extended): after dump pass 2 (~8.5s) the
debug module re-enables OVL0 layer 0 mirroring mtk_ovl_layer_on()
(RDMA_CTRL(0)=1, SRC_CON|=1), reusing LK's leftover L0 config (addr
0x7dfb0000 = LK splash buffer, still fully programmed). Dump pass 3 at ~9s
shows the result. If FME_CPL latches after the poke (and/or the fbcon
commit suddenly completes, possibly with the LK splash re-appearing on the
panel), the hypothesis is proven and the proper fix is to make the first
frame's plane config apply at enable time (or enable a layer before
starting the mutex) for mt6797.

### CAPTURE 234 result + BUILD #235 — clock-rate report (banner #84), 2026-07-10

Capture `logs/2026-07-10-234-b17-ovl0-layer-poke-boot.log` (banner #83
verified). **Layer-poke hypothesis disproven**: after the poke, SRC_CON=1
and the layer fetcher is demonstrably active (RDMA_CTRL(0)=0x00e80001 —
FSM bits live; GMC register changed; OVL_STA 0x1f→0x1d), but FME_CPL still
never latches; instead a new INTSTA bit 5 appears (RDMA0_EOF_ABNORMAL —
the layer fetch is being aborted mid-frame). flip_done timeouts continue
unchanged. So OVL0 aborts every frame regardless of layers, with each
abort coinciding with the next SOF arriving while it is still busy
(ABNORMAL_SOF).

**New hypothesis — DDP clocked too slow**: that signature (head-of-pipe
frame never finishes before the next SOF, underrun, downstream FIFO
underflow, while DSI streams at full rate off its own PLL) fits the DDP
engines running far below the DSI drain rate (~165 Mpix/s for
1080x2160@60). All DDP engines run from `mm_sel` (topckgen +0x40 bits
25:24; parents 0=clk26m/26MHz, 1=imgpll_ck, 2=univpll1_d2, 3=syspll1_d2).
Nothing in our DTS or drivers assigns mm_sel a parent or rate — it is pure
LK leftover, and the CCF may also have reparented/disabled its PLL parent
during late clk cleanup (we no longer boot with clk_ignore_unused; an
unused imgpll/univpll would be shut off, forcibly reparenting or killing
mm_sel).

**Build #235** (banner `#84 SMP PREEMPT Fri Jul 10 06:34:54 UTC 2026`,
sha256 `ef322d69bf7f28207ccf424cfba14a548f6e6b16cff34b35f5e00e5b10ba99d1`,
provenance `logs/2026-07-10-235-b17-clk-rate-report/`): zz-debug/0003 now
also dumps topckgen CLK_CFG_0..6 (0x10000040..0xa0) raw and reports CCF
rate/enabled/parent for mm_sel, clk26m, imgpll_ck, univpll1_d2, syspll1_d2,
mm_disp_ovl0, mm_disp_rdma0, mm_dsi0_mm_clock, mm_smi_common. If mm_sel
reads parent=clk26m (mux field 0) or its PLL parent is off/slow, the stall
is explained and the fix is a DTS assigned-clocks (like MSDC's) pinning
mm_sel to a fast parent.

## CAPTURE 236 result + BUILD #237 — OVL0 soft-reset poke (banner #85), 2026-07-10

**Capture:** `logs/2026-07-10-236-b17-clk-rate-report-boot.log` (banner #84
verified). **Clock hypothesis DISPROVEN.** GEMINI-CLK report: `mm_sel` rate
325000000, enabled, parent `imgpll_ck` (325 MHz, on); raw topck+0x040 bits
25:24 = 1 (imgpll_ck) agrees. All display gates (`mm_disp_ovl0`,
`mm_disp_rdma0`, `mm_dsi0_mm_clock`, `mm_smi_common`) inherit 325 MHz —
~2x the ~165 Mpix/s the mode needs. `univpll1_d2`/`syspll1_d2` off is
irrelevant (unused parents). Rest of dump identical to capture 232: OVL0
INTSTA=0x2014 (FME_UND + FME_HWRST_DONE + ABNORMAL_SOF, no FME_CPL), DSI
streaming (state-debug advancing between passes), flip_done/vblank timeouts
unchanged.

**Eliminated so far:** mmsys routing, OVL cascade wiring, layerless-frame
limitation (poke, capture 234), MM CG gating, OD/DITHER config, mutex
MOD/SOF, and now engine clock rate.

**Remaining asymmetry → new hypothesis: OVL0 FSM wedged from LK handoff.**
OVL_2L0 (never used by LK) latches FME_CPL (INTSTA 0x201e); OVL0 (LK's
splash engine, still carrying leftover layer addr 0x7dfb0000 / GMC / CON
values) never does. Mainline `mtk_disp_ovl.c` never resets the engine;
vendor `ddp_ovl.c ovl_reset()` always pulses OVL_RST (+0x14, write 1 then
0) during path init. OVL0's latched FME_HWRST_DONE is LK-era.

**BUILD #237 (banner `#85 SMP PREEMPT Fri Jul 10 06:45:55 UTC 2026`,
sha256 `036859140419062e3974b682f366105becee652e8487516414e8b04ba43b0845`,
provenance `logs/2026-07-10-237-b17-ovl0-reset-poke/`):** rewrote
zz-debug/0003 — topck/CLK report removed; after dump pass 1 (8 s), pulse
OVL0 OVL_RST (1 → udelay → 0) and clear INTSTA, then passes 2/3 at +500 ms.
ovl_offs now include 0x14 (RST).

**Interpretation:** if post-reset INTSTA shows FME_CPL (bit 1) latching in
passes 2/3 (and ideally flip_done timeouts stop for later commits), the
wedged-FSM hypothesis is confirmed → proper fix = reset pulse in
mtk_disp_ovl probe/enable (same LK-quiesce family as drm/0012). If INTSTA
returns to 0x2014-style with no FME_CPL, the wedge survives soft reset or
the cause is elsewhere (next suspect: SMI/M4U fetch path).

## CAPTURE 238 result + BUILD #239 — mid-chain backpressure dump (banner #86), 2026-07-10

**Capture:** `logs/2026-07-10-238-b17-ovl0-reset-poke-boot.log` (banner #85
verified). **Wedged-FSM hypothesis DISPROVEN:** the OVL_RST pulse took
effect (STA 0x1f→0x1e, INTSTA cleared to 0), but within 500 ms OVL0 was
back to INTSTA 0x2014 (FME_UND + ABNORMAL_SOF, no FME_CPL). The failure is
live, not stuck LK state.

**Breakthrough from the same capture:** offset +0x240 — previously
misread as a GMC register — is OVL_FLOW_CTRL_DBG, the FSM debug register,
decodable with vendor `ddp_ovl.c ovl_printf_status()`. OVL0 = 0x080f1020:
FSM state 0x020 = eng_act (processing), ovl_running=1, all four layer
RDMAs idle, and critically **out_valid=1 / out_ready=0** — OVL0 has output
pixels the downstream never accepts. OVL_2L0 = 0x080c1020: identical
signature. So the head of the pipeline is stalled on **backpressure from
the mid-chain** (COLOR0→CCORR→AAL0→GAMMA→OD0→DITHER0), which has never
been dumped — this also retro-explains FME_UND/ABNORMAL_SOF (frame can't
drain before the next DSI SOF) and RDMA0's FIFO underflow (nothing gets
through to it while DSI drains).

**BUILD #239 (banner `#86 SMP PREEMPT Fri Jul 10 06:54:53 UTC 2026`,
provenance `logs/2026-07-10-239-b17-midchain-backpressure-dump/`):**
zz-debug/0003 rewritten (poke removed, 2 passes @8s/+500ms) to dump the
mid-chain: COLOR0 (CFG_MAIN 0x400, START 0xc00, OUT_SEL 0xc08, internal
width/height 0xc50/0xc54), CCORR/AAL/GAMMA/OD/DITHER (EN 0x00, INTSTA
0x0c, CFG 0x20, IN_CNT 0x24, OUT_CNT 0x28, SIZE 0x30 — vendor ddp_reg.h
offsets), plus both OVLs' FLOW_CTRL_DBG/ADDCON_DBG and RDMA0/DSI0.

**Interpretation:** walk the chain; the blocker is the engine whose
IN_CNT advances while OUT_CNT stays 0, or the first whose IN_CNT stays 0
while the upstream is stalled out_valid — likely not started (COLOR START
reg?), zero SIZE, or wrong relay bit. Fix follows directly from which
engine it is.

## CAPTURE 240 result + BUILD #241 — OD0 is the blocker; relay-mode poke (banner #87), 2026-07-10

**Capture:** `logs/2026-07-10-240-b17-midchain-backpressure-dump-boot.log`
(banner #86 verified). **Blocking engine identified: OD0.** Pixel counters
across the two passes: CCORR IN/OUT frozen (y=1,x=15 / y=1,x=7); AAL
frozen; GAMMA crawling (~28 px per 500 ms); **OD0 IN_CNT frozen at
y=1,x=3 while OD0 OUT_CNT free-runs (hundreds of lines per pass)**;
DITHER0 streaming at full rate. OD0 blocks its input port and
self-generates output — it is the backpressure source stalling
GAMMA/AAL/CCORR/both-OVLs, while feeding DITHER→RDMA0→DSI a self-timed
stream (which is why DSI "works" and RDMA0 shows underflow-style
abnormal IRQs).

**Root cause (vendor `video/common/od10/ddp_od.c`):** OD_CFG[1:0] is the
mode field — 0x1 relay/bypass, 0x2 core-enable; vendor init default is
CFG=0x1. Mainline `mtk_od_config` writes OD_RELAYMODE (bit 0) but then
calls `mtk_dither_set`, which **overwrites** OD_CFG with DISP_DITHERING
(bit 2) only — hardware reads back 0x4: dither on, neither relay nor
core enabled, mode undefined. MT8173 tolerates this; MT6797's OD (needs
table/DRAM init we never do) does not.

**BUILD #241 (banner `#87 SMP PREEMPT Fri Jul 10 07:02:37 UTC 2026`,
sha256 `fd5022d044e623a497b72d2a244622b0e8dd791de5924365034e0980749afbb2`,
provenance `logs/2026-07-10-241-b17-od0-relay-poke/`):** zz-debug/0003 now
pokes OD0_CFG=0x5 (relay + dithering) after pass 1, then passes 2/3.
Expected if confirmed: CCORR/AAL/GAMMA counters unfreeze, OVL0 INTSTA
gains FME_CPL (bit 1), OVL FLOW_CTRL_DBG leaves eng_act/out_ready=0.
Proper fix then = drm patch making mtk_od_config preserve the relay bit
(write OD_CFG = RELAYMODE | dithering, or set relay after dither_set).

## CAPTURE 242 result — OD0 ROOT CAUSE CONFIRMED; new crash at first real scanout, 2026-07-10

**Capture:** `logs/2026-07-10-242-b17-od0-relay-poke-boot.log` (banner #87
verified; capture also contains the post-crash reboot into the `boot`
slot, banner #75 readout build — the device WDT-reset and fell back).

**The OD_CFG poke fixed flip_done.** Sequence in the log:
- 8.68s: pass 1 identical to capture 240 (OD0 blocking, CFG=0x4); poke
  writes CFG=0x5 (relay + dithering), reads back 0x5.
- 8.83s: `Console: switching to colour frame buffer device 135x135` —
  the atomic commit that has timed out on every build **completed**.
- 9.19s: `fb0: mediatekdrmfb frame buffer device`, SSD2092 panel
  registered.
- Pass 2 (9.19s): OVL0 STA=0x1d, INTSTA=0x200 (only layer-0 FIFO
  underflow latched — old FME_UND/ABNORMAL_SOF pattern gone), SRC_CON=0x1
  — a real plane was enabled and OVL0 started fetching an actual
  framebuffer via DMA. FME_CPL/vblank clearly fired (plane config is
  only applied from the vblank IRQ path).

**Conclusion (CONFIRMED):** the flip_done/vblank timeout root cause is
mainline `mtk_od_config` writing OD_RELAYMODE then letting
`mtk_dither_set` overwrite OD_CFG with DISP_DITHERING only → OD_CFG=0x4,
mode undefined; MT6797's OD blocks its input and free-runs its output.
Poking relay mode (0x5) instantly unstuck the whole pipeline.

**New, separate crash:** ~9.21s, immediately after
`clk: Disabling unused clocks` and ~0.4s into first real scanout, the
pass-2 dump stopped mid-read (after ovl0+0x02c; next read 0x240 never
printed), serial degraded to garbage, WDT reset → Android slot. Two
suspects: (1) SMI larb0 IOMMU-bypass gap (blockers.md B-13 finding from
vendor source) — first real layer DMA through larb0 wedges the MM bus;
the freshly latched layer-0 FIFO-underflow bit fits a starving fetch;
(2) late clk cleanup gating a now-needed clock (e.g. imgpll losing its
last reference). Plan: proper OD fix as drm/0014 + one build with
`clk_ignore_unused` temporarily restored to separate the suspects.

## BUILD #243 — proper OD relay fix (drm/0014) + temporary clk_ignore_unused (banner #88), 2026-07-10

**New permanent patch:**
`patches/v6.6/drm/0014-drm-mediatek-preserve-OD-relay-mode-after-dither-set.patch`
— in `mtk_od_config()`, after `mtk_dither_set()` (which overwrites OD_CFG
with the dithering bit alone), re-assert OD_RELAYMODE with
`mtk_ddp_write_mask()` so OD_CFG ends as 0x5 (relay + dithering) instead
of 0x4 (no mode). Sourced from vendor common/od10/ddp_od.c (OD_CFG[1:0]:
0x1 relay, 0x2 core-en). Upstream candidate. The zz-debug/0003 OD poke is
retained — it now writes 0x5 over an already-correct 0x5, doubling as
verification (pre CFG should read 0x5 this time).

**Temporary:** `clk_ignore_unused` re-added to
`configs/gemini-cmdline.config` (comment block marks it TEMPORARY) to
split the capture-242 scanout crash: if the WDT reset still happens with
late clk cleanup disabled, the clk path is exonerated and the SMI larb0
IOMMU-bypass gap becomes the prime suspect.

Banner `#88 SMP PREEMPT Fri Jul 10 07:26:07 UTC 2026`, sha256
`959273f616bfcad4682b71c0a0bda688a353c4cd7f8a01db92540a681fc5ac6e`,
provenance `logs/2026-07-10-243-b17-od-relay-fix-clk-ignore/`.

**Expected:** commit completes without any poke (fbcon by ~1 s rather
than after the 8.7 s poke). Outcomes: (a) survives + panel shows fbcon →
crash was clk cleanup, fix = proper clk refs; (b) WDT reset again at
first scanout → SMI/M4U path next; (c) no fbcon at all → fix regression,
inspect OD_CFG in dump.

## CAPTURE 244 result — FLIP_DONE FIXED, FULL CLEAN BOOT WITH DISPLAY STACK (banner #88), 2026-07-10

**Capture:** `logs/2026-07-10-244-b17-od-relay-fix-clk-ignore-boot.log`
(banner #88 verified). **Best display-stack boot of the project:**
- fbcon bound at 1.01 s (`Console: switching to colour frame buffer
  device 135x135`), `fb0: mediatekdrmfb` at 1.28 s — no poke involved;
  dump pass 1 reads OD0_CFG=0x5 already, confirming drm/0014.
- Zero flip_done / vblank-wait timeouts, zero WARNINGs.
- All three dump passes completed; no WDT reset; boot to
  `graphical.target` in 10.076 s; Debian login prompt on ttyS0.

**Conclusions:** (1) drm/0014 (preserve OD relay mode) is the proper,
validated fix for the flip_done/vblank timeout — pipeline now completes
frames continuously. (2) The capture-242 scanout crash did NOT reproduce
with `clk_ignore_unused` → prime suspect is late clk cleanup disabling a
display-needed clock (SMI/M4U gap did not bite during a full boot of
real scanout). Remaining follow-up: identify which clock the late
cleanup killed (likely an unreferenced parent in the mm/imgpll tree),
fix the reference properly, drop the TEMPORARY cmdline flag, then strip
zz-debug and rebuild production config (USB restored).

## CAPTURE 244 follow-up + BUILD #245 — panel dark w/ backlight lit; full DSI reg dump (banner #89), 2026-07-10

Physical observation on build #243's clean boot: **backlight lit, image
black**. PWM confirmed on via serial login (`/sys/kernel/debug/pwm`:
pwm-0 enabled, duty=period; brightness 200/255, bl_power=0). Pixels
aren't reaching the glass despite the pipeline completing frames →
suspect DSI video timing/format mismatch vs. what the panel expects.
`/dev/mem` reads return nothing (kernel config blocks it), so the diff
moves into the debug module.

**Golden reference in hand:** LK dumps its working DSI block
(`DSI+0000..0180`) in every capture — 4 lanes, packed RGB888
(PSCTRL=0x00030ca8), VSA=3/VBP=0xf/VFP=0xa/VACT=0x870,
HSA_WC=0x1c/HBP_WC=0x94/HFP_WC=0x74, PHY_TIMCON 0x080f0708/0x10280c20/
0x0a280100/0x00102406.

**BUILD #245 (banner `#89 SMP PREEMPT Fri Jul 10 07:42:25 UTC 2026`,
sha256 `0503b139b34e55b1997b006ea116b23633e6b4a38af8a4fc6225bcc37f2f4647`,
provenance `logs/2026-07-10-245-b17-full-dsi-reg-dump/`):** zz-debug/0003
dsi0 dump extended from 4 regs to the full 0x000–0x1AC block, dumped
each pass. Next capture: diff kernel values against LK's lines from the
same log; mismatches in lane count, PS format, porches or PHY timing
name the fix.

## CAPTURE 246 result — DSI diff done: EOT/clock-mode + porch mismatches + BUILD #247 (banner #90), 2026-07-10

Capture `logs/2026-07-10-246-b17-full-dsi-reg-dump-boot.log` (banner #89
verified; clean boot to prompt again; panel still backlit-black). Full
kernel DSI dump diffed against LK's golden dump (capture 244):

**Matching:** PSCTRL 0x00030ca8 (packed RGB888, 3240 B/line), VACT 0x870,
4 lanes, video sync-pulse mode, 0x100=0x55, 0x10c=0xb8, 0x130=0x21,
0x90=0x3c, 0xa0/0xa4. Not a gross format/lane mismatch.

**Mismatches:**
- **TXRX_CTRL (0x18): LK 0x0001003c vs kernel 0x0000007c.** LK sends EOT
  packets (bit6 DIS_EOT clear) and lets the HS clock drop to LP between
  transmissions (bit16 HSTX_CKLP_EN). Kernel disables EOT and runs a
  continuous clock — mtk_dsi sets DIS_EOT unless the panel declares
  MIPI_DSI_MODE_NO_EOT_PACKET (inverted-looking logic, mtk_dsi.c:410).
  Prime suspect for backlit-black: panels commonly reject HS video
  without EOT.
- **Vertical porches: LK VSA=3/VBP=15/VFP=10 vs kernel 1/43/76** — the
  panel patch had used vendor-3.18 LCM source values; LK (which provably
  lights the panel) programs different ones. vtotal 2188 vs 2280.
- **Horizontal WCs: LK 0x1c/0x94/0x74 vs kernel 0x02/0x32/0x4e** — much
  narrower blanking.
- PHY_TIMCON differs moderately (LK longer margins) — left alone this
  build to keep attribution clean.

**BUILD #247 (banner `#90 SMP PREEMPT Fri Jul 10 07:55:01 UTC 2026`,
sha256 `617c69c15ab7605abf89fe575274a5c4f0e473e12be598dd5d418f3b95fe09a1`,
provenance `logs/2026-07-10-247-b17-lk-dsi-timing-eot/`):** panel/0005
updated: (1) mode_flags += MIPI_DSI_MODE_NO_EOT_PACKET |
MIPI_DSI_CLOCK_NON_CONTINUOUS → TXRX_CTRL becomes bit-identical to LK's
0x1003c; (2) mode timings adopted from LK registers: VSA=3 VBP=15 VFP=10,
HSA=13 HBP=53 HFP=42 (reversed through mainline's px*3−10 WC formula,
within one byte of LK), clock 155961 kHz (1188×2188×60). Expected next
capture: TXRX_CTRL=0x1003c and porch regs matching LK in the dump —
and, if EOT/porches were the blocker, pixels on the glass.

## CAPTURE 248 result — registers now LK-identical, still black; panel side implicated + BUILD #249 (banner #91), 2026-07-10

Capture `logs/2026-07-10-248-b17-lk-dsi-timing-eot-boot.log` (banner #90
verified). All intended register changes landed: TXRX_CTRL=0x0001003c
(bit-identical to LK), VSA/VBP/VFP=3/15/10, HSA_WC=0x1d (LK 0x1c). DSI
INTSTA=0x80000790 across all passes (busy, frame-done/VM-done cycling,
no error bits), zero flip_done timeouts — the link streams frames
correctly. **Panel still black.** Remaining reg diffs (0x64/0x68/0x88 =
BLLP_WC/MEM_CONTI-class housekeeping per vendor ddp_dsi.c) are not
blank-screen material. Controller-misconfig theory exhausted.

**Decisive user observation: the Planet logo IS displayed by LK, then
goes dark at kernel takeover.** Panel hardware + LK init proven good;
our driver's takeover (reset pulse / avdd+avee toggling / init table)
kills it. Note the vendor 3.18 tree has NO ssd2092 LCM source (Halium
stripped it), so the init table can't be source-checked — the panel
must be interrogated directly.

**BUILD #249 (banner `#91 SMP PREEMPT Fri Jul 10 08:09:14 UTC 2026`,
sha256 `a0723a8757995c3ef91e199e74362d1f9f4f6168560fcadea443a836add68323`,
provenance `logs/2026-07-10-249-b17-panel-dcs-readback/`):** new
zz-debug/0004: differential DCS read-back in the panel driver — reads
0x0a/0x0b/0x0c/0x0d/0x0e (1) at the top of prepare(), before our reset
pulse, while the panel still holds LK's working state (expect
0x0a=0x9c; also validates the read path), and (2) after our init
sequence. Interpretation: pre-reset read fails → read plumbing broken
(inconclusive); pre-reset good + post-init dead → our reset/init breaks
the panel; both good but black → panel-internal format/mapping issue.

## CAPTURE 250 result — PANEL-DARK ROOT CAUSE: TPS65132 bias never programmed + BUILD #251 (banner #92), 2026-07-10

Capture `logs/2026-07-10-250-b17-panel-dcs-readback-boot.log` (banner #91
verified). Read-back results: pre-reset reads all timed out (-62; panel
in LK video state, secondary). **Post-init reads all succeed: 0x0a=0x1c
— sleep-out ✓, normal mode ✓, display ON ✓, but bit7 (booster) OFF.**
The panel is fully initialized and displaying — it has no analog drive
voltage. 0x0c=0x70 (24bpp) correct.

**Root cause chain:** AVDD/AVEE come from a TI TPS65132 charge pump on
I2C1 @0x3e (ENP=GPIO60, ENN=GPIO251 — vendor DTB aeon_lcd_bias pin
nodes decode to these). Its VPOS/VNEG output registers are volatile;
LK programs them over I2C on EVERY boot — visible in our own captures
as `SSD2092--------cmd=0/1--i2c write success` (0x0E = 5.4 V). Our DTS
modelled the bias as GPIO-only fixed regulators; the panel driver
power-cycles them in prepare(), the chip comes back unprogrammed, the
panel booster finds no rails → backlit black. The old DTS comment even
documented the needed I2C writes — never implemented.

**BUILD #251 (banner `#92 SMP PREEMPT Fri Jul 10 08:19:04 UTC 2026`,
sha256 `1dd49fd25faec05a349b080ce3403dd1fa78a444bed24cdc3f364908fd3a8cdf`,
provenance `logs/2026-07-10-251-b17-tps65132-bias/`):** dts/0001 —
lcd_avdd/lcd_avee fixed regulators replaced with a `ti,tps65132` node
on &i2c1 (outp/outn, min=max=5.4 V so the core applies the voltage via
the driver's I2C write on enable, enable-gpios 60/251);
gemini-display.config += CONFIG_REGULATOR_TPS65132=y (mainline driver).
DTB spot-checked in the packed image. zz-debug/0004 read-back retained:
expected next capture — post-init 0x0a=0x9c (booster ON) and pixels on
the glass.

## CAPTURE 252/253 result — tps65132 probe -ETIMEDOUT; I2C1 combined-transfer bug found + BUILD #254 (banner #93), 2026-07-10

Capture 252 (banner #92): tps65132 probe failed (`regulator
tps65132-outp register failed: -110`) → panel driver never probed → LK's
scanout was left running (Planet logo stayed on the glass through a full
boot to prompt — incidentally proving the kernel boots clean without
ever touching the display pipeline it inherited).

Interactive session (capture 253, first use of `--interactive`):
`i2cdetect -l` shows 4 mt65xx adapters; `i2cdetect -y -r 1` sees the
whole bus fine — 0x25 (fusb301a), **0x3e (TPS65132)**, 0x48, 0x69
(bmi160) all ACK; but `i2cget -y 1 0x3e 0x00` fails. Diagnosis:
single-message transfers work, **combined write-then-read (repeated
start / WRRD) fails** — exactly what the tps65132 regmap read does.
Root cause: mainline mt6797.dtsi i2c nodes fall back to the
"mediatek,mt6577-i2c" compat (auto_restart=0, aux_len_reg=0 — no WRRD),
but MT6797's I2C block is MT8173-generation (vendor mt6797 mt_i2c uses
DIR_CHANGE + TRANSFER_LEN_AUX and 33-bit DMA).

**BUILD #254 (banner `#93 SMP PREEMPT Fri Jul 10 08:30:35 UTC 2026`,
sha256 `456d1fe4ab29db27ccb113497368aa75b5acae0fed2a1fd5608ebf3677756c36`,
provenance `logs/2026-07-10-254-b17-i2c-mt6797-wrrd/`):** new patch
`i2c/0001` — add `{ "mediatek,mt6797-i2c", &mt8173_compat }` to
i2c-mt65xx (the dtsi already lists mt6797-i2c as primary compat; no DTS
change needed). Upstream candidate. Expected: tps65132 probes, panel
binds, booster ON, pixels.

## CAPTURE 255 result — FIRST PIXELS; supply side fully verified; init table is the last suspect + BUILD #256 (banner #94), 2026-07-10

Capture 255 (banner #93): I2C fix works — tps65132 probed and programmed
the bias over I2C (`Bringing 5500000uV into 5400000-5400000uV`). Panel
init ran; fbcon bound at 11.09s and the user saw **real pixels**
(horizontal bands) for a moment before the glass went black. Live
interactive audit afterwards: TPS65132 VPOS/VNEG read back 0x0e (±5.4V,
LK-identical), both EN GPIOs (572/763 = pins 60/251) physically high,
panel reset (gpio-692/pin 180) deasserted, PWM at 100% duty, backlight
visibly glowing, DRM state scanning plane-0/fbcon on crtc-0, DSI
INTSTA frame-done cycling. Panel post-init reads: display ON, sleep out,
24bpp — but **0x0a bit7 (booster) still 0**. Everything measurable is
good except the panel's internal drive stage; hypothesis: our init
table trips the panel's protection moments after drive starts (the
brief pixels), leaving it dark. Init table provenance can't be
source-verified (no ssd2092 LCM in the vendor 3.18 tree).

**BUILD #256 (banner `#94 SMP PREEMPT Fri Jul 10 08:45:02 UTC 2026`,
sha256 `f4c2e97de6b6d3da541c5635df08ef49ab0b69c49a0e63a407dbf8625651b930`,
provenance `logs/2026-07-10-256-b17-panel-skip-init-keep-lk/`):** new
zz-debug/0005 — skip-init experiment: prepare() keeps regulator enables
and the DCS read-back but performs NO reset pulse and NO init table;
LK's proven init survives and our LK-identical video stream attaches to
it. Pixels persisting ⇒ init table is the culprit. The read-back also
finally samples a known-good LK-initialized panel in cmd mode —
calibrating whether 0x0a bit7=0 is even abnormal for this panel.

## CAPTURE 257 result — init table ACQUITTED; suspect moves to D-PHY lane rate + BUILD #258 (banner #95), 2026-07-10

Capture 257 (banner #94): skip-init build — LK's init preserved
untouched (logo died at 0.556s when mtk_dsi_poweron reset the host, as
expected for a video-mode panel losing its stream), our LK-identical
stream attached at 10.8s… **still black**. (LK-state panel also doesn't
answer LP reads — all -62 — so the read-back calibration was
inconclusive.) With init, controller registers, bias, backlight and
pipeline all eliminated, the only never-compared layer is the analog
D-PHY (mipi_tx0 @0x10215000). Physics motive: mainline derives the lane
rate from the pixel clock (155961 kHz × 24 / 4 ≈ 936 Mbps) but the
vendor LCM ran a fixed PLL_CLOCK=502 MHz (1004 Mbps) — the SSD2092's
init contains MIPI RX trims tuned for that rate; a receiver that can't
lock shows exactly this signature (LP ACKs fine, HS video invisible).
LK dumps its working PHY (`DSI_PHY+0000..0090`) in every capture.

**BUILD #258 (banner `#95 SMP PREEMPT Fri Jul 10 08:49:50 UTC 2026`,
sha256 `bb07aebe74f845020824b2961ebb4b983f813e4d5b0019378a9a606de845e40e`,
provenance `logs/2026-07-10-258-b17-mipitx-phy-dump/`):** zz-debug/0003
gains a `mipitx0 @0x10215000` block (0x00–0xAC, every reg) for the
kernel-vs-LK PHY diff. zz-debug/0005 (skip-init) retained so the panel
state matches LK's during the diff. Next capture: line up kernel
mipitx0 values against LK's DSI_PHY dump; a PLL divider mismatch names
the fix (match LK's 1004 Mbps lane rate).

## CAPTURE 259 result — PHY PLL BUG FOUND: lanes at half rate + BUILD #260 (banner #96), 2026-07-10

Capture 259 (banner #95): kernel mipitx0 dump vs LK's DSI_PHY dump
(capture 255). Lane/BG/SW regs identical; PLL differs: LK CON0
0xf0002001 / PCW 0x43b13b13 (67.69) vs kernel CON0 0xf0002011 (POSDIV
÷2) / PCW 0x47fb645a (71.98). Vendor formula recovered from 3.18
ddp_dsi.c DSI_PHY_clk_setting: fixed S2Q ÷2 stage always in the chain,
pcw = rate(Mbps)*ratio/13, ≥500 Mbps → posdiv=0. LK decodes to
**880 Mbps** (not the LCM comment's 1004). Our phy/0004 table was one
octave off (posdiv one step too high per range): PCW right for 936 Mbps
but extra ÷2 → **lanes ran at 468 Mbps, half rate**. Panel receiver
can't lock half-rate HS → LP ACKs fine, video invisible — matches every
symptom including the transient pixels.

**BUILD #260 (banner `#96 SMP PREEMPT Fri Jul 10 08:57:37 UTC 2026`,
sha256 `9df61650fa2dd2c1e952679ca17f2cee6fe1d8700acd77347eaaf496f45a4707`,
provenance `logs/2026-07-10-260-b17-mipitx-pll-octave-fix/`):**
phy/0004 fixed: vendor POSDIV table (≥500M→0 … ≥50M→4, limit 1250M) and
PCW gains the ×2 S2Q compensation. Expected mipitx0 regs: CON0
0xf0002001, PCW ≈ 0x48000000 (936 Mbps). zz-debug/0005 (skip-init) still
in — cleanest test: LK's init + correct-rate stream. If pixels persist,
next build re-enables our init table and strips skip-init.

## CAPTURE 261 — PLL fix confirmed, FIRST KERNEL PIXELS (flicker), residual rate mismatch + BUILD #262 (banner #97) — 2026-07-10

Log: `logs/2026-07-10-261-b17-mipitx-pll-octave-fix-boot.log` (banner #96 ✓).

**PLL fix verified in-register:** mipitx0+0x050 (PLL_CON0) = `0xf0002001` —
POSDIV now ÷1 (was ÷2), PCW `0x47fb645a` (71.98) → **936 Mbps/lane**, exactly
as computed. Boot fully clean: fbcon bound 10.7s, graphical.target 20s, zero
DSI errors. Skip-init (zz-debug/0005) active; pre-reset DCS reads all -62 as
always (LK-mode panel doesn't answer LP reads).

**On the glass:** first boot of this build (no FTDI attached, user report):
Planet logo → **screen flashed lots of colors** — the panel visibly receiving
kernel HS video for the first time in the project. Second boot (captured):
logo → dark. Intermittent lock.

**Interpretation — one rate mismatch left:** LK drives this panel at
**880 Mbps** (its own PLL dump: PCW 0x43b13b13, POSDIV ÷1), but our mode
clock 155961 kHz × 24bpp ÷ 4 lanes demands 936. With LK's init preserved,
we streamed 936 at a panel configured for 880 — close enough to almost lock
(flicker), not enough to hold. Nondeterministic across boots = marginal lock.

**BUILD #262** `logs/2026-07-10-262-b17-lk-rate-880-own-init/`, sha256
`f9511cf561421aa34f680165a101a754c6611f1698d25433d176af5eef74d7b8`, banner
`#97 SMP PREEMPT Fri Jul 10 09:07:59 UTC 2026`. Two changes:
1. panel/0005 `.clock` 155961 → **146667** kHz (= 880e6·4/24, LK's exact
   measured rate; ~56.4 Hz refresh — LK never ran this panel at 60 Hz).
2. zz-debug/0005 skip-init **deleted** — our full reset + init table runs
   again, now validated end-to-end at the proven rate (needed anyway for
   cold boots without LK's init).

Expected: mipitx0 PCW ≈ 0x43b13b13-ish, POSDIV ÷1 (880 Mbps); post-init DCS
reads answering (0x0a=0x1c etc.); stable pixels/fbcon on the glass.

## CAPTURE 263 — build #262 was a dud (patch-edit truncated the panel driver) + BUILD #264 (banner #98) — 2026-07-10

Log: `logs/2026-07-10-263-b17-lk-rate-880-own-init-boot.log` (banner #97 ✓).
Planet logo persisted; boot clean to graphical.target 9s, but **no DRM bind
at all** — zero "bound" lines, no fbcon, no GEMINI-PANEL messages.

Live diagnosis over serial: `devices_deferred` empty; tps65132 bound fine
(regulator_summary shows lcd_avdd/lcd_avee 5400 mV); panel device
`1401c000.dsi.0` present but driverless; `/sys/bus/mipi-dsi/drivers/` has no
panel-solomon-ssd2092 at all. Build forensics: build #262's System.map has
**zero** ssd2092 symbols (build #260 had 14); the compiled .o was 32 bytes.

**Root cause (assistant error, not hardware):** the hand-edit of
panel/0005's mode-clock comment added 5 lines inside the new-file hunk
without updating the `@@ -0,0 +1,516 @@` count. `git apply` took only 516
lines and silently dropped the patch tail — including
`module_mipi_dsi_driver(ssd2092_driver);` — so the whole driver was
dead-code-eliminated. Kconfig/Makefile hunks were intact, so the build
"succeeded". Fixed by correcting the hunk header to `+1,521` and verifying
the applied file ends with MODULE_LICENSE (521 lines) and that
zz-debug/0004 still applies. Lesson: after hand-editing a patch, verify the
applied file's tail, not just `git apply --check` (which did NOT catch
this).

**BUILD #264** `logs/2026-07-10-264-b17-lk-rate-880-own-init-fixed/`, sha256
`4c33ed087928b8c426189cbe2854ddbd52f3ac1d4776cb9d181448ee51b4b605`, banner
`#98 SMP PREEMPT Fri Jul 10 09:18:07 UTC 2026`. Same intent as #262 (LK
880 Mbps clock 146667 kHz + our full init, skip-init removed); System.map
now shows 15 ssd2092 symbols. Expected: mipitx0 PCW ≈ 0x43b1…, POSDIV ÷1
(880 Mbps); post-init DCS reads answer; stable pixels on the glass.

## CAPTURE 267 — kernel-side signals all healthy while panel is dark; BUILD #268 adds live poke debugfs — 2026-07-10

Log: `logs/2026-07-10-267-b17-lk-rate-880-own-init-fixed-boot.log` (banner #98,
build #264 — LK rate 880 Mbps + our full init). Boot showed pixels (planet
logo, then color/white/pattern content responsive to `/dev/fb0` writes),
then faded to black on its own during the session — same "fade" symptom as
several earlier builds, but this time fully instrumented live over SSH
while it was happening:

- fb0 writes (white fill, RGB bar test) succeeded (`echo $?` = 0), correct
  geometry (1080x2160, 32bpp) — no format/stride bug.
- DRM atomic state: plane-0 bound to crtc-0, fbcon's framebuffer, correct
  1080x2160 size, still "active" from software's point of view.
- PWM: `pwm-0 (backlight)` enabled, duty=period=39385ns (100% duty).
- backlight class: brightness=actual=max=255, bl_power=0 (on).
- reset GPIO (gpio-692, pin 180, ACTIVE LOW): driven **high** = inactive,
  panel not held in reset.
- uptime/dmesg: no reboot, no watchdog reset, no crash — 15+ minutes clean.

**Conclusion:** every Linux-side signal in the pipeline (PWM, DRM, fb,
GPIO) is healthy and unchanged; the panel itself has silently gone dark
without the kernel doing anything to it after boot. This narrows the "fade"
bug to inside the SSD2092 panel: either it self-triggers a sleep/low-power
mode, or its internal booster (DCS 0x0a bit7) drops after some time/thermal
condition, invisible to the driver because it never re-polls status after
`prepare()`.

**BUILD #268** `logs/2026-07-10-268-b17-panel-live-poke-debugfs/`, sha256
`81f2323ed2ea19858c74d22c08a4b8182281a9daad16e252792a4f9e90d0aea3`, banner
`#99 SMP PREEMPT Fri Jul 10 09:58:48 UTC 2026`. Adds
`zz-debug/0005-GEMINI-DEBUG-panel-live-poke.patch`: a
`/sys/kernel/debug/gemini_panel_poke` debugfs write trigger that, on demand
(`echo 1 > .../gemini_panel_poke`), re-reads DCS status regs 0x0a-0x0e live,
re-sends sleep-out(0x11)+display-on(0x29), and re-reads again — all via
dev_info, visible on serial without needing a reboot. Plan: reproduce the
fade, then poke and read the live DCS state to see whether the panel
reports itself asleep/booster-off, and whether the re-nudge revives it.

## CAPTURE 269 — poke revives the picture then it fades again; BUILD #270 adds on-demand DDP dump — 2026-07-10

Log: `logs/2026-07-10-269-b17-panel-live-poke-debugfs-boot.log` (banner #99,
build #268). `echo 1 > /sys/kernel/debug/gemini_panel_poke` was run while
the glass was dark. DCS reads were mostly inconclusive by design — this
panel doesn't answer register reads while the DSI engine is actively
streaming HS video (`[drm] dsi get 0 byte data from the panel address`,
i.e. the transaction "succeeds" with zero payload bytes; two full -62
timeouts too). Not proof of anything wrong — the read path itself doesn't
work mid-stream.

**But the re-nudge (sleep-out 0x11 + display-on 0x29) visibly revived the
picture** — horizontal-block pattern reappeared on the glass — **then
faded to black again within a couple seconds**, same as every prior fade.
This rules "panel silently entered sleep and stayed there" *out*: sending
the same two commands that already ran during our normal init briefly
un-blanks it, so the panel is still receiving and reacting to the DSI
stream; something in the pipeline (or the panel's own internal state) is
periodically re-entering a blocked/blanked condition after being unblocked.

Checked whether this is a recurrence of the OD_CFG relay-mode clobber
(build #243, `drm/0014`): no — that fix re-asserts relay mode *inside*
`mtk_od_config()` itself via `mtk_ddp_write_mask`, so it self-heals on
every call regardless of how often the function runs; not a plausible
repeat offender from that specific bug.

**BUILD #270** `logs/2026-07-10-270-b17-ddp-dump-on-demand/`, sha256
`598dd6e61e682659473a01aec74a76dca050bbfce39c21aae1a016ba6e2db0f4`, banner
`#100 SMP PREEMPT Fri Jul 10 10:06:58 UTC 2026`. Adds
`zz-debug/0006-GEMINI-DEBUG-ddp-dump-on-demand.patch`: extends the boot-time
`gemini-ddp-dump.c` (3 passes at 8s/+500ms, ovl/color/ccorr/aal/gamma/od/
dither/rdma/dsi0/mipitx0) with a `/sys/kernel/debug/gemini_ddp_dump_now`
write-trigger, so the full register set (esp. OD0_CFG, DSI0 status/IRQ
regs, mipitx0 PLL) can be captured live at the moment of a fade, alongside
the existing panel poke. Plan: reproduce the fade, dump immediately before
touching anything, dump again after the poke revives it, diff the two —
whichever block differs (frozen counter, wrong CFG value, PLL unlock) names
the recurring blocker.

## BUILD #272 — periodic panel keepalive workaround (fade stabilizer) — 2026-07-10

Confirmed live: continuous `/dev/fb0` writes (color-cycling loop) keep the
panel lit indefinitely — never fades, gets *brighter* with fresh content
(photo IMG_2627). This rules out a hardware/electrical fault outright
(stock Android on the same physical hardware/cable/bias chip never
exhibits the fade either, per user). Checked `mtk_ovl_disable_vblank()`
(masks OVL_FME_CPL IRQ only, doesn't touch scanout — DDP dumps already
proved OVL keeps completing frames while dark) and `mtk_dsi.c` (no
autosuspend/idle timer) — neither explains the mechanism. Root cause of
*why* static content fades while a live SoC-side pipeline doesn't is still
unknown; parking further hunting.

**BUILD #272** `logs/2026-07-10-272-b17-panel-keepalive-workaround/`, sha256
`808eb3d52798395dada11a4c45e290f310f986387e6c3bc036e4900142d9cf2a`, banner
`#101 SMP PREEMPT Fri Jul 10 11:29:33 UTC 2026`. Adds
`zz-debug/0007-GEMINI-WORKAROUND-panel-keepalive.patch`: a
`delayed_work` in the panel driver that re-sends sleep-out(0x11)+
display-on(0x29) — the same pair `gemini_panel_poke` proved revives the
picture — once per second for as long as the panel is enabled, started in
`ssd2092_enable()` and cancelled in `ssd2092_disable()`. This is an
explicit workaround, not a fix (labelled as such in the patch header) —
remove once the actual trigger is found. Candidates for the real cause,
for whoever picks this up: something in the DRM fbdev/fbcon idle/damage
path that behaves differently for a static vs. changing image, or a
content-adaptive brightness/idle feature inside the SSD2092 itself
distinct from sleep mode (since ESD-check is confirmed disabled in the
vendor 3.18 driver, ruling that specific mechanism out).

## BUILD #274 — keepalive tuned to 250ms for full brightness — 2026-07-10

User confirmed build #272's 1 Hz keepalive holds the picture lit (no fade)
through 30+ seconds static at the login prompt — the workaround works.
Photo (IMG_2629) showed a real, undamaged LCD image (solid green fill,
backlight vignetting, top-line artifact) at reduced brightness vs. the
~4/s color-cycle test that originally revealed the fix. Confirms brightness
scales with update rate, not just on/off — content-adaptive behavior.

**BUILD #274** `logs/2026-07-10-274-b17-panel-keepalive-250ms/`, sha256
`ac80228d52a9618d252bcc4dd70b9718917b0ffa0e539ccb2918c09e4dd77a0f`, banner
`#102 SMP PREEMPT Fri Jul 10 11:38:24 UTC 2026`. `zz-debug/0007` keepalive
interval reduced from `HZ` (1 s) to `HZ / 4` (250 ms) to match the update
rate that produced full brightness. Expected: picture stays lit and as
bright as the rapid-cycle test, indefinitely, at a static prompt.

Known remaining items, in priority order: (1) verify brightness at 250ms
keepalive; (2) top-of-screen thin horizontal line artifact (separate,
likely vertical-timing/porch issue); (3) real root cause of the
static-content fade (workaround only); (4) strip zz-debug patches and
restore production USB config once the display is fully stable; (5) pin
the clock `clk_ignore_unused` currently masks (capture 242 crash, still
parked).

## BUILD #276 — CABC-disable attempted as real fix, keepalive disabled for isolation — 2026-07-10

Capture 275 (build #274, 250ms keepalive) still faded to black despite the
DSI IRQ trace confirming the keepalive's sleep-out/display-on writes fired
continuously throughout (no timeouts, no errors). This falsifies the
"resending commands helps" theory — the earlier apparent revival from
manual poking was likely a brief re-lit window, not a real fix. The
distinguishing factor is specifically **framebuffer content changing**,
not DSI command traffic.

That points at CABC (Content-Adaptive Backlight Control) — a standard
mobile-panel feature that dims static/low-motion content to save power.
Neither the vendor init table nor ours sends any CABC command (0x51/0x53/
0x55) at all; if this panel defaults to CABC-on at reset (common), nothing
in either driver has ever disabled it. Android's compositor redraws
continuously (status bar clock, animations) even on a nominally static
screen, which would mask CABC entirely — explaining why stock Android
never shows the fade while our idle mainline console does.

**BUILD #276** `logs/2026-07-10-276-b17-panel-cabc-disable-test/`, sha256
`14ebebb8e8a49c506ed876b3b6709b8201e30a7c476f8e2d1a978583fc2bd7bb`, banner
`#103 SMP PREEMPT Fri Jul 10 11:47:24 UTC 2026`. Adds
`panel/0006-drm-panel-ssd2092-disable-cabc-force-max-brightness.patch`:
after the init table's sleep-out+display-on, sends `0x51 0xff` (max
manual brightness), `0x53 0x24` (BCTRL+BL on), `0x55 0x00` (CABC off) —
standard MIPI DCS commands. `zz-debug/0007` (keepalive workaround)
**disabled** (renamed `.disabled`) for this build so the CABC fix can be
tested in isolation, not masked by the workaround. If this holds a static
screen lit indefinitely, it supersedes the keepalive workaround entirely
(delete 0007) and is a genuine fix, not a mitigation.

**Result (2026-07-10): CABC-disable did NOT fix the fade.** User reported
the same horizontal-block-rows-fade-to-black behavior on build #276 as on
every prior build — standard DCS CABC-disable commands sent successfully
(no I/O errors) but had zero effect. This panel's proprietary controller
(heavy 0xB0-0xBD custom register use per vendor init table) most likely
doesn't implement standard MIPI CABC at all, so this theory is now
falsified alongside the DSI-command-resend theory. Both confirm: the fade
is tied specifically to framebuffer *content* not changing, not to any
DSI command traffic (of either kind) reaching the panel.

## Userspace keepalive workaround, take 2 — full-frame writes vs. single-pixel — 2026-07-10/11

Given two kernel-level fix attempts falsified, pivoted to a pragmatic
userspace workaround on the live device (not a kernel patch): a systemd
service (`gemini-fb-keepalive.service`, `Restart=always`,
`/usr/local/bin/gemini-fb-keepalive.sh`) that continuously rewrites
`/dev/fb0` to keep the panel lit, installed directly via a live serial
session (pyserial to `/dev/cu.usbserial-B001VBPM`) rather than a rootfs
rebuild — **this is NOT yet folded into `scripts/mkrootfs.sh`**, so it will
be lost on any future rootfs reflash/rebuild unless added there.

First attempt: toggling a single 4-byte corner pixel every 100ms via plain
`write()`. Result: **did not prevent the fade** — screen went to
backlight-on/blank even with the service confirmed `active (running)`.
Register dump (`gemini_ddp_dump_now`) taken during the blank period showed
the full DDP pipeline still healthy (OD relay mode 0x5, OVL/RDMA/color/
ccorr/aal/gamma/dither all enabled, DSI still streaming) — same signature
as every previous fade, confirming the SoC-side pipeline is not the
problem; the panel itself is doing something independent of pipeline
health. A single small, infrequent write is not enough to prevent it.

Second attempt: pre-generated two full-framebuffer pattern files
(`/usr/local/lib/gemini-fb-{white,black}.bin`, 9,331,200 bytes each =
1080×2160×4) and rewrote the script to `dd` them alternately in a tight
loop (no sleep) instead of poking one pixel. Result: **holds the display
lit and stable** — user confirmed "screen is solid white with a few thin
black lines at the top - stable display" after a reboot + relogin cycle.
This is the first successful userspace mitigation and matches the
originally-observed empirical fact (this session's predecessor) that fast
full-frame content changes prevent the fade and increase brightness,
while sparse/small writes do not.

The thin black lines at the top are the pre-existing, separate
vertical-timing/porch artifact (tracked as its own open item, blocking
readable console text) — not related to the fade.

**Root cause of the fade itself remains unknown.** Two theories now
falsified (DSI command resend at up to 4 Hz; standard MIPI CABC disable).
Leading remaining candidates: (a) a DRM fbdev/fbcon damage-tracking/idle
path that treats static vs. changing content differently, something
Android's continuously-compositing stack never exercises; (b) a
panel-internal content-adaptive/dimming feature that only responds to
real GRAM writes reaching a large fraction of the panel fast, not
controllable via any DCS command tried so far — possibly needing
proprietary 0xB0-0xBD range commands this SSD2092 variant needs that
neither driver has ever sent.

Next steps: fold the keepalive script + pattern files + systemd unit into
`scripts/mkrootfs.sh` so it survives rootfs rebuilds; consider a lighter
CPU-cost variant (smaller regions changed faster, vs. full 9MB writes
twice per loop iteration) once proven this direction is the accepted
long-term approach; continue root-cause investigation if a proper fix is
still wanted instead of the workaround.

**Decision (2026-07-11): workaround accepted as "good enough for now."**
User confirmed the full-frame userspace keepalive is an acceptable interim
state — not closing the underlying issue. Explicitly flagged as needing
future improvement: (1) it currently only flashes solid white/black at
full brightness, not real content — no readable console/desktop is visible
through it yet; (2) it is not yet folded into `mkrootfs.sh`, so lost on
rootfs rebuild; (3) the actual fade root cause is still unknown (see
falsified theories above). Do not treat this as resolved — it's a known,
documented gap. Priority shifts now to the separate top-of-screen thin
horizontal line timing artifact, which is blocking readable text
regardless of the fade workaround.

**Tearing hypothesis tested and falsified (2026-07-11):** the keepalive
writes to `/dev/fb0` are unsynced single-buffered raw writes racing live
OVL scanout — a plausible source of a thin horizontal tear line. Test:
stopped `gemini-fb-keepalive.service` and watched the last static frame
before the display faded. **The thin line was still present on the static,
non-updating frame** ("the thin line remains" — user, immediately after
stop). A genuinely static frame cannot tear, so this rules out the
keepalive write pattern as the cause. The artifact is a real DSI/panel
timing defect, independent of the fade workaround. Service restarted to
relight the screen.

Leading candidate reopened: the still-unresolved single-word `HSA_WC`
mismatch from capture 248 (kernel 0x1d vs LK's 0x1c, `hsync_len=13` giving
`13*3-10=29=0x1d` per mainline's `mtk_dsi_ps_control` formula in
`mtk_dsi.c:475`) — previously judged "not blank-screen material" when the
screen was fully black, but re-examine now that real content is visible:
a 1-word HSA error is tiny (~1 pixel-time) and an unlikely sole cause of a
visible line, but worth first ruling out with an exact `hsync_len` value
LK actually uses (reverse the vendor formula precisely rather than
rounding) before looking elsewhere (vactive/vtotal off-by-one, VFP/VBP
line-count vs LK's, or a fixed OVL/RDMA offset in vertical start position).

**Full scatter-file recovery reflash + live stock-driver register read
(2026-07-11).** User performed a full SP Flash Tool scatter-file restore
(`Scatter_Gemini_x25_x27_A30GB_L26GB_Multi_Boot.txt` + 2019 stock images),
which resets all partitions to factory state — this wipes the Debian 13
rootfs (p29) and our custom Linux 6.6 `boot2` kernel, not just `boot2`
alone; both will need to be re-established afterward per CLAUDE.md's
"Root Filesystem" / "Flashing a Custom Kernel" sections. Goal: read live,
steady-state DSI PHY/mipitx register values from the genuinely-working
stock vendor driver, as a better reference than LK's one-shot boot-time
splash dump or further blind mainline-formula tuning.

Post-reflash observation: screen showed transient "ghostly white hue" /
slow-fading image retention after the stock Kali boot came up, most
likely residual LC relaxation from the prior session's full-frame
white/black keepalive pattern being held static for a long period —
cleared on its own after the panel ran normal (non-static) content for a
while. Not judged to be physical damage. Possibly relevant data point for
the fade-to-black investigation: this panel shows real, slow (multi-
second-to-minutes) retention/relaxation behaviour, consistent with a
liquid-crystal characteristic rather than a purely digital driver
artifact.

Access to the live stock system took several detours: UART was silent
(device's left USB-C port muxes UART vs. direct-USB, and USB was likely
connected during attempts); ADB was not exposed; the RNDIS/g_ether-style
gadget on the 2019 image (if any) did not respond on our custom
project's static IP/MAC (that config is ours, not the vendor's). Resolved
via: device already had Wi-Fi connected (IP `192.168.100.126` obtained
from the user reading the device's own screen/shell) with `sshd` running
and reachable (port 22 open). Root SSH login was rejected even with the
correct local password — root-caused to modern OpenSSH's default
`PermitRootLogin prohibit-password` (no explicit entry in
`/etc/ssh/sshd_config`, so the secure default applied, password auth
blocked for root specifically). Workaround: created a new sudo-capable
user (`useradd -m -s /bin/bash gemini`, `usermod -aG sudo gemini`) and
SSH'd in as that user instead of continuing to fight root's SSH policy.

**Register read technique note:** direct `dd`/`skip=`/`od` reads from
`/dev/mem` failed with "Bad address" — likely `CONFIG_STRICT_DEVMEM`
rejecting arbitrary-offset `read()` on `/dev/mem` (only mmap-based access
to non-reserved physical ranges is typically permitted under strict
devmem). Worked around with a small Python script using `mmap.mmap()` on
`/dev/mem` opened `O_RDONLY|O_SYNC`, page-aligning the offset
(`phys_addr & ~(4095)`) and unpacking a little-endian `uint32` at the
sub-page offset via `struct.unpack_from("<I", ...)`. This technique is
reusable for any future need to read arbitrary MMIO from userspace on a
stock/unmodified image without `busybox devmem`.

**Results — live stock Kali PHY_TIMCON0-3 (`0x1401c110/114/118/11c`) and
mipitx0 PLL CON0 (`0x10215050`), read while real content was actively
displayed:**

| Register | Our build (mainline formula, 880Mbps) | LK one-shot boot dump (capture 244) | **Stock Kali live (new, 2026-07-11)** |
|---|---|---|---|
| TIMCON0 (0x110) | 0x0a0b0907 | 0x080f0708 | **0x0a12080a** |
| TIMCON1 (0x114) | 0x0f1c091a | 0x10280c20 | **0x14320f28** |
| TIMCON2 (0x118) | 0x071c0100 | 0x0a280100 | **0x0d320100** |
| TIMCON3 (0x11c) | 0x000e0f07 | 0x00102406 | **0x00141208** |
| mipitx0 PLL CON0 | 0xf0002001 | — | **0xf0002001 — exact match** |

Analysis: the PLL/data-rate configuration is confirmed correct (mipitx0
CON0 matches exactly between our build and the live stock driver — POSDIV
and data-rate setup are not in question). All four PHY_TIMCON registers,
however, are consistently and substantially *larger* (looser/more
conservative D-PHY timing margins) in the stock live capture than either
our mainline-formula-derived values or even LK's own one-shot boot dump —
the stock driver runs with noticeably more timing headroom than mainline's
formula computes for this data rate. This is now the strongest evidence
yet for the leading hypothesis: mainline's `mtk_dsi.c` PHY_TIMCON formula
produces margins too tight for this specific panel/board at this data
rate, and the first several scanlines of every frame corrupt as a result
(matching the photographed artifact confined to the top ~5-8% of the
panel). LK's dump — itself different again from both — was likely a
transient/splash-time value, not representative of steady-state operation,
which explains why matching it exactly wasn't sufficient.

Next step: add a debug patch overriding `mtk_dsi_phy_timconfig`'s
computed TIMCON0-3 with (or close to) these live stock values, build,
flash, and capture to test directly — this is a real, empirically-sourced
value set, not a guess, so it's worth a dedicated flash/capture cycle.
Once display is fully clean and stable, the current custom Linux 6.6
`boot2` and Debian 13 rootfs baseline will need re-establishing per
CLAUDE.md (both were wiped by this scatter reflash).

**Debug patch written:** `patches/v6.6/zz-debug/0008-GEMINI-DEBUG-dsi-timcon-vendor-live-values.patch`
— hardcodes TIMCON0-3 to `0x0a12080a / 0x14320f28 / 0x0d320100 /
0x00141208` immediately after `mtk_dsi_phy_timconfig()`'s formula
computation in `mtk_dsi.c`, overriding the computed values before the
`writel()`s. Marked temporary/GEMINI-DEBUG per convention; not yet
built/flashed/tested as of this entry.

**Extended data harvest from the live stock image (2026-07-11,
`logs/2026-07-11-stock-vendor-harvest/`)** — while root SSH access was
being fought over PAM/`PermitRootLogin` defaults, a second `gemini` user
was created (`useradd -m`, added to `sudo`) as a pragmatic workaround, and
used to pull the following reference data via SSH (session logged in
`logs/2026-07-11-196-stock-kali-live-register-read.log`, though the
final data extraction happened over SSH, not serial, once Wi-Fi/SSH access
was established):

- **Kernel identity:** `Linux kali 3.18.41-kali+ #12 SMP PREEMPT Wed Apr 3
  19:04:09 AEDT 2019 aarch64` — confirms this is the exact stock 2019
  vendor build referenced elsewhere in the project (matches the
  `dguidipc`/`gemian` vendor 3.18 source tree used as our driver-source
  reference).
- **Kernel cmdline:** `console=tty0 console=ttyMT0,921600n1 root=/dev/ram
  vmalloc=496M slub_max_order=0 slub_debug=OFZPU
  androidboot.hardware=mt6797 maxcpus=5 androidboot.verifiedbootstate=green
  bootopt=64S3,32N2,64N2 log_buf_len=4M androidboot.veritymode=enforcing
  printk.disable_uart=1 ...`. Two independent confirmations of
  project-established facts: `console=ttyMT0,921600n1` matches our own
  UART0/921600 finding exactly, and `printk.disable_uart=1` confirms the
  long-standing conclusion that LK/vendor kernel dmesg is intentionally
  silenced on UART (not a wiring/capture problem). **New data point:**
  vendor stock also runs `maxcpus=5`, not all 10 cores — independent
  confirmation that the vendor kernel doesn't fully solve the SMP-bringup
  problem either (relevant context for our own B-13-linked
  `maxcpus=8` workaround; the vendor's own answer is more conservative,
  not more complete).
- **debugfs technique note:** `/sys/kernel/debug/mtkfb`,
  `/sys/kernel/debug/disp/dump`, and `/sys/kernel/debug/dispsys` are rich,
  human-readable vendor debug interfaces (not present in mainline — MTK
  vendor-only). Reading `/sys/kernel/debug/mtkfb` triggers
  `mtkfb_release()` as a side effect, which suspends and power-offs the
  display (`ddp_dsi_power_off`) — **reading this file is not side-effect
  free**, note for any future harvesting session on a similar vendor
  image. Display was successfully woken again with a physical screen tap,
  which triggered a full, cleanly-logged resume sequence (see below).
- **`mtkfb` static dump (pre-suspend), key facts:**
  `LCM Driver=[aeon_ssd2092_fhd_dsi_solomon]`, `Resolution=1080x2160,
  Interface:DSI, LCM Connected:Y`, `lcm_fps=5922` (actual measured/
  configured refresh rate is **59.22 Hz**, not a round 60 Hz — worth
  checking our own mode's computed refresh rate against this), `Current
  display driver status=video mode + CMDQ Enabled`. Framebuffer:
  `xres=1080, yres=2160, bpp=32, pages=3, linebytes=4352` (4352 = 1080*4
  rounded up to 32-byte GPU line alignment, i.e. an 8-pixel pad — matches
  the earlier-documented `1088`-pixel-stride convention seen in the
  ion/graphics-buffer trace below).
- **DSI clock (debugfs `clk` tree):** `mm_dsi0_mm clock` (engine clock) =
  **325 MHz**, enable count 1. `mm_dsi0_interface_clock` reads 0 (likely a
  derived/gated mux, not a primary source — not necessarily meaningful on
  its own).
- **Live PHY_TIMCON0-3 + mipitx0 PLL CON0**, read via a custom `mmap()`
  -based Python script (see technique note below) while real content was
  actively displaying: table already given above this entry. mipitx0 PLL
  CON0 read as `0xf0002001`, an exact match to our own build's value,
  confirming our PLL/data-rate setup is correct and isolating the
  remaining discrepancy to the D-PHY timing margins specifically.
- **Register-read technique (reusable):** `dd`+`skip=`+`od` against
  `/dev/mem` failed with "Bad address" (`CONFIG_STRICT_DEVMEM` rejecting
  arbitrary-offset `read()`). Worked around with a small Python script:
  `os.open("/dev/mem", O_RDONLY|O_SYNC)`, `mmap.mmap(fd, 4096,
  MAP_SHARED, PROT_READ, offset=phys_addr & ~4095)`, then
  `struct.unpack_from("<I", m, phys_addr & 4095)`. Confirmed to work for
  arbitrary MMIO reads from unprivileged-adjacent userspace (via `sudo`)
  on a stock/unmodified image with no `busybox devmem` present. Kept as a
  documented technique for any future need to read arbitrary registers
  from userspace without kernel changes.
- **Full DSI/LCM/touch resume trace captured** (`dmesg-full.log` in the
  harvest dir, lines ~66588-66670) by enabling
  `echo 2 > /sys/kernel/debug/dispsys` (max verbosity) and
  `echo irq_log:1 > /sys/kernel/debug/dispsys`, then physically tapping
  the screen to trigger a real resume-from-suspend cycle:
  - `lcm_poweron` → bias/power-IC I2C writes (`lp3101---cmd=0/1--i2c write
    success`, an LP3101 dual-rail DSI bias IC, TPS65132-equivalent role)
  - Panel/touch controller identifies itself via SEEPROM reads:
    `ds16_seeprom_fw_ds_read_version` returns four ASCII-decodable
    version words that spell out `AUO` / `599` / `SSD` / `2092` /
    firmware version `0x16` — confirms the panel is an **AUO-manufactured
    module using a Solomon SSD2092 controller**, resolving the earlier
    "SSD2092 = touch, not display" vs. "SSD2092 = display" confusion from
    different vendor source trees: **this is a combined in-cell
    touch+display controller**, so both attributions were partially right
    (`solomon_read_points`/TMC-config log lines immediately after are the
    same IC's touch function, not a separate chip).
  - `lcm_resume==end` → backlight PWM set: `disp_pwm_set_backlight_cmdq(id
    = 0x1, level_1024 = 827)` — a concrete, real-world backlight brightness
    reference value (827/1024 ≈ 81%) for whatever ambient/default level
    the vendor stack chooses.
  - One **DEVAPC access violation** logged immediately before this
    sequence: `[DEVAPC] Violation(R) - Process:Xorg, ... Vio
    Addr:0x14015000 ... Access Violation Slave: DISP_AAL (index=151)` —
    Xorg attempted a direct read of the DISP_AAL register range and was
    blocked by the MT6797 security controller (DEVAPC). Not something we
    caused; useful confirmation that DISP_AAL (and presumably other
    DISP_* blocks) are DEVAPC-protected against unprivileged/unexpected
    userspace access even under the vendor kernel — worth keeping in mind
    if any future debug tooling on our own kernel tries similar direct
    `/dev/mem` pokes at that range from a non-privileged path.
- **Panel/tearing-adjacent observation:** immediately after the scatter
  reflash and first stock boot, the panel showed a slow-fading "ghostly
  white hue" (image retention) that cleared on its own after the panel
  ran normal, non-static content for a while. Most likely explained by
  the prior session's full-frame white/black keepalive pattern having
  been held static on the panel for an extended period before the
  reflash. Judged not to be physical damage, but is a real, physically-
  confirmed data point that this specific panel exhibits slow (multi-
  second-to-minute) LC relaxation/retention — potentially relevant
  context for the still-unsolved fade-to-black investigation (a
  liquid-crystal characteristic, not necessarily a purely digital driver
  artifact).
- **Not obtainable this session:** persistent/pre-wrap boot-time dmesg
  (the running kernel's dmesg ring buffer had already wrapped past all
  boot-time DSI/LCM init messages by the time SSH access was
  established — none of the standard `/var/log/*` files had kernel
  facility messages either, so this specific vendor rootfs apparently
  doesn't route `kern.*` to persistent syslog by default);
  `/sys/kernel/debug/regulator/regulator_summary` (not present on this
  kernel — no regulator framework debugfs summary exposed, unlike
  mainline). Both are gaps for any *future* similar harvesting session to
  close early (e.g. redirect dmesg to a file within the first ~60s of
  boot, before ~270s of runtime chatter has wrapped the 4 MB ring buffer)
  rather than something to chase further on this now-superseded stock
  image — this rootfs will be discarded once the project's own Linux 6.6
  `boot2` + Debian 13 baseline is re-flashed.

## BUILD #105 (banner #105) — vendor-live TIMCON experiment, 2026-07-11

**Correction (same day, after re-check):** the write-up below originally
described this result as "worse than the existing top-of-frame line
corruption." That baseline claim was wrong and has been struck — boot.md
has no prior entry documenting "thin top-of-frame corruption" anywhere
before this session. The last actually-documented visual state (build
#243/#245, CLAUDE.md Phase 5 status, boot.md ~"CAPTURE 248/250 result")
was **backlight lit, image fully black** — no pixel content at all, not a
corrupted-but-visible image. See the "BUILD #106 recheck" entry below for
the follow-up once this was caught.

**Motivation:** with the known-good baseline (build #71 kernel + Debian 13
rootfs) restored and verified via SSH banner match, tested whether the
live vendor `PHY_TIMCON0-3` register values harvested from the stock Kali
image (see previous entry) would produce a visible image, given the panel
had been black-with-backlight since #243/#245.

**Patch:** `patches/v6.6/zz-debug/0008-GEMINI-DEBUG-dsi-timcon-vendor-live-values.patch`
— hardcodes `timcon0..3` in `mtk_dsi_phy_timconfig()` to the vendor-harvested
values (`0x0a12080a` / `0x14320f28` / `0x0d320100` / `0x00141208`),
overriding the mainline formula output. Built with `ALLOW_DEBUG=1`
(provenance `logs/2026-07-11-279-dsi-timcon-vendor-live-values/`, sha256
`0c0371b950d8b34f9f1c62a98ca60d749fc3ba6473b53ee0f39cc174f372304b`, banner
`#105 SMP PREEMPT Sat Jul 11 06:26:58 UTC 2026`).

**Result:** flashed to `boot2`, capture
`logs/2026-07-11-280-dsi-timcon-vendor-live-values-boot.log`. Kernel boot
was clean end-to-end — reached `graphical.target` in ~20s, no
`flip_done`/vblank timeouts, DSI component bound
(`1401c000.dsi (ops mtk_dsi_component_ops)`), panel post-init DCS reads all
succeeded (`0x1c`/`0x09`/`0x70`/`0x00`/`0x80`, unchanged from prior good
builds), panel registered
(`panel-solomon-ssd2092 1401c000.dsi.0: Solomon SSD2092 FHD DSI panel
registered`). No kernel-level errors of any kind.

**Visual result:** the physical panel showed thick, regularly-spaced
horizontal bands (light-blue/black, ~12 bands across the top ~60% of the
panel) — real pixel content, not black. Photo:
`logs/2026-07-11-279-dsi-timcon-vendor-live-values/panel-thick-bars-result.jpg`.
Screen then faded to black, consistent with the separate known
fade-to-black bug (unrelated, workaround-only).

**Action taken (before the baseline check below):** patch 0008 disabled
(`0008-...-values.patch.disabled`) and reverted out of the build on the
assumption the bars were a regression it had introduced. Rebuilt as
`logs/2026-07-11-281-revert-timcon-back-to-baseline/`, sha256
`f8888999d553cb3009a0c8c0aefed431655cccd82c7d262c461913f498772a5e`, banner
`#106 SMP PREEMPT Sat Jul 11 06:32:18 UTC 2026`.

## BUILD #106 recheck — same thick bars WITHOUT patch 0008; root cause is NOT the TIMCON override

Flashed build #106 (banner confirmed via
`logs/2026-07-11-282-revert-timcon-back-to-baseline-boot.log`: `Linux
version 6.6.0-dirty ... #106 SMP PREEMPT Sat Jul 11 06:32:18 UTC 2026`,
sha256-verified identical to what was built) — **pure mainline-formula
TIMCON, patch 0008 not applied** (confirmed by reading
`mtk_dsi_phy_timconfig()` directly from the VM's post-build tree: formula
code only, no override). User confirmed on physical hardware: **"same
horizontal lines as the previous build"** — identical thick
red/black/white banding to build #105 (vendor TIMCON).

**Conclusion:** patch 0008 is exonerated — visually indistinguishable
result with or without it, so the banding is not a D-PHY bit-timing
(`PHY_TIMCON0-3`) issue at all. Root cause lies elsewhere in the
pipeline (OVL/DDP config, panel init sequence, or framebuffer/scanout
format). Combined with the
correction above (no genuine "black to thin corruption to thick
corruption" regression chain exists; the last confirmed-documented prior
state was plain black), the most defensible read is that **this may be
the first time real pixel content has appeared on this panel under our
own kernel**, not a regression from a better-documented previous state.
Whether thick banding is new behavior since #243/#245 (something changed:
TPS65132 went `m` to `y`, zz-debug 0002-0006 remained active,
`gemini-nousb-debug.config` newly added — config diff checked, only the
TPS65132 module-to-built-in change found) or was already the state at
#243/#245 and simply never photographed/described in this file, is
unresolved — no photographic or detailed textual record of #243/#245's
actual screen exists to compare against.

**Next step for B-13/top-of-frame investigation:** the D-PHY timing lead
(`PHY_TIMCON0-3`) is closed off — 0008 vs. mainline formula is a
user-confirmed visual non-difference, identical banding both ways. Do not
re-attempt further TIMCON register tuning. Redirect investigation to
non-D-PHY causes of the banding: (1) OVL/DDP layer config (mutex/routing,
possible off-by-something in blend/output config given the band pattern
is coarse and periodic — consistent with a scanline-count or line-stride
mismatch); (2) panel init command sequence — check if a full
column/page-address-set or memory-write command is missing/wrong,
producing a repeating short pattern instead of a full frame; (3)
framebuffer/scanout format — the earlier-documented 1088-px GPU-aligned
stride vs. panel's native 1080 could be a factor if not matched exactly
on this path. A deliberate baseline photo of the current build (#106) is
still worth capturing for future comparison, but the immediate priority
is a pipeline-config review rather than more TIMCON experiments.

## BUILD #107 — exact LK DSI word counts (HSA/HBP/HFP_WC); same banding, lead #2 also closed off

Second targeted experiment against the same artifact. Mainline's
`mtk_dsi_config_vdo_timing()` derives `DSI_HSA_WC`/`DSI_HBP_WC`/`DSI_HFP_WC`
from a pixel-clock formula further adjusted by a D-PHY cycle-budget
correction (`drivers/gpu/drm/mediatek/mtk_dsi.c` lines ~475-519) — the
panel patch's own comment admits this "lands within one byte" of LK's
actually-proven-working register dump (capture 244), not an exact match.
Debug patch `zz-debug/0009-GEMINI-DEBUG-dsi-exact-lk-word-counts.patch`
overrides the three registers with LK's exact values (`HSA_WC=0x1c`,
`HBP_WC=0x94`, `HFP_WC=0x74`) right after the formula/correction, bypassing
mainline's derivation entirely for this test.

Build #107 (`logs/2026-07-11-283-dsi-exact-lk-word-counts/`,
`ALLOW_DEBUG=1`). Flashed to `boot2`, captured
`logs/2026-07-11-284-dsi-exact-lk-word-counts-boot.log` with `--interactive`.
Kernel-side DDP register dump (also captured via the existing debug
instrumentation) confirms the override took effect exactly as intended:
`DSI+0050 : 0x0000001c 0x00000094 0x00000074` — i.e. `HSA_WC/HBP_WC/HFP_WC`
read back as `0x1c/0x94/0x74`, matching LK bit-for-bit. Vertical registers
also confirmed matching LK's dump (`VSA_NL=3, VBP_NL=0xf, VFP_NL=0xa,
VACT_NL=0x870`=2160). `DSI_PSCTRL` read back `0x30ca8`: `PS_WC` field =
`0xca8` = 3240 = 1080×3 (RGB888, native 1080 width, not the 1088-aligned
GPU stride) and `PS_SEL` = `PACKED_PS_24BIT_RGB888` — so the DSI-level
packet width is exactly right for a native, un-padded 1080px line; the
1088px-stride hypothesis is *not* what's happening at the DSI-packetization
layer specifically (a stride mismatch could still exist further upstream,
at the OVL/RDMA→GEM-buffer level — not ruled out by this test).

Boot itself: clean, `graphical.target` reached in ~20s, ssh/getty started,
no flip_done/vblank timeouts, no DSI/panel errors on serial.

**Visual result (user, on physical hardware):** "same orange white black
horizontal bars then fade to black" — visually indistinguishable from
build #105 (vendor TIMCON) and #106 (mainline formula, no override).

**Conclusion:** lead #2 (DSI horizontal word-count derivation) is also
exonerated. Two independent D-PHY/DSI-line-timing hypotheses (TIMCON
bit-timing margins, and now HSA/HBP/HFP word counts) have each been
overridden with LK's own proven-correct hardware values and produced a
byte-for-byte-verified-correct DSI configuration with **zero visible
change** to the artifact. This is strong evidence the banding is not a
DSI-protocol/timing issue at all — the DSI engine is receiving and
transmitting a well-formed, correctly-timed video stream; whatever's wrong
is upstream of the DSI packetizer, most likely in what the OVL/RDMA layer
is actually reading out of memory (layer format/pitch/address, GEM buffer
content, or CRTC blending) and handing to DSI to transmit.

**Next step:** stop testing DSI-register-level values. Move investigation
to the OVL/RDMA layer feeding DSI. The existing DDP debug dump
(`zz-debug/0003`/`0006`) currently only captures a handful of OVL control/
status registers (`+0x000/0x008/0x00c/0x024/0x02c/0x240/0x244`) — extend it
to also dump the per-layer registers (`OVL_CON`, `OVL_ADDR`, `OVL_PITCH`/
`HDR_PITCH` at the `0x30-0x50`-ish per-layer offsets in
`drivers/gpu/drm/mediatek/mtk_disp_ovl.c`) so the actual format/pitch/
address the kernel programs into the live OVL layer can be read back and
compared against what fbcon/DRM *thinks* it configured (color format,
stride, GEM buffer size) — a mismatch there (e.g. pitch not matching the
allocated stride, or a color-format bit landing on the wrong panel-expected
format) would directly produce a periodic, coarse banding pattern like the
one seen, and unlike DSI timing this has not yet been directly instrumented
or tested.

## RUNS #110–#123 — OVL exoneration, command-mode detour, booster-off discovery (2026-07-11)

Condensed sequence (each run has its provenance dir/log under `logs/2026-07-11-*`):

- **Run 110/111 (ovl-fb-readback)** + **113/114 (plane/crtc commit trace)**:
  extended DDP dump with per-layer OVL registers and CPU readback of the GEM
  framebuffer. Result: OVL layer format/pitch/address all correct and the
  framebuffer content is what fbcon drew — the memory-side pipeline was
  exonerated, leaving the panel itself as the suspect for the banding/fade.
- **Run 115–117 (panel-command-mode)**: noticing LK's golden dump has
  `DSI_MODE_CON=0`, the panel was retried in command mode (zz-debug 0015).
  Panel stayed dark; flip_done/vblank timeouts returned (mainline mtk_dsi has
  no per-frame CMDQ push); boot slowed to ~90 s. In hindsight this was a
  wrong turn — LK uses command mode only for its one-shot splash push; the
  vendor *kernel* driver runs the panel in video mode (see run 132).
- **Run 118/119 (all-pixels-on)** + **120/121 (live DCS debugfs)**: DCS
  0x23 ACKed but glass never changed; live reads mostly failed (-62 timeouts,
  0-byte returns, and DSI ACK+Error [type 0x02] responses). Key finding:
  **RDDPM read 0x1c — booster (bit7) off** vs LK's working 0x9c.
- **Run 122/123 (inherit-lk-state)**: skipping reset+init to inherit LK's
  live panel state — no improvement, disabled again.
- **Run 124/125 (bias55 + HS booster recheck)**: TPS65132 bias confirmed
  programmed; booster still off. Suspicion moved to the init table itself.

## BUILD #126 (banner #117, run 126/127) — packet-type root cause: mfr commands need GENERIC packets (2026-07-11)

Vendor `DSI_set_cmdq_V2` sends commands ≥0xB0 as **generic** long/short
packets and only <0xB0 as DCS. Our panel driver sent everything as DCS, so
the entire manufacturer init table (all the 0xB0–0xE1 writes) was
packet-type-corrupted from day one — the real root cause behind the banding
era's "everything host-side verified correct, glass wrong" deadlock. Fix:
`zz-debug/0020` dispatches ≥0xB0 via `mipi_dsi_generic_write`.

Result (run 127 log): writes go out clean, but panel still dark, RDDPM
still 0x1c — necessary but not sufficient. Also of note: the first boot of
this image produced **zero kernel serial output** and a hardware WDT reset
at ~14.3 s (`aee_wdt_dump` on cpu2, PC in kernel text) falling back into
Android; not reproduced on any subsequent boot of the identical image, no
mechanism found. The "flashing colors" seen on that crashed boot were a
crash artifact, not scanout.

## BUILD #129-run (banner #118) — LK D-PHY TIMCON fixes LP communication (2026-07-12)

Register diff vs LK's golden dump showed every LP-relevant D-PHY parameter
(LPX, TA_GO/SURE/GET, CLK_ZERO/TRAIL, HS_EXIT) ~40% shorter than LK's
(`0x0a0b0907/0x0f1c091a/...` vs `0x0a12080a/0x14320f28/0x0d320100/0x00141208`),
matching the panel's ACK+Error (protocol error) responses. Re-enabled
`zz-debug/0008` (LK TIMCON values, previously exonerated *for banding* but
never tried with command mode + generic writes).

Result (`logs/2026-07-12-130-*-boot.log`): **LP reads work for the first
time** — post-init DCS reads return coherent values (0x0a=0x1c, 0x0c=0x70
= 24bpp, RDDSDR 0x0f=0x80 self-diagnostic OK). Booster still off (RDDPM
0x1c after clean sleep-out + display-on).

## LIVE SESSION (run 131) — bias rails verified; vendor kernel says VIDEO mode (2026-07-12)

First scripted (non-interactive) serial session — new tooling
`scripts/serial-session.py` + `/serial-login` skill; log
`logs/2026-07-12-131-panel-live-dcs-session.log`. Findings:

- TPS65132 @ i2c 1-003e: reg 0x00=0x0f, 0x01=0x0f (AVDD=AVEE=5.5 V),
  0x03=0x33; ENP/ENN GPIOs high → panel power rails genuinely up.
- Repeat sleep-out/display-on ACK cleanly; booster still refuses (0x1c).
- **Decisive**: vendor kernel LCM driver
  (`gemini-android-kernel-3.18-android8/.../aeon_ssd2092_fhd_dsi_solomon.c`)
  has `LCM_DSI_CMD_MODE=0` → production Android drove this panel in
  **SYNC_PULSE video mode** (4-lane, RGB888, PLL_CLOCK=502). Its init table
  matches ours byte-for-byte. The command-mode pivot (run 115) was the
  wrong fork; LK's command-mode splash is a special case.

## BUILD #132 (banner #119, run 132/133) — ⭐ FIRST IMAGE ON THE PANEL (2026-07-12)

Combination never built before: **video mode restored** (0015 and 0009
disabled) + generic-write init (0020) + LK TIMCON (0008), white-fill test
pattern (0011) still in.

Result (`logs/2026-07-12-133-*-boot.log` + user observation): **panel lit
solid bright white** — the 0011 test fill, scanned out end-to-end. Clean
boot, **zero flip_done/vblank timeouts**, `graphical.target` in 21 s.
Banding gone (it was the corrupted init table all along). B-13/Phase 5
display pipeline is now functionally proven: OVL→…→DSI→D-PHY→panel.

## BUILD #134 (banner #120) — fbcon console on glass (2026-07-12)

0011 (white fill) and 0016 (all-pixels-on) disabled; otherwise identical to
#132. Expect real fbcon text + login prompt on the panel.
Provenance: `logs/2026-07-12-134-panel-fbcon-console/`. Result: pending flash.

## BUILD #136 (banner #121, run 136/137) — RGB-thirds pattern: folding confirms row-length mismatch (2026-07-12)

White fill displays perfectly but structured content banded → the fault is
in buffer/line interpretation, not the link. RGB-thirds + left-edge white
stripe pattern (zz-debug 0021) showed the white stripe folded into
periodic thin lines (photo IMG_2670): each display line consumes fewer
pixels than a buffer row → line-length/timing mismatch, then loss of sync
(fade to black).

## BUILD #138 (banner #122, run 138/139) — ⭐⭐ VENDOR KERNEL VIDEO TIMINGS: FIRST CORRECT IMAGE, THEN FIRST TEXT CONSOLE (2026-07-12)

Replaced the LK-derived mode timings (LK is command-mode; its video porch
registers are meaningless leftovers) with the vendor kernel LCM driver's
values: HFP=26 HSA=4 HBP=20, VFP=76 VSA=1 VBP=43, pixclk 167333 kHz
(= vendor PLL_CLOCK 502 → 1004 Mbps/lane). Result on glass: clean RGB
thirds flash, then **a readable fbcon login prompt — first text on the
panel under mainline Linux** (photos IMG_2672/2673). Stable, no fade.

## BUILDS #140–#143 (banners #123–#125) — fbcon rotation + readable font (2026-07-12)

`fbcon=rotate:` needs CONFIG_FRAMEBUFFER_CONSOLE_ROTATION (missed in #140);
rotate:1 (CW) was the wrong direction for the clamshell; final: rotate:3
(90° CCW) + CONFIG_FONT_TER16x32 + fbcon=font:TER16x32
(gemini-display.config / gemini-cmdline.config). User-confirmed: landscape
login prompt in a readable font. **Phase 5 display enablement: DONE.**

## BUILD #145 (banner #126, run 145) — production display build (2026-07-12)

Productization: generic-write dispatch + vendor video timings folded into
`panel/0005`; LK D-PHY TIMCON promoted to `drm/0015-drm-mediatek-dsi-
mt6797-vendor-dphy-timing.patch`; ALL zz-debug patches disabled (verified
"debug instrumentation absent"); USB gadget config restored
(gemini-usb.config), nousb-debug fragment deleted; `clk_ignore_unused`
dropped from the cmdline (TEMPORARY flag from the 2026-07-10 scanout-crash
diagnosis — this build revalidates without it). Result: pending flash.
Validation checklist: fbcon on glass (rotated, big font), no
flip_done/vblank timeouts, g_ether + SSH at 10.15.19.82, boot survives
late clk cleanup (the old scanout-WDT suspect), serial console goes quiet
at ~0.45s when the left-port mux switches to USB (expected, B-15).

---

# PHASE 6 — KEYBOARD

## LIVE PROBE (no build) — AW9523B confirmed on hardware over SSH (2026-07-12)

Phase 6 gate 1, done entirely on the running production build (#145 kernel,
no kernel changes) via SSH + i2c-dev:

- i2c5 hardware (0x1101c000) is registered as Linux bus **i2c-3** (buses
  enumerate in DTS order, not by vendor numbering: 0=0x11007000,
  1=0x11008000, 2=0x11010000, 3=0x1101c000).
- Initial `i2cdetect -y 3` scan: completely empty. Cause: **LK leaves SHDN
  (GPIO58, active-low reset) driven low** — chip held in reset.
- GPIO58 register math (pinctrl-mt6797: 32 pins/reg, stride 0x10):
  DIR 0x10005010 bit 26 = 1 (output), DOUT 0x10005110 bit 26 = 0 (low),
  MODE 0x10005370 bits 8–11 = 0 (GPIO). Set DOUT bit 26 via busybox
  devmem (`busybox-static` deb pushed over scp — the rootfs has no
  libgpiod/sysfs-gpio/devmem; plain `dd` on /dev/mem gets EFAULT for MMIO).
- After SHDN high: chip ACKs at **0x5b**, ID register 0x10 reads **0x23**
  (expected AW9523B ID; matches the driver patch's AW9523B_ID_VALUE).
  Port registers at power-on defaults (P0/P1 input 0xff, config 0x00,
  LED-mode 0xff = GPIO mode).

Conclusions: i2c5 pinmux (GPIO240/241) is correct as-is; address 0x5b
confirmed; the driver's `reset-gpios` deassert at probe is mandatory
(LK will always hand over with the chip in reset). Both driver_ports.md
"Open Questions" for AW9523B are closed.

## BUILD #147 — keyboard enablement, polled matrix (2026-07-12)

Changes vs #145:
- `patches/v6.6/input/0001-Input-matrix_keypad-add-polling-mode.patch`
  (NEW): optional `poll-interval` DT property → self-rescheduling
  delayed-work scan loop; skips all row-IRQ request/enable/disable/wakeup
  paths. Needed because pinctrl-mt6797 has no EINT (B-11) so the AW9523B
  INT line (GPIO87/EINT10) cannot deliver, and v6.6 matrix_keypad is
  IRQ-only (no upstream polling mode exists even in current mainline —
  checked the full matrix_keypad.c git log; the prior blockers.md B-11
  claim that it "can poll" was wrong).
- `patches/v6.6/dts/0001` regenerated (applied-edit-rediff, no hand-hunks):
  aw9523b node → `status = "okay"`, interrupt properties removed
  (annotated for B-11 restore); keyboard node gains `poll-interval = <20>`.
- `configs/gemini-keyboard.config` (NEW): GPIO_AW9523B=y,
  INPUT_KEYBOARD=y, KEYBOARD_MATRIX=y (built-in — must work at the fbcon
  login prompt).
- Full patch series `git apply` + dtc compile of the board DTS verified
  clean on the Mac before the VM build (poll-interval and enabled aw9523b
  confirmed present in the output dtb).

## BUILDS #147–#153 diagnostics — keyboard silent-fail + two red herrings (2026-07-12)

Run log: #147 flashed (capture `logs/2026-07-12-148-...`), USB cable in →
panel stuck at penguins, no gadget on the Mac, no SSH. FTDI swap capture
ends at mtu3 `u2p_dis_msk` (t=0.448) — that is the **B-15 console mux
switch**, not the hang. Diagnostic rebuilds #149/#151 turned out to be
**config-identical to #147**: `build-pack`'s rsync does not `--delete`, so
renaming `gemini-usb.config` → `.disabled` on the Mac left the old file
merging in the VM, and `CONFIG_USB_MTU3=y` comes from the arm64 defconfig
anyway (the `#151` fragment landed but was overridden by the stale
`gemini-usb.config` sorting after it). Lesson: **always verify the
provenance `config` after changing fragments; clean deleted/renamed
fragments out of the VM by hand.**

Findings from the identical-kernel boots:
- FTDI attached: boots to login on panel (#149 observation) → the keyboard
  code does NOT hang boot; the #147 "hang at penguins" correlates with the
  USB cable/Mac attached at boot. Cause unknown, parked (see below).
- Keyboard dead either way.

Build #153 (real `CONFIG_USB_MTU3 is not set`, capture
`logs/2026-07-12-154-...`): serial finally survives past 0.448 and shows
**`aw9523b 3-005b: AW9523B ready: 16 GPIOs, irq=0` at t=0.459 — the
expander probes cleanly on hardware.** But no `input:` registration and no
matrix-keypad output at all (silently deferred?), and the boot **dies at
`clk: Disabling unused clocks` (~t=0.99) → watchdog reset into Android**:
with mtu3 gone nothing holds the SSUSB-adjacent clocks and the unused-clk
sweep gates something fatal — new constraint: **no-USB diagnostic builds
need `clk_ignore_unused`** (added to gemini-nousb-debug.config as a
CMDLINE override; production keeps mtu3 and is unaffected).

Open items: (1) why gpio-matrix-keypad never probes — next build #155
(no-USB + clk_ignore_unused) gives a serial shell to read
`/sys/kernel/debug/devices_deferred`; (2) USB-cable-at-boot hang on the
keyboard build — revisit after the keyboard works.

## BUILDS #155–#164 — keyboard root-caused and WORKING (2026-07-12) ⭐

Chain of evidence after #153's crash:
- **#155** (nousb + clk_ignore_unused): stable serial shell all boot.
  Live session found `/proc/device-tree/keyboard/status` = **"disabled"**
  — the gpio-matrix-keypad node had a SECOND status property after the
  53-line keymap in dts/0001, missed when the aw9523b node was enabled.
  No platform device was ever created; every "keyboard" build so far had
  shipped a disabled keyboard. Fixed in dts/0001 (status = "okay").
- **#157** (fix + production USB): with USB host attached at boot → stuck
  at penguins again, gadget never enumerates (same as #147 — and note in
  #147–#155 the keypad was inert, so the USB-attached hang correlates with
  the aw9523b probe alone, NOT key scanning). With FTDI: boots.
- **#159** (+ console=tty0, kernel log on panel — now PERMANENT per user):
  reached prompt; keypad registered but keys dead.
- **#161** (fix + nousb serial diag): serial session shows the smoking gun:
  `matrix-keypad keyboard: polling mode, interval 20 ms`, input0 bound to
  kbd — but /sys/kernel/debug/gpio shows idle cols OUT-HI and the active
  scan col HIGH against pulled-up rows (P0 in 0xff, P1 out latch 0xff).
  **matrix_keypad is a legacy-GPIO driver: it ignores GPIO_ACTIVE_LOW
  flags in row-/col-gpios and only honors the `gpio-activelow` property**,
  which the node lacked — the scan polarity was inverted, no keypress
  could ever change a row. (Device hard-hung at the end of this session
  while forced i2cget reads raced the 20 ms poll on the same bus — avoid
  concurrent i2c-dev access to the live keypad bus.)
- **#164** (gpio-activelow added, dts/0001): **KEYBOARD WORKS — user
  confirmed typing at the panel login prompt** (capture
  logs/2026-07-12-165-keyboard-activelow-boot.log). Keymap spot-check
  pending.

Keyboard root-cause chain (three stacked defects, cf. Phase 5's three):
1. LK hands over with AW9523B in reset (SHDN/GPIO58 low) → driver
   reset-gpios deassert is mandatory (found by live i2c probe, no build).
2. Keyboard DT node carried a hidden second status="disabled" → no
   platform device (found via /proc/device-tree on a serial shell).
3. Matrix polarity inverted: legacy matrix_keypad needs `gpio-activelow`,
   ignores gpiod flags (found via /sys/kernel/debug/gpio snapshot).

Still open: USB-host-attached-at-boot hang on aw9523b-enabled builds
(#147/#157 hung; #159 reached prompt — cable state that boot unconfirmed).
Production build #166 (USB restored + all fixes + console=tty0) is the
discriminating test: clean USB boot + SSH = Stage A complete.

## BUILD #166 (production attempt) + #168 BASELINE (banner #135) — keyboard production; USB gadget regression → serial-console operating mode (2026-07-12)

**#166** (all keyboard fixes + USB restored + console=tty0, sha256
ea6ddf0f…ee3c): boots WITH the USB host attached (the #147/#157 full hang
did not reproduce with all fixes in), **keyboard works at the panel
login** — but the gadget never enumerates on the Mac (no interface with
host MAC 42:00:15:19:82:00, 10.15.19.82 unreachable) → SSH dead. Serial
also dead on mtu3 builds (B-15 mux, switches at t=0.45s and never
returns even after cable swap — confirmed empirically this session). The
aw9523b↔USB interaction is now blocker **B-18**; device-side dmesg could
not be captured because the base keymap cannot type `|`/`-`/`>` (no Fn
layer yet).

**User decision:** disable USB, operate over serial + on-device keyboard.
Config state committed: `gemini-usb.config` → `.disabled`, new
`gemini-serial-console.config` (USB_MTU3 off + clk_ignore_unused +
console=tty0 CMDLINE). **#168** rebuilt from this committed state,
config-identical to validated #164 (verified by diff), sha256
51b9a3fb…1844, flashed as the new baseline: display + keyboard + serial
console/shell all boot + kernel log on panel. Confirmed live over a
serial session (banner #135, `logs/2026-07-12-170-locale-check-session.log`).

Console layout/locale check (user request): no kbd/locales packages on
the minbase rootfs → kernel built-in **US keymap** is in effect and
locale is C.UTF-8 (English) — both already US/English; en_US.UTF-8
generation deferred until network returns (B-18). The earlier "|
rendered as \"" report was the missing Fn layer, not a layout issue.

**PHASE 6 STAGE A COMPLETE** — the Gemini is usable standalone (screen +
keyboard) for the first time under mainline Linux. Follow-ups tracked:
Fn layer (all punctuation beyond , . ' lives there), keymap spot-check,
B-18 (USB gadget), B-11/EINT (Stage B, IRQ-driven keypad).

## BUILD #171 (banner #138) + live console keymap — Fn LAYER WORKING (2026-07-12) ⭐

Kernel side: DTS Fn key (matrix 4,3) remapped KEY_FN → KEY_RIGHTALT
(AltGr) — the console's level-3 modifier; matrix_keypad can't do layers,
the console keymap can. Flashed and validated (capture
logs/2026-07-12-172, session -173).

Keymap side (rootfs, no reflash): extracted Gemian's authoritative XKB
map from the 2019 Kali image with debugfs (planet/linux.img,
/usr/share/X11/xkb/symbols/planet_vndr/gemini — "us" variant; Gemian's
Fn = ISO_Level3_Shift on <LWIN>, same idea). Encoded its level-3 layer +
US-silkscreen shift fixes into a busybox bkeymap (base = `busybox
dumpkmap` of the running kernel map; 23 entries patched: Fn+1..0 =
~`£<>[]{}; Fn+i/o/p = +-=; Fn+j/k/l = _;"; Fn+m = '; Fn+\ = :;
shift+comma = /; shift+period = ?; apostrophe-position key corrected to
\ | per US silkscreen). Transferred over serial via base64/echo (md5
verified), loaded with `busybox loadkmap` — **user confirmed all Fn keys
work.** No pipe/redirect-free workarounds needed anymore.

Persistence: `/etc/gemini.bkmap` + `gemini-keymap.service` (oneshot,
Before=getty.target, StandardInput=file:) enabled on the device;
committed to the repo as `rootfs-files/` and folded into
`scripts/mkrootfs.sh` (+ busybox-static and iputils-ping added to
PKGS_TOOLS). DTS also fixed for the next build: matrix (5,0)
KEY_APOSTROPHE → KEY_BACKSLASH (keymap covers both keycodes 40 and 43,
so it works on the current kernel too).

Remaining keymap niceties (not blockers): Esc key (not in the 53-key
matrix?), media/brightness Fn keys (X11-only in Gemian), arrow
PgUp/Home combos.

---

## BUILD #175 (banner #140) — B-18 RESOLVED: keyboard + display + USB gadget SSH together for the first time

**2026-07-13.** Following the WiFi-plan Stage 0 desk research (vendor
`aw9523_key.c` power-up sequencing + vendor-DTB pin/bus topology — see
research.md/blockers.md B-18), found that `patches/v6.6/dts/0001-...patch`
defined an `aw9523b_pins` pinctrl state (SHDN/GPIO58 output-high +
GPIO87/INT `bias-pull-up`) but never referenced it from any `pinctrl-0`
property — dead DTS, leaving GPIO87/INT floating next to USB/mtu3 IRQ
activity. Added `pinctrl-names = "default"; pinctrl-0 = <&aw9523b_pins>;`
to the `aw9523b: gpio@5b` node. Regenerated the three DTS patches that
touch `mt6797-gemini-pda.dts` (0001, 0009, 0011) via apply-edit-rediff
(applied the patch set, made the edit against the real file, re-diffed)
so their line-number context stays internally consistent — verified the
full `patches/v6.6/` set still applies cleanly end-to-end afterward.

Also restored `configs/gemini-usb.config` (from `.disabled`) and retired
`configs/gemini-serial-console.config` to `.disabled`, since the
USB-off/`clk_ignore_unused` fallback (B-18 workaround) is no longer
needed. Cleaned two stale config fragments off the VM (rsync doesn't
`--delete`; same lesson as builds #149/#151 — always verify the
provenance `config` after fragment renames).

Build #175 (banner #140, `logs/2026-07-13-175-b18-aw9523b-pinctrl-fix/`,
sha256 `d34d58474bca24a851eda4c93ac660aada268c8cb3de1f231d44b00d7c7883c8`),
flashed to `boot2`. **Result: booted cleanly to prompt, keyboard works,
USB gadget enumerated** (`en12`, fixed MAC `42:00:15:19:82:00`, static IP
`10.15.19.1` alias reapplied on the Mac), `ping 10.15.19.82` and
`ssh root@10.15.19.82` both succeeded (banner confirmed over SSH:
`Linux gemini 6.6.0-dirty #140 SMP PREEMPT Mon Jul 13 00:45:17 UTC 2026
aarch64`). All three B-18 symptoms cleared in a single fix — no need for
the 5-variant diagnostic matrix. **New baseline: display + keyboard + USB
gadget SSH, all working together, first time since Phase 6 began.**

## BUILD #142 (logs/2026-07-13-220-stage1-usb-host-xhci) — WiFi plan Stage 1.1: USB host mode on ssusb (untested on hardware)

**2026-07-13.** First cut at Stage 1 of the WiFi plan (plan.md Phase 8):
extended `patches/v6.6/dts/0009-...-ssusb-gadget.patch` (apply-edit-rediff
against the 0001/0009/0011 patch set, same technique as the B-18 fix) to
add host-mode support on the existing SSUSB controller, using facts
confirmed from the vendor DTB (`docs/vendor-dtb/gemini_kali_boot.dts`)
during Stage 1 desk research:

- The vendor's combined SSUSB block (`0x11270000/0x11280000/0x11290000`)
  is **one dual-role mtu3 controller** with two IRQs: SPI 127 "musb-hdrc"
  (device, already used by the existing gadget-mode node) and **SPI 126
  "xhci"** (host) — not two separate ports. Added an `xhci` child node
  (`compatible = "mediatek,mtk-xhci"`, reusing the parent's mac/ippc reg
  block, `interrupts = <GIC_SPI 126 IRQ_TYPE_LEVEL_LOW>`) per the mainline
  `mediatek,mtu3.yaml` binding's dual-role-child pattern.
- VBUS has no discrete regulator node in the vendor tree — it's driven
  directly via GPIO94 through the `usb1_drvvbus_low`/`usb1_drvvbus_high`
  pinctrl states (`pins = <0x5e00>` decodes as `MTK_PIN(0x5e, 0)` =
  GPIO94, func 0/GPIO). Modelled as a new `regulator-fixed` node
  (`usb1_vbus`), same pattern as the existing `vemc_fixed`/`vproc_fixed`
  nodes, referenced as `vbus-supply` on both the mtu3 parent and the xhci
  child.
- `dr_mode` changed from `"peripheral"` to hard `"host"` (not `"otg"`) for
  this first hardware cycle — avoids needing `usb-role-switch`/connector
  machinery before host mode is even confirmed to enumerate anything.
  **This means g_ether/gadget SSH is NOT available in this build** — mtu3's
  host/gadget Kconfig options are a mutually exclusive choice
  (`drivers/usb/mtu3/Kconfig`). Dual-role is deferred to after Gate G1a.
- Confirmed via kernel source inspection (not just hardware.md's existing
  flag) that `xhci-mtk.c`'s `of_device_id` table already includes a
  generic `"mediatek,mtk-xhci"` fallback match (`drivers/usb/host/xhci-mtk.c`)
  alongside the mt8173/mt8195-specific compatibles — so no driver source
  change is needed for xhci-mtk to bind mt6797, despite no SoC-specific
  entry existing for it.

`configs/gemini-usb.config` rewritten for host mode: `CONFIG_USB=y`,
`CONFIG_USB_MTU3=y`, `CONFIG_USB_MTU3_HOST=y` (was `_GADGET`),
`CONFIG_USB_XHCI_HCD=y`, `CONFIG_USB_XHCI_MTK=y`, `CONFIG_USB_STORAGE=y`
(cheap USB-stick smoke test ahead of an MT7921U WiFi dongle).

**Build verification (VM, no hardware flash yet):** full patch set
(`patches/v6.6/`, all subsystems) applied cleanly end-to-end; `.config`
resolved to the intended symbols (`USB_MTU3_HOST=y`, `USB_XHCI_MTK=y`,
`USB_XHCI_HCD=y`, `USB_STORAGE=y`); `make` completed with **zero
warnings or errors** touching USB/xhci/mtu3/gemini; `fdtdump` on the
compiled DTB confirms the `usb@11271000` node's `vbus-supply` phandle
resolves and the child `usb@11271000` (xhci) node carries `interrupts =
<0x00 0x7e 0x08>` (SPI 126) distinct from the parent's `<0x00 0x7f 0x08>`
(SPI 127) as intended. Packed as build #142
(`logs/2026-07-13-220-stage1-usb-host-xhci/`, sha256
`861402f388d5342e1d2ad189b2fd84132e5f38562d45bc69013f58cafb716808`).

**Not yet flashed/tested on hardware — Gate G1a still open.** Because
this build has no gadget mode, verification on hardware must use the
panel console (`console=tty0`) or on-eMMC dmesg, not SSH. Expected next
step: flash `boot2`, plug a USB stick into the right-hand port, and read
the panel for xhci-mtk probe/enumeration output.

## BUILD #142 hardware result: xhci child device registration failed (sysfs duplicate filename) — root cause and fix, 2026-07-13

**Flashed and booted on hardware.** Serial capture
(`logs/2026-07-13-222-stage1-live-check.log`) confirms the banner
(`#142 SMP PREEMPT Mon Jul 13 01:13:31 UTC 2026`) and shows `mtu3` probing
correctly in host mode (`dr_mode: 1, drd: auto`) before the expected B-15
mux handoff silences serial. On-device `dmesg` (photographed off the
panel, physical keyboard — no SSH in this build) showed the real problem:

```
[    0.444458] mtu3 11271000.usb: supply vusb33 not found, using dummy regulator
[    0.445850] mtu3 11271000.usb: dr_mode: 1, drd: auto
[    0.446503] mtu3 11271000.usb: u2p_dis_msk: 0, u3p_dis_msk: 0
[    0.447527] mtu3 11271000.usb: usb3-drd: 0
[    0.448325] sysfs: cannot create duplicate filename '/bus/platform/devices/11271000.usb'
[    0.457751]  ssusb_host_init+0x150/0x18c
[    0.458268]  mtu3_probe+0x6b8/0x814
[    0.463928]  mtu3_driver_init+0x1c/0x28
[    0.465537] mtu3 11271000.usb: xHCI platform device register success...
```

No `xhci-mtk`/`xhci-hcd` probe line ever appeared after this — the xhci
platform device was never usable despite mtu3 logging "register success".

**Root cause:** the `xhci` child node in `patches/v6.6/dts/0009-...`
reused the parent `ssusb` node's exact register block/unit address
(`0x11271000`, mac+ippc). `ssusb_host_init()` calls
`platform_device_register()` for the xhci child using a name derived from
that address — identical to the parent's own device name
(`11271000.usb`) — so `sysfs_create_dir_ns()` collided and the xhci
platform device never got a working sysfs entry, meaning the driver core
could never match/probe it against `xhci-mtk.c`.

**Fix:** matched the mainline `mediatek,mtu3.yaml` binding's own dual-role
example exactly — the xhci child must use a *different*, MAC-only
register window than the parent. Changed the child node from
`usb@11271000` (mac+ippc, same as parent) to `usb@11270000` (`reg = <0
0x11270000 0 0x1000>`, `reg-names = "mac"` only). Regenerated
`patches/v6.6/dts/0009-...` via the same apply/edit/rediff technique used
for the B-18 fix, verified byte-identical reconstruction of the full
patch stack. Config unchanged.

**Build verification (VM):** full patch set applies cleanly; `.config`
unchanged (`USB_MTU3_HOST=y` etc. as before); build clean, zero
warnings. Packed as build #143 (`logs/2026-07-13-223-stage1-xhci-reg-fix/`,
sha256 `6ae42067a5c50bce21f84b94167006f802473bd1c451d4acfe03c71b852673a0`).

**Hardware result: "HC died" crash.** Flashed and booted; xhci-mtk bound
this time (the sysfs-collision fix worked), but the host controller
crashed shortly after with `xhci_hcd 11271000.usb: xHCI host controller
not responding, assume dead` / `couldn't allocate usb_device`. Root
cause: pure `dr_mode = "host"` only calls `mtu3_host.c`'s
`ssusb_host_setup()` (`ssusb_host_enable()` + `ssusb_set_force_mode()`,
IDDIG override bits) and *assumes* port0's U2/U3 mux is already hardwired
to host by the SoC — true for boards with a fixed Type-A receptacle, not
true for the Gemini's shared Type-C port. The actual port-mux flip
(`switch_port_to_host()` in `mtu3_dr.c`) only runs through the OTG
role-switch work queue, gated on `dr_mode == USB_DR_MODE_OTG`.

## BUILD #144 — dr_mode host→otg + role-switch, 2026-07-13

Changed `patches/v6.6/dts/0009-...`: `dr_mode = "host"` →
`dr_mode = "otg"; usb-role-switch; role-switch-default-mode = "host";` on
the `ssusb` node. This routes through the real `ssusb_role_sw_register()`
→ mux-flip path at probe (reads `role-switch-default-mode` from DT and
runs the full role-switch sequence unconditionally when
`usb-role-switch` is present), without needing a `connector`/ID-pin node.
`CONFIG_USB_MTU3_DUAL_ROLE` (mutually exclusive with `_HOST`/`_GADGET`,
requires `USB_GADGET=y` + `EXTCON=y` as Kconfig deps even though extcon
isn't used at runtime — role-switch takes priority). Still no
g_ether/gadget SSH in this build.

Packed as build #144 (`logs/2026-07-13-144-stage1-otg-rolesw/`, sha256
`94da4bc7d0587cd5100db6bb289248cbc0225312244c554a39db09bd6fb51a24`).

**Hardware result: crash fixed, enumeration still fails.** No more "HC
died" — the OTG/role-switch path is genuinely more correct. But
`/proc/interrupts` still showed SPI 126 (`xhci-hcd:usb1`) at 0 fires, and
`lsusb` showed only the virtual root hub, same as #143. This ruled out
"missing IRQ due to mux/role-switch mechanism" as the remaining blocker —
the symptom is consistent with "nothing ever generates a port-status-change
event at all," i.e. no real electrical connect ever registers, pointing at
power/mux gating rather than IRQ routing.

## BUILD #145 — VBUS mux gap: sw7226 GPIO72, 2026-07-13

User question ("is it something we could harvest from the plant known good
kali?") prompted reading the real vendor 3.18 driver source
(`/Volumes/extdata/github/gemini-android-kernel-3.18/kernel-3.18/drivers/misc/mediatek/usb_c/fusb302/usb_typec.c`,
despite its directory name this chip is actually an **FUSB301A**, a
CC-orientation-only chip with no VBUS/data gating of its own — confirmed
by its probe function only reading `regDeviceID`/`regStatus` over I2C).
`fusb300_eint_work()` shows that on real cable-insert, the vendor driver
asserts *both* `usb1_drvvbus_high` (GPIO94, already wired in #142) *and*
`sw7226_en_high` (GPIO72) — SW7226 is a separate physical USB power-switch
IC gating the real 5V rail; GPIO94 alone is insufficient. Added
`sw7226_en_hog` gpio-hog (GPIO72, output-high) to `&pio` in
`patches/v6.6/dts/0009-...`. Verified locally via `dtc` before syncing
(caught and fixed a `/ {` / `&pio {` nesting bug introduced while adding
the hog, before ever reaching the VM).

Packed as build #145 (`logs/2026-07-13-145-stage1-sw7226-vbus/`, sha256
`4b9a3388dbc511729db34b6d5d246a70673d8f50e73b0c799b794b5f510b41c9`).

**Hardware result: GPIO confirmed correctly asserted, still no
enumeration.** `/sys/kernel/debug/gpio` showed `gpio-606`
(`regulator-usb1-vbus`, GPIO94) and `gpio-584` (`sw7226-en`, GPIO72) both
`out hi`. Stick still not visible in `lsusb`.

## BUILD #146 — fusb301a mux GPIO70/71, 2026-07-13

Same vendor source, `fusb300_gpio_init()`: the idle/default state (set at
driver init, never touched again outside the HDMI alt-mode branch) is
`fusb301a_sw_en_high` (GPIO70) + `fusb301a_sw_sel_low` (GPIO71). Checked
`/sys/kernel/debug/gpio` on hardware after #145 — GPIO70/71 were completely
unclaimed (LK never touches them, nothing in our tree requested them
either), i.e. floating at silicon reset default rather than the vendor's
documented safe-idle values. Added `fusb301a_sw_en_hog` (GPIO70,
output-high) and `fusb301a_sw_sel_hog` (GPIO71, output-low) to `&pio`.

Packed as build #146 (`logs/2026-07-13-146-stage1-fusb301a-mux/`, sha256
`77061130cf9adf897995bb3a642a8dbe0b931bdff7411eaa38b108f5e550593c`).

**Hardware result: booted fine (display + keyboard both fine, initial
"hang" report was just a slower boot, not a regression), USB stick still
only shows the root hub in `lsusb`.** All three vendor-sourced GPIO fixes
(VBUS/94, sw7226/72, fusb301a-mux/70+71) now exactly replicate the
vendor's documented "USB1 OTG mode, no HDMI" idle state, confirmed via
GPIO readback — yet enumeration still fails. This is a useful negative
result: it means the GPIO/mux layer is very unlikely to be the remaining
gap.

## BUILD #147 — FUSB340 redriver GPIO251/252: DISPLAY REGRESSION, reverted in #148, 2026-07-13

Vendor DTB (`docs/vendor-dtb/gemini_kali_boot.dts`) carries a completely
separate `usb_c_pinctrl@0` node (`compatible = "mediatek,usb_c_pinctrl"`)
with pinctrl states named `fusb340_noe_init/low/high` and
`fusb340_sel_init/low/high` — an FUSB340 USB3 SuperSpeed redriver/mux,
distinct from the FUSB301A CC chip and not referenced anywhere in
`usb_typec.c`. Decoded `pins = <0xfb00>`/`<0xfc00>` to GPIO251/252.
Added `fusb340_noe_hog` (GPIO251, output-low = enable, NOE being
active-low by naming convention) and `fusb340_sel_hog` (GPIO252,
output-low, matching the CC1-orientation default assumed elsewhere).

Packed as build #147 (`logs/2026-07-13-147-stage1-fusb340-redriver/`,
sha256 `4afb492115b0325fccf51fbdb1fa17da089c45326f3b37702afa47412535bf23`).

**Hardware result: DISPLAY LOST.** Serial capture
(`logs/2026-07-13-149-stage1-fusb340-crash.log`) looked completely normal
up to the expected B-15 serial death at `mtu3` init — no crash visible in
the log itself. But the physical panel went blank/unresponsive. The only
change from #146 (display fine) was the two new GPIO251/252 hogs. Reverted
immediately (build #148, below) rather than continue guessing blind on a
live display regression.

**Conclusion:** either the vendor-DTB pin-number decode for GPIO251/252 is
wrong, or those pins are genuinely shared with (or gate) something on the
display power/bias path on the real board, contrary to the vendor pinctrl
label naming. Do not re-add without independent GPIO debugfs readback
*and* a hardware test that isolates the display from the USB test —
not both changed in the same build again. This lead is now considered a
dead end absent new evidence.

## BUILD #148 — revert FUSB340 hogs, display restored, 2026-07-13

Reverted the GPIO251/252 gpio-hogs from #147; otherwise identical to #146
(VBUS/94, sw7226/72, fusb301a-mux/70+71 all still present). Regenerated
`patches/v6.6/dts/0009-...`/`0011-...` via the standard apply-edit-rediff
technique, verified full-sequence reapplication byte-identical to the
target file before syncing.

Packed as build #148
(`logs/2026-07-13-148-revert-fusb340-display-fix/`, sha256
`94780ff6b1c49c0de84858c7427cbde91f3980343c3d835982d544295f4d2794`).

**Hardware result: display restored, confirmed by user ("revert
successful").** This confirms GPIO251/252 as the display regression
cause. **Gate G1a status: still open.** Every GPIO-level gate found in
the vendor 3.18 source and vendor DTB for the CC/VBUS/mux path is now
correctly asserted (VBUS/94, sw7226/72, fusb301a-mux/70+71); the FUSB340
redriver lead is a dead end (or at least not safely reproducible via
static GPIO assertion). USB stick enumeration remains unexplained as of
this build — next steps need to consider non-GPIO causes: a genuine
physical connection/cable/stick issue, or something in the mtu3/xhci
driver stack itself now that the "HC died" crash is gone but nothing
electrical is ever detected.

## BUILD #149/#150 — FUSB301A I2C diagnostic: chip responds, ATTACH never fires. Gate G1a PAUSED, 2026-07-13

Enabled the previously-unused FUSB301A driver (`patches/v6.6/usb/0001-...`)
as a pure I2C diagnostic (DTS node `status = "okay"`,
`CONFIG_TYPEC_FUSB301A=y`; deliberately not wired as a `usb-role-switch`
consumer, since the driver's own role-derivation logic is flagged FIXME
and could set `USB_ROLE_NONE`, disabling the port). Build #149
(`logs/2026-07-13-149-fusb301a-i2c-diagnostic/`, sha256
`1ee984a32d84aa2e57e1845b6eb53ed18784129edc3128cd39f0170a44dd9d46`):
`dmesg` confirmed the chip responds — "FUSB301A USB Type-C CC controller
ready" (the `regDeviceID` I2C read succeeded). Bumped the status log from
`dev_dbg` to `dev_info` (build #150,
`logs/2026-07-13-150-fusb301a-status-visible/`, sha256
`7b5a1b277c15869a9ca9f867cb676542761e1f565ceb8d47ab61c39de82a6238`) since
no dynamic-debug support exists in this kernel (`CONFIG_DYNAMIC_DEBUG` not
set, confirmed via missing `/sys/kernel/debug/dynamic_debug/control`).

**Result: `status=0x00 type=0x00 cc=CC1 role=0` — ATTACH bit never set —
with TWO different devices on the confirmed-correct left port:** a USB2.0
SD card reader via a plain USB-C-to-USB-A adapter (VID:PID 349C:0418), and
a native USB-C MediaTek network dongle (no adapter). Same reading both
times. This rules out both "bad test device" and "CC-less adapter cable"
as explanations.

**Conclusion / Gate G1a paused, not resolved.** Every other theory this
investigation has been able to test is now ruled out (see blockers.md B-19
for the full list: xhci sysfs collision, host-only mux gap, VBUS/mux GPIO
gaps, wrong physical port, bad device, bad cable). The one remaining
unverified variable is the FUSB301A `MODE` register write (`0x04`),
reverse-engineered from the vendor 3.18 driver's call site rather than a
real datasheet — if wrong, the chip may never actually enable CC
detection, explaining `ATTACH=0` regardless of what's plugged in. Not
pursuing further register-level guesses without the real FUSB301A
datasheet.

**Reverted to known-good baseline:** re-flashed build #175 (banner #140,
`logs/2026-07-13-175-b18-aw9523b-pinctrl-fix/`, sha256
`d34d58474bca24a851eda4c93ac660aada268c8cb3de1f231d44b00d7c7883c8`) —
keyboard + display + USB gadget SSH all confirmed working together. All
Stage 1 DTS/config work (builds #142-150) remains in `patches/v6.6/` for
when this gate is resumed, but is not part of the currently flashed image.

## BUILDS #176/#177 + B-20 investigation — gadget "not attached" regression; FUSB301A exonerated; left-port UART/USB mux = U2-PHY usb2uart, 2026-07-13/14

Full-evening debugging session after the morning's #175 baseline stopped
enumerating its USB gadget. Timeline and evidence:

**Numbering fix (permanent):** `build-pack.sh` now passes the build number
as `BUILD_NN` → `KBUILD_BUILD_VERSION`, and the verify step FAILS if the
packed kernel's banner ≠ build number (it caught a stale in-VM `build.sh`
on its first run — build-pack now also rsyncs `scripts/`). From #176
onward, banner == build number. Builds ≤ #175 keep their old banners
(#175 = banner #140).

**Builds:**
- **#176 serial-known-good-baseline** (`logs/2026-07-13-176-...`, sha256
  `e30c1036...`): exact #175 patch set (restored from commit `aff681d`;
  Stage 1 fusb301a/host work parked), serial-console config (USB_MTU3
  off, clk_ignore_unused). Booted clean to prompt in 12.2s
  (`logs/2026-07-13-177-serial-baseline-boot.log`, banner #176).
- **#177 usb-gadget-baseline** (`logs/2026-07-13-177-usb-gadget-baseline/`,
  sha256 `f3a22628...`): same patch set + the #175-era USB config
  (byte-identical content to #175). Currently flashed on boot2.

**Rootfs:** the Jul 8 pristine image (`a87d4780...`) was reflashed to p29
mid-evening — a MISTAKE, since it predates the 2026-07-12 Fn-keymap work
(`/etc/gemini.bkmap` + `gemini-keymap.service`), which killed the symbol
keys on the physical keyboard. Rebuilt via `mkrootfs.sh` (VM disk had to
be cleaned: a stale rsync had put 3.3 GB of `logs/` in the VM) → new image
sha256 `063b1ee8...` with keymap + busybox-static + #177 modules,
verified by loop-mount, flashed to p29. Keyboard symbols confirmed back.
Old image preserved as `debian13-rootfs-20260708-a87d4780.img`.

**Gadget regression (B-20) evidence:**
- Kernel and rootfs EXONERATED: pristine rootfs + byte-identical-to-#175
  kernel still fail; failure is at USB enumeration (Mac sees no device at
  all), below the rootfs layer.
- Android (boot slot) enumerates on the same cable/port/Mac
  (`Gemini_4G`) — hardware path intact.
- SSH DID work once mid-evening on #177 + old rootfs (verified
  `uname` banner #177, UDC `configured`) after a sequence involving FTDI
  boots and a live cable swap — then broke again after the mtkclient DA
  session that flashed the new rootfs. Every break tonight had a
  preloader/DA session immediately upstream. Android bounce + cold boot
  + hot replug were each tried afterwards; none reproduced the fix.
- FUSB301A register dump over the (restored) device keyboard, decoded
  against the REAL vendor register map
  (`gemini-android-kernel-3.18/.../fusb301/fusb301.h`: 0x01 DeviceID,
  0x02 Mode, 0x03 Control, 0x04 **Manual**, 0x05 Reset, 0x11 Status,
  0x12 Type — note the Stage 1 driver wrote "mode" to 0x04, which is
  actually the Manual register):
  `DeviceID=0x12 Mode=0x04(SNK) Control=0x03 Manual=0x00
  Status=0x2b (ATTACH=1, VBUSOK=1, BC_LVL=01, ORIENT=CC2) Type=0x08
  (attached-to-source)` — **the CC chip sees the Mac perfectly.** The
  "poisoned FUSB301A" theory is DEAD (Manual=0x00, attach clean).
- GPIO70/71 ("fusb301a_sw_en/sel") probed and driven via
  `busybox devmem` on pio 0x10005000 (MODE bank 0x380 = GPIO mode;
  DIR bank2 0x...20 shows both outputs; DOUT bank2 was 0x0 = en LOW).
  All four (en,sel) combinations tried — NO effect on enumeration, no
  dmesg events, UDC stayed `not attached`.
- Vendor source explains why: `fusb302/usb_typec.c` shows GPIO70/71/72/94
  belong to the **USB1 (right port) OTG/HDMI path** (`fusb300_eint_work`
  switches them on the USB1 ID pin, CC orientation for HDMI alt mode).
  They are NOT the left-port gadget data path.

**New working theory (B-20):** the left port's UART/USB console "mux"
(B-15) is not a discrete mux at all — it is the MT6797 U2 PHY's
**usb2uart function** (FORCE_UART_EN / RG_UART_EN bits in the U2 PHY DTM
registers): D+/D- carry the LK serial console until the tphy driver
clears those bits. If they stay set, USB data never reaches mtu3 while
CC attach (separate pins) looks perfect — exactly tonight's signature.
NOTE: the "#177 boots to prompt with serial" observation that motivated
the mux theory came from a misread log (`2026-07-13-177-serial-baseline-
boot.log` is actually the #176 BOOT — banner #176 inside); a genuine
#177 serial capture has NOT been made yet.

**Next session:**
1. FTDI capture of a #177 cold boot: serial dying at ~0.45s = PHY
   switched (problem elsewhere); serial surviving = PHY stuck in UART
   mode = root cause confirmed.
2. `devmem` read of U2 PHY DTM0/DTM1 (base from mt6797.dtsi u2port0) to
   inspect the uart-mode bits directly on a broken boot.
3. If stuck: clear live as proof, then permanent fix (tphy init path /
   probe ordering).

**CORRECTION (2026-07-14, same session):** a genuine #177 FTDI capture DOES
exist — `logs/2026-07-13-180-b20-177-mux-test.log` (banner #177). It shows
serial dying at t=0.454s mid-mtu3-probe (classic B-15 switch), NOT running
to prompt — the "to prompt" observation was the panel console. So on
broken boots the PHY *does* leave UART mode; "PHY stuck in usb2uart" is
weakened as the sole cause. Refined suspect: mtu3's VBUS/role sensing
(`drd: auto`, no extcon/usb-role-switch wired in our DTS) — the gap is
between PHY switchover and mtu3 deciding to connect. Next-session step 2
(PHY DTM devmem dump) stands, now inspecting force-VBUS/role bits too.

---

## 2026-07-14 — Rootfs prep over live SSH (#177 running): run-once harness, gemini user, persistent journal, Mac SSH key

No kernel/flash changes; all rootfs-only, applied live over gadget SSH to
the running device (#177, `/dev/mmcblk0p29`) and mirrored into
`scripts/mkrootfs.sh` + `rootfs-files/` so reflashes keep them (B-17
lesson). **USB gadget config untouched** (usb0.network, g_ether cmdline —
logged per the standing rootfs/USB rule).

Changes:
1. **run-once diagnostic harness** — `run-once.service` +
   `/usr/local/sbin/run-once-exec`: executes `/root/run-once.sh` at boot
   if present, logs script+output to `/var/log/run-once/<ts>.log`, renames
   the script `.done-<ts>` (single-shot). Purpose: pre-stage devmem/i2c
   diagnostics for boots where SSH and serial are both unavailable (B-20
   broken-gadget boots) — no more panel transcription. Smoke-tested live
   (`systemctl start`, log written, script consumed). Sources in
   `rootfs-files/run-once-exec`, `rootfs-files/run-once.service`.
2. **Persistent journald** (`journald.conf.d/persistent.conf`,
   `/var/log/journal`) — broken-boot dmesg/journal now survives to the
   next good boot.
3. **User `gemini`** (password `gemini`, group `sudo`) recreated — existed
   before, lost in the scatter-restore rootfs wipe. `sudo` package was
   missing on the minbase rootfs (device has no internet route): fetched
   `sudo_1.9.16p2-3+deb13u2_arm64.deb` in the build VM, relayed
   VM→Mac→device, `dpkg -i`. Added `sudo` to PKGS_TOOLS in mkrootfs.sh.
4. **Mac SSH key** installed in `/root/.ssh/authorized_keys` —
   passwordless scripted sessions (verified `BatchMode=yes` login works).

Observed while on: device wall clock is wrong (reads 2026-04-13 — no RTC
sync); run-once log timestamps inherit this until time is set. Harmless
but worth remembering when matching logs to sessions.

## 2026-07-14 — Live register verification on #177 (good boot): usb2uart baseline + FUSB301 two-chip identification

Over gadget SSH on the running #177 (UDC `configured`), using the
vendor-source register map harvested the same day (research.md "USB
Left-Port PHY & Type-C Harvest"):

- `U2PHYDTM0(0x11290868)=0x52000008`, `U2PHYDTM1(0x1129086C)=0x00043E2E`,
  `GPIO MISC(0x10005600)=0x80` — i.e. RG_UART_MODE=01 and the AP-side
  mux still at its "UART" value on a WORKING gadget boot. These bits
  alone do not block USB; only FORCE_UART_EN/RG_UART_EN (which mainline
  tphy clears) differ from the vendor's full uart-mode state. This is
  the good-boot baseline for the B-20 differential.
- FUSB301 probe on all i2c buses: chips at 0x25 on BOTH i2c0 and i2c1
  (DeviceID 0x12 each). With the Mac on the LEFT port: i2c1 Status=0x2b
  (ATTACH/VBUSOK/CC2), i2c0 Status=0x00 → **left port CC controller =
  the i2c1 chip**; the i2c0 chip (target of all B-19 Stage 1 work) is
  the right port's. Both chips at power-on defaults Mode=0x04 (SINK),
  Control=0x03.
- `/root/run-once.sh` staged with this dump set for the next broken
  (Mac-cable-at-power-on) boot; results will land in
  `/var/log/run-once/`.

---

## 2026-07-14 — B-20 ROOT-CAUSED AND PROVEN LIVE: U2 PHY session-valid signals must be software-forced; one devmem write flips a broken boot to `configured`

**The differential (run-once harness, #177, both boots hash-identical
kernel/rootfs):**

| Register | GOOD boot (FTDI protocol) | BROKEN boot (Mac cable at power-on) |
|---|---|---|
| U2PHYDTM0 0x11290868 | 0x52000008 (RG_UART_MODE=01!) | 0x02000000 |
| U2PHYDTM1 0x1129086C | **0x00043E2E** | **0x00000026** |
| GPIO MISC 0x10005600 | 0x80 ("UART") | 0x00 ("USB") |
| FUSB301A (i2c1) Status | 0x2b attach | 0x2b attach |
| UDC | configured | not attached |

Counter-intuitively the BROKEN boot has the *cleaner* PHY state — the
stuck-usb2uart theory is dead. The real diff is DTM1 bits 13:9
(FORCE_VBUSVALID/SESSEND/BVALID/AVALID/IDDIG) + RG values: on good boots
LK leaves the session signals software-forced; mainline tphy only ever
sets RG_VBUSVALID/RG_AVALID (inert without FORCE bits) and relies on
hardware VBUS sensing that this platform doesn't have (vendor mu3d senses
VBUS via PMIC BC1.2/CHRDET and forces these bits in software —
mt_usb.c). Boot with a host attached → LK takes a different path, leaves
FORCE bits clear → mtu3 never sees a valid session → `not attached`
forever, despite `pullup D+` and a perfect CC attach.

**Causal proof (run-once log `20260413-193810` [device clock resets each
boot — 195537 is the older smoke test], broken-protocol boot):**
`devmem 0x1129086C 32 0x3E2E` → UDC `not attached` → **`configured`
within 5s**, RNDIS enumerated on the Mac, SSH login worked — on the boot
protocol that had never once enumerated. B-20's cable protocol is
obsolete once the fix lands.

**Fix (build #225):** `patches/v6.6/phy/0001-phy-mtk-tphy-force-b-
session-valid-for-mt6797.patch` — new DTS-gated behavior in
`u2_phy_instance_power_on()`: property `mediatek,force-b-session-valid`
(added to `u2port0` in dts/0009) sets FORCE_IDDIG/AVALID/BVALID/SESSEND/
VBUSVALID + RG values for device-role/session-valid (the proven 0x3E2E
state), cleared symmetrically in power_off. dev_info logs when forcing
(STANDARDS serial observability). Validated: full patch stack applies on
pristine v6.6, DTS compiles (dtc, zero errors), phy-mtk-tphy.o compiles
clean in the VM.

Expected on-hardware outcome: boot with Mac cable attached from power-on
→ gadget enumerates with no devmem intervention; FTDI-protocol boots
unchanged. Note en12 on the Mac needed
`sudo ifconfig en12 alias 10.15.19.1 netmask 255.255.255.0` again this
session (twice) — recurring post-flash quirk, documented in CLAUDE.md.
**Build #225 provenance:** `logs/2026-07-14-225-b20-force-session-valid/`,
image sha256 `78b71ad393c2d0df1c8a62ea03f1021d1da0391b1b30063761bb015afd460255`,
banner `#225` (verified = build number), DTB spot-check
`mediatek,force-b-session-valid` present, no debug instrumentation.

## 2026-07-14 — BUILD #225 VERIFIED: B-20 CLOSED — boot-with-host-attached enumerates unaided, 3/3

Flashed to boot2 (`mtk w boot2 logs/2026-07-14-225-b20-force-session-valid/new_kali_boot.img`).

**Mac-cable protocol (previously 100% broken): 3/3 consecutive cold boots
enumerated unaided.** Each verified over SSH: banner `#225`, dmesg
`mtk-tphy 11290000.t-phy: u2 phy0: forcing session-valid/device mode`
at 0.449s, `devmem 0x1129086C` = `0x3E2E`, UDC `configured`, RNDIS + SSH
working — no run-once intervention, no cable dance.

**FTDI-protocol regression boot: clean.**
`logs/2026-07-14-226-b20-ftdi-regression-boot.log` — banner #225 on
serial; serial dies at the ~0.45s PHY switch as always (B-15, expected
on gadget builds); after hot-swapping to the Mac cable: UDC
`configured`, SSH working. Display + keyboard unaffected.

**Conclusion:** B-20 🟢. The cable protocol ("never boot with the Mac
cable in") is retired. The left port now behaves like a normal gadget
port regardless of what is attached at power-on. Next: Stage C (B-19
host mode, i2c1 FUSB301 Mode=SOURCE) when scheduled.

---

## 2026-07-14 — B-19 Stage C Phase 0: left-port CC + VBUS chain proven live (no flash, build #225 running)

Not a boot attempt — a series of live userspace probes over gadget SSH on
the already-flashed build #225, using staged self-restoring scripts
(`/root/phase0.sh` iterations v1–v5) because the serial console is dead on
#225 (see side-finding below). Logs:

- `logs/2026-07-14-227-b19-phase0-attach-test.log` (v2: first ATTACH proof)
- `logs/2026-07-14-228-b19-phase0-v3-ethadapter.log` (v3: WD off, CC2 orientation, fault reg clean)
- `logs/2026-07-14-229-b19-phase0-v4-regdump.log` (v4: full BQ25896 regdumps, VBUS ADC=0 despite OTG bit — pin-gate signature)
- `logs/2026-07-14-230-b19-phase0-v5-gpio107-vbus.log` (v5: GPIO107 high → **VBUS_STAT=111, VBUS ADC 5.0V, ATTACH+VBUSOK, adapter LEDs lit**)

Results (full detail: research.md §8, blockers.md B-19):
1. i2c1 FUSB301 Mode=SOURCE detects real sinks (ATTACH=1, Type=0x10, both
   CC orientations seen across devices).
2. Charger is a **TI BQ25896 at i2c0 0x6b** (REG14=0x06) — the RT9466@0x53
   identification was wrong; corrected across hardware.md/CLAUDE.md.
3. BQ25896 boost requires REG03 OTG bit + watchdog disabled + **GPIO107
   (`GPIO_OTG_DRVVBUS_PIN`) high** — LK hands it over low; boost fails
   silently (no fault) without it. With all three: 5.0V at the connector.
All state self-restored after each run (verified: Mode=0x04, REG03=0x1a,
REG07=0x9d, GPIO107 low, device charging from Mac).

**Side-finding (B-20 ledger): build #225 has NO working serial console on
any boot** — the forced session-valid bits keep the PHY pads in USB mode;
the #226 "FTDI regression" capture actually ends at 0.447s (mtu3 probe).
Additionally a power-on with the FTDI rig attached appeared to hang at
`clk: Disabling unused clocks` (stuck on panel too); boot with no cable +
hot-plug works. Serial capture/serial-login are unavailable until the
force bits are gated (planned in Stage C Phase 2).

## 2026-07-14 — BUILD #231: B-19 Stage C Phase 2 host-mode build (not yet flashed)

Provenance: `logs/2026-07-14-231-b19-stage-c-host-mode/` — image sha256
`2033f9372fe58a3be53223f18646dfe14d10b7f4796a8c11d92f2f036b09ff45`, banner
`#231` (verified = build number), debug instrumentation absent, DTB
spot-check `usb-otg-vbus` present. Repo commit `00dc268` (patch set) on
`driver-review-fixes`.

What changed (vs #225 gadget baseline; full detail blockers.md B-19
"Phase 2 patches drafted"):
- `usb/0001` rewritten: FUSB301 driver binds the **i2c1** left-port chip,
  Mode(0x02)=SOURCE, 500ms polling + dev_info CC logging, SINK restored on
  shutdown.
- New `power/0001`: bq25890_charger probes without an IRQ (B-11).
- New `dts/0012`: ti,bq25896@i2c0-0x6b node + `otg_vbus` usb-otg-vbus
  regulator; GPIO107 hog high; ssusb dr_mode="otg" +
  role-switch-default-mode="host" + xhci child (SPI 126);
  vbus-supply=<&otg_vbus>; **B-20 force-b-session-valid removed** (host
  role; should also restore serial console).
- `configs/gemini-usb.config`: MTU3_DUAL_ROLE, XHCI_MTK, TYPEC_FUSB301A,
  CHARGER_BQ25890, usb-storage/usbnet class drivers.

Expected on next capture (flash boot2, FTDI protocol usable again since
force bits are gone):
1. Regression gate first: keyboard + display + serial banner `#231`.
2. bq25896 probe line (no-IRQ warn ok), fusb301 "SOURCE mode, polling"
   line, xhci-mtk probe, SPI 126 present in /proc/interrupts.
3. Gate G1a test: plug SD reader / MediaTek eth adapter into LEFT port →
   FUSB301 "CC change ... sink-attached" + SPI 126 count increments +
   lsusb shows device beyond root hub.
Note: gadget SSH is unavailable in this build (fixed host role) — console
is serial + panel.

## 2026-07-14 — BUILD #231 flashed: host-mode regression PASS, Gate G1a NOT yet passed — live debug session findings

Flashed by user (`mtk w boot2 .../2026-07-14-231-.../new_kali_boot.img`),
banner `#231` confirmed on serial and panel. No serial/FTDI capture file —
early serial worked (banner seen) then died at the B-15 mux as expected for
an mtu3-active build; all subsequent observation via panel console +
photos. Debug scripts `/root/h.sh` (host-enable pokes) and `/root/s.sh`
(status dump) were scp'd to the rootfs via a temporary #225 reflash
(gadget SSH), then #231 reflashed — both survive kernel reflashes.

**Regression gate: PASS.** Boot with FTDI attached no longer hangs (the
#225 clk-cleanup hang is gone with the force bits removed), display +
keyboard fine, banner correct. New-driver evidence, all working:
- `fusb301a 1-0025: FUSB301 CC controller ready (SOURCE mode, polling)`;
  live `CC change` lines on every plug/unplug with correct
  attach/vbusok/orient/sink-type decode. CC layer fully proven in-kernel.
- bq25890 probes (no-IRQ warn as designed); `usb_otg_vbus` regulator
  registers and mtu3+xhci both enable it (use_count 2).
- mtu3 dual-role + xhci: "xhci platform device register success", root hub
  enumerates (`lsusb` 1d6b:0002), `maxchild=1`, role reports `host`.

**Gate G1a: FAIL so far — device never enumerates.** portsc permanently
"Powered Not-connected", SPI 126 count 0. Root-caused a CHAIN of real
defects live (each verified by devmem/i2c on the panel):
1. **BQ25896 lost its programming after boot** — REG03 OTG bit clear,
   REG07 read 0xff (not even the 0x9d default) despite regulator
   use_count=2. Manual rewrite (WD off + OTG on) brought VBUS up (LEDs,
   REG0B=0xe2 boost-running); vbusok=1 in the FUSB Status confirms 5V at
   the connector. Driver needs enable-path hardening (re-assert WD-off +
   OTG on every regulator enable).
2. **Runtime PM kills the host port**: with no device attached xhci
   autosuspends -> mtu3 `ssusb_host_disable` clears IPPC U2_CTRL HOST_SEL
   (read 0x200 = VBUSVALID only) and power-cycles the PHY (wiped our DTM1
   test writes). `echo on > .../1127{0,1}000.usb/power/control` restores
   HOST_SEL (0x2CC). No USB wakeup source is wired, so autosuspend is
   fatal to connect detection — must be disabled in the build.
3. **U2PHYDTM1 LK leftovers**: FTDI-attached boot hands over 0x43E2E
   (forced device-role session-valid, the B-20 signature) — wrong for
   host. Clean no-cable boot hands over 0x0. Manually forced 0x200
   (FORCE_IDDIG, RG_IDDIG=0 = host).
4. **SUSPENDM=0 on clean boot**: DTM0 came up 0x02000000 (PHY analog
   suspended); forced 0x02040008 (FORCE_SUSPENDM|RG_SUSPENDM).
Ruled out by direct readback: usb2uart pad mux (0x10005600=0=USB),
usb2jtag infra mux (0x10001F00 bit14 clear), ACR4 GPIO-mode bits (clear),
ACR6 (vendor host config: VBUSCMP on, BC1.1 off), GPIO70/71 fusb301a_sw
combos (no effect), connector orientation flip (no effect), pad routing
theories generally.

**Still failing after all of the above**: portsc Powered/Not-connected,
zero xhci IRQs, with VBUS live and CC attached. Next diagnostic queued:
PHY linestate monitor readback (0x11290870/74 and ACR0 0x11290800) with
adapter out vs in, to split PHY-sees-D+ (MAC-side break) from
PHY-blind (analog power rails — VUSB33/VA10 are MT6351 PMIC rails with no
mainline driver; LK-inherited state is unverified in host role).
Vendor-source finding for the eventual fix: `usb_phy_recover()`
(mu3phy/mt6797/mtk-phy-asic.c) is the canonical host-side U2 PHY bring-up
(clear all DTM0 forces, BC11 off, VBUSCMP on, + PMIC VUSB33/VA10 on).

## 2026-07-14 — BUILD #233: CONSYS spike Gate G2a (B-19 PARKED, WiFi pivots to internal CONSYS path)

**Decision (user):** B-19 (left-port USB host) is parked after build #231
exhausted the GPIO/mux/PHY-forcing candidates without a connect event.
WiFi is now pursued via the internal MT6797 CONSYS block (plan.md Phase 8
Stage 2, promoted from "feasibility spike only" to "make WiFi work if the
gates pass") — working SSH-over-WiFi would give a debug channel
independent of the left port, making B-19 easier to attack later.

**Provenance:** `logs/2026-07-14-233-consys-spike-g2a/`, sha256
`7e85ce0359548eca8299bc05a44d1bb78650db082c41eaaf3dc5fe505118ad93`,
banner `#233`. DTB spot-check: `consys@18070000` +
`consys-reserve-memory` present.

**Stage W0 groundwork (same day, no flash — see research.md "CONSYS
Stage W0 harvest"):** live devmem on #225 proved LK leaves CONSYS fully
cold (CONN_PWR_CON=0x0, PWR_STATUS bit1 clear, bus-prot clear); firmware
blobs (ROMv3 patches, WIFI_RAM_CODE_6797, WMT_SOC.cfg) + wmt_launcher/
wmt_loader pulled from the device's Android p27 into
`docs/firmware-consys/` with sha256s; full vendor power-on sequence
source-harvested — headline corrections: SPM_CONN_PWR_CON is **0x280**
(plan.md's 0x32C was wrong), the "raw poke 0x10006280 bit4" is just
PWR_CLK_DIS inside the standard MTCMOS sequence, and **no clk-mt6797
change is needed** (vendor "conn" clock = the power domain itself;
"bus" gate compiled out on mt6797).

**What's in the build (all new, B-19 host overlay retired):**
- `patches/v6.6/pmdomain/0002`: CONN domain in mtk-scpsys mt6797 table
  (ctl 0x280, sta BIT(1), sram_pdn BIT(8) no-ack, TOPAXI prot bits 2|8 =
  MT2701 defines) + new `MTK_SCPD_KEEP_DEFAULT_OFF` cap so scpsys does
  NOT blind-power CONN at probe (vendor requires VCN18 first) +
  `MT6797_POWER_DOMAIN_CONN` dt-binding.
- `patches/v6.6/regulator/0002`: minimal MT6351 regulator driver — VCN
  rails only (vcn18/vcn28/vcn33_bt/vcn33_wifi; register addrs from
  vendor upmu_hw.h), binds the pwrap "mediatek,mt6351" child, parent
  regmap, mt6380 pattern. First Linux-side PMIC access in this project.
- `patches/v6.6/soc/0003`: `mtk-consys-spike.c` throwaway probe driver —
  vendor power-on order (VCN18 → 240µs → VCN28 → CONN2AP sleep mask →
  AP_RGU key'd bit12 → SPM PWRON_CONFG_EN 0x0b160001 → CONN domain via
  runtime PM → 30µs → poll chip-ID 0x18070008). Every step dev_info'd
  before execution; full rollback on failure. **Gate G2a pass = dmesg
  line `GATE G2A PASS - CONSYS chip ID 0x279`.**
- `patches/v6.6/dts/0013`: pwrap@1000d000 (mt6797-pwrap, IRQ SPI 178,
  clocks pmicspi_sel + infra_pmic_ap) + mt6351 child with the 4 VCN
  regulators + consys@18070000 node (power-domain CONN, vcn18/vcn28
  supplies) + dynamic 2MB no-map consys EMI reserved-memory.
- `configs/gemini-consys.config` (PWRAP + MT6351 + spike =y).
- **Parked:** `patches/v6.6/dts/0012` → `.disabled` (host-mode overlay);
  `configs/gemini-usb.config` restored to the gadget/g_ether version
  (5a5d553). usb/0001 + power/0001 remain but are config-inert.
  Config verified: `USB_MTU3_GADGET=y`, `USB_ETH=y`, no host/dual-role.

**Expected on hardware:** boot indistinguishable from #225 (display,
keyboard, gadget SSH) + pwrap/mt6351 probe lines + the consys-spike
step-by-step dmesg ending in G2A PASS/FAIL. Failure modes are
step-labelled; a hang identifies the stalled step by the last logged
line. Verification is possible entirely over SSH (`dmesg | grep
consys-spike`) — FTDI not required.

**Flash:**
```
~/gemini-build/mtk-venv/bin/python3 ~/mtkclient/mtk.py w boot2 /Volumes/extdata/github/gemini_linux/logs/2026-07-14-233-consys-spike-g2a/new_kali_boot.img
```

## 2026-07-14 — BUILD #233 flashed: boots clean, gadget SSH restored, but pwrap probe fails -ENOENT → spike deferred; BUILD #234 = one-line pwrap fix

**#233 on hardware (verified over SSH, banner #233):** boot clean, gadget
SSH working again (B-19 park confirmed good), consys reserved-memory
allocated at 0x42600000. But `mt-pmic-pwrap: probe of 1000d000.pwrap
failed with error -2` and `platform 18070000.consys: deferred probe
pending` — the spike never ran.

**Root cause (source-confirmed):** mainline `pwrap_mt6797` carries
`PWRAP_CAP_RESET`, making probe hard-require a `resets = <...>; 
reset-names = "pwrap"` property — but MT6797 has NO mainline reset
provider (clk-mt6797 registers no reset controller), so the property is
unsatisfiable and `devm_reset_control_get()` returns -ENOENT. The reset
is only used inside `pwrap_init()`, which is skipped when LK has already
initialised the wrapper (INIT_DONE2), so it is safe to make optional.

**Fix:** `patches/v6.6/soc/0004-soc-mediatek-pwrap-optional-reset.patch`
— `devm_reset_control_get()` → `devm_reset_control_get_optional()`
(NULL rstc; `reset_control_reset(NULL)` is a no-op even if init runs).

**Build #234:** identical to #233 + soc/0004. Provenance
`logs/2026-07-14-234-consys-spike-g2a-pwrap-fix/`, banner `#234`, DTB
consys spot-check OK. Expected: pwrap probes, mt6351 VCN regulators
register, consys-spike runs → G2A PASS/FAIL dmesg line. Verify over SSH:
`dmesg | grep -iE "consys|mt6351|pwrap"`.

**Flash:**
```
~/gemini-build/mtk-venv/bin/python3 ~/mtkclient/mtk.py w boot2 /Volumes/extdata/github/gemini_linux/logs/2026-07-14-234-consys-spike-g2a-pwrap-fix/new_kali_boot.img
```

## 2026-07-14 — GATE G2A PASSED LIVE (manual, build #234): CONSYS chip-ID 0x0279; root cause of scpsys failure = stale vendor CONN_PWR_CON offset; BUILD #236 carries the fix

**#234 on hardware (banner #234, SSH):** pwrap + MT6351 VCN regulators
probe cleanly (soc/0004 fix confirmed), but `mtk-scpsys ... Failed to
power on domain conn` ×N and the consys spike stayed deferred (genpd
attach powers the domain before the driver's probe runs, so the spike's
own logs never appeared).

**Live root-cause session (all devmem over SSH, no flash):**
- `PWRON_CONFG_EN` unlock made no difference; `CONN_PWR_CON@0x280` reads
  0x0 and **silently rejects writes**, while MJC's PWR_CON at 0x310
  accepts them → not global SPM protection, wrong offset.
- SPM block scan found **0x1000632C = 0x112** (ISO|CLK_DIS|SRAM_PDN —
  the canonical powered-off PWR_CON pattern). The vendor mt_spm.h 0x280
  define is stale for this silicon; consys_hw.c's fallback comments
  ("0x1000632c [3]") and plan.md's original claim were right.
- Manual vendor on-sequence at 0x32C: 0x116 → 0x11E → **PWR_STATUS
  0x…5C→5E / 0x…4C→4E (bit1 ack)** → 0x10E → 0x10C → 0x10D → 0x00D.
- `devmem 0x18070008` → **0x00000279. GATE G2A PASSED.** Notably with
  VCN18/VCN28 still off and no sleep-mask/RGU/PWRON pokes — the
  MTCMOS+chip-ID path needs none of them.

**Build #236** = #234 with `pmdomain/0002` ctl_offs corrected to 0x32C
(comment documents the live proof). Provenance
`logs/2026-07-14-236-consys-g2a-ctloffs-32c/`, sha256
`980b6d0f6cce5d102d6322c8806f1b62994947b57603123adc6a44414665f454`,
banner `#236`. Expected: scpsys powers CONN at attach, spike probe runs
its full sequence and logs `GATE G2A PASS - CONSYS chip ID 0x279`;
display/keyboard/gadget-SSH unchanged. MJC PWR_CON was restored to its
boot value (0x1F12) after the write-stick test; device rebooted before
flashing anyway.

**Flash:**
```
~/gemini-build/mtk-venv/bin/python3 ~/mtkclient/mtk.py w boot2 /Volumes/extdata/github/gemini_linux/logs/2026-07-14-236-consys-g2a-ctloffs-32c/new_kali_boot.img
```

## 2026-07-14 — BUILD #236 VERIFIED: GATE G2A PASSED AT DRIVER LEVEL — Stage W1 COMPLETE

Banner #236 confirmed over SSH. The consys-spike probe ran the full
sequence at 0.578-0.588s (11ms): VCN18 → VCN28 → sleep mask → RGU →
PWRON_CONFG_EN → CONN domain via scpsys (ctl_offs 0x32C fix working —
no "Failed to power on domain conn") → chip-ID **0x279 on the first
read** → `*** GATE G2A PASS - CONSYS chip ID 0x279 ***`.

Regression check: CONN genpd `on`, systemd `running`, mediatekdrmfb
present, gadget SSH working (this session), keyboard unchanged; only
pre-existing warnings in the log (aw9523b group-87 pinconf, gce-client,
EINT, regulatory.db). **Stage W1 complete; W2 (MCU firmware handshake,
Gate G2b) is next.**

## 2026-07-14 — BUILD #237: Stage W2 spike — MCU release + first WMT handshake (Gate G2b)

Provenance: `logs/2026-07-14-237-consys-w2-g2b-mcu-handshake/`, boot.img
sha256 `c646178ae209591c07408edaaacd3541c12352d327ae331b8ed7205ba09bc1b5`,
banner `#237`.

What changed (all desk-sourced from the vendor 3.18 tree this session):

- **soc/0003 extended** (`mtk-consys-spike.c`): after the G2a chip-ID
  pass + ACR MBIST bit, the driver now runs Stage W2: (1) programs the
  CONSYS→AP **EMI remap** — `TOPCKGEN+0x1340 |= ((emi_base &
  0xFFF00000) >> 20) | BIT(12)` — and zeroes the 343K fw ctrl window at
  `emi_base + 512K` (vendor `mtk_wcn_consys_hw.c` order: before MCU
  release); (2) enables `CLK_INFRA_BTIF` (gate exists in mainline
  clk-mt6797, ICG0 bit 31) and initialises the **BTIF** FIFO at
  0x1100c000 in pure PIO-polling mode (FAKELCR=0, new-handshake mode,
  FIFO clear, TRI_LVL 8/4, DMA off, IER=0 — register map from vendor
  `btif_priv.h`); (3) **releases the CONSYS MCU** by clearing WDT
  swsysrst BIT(12) with key `0x88<<24` at 0x10007018 — builds ≤#236
  deliberately left the MCU held in reset; (4) drains + hex-dumps any
  unsolicited ROM bytes, then sends **WMT_QUERY_STP** (`01 04 01 00
  04`) wrapped in STP *mand-mode* framing (`80 40 05 00` hdr + payload
  + `00 00` CRC; WMT task index 4 — vendor `stp_core.c`/`stp_exp.h`)
  and scans 1s of RX for the ROM-default event payload `02 04 06 00 00
  04` (vendor `wmt_ic_soc.c` `WMT_QUERY_STP_EVT_DEFAULT`).
- **dts/0013 extended**: `clocks = <&infrasys CLK_INFRA_BTIF>;
  clock-names = "btif";` on the consys node.
- **Gate G2b criterion**: dmesg line `*** GATE G2B PASS - CONSYS MCU
  ROM answers WMT over BTIF ***`. On failure the driver logs `GATE G2B
  FAIL` with the errno plus full RX hex dumps and leaves
  CONSYS/BTIF/EMI state up for devmem inspection over gadget SSH; the
  probe still returns 0 so the rest of boot is unaffected.

Key protocol discovery (desk): at ROM stage the chip's STP is NOT in
full mode — the vendor sends its first init-table commands in mand
mode (header + zero CRC, no retransmission), so the 3.5-KLOC STP core
is not needed for the G2b gate. The full ROM-patch download
(`WMT_PATCH_ADDRESS_CMD` opcode 0x08 + ≤1000-byte `WMT_PATCH_CMD`
opcode 0x01 fragments over the same channel) is deferred until the
query handshake is proven.

Expected outcome: boot #237, check dmesg for the G2B PASS/FAIL line and
the RX hex dumps. Either result advances W2 — a FAIL's hex dump tells
us whether the ROM speaks at all (electrical/clock issue vs framing
issue).

## 2026-07-14 — BUILD #237 RESULT + BUILD #238: G2b EMI lookup fix

**Build #237 booted and verified over gadget SSH** (banner `#237`,
`logs/2026-07-14-237-consys-w2-g2b-mcu-handshake/`). Gate G2a still
passes (chip-ID 0x279 at 0.58s). **Gate G2b failed at its very first
step**, before any BTIF/MCU work:

```
mtk-consys-spike 18070000.consys: consys-spike: Gate G2b starting
mtk-consys-spike 18070000.consys: consys-spike: memory-region unresolved (-22)
```

Root cause (code bug, not hardware): `consys_mem` is a **dynamic**
reserved-memory node (`size`/`alignment`/`alloc-ranges`, no `reg`), so
`of_address_to_resource()` on it returns -EINVAL — dynamic regions have
no address in the DT; the kernel allocates one at early boot (this boot:
`0x42600000..0x427fffff`, visible in the `OF: reserved mem` line). The
correct API is `of_reserved_mem_lookup()`, which returns the
kernel-chosen base from the reserved_mem table.

**Build #238 (`consys-g2b-emi-lookup-fix`)** changes only that:
`consys_emi_setup()` now uses `of_reserved_mem_lookup()` (+
`linux/of_reserved_mem.h` include) and logs base + size. soc/0003
regenerated (note to future self: the driver file is untracked in the
kernel tree — `git add -N` it before `git diff` or the patch silently
loses the whole driver, as almost happened this session).

- Provenance: `logs/2026-07-14-238-consys-g2b-emi-lookup-fix/`
- sha256: `1766aeb3f91011bb02599fee9e61a4434b2d61cacba63ef69a7597c2727ba16a`
- Banner `#238` verified; dtb-grep `consys-reserve` OK.

Expected: EMI remap programmed with the runtime base, then the MCU
release + WMT_QUERY_STP handshake actually runs — first real G2b data.

## 2026-07-14 — BUILD #238 RESULT (live-debug session) + BUILD #239: BTIF FIFO pulse + wakeup

**Build #238 booted (banner verified).** EMI fix worked: remap word
0x1426 programmed (base 0x42600000), ctrl window zeroed, BTIF up,
MCU released — but **G2b FAIL (-110)**: WMT query TX went out, 0 RX
bytes.

**Live SSH debugging (the big result): the CONSYS MCU ROM IS RUNNING.**
CONSYS_CPUPCR (0x18070160, MCU program counter, harvested from vendor
`wmt_plat_read_cpupcr`) returns a different value on every read
(0x458, 0x435A, 0x130B2 …) — power, clocks, EMI and the reset release
are all correct. Gate G2b's remaining problem is purely the BTIF
channel.

Root cause found by re-reading vendor `hal_btif_hw_init`: the BTIF
FIFOCTRL clear bits are **level-held, not self-clearing** — the vendor
sets then explicitly clears each; build #237/#238 wrote
`CLR_TX|CLR_RX` once and left them asserted, holding both FIFOs in
reset. LSR evidence agrees: at first TX the FIFO drained (THRE=1) with
the last byte stuck in the shifter (TEMT=0), and any ROM reply was
discarded by the held RX clear. Attempts to un-wedge the block live
(FIFOCTRL release, full re-init, old-handshake mode, BTIF_WAK pulse,
bus-protect pokes) did not recover it — needs a clean boot.

Also harvested: `hal_btif_send_wakeup_signal` — BTIF_WAK (+0x64) must
be pulsed low >1/32kHz then high before TX (ap_wakeup_consys line);
never done in #237/#238. Side-finding: vendor SPM CONN_PROT_MASK is
bits 2|8 (mt_spm_mtcmos.c:1149) — same as MT2701, so our scpsys entry
is correct; the 18|19 mask in mtk_wcn_consys_hw.h belongs to a
compiled-out branch (CONSYS_PWR_ON_OFF_API_AVAILABLE=1).

**Build #239 (`consys-g2b-btif-fifo-wakeup`)**, soc/0003 changes:
1. FIFO clear bits pulsed (set RX, clear; set TX, clear) per vendor.
2. `btif_wakeup_consys()` BTIF_WAK pulse before every WMT TX.
3. One 500ms-delayed retry of the query on timeout.
4. FAIL path now logs 3 CPUPCR samples + LSR/IIR (ROM-executing
   evidence in the log itself).

- Provenance: `logs/2026-07-14-239-consys-g2b-btif-fifo-wakeup/`
- sha256: `d18973f8ebbfc21ef715cf0f9702577922b91c5cafaa98601895ab74e3ef4848`
- Banner `#239` verified.

Expected: RX FIFO now actually retains the ROM's reply — best shot yet
at the G2B PASS line.

## 2026-07-14 — BUILD #239 RESULT (live-debug) + BUILD #240: real CONN bus-protect mask (bits 17|18)

**Build #239 booted (banner verified).** FIFO pulse + BTIF_WAK helped
the evidence but not the outcome: first WMT TX drained fully, RX 0
bytes; retry TX jammed (LSR TEMT stuck). FAIL-path diagnostics worked:
CPUPCR samples in the log (0x55aa55d6/da/de) prove the ROM executing.

**Root cause found (live SSH + vendor cross-check): wrong TOPAXI
bus-protect mask on the CONN domain.** Three CONN_PROT_MASK values
exist in the vendor tree:
- `mt_spm_mtcmos.c`: bits 2|8 (what our scpsys entry copied, via the
  MT2701 defines) — STALE, that file is not the runtime path;
- `mtk_wcn_consys_hw.h`: bits 18|19 — STALE, compiled-out branch;
- `clk-mt6797-pg.c` line 193: **bits 17|18** — the REAL one: this file
  implements `clk_scp_conn_main` (the vendor's actual runtime CONN
  power path, CONSYS_PWR_ON_OFF_API_AVAILABLE=1) and its CONN_PWR_CON
  0x032c define carries a literal "correct" comment, independently
  matching our live-proven 0x32C discovery.

Live signature: INFRA_TOPAXI_PROTECTEN reads 0x104B8 = exactly
MD1_PROT_MASK (modem off, expected), CONN bits 17|18 clear in EN, but
**PROTECTSTA1 bit 18 stuck asserted** — the CONN slave-side protection
was never released in-sequence, so every BTIF byte toward CONSYS
stalls (LSR TEMT stuck low) and the ROM's BTIF is unreachable, while
chip-ID/CPUPCR reads use a different path and work. Late manual
17|18 pulses can't clear the stuck ack (wedged outstanding BTIF
transaction); it must be released in the scpsys power-on sequence
(vendor order: PWR_RST_B, then release protect) on a clean boot.

**Build #240 (`consys-conn-busprot-17-18`)**: pmdomain/0002 CONN
`.bus_prot_mask` changed from the MT2701 bits (2|8) to `BIT(17) |
BIT(18)`, comment block updated with the three-mask provenance story.
No other changes.

- Provenance: `logs/2026-07-14-240-consys-conn-busprot-17-18/`
- Banner `#240` verified.

Expected: scpsys now releases the real CONN protection right after the
domain powers on — first boot where the BTIF↔CONSYS path is actually
open. If the ROM answers, G2B PASS.

## 2026-07-14 — BUILD #240 RESULT: bus-protect fix verified (protection releases), but ROM still silent — G2B FAIL (-110); exhaustive live session points off-AP

Log: SSH session on build #240 (banner verified). G2a PASS again (chip-ID
0x279 @0.59s). G2b FAIL (-110), but the failure signature CHANGED —
the bits 17|18 bus-protect fix is confirmed working:

- `TOPAXI_PROTECTEN` 0x10001220 = 0x104B8 (MD1 bits only) and
  `PROTECTSTA1` 0x10001228 **bit 18 now CLEAR** (was stuck set on #239).
- Proof of open path: the FIRST 11-byte WMT_QUERY_STP frame TXed
  completely (LSR drained; on #239 no frame ever drained). The retry
  frame then wedged (LSR 0x20 → 0x00) and no RX byte ever arrived.

Live-debug findings (all over SSH devmem):
1. **The CONSYS MCU ROM runs but never services BTIF.** CPUPCR samples
   alternate 0x55AA55xx (suspected idle/WFI marker pattern) with real ROM
   addresses (0x428, 0x3538, 0x435A). Interpretation: the first frame's
   bytes were swallowed by the CONSYS-side BTIF link FIFO (never drained
   by the ROM); once full, all later TX stalls — matches every observed
   LSR state.
2. Re-asserting + releasing the MCU reset (0x10007018 swsysrst bit12) live
   and re-querying 10ms after release: peer accepts nothing (its FIFO
   still full; CPU reset does not clear the link FIFO).
3. AP2CONN_OSC_EN (0x10001f00 bit9) wakeup pulse and BTIF_WAK pulses: no
   effect.
4. EMI ctrl window (0x42680000): still all zeros — the ROM writes nothing
   there (so no evidence it even runs its normal boot path beyond the
   idle loop).
5. Host BTIF now matches vendor `hal_btif_hw_init` bit-for-bit (FAKELCR=0,
   HANDSHAKE=1 new-handshake mode, TRI_LVL=0x48, DMA_EN=0x4, sleep off,
   FIFOs pulse-cleared). Frame format verified correct against vendor
   `stp_send_data_no_ps` mand-mode branch (hdr `80 40 05 00`, 2 zero
   "CRC" bytes; note byte0 is FIXED 0x80 in mand mode — the seq<<3 retry
   variants #239/#240 send are technically malformed, fix in driver).
6. MCU config block healthy: HW_VER 0x8A00 (exact vendor table match for
   MT6797 E1), FW_VER 0x8A00, chip-ID 0x279, ACR 0x340002 (MBIST bit18
   already set — vendor step 14 satisfied), CONN_PWR_CON=0xD, PWR_STATUS
   bit1 set, 0x10006280=0.
7. PMIC clock-buffer check: MT6351 DCXO_CW00 (0x7000) reads 0x6b6d — 
   XO_EXTBUF2/WCN enable bit5 IS set (vendor init would write 0x4DFD;
   mode-field differs, bits 3-4 = 01 vs vendor 11 — the only AP-visible
   delta left). Vendor also programs the pwrap DCXO_CONN bridge
   (pwrap+0x190..0x19C + DCXO_ENABLE bit1) so hardware toggles CW00 bit5
   on CONSYS 26M requests — we never program that bridge.

Conclusion: every register the vendor 3.18 power-on sequence touches now
matches, yet the ROM ignores BTIF. Remaining hypothesis space (DCXO
mode/bridge, an invisible CONSYS-internal prerequisite, or "0x55AA55xx =
wedged not idle") is NOT resolvable from source reading — this is
exactly the Stage W0b golden-reference case: boot the vendor Kali 3.18
stack with working WiFi and harvest the same registers (CPUPCR pattern
when healthy-idle, CW00/DCXO regs, BTIF peer behavior, EMI ctrl window
contents after ROM boot). Decision pending user (requires ~5.5GB
linux.img reflash + restore).

## 2026-07-15 — Stage W0b GOLDEN HARVEST COMPLETE (vendor Kali 3.18, WiFi working) + BUILD #244: three golden-reference fixes

The user's suggested golden-reference harvest paid off decisively. Vendor
Kali stack booted (boot2 = planet/kali_boot.img, linux = planet/linux.img),
WiFi associated (wlan0, -52 dBm), and the full register set was harvested
over SSH (kali/kali) with a python /dev/mem devmem (vendor kernel has
CONFIG_STRICT_DEVMEM unset; the vendor /proc/driver/wmt_dbg interface also
mapped: 0x17 ap-vaddr read, 0x1b cpupcr poll — pr_debug-gated, unused).

Artifacts:
- `logs/2026-07-15-242-w0b-kali-golden-wifi-on.txt` — full harvest, WiFi on
- `logs/2026-07-15-243-w0b-kali-fresh-boot-dmesg.txt` — fresh-boot dmesg
  with the complete WMT bring-up timeline
- `logs/2026-07-15-243-w0b-kali-crash-capture.log` — serial boot capture

Golden values vs our build #240 state (deltas marked ★):

| Register | Golden (WiFi on) | Ours (#240) |
|---|---|---|
| CPUPCR 0x18070160 | 0x0009997A steady (occasional 0x7FD08/0x24A0) | 0x55AA55xx pattern ★ |
| CONN_PWR_CON 0x1000632C | **0x10D — bit 8 (SRAM_PDN) SET** | 0xD (we clear bit 8) ★ |
| AP2CONN_OSC_EN 0x10001f00 | 0x6D403A00 (bit 11 set) | 0x11403200 ★ (watch item) |
| BTIF HANDSHAKE +0x6C | 0x3 | 0x1 ★ |
| BTIF TRI_LVL +0x60 | 0x18 | 0x48 ★ |
| BTIF DMA_EN/RTOCNT/WAT_TIME | 0x7 / 0x40 / 0x12 | PIO / default / default |
| pwrap DCXO_CONN bridge 0x1000D18C-19C | ALL ZERO | n/a — clock-buffer theory dead |
| MCU_CFG_ACR 0x18070110 | 0x340002 (0x334 transient) | 0x340002 same |
| HW_VER/FW_VER/0x114/0x120 | identical to ours | — |
| CONN2AP_SLEEP_MASK / EMI remap encoding | identical scheme (golden EMI base 0xBFA00000) | — |

Timeline from the fresh-boot dmesg: power-on finishes 11.550s, btif_open
11.551s, chip-id hwcheck 11.552s, first WMT query (init_table_1_2) succeeds
~11.60s, both ROM patches downloaded by 11.94s (frag 47+211), STP ready
12.86s, "co-clock disabled." So on working hardware the ROM answers the
query ~50ms after reset release — our 263ms delay was never the issue, and
0x55AA55xx CPUPCR is now proven ABNORMAL (wedged/bus artifact, not idle).

Incident: the first harvest run crashed the vendor kernel (panic → WDT →
Android-slot fallback) at its last two probes — the pmic_access poke or the
EMI-window read at 0xBFA80000. Those reads are removed from future harvests.
One reboot later Kali came back (a middle boot was actually the Android slot
— serial log proved it — and one Kali boot stopped short of the UI at the
getty; second attempt fully recovered, WiFi reconnected as .135).

**BUILD #244** (`consys-g2b-golden-fixes`, sha256 `7d681d06...`, banner
verified #244) applies every safe match-the-golden-reference change:
1. pmdomain/0002: CONN `.sram_pdn_bits` GENMASK(8,8) → **0** — the top
   suspect. Vendor never touches the SRAM_PDN field; golden runs WiFi with
   bit 8 still set; the off-state reset value (0x112) also has it set. Our
   generic scpsys sequence was clearing it — the single known divergence
   in the power-on sequence itself.
2. soc/0003: BTIF TRI_LVL 0x48→0x18, HANDSHAKE 0x1→0x3 (golden values).
3. soc/0003: mand-mode frame byte0 fixed at 0x80 (vendor
   stp_send_data_no_ps mand branch has no tx-seq field; our seq<<3
   retries were malformed).
Held in reserve (not in this build): 0x10001f00 bit 11 delta.

Expected: CONN_PWR_CON reads 0x10D after power-on and the ROM answers
WMT_QUERY_STP → G2B PASS. If still -110, next single variable =
0x10001f00 bit 11.

## 2026-07-15 — B-19 golden-reference attempt on vendor Kali 3.18: vendor left-port host mode is BROKEN TOO (no flash; live SSH session, ended by crash)

Opportunistic host-mode test while the vendor stack was flashed for W0b.
User plugged a USB memory stick (and earlier an ethernet dongle) into the
LEFT port. Findings (all over kali@192.168.100.135 SSH, sshpass):

1. **ID-pin/role-switch path works on the vendor kernel:** on attach,
   `otg_state` switch → 1 and xhci registers (`xhci-hcd
   11270000.usb3_xhci` — buses 2+3, incl. a USB 3.0 root hub). The
   earlier dongle "3 lsusb entries" were ONLY these root hubs.
2. **VBUS is never driven — vendor host mode fails at the same point ours
   does.** dmesg: `xhci-hcd 11270000.usb3_xhci: Cannot find usb pinctrl
   drvvbus_high` — this Halium DTS lacks the drvvbus pinctrl state (=
   GPIO107 driver). No device ever enumerated; dongle/stick LEDs dark on
   vendor kernel too. So the vendor Kali image is NOT a working host-mode
   golden reference, and dark LEDs on our kernel were never evidence
   against our VBUS chain.
3. GPIO107 forced high live (`devmem 0x10005134 32 0x800`, DOUT verified
   1 via mtgpio) — still no enumeration, consistent with the BQ25896
   REG03 OTG bit not being set (charger reported idle: battery
   `Not charging`, ac/usb online=0).
4. Attempting to READ BQ25896 registers via the vendor
   `/sys/devices/platform/bq25890-user/bq25890_access` node **rebooted
   the device** — same class of failure as the pmic_access crash. RULE:
   never touch any vendor `*_access` sysfs node on the 3.18 kernel,
   read or write.

Consequence for B-19: the vendor 3.18 Kali stack cannot demonstrate
left-port host mode, so there is no golden register state to harvest
there. Host mode must be proven on OUR kernel (build #231 patch set:
FUSB301-i2c1 SOURCE + bq25890 usb-otg-vbus + GPIO107 hog + xhci), where
Phase 0 already proved the full VBUS chain from userspace.

## 2026-07-15 — Right-port host mode WORKS on vendor Kali: musbfsh (usb1@11200000), SD reader enumerated + mounted

Follow-up to the left-port entry above (device rebooted after the
bq25890_access read; Kali back at 192.168.100.137). User moved the SD
reader to the RIGHT port: enumerated immediately — `349c:0418`, 480 Mbps,
on **bus 1 = MUSBFSH HDRC** (`usb1@11200000`, IRQ GIC 105, PHY
`usb1p_sif@11210000`), `sda1` FAT auto-mounted. Left-port PHY stuck at
DTM1=0x00053E2E (forced device session) even in "host" state — the
vendor host switch aborts at the missing `drvvbus_high` pinctrl.
Evidence: `logs/2026-07-15-245-vendor-rightport-host-enum.log`; analysis
in research.md "Right-port USB host — vendor architecture". B-19 gains a
candidate easy path: mainline musb mediatek glue on usb1@11200000.

## 2026-07-15 — BUILD #247 (consys-g2b-spike-kconfig-fix): #244 was a silent no-op — spike driver never built; Kconfig hunk restored

Post-detour, the user restored the Debian rootfs and flashed build #244
(G2b golden fixes). Verification over gadget SSH: banner `#244` correct,
MT6351 VCN regulators registered — but **zero CONSYS/BTIF/spike output in
dmesg**. Root cause: `CONFIG_MTK_CONSYS_SPIKE` was absent from #244's
built config (not even as a comment). The `config MTK_CONSYS_SPIKE`
Kconfig entry existed only as an uncommitted edit in the Mac kernel
tree; when `patches/v6.6/soc/0003` was regenerated for the golden-fixes
build, the Kconfig hunk was lost (and `mtk-consys-spike.c`, being an
untracked new file, is invisible to plain `git diff HEAD`). In the VM's
clean tree the symbol didn't exist, so `olddefconfig` silently dropped
the fragment's `CONFIG_MTK_CONSYS_SPIKE=y` and the driver was never
compiled. **Build #244 therefore tested nothing — its G2b outcome is
void, and the golden fixes (scpsys sram_pdn_bits=0, golden BTIF config,
mand-mode byte0=0x80) remain unexercised.**

Fix: regenerated soc/0003 with all three files (Kconfig + Makefile +
full mtk-consys-spike.c via `git diff --no-index /dev/null`). Verified
in #247's provenance config: `CONFIG_MTK_CONSYS_SPIKE=y` present,
`mtk_consys_spike_probe` in System.map. Lesson for patch regeneration:
**new files and new Kconfig entries must be explicitly included —
`git diff HEAD -- <file.c>` alone silently omits untracked files.**

- Provenance: `logs/2026-07-15-247-consys-g2b-spike-kconfig-fix/`
- sha256: `3810bd14a84ff8dc1b2563b04e40191d8403f3f482d8fd695416e01ad4a7d1a1`
- Banner: `#247 SMP PREEMPT Wed Jul 15 06:11:07 UTC 2026`
- Flash: `mtk w boot2 logs/2026-07-15-247-consys-g2b-spike-kconfig-fix/new_kali_boot.img`
- Expected: dmesg `consys-spike: *** GATE G2B PASS ***` (or a FAIL line
  naming the stalled step, state left up for devmem inspection).

## 2026-07-15 — BUILD #247 live G2b debug: G2a PASS again, G2b FAIL (-110) — MCU ROM runs but never services BTIF; all harvested golden deltas eliminated live

Flashed #247 (banner verified). Spike ran fully this time: **G2a PASS**
(chip-ID 0x279 at 0.59s), then G2b fails at WMT_QUERY — 0 RX bytes, and
the tell is on the TX side: **BTIF LSR sticks at 0x20** (THRE set, TEMT
never) — one byte parked in the TX shifter forever. FIFO-clear (FCR
0x06) restores LSR=0x60; the very next TX byte re-sticks at 0x20. A UART
shifter drains regardless of the peer unless internally flow-gated, so
the CONN-side BTIF peer is never accepting — consistent with the CONSYS
MCU ROM crashing/parking early. CPUPCR samples mix real ROM PCs
(0x19A0/0x41C/0x3540/0x4308/0x435A/0x130C0) with 0x55AA55xx
(sleep/gated indicator); golden post-firmware CPUPCR is 0x0009997A.

Live-eliminated variables (each written on the running system, MCU
reset-cycled where relevant, no change to the stuck-TX symptom):
1. `AP_RGU_SWSYSRST` bit16 cleared (golden 0x0; ours had 0x10000 since
   boot).
2. `MCU_CFG_ACR` 0x18070110 topped up to golden 0x03340002 (bits 24/25).
3. `AP2CONN_OSC_EN` 0x10001f00 set to full golden 0x6D403A00.
4. Vendor AFE/WBG analog table (0x180B6000, step 15 of
   `mtk_wcn_consys_hw.c`, missing from the spike) written with MCU held
   in reset, then released.
5. BTIF HANDSHAKE=1 (vendor value; spike used 3) + manual WAK pulse
   (0x64: 0→64µs→1) + FIFO clear.
6. **EMI-MPU hypothesis tested and weakened:** CONSYS_EMI_MAPPING
   remapped to golden 0x180E1BFA (vendor window 0xBFA00000) with MCU
   reset-cycled — same stuck TX, so the preloader's EMI MPU permitting
   only the vendor window is not (alone) the explanation.
7. Confirmed already-correct: CONN_PWR_CON=0x10D, SPM_CONN_PWR_CON
   0x10006280=0 (golden), CONN2AP_SLEEP_MASK=0x11D (golden),
   infra0 CG bit15 (CONNMCU_BUS) and bit31 (BTIF) both ungated,
   TOPAXI CONN_PROT bits 2|8 clear, MCU_HW_VER 0x8A00 = golden.

Also decoded from vendor source this session: `MT_CG_INFRA_CONNMCU_BUS`
= infra0 CG bit 15; CONN_PROT_MASK = TOPAXI bits 2|8 (build #240's
bits 17/18 were wrong); BTIF_WAK = base+0x64 bit0 (write-only pulse);
BTIF_HANDSHAKE = base+0x6C, vendor EN=1.

Open hypothesis space for next session: (a) golden *pre-patch* ROM state
was never harvested — vendor golden numbers are all post-firmware, so we
don't know what a healthy ROM-idle CPUPCR/BTIF looks like; (b) something
in the vendor CCF `clk_scp_conn_main` (scpsys 3.18) enable path beyond
our scpsys CONN domain sequence; (c) conn-side co-clock/XO setup
(`co_clock_type=0` path pokes `MT6351_PMIC_RG_VCN28_ON_CTRL=1` HW-mode
before VCN28 enable — our regulator driver may differ); (d) ROM may
require the 32k/26M co-clock routing from PMIC (DCXO_CONN bridge regs
all 0 in golden though). Device left safe: MCU in reset, EMI mapping
restored to 0x42600000.

## 2026-07-15 — BUILD #248: B-19 RESUMED (user decision, W2/G2b parked) — host mode with all four #231 defects fixed; target = USB ethernet adapter → SSH

**Context:** user parked the CONSYS G2b hunt and pivoted back to B-19: get a
USB ethernet adapter enumerating on the left port in host mode, then use
SSH-over-ethernet as the debug channel for the WiFi work (frees the
gadget/serial tangle entirely).

**New evidence before building (live on #247 over gadget SSH):** the MT6351
**VUSB33/VA10 PHY rails are ON** — pwrap regmap debugfs (exposed by the W1
regulator driver) reads LDO_VUSB33_CON0 0x0A16=0xda62 (EN bit1=1),
LDO_VA10_CON0 0x0A6E=0xda62 (EN=1), VA10_ANA_CON0 0x0B10=0x0100. This
weakens #231's "PHY-blind analog rails" suspect (register addresses from
vendor upmu_hw.h). Also root-caused #231 defect 2's mechanism: both mtu3
and xhci-mtk already pm_runtime_forbid() at probe — the autosuspend came
from Debian's /lib/udev/rules.d/60-autosuspend.rules (hwdb ID_AUTOSUSPEND)
writing power/control=auto. And defect 3's mechanism: mtu3 NEVER calls
phy_set_mode(), so tphy's host-role IDDIG code is dead code on this SoC.

**Provenance:** `logs/2026-07-15-248-b19-host-mode-defect-fixes/`, sha256
`99bf2c1aa53a46348a55e0e43e1f898f594435dd99370dd7c4559450e2b76edb`, banner
`#248 SMP PREEMPT Wed Jul 15 06:57:30 UTC 2026`. DTB spot-check:
`mediatek,force-usb-host` present. Config verified (per the #244 lesson):
MTU3_DUAL_ROLE/XHCI_MTK/TYPEC_FUSB301A/CHARGER_BQ25890 + usbnet drivers
all =y; System.map has bq25890/fusb301a/xhci_mtk symbols.

**What's in the build (all four #231 defects baked in):**
- `phy/0001` extended: new DTS-gated `mediatek,force-usb-host` on u2port0
  — in u2_phy power_on force DTM1 FORCE_IDDIG with RG_IDDIG=0 (host) and
  DTM0 FORCE_SUSPENDM|RG_SUSPENDM (defects 3+4); undone in power_off;
  survives PHY power cycles, unlike #231's hand pokes.
- `power/0001` extended: `bq25890_vbus_enable` re-asserts F_WD=0 before
  every OTG enable + dev_info (defect 1 — chip observed losing probe-time
  programming, REG07=0xff).
- `dts/0012` re-enabled from `.disabled` (dr_mode=otg +
  role-switch-default host + xhci child + bq25896/otg_vbus + GPIO107 hog +
  fusb301a i2c1), with force-b-session-valid comment block replaced by
  `mediatek,force-usb-host;`. **dts/0013 second hunk context regenerated**
  — it was written against a tree without 0012 and its EOF context no
  longer matched (first #248 build attempt failed at the patch step;
  fixed and stack pre-validated in the VM).
- `configs/gemini-usb.config` restored to the 00dc268 host build + extra
  usbnet drivers (AX8817X, RNDIS_HOST, SMSC95XX on top of CDCETHER/
  RTL8152/AX88179_178A).
- CONSYS W1/W2 patch set stays in (spike will log G2B FAIL -110 at boot —
  expected, harmless).

**Rootfs changes (staged live over #247 SSH, survive kernel reflashes) —
flagged per the rootfs-USB-change rule:**
- `/etc/udev/rules.d/99-gemini-usb-host-pm.rules` — pins power/control=on
  for 11270000.usb/11271000.usb and all USB devices (defect 2 fix).
- `/etc/systemd/network/usb-host-ether.network` — DHCP on `en*/eth*`
  except usb0 (gadget usb0 keeps static 10.15.19.82; it is inert in this
  host build anyway).
- `/root/h.sh` (manual host-enable pokes, fallback) and `/root/s.sh`
  (status dump incl. the queued PHY **linestate monitor** 0x11290870/74 +
  ACR0 0x11290800, bq25896 + fusb301 register dumps) re-staged — the old
  copies were gone from the rootfs.

**Expected on hardware:** boot clean (serial dies at the B-15 mux as on
#231 — panel console is the observation channel), fusb301a SOURCE +
bq25890 + xhci root hub probe lines, then plugging the ethernet adapter
into the LEFT port should fire SPI 126, enumerate, bind a usbnet driver,
DHCP via systemd-networkd, and be SSH-able from the Mac over the LAN.
If still "Powered Not-connected": run `/root/s.sh` at the physical
console with adapter out vs in and compare the linestate words — that
splits MAC-side break vs PHY-analog-blind, the #231 queued diagnostic.

**Flash (user, device in preloader mode):**
```
~/gemini-build/mtk-venv/bin/python3 ~/mtkclient/mtk.py w boot2 /Volumes/extdata/github/gemini_linux/logs/2026-07-15-248-b19-host-mode-defect-fixes/new_kali_boot.img
```

## 2026-07-15 — BUILD #248 flashed: 🟢 GATE G1a PASSED — first USB host-mode enumeration + SSH-over-ethernet-adapter working end-to-end

**Result: B-19 resolved.** Realtek RTL8156 USB-C 2.5G ethernet adapter
(0bda:8156, the same unit proven under vendor Kali) enumerates on the left
port, binds r8152, gets DHCP (192.168.100.144) and is SSH-able from the
Mac over the LAN. Verified TWICE: once after manual recovery pokes, then
the clincher — a **cold boot with zero manual intervention**: tphy
`forcing host role` 2.96s → bq25890 `enabling OTG boost` 3.12s →
vbusok 3.55s → FUSB301 `attach=1 sink-attached` (CC1) 22.5s →
`new high-speed USB device` 22.8s → SPI 126 firing (774+) → DHCP → SSH.
REG0B=0xe2 (boost running), FUSB Status=0x19.

**The two live root causes found this session (on top of #248's baked-in
fixes, which all worked as designed):**
1. **External charge power suppresses the OTG boost** — with a charger
   present the BQ2589x hardware enters charge mode (REG0B=0x36
   VBUS_STAT=001 + fast-charging), drops/ignores the OTG bit (REG03 read
   0x1a) and never sources VBUS: adapter dead, FUSB attach=0. This is
   chip behaviour, not a driver bug. The #231 session was very likely
   fighting this the whole time too (device usually charging during
   debug). CAVEAT: plugging a charger while in host mode will cut the
   adapter; after charger removal the boost does NOT self-resume
   (/root/h.sh re-asserts it). Driver hardening (re-enable OTG when
   input removed) is a follow-up.
2. That was the only remaining blocker — with power actually flowing,
   CC attach, linestate, IDDIG, SUSPENDM and enumeration all just worked.

**Known rough edges (not blockers):**
- One unexplained kernel panic during the first SSH-initiated `reboot`
  (panel showed a backtrace; pstore came up EMPTY next boot — ramoops
  capture didn't record it, worth wiring up properly before chasing).
  Subsequent cold boot clean.
- `r8152: unable to load firmware patch rtl_nic/rtl8156b-2.fw` — works
  without; add linux-firmware blob to the rootfs sometime.
- `r8152: exports duplicate symbol` — stale module on the rootfs
  colliding with the now-builtin driver; cosmetic.
- s.sh's FUSB "vbusok" read 1 even with boost off earlier in the session
  — that bit's decode may lag/latch; don't use it as a VBUS meter.

**Consequence for the WiFi plan:** SSH now works over the ethernet
adapter with the gadget path unused — serial (FTDI) and SSH are no longer
mutually exclusive once serial returns (host build serial still dies at
the B-15 mux; next serial-capable build can drop mtu3 if ever needed).
B-21 CONSYS G2b debugging can resume with a live SSH channel + the panel.

## 2026-07-15 — Right-port VBUS proven live (zero kernel changes): GPIO94+GPIO72 alone power the right port — independent of the BQ25896 boost

**Motivation:** left-port ethernet means the device runs on battery (host
mode and charging are mutually exclusive on the shared left connector +
BQ boost). Under Kali, charge-on-left + host-on-right worked
simultaneously, implying the right port has its own VBUS source.

**Proven live over SSH on #248:** GPIO decode verified against the
GPIO107 hog (MTK v1 pio: DOUT bank base 0x10005100+bank*0x10, +4=SET,
+8=RST — earlier reads of the SET regs return 0, don't be fooled). LK
already leaves GPIO70/71/72/94 configured as outputs driving 0. One
write `devmem 0x10005124 32 0x40000100` (GPIO94 usb1_drvvbus + GPIO72
SW7226 load switch high) → the same RTL8156 adapter's LEDs lit in the
RIGHT port, with the BQ boost busy elsewhere. So the #144-146 GPIO
harvest was correct all along — right port power is just those two pins.

**What remains for right-port host under mainline (new workstream):**
1. Controller: `usb1@11200000` (`mediatek,mt6797-usb11`) = MUSB
   host-only instance (vendor driver drivers/misc/mediatek/usb11/
   "musbfsh"). Mainline glue `drivers/usb/musb/mediatek.c`
   ("mediatek,mtk-musb", MT2701/MT8516) is the same IP family — needs a
   DTS node + clock-name adaptation (CLK_INFRA_ICUSB exists in
   clk-mt6797).
2. PHY at 0x11210000 (`usb1p_sif`) — NOT in mainline mtk-tphy. Best
   case: register layout matches generic-tphy-v1 and it's a DTS-only
   addition; else small PHY driver from vendor musbfsh phy code.
3. DTS gpio-hogs for GPIO94+72 (+70/71 OTG-mux idle values from #146).
4. FUSB301 i2c0 (right-port CC chip) node → SOURCE mode via the existing
   usb/0001 driver (second instance).
Payoff: ethernet/host on the right + charging (and serial) on the left.

## 2026-07-15 — BUILD #249: right-port MUSB host (first attempt, not yet flashed)

**Goal:** host on the RIGHT port so the left port is free for charging —
under Kali charge-on-left + host-on-right worked simultaneously; VBUS
independence proven live earlier today (GPIO94+72 only, boot.md above).

**Provenance:** `logs/2026-07-15-249-b19-right-port-musb-host/`, sha256
`97ab102b87652d9fdb9d55e0e35727aeb6889502c174a8f61104b12d03572377`,
banner `#249 SMP PREEMPT Wed Jul 15 08:01:19 UTC 2026`. DTB spot-check:
`usb@11200000` present. Config verified: USB_MUSB_HDRC/MEDIATEK/
DUAL_ROLE + NOP_USB_XCEIV + MUSB_PIO_ONLY =y; System.map has mtk_musb/
musb_core symbols.

**New pieces:**
- `usb/0002`: mtk-musb glue `devm_clk_bulk_get` → `_optional` — MT6797
  usb11 only has the infra icusb gate ("main"); no "mcu"/"univpll".
- `dts/0014`: (a) second `generic-tphy-v1` instance at 0x11210000 with
  u2port1@11210800 + `mediatek,force-usb-host` — vendor musbfsh PHY
  pokes map byte-for-byte onto tphy-v1 U2 bank (0x6C/0x6D = U2PHYDTM1),
  so the PHY needs NO new driver; (b) `usb1@11200000` on
  `mediatek,mtk-musb` (SPI 73 level-low, CLK_INFRA_ICUSB as "main",
  dr_mode="host", phys=u2port1); (c) four gpio-hogs: GPIO94
  usb1-drvvbus HIGH + GPIO72 sw7226-en HIGH (VBUS chain) + GPIO70
  fusb301a-sw-en HIGH / GPIO71 sw-sel LOW (vendor USB-OTG mux position,
  70 goes low only for HDMI alt-mode — vendor fusb302/usb_typec.c
  fusb300_eint_work harvest). No FUSB301-i2c0 node yet: vendor host
  path never used CC (pure ID-pin), and today's live test proved the
  adapter powers + the left-port RTL8156 enumerated without any CC
  negotiation.
- `configs/gemini-usb.config`: musb options appended (PIO-only for
  bring-up; DMA later). musb mode = default DUAL_ROLE; dr_mode="host"
  in DT fixes the role.

**CAVEAT while these hogs are active: the right port is host-only — do
NOT plug a charger into the right port** (VBUS contention against the
SW7226 output). Charge on the left port.

**Expected on hardware:** left-port behaviour identical to #248
(ethernet+SSH). New: musb probe lines, then a device in the RIGHT port
should enumerate on a second USB bus (`lsusb` Bus 002; SPI 73 in
/proc/interrupts). Test = LED ethernet adapter in the right port +
second `enx...` interface, while the no-LED adapter keeps SSH on the
left. Failure modes: musb probe clk/phy errors (dmesg), or bus up but
no connect (would implicate the GPIO70/71 mux or PHY linestate — same
debug pattern as B-19 left).

**Flash (user, preloader mode):**
```
~/gemini-build/mtk-venv/bin/python3 ~/mtkclient/mtk.py w boot2 /Volumes/extdata/github/gemini_linux/logs/2026-07-15-249-b19-right-port-musb-host/new_kali_boot.img
```

## 2026-07-15 — BUILD #249 flashed + BUILD #250: right-port musb probes but VBUS_ERROR; session-valid forcing extended to host role

**#249 on hardware (banner #249, verified over left-port SSH):**
- Left port unchanged: adapter enumerated on xhci (bus 2), SSH working —
  no regression from the musb/tphy additions.
- Right port: PARTIAL — musb-hdrc probes ("MUSB HDRC host driver", bus
  1), the second tphy instance runs force-usb-host at 0.47s, the hogs
  power the adapter (LEDs lit), but the MAC loops at
  `VBUS_ERROR in a_idle (80, <SessEnd), retry #0, port1 00000104` and
  never enumerates: the PHY isn't reporting VBUS-valid to the MUSB OTG
  state machine. Vendor musbfsh_mt65xx.c confirms the fix: on host
  enable it FORCES avalid/bvalid/vbusvalid and clears sessend on this
  PHY — the host-side twin of B-20.

**BUILD #250** (`logs/2026-07-15-250-b19-right-port-musb-session-force/`,
sha256 `ce644b71f90e7a8494b889b1c70fa1a6c389d2d253d1f48c698ebc61c5cdca45`,
banner `#250`): phy/0001's `mediatek,force-usb-host` extended to the full
vendor host state — IDDIG=0 + P2C_FORCE_SESS_MSK + RG vbusvalid/avalid/
bvalid set + RG_SESSEND cleared + SUSPENDM forced; symmetric clear in
power_off. New dmesg string "session forced valid" verified present in
the packed kernel. NOTE: u2port0 (left) shares the property, so the left
port inherits the forced session bits in host role — regression check of
left-port SSH is mandatory on this build.

**Flash:** `mtk w boot2 .../2026-07-15-250-b19-right-port-musb-session-force/new_kali_boot.img`

## 2026-07-15 — BUILDS #250/#251 on hardware + BUILD #252: right-port session-force works, bulk still dead, DMA crashes the SoC → PIO + full-speed cap

**#250 flashed:** session-valid forcing fixed the VBUS_ERROR — musb
enumerates devices now. New failure layer: cdc bulk-IN dies with
`ep2 RX three-strikes error` ×N then `Babble`; after babble the OTG FSM
falls to b_idle (DEVCTL 0x99) and never re-enumerates. **Vendor babble
recovery replayed live over devmem WORKS**: DTM1 0x3E10 (sessend pulse)
→ 0x3E2C (session restore) flips DEVCTL back to 0x5D and the device
re-enumerates instantly (vendor musbfsh_mt65xx.c
mac_phy_babble_clear/recover). Also: mainline glue UNBIND OOPSES in
devm_usb_phy_release (NULL deref) — never unbind musb; noted, not chased.

**#251 (Inventra DMA) flashed:** enumeration fast/clean, BUT zero bulk
completions (TX counter frozen at 0 with urbs submitted; MAC state
textbook-healthy: DEVCTL 0x5D, all INTRTXE/RXE + DMA channels unmasked)
AND the system hard-crashed twice within minutes (green-screen panic,
then a hang) with both adapters active. pstore/ramoops IS bound and
mounted (44410000.ramoops, driver linked — earlier "pstore not wired"
theory wrong) yet records nothing → crashes are hard bus lockups with no
panic path, consistent with a rogue DMA master starving/corrupting the
interconnect. The glue's "mcu" clock (absent on MT6797) may be the DMA
engine's bus path. DMA = off until understood.

**Addressing cleanup (rootfs):** RTL8156 = 192.168.100.145 static,
Naxiang = 192.168.100.146 static, one IP each, matched by MAC (the
earlier "both IPs on one adapter" confusion was Linux ARP-flux + the
static file following the RTL's MAC). No default route on these — LAN
SSH only. Vendor-source babble recovery + these facts belong in the
FUSB/h.sh tooling notes.

**BUILD #252** (`logs/2026-07-15-252-b19-right-port-musb-pio-fullspeed/`,
sha256 below, banner `#252`): musb back to MUSB_PIO_ONLY (no crashes on
PIO builds) + mtk-musb glue now honors DT `maximum-speed` (usb/0002,
musb_dsps precedent) + dts/0014 sets `maximum-speed = "full-speed"` on
usb1. Theory under test: the three-strikes/babble is HS signal integrity
through the SW7226/FUSB301a mux chain; FS (12 Mbps, SSH-grade) should
carry bulk cleanly. Verified in artifacts: CONFIG_MUSB_PIO_ONLY=y,
"capping port to full-speed" string in Image, DTB usb@11200000 has
full-speed. Success = Naxiang on the right port passes real traffic
(ping/SSH via 192.168.100.146 with the left adapter's route removed from
the test path).

## 2026-07-15 — BUILD #252 flashed and verified (banner #252, SSH over .146); right-port FS test NOT yet run — session ends, state parked as B-22

- #252 boots clean; `musb-mtk 11200000.usb: capping port to full-speed`
  present; left port (xhci) carries SSH fine (Naxiang adapter,
  192.168.100.146 static-by-MAC).
- The decisive experiment — a device in the RIGHT port at full speed,
  checking whether bulk finally flows (no three-strikes/babble) — was
  NOT run this session; right port was empty at wrap-up.
- Side anomaly to keep in mind: earlier on this #252 boot the RTL8156 on
  the left had UP + IP (.145) but passed NO traffic either direction.
  New variable since it last worked: rtl_nic/rtl8156b-2.fw was installed
  on the rootfs (loads now). If the RTL misbehaves again, remove
  /lib/firmware/rtl_nic/rtl8156b-2.fw to revert that variable. The
  Naxiang on the same port works, so the port itself is exonerated.
- Full right-port state, findings and resume plan recorded in
  blockers.md **B-22** (new).

## 2026-07-16 — #252 FS test result read live + ROOT-CAUSE CANDIDATE: mainline glue config ≠ musbfsh hardware → BUILD #253 (6-EP non-multipoint config)

**#252 full-speed result (read over SSH from the running device,
dmesg of boot #252):** the decisive experiment ran — Naxiang cdc_ether
on the RIGHT port enumerated at **full speed** (`usb 1-1: new full-speed
USB device number 2 using musb-hdrc`), registered `enxec9a0c162365`,
got its IP, then bulk STILL failed:
`NETDEV WATCHDOG: transmit queue 0 timed out` (zero TX completions),
`Could not flush host TX2 fifo: csr: 2003` (TXPKTRDY stuck — packet
loaded into the FIFO, never transmitted on the wire) +
musb_h_tx_flush_fifo WARN, then `ep2 RX three-strikes error` and
unregister. **The HS-signal-integrity theory is falsified** — control
(EP0) works, bulk moves nothing in either direction at any speed →
MAC/glue layer.

**Root-cause candidate (vendor source vs mainline):** mainline
`drivers/usb/musb/mediatek.c` hardcodes the MT8516 OTG controller
config — `num_eps=8`, `multipoint=true`, EP1–7 FIFO table (EP6=1024).
The vendor MT6797 usb11 driver (`musbfsh_core.c`,
`musbfsh_config_mt65xx` + `epx_cfg`) says this hardware is the cut-down
musbfsh IP: **`num_eps=6` (EP0+5), `multipoint=false`, EP1–5 all 512B
BUF_SINGLE** ("fits in 4KB"). Consequences match the symptoms exactly:
multipoint=true makes musb_core address bulk transfers via per-EP
TXFUNCADDR/busctl registers this hardware doesn't implement (EP0
enumeration survives because the FADDR path still works during setup),
and num_eps=8 programs FIFO size/address through the INDEX register for
EPs 6–7 that don't exist. May also explain the #250 HS babble and the
#251 DMA lockups (unprogrammed/aliased FIFO addressing).

**BUILD #253** (`logs/2026-07-16-253-b22-right-port-musbfsh-config/`,
sha256 `7a46773a32ed334460eaaba293f109362428783b53c3831d1d7f526c8146baeb`,
banner `#253`): usb/0002 extended — adds `mediatek,mt6797-musb`
compatible with `.data` → new `mt6797_musb_hdrc_config` (6 EPs,
multipoint=false, EP1–5 512B single-buffered fifo table); probe now
takes the config from `of_device_get_match_data()` (falls back to the
stock config) and the FS-cap kmemdup dups the selected config.
dts/0014: usb1 compatible switched to `mediatek,mt6797-musb`.
Single-variable: **full-speed cap kept**, PIO only kept
(CONFIG_MUSB_PIO_ONLY=y verified in merge output), DTB grep
`mediatek,mt6797-musb` present.

**Expected next capture:** Naxiang in RIGHT port → full-speed
enumeration, NO watchdog/three-strikes, real traffic on
192.168.100.146 with the right interface's own RX/TX counters moving.
Then the B-22 success gate: charger LEFT + ethernet RIGHT
simultaneously. If it still fails: vendor musbfsh_host.c CSR/IRQ-ack
comparison, then the missing "mcu"/AHB bus-clock hunt.

Flash:
`~/gemini-build/mtk-venv/bin/python3 ~/mtkclient/mtk.py w boot2 /Volumes/extdata/github/gemini_linux/logs/2026-07-16-253-b22-right-port-musbfsh-config/new_kali_boot.img`

## 2026-07-16 — BUILD #253 flashed and tested: REGRESSION, worse than #252 → isolating the variable for BUILD #254

**Result (read live over SSH, banner confirmed #253):** neither adapter
enumerates on the right port at all now — both the RTL8156 and the
Naxiang, tried in turn, produce an endless retry loop that never
succeeds even at the control-transfer stage:
```
usb 1-1: new full-speed USB device number N using musb-hdrc
usb 1-1: device descriptor read/all, error -71   (EPROTO)
[repeats ~20+ times over 2+ minutes, never settles]
```
This is a regression from #252, where the Naxiang got all the way
through enumeration (interface bound, cdc_ether registered, IP
assigned) and only failed later at the bulk-data stage. #253 fails
earlier — before an interface even exists — meaning the musbfsh config
change made things worse, not better.

**Left port unaffected, confirming the fault is right-port-specific:**
on the SAME boot/build, both the RTL8156 (192.168.100.145) and Naxiang
(192.168.100.146) were swapped into the LEFT port and worked flawlessly
(SSH confirmed to both IPs, banner #253). This proves the left
(xhci-mtk/mtu3) and right (usb11/MUSB) controllers are fully
independent silicon with zero interaction — see blockers.md B-22 "Why
the two ports must be treated as fully separate problems" for the full
writeup (added this session).

**Diagnosis:** build #253 changed TWO things in one step —
`multipoint: true→false` AND `num_eps: 8→6` + trimmed FIFO table. Since
the result is worse (control transfers now fail, not just bulk), one of
these two changes is wrong for this hardware, or they need to be
combined differently. Isolating: **BUILD #254** reverts `multipoint`
back to `true`, keeping only the `num_eps=6`/trimmed EP1–5 FIFO table,
to determine which half broke enumeration.

## BUILD #254 — multipoint reverted to true, num_eps=6/trimmed FIFO kept (isolating the #253 regression)

**Change:** `mt6797_musb_hdrc_config` now has `.multipoint = true` (only
`num_eps=6` + the trimmed EP1-5 512B FIFO table stay from #253).
`logs/2026-07-16-254-b22-right-port-multipoint-revert/`, sha256
`8352b0b01262a70688f95b6d0cea12c22467f25abd05dae371ffc399f0458e5c`,
banner `#254` verified, DTB grep `mediatek,mt6797-musb` present.

**Purpose:** #253 combined `multipoint=false` + `num_eps=6` in one step
and REGRESSED right-port enumeration itself (both adapters stuck in
endless `device descriptor read/all, error -71` retries — worse than
#252's 8-EP/multipoint=true baseline, which at least enumerated fully
before dying on bulk). This build isolates which half broke it: if
enumeration succeeds again (matching #252's behavior) with multipoint
reverted, the FIFO/num_eps trim was safe and multipoint=false was the
regression; if it still fails, num_eps=6/FIFO trim itself is the
problem and multipoint isn't involved.

**Expected next capture:** flash boot2, test both adapters in the RIGHT
port (left port confirmed working for both, build #253, unaffected —
see blockers.md B-22 "why the two ports must be treated separately").
If enumeration succeeds: repeat the bulk-data test from #252 to see if
num_eps=6/trimmed FIFO alone fixes the TX-stuck/three-strikes failure.
If it still fails to enumerate: multipoint isn't the culprit, look
harder at the FIFO table/ram_bits interaction.

Flash:
`~/gemini-build/mtk-venv/bin/python3 ~/mtkclient/mtk.py w boot2 /Volumes/extdata/github/gemini_linux/logs/2026-07-16-254-b22-right-port-multipoint-revert/new_kali_boot.img`

## 2026-07-16 (later) — BUILD #254 flashed and tested: RIGHT-PORT BULK DATA WORKS — B-22 root cause fixed

Confirmed on hardware, banner `#254`: RTL8156 in the RIGHT port enumerated
full-speed (`usb 1-1: new full-speed USB device number 2 using musb-hdrc`),
bound `cdc_ether` cleanly, got a DHCP/static lease
(`192.168.100.146/enxec9a0c162365`), and **this exact SSH session was
conducted over that interface** — `ip -br link` on the device shows `usb0`
(left-port gadget) is `DOWN`/no-carrier, so there is no ambiguity about
which port carried the traffic. `ip -s link` counters: RX 43510B/279pkts,
TX 22182B/78pkts, **zero errors/drops** — no watchdog timeout, no
`three-strikes`, no babble, no TXPKTRDY-stuck (`csr: 2003`) anywhere in
dmesg. This is the first time the right port has passed bulk data
end-to-end.

**Root cause confirmed:** `multipoint=false` (introduced in #253) was the
regression — MUSB's multipoint addressing mode (per-endpoint
TXFUNCADDR/HUBADDR "busctl" registers for routing to downstream hub
ports) doesn't exist on this musbfsh IP; forcing it off broke control
transfers entirely (`error -71` on every descriptor read). Reverting
`multipoint` to `true` (mainline default — the MT6797 musbfsh apparently
tolerates the field being set even though it doesn't route through a
hub) while keeping `num_eps=6` + the trimmed EP1-5 512B FIFO table (the
actual vendor-hardware-accurate fix) resolved the original TX-stuck/
three-strikes bulk failure from #252. So: **`num_eps`/FIFO trim was the
real fix; `multipoint=false` was an incorrect extra change that broke
enumeration.**

Left port (RTL8156/Naxiang, build #253) was previously confirmed still
fully working; not retested this build but no shared state exists
between the two controllers (blockers.md B-22 "why the two ports must be
treated separately"), so no regression is expected there.

**Not yet tested:** battery was "Discharging"/`online=0` during this
capture — no charger was plugged into the left port. The B-22 success
gate (Step 3 of the plan) — charger on LEFT + ethernet on RIGHT
simultaneously, confirmed via `power_supply` sysfs — is the next and
final validation step.

## 2026-07-16 (later still) — charger plugged in but NOT charging: root cause found — LEFT port still forced host, blocking BQ25896 input → BUILD #255

With build #254 confirmed working (right-port ethernet, previous entry),
the user plugged a charger into the LEFT port to test the actual B-22
goal (charge left + ethernet right). `power_supply` sysfs still read
`Discharging`/`online=0` with the charger connected. dmesg showed, at
3.156s into every boot:
```
bq25890-charger 0-006b: enabling OTG boost (watchdog re-disabled)
```
— i.e. the BQ25896 is put into **OTG boost/source mode** unconditionally
at boot, regardless of whether a charger is plugged in. Traced to
`patches/v6.6/dts/0012` (left-port host-mode overlay, written for the
now-superseded B-19 Stage C left-port-host workstream): the `ssusb` node
still carries `dr_mode = "otg"` + `role-switch-default-mode = "host"` +
`vbus-supply = <&otg_vbus>`, so `mtu3`'s role-switch probe calls
`regulator_enable()` on the `usb-otg-vbus` regulator at every boot —
`bq25890_vbus_enable()` fires unconditionally, putting the charger IC
into source mode. A chip in source mode cannot simultaneously act as a
sink for an external charger, so the "enabling OTG boost" line and the
"Discharging" reading were the same root cause, not two separate bugs.

This was pure leftover: B-22's host duty moved to the RIGHT port
(usb1/MUSB, dts/0014) once build #248 established right-port dongles
work, but the LEFT port's host-mode DTS was never reverted back to
peripheral-only.

**Fix (BUILD #255):** new patch `patches/v6.6/dts/0015` (applies after
0014) reverts the LEFT port (`ssusb`/`u2port0`) back to its original
peripheral role:
- `mediatek,force-usb-host` → `mediatek,force-b-session-valid` on
  `u2port0` (B-20's original device-role force — this PHY still has no
  hardware VBUS/session sensing, so *some* force is still required, just
  the device-role one instead of the host-role one).
- `ssusb` node: `dr_mode = "otg"` + `usb-role-switch` +
  `role-switch-default-mode = "host"` + `vbus-supply = <&otg_vbus>` +
  `#address-cells`/`#size-cells`/`ranges` + the `xhci@11270000` child
  node all removed; `dr_mode = "peripheral"` restored.
- `otg_vbus` regulator node and the GPIO107 hog in `&pio` are left in
  place (harmless — no consumer left to auto-enable the regulator; the
  hog only gates the boost enable path, per its own comment, so it
  doesn't source anything by itself).

Banner `#255` verified (`SMP PREEMPT Thu Jul 16 01:08:16 UTC 2026`), DTB
grep confirms `dr_mode = "peripheral"` (line 1025, left port) alongside
`dr_mode = "host"` (line 1110, right MUSB port — dts/0014, untouched).
`logs/2026-07-16-255-b22-left-port-drop-host-mode/new_kali_boot.img`.

**Expected next capture:** flash boot2, confirm no more "enabling OTG
boost" line at boot, then plug the charger into the LEFT port and check
`/sys/class/power_supply/bq25890-charger-0/status` — expect `Charging`
(or `Full`) and `online=1` instead of `Discharging`/`0`. With an ethernet
adapter simultaneously in the RIGHT port, this is the actual B-22
success-gate test.

Flash:
`~/gemini-build/mtk-venv/bin/python3 ~/mtkclient/mtk.py w boot2 /Volumes/extdata/github/gemini_linux/logs/2026-07-16-255-b22-left-port-drop-host-mode/new_kali_boot.img`

## 2026-07-16 (final) — BUILD #255 flashed and tested: B-22 SUCCESS GATE PASSED

Charger in LEFT port + RTL8156 ethernet in RIGHT port, same boot, banner
`#255`:
```
root@gemini:~# cat /sys/class/power_supply/bq25890-charger-0/status
Charging
root@gemini:~# cat /sys/class/power_supply/bq25890-charger-0/online
1
```
`enxec9a0c162365` (right port) live with clean RX/TX counters (391/145
pkts, 0 errors), and the user confirmed the charging LED lit on the
device itself. `usb0` (left-port RNDIS gadget) also came up automatically
— a side effect of `dts/0015` restoring `mediatek,force-b-session-valid`,
which makes the left port auto-enumerate as a gadget whenever a host is
present, exactly as it did before the B-19 host-mode detour.

**B-22 is closed.** See blockers.md for the full fix chain across builds
#252-#255.
