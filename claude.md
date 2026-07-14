# CLAUDE.md

## Project Objective

Port the Gemini PDA (MediaTek Helio X27) from its legacy Android/Linux 3.18 kernel to the newest practical Linux kernel while maximizing the use of upstream Linux support and minimizing reliance on vendor-specific code.

The primary objective is not feature completeness. The objective is to achieve a stable, maintainable, booting system on a modern Linux kernel. Hardware functionality will be enabled incrementally as dependencies are resolved.

The project should follow a hardware-enablement methodology similar to that used by Linux kernel bring-up teams. The focus is on identifying existing upstream support, minimizing custom code, and reducing risk through staged milestones.

---

# History
files in archive/ refelct previous attempts.  they could contain details of lessons learnt, but the approach may have changed so use it as a resource, but any assumptions drawn must be tested.

# Current Operating Decisions

**Driver-work freeze (2026-06-10, LIFTED 2026-07-04):** was in effect until
first serial output on hardware (Phase 3). That condition is now met — a
clean capture of the stock Android boot chain over the now-working FTDI rig
(see [boot.md](boot.md), B-1 in [blockers.md](blockers.md)). Driver work may
resume. This note is kept for history; see [blockers.md](blockers.md) for
rationale and the full blocker list.

**Console (resolved 2026-06-10):** debug console is UART0 @ 0x11002000
(vendor `ttyMT0`, mainline `ttyS0`), 921600 baud, RX=GPIO97 / TX=GPIO98.
Triple-sourced; see [kernel.md](kernel.md). The `ttyMT3` value in the
known-good kernel's CONFIG_CMDLINE is a never-used fallback — do not use it.

**Vendor DTB evidence:** the decompiled vendor device tree is committed at
`docs/vendor-dtb/gemini_kali_boot.dts` (extracted from `planet/kali_boot.img`),
with the known-good kernel config alongside. Do not cite `/tmp` paths in
project documents.

---

# Core Principles

1. Prefer upstream Linux drivers over vendor-specific drivers.
2. Reuse existing mainline Linux subsystems wherever possible.
3. Avoid large-scale vendor kernel porting unless absolutely necessary.
4. Disable, stub or defer unsupported hardware until required.
5. Prioritize bootability first, usability second, completeness last.
6. Document all findings, assumptions, decisions and blockers.
7. Every subsystem must have a documented rationale for its implementation approach.
8. Minimize technical debt and long-term maintenance burden.

---

# Project Phases

The full phase plan, including per-phase goals, success criteria and the
hardware.md table specification, lives in [plan.md](plan.md). Consult it when
working within a phase or planning the next one — do not duplicate its content
here.

| Phase | Scope | Status |
|-------|-------|--------|
| 1 | Hardware inventory (hardware.md) | Complete |
| 2 | Upstream analysis | Complete |
| 3 | Minimal kernel bring-up (serial console over FTDI) | **Complete 2026-07-04.** First full Linux 6.6 boot to userspace achieved (`Run /init as init process`) with diagnostic serial output throughout. See blockers.md B-2 (resolved) and boot.md's "SEVENTH RESULT" entry. |
| 4 | Storage and userspace | **Complete 2026-07-06.** eMMC works (`mediatek,mt2701-mmc` compat, boot.md FIFTEENTH RESULT). The 2019 Kali userspace booted first (B-7 resolved, boot.md SIXTEENTH RESULT) but has since been **replaced** by a fresh Debian 13 (trixie) rootfs built by `scripts/mkrootfs.sh`, flashed to p29, and confirmed live and reachable over SSH (build #53, root@10.15.19.82) — the vendor droid-hal-init/kpoc_charger read-only-remount issue does not apply to this rootfs, so that follow-up is moot. The `clk_ignore_unused` workaround is **resolved 2026-07-06** — root-caused to a `drivers/tty/serial/8250/8250_mtk.c` bug (never enables the UART's own `"baud"` clock, so late-boot clk cleanup cuts the console) and fixed upstream-style with `devm_clk_get_enabled()` (`patches/v6.6/serial/0001-...`). Fix **folded back into the production build 2026-07-06** (build #71, USB gadget re-added alongside the fix, `configs/gemini-cmdline.config` updated to drop `clk_ignore_unused`) and validated over SSH-over-USB (boot.md "BUILD #71"): clean boot to `graphical.target` in 19s, `g_ether` gadget working, no regression. Remaining carried-forward item: the SMP-secondary-CPU-hang workaround from Phase 3 (`maxcpus=1`) — **narrowed 2026-07-06** via PSCI `CPU_ON` instrumentation (boot.md "PSCI CPU_ON diagnostic"): CPUs 0–7 (both Cortex-A53 clusters) bring up cleanly; the hang is specifically at CPU8 (first Cortex-A72 core), root-caused to the same B-13 `mtk-scpsys` MT6797 domain-table bug blocking Phase 5 display. Workaround upgraded from `maxcpus=1` to `maxcpus=8` (all A53 cores, validated `logs/2026-07-06-77-maxcpus8/`, boot.md "BUILD — maxcpus=8") — an 8x improvement that doesn't require B-13 fixed first. Full 10-core SMP is now tracked under B-13, not as a separate item. |
| 5 | Display enablement | **COMPLETE 2026-07-12.** Readable landscape text console (fbcon, rotate:3, TER16x32 font) on the physical SSD2092 panel, clean boot, zero display errors. Root-cause chain, in order discovered: (1) B-13 cpu0 hang = mtk_dsi unmasking asserted level-low IRQ at probe (fixed drm/0008); (2) flip_done/vblank pipeline stall = OD_CFG clobbered by dither (fixed drm/0014); (3) panel dark/banding = THREE stacked defects — manufacturer init commands ≥0xB0 must be GENERIC packets not DCS (vendor DSI_set_cmdq_V2 behavior; folded into panel/0005), D-PHY LP/turnaround timing ~40% too short from mainline's formula (LK's TIMCON values, drm/0015), and mode timings must come from the vendor KERNEL video-mode LCM driver (HFP26/HSA4/HBP20, VFP76/VSA1/VBP43, 167333 kHz), not LK's command-mode leftovers (folded into panel/0005). Production build #145 (banner #126): zz-debug stripped, USB restored, clk_ignore_unused dropped. Remaining follow-ups (not blockers): command-mode per-frame push is NOT needed (video mode); ESD/recovery, brightness control (Phase 9). See boot.md builds #105–#145 and blockers.md B-13/B-17 closure notes. |
| 6 | Keyboard enablement | **Stage A COMPLETE 2026-07-12 — the keyboard types on the physical device** (build #164, baseline rebuild #168/banner #135). Three stacked root causes, in discovery order: (1) LK hands over with the AW9523B (i2c-3/0x5b, ID 0x23) held in reset — SHDN/GPIO58 low; driver `reset-gpios` deassert covers it; (2) the keyboard DT node carried a hidden second `status="disabled"` after the 53-key keymap — no platform device was ever created; (3) matrix polarity inverted — legacy `matrix_keypad` ignores GPIO_ACTIVE_LOW flags and needs the `gpio-activelow` property. Supporting work: local matrix_keypad polling-mode patch (`patches/v6.6/input/0001`, `poll-interval = <20>`) because v6.6 matrix_keypad is IRQ-only and pinctrl-mt6797 has no EINT (B-11); `console=tty0` added permanently (kernel log on panel). **B-18 RESOLVED 2026-07-13** (build #175/banner #140): the `aw9523b_pins` pinctrl state existed in the DTS but was never wired to the `aw9523b` node's `pinctrl-0`, leaving GPIO87/INT floating next to USB/mtu3 IRQ activity — one-line fix (`pinctrl-0 = <&aw9523b_pins>;`); `configs/gemini-usb.config` restored. Verified on hardware: keyboard + display + USB gadget SSH all working together for the first time. Fn layer also complete (2026-07-12, Fn=AltGr). Remaining: keymap niceties (Esc, media keys), Stage B = EINT in pinctrl-mt6797 (B-11; also unblocks RT9466 charger, FUSB301A, touchscreen). |
| 7 | Power management | **Researched 2026-07-12; charger identity CORRECTED 2026-07-14** (research.md §8): the charger is a **TI BQ25896 at i2c0 0x6b** (chip-ID verified live), NOT the RT9466@0x53 named in the original research (dead vendor config branch; nothing at 0x53 on any bus). Mainline driver = `bq25890_charger.c` (`ti,bq25896`), which also exposes the OTG boost as a `usb-otg-vbus` regulator (used by Phase 8/B-19 host mode; boost additionally gated by GPIO107 = `GPIO_OTG_DRVVBUS_PIN`, LK leaves it low; 40s I2C watchdog resets registers unless disabled). Check that driver's IRQ requirement vs B-11 (EINT gap) — same plan shape as before: fix B-11 first or patch IRQ-optional. Today the Linux boot path charges on BQ25896 hardware defaults only. Fuel gauge (MT6351) has no mainline support — charger-only + userspace voltage monitor is the Phase 7 minimum. |
| 8 | Networking | **B-20 RESOLVED 2026-07-14 (build #225): gadget enumerates when booting with the host attached — cable protocol retired.** Root cause: MT6797's U2 PHY has no hardware VBUS/session sensing; the vendor kernel software-forces U2PHYDTM1's session-valid FORCE bits [13:9] (driven by PMIC BC1.2 detection), and our earlier "good" boots only worked by inheriting LK's leftover forced state (DTM1=0x43E2E; host-attached boots got 0x26). Causally proven first by a live `devmem 0x1129086C 32 0x3E2E` flipping a broken boot from `not attached` to `configured`. Fix = `patches/v6.6/phy/0001` (DTS-gated `mediatek,force-b-session-valid` on u2port0, dts/0009). Verified 3/3 boot-with-host-attached + FTDI-protocol regression clean (blockers.md B-20 🟢, boot.md 2026-07-14). Vendor harvest also found TWO FUSB301 chips — the left-port CC controller is on **i2c1**; all prior B-19 host-mode work targeted the i2c0 (right-port) chip, so Stage C resumes with i2c1 Mode(0x02)=0x01 SOURCE + IDDIG (EINT 181) tracing. **B-18 RESOLVED 2026-07-13 (build #175/banner #140): USB gadget/SSH restored, working alongside the keyboard** — root cause was a dead `pinctrl-0` reference on the `aw9523b` DTS node (GPIO87/INT left floating next to USB/mtu3 IRQ activity); one-line fix, `configs/gemini-usb.config` restored, `configs/gemini-serial-console.config` retired to `.disabled`. Verified on hardware: boot, keyboard, gadget enumeration (`en12`, fixed MAC), ping, SSH all working together — see boot.md "BUILD #175" and blockers.md B-18 (now 🟢). This unblocks WiFi Stage 1 (USB host mode). History: **SSH-over-USB fast-track VERIFIED WORKING 2026-07-06:** build #53 (clean, no debug instrumentation) confirmed end-to-end on hardware — RNDIS/Ethernet gadget enumerates on the host, static IP + ping + `ssh root@10.15.19.82` all succeed (boot.md TWENTY-SIXTH RESULT). An apparent hang across builds #40–#52 was chased through clock/IPPC/PMIC forensics before being root-caused to the documented UART/USB console mux switching mid-boot, not a driver defect (B-15, resolved). Note the left USB-C port is shared with the UART console mux: serial and direct-to-Mac USB are mutually exclusive — verification requires a single-cable-swap protocol. WiFi (no mainline driver) remains not started. **Update 2026-07-08:** `g_ether` gadget now has a fixed MAC (`g_ether.dev_addr`/`host_addr` in `configs/gemini-cmdline.config`) instead of randomizing one every boot, so macOS no longer treats each boot as a new device — folded into build #178 (banner #63). **B-17 gadget/SSH sub-issue root-caused and CLOSED 2026-07-08:** a full SP Flash Tool scatter-file restore (done to reset the device to a clean baseline) wiped p29 (`linux` partition), replacing the Debian 13 rootfs with the factory Kali image — this, not any kernel/driver regression, was why builds #71/#159/#178 all appeared to have identical gadget failures afterward (confirmed via cross-host isolation on a Linux workstation, ruling out Mac-specific causes, before the rootfs was identified as the actual variable). **Current known-good baseline (2026-07-08):** `boot2` = build #71 kernel (banner #5, sha256 `c38e176bf18870a17636d66d22081c2e463384f9587c322bd4de2d8fe484d98e`), `linux` (p29) = freshly rebuilt `debian13-rootfs.img` (sha256 `a87d4780e7ccbbdba0a281b7e174c60f0eff181c1e470c5bdc8c5b3e8cd8c79e`) via `scripts/mkrootfs.sh` — SSH-over-USB reconfirmed working end-to-end (`logs/2026-07-09-185-freshrootfs-boot-check.log`, boot.md "FRESH DEBIAN 13 ROOTFS REFLASH"). Root password is `toor` (no key auth on a fresh rootfs); expect a one-time SSH host-key-changed warning after any rootfs reflash (`ssh-keygen -R 10.15.19.82` clears it) — this is expected, not a MITM. On the Mac, `en12` (RNDIS/Ethernet Gadget) may only self-assign an APIPA address after a fresh rootfs flash; add a static IP manually if so: `sudo ifconfig en12 alias 10.15.19.1 netmask 255.255.255.0`. The B-13 display sub-issue that also lives under B-17's heading (DRM atomic commit / `flip_done` timeout, panel dark) remains open. `CONFIG_PSTORE_RAM` also newly enabled (`configs/gemini-pstore.config`) so future crashes are diagnosable via `/sys/fs/pstore/` on the next boot. **WiFi plan adopted 2026-07-12 (user decision, WiFi only — no BT):** staged plan recorded in plan.md Phase 8 "WiFi plan" and research.md — Stage 0 fix B-18 (five-build single-variable diagnostic matrix, gate G0 = keyboard + gadget SSH in one build), Stage 1 USB dongle WiFi via mtu3 `dr_mode="host"` + xhci-mtk + upstream mt76 (recommended MT7921U, fallback MT7612U; gates G1a right-port enumeration, G1b SSH-over-WiFi — which frees the left port for serial permanently), Stage 2 time-boxed (~5 day) CONSYS feasibility spike (CONN power domain/clock/regulator bring-up + MCU firmware handshake, gates G2a/G2b) producing a go/no-go on porting the vendor gen2 stack (~150 KLOC; internal WiFi otherwise stays Phase 9). |
| 9 | Optional hardware | Not started |

Update the Status column as phases complete or open.

---

# Build Environment

All kernel builds are performed inside the QEMU arm64 VM. Do not attempt to cross-compile on macOS — the kernel host-tool build chain requires Linux (confirmed again 2026-06-10: macOS's case-insensitive filesystem produces phantom file collisions in the kernel tree).

## Machine Profiles (added 2026-07-08)

The user works on this project from two machines. **The build VM always lives
on the Mac** (`~/gemini-build/vm/gemini-build.qcow2`) regardless of which
machine the user is on — it is never relocated to the Linux workstation. The
user will state which machine they are currently on; adjust paths and
flashing capability accordingly.

**Profile: Mac (primary)**
- Repo: `/Volumes/extdata/github/gemini_linux`, kernel source:
  `/Volumes/extdata/github/linux-6.6`.
- Runs the build VM directly (`~/gemini-build/vm/start-vm.sh`), the FTDI
  serial monitor (`scripts/ftdi-monitor.py`), and `mtkclient`
  (`~/gemini-build/mtk-venv`) for flashing/GPT reads. This is the only
  machine with physical USB access to the Gemini hardware and the FTDI rig.
- All flash (`mtk w ...`) and capture (`ftdi-monitor.py`) commands are run by
  the user themselves, never executed directly by the assistant.

**Profile: Linux workstation (secondary, added 2026-07-08)**
- No direct hardware access (no FTDI rig, no USB connection to the Gemini,
  no mtkclient venv) and no local build VM — the VM stays on the Mac.
- Useful for: reading/editing patches, docs, and configs; `git apply --check`
  and DTS compilation (same tool invocations documented above work on any
  POSIX host with `dtc`/`clang` installed); research; drafting patches before
  they're rsynced to the Mac-hosted VM for an actual build.
- Cannot: start/reach the build VM, run `scripts/build.sh` or
  `scripts/build-pack.sh` end-to-end (they target the VM over SSH on
  `localhost:5522`, which only resolves from the Mac), flash partitions, or
  capture serial logs. Any of those steps must be handed back to the Mac
  session.
- If asked to do a full build-and-flash cycle while on this profile, say so
  explicitly rather than attempting it — coordinate with the Mac session
  (e.g., push patches, switch machines, or ask the user to run the Mac side).

> **VM rebuilt 2026-06-10** after the original was deleted in a disk cleanup.
> Now Debian 13 (was Kali) provisioned headlessly via cloud-init — rebuild any
> time with `~/gemini-build/vm/seed/` + the base image (see blockers.md B-10
> history). Patch validation and DTS compilation also work directly on macOS:
> `git apply --check` against `/Volumes/extdata/github/linux-6.6` and
> `clang -E -nostdinc -x assembler-with-cpp -undef -D__DTS__ -I include
> -I arch/arm64/boot/dts <dts>` piped to Homebrew `dtc`.

## Build VM

| Parameter | Value |
|-----------|-------|
| Image | `~/gemini-build/vm/gemini-build.qcow2` (10 GiB virtual, `discard=unmap`) |
| Base / rescue image | `~/gemini-build/vm/debian-13-generic-arm64.qcow2` + `seed.iso` (cloud-init: root key+password, build deps) |
| OS | Debian 13 arm64 (cloud image; was Kali pre-2026-06-10) |
| GCC | 14.2.0 (Debian 13) — full kernel build confirmed 2026-06-10. (GCC 15.2 note below predates the rebuild; both work for 6.6.) |
| SSH | `ssh -p 5522 root@localhost` — key auth (`~/.ssh/id_ed25519`) or password |
| Password | toor |
| Kernel source (in VM) | `~/linux-6.6/` (shallow clone, tag v6.6 — clone in-VM; do **not** rsync the Mac checkout, macOS case-folding corrupts colliding files like `xt_CONNMARK.h`) |
| Project source (in VM) | `~/gemini_linux/` (rsync, exclude `planet/` + `FlashToolLinux/`) |
| Host share | `~/gemini-build` ↔ `/mnt/host` (9p, tag `hostshare`); build outputs in `~/gemini-build/OUTPUT/` |
| Disk hygiene | run `fstrim /` in the VM after large deletions — with `discard=unmap` the host qcow2 shrinks |

**Start the VM (macOS):**
```bash
~/gemini-build/vm/start-vm.sh &
```

**Sync project and kernel changes from Mac to VM:**
```bash
# Project patches and scripts
rsync -a /Volumes/extdata/github/gemini_linux/ root@localhost:~/gemini_linux/ -e "ssh -p 5522"

# Kernel source (first time or after large changes)
rsync -a /Volumes/extdata/github/linux-6.6/ root@localhost:~/linux-6.6/ -e "ssh -p 5522"
```

If host tools were compiled on macOS before rsync (producing Mach-O binaries), run `make mrproper` inside the VM before building.

## Kernel Source

Target: **Linux 6.6 LTS**

- Mac: `/Volumes/extdata/github/linux-6.6`
- VM: `~/linux-6.6`
- Origin: shallow clone of `git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git` at tag `v6.6`

The kernel source is **not patched in place** for development work. All custom driver changes live as patch files in this project (see Patches below) and are applied on top of a clean kernel checkout before building.

**Vendor reference source (2026-07-06):** `/Volumes/extdata/github/gemini-android-kernel-3.18`
(`git remote`: `https://github.com/dguidipc/gemini-android-kernel-3.18.git`) is
a real, buildable Linux 3.18.41 kernel source tree for this exact device —
`dguidipc`'s Halium port (confirmed by the `Linux version 3.18.41+
(dguidi@nowhere)` banner matching the kernel embedded in
`/Volumes/extdata/scratch/debian`'s extracted boot image). This is the
primary cross-reference for vendor driver *source code* (scpsys/MTCMOS
sequencing, dispsys/DDP, SMI/M4U handling, CPU hotplug strategy, USB-C mux)
— use it instead of guessing from decompiled strings. Its board DTS
(`arch/arm64/boot/dts/aeon6797_6m_n.dts`) is a close but **not** bit-identical
match to our actual hardware's extracted DTB
(`docs/vendor-dtb/gemini_kali_boot.dts`) — e.g. it lacks the `fusb301a@25`
I2C node our real device has — so treat the real vendor-dtb extraction as the
DTS authority and this repo as the driver-source authority. See blockers.md
B-13 for the first concrete finding sourced from it (SMI larb IOMMU-bypass
gap).

## Patches

**Every patch must follow [`patches/STANDARDS.md`](patches/STANDARDS.md)** —
the mandatory rules (serial observability, error-path completeness,
hardware-value sourcing, interrupt safety, dual-boot handoff, DTS console/reserved-memory)
distilled from the driver review rubric in `code_review/`. A patch that fails a
MUST rule is not mergeable. Worked examples of each rule being broken are in
[`code_review/findings.md`](code_review/findings.md).

All driver ports and kernel modifications for the Gemini PDA are stored as patch files inside this project:

```
patches/
  README.md               — how to apply and add patches
  v6.6/                   — patches against Linux 6.6
    regulator/
      0001-regulator-fan53555-add-Richtek-RT5735-variant.patch
    dts/                  — (future) Gemini PDA device tree
    clk/                  — (future) clock additions
    ...
```

Patches are plain `git diff` output. Name them `NNNN-short-description.patch` using four-digit sequence numbers so they apply in the correct order.

**Apply all patches to a clean kernel tree (in VM):**
```bash
cd ~/linux-6.6
git checkout -- .          # ensure clean state
for p in $(find ~/gemini_linux/patches/v6.6 -name '*.patch' | sort); do
    git apply "$p"
done
```

**Add a new patch after making changes in the kernel tree (on Mac):**
```bash
cd /Volumes/extdata/github/linux-6.6
git diff HEAD -- path/to/changed/file.c \
    > /Volumes/extdata/github/gemini_linux/patches/v6.6/subsystem/NNNN-short-description.patch
```

Then rsync `patches/` to the VM.

## Build Script

`scripts/build.sh` is the single entry point for all kernel build operations. Run it inside the VM.

```bash
# Inside VM (ssh -p 5522 root@localhost)
cd ~/gemini_linux

./scripts/build.sh patch      # apply all patches to ~/linux-6.6
./scripts/build.sh config     # generate .config (defconfig for now)
./scripts/build.sh build      # build Image.gz + dtbs + modules
./scripts/build.sh module drivers/regulator/fan53555.o  # build one file
./scripts/build.sh clean      # make mrproper
```

Environment variables: `LINUX_SRC`, `PATCHES_DIR`, `JOBS` (see script header).

The build script will grow to include defconfig customisation and a `gemini_defconfig` target as Phase 3 progresses.

## Full-Cycle Script (Mac)

`scripts/build-pack.sh <NN> <short-desc> [--dtb-grep <pattern>]` runs an
entire build iteration from the Mac with the VM up: sync patches/configs,
reset + patch + build the kernel in the VM, pack `new_kali_boot.img`, create
the `logs/YYYY-MM-DD-NN-<desc>/` provenance dir (image, `.config`,
`System.map`, sha256), verify the packed kernel's banner and headless
invariants, and print the flash/capture commands. `build.sh` remains the
in-VM primitive it calls. The `/build-pack` skill wraps this plus the
documentation follow-ups (boot.md entry, blockers.md update).

**Banner = build number (since 2026-07-13):** build-pack passes the build
number as `BUILD_NN` → `KBUILD_BUILD_VERSION`, so the kernel banner `#NNN`
in `uname -a` now equals the build-pack `<NN>` exactly, and the verify step
fails the build if they differ. Builds ≤ #175 predate this — their banner
was the VM's own incrementing `.version` counter (e.g. build #175 = banner
#140); use the provenance dir or boot.md to map older numbers.

## GCC Version Note

GCC 15.2.0 in the VM is confirmed working with both Linux 6.6 LTS and the 3.18 BSP kernel (Kali/Gemian). The GCC ≤ 4.9 requirement mentioned in earlier project notes was not substantiated by testing.

**Empirical test (2026-06-07):** Built `~/gemini-kernel` (3.18.41, `kali_gemini_defconfig`) with `make ARCH=arm64 CROSS_COMPILE="" CC=gcc -k`. No implicit function declaration errors. No `-fno-common` failures. No language-standard compatibility errors. All build failures were path/include issues in MTK vendor drivers that require the Android build system to inject include paths — not GCC version issues. The core kernel and most drivers compiled cleanly.

**Conclusion:** GCC 15.2.0 can be used for both 3.18 BSP reference builds and Linux 6.6 development. No separate toolchain is required.

---

# Documentation Requirements

Maintain the following project documents:

## CLAUDE.md

Project strategy and operating instructions.

## plan.md

The phase-by-phase project plan: goals, success criteria and constraints for
each phase. Phase status is tracked in the table in CLAUDE.md.

## hardware.md

Hardware inventory and upstream support tracking.

## research.md

Research findings, references and technical notes.

## boot.md

Boot logs, observations and debugging notes.

## blockers.md

Known blockers, issues and risks.

## kernel.md

Kernel configuration decisions and implementation details.

## driver_ports.md

Porting plans and implementation details for every driver that is not available in mainline Linux. One entry per driver. Linked from hardware.md. See [driver_ports.md](driver_ports.md).

All significant findings must be documented.

Assume future contributors have no prior knowledge of the project.

---

# Decision Framework

For every subsystem, answer the following questions:

1. Does upstream support already exist?
2. Can existing upstream support be adapted?
3. Is the subsystem required for the current milestone?
4. Can the subsystem be disabled without blocking progress?
5. Is the engineering effort justified?
6. Does the solution reduce long-term maintenance burden?

Prefer the simplest solution that advances the project toward a modern, maintainable Linux kernel.

---

# Definition of Success

The project is considered successful when the Gemini PDA can boot a modern Linux kernel using primarily upstream components, with a maintainable architecture and minimal reliance on legacy vendor code. Feature completeness is secondary to maintainability, reproducibility and long-term viability.

# Flashing

## Rules

- **Never use `mtk wl` (write-from-directory) or any operation that rewrites the GPT/partition table.** When used, it wrote a partition table that conflicted with the device's actual layout, causing the official Gemini Flash Tool to report a scatter file mismatch and requiring a full firmware reinstall.
- **Only flash individual partition images** using targeted writes (e.g. `mtk w boot boot.img`). The existing partition layout is correct and sufficient — do not modify it.
- For kernel bring-up work, only `boot` (Android kernel) and `boot2` (Kali kernel) need to be replaced.
- The official Gemini Flash Tool (SP Flash Tool, x86 Linux) with the scatter file is the safe method for full reflash if recovery is needed.

## Flashing a Custom Kernel (Kali boot2 partition)

Build a new `boot.img` in the VM, then from macOS:

```bash
~/gemini-build/mtk-venv/bin/python3 ~/mtkclient/mtk.py w boot2 /path/to/new_kali_boot.img
```

Device must be in preloader mode (power on, connect USB — no button hold needed if preloader is intact).

**Note (2026-07-06):** use the `python3 ~/mtkclient/mtk.py` form, not the
`mtk-venv/bin/mtk` console-script — that entrypoint is broken in this
checkout (`ModuleNotFoundError: No module named 'mtkclient.mtk'`) because
`~/mtkclient` ships `mtk.py` as a top-level standalone script, not as a
`mtkclient/mtk.py` package submodule the installed entrypoint expects.

**Note (2026-07-07):** the venv lives at `~/gemini-build/mtk-venv`, not
`/tmp/mtk-venv` — macOS clears `/tmp` on every reboot, so a `/tmp`-based venv
silently disappears and every command referencing it fails with "no such
file or directory" until recreated. `~/gemini-build` already persists across
reboots (it holds the build VM), so the venv lives there instead. If it's
ever missing: `python3 -m venv ~/gemini-build/mtk-venv && ~/gemini-build/mtk-venv/bin/pip install -r ~/mtkclient/requirements.txt`.

## Recovery (Full Reflash)

If the device needs a full reflash, use the SP Flash Tool on an x86 Linux machine with:
- Scatter file: `Scatter_Gemini_x25_x27_A30GB_L26GB_Multi_Boot.txt`
- Images from: `Gemini_x25_x27_06052019/` and `kali/`

# Root Filesystem

**Resolved 2026-07-06.** The 2019 Kali `linux.img` userspace (systemd 239)
booted fully under Linux 6.6 first (blockers.md B-7, boot.md SIXTEENTH
RESULT) — but it was a dead 7-year-old rolling snapshot with vendor sabotage
units (droid-hal-init/kpoc_charger forced a read-only remount ~28s in). It has
since been **replaced** by a fresh Debian 13 (trixie) arm64 rootfs built by
`scripts/mkrootfs.sh` (run inside the build VM, native arm64): mmdebstrap
minbase + serial/ssh/debug tools, kernel modules installed from the current
build, packed as a sparse 4 GiB ext4 image and flashed to the `linux`
partition (p29, 25.8 GiB) with `mtk w linux <img>`. This is what's currently
running on the device — confirmed live 2026-07-06 via `ssh root@10.15.19.82`
(build #53): `/` is `/dev/mmcblk0p29` ext4 mounted `rw`, no droid-hal-init or
charger units present (they were specific to the 2019 image, not this
rootfs). After first boot, `resize2fs /dev/mmcblk0p29` grows it to the full
partition.

Key facts (verified from the vendor ramdisk, which our boot images keep
unchanged): its "Mer Boat Loader" `/init` mounts p29 with a bare busybox
`mount` (kernel autodetect, no fs-feature constraints beyond what the running
kernel supports) and then `exec switch_root /target /sbin/init
--log-target=kmsg`, preferring `/sbin/preinit` if executable (Debian ships
none). So rootfs swaps require no boot-chain changes at all.

**Recovery:** the 2019 image is kept at `planet/linux.img` — reflash with
`mtk w linux planet/linux.img` (5.5 GB, slow but proven).

# Change Requests

Any instruction received after initial project creation must be incorporated into CLAUDE.md, hardware.md, research.md or other project documentation as appropriate.

When updating project documentation:
1. Modify the relevant document.
2. Preserve existing content.
3. Maintain consistency across all project files.
4. Explain what was changed and why.

# Logging Requirements

Every boot attempt must be diagnosable after the fact. A serial log with no
record of what was flashed is worthless — the build, the flash and the capture
must be traceable to each other.

## Serial Capture

- Capture all boot attempts over FTDI with `scripts/ftdi-monitor.py --log <file>`.
  It records every byte timestamped in hex + ASCII, so wrong-baud garbage is
  still visible evidence (garbage = electrical activity; silence = wiring).
- Never rely on terminal scrollback. Always write a log file.
- Never use `--beacon` while wired to the Gemini — loopback testing only.

## Per-Attempt Provenance

Each boot attempt gets a raw capture under `logs/` named
`YYYY-MM-DD-NN-short-desc.log`, plus the following recorded alongside it or in
the boot.md entry:

- Kernel base tag (e.g. v6.6) and the `gemini_linux` repo commit, which
  together identify the exact patch set applied
- The `.config` used (copy it next to the log)
- DTB and boot.img identity (`sha256sum`)
- Partition flashed and the exact `mtk w` command
- Outcome: what was observed on serial, how far boot progressed

## boot.md

`boot.md` is the index and analysis layer: one entry per attempt linking the
raw log file, with observations, hypotheses and conclusions. Raw logs are
evidence and are never edited; analysis lives in boot.md.
