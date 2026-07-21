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
| 3 | Minimal kernel bring-up (serial console over FTDI) | **Complete 2026-07-04.** First full Linux 6.6 boot to userspace. Details: blockers.md B-2, boot.md "SEVENTH RESULT". |
| 4 | Storage and userspace | **Complete 2026-07-06.** eMMC working; Debian 13 rootfs live over SSH (build #53); `clk_ignore_unused` root-caused and fixed (serial/0001); SMP narrowed to `maxcpus=8` (A72 hang tracked under B-13). Details: blockers.md B-7/B-13, boot.md "BUILD #71", "PSCI CPU_ON diagnostic". |
| 5 | Display enablement | **Complete 2026-07-12.** Readable landscape console on the physical SSD2092 panel, zero display errors (build #145). Root causes: DSI IRQ unmask at cpu0 hang (B-13), OD_CFG/dither pipeline stall, panel init/timing (3 stacked defects). Details: blockers.md B-13/B-17, boot.md builds #105-#145, driver_ports.md panel entry. |
| 6 | Keyboard enablement | **Stage A complete 2026-07-13** (build #175/banner #140) - keyboard types alongside display + USB gadget SSH. Root causes: AW9523B held in reset, hidden `status="disabled"`, inverted matrix polarity, dead pinctrl-0 reference (B-18). Details: blockers.md B-18, driver_ports.md AW9523B entry. Stage B (EINT in pinctrl-mt6797, B-11) still open - also unblocks touchscreen. |
| 7 | Power management | **Charger identity corrected 2026-07-14** (research.md section 8): TI BQ25896 at i2c0 0x6b, not RT9466. Mainline `bq25890_charger.c` in use; see hardware.md Battery Charger row. Fuel gauge (MT6351) has no mainline support - charger-only + userspace voltage monitor remains the Phase 7 minimum. **Voltage monitor implemented and hardware-verified 2026-07-21** (build #269): `scripts/battery-monitor.sh` polls the charger's V_BAT ADC (`bq25890-charger-*` power_supply) and shuts down below a configurable floor when VBUS is absent; both the charging-gate and the low-battery trigger path confirmed on device (charger unplugged, V_BAT under threshold correctly logged via `logger`/journalctl), only the final `shutdown -h now` call itself not executed live; no systemd unit yet. |
| 8 | Networking | **Complete 2026-07-16 (WiFi parked).** B-22 resolved (build #255): simultaneous left-port charging + right-port USB ethernet; device internet-enabled via the right port (gateway/DNS/NTP, boot.md 2026-07-16). Internal WiFi (B-21) parked by user decision with the untested firmware-push build #262 ready to resume from — full history in blockers.md B-21/B-22. Right port upgraded to USB high-speed 2026-07-20 (build #269, dts/0019): ~43-64 Mbit/s with the SZNX adapter; RTL8156 incompatible (babbles + wedges port) — see boot.md "#269 OUTCOME REVISED". |
| 9 | Optional hardware | **Started 2026-07-16.** Touchscreen **WORKING 2026-07-19** (build #266): Solomon SSD2092 on i2c4/0x53, new polled driver `input/0002`; details boot.md builds #263–#266, driver_ports.md SSD2092 entry. Audio **WORKING 2026-07-19** (build #267, headphones): all-mainline MT6797 AFE + MT6351 codec, DTS dts/0018, routing in `scripts/audio-test.sh`; loudspeaker **parked 2026-07-20** (B-23 — vendor-exact enable replicated, still silent; harvest checklist for next Kali flash in blockers.md); capture still open — details boot.md builds #267/#268. msdc1 SD card **build #270 completed but non-functional as shipped** — msdc1 sat in permanent deferred-probe waiting on the MT6351 `vmc` regulator supply (same root cause also stalled WiFi/consys, needing `vcn28`). Root cause was **local file corruption**, not a missing patch: `patches/v6.6/regulator/0002-regulator-add-mt6351-vcn-regulators.patch` already had correct Kconfig/Makefile wiring committed in git, but the Mac-side on-disk working copy had been silently truncated to just the `.c`-file hunk before builds #270/#271 ran (see boot.md 2026-07-20 correction entry). Restored via `git checkout --`; rebuilt clean as **build #272 — not yet flash-verified**, see boot.md for exact flash/capture commands. LXQt desktop **WORKING 2026-07-19** (userspace only, no boot change — `startx` on demand): fbdev-rotated landscape X + touch; full findings in research.md section 9. HiDPI panel.conf gap **fixed 2026-07-20**: `.xinitrc` scaling was already baked into `mkrootfs.sh`, but `~/.config/lxqt/panel.conf` (panelSize=48/iconSize=36/mainmenu-first) was only a live edit, never staged — now added as `rootfs-files/panel.conf` and wired into `mkrootfs.sh`. Bluetooth blocked on parked CONSYS (B-21) — see kali-harvest-plan.md for the extensive 2026-07-20 harvest session (7 real vendor-kernel bugs found/fixed, session paused before a clean BT trace was captured). Remaining candidates: suspend/resume, sensors, GPS, camera, LTE. |

Update the Status column as phases complete or open, but keep entries to 2-4 sentences with a pointer into blockers.md/boot.md/driver_ports.md for the full history - those files are the source of truth, not this table.

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
