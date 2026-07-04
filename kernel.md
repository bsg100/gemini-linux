# kernel.md — Kernel Configuration Decisions

Target: **Linux 6.6 LTS**. This document records kernel configuration and
boot-artifact decisions, per the CLAUDE.md documentation requirements. The
companion documents are [hardware.md](hardware.md) (what hardware needs what),
[blockers.md](blockers.md) (what is blocked), and [boot.md](boot.md) (what
actually happened on hardware).

---

## Serial Console (RESOLVED 2026-06-10)

The single most boot-critical configuration. Previously contradictory across
documents (ttyMT0 vs ttyMT3); now resolved with three independent sources.

| Item | Value | Source |
|------|-------|--------|
| Physical UART | UART0 @ `0x11002000` | Vendor DTB `apuart0@11002000`; mainline `mt6797.dtsi` `uart0: serial@11002000` |
| Vendor console name | `ttyMT0` | Vendor DTB `chosen/bootargs`: `console=tty0 console=ttyMT0,921600n1 root=/dev/ram initrd=0x44000000,0x4B434E loglevel=8` |
| Mainline console name | `ttyS0` (8250_mtk) | `serial0 = &uart0` alias in board DTS |
| Baud | 921600 | Vendor DTB bootargs |
| UART input clock | 26 MHz | Vendor DTB `clock-frequency = <0x18cba80>` = 26,000,000 |
| RX pin | GPIO97, aux function 1 = URXD0 | MT6797 spec Table 2-7 p.64; vendor DTB `uart0_rx_set@gpio97` |
| TX pin | GPIO98, aux function 1 = UTXD0 | MT6797 spec Table 2-7 p.64; vendor DTB `uart0_tx_set@gpio98` |

**The ttyMT3 red herring:** the known-good 2019 kernel's built-in
`CONFIG_CMDLINE` says `console=ttyMT3,921600n1`, which misled earlier analysis
(`archive/progress2.md`). That kernel has `CONFIG_CMDLINE_FROM_BOOTLOADER=y`
with EXTEND/FORCE unset — the built-in cmdline is a fallback that is **never
used**, because LK always supplies the DTB bootargs (ttyMT0). Extracted config:
[docs/vendor-dtb/kali_known_good_kernel.config](docs/vendor-dtb/kali_known_good_kernel.config).

Note that mainline `mt6797.dtsi`'s default `uart0_pins_a` muxes GPIO234/235 —
**wrong for the Gemini**. The board DTS overrides with GPIO97/98
(`uart0_gemini_pins`).

## Physical console access — UART over USB-C (documented 2026-06-12)

No mainboard soldering is required. The MediaTek preloader muxes UART0 onto
the USB 2.0 data lines of the **left** USB-C port (the one next to the
Esc/power button) when it detects VBUS with no USB host enumeration.

| UART signal | USB wire | USB-C pin | Standard USB-A wire colour | FTDI side |
|-------------|----------|-----------|---------------------------|-----------|
| Gemini TX (console out) | Data+ | A6/B6 | Green | RX |
| Gemini RX (console in) | Data− | A7/B7 | White | TX |
| VBUS 5 V — **required for cable detect** | VBUS | A4/B4/A9/B9 | Red | VCC (5 V) |
| GND | GND | A1/B1/A12/B12 | Black | GND |

- Data lines run at **3.3 V** in this mode (USB levels, not the 1.8 V of the
  raw SoC pads). Use a 3.3 V-signal FTDI cable (e.g. TTL-232R-3V3). Never a
  5 V-signal variant. If your adapter has a selectable I/O-voltage jumper
  (1.8/3.3/5 V), it must be set to **3.3 V** for this USB-C mux path — 1.8 V
  is the wrong setting here even though it matches the SoC's native UART pad
  voltage, because this path rides on standard USB D+/D− logic levels, not
  the raw pads.
- Without 5 V on VBUS the preloader never switches the mux and no output
  appears.
