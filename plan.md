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

## WiFi plan (approved 2026-07-12, user decision: staged, WiFi only — no BT)

Research summary: the Gemini's internal WiFi is the **CONSYS block on the
MT6797 die** (AHB @0x18070000, MT6625-class core; vendor DTB
`consys@18070000` / `wifi@180f0000`), not a discrete chip. **No mainline
driver has ever existed**; the only implementation is the vendor gen2 WMT
stack (~150 KLOC WiFi alone, ~314 KLOC full combo) with firmware blobs plus
a userspace `wmt_launcher`. Nearest prior art, frank-w's BPI-Router-Linux
(same gen2 core, external-SDIO HIF), last worked on kernel 5.6. A USB WiFi
dongle by contrast is fully upstream (`mtu3` host mode + `xhci-mtk` +
`mt76`), but USB is currently disabled (B-18) and host mode is untested.

Staged plan, hardware-verifiable gates:

- **Stage 0 — B-18 root cause (prerequisite).** Desk research (vendor
  aw9523 power-up ordering, GPIO58/GPIO87 vs USB-C mux/FUSB301A pinctrl in
  the vendor DTB), then a one-variable-per-flash diagnostic matrix: (A) skip
  SHDN assertion, (B) INT/GPIO87 bias-pull-up, (C) cable hot-plug after
  boot, (D) deferred aw9523b probe, (E) FUSB301A read-only CC logging. All
  USB builds log dmesg to eMMC (serial dies at the B-15 mux). **Gate G0:**
  keyboard + working gadget SSH in one build; B-18 RESOLVED.
- **Stage 1 — USB host mode + dongle WiFi.** **1.1 built 2026-07-13, not
  yet flashed (build #142,** `logs/2026-07-13-220-stage1-usb-host-xhci/`
  **):** extended `patches/v6.6/dts/0009-...` with `dr_mode = "host"`, a
  `mediatek,mtk-xhci` child node (IRQ SPI 126) on the existing single
  dual-role mtu3 controller (confirmed from the vendor DTB — not a second
  PHY port), and a `usb1_vbus` `regulator-fixed` node driving VBUS via
  GPIO94 (decoded from the vendor DTB's `usb1_drvvbus_low/high` pinctrl
  states, since no discrete VBUS regulator exists in the vendor tree).
  `configs/gemini-usb.config` rewritten for `USB_MTU3_HOST` + `XHCI_MTK` +
  `USB_STORAGE`. Confirmed `xhci-mtk.c` already has a generic
  `"mediatek,mtk-xhci"` compatible fallback, so no driver-source change
  was needed. Host mode and gadget mode are Kconfig-mutually-exclusive, so
  **this build has no g_ether/SSH** — verification is panel-console/dmesg
  only. **Gate G1a (open):** flash `boot2`, USB stick in the right-hand
  port, confirm xhci-mtk probe + enumeration in dmesg. If xhci-mtk doesn't
  bind, add a one-line mt6797 compatible entry (mechanical fix, not a new
  driver). The `usb1@11200000` MUSB controller (no mainline driver) stays
  out of scope unless this path fails outright.
  Dongle: **MT7921U** recommended (Netgear A8000 class; fallback
  MT7612U/mt76x2u); firmware + wpa_supplicant or iwd into
  `scripts/mkrootfs.sh`. **Gate G1b:** scan/associate/DHCP/ping +
  SSH-over-WiFi — which frees the left port for serial permanently. Dual-role
  (`otg` + `usb-role-switch`) to restore gadget SSH alongside host mode is
  deferred until after G1a/G1b.
- **Stage 2 — CONSYS feasibility spike (time-boxed ~5 days / ~8 flashes;
  deliverable = go/no-go report in research.md, NOT working WiFi).** Add
  CONN power domain to mtk-scpsys mt6797 data (vendor CONN_PWR_CON =
  SPM+0x32C, PWR_STATUS BIT(1)); resolve the "conn" clock in clk-mt6797;
  vcn18/vcn28/vcn33_wifi regulators; minimal consys DTS node + 2MB no-map
  reserved memory; throwaway probe driver reading CONSYS chip-ID (**gate
  G2a**), then minimal MCU release + ROM firmware handshake using blobs
  from the Android vendor partition (**gate G2b**). GO to a full gen2 port
  only if both gates pass and the frank-w 5.6→6.6 delta looks mechanical;
  otherwise the dongle remains the WiFi path and CONSYS stays Phase 9.

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
