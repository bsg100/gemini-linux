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
| 4 | Storage and userspace | **In progress — current phase.** Blocked on B-7: no eMMC/MMC controller DT node exists yet (init panics in `switch_root` on `/dev/mmcblk0p29`). Also carries the SMP-secondary-CPU-hang and clk-gating workarounds from Phase 3 (`maxcpus=1`, `clk_ignore_unused`) as follow-up items to properly fix rather than work around. |
| 5 | Display enablement | Not started |
| 6 | Keyboard enablement | Not started |
| 7 | Power management | Not started |
| 8 | Networking | Not started |
| 9 | Optional hardware | Not started |

Update the Status column as phases complete or open.

---

# Build Environment

All kernel builds are performed inside the QEMU arm64 VM. Do not attempt to cross-compile on macOS — the kernel host-tool build chain requires Linux (confirmed again 2026-06-10: macOS's case-insensitive filesystem produces phantom file collisions in the kernel tree).

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
/tmp/mtk-venv/bin/mtk w boot2 /path/to/new_kali_boot.img
```

Device must be in preloader mode (power on, connect USB — no button hold needed if preloader is intact).

## Recovery (Full Reflash)

If the device needs a full reflash, use the SP Flash Tool on an x86 Linux machine with:
- Scatter file: `Scatter_Gemini_x25_x27_A30GB_L26GB_Multi_Boot.txt`
- Images from: `Gemini_x25_x27_06052019/` and `kali/`

# Open Questions

## Userspace / Root Filesystem Compatibility

The Planet Computers Kali `linux.img` (from `kali(2).zip`, dated Feb 2019) was built against and ships with kernel **3.18.41-kali+** (confirmed 2026-06-07 by inspecting `kali_boot.img`). When we boot a Linux 6.6 kernel against this filesystem, userspace binaries and init scripts that depend on 3.18-specific kernel interfaces, module names, or `/proc`/`/sys` layouts may fail.

**TODO:** Determine whether the existing `linux.img` userspace will boot cleanly under Linux 6.6, or whether a new root filesystem must be built. Considerations:

- glibc and systemd/init generally tolerate kernel upgrades well, but module loading, udev rules, and device node names may differ.
- If a new filesystem is needed, options include: debootstrap a fresh Kali arm64 rootfs, or adapt an existing arm64 Kali image.
- This does not block Phase 3 (serial console bring-up), but must be resolved before Phase 4 (userspace startup).

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