- Cable recipe (no fine-pitch work): USB-C–to–A adapter + a sacrificial
  **4-wire** USB-A cable (2-wire charge cables won't work), cut and stripped,
  joined to the FTDI's dupont ends.
- **Breakout-board variant (our rig, 2026-06-12):** a USB-C breakout board in
  the left port + 3.3 V FTDI cable. VBUS 5 V comes from the FTDI's red VCC
  wire — on a genuine TTL-232R-3V3 that wire is USB VBUS pass-through (5 V;
  only the signals are 3.3 V) — *verify ~5 V red-to-black with a multimeter
  first*. If the adapter's VCC is 3.3 V, feed VBUS from any external 5 V USB
  source instead, grounds tied together. The PMIC's VBUS detect triggers the
  mux; CC and SBU stay unconnected. Breakouts expose D+/D− twice (A6/A7 and
  B6/B7) — only one pair may reach the PHY per plug orientation, so if silent,
  flip the plug or use the other pair (or bridge A6→B6, A7→B7).
- Procedure: Gemini **off** → terminal open on the FTDI at 921600
  (`screen /dev/cu.usbserial-XXXX 921600`) → plug into the left USB-C port.
  Preloader output appears immediately, before pressing power.
- Community boot logs over this path show full vendor-kernel output
  (`console=ttyMT0,921600n1`), so the mux persists past the preloader through
  LK and kernel boot — at least while the kernel does not re-enable USB on
  that port. Phase 3 kernels build with USB disabled, so this is not a
  concern until USB enablement, at which point console access must be
  re-verified.

Sources (original blog now returns HTTP 500; archive link is the durable one):
- Omegamoon, "MediaTek USB-UART on Gemini-PDA" (2018-06-26):
  <https://web.archive.org/web/20210802183928/https://www.omegamoon.com/blog/index.php?entry=entry180626-210224>
- OESF thread with boot log: <https://www.oesf.org/forum/index.php?topic=35286.0>
- hivebriq, debug cable build (same scheme, 921600 baud confirmed):
  <https://hivebriqblog.wordpress.com/2018/07/25/debug-serial-cable-for-geminipda/>

## Required console-related config (Phase 3)

```
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_CONSOLE=y
CONFIG_SERIAL_8250_MT6577=y       # 8250_mtk.c — the symbol is MT6577, not MTK
                                  # (verified against v6.6 Kconfig 2026-06-10)
CONFIG_SERIAL_OF_PLATFORM=y
CONFIG_SERIAL_EARLYCON=y          # bare "earlycon" derives base from stdout-path
```

Plus maximum verbosity / diagnostics per CLAUDE.md Phase 3:

```
CONFIG_PRINTK_TIME=y
CONFIG_DEBUG_KERNEL=y
CONFIG_DEBUG_INFO=y (or DWARF5 variant)
CONFIG_MAGIC_SYSRQ=y
CONFIG_PANIC_TIMEOUT=-1           # do not auto-reboot on panic; keep UART output
```

## ramoops / pstore (post-mortem when the UART dies)

The board DTS places a `ramoops` node in the region Android/Kali already use
for pstore (`0x44410000`, 896 KB — vendor DTB `pstore-reserved-memory`), so a
panic that kills the UART still leaves a readable log, and the region is
dual-boot safe. Requires:

```
CONFIG_PSTORE=y
CONFIG_PSTORE_RAM=y
CONFIG_PSTORE_CONSOLE=y
CONFIG_PSTORE_PMSG=y
```

The known-good 3.18 kernel also had `CONFIG_PSTORE_CONSOLE=y` with size
0x10000 in the same region.

---

## Phase 3 Minimal Boot Artifact (definition)

The Phase 3 deliverable is the **smallest** artifact that can produce serial
output. Anything not needed for that is excluded so it cannot hang early boot.

| Component | Definition |
|-----------|------------|
| Kernel | `Image.gz` from 6.6 + `defconfig` + the console/pstore options above; all Gemini driver patches *not* required for serial boot excluded from the build (see patch policy below) |
| DTB | `mt6797-gemini-pda.dtb` from `dts/0001` (+ `dts/0006` — see dependency note) |
| Initramfs | Minimal busybox initramfs (~10 MB) — proves the kernel reaches userspace without committing to a rootfs (lesson from `archive/PROGRESS.md`) |
| Packaging | Android boot image: `cat Image.gz dtb > Image.gz-dtb`, repack with the Mer Boat Loader ramdisk layout below |
| Flash | `mtk w boot2 <image>` only (CLAUDE.md flashing rules) |

### Boot image packaging facts (from `planet/kali_boot.img` header)

| Field | Value |
|-------|-------|
| kernel load addr | `0x40080000` |
| tags addr | `0x44000000` |
| ramdisk addr | `0x45000000` |
| page size | 2048 |
| header cmdline | `bootopt=64S3,32N2,64N2 log_buf_len=4M` |
| ramdisk | Mer Boat Loader, 872,380 bytes |
| DTB | appended to `Image.gz` (offset 8,951,720 in the known-good kernel blob; 130,745 bytes) |

### Patch application policy for Phase 3

`build.sh patch` currently applies **all** patches. For Phase 3 builds, only
the DTS patches are required; the driver patches (gpio, regulator, usb, panel,
phy, drm) add code for hardware whose DTS nodes are `disabled` and **must not
be needed** for serial output. They may still be applied (the code is inert
without DT match) but a Phase 3 failure should first be re-tested with *only*
the DTS patches applied.

**Dependency note:** `dts/0001` (board) references labels `&dsi0`, `&dsi0_out`,
`&mipi_tx0` that are *created by* `dts/0006` (display nodes in `mt6797.dtsi`).
The two DTS patches must be applied together or `dts/0001` will not compile.
All display nodes are `status = "disabled"` in the board file; **dts/0006's MM
nodes must also be `disabled`** (open finding — see blockers.md B-4).

### Reserved memory

The board DTS reproduces the vendor DTB's fixed-address carve-outs (`no-map`):
ATF, ATF-ramdump, cache-dump, RAM console, minirdump, preloader, LK, spm-dummy
— plus the ramoops node. Sources cited inline in the DTS; full table in
[boot.md](boot.md). The vendor's dynamic carve-outs (ccci modem, consys,
scp_share, spm) are allocation requests by 3.18 drivers we do not run and are
deliberately omitted.

