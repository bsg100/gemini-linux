# B-13 bare-metal diagnostic payload

## Known issue — payload never executes; harness PARKED (2026-07-07)

**Status: this payload has never run on the hardware.** Every packaging
variant tried hangs identically inside ATF/BL31 before `el3_exit` (same
PC ~`0x46026020`, same ~12.3s watchdog window), while a control reflash of
the known-good mainline build in between booted clean (so it is not a
device/environment regression). Variants tested, all with identical results:

| Variant | Log | What it ruled out |
|---|---|---|
| v1: gzip'd payload, no ARM64 Image header | `logs/2026-07-06-114` | — (baseline) |
| v2: correct 64-byte Image header (magic @ offset 56) | `-116` | malformed/missing header |
| v3: raw uncompressed binary | `-118` | gzip handling of tiny input |
| v4: raw binary zero-padded to 1 MB | `-120` | size-threshold bug |
| v5: gzip'd + real project DTB | `-122`, reboot `-123` | empty DTB; first-boot flakiness |
| v6: `--kernel-addr 0x40200000` | `-125` | nothing — LK ignores this field (boot.md "Aligned kernel_addr Retested"), no-op by design |
| control: known-good mainline build | `-126` (clean boot) | device regression |

A `text_offset=0x80000` theory was also formed and reverted un-flashed:
boot.md's own findings show `text_offset=0` is what every mainline kernel
ships and LK's jump address is fixed at `0x40080000` regardless.

The failure timing (~12.3s, independent of payload size/content) suggests
ATF/LK is polling for something our blob never satisfies rather than
choking on its bytes — root cause open.

**Probable root cause found 2026-07-07 (from build #127's capture,
`logs/2026-07-07-128-…`):** LK logged `[LK]jump to K64 0x40200000` and ATF
`pc=0x40200000` for a normally-packed mainline kernel — LK **does** honor
the boot.img header's `kernel_addr` (pack-boot-img default `0x40200000`),
contradicting the earlier "fixed 0x40080000" reading of the prior logs.
This payload is linked at `0x40080000` (`link.ld`) but every variant was
loaded/executed at `0x40200000`, so all absolute addresses (`ldr x0,
=_stack_top`, `=vectors`, string literals) pointed 1.5 MB below the real
image — Linux survives this via position-independent head.S +
CONFIG_RELOCATABLE; this payload has no such relocation. Untested fix if
ever revived: change `link.ld` to `. = 0x40200000;` (and re-check the v6
capture's assumptions). The v6 "staged kernel_addr" test then also needs
reinterpreting: it moved load and link *apart* further, not together.

**Superseded by:** an in-kernel equivalent diagnostic
(`patches/v6.6/drm/0007-GEMINI-DEBUG-cpu0-irqsoff-poll-loop.patch`) that
runs the same experiment — cpu0 spinning with IRQs masked, raw-MMIO UART
heartbeat + `CNTPCT` + GICD pending/active dumps — inside the proven-bootable
Linux kernel right after DRM/DSI bind. It answers the same
hardware-lock-vs-software question without needing this boot chain solved.
The harness code below is kept as-is (compiles clean, believed correct) in
case the ATF packaging issue is ever cracked.

## Purpose

Every register/driver-level hypothesis for B-13 (cpu0 hard-locks, all
interrupt sources including its own local timer, ~2.4s into boot with the
display config enabled) has been tested and refuted under Linux — see
`blockers.md` B-13. The remaining open question is whether this is a genuine
hardware/AXI bus lock, or something specific to Linux's own interrupt/
scheduler/RCU/cpuhp plumbing that a from-scratch bare-metal payload
wouldn't reproduce.

This payload runs on cpu0 only, at EL1, with no Linux anywhere in the
picture: its own tiny GICv3 bring-up, its own EL1 physical-timer heartbeat,
its own vector table. If the heartbeat survives indefinitely, that's strong
evidence B-13 is Linux-software-specific. If it dies at the same ~2.4s mark
with no Linux running at all, that's strong evidence of a genuine hardware
lock triggered by something in the display-enable sequence.

## Scope of this first cut

Only the scpsys MM-domain power-on sequence is replicated here
(`main.c:scpsys_mm_power_on()`), which Linux's own per-step trace already
proved is a no-op (LK leaves MM domain already powered) and NOT the trigger
(boot.md "per-step power-on trace"). It's included as a control: if this
harness can't even survive a register sequence already proven safe, the bug
is in the harness (GIC/timer setup), not in B-13.

**Not yet included:** SMI larb/common enable and DSI/MIPI controller init —
also each individually proven not to cause an *immediate* hang under Linux,
but the actual delayed trigger (something that only manifests ~100ms later,
during an unrelated `cacheinfo_sysfs_init()` call) is still unidentified.
Follow-up: pull the exact DSI/MIPI init register sequence from the vendor
source (`/Volumes/extdata/github/gemini-android-kernel-3.18/kernel-3.18/drivers/misc/mediatek/video/mt6797/dispsys/ddp_dsi.c`)
and add it as a second phase in `main.c`, gated behind a UART prompt or
compile-time flag so each phase can be tested incrementally rather than
re-introducing several unknowns at once.

## Build (in the VM — native aarch64 gcc, no cross-compiler needed)

```
ssh -p 5522 root@localhost
cd ~/gemini_linux/baremetal/display-hang-test
make
```

Produces `payload.img` — a gzip'd raw binary (same compression LK expects
for the kernel blob; verified compatible with today's `Image.gz` boot flow).

## Pack into a boot.img

Reuses `scripts/pack-boot-img.py` — it just concatenates `--kernel` +
`--dtb` as the kernel blob and copies the reference boot.img's ramdisk
unchanged (unused here, this payload never reaches a ramdisk). Needs a dummy
DTB file since the script requires one; an empty file works, since LK's
gunzip stops at the compressed stream's own end and copies whatever
trailing bytes follow to RAM without interpreting them — our payload never
reads them either.

```
touch /tmp/dummy.dtb
python3 scripts/pack-boot-img.py \
    --reference planet/kali_boot.img \
    --kernel baremetal/display-hang-test/payload.img \
    --dtb /tmp/dummy.dtb \
    --out OUTPUT/b13-baremetal-test.img
```

## Flash and capture

Only `boot2` needs the test payload (per the flashing rules, only targeted
`mtk w` writes — leave `boot` alone):

```
/tmp/mtk-venv/bin/python3 ~/mtkclient/mtk.py w boot2 OUTPUT/b13-baremetal-test.img
```

```
cd /Volumes/extdata/github/gemini_linux
python3 scripts/ftdi-monitor.py --log logs/YYYY-MM-DD-NN-b13-baremetal-boot.log
```

## Reading the result

Expect output like:

```
[b13-baremetal] cpu0 entry, MMU off, no Linux
[gic] cpu0 redistributor + CPU interface up, PPI30 enabled
[timer] CNTFRQ_EL0 = 0x...
[b13-baremetal] heartbeat armed, running scpsys MM power-on
[scpsys] MM ctl before: 0x...
[scpsys] MM ctl after:  0x...
[b13-baremetal] entering heartbeat loop (no further register writes)
[hb] 1 cntpct=0x...
[hb] 2 cntpct=0x...
...
```

- **Heartbeat count climbs steadily past ~24 (2.4s at the 100ms period
  configured in `main.c`) and keeps going indefinitely:** the scpsys
  sequence alone doesn't reproduce anything at the bare-metal level (expected,
  consistent with Linux's own finding that this step is a no-op). Move on to
  adding the SMI/DSI phases.
- **Heartbeat stops advancing, `cntpct` value also stops advancing between
  reports:** genuine full CPU/clock lock — the arch counter itself has
  stopped, which is as close to "the hardware truly froze" as this harness
  can show.
- **Heartbeat stops advancing but a later manual read of `cntpct` (e.g. via
  JTAG/SWD if ever available) shows it still counting:** cpu0 is executing
  but has lost interrupt delivery specifically — points at GIC/timer state,
  not a full core lock.
- **`[irq] unexpected INTID ...` or `[EXC] unexpected exception ...`:** the
  harness itself hit something unplanned (spurious interrupt, alignment
  fault, etc.) — a bug in this payload, not new B-13 evidence.

## Recovery

This payload never touches storage or the ramdisk; recovery is a normal
`boot2` reflash back to the known-good mainline build
(`logs/2026-07-06-77-maxcpus8/new_kali_boot.img`) or the vendor image
(`planet/kali_boot.img`).
