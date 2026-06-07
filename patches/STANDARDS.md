# Patch Authoring Standard

Every driver patch in this project is reviewed against the rubric in
[`../code_review/opus_driver_review_prompt.md`](../code_review/opus_driver_review_prompt.md).
This document distils that rubric into the concrete rules a patch **must**
satisfy before it is added under `patches/`. It exists so the same defects found
in the first review round are not reintroduced.

A patch that violates a **MUST** is not mergeable. A patch that violates a
**SHOULD** requires a written justification in the patch's commit message.

Read this alongside [`README.md`](README.md) (mechanics) and
[`../code_review/findings.md`](../code_review/findings.md) (worked examples of
each rule being broken).

---

## 1. Serial-debug observability (the project's first-class constraint)

The only reliable debug channel during bring-up is the FTDI UART. A driver that
fails silently is undebuggable and is treated as broken regardless of whether
its logic is correct.

- **MUST** log probe entry with `dev_info`/`dev_dbg`, identifying the device
  (e.g. `"probing at 0x%02x"`).
- **MUST** precede *every* error return from `probe()` (and from panel
  `prepare`/`enable`, PHY `power_on`, etc.) with a `dev_err` that names what
  failed and includes the errno. Prefer `dev_err_probe()`. **A silent error
  return is a BLOCK.**
- **MUST** check the return value of every hardware access that can fail
  (`regmap_write`, `regmap_read`, `regulator_enable`, `clk_prepare_enable`,
  `mipi_dsi_dcs_*`, GPIO requests). An ignored return that hides a NAK is a
  silent failure.
- **MUST** log a positive success line at the end of `probe()` so "bound and
  working" is distinguishable from "never matched".
- **SHOULD** log each hardware state transition (clock enable/disable, regulator
  on/off, reset assert/deassert, IRQ request, PLL-lock wait) at `dev_dbg` so a
  hang at step N is distinguishable from a hang at step N+1.
- **SHOULD** log IRQ-handler entry and significant state changes at
  `dev_dbg`/`trace_printk`, **rate-limited** (`dev_dbg_ratelimited`) where the
  event can flood (CC toggling, key scan, VBLANK).
- **MUST** use a consistent, grep-able prefix (the `dev_*` device prefix is
  sufficient) so one driver's output can be isolated from the boot log.

## 2. Hardware values must cite a source

Assume the author has no datasheet unless one is cited. The first review round
found CPU-rail voltages, slew tables, PLL maths, register bit positions, and
init sequences all asserted without evidence.

- **MUST** cite a source in a comment for every register offset, bit position,
  default value, voltage, timing/delay, slew rate, and init-command payload —
  e.g. `/* datasheet §7.3 */` or `/* vendor aeon6797_6m_n.dts &i2c5 */`.
- **MUST** tag any value that is assumed or copied from a *similar* SoC/part
  (rather than confirmed for this hardware) with `/* TODO: verify on hardware */`
  or `FIXME`. Copying a register layout from another MediaTek SoC without
  evidence is the single most common defect.
- **MUST**, where the chip exposes a product/chip-ID register, read it in
  `probe()` and reject a mismatch with a `dev_err` — especially for anything
  driving a power rail. Never apply a voltage/slew table to a chip whose
  identity was not confirmed.
- **MUST NOT** invent a plausible-looking value to silence a reviewer. If a value
  is unknown, leave the feature `disabled`/stubbed and flag it, rather than
  guessing.

## 3. Error and teardown paths

- **MUST** free every resource on every exit path. Prefer `devm_*` so cleanup is
  automatic and ordered.
- **MUST** order resource acquisition so devm unwind is correct. In particular,
  for a gpiochip/irqchip add the gpiochip (which creates the IRQ domain) **before**
  requesting the line IRQ, so on unwind the IRQ is freed before the domain
  (otherwise an in-flight IRQ uses a freed domain — use-after-free on unbind).
- **MUST NOT** leave a partially-initialised device registered and visible to
  userspace after an error.
- **MUST** restore benign output/GPIO/reset state on error paths (e.g. a panel
  `prepare` failure must not leave reset asserted or a regulator enabled).
- **SHOULD** avoid non-`devm` getters (`usb_role_switch_get`, etc.) unless the
  `devm_` variant truly does not exist; a manual `put` racing a live IRQ is a
  use-after-put.

## 4. Interrupt safety

- **MUST** use a **threaded** IRQ handler for any device whose IRQ work sleeps —
  every I2C/SPI/regmap access sleeps, so an I2C expander/CC-controller IRQ must
  run in thread context (`devm_request_threaded_irq(..., NULL, handler,
  IRQF_ONESHOT, ...)`), never in hardirq.
- **MUST** track previous state for change/edge-style interrupts rather than
  re-deriving "pressed = currently low". Signal only lines that changed; report
  both assertion and de-assertion.
- **MUST NOT** use `IRQF_SHARED` unless the line is genuinely shared, and **MUST**
  return `IRQ_NONE` when nothing was pending for this device.
