# plan.md — Project Phases

The full phase-by-phase plan for the Gemini PDA Linux port. Current phase and
status live in the table in [CLAUDE.md](CLAUDE.md); consult this document when
working within a phase or planning the transition to the next one.

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
