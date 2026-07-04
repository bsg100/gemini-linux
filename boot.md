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

## Future Entries

Boot logs from kernel bring-up attempts will be appended here as Phase 3 progresses.

**First entry on FTDI cable arrival (per blockers.md B-1):** baseline serial
capture of the known-good 3.18 Kali boot — validates cable/wiring/baud before
any 6.6 flash.