- **MUST** protect data shared with the handler, or access it with
  `READ_ONCE`/`WRITE_ONCE`, given the 10-core heterogeneous SoC.

## 5. Power management and dual-boot handoff

The device dual-boots Android and Debian. Neither OS owns the hardware
exclusively.

- **MUST** consider suspend/resume. For input/charger/CC devices, justify whether
  the IRQ should be a wake source (`device_init_wakeup` + wake IRQ) and document
  the decision.
- **MUST NOT** hold a clock, regulator, or wakelock enabled across suspend
  without justification.
- **MUST** leave clocks, regulators, PLLs, and shared controllers in a state the
  *other* OS tolerates on handoff — and say so in a comment. A controller that
  is reconfigured in `probe()` with no documented handoff state is a WARN at
  minimum.

## 6. Kernel API usage (Linux 6.6)

- **MUST** use 6.6 idioms: single-arg `probe(struct i2c_client *)`,
  `void`-returning `remove()`, `dev_err_probe()`, `devm_*`,
  `IRQCHIP_IMMUTABLE` irqchips, the generic PHY framework, and the upstream
  `mipi_dsi_dcs_write_seq` helper (do not hand-roll a same-named macro).
- **MUST NOT** use deprecated/fbdev idioms such as setting
  `backlight->props.power = FB_BLANK_*`; use `backlight_enable()` /
  `backlight_disable()`.
- **SHOULD** keep Kconfig/Makefile entries in the file's existing alphabetical
  order and provide a DT binding (`Documentation/devicetree/bindings/...`) whose
  example matches the real board.

## 7. Device tree

- **MUST** keep `chosen { bootargs }` / `stdout-path` correct for the FTDI debug
  UART and enable `earlycon` (bare `earlycon` derives the base from
  `stdout-path`, avoiding a hardcoded SoC address). A wrong/absent console is a
  silent dead boot — BLOCK.
- **MUST** confirm the board has the firmware `reserved-memory` carve-outs
  (ATF/TEE/SCP) so the kernel does not stomp them, and **SHOULD** add a
  ramoops/pstore region so a panic that kills the UART still leaves a
  post-mortem.
- **MUST** keep boot-only phases minimal: leave display/MM/optional blocks
  `status = "disabled"` until their milestone, so they cannot hang early boot.
- **MUST NOT** duplicate node names/labels (DTC rejects them).
- **MUST** cite every reg address, IRQ number + trigger flag, clock id, GPIO
  line, regulator voltage, and pinmux (rule 2 applies to DTS too).

## 8. Flashing safety (hard rule)

- **MUST NOT** call `mtk wl` or any operation that rewrites the GPT/partition
  table. Only targeted `mtk w <partition>` writes are permitted, and for
  kernel work only `boot`/`boot2`. This is a BLOCK with no exceptions
  (see [CLAUDE.md](../CLAUDE.md) → Flashing).

## 9. Shell scripts

- **MUST** use `set -euo pipefail` and quote variables.
- **MUST NOT** rely on `[ x -eq 0xNN ]` — `test` does not parse hex; use
  `$((0xNN))` or `(( ... ))`.
- **MUST** account for `set -e` interactions: a command whose non-zero exit you
  want to *inspect* must not be a bare statement under `set -e` (capture it, or
  use `if cmd; then`).
- **MUST** compare `i2cdetect` output as hex (it prints `5b`, not decimal `91`),
  and avoid grep patterns that match header/ruler rows (false PASS).
- **SHOULD** read live device state through gpiolib/`debugfs`/`power_supply`
  sysfs rather than poking raw `i2cget`/`i2cdetect` at a bus the kernel driver
  owns.
- **MUST** keep device addresses/bus numbers consistent with the matching DTS and
  driver patch.

---

## Pre-merge checklist

Copy into the patch's review note and confirm each item:

- [ ] Probe logs entry + success; every error return logs with errno.
- [ ] Every HW access return value checked; no silent NAK.
- [ ] Every register/voltage/timing/init value cites a source or is TODO-flagged.
- [ ] Chip-ID/PID read and verified where available.
- [ ] All resources `devm_`-managed; teardown order correct (gpiochip before IRQ).
- [ ] No partially-initialised device left registered on error.
- [ ] Threaded IRQ if work sleeps; change-tracking; no stray `IRQF_SHARED`.
- [ ] Suspend/resume + wake policy considered and documented.
- [ ] Dual-boot handoff state documented.
- [ ] 6.6 APIs only; no `FB_BLANK_*`, no hand-rolled `mipi_dsi_dcs_write_seq`.
- [ ] DTS: earlycon present, reserved-memory confirmed, optional blocks disabled,
      no duplicate nodes, values cited.
- [ ] No `mtk wl` / partition-table writes anywhere.
- [ ] Scripts: `set -euo pipefail`, hex-aware, addresses match DTS.