**Open question:** the vendor DTB memory node is a 1 GB placeholder that
preloader/LK fixes up to the real DRAM size at boot. Whether LK performs the
same fixup on our DTB (and honours our reserved-memory node) is unverified —
first boot will tell (`free -m` / `dmesg | grep Memory`).

---

## Kernel source / toolchain

- Source: Linux 6.6 LTS; patched at build time from `patches/v6.6/` (never
  patched in place).
- **Status (2026-06-10):** the build VM was deleted (blockers.md B-10) and
  must be rebuilt before any kernel build. The Mac-side checkout is restored
  at `/Volumes/extdata/github/linux-6.6` (shallow clone, tag v6.6) and is
  sufficient for patch validation (`git apply --check`) and DTS compilation
  (`clang -E -nostdinc -x assembler-with-cpp -undef -D__DTS__ -I include
  -I arch/arm64/boot/dts <dts> | dtc`) — all 10 patches and the board DTB
  were verified this way. Kernel/module builds still require the Linux VM.
- Toolchain: GCC 15.2.0 in the (former) VM — empirically confirmed working for
  both 6.6 and the 3.18 BSP (see CLAUDE.md "GCC Version Note").

## Config strategy

Phase 3 starts from `defconfig` (arm64) + the console/pstore options above +
`CONFIG_MTK_*` platform basics (clk/pinctrl/pwrap drivers are built-in via
`ARCH_MEDIATEK`). A `gemini_defconfig` fragment will be added to `scripts/`
once the Phase 3 option set stabilises against real boots. Decisions will be
recorded here per subsystem as they are made.

| Subsystem | Decision | Status |
|-----------|----------|--------|
| Console / earlycon | 8250_mtk on uart0, 921600, earlycon via stdout-path | Decided (above) |
| pstore | ramoops at vendor pstore region | Decided (above) |
| Sensors (STK3x1x etc.) | Excluded entirely from Phase 3 config | Decided — prior crash-loop root cause (hardware.md note 7) |
| CPUfreq / DVFS | Off; fixed voltage via `vproc_fixed` | Decided — RT5735 driver not hardware-verified |
| Display / DRM / GPU | Off in Phase 3 config | Decided — Phase 5 |
| eMMC (mtk-sd) | On from Phase 3 (harmless) but rootfs not required until Phase 4 | Decided |
| PMIC MT6351 | No mainline driver exists (blockers.md B-12) — all rails as `regulator-fixed` stubs; `CONFIG_REGULATOR_MT6351` does not exist, do not look for it | Decided 2026-06-10 |
| Console driver symbol | `CONFIG_SERIAL_8250_MT6577` (not "MTK" — verified against v6.6 Kconfig) | Decided 2026-06-10 |
