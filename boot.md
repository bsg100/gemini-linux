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
