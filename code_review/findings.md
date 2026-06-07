# Driver Patch Review — Findings

Consolidated review of `patches/*` and `scripts/*` against the rubric in
[`opus_driver_review_prompt.md`](opus_driver_review_prompt.md). Reviewed
2026-06-07.

**Context correction (applies to every patch):** the review prompt describes a
"kernel 3.18 MTK vendor tree." The actual patches target **Linux 6.6 LTS**
(`patches/v6.6/`, per [CLAUDE.md](../CLAUDE.md)). All findings are assessed
against 6.6 APIs. The 3.18 BSP is used only as a *source* for register/GPIO
values, which is appropriate.

**Verification limitation:** the kernel tree is not checked out on the build
host (it lives in the VM), and no datasheets for the AW9523B, RT5735, FUSB301A,
or R63419 are in this repo. Findings that depend on register semantics,
voltages, PLL maths, or bit encodings are flagged as **verification-blocked** —
they cannot be resolved from this repository and must be confirmed against the
datasheet or in the VM before the affected patch is trusted on hardware.

Severities: **BLOCK** = would not merge. **WARN** = requires a response before
merge. **NOTE** = advisory.

The rules these findings imply for *future* patches are codified in
[`patches/STANDARDS.md`](../patches/STANDARDS.md).

---

## Status summary

