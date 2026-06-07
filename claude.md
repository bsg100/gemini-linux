# CLAUDE.md

## Project Objective

Port the Gemini PDA (MediaTek Helio X27) from its legacy Android/Linux 3.18 kernel to the newest practical Linux kernel while maximizing the use of upstream Linux support and minimizing reliance on vendor-specific code.

The primary objective is not feature completeness. The objective is to achieve a stable, maintainable, booting system on a modern Linux kernel. Hardware functionality will be enabled incrementally as dependencies are resolved.

The project should follow a hardware-enablement methodology similar to that used by Linux kernel bring-up teams. The focus is on identifying existing upstream support, minimizing custom code, and reducing risk through staged milestones.

---

# History
files in archive/ refelct previous attempts.  they could contain details of lessons learnt, but the approach may have changed so use it as a resource, but any assumptions drawn must be tested.

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

# Phase 1: Hardware Inventory

The first task is to create hardware.md.

The purpose of this document is to inventory all device-specific hardware and determine the status of upstream Linux support.

Information sources include:

- Vendor kernel source tree
- Device tree files
- Kernel configuration files
- Board support files
- Boot logs
- Existing Gemini Linux projects
- Hardware teardowns
- Linux kernel source code
- Community documentation

The inventory must focus on actual hardware present in the Gemini PDA rather than generic MediaTek platform capabilities.

---

# hardware.md

Maintain the following table structure:

| Subsystem | Hardware / Chip | Function | Vendor Driver / Path | Device Tree Node | Mainline Status | Required Tier | Action | Notes / Evidence |
|------------|----------------|-----------|---------------------|------------------|-----------------|---------------|--------|------------------|

## Mainline Status Values

- Upstreamed
- Partial
- Not Upstreamed
- Unknown
- Not Required

## Required Tier Values

### Boot Critical

Required for kernel boot:

- CPU
- Memory
- Interrupt controller
- Clocks
- Regulators
- GPIO
- Pinctrl
- Storage
- UART serial console

### Usability Critical

Required for a useful Gemini PDA:

- Display
- Keyboard
- USB
- Battery monitoring
- Charging
- Wi-Fi

### Optional

Can be deferred:

- LTE modem
- Bluetooth
- Audio
- Camera
- Sensors
- GPS
- Suspend / Resume
- Miscellaneous peripherals

## Action Values

- Use Upstream
- Port Driver
- Stub / Disable
- Research Further
- Defer

---

# Phase 2: Upstream Analysis

For every hardware component:

1. Identify the vendor implementation.
2. Determine whether equivalent support exists in mainline Linux.
3. Identify all dependencies.
4. Record findings in hardware.md.
5. Determine the preferred implementation strategy.

The completed inventory should clearly identify:

- Hardware already supported upstream.
- Hardware partially supported upstream.
- Hardware requiring driver porting.
- Hardware that can be disabled.
- Hardware requiring further investigation.

No implementation work should begin until the inventory is substantially complete.

---

# Phase 3: Minimal Kernel Bring-Up

The objective of this phase is to establish a reliable kernel bring-up and debugging environment before attempting to enable user-facing hardware.

The target is not a usable system.

The target is a modern Linux kernel that boots and produces diagnostic output.

Use an FTDI serial adapter connected to the Gemini PDA debug UART to capture all boot output.

Configure the kernel with:

- Early console support
- Serial console logging
- Maximum boot verbosity
- Debug symbols
- Kernel diagnostics enabled

Create a repeatable workflow for:

- Building kernels
- Deploying kernels
- Capturing logs
- Reproducing failures

Only enable hardware required for a minimal boot:

- CPU
- Memory
- Interrupt controller
- Clocks
- Regulators
- GPIO / Pinctrl
- Storage
- UART serial console

All other hardware should be disabled, stubbed or deferred unless required for the current milestone.

The primary deliverable of this phase is a kernel that boots far enough to provide reliable serial output and enable root cause analysis.

Success criteria:

- Kernel image loads successfully
- Early console output visible over FTDI
- Boot progress observable
- Panic and crash information captured
- Boot process repeatable
- Development can continue without display, keyboard or networking

The FTDI serial console is the primary debugging interface until the system reaches a stable and repeatable boot state.

---

# Phase 4: Storage and Userspace

Enable boot from internal storage.

Goals:

- eMMC operational
- Stable root filesystem
- Reliable userspace startup
- Repeatable boot process

Success criteria:

- System boots from internal storage
- Root filesystem mounts successfully
- Userspace launches correctly

---

# Phase 5: Display Enablement

Enable display support using the simplest practical approach.

Priorities:

1. Existing upstream support
2. Minimal framebuffer output
3. DRM support

Goals:

- Visible local console
- Local debugging capability

Do not prioritize acceleration or advanced graphics features.

---

# Phase 6: Keyboard Enablement

The keyboard is one of the defining features of the Gemini PDA.

Goals:

- Full keyboard functionality
- Correct key mapping
- Stable operation

Keyboard support should be considered a high-priority usability milestone.

---

# Phase 7: Power Management

Enable:

- Battery monitoring
- Charging support
- Safe operation

Advanced power management and suspend functionality may be deferred until later phases.

Goals:

- Accurate battery reporting
- Reliable charging
- Thermal stability

---

# Phase 8: Networking

Enable networking using the simplest available path.

Priorities:

1. Existing upstream support
2. USB networking if necessary
3. Internal Wi-Fi

Goals:

- Reliable network connectivity
- Remote administration capability

---

# Phase 9: Optional Hardware

Evaluate and enable optional hardware as resources permit.

Potential candidates:

- Audio
- Bluetooth
- LTE modem
- Camera
- Sensors
- GPS
- Suspend / Resume

Optional hardware should never block progress toward earlier milestones.

---

# Build Environment

All kernel builds are performed inside the QEMU arm64 VM. Do not attempt to cross-compile on macOS — the kernel host-tool build chain requires Linux.

## Build VM

| Parameter | Value |
|-----------|-------|
| Image | `~/gemini-build/vm/gemini-build.qcow2` |
| Architecture | arm64 (Kali Linux) |
| GCC | 15.2.0 (Debian) — confirmed working with Linux 6.6 |
| Make | 4.4.1 |
| SSH | `ssh -p 5522 -o StrictHostKeyChecking=no root@localhost` |
| Password | toor |
| Kernel source (in VM) | `~/linux-6.6/` |
| Project source (in VM) | `~/gemini_linux/` |

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