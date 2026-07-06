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