| Patch / script | Verdict | Fixed in this pass? |
|---|---|---|
| `gpio/0001` aw9523b | BLOCK | Yes — logic, teardown, observability |
| `regulator/0001` fan53555 RT5735 | BLOCK (verification) | No — values need datasheet; documented |
| `usb/0001` fusb301a | BLOCK | Partly — observability/leak fixed; role logic flagged FIXME (needs datasheet) |
| `phy/0004` mt6797 mipitx | BLOCK (WIP) | No — PCW maths + lock register need datasheet; documented |
| `phy/0003` wire-in | Merge only with 0004 | n/a |
| `panel/0005` r63419 | BLOCK | Yes — ordering, backlight API, observability, reset path |
| `drm/0001` mmsys | WARN | No — DDP list needs sourcing; documented |
| `drm/0002` dsi-data | WARN | No — needs sourcing; documented |
| `dts/0001` board | BLOCK (won't compile) | Yes — duplicate node removed, earlycon added |
| `dts/0006` display nodes | WARN | Partly — recommend disabling MM block; documented |
| `scripts/*` | WARN (safe but buggy) | Yes — all script bugs fixed |
| `scripts/build.sh` | PASS | n/a |

No script performs any flashing or partition-table operation — the banned
`mtk wl` rule is fully respected.

---

## gpio/0001 — AWINIC AW9523B (BLOCK → fixed)

- **BLOCK — IRQ handler had no edge/state tracking.** `pending = ((p1<<8)|p0) ^ 0xFFFF`
  assumed "input low = pressed" and re-signalled every currently-low pin on
  every interrupt, producing spurious storms and never detecting key release
  (stuck keys). *Fixed:* the driver now keeps a `prev_state` shadow and signals
  only the lines that actually changed, so both press and release are reported
  and unchanged pins are ignored.
- **BLOCK — silent failure / observability.** Probe entry, success, and seven
  config register writes were unlogged and unchecked; a NAK produced a
  registered-but-broken gpiochip with zero serial output. *Fixed:* probe logs
  entry and success, every register write is checked via a helper and logged on
  failure, and the IRQ handler logs (rate-limited) which lines fired.
- **BLOCK — teardown order (use-after-free on unbind).** The threaded IRQ was
  requested before `devm_gpiochip_add_data`, so devm tore the gpiochip (and its
  irq domain) down first while an in-flight IRQ could still use it. *Fixed:* the
  gpiochip is added first, then the IRQ is requested, so on unwind the IRQ is
  freed before the domain.
- **BLOCK — `IRQF_SHARED` with always-`IRQ_HANDLED`.** On a level line this
  risks claiming others' interrupts and livelock. *Fixed:* dropped `IRQF_SHARED`
  and the handler now returns `IRQ_NONE` when nothing is pending.
- **WARN — `irq_mask` read in handler without a barrier.** *Fixed:* handler now
  reads it via `READ_ONCE`.
- **WARN — `reset-gpios` documented in the binding but never used.** *Fixed:*
  probe now acquires and deasserts the reset GPIO before talking to the chip.
- **WARN — verification-blocked values:** `AW9523B_ID_VALUE 0x23`, the CFG/INT
  inverted-sense polarity, and `CTL[4]` push-pull are asserted without datasheet
  citation. These remain TODO-flagged; the driver still checks the ID so a
  mismatch is now logged rather than silent.
- **NOTE — GPIO "8-14" vs "8-15".** P1 is a full 8-bit port (GPIO 8-15). *Fixed:*
  comment corrected.
- **Worst case:** unusable/stuck keyboard or an oops on unbind — recoverable via
  BROM/mtkclient reflash of `boot2`. No brick path.

## regulator/0001 — fan53555 RT5735 (BLOCK, verification-blocked — not fixed)

Structurally clean and slots into the 6.6 fan53555 variant framework correctly;
no memory/IRQ/error-path regressions, and the voltage arithmetic (600 mV +
127×6.25 mV = 1393.75 mV) checks out. **But it drives a CPU/core rail entirely
from uncited assumptions** and none of these can be resolved from this repo:

- **BLOCK — slew table provenance.** `rt5735_slew_rates[]` is non-monotonic with
  duplicate entries, lifted from a vendor header, not a datasheet.
- **BLOCK — VSEL0=active register polarity** depends on the board's VSEL pin
  strap; if wrong, voltage is programmed into the standby register.
- **WARN — `RT5735_PID` is `#define`d but never read**, so there is no runtime
  confirmation the chip is actually an RT5735 before a 600 mV/6.25 mV table is
  applied to the cores.
- **Action:** in the VM, confirm every register/voltage/slew value against the
  RT5735 datasheet, add a PID read + `dev_info`, and confirm the VSEL strap on
  the Gemini board. The DTS keeps `vproc_fixed` as the Phase-3 substitute, so
  this is not on the boot-critical path yet.
- **Worst case:** brownout/instability or (with over-volt) silicon stress on the
  cores. Still BROM-recoverable; max voltage is within typical core tolerance so
  practical risk is hang, not destruction.

## usb/0001 — FUSB301A (BLOCK → partly fixed)

- **BLOCK (verification-blocked) — role derived from VBUS, likely inverted.**
  Role should come from the TYPE register (0x05), not `VBUS_OK`. The correct
  TYPE-field decode needs the datasheet, so this is **not silently "fixed"**: the
  logic is now wrapped in a prominent `FIXME`, the TYPE register is read and
  logged, and orientation (`CC_ORIENT`) is read and logged so the gap is visible.
  Role detection must be rewritten against the datasheet in the VM.
- **BLOCK — silent register writes.** *Fixed:* MODES and INT_MASK writes are now
  checked and logged.
- **BLOCK — no PM/wake on a charger-path device.** *Fixed:* probe now calls
  `device_init_wakeup` and marks the IRQ as a wake source.
- **WARN — `usb_role_switch_get` not devm-managed → use-after-put on remove.**
  *Fixed:* switched to `devm_usb_role_switch_get`, removed the manual `put` and
  the now-unnecessary `remove` hook.
- **WARN — no initial state read.** *Fixed:* probe now reads STATUS once so a
  cable present at boot is handled.
- **BLOCK — register map unsourced.** STATUS bit positions remain
  verification-blocked and FIXME-flagged.
- **Worst case:** wrong CC role can misdirect VBUS / prevent charging — a flat,
  non-charging battery is a bad field case, though still BROM-recoverable.

## phy/0004 + phy/0003 — MT6797 MIPI-TX (BLOCK WIP, verification-blocked — not fixed)

- **BLOCK — PCW field packing is self-contradictory.** `RG_DSI_PLL_PCW =
  GENMASK(30,0)` makes the "field" span all of CON2; the integer/fraction
  comments disagree with the formula. The reference mt8183 driver uses a plain
  `writel` precisely because PCW spans the register.
- **BLOCK — silent no-lock success.** `pll_enable` waits a fixed delay and
  returns 0 without polling PLL lock; a failed lock looks like success with no
  serial output.
- **BLOCK — entire register map self-admittedly unverified** (the header says
  so). The driver is correctly isolated in its own file and honest about being
  WIP, but the values, the PLL-lock register bit, and the hardcoded 26 MHz ref
  all need the datasheet/VM. **Not fixed here** — fixing requires register
  knowledge this repo does not contain. phy/0003 is correct and must land only
  together with 0004 (hard link dependency).
- **Worst case:** blank/garbled display only; low blast radius, BROM-recoverable.

## panel/0005 — Renesas R63419 (BLOCK → fixed)

- **BLOCK — `set_display_on` issued before `exit_sleep_mode`.** *Fixed:* order
  corrected to sleep-out → wait → display-on.
- **BLOCK — obsolete `FB_BLANK_*` backlight idiom** (wrong for 6.6, likely won't
  build). *Fixed:* replaced with `backlight_enable()` / `backlight_disable()`.
- **BLOCK — pervasive silent failures.** The `dsi_dcs_write_seq` macro and the
  prepare/enable paths returned errno with no `dev_err`; on a no-display
  bring-up a silent panel failure is indistinguishable from a hang. *Fixed:* the
  macro now logs the failing command, and every regulator/DSI error path logs.
- **BLOCK — reset GPIO left asserted on the init-error path.** *Fixed:* the error
  path now drives reset low before returning.
- **WARN — verification-blocked:** the init sequence, reset/power-on delays,
  pixel clock (154980 kHz looks wrong for 1440×2560), and the HFP/HBP-vs-init
  comment contradiction are unverified transcriptions. These are flagged in-code
  as TODO; they do not block bring-up because the panel node is `disabled`.
- **NOTE — single-DSI bring-up limitation** is honestly documented.
- **Worst case:** blank screen; no damage path identified; BROM-recoverable.

## drm/0001 + drm/0002 — MT6797 DDP/DSI data (WARN — not fixed)

Mechanically correct, idiomatic 6.6, no runtime risk in the patches themselves
(static data + OF match). The concern is sourcing: the DDP main-path component
list and the `reg_cmdq_off=0x200` DSI config appear copied from mt8183/mt8173
with no citation, and a wrong DDP list can *hang* the pipeline rather than
merely blank it. **Action:** cross-check both against the MT6797 BSP `ddp_main`
topology and DSI register map, add a sourcing comment, then merge.

## dts/0001 — Gemini board (BLOCK, won't compile → fixed)

- **BLOCK — duplicate `panel_pins` node and `&pio` comment block.** The `&pio`
  section defined `panel_pins: panel { ... }` twice; DTC rejects the duplicate
  label/node. *Fixed:* deduplicated; `&pio` now has one each of
  `uart0_gemini_pins`, `aw9523b_pins`, `panel_pins`.
- **WARN — no earlycon / no `bootargs`.** Phase 3 depends on early serial output.
  *Fixed:* `chosen` now sets `bootargs = "earlycon console=ttyS0,921600n8"`.
  Bare `earlycon` derives the UART base from the `stdout-path` node, so no SoC
  address is hardcoded; confirm the 921600 baud against LK.
- **WARN — no `reserved-memory` / ramoops (verification-blocked).** A flat 4 GB
  memory node may let the kernel stomp ATF/TEE/SCP carve-outs, and there is no
  pstore region for post-mortem after a UART-killing panic. The carve-out
  addresses are not in this repo. *Fixed (documentation only):* a TODO block now
  documents the requirement at the memory node; the addresses must come from the
  vendor memory map.
- **WARN — UART0 pinmux GPIO97/98 is the single most boot-critical value** and is
  cited only by prose. Verify against the vendor `&uart0` pinctrl before
  flashing; a wrong pinmux = silent dead console.
- **WARN — `richtek,rt9467` at 0x53 is inconsistent** (RT9466 is 0x53; RT9467 is
  typically 0x5b) and there is no charger driver patch — dangling compatible.
  Reconcile chip identity with the test script.
- **NOTE — `vproc_fixed` 1.0 V** is uncited and referenced by no `cpu-supply`.
- **Worst case:** silent boot hang (recoverable by reflashing `boot2`).

## dts/0006 — MT6797 display nodes (WARN — documented)

The added MM block (OVL/RDMA/COLOR/.../DSI, larb0, smi_common, mutex) defaults
to `status="okay"` and pulls in MM clocks/power-domain at boot — during a
boot-only phase where display is meant to be deferred. **Recommendation:** set
these nodes `status="disabled"` until Phase 5, matching `dsi0`/`mipi_tx0`. All
GIC SPI numbers, reg addresses, and clock IDs are uncited and need sourcing
against the MT6797 BSP. (Not auto-fixed: these are context edits to the shared
`mt6797.dtsi` and should be verified in the VM.)

## scripts/* (WARN, safe but buggy → fixed)

- `test-aw9523b.sh`: `$((0x5b & 0x7f))` produced decimal 91 grepped against a hex
  `i2cdetect` map (never matches); raw `i2cget`/`i2cdetect` poked a live device
  the kernel owns. *Fixed:* hex-aware detection, reads via gpiolib/`debugfs`
  where possible, address aligned to the DTS (0x5b, bus 5).
- `test-charger.sh`: `[ ... -eq 0x80 ]` hex-in-`test` bug; `set -e` aborting on a
  failed `i2cget` before the friendly message; false-positive `i2cdetect` grep;
  RT9466/RT9467 identity confusion. *Fixed.*
- `test-keyboard.sh`: `set -e` aborted before the `evtest --query` exit check
  could run. *Fixed.*
- `test-display.sh`: gate/warn before the `/dev/fb0` random-write and fix the
  misleading "random noise" claim. *Fixed.*
- `build.sh`: PASS. Strict mode, `git apply --check` before applying, no
  destructive ops. Note: the `config` target is defconfig-only and does not yet
  enable the new driver symbols or guarantee earlycon — expected for the phase.
