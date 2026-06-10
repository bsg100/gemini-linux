# driver_ports.md — Driver Porting Reference

This document records the porting plan and implementation details for every driver that is not available in mainline Linux and cannot simply be replaced by an existing upstream driver. It is a working reference for contributors, not a design proposal — entries are updated as work progresses.

For the status of each subsystem in context see [hardware.md](hardware.md).

---

## Contents

- [Porting Methodology](#porting-methodology)
- [RT5735 Buck Regulator (VPROC / VGPU)](#rt5735-buck-regulator)
- [MT6797 Display Controller (MMSYS / DDP)](#mt6797-display-controller)
- [R63419 Display Panel](#r63419-panel)
- [AW9523B Keyboard Matrix](#aw9523b-keyboard)
- [FUSB301A USB-C CC Controller](#fusb301a-cc-controller)
- [MT6351 Fuel Gauge](#mt6351-fuel-gauge)
- [Novatek Touchscreen](#novatek-touchscreen)
- [MT6797 CONSYS WiFi/BT](#mt6797-consys-wifibt)

---

## Porting Methodology

This section defines a reusable approach for porting Android/MTK peripheral drivers to mainline Linux. It applies to all I2C/SPI device drivers in this project. Follow it for each new port to keep the codebase consistent and upstreamable.

### Principles

1. **Start from mainline, not vendor.** The vendor 3.18 driver is a source of register knowledge only. Never copy its structure, naming, or MTK-specific API calls. Write from scratch using mainline idioms.
2. **Use regmap.** All register access goes through `devm_regmap_init_i2c()` / `devm_regmap_init_spi()`. This gives free register caching, debug access via debugfs, and deferred I/O without any extra code.
3. **Use `devm_*` everywhere.** No manual cleanup in `.remove`. If a `devm_` variant exists, use it.
4. **Linear voltage ranges.** Use `REGULATOR_LINEAR_RANGE` / `regulator_desc.linear_ranges` rather than a hand-coded voltage lookup table.
5. **Standard DT bindings.** Every driver needs a YAML binding under `Documentation/devicetree/bindings/`. Follow `regulator/regulator.yaml` for regulators, `input/input.yaml` for input devices, etc.
6. **Chip ID verification in probe.** Always read the product ID register in `.probe` and fail with `-ENODEV` if the value is unexpected. This catches wiring errors early.
7. **No MTK dependencies.** The ported driver must compile and link without any `drivers/misc/mediatek/` headers or functions.

### I2C Regulator Port Checklist

This pattern applies to RT5735 and any other simple I2C buck/LDO regulator encountered in this project.

```
Step 1  Read vendor driver — extract register map, voltage formula, init sequence
Step 2  Find closest mainline analog (fan53555.c, rt5739.c, etc.)
Step 3  Decide: new variant in existing driver, or standalone file
Step 4  Write driver skeleton:
          - struct <chip>_priv  { struct regmap *regmap; struct device *dev; }
          - static const struct regmap_config <chip>_regmap_config
          - static const struct linear_range <chip>_voltage_range
          - static struct regulator_desc <chip>_rdesc
          - static int <chip>_probe(struct i2c_client *)
Step 5  Implement probe:
          a. devm_regmap_init_i2c()
          b. read PID register — return -ENODEV if unexpected
          c. chip_init() — write slew rate, mode, and safety registers
          d. devm_regulator_register()
Step 6  Write YAML DT binding
Step 7  Add Kconfig entry + Makefile line
Step 8  Test: insmod → regulator shows in /sys/class/regulator/
Step 9  Test: set_voltage() / get_voltage() via regulator_set_voltage()
Step 10 Submit upstream patch series
```

### Evaluating an Existing Driver as a Base

Before writing a new driver, check if the target chip can be added as a new `compatible` + variant entry to an existing mainline driver:

| Check | Pass condition |
|-------|---------------|
| VSEL register address | Same register offset as existing variant |
| VSEL bit mask | Same mask width |
| Voltage formula | Same min_uV + step_uV * n pattern |
| Enable/disable register | Same register and bit |
| Slew rate mechanism | Same register/field structure |
| I2C SMBus access width | Same (byte vs word) |

If all checks pass → add as new variant. If two or more fail → write standalone driver.

---

## RT5735 Buck Regulator

**Subsystem:** Regulators (external) — VPROC (CPU voltage) + VGPU  
**hardware.md Action:** Port Driver  
**Status:** Code complete — **compiled built-in in full kernel build 2026-06-10** (`REGULATOR_FAN53555=y`, GCC 14.2, rebuilt VM); DT binding written; not yet tested on hardware; register values remain verification-blocked (findings.md)  
**Priority:** Boot Critical — blocks DVFS; can defer with fixed-voltage workaround

### Background

The RT5735 is a Richtek dual-output synchronous step-down DC-DC converter used on the Gemini PDA to supply VPROC (CPU cluster voltages) and VGPU (Mali T860 core voltage). It sits on I2C bus 7 at address `0x1c` and is controlled directly by the MediaTek CPUFreq and GPU DVFS subsystems via the MTK vendor regulator framework. A second instance at `0x60` labelled `vgpu_buck` in the vendor DTS is likely the same chip on a different I2C address.

Without a working regulator driver, the kernel cannot adjust CPU or GPU voltage and must run at a fixed operating point. For initial bring-up this is acceptable (see workaround below), but a real driver is needed before CPUFreq can be enabled.

### Vendor Driver

Source: `drivers/misc/mediatek/power/mt6797/rt5735.c` + `rt5735.h`  
Repo: `github.com/gemian/gemini-linux-kernel-3.18` (also Re4son)

The vendor driver uses a proprietary `mtk_user_intf` regulator abstraction that is completely MTK-specific and not portable. It is useful only as a register-map reference.

### Register Map

| Register | Address | Description |
|----------|---------|-------------|
| `PROGVSEL1` | `0x10` | Voltage selector — DVS state 1 (standby / low-power) |
| `PROGVSEL0` | `0x11` | Voltage selector — DVS state 0 (active, default) |
| `PGOOD` | `0x12` | Power-good configuration |
| `TIME` | `0x13` | DVS-up slew rate (`bits[4:2]`, mask `0x1c`) |
| `COMMAND` | `0x14` | PWM/auto mode select (`bit[7]`, mask `0x80`) |
| `LIMCONF` | `0x16` | DVS-down slew rate (`bits[2:1]`, mask `0x06`) |
| `PID` | `0x03` | Product ID — read in probe to verify chip presence |

VSEL bit mask: `0x7f` (7 bits, `bits[6:0]`).

### Voltage Table

```
V(µV) = 600,000 + (regval × 6,250)

regval  0x00  →  600,000 µV  (0.600 V)
regval  0x40  →  1,000,000 µV  (1.000 V)  [typical CPU nominal]
regval  0x7f  →  1,393,750 µV  (1.394 V)
```

`n_voltages` = 128 (`0x7f` + 1)  
`min_uV` = 600,000  
`uV_step` = 6,250

### DVS Slew Rates

DVS-up rate is encoded in `TIME[4:2]` and DVS-down in `LIMCONF[2:1]`. The Gemini PDA DTS sets `rt,dvs_up = 6` and `rt,dvs_down = 1`.

**DVS-up rate table (`TIME[4:2]`):**

| Value | Rate |
|-------|------|
| 0 | 64 mV/µs |
| 1 | 16 mV/µs |
| 2 | 32 mV/µs |
| 3 | 8 mV/µs |
| 4 | 4 mV/µs |
| 5 | 4 mV/µs |
| 6 | 32 mV/µs ← Gemini setting |
| 7 | 8 mV/µs |

**DVS-down rate table (`LIMCONF[2:1]`):**

| Value | Rate |
|-------|------|
| 0 | 32 mV/µs |
| 1 | 4 mV/µs ← Gemini setting |
| 2 | 8 mV/µs |
| 3 | 16 mV/µs |

DVS is implemented entirely via I2C register writes. No GPIO pins are used for DVS. The GPIO access in the vendor driver is an I2C bus-recovery workaround (bit-banging SCL/SDA when the bus is stuck low) — this does not need to be ported; the mainline I2C recovery framework (`i2c_recover_bus()`) handles this.

### Mainline Driver Decision: fan53555.c variant

**Verdict: Add RT5735 as a new variant in `drivers/regulator/fan53555.c`.**

Rationale:

| Check | RT5735 | fan53555 existing variants | Pass? |
|-------|--------|---------------------------|-------|
| VSEL bit mask | `0x7f` (7-bit) | `0x7f` or `0x3f` depending on variant | Yes |
| Voltage formula | 600 mV + 6.25 mV × n | 600 mV + 6.25–12.5 mV × n | Yes |
| Enable/disable register | `COMMAND` `0x14` `bit[7]` | varies by variant, abstracted in setup fn | Yes |
| Ramp rate mechanism | register field, table-driven | `ramp_delay_table` + `ramp_reg` / `ramp_mask` | Yes |
| I2C access | SMBus byte read/write | SMBus byte read/write | Yes |
| VSEL register | `0x11` (PROGVSEL0) | variant-specific, set in setup fn | Yes |

The `fan53555.c` driver already dispatches to per-variant setup functions (`fan53555_voltages_setup_*`) that set `min_uV`, `uV_step`, `n_voltages`, `vsel_reg`, `vsel_mask`, `enable_reg`, `ramp_reg`, `ramp_mask`, and `ramp_delay_table`. Adding RT5735 is a new case in this dispatch with the values above.

Alternative `rt5739.c` was rejected: different VSEL register addresses (`0x00/0x01`) and different voltage range would require more invasive changes. `fan53555.c` is architecturally closer.

### Implementation Plan

#### Step 1 — Add chip type and DT compatible

In `fan53555.c`, add to the chip type enum:

```c
/* existing */
FAN53555_VENDOR_FAIRCHILD = 0,
...
/* new */
FAN53555_VENDOR_RICHTEK,
```

Add to the `of_device_id` table:

```c
{ .compatible = "richtek,rt5735", .data = (void *)FAN53555_VENDOR_RICHTEK },
```

#### Step 2 — Write the setup function

```c
static int fan53555_voltages_setup_richtek(struct fan53555_device_info *di)
{
    /* Verify chip by reading PID register 0x03 */
    if (regmap_read(di->regmap, 0x03, &di->chip_id))
        return -ENODEV;

    di->rdesc.linear_ranges     = NULL;  /* use min_uV / uV_step path */
    di->vsel_reg                = 0x11;  /* PROGVSEL0 — active voltage */
    di->vsel_mask               = 0x7f;
    di->enable_reg              = 0x14;  /* COMMAND */
    di->enable_mask             = BIT(7);
    di->rdesc.min_uV            = 600000;
    di->rdesc.uV_step           = 6250;
    di->rdesc.n_voltages        = 128;
    di->rdesc.ramp_reg          = 0x13;  /* TIME */
    di->rdesc.ramp_mask         = 0x1c;
    di->rdesc.ramp_delay_table  = rt5735_ramp_table;
    di->rdesc.n_ramp_values     = ARRAY_SIZE(rt5735_ramp_table);
    return 0;
}
```

Slew rate table (maps `ramp_mask` field value → µV/µs):

```c
static const unsigned int rt5735_ramp_table[] = {
    64000,  /* 0: 64 mV/µs */
    16000,  /* 1: 16 mV/µs */
    32000,  /* 2: 32 mV/µs */
     8000,  /* 3:  8 mV/µs */
     4000,  /* 4:  4 mV/µs */
     4000,  /* 5:  4 mV/µs */
    32000,  /* 6: 32 mV/µs */
     8000,  /* 7:  8 mV/µs */
};
```

#### Step 3 — Dispatch in probe

In `fan53555_regulator_probe()`, add a case:

```c
case FAN53555_VENDOR_RICHTEK:
    ret = fan53555_voltages_setup_richtek(di);
    break;
```

#### Step 4 — DT binding

File: `Documentation/devicetree/bindings/regulator/richtek,rt5735.yaml`

```yaml
# SPDX-License-Identifier: GPL-2.0-only OR BSD-2-Clause
%YAML 1.2
---
$id: http://devicetree.org/schemas/regulator/richtek,rt5735.yaml#
$schema: http://devicetree.org/meta-schemas/core.yaml#

title: Richtek RT5735 synchronous step-down DC-DC converter

maintainers:
  - <your name>

allOf:
  - $ref: regulator.yaml#

properties:
  compatible:
    const: richtek,rt5735

  reg:
    maxItems: 1

  richtek,dvs-up-microvolt-per-usec:
    description: DVS ramp-up slew rate in µV/µs
    $ref: /schemas/types.yaml#/definitions/uint32

  richtek,dvs-down-microvolt-per-usec:
    description: DVS ramp-down slew rate in µV/µs
    $ref: /schemas/types.yaml#/definitions/uint32

required:
  - compatible
  - reg

additionalProperties: false
```

#### Step 5 — Board DTS node (Gemini PDA)

Replace the vendor `rt,rt5735-regulator` node with:

```dts
vproc: rt5735@1c {
    compatible = "richtek,rt5735";
    reg = <0x1c>;
    regulator-name = "vproc";
    regulator-min-microvolt = <600000>;
    regulator-max-microvolt = <1393750>;
    richtek,dvs-up-microvolt-per-usec = <32000>;   /* dvs_up=6 */
    richtek,dvs-down-microvolt-per-usec = <4000>;  /* dvs_down=1 */
};
```

The `regulator-name = "vproc"` is required so `mediatek-cpufreq.c` can look it up by name via `regulator_get(dev, "vproc")`.

### Fixed-Voltage Boot Workaround

For Phase 3 bring-up, before the RT5735 driver is ready, add a fixed-voltage dummy regulator in the DTS to satisfy any driver that calls `regulator_get("vproc")`:

```dts
vproc: vproc-fixed {
    compatible = "regulator-fixed";
    regulator-name = "vproc";
    regulator-min-microvolt = <1000000>;
    regulator-max-microvolt = <1000000>;
    regulator-always-on;
    regulator-boot-on;
};
```

This keeps the CPU at a safe fixed 1.0 V, allows `mediatek-cpufreq.c` to load without error, and defers DVFS until the real driver is ready. Remove once the RT5735 driver is functional.

### Verification

Once the driver is loaded:

```bash
# Confirm regulator registered
ls /sys/class/regulator/ | grep vproc

# Read current voltage
cat /sys/class/regulator/regulator.X/microvolts

# Force a voltage change (as root, with regulator framework unlocked)
echo 1000000 > /sys/kernel/debug/regulator/vproc/voltage

# Confirm PID read succeeded (check dmesg)
dmesg | grep rt5735
```

### Open Questions

- Confirm the VGPU instance at I2C address `0x60` (labelled `vgpu_buck` in vendor DTS) — is this a second RT5735 or a different chip? Read its PID register `0x03` in probe to determine.
- Check whether the PROGVSEL1 (`0x10`) standby voltage register needs to be written during CPUSuspend/Resume. May require a `regulator_set_suspend_voltage()` implementation.
- Validate that `regulator-always-on` should be set for the VGPU instance to prevent the GPU power rail from being disabled when Panfrost idles.

---

## MT6797 Display Controller

**Subsystem:** Display Controller (MMSYS / DDP)  
**hardware.md Action:** Port Driver  
**Status:** Code complete — **compiled as modules in full kernel build 2026-06-10** (`DRM_MEDIATEK=m` + MT6797 DDP/DSI/MIPITX, GCC 14.2); not yet tested on hardware; MIPITX PLL values remain verification-blocked (findings.md)  
**Priority:** Usability Critical — Phase 5 (display bring-up)

### Background

The MediaTek DRM driver (`CONFIG_DRM_MEDIATEK`) supports multiple SoCs using a common DDP (Display Data Path) framework but MT6797 is absent from every component in Linux 6.6. The supported list in `mtk_drm_drv.c` is: mt2701, mt7623, mt2712, mt8167, mt8173, mt8183, mt8186, mt8188, mt8192, mt8195.

Despite the missing DRM support, the MT6797 MMSYS clock driver (`clk-mt6797-mm.c`) is present in mainline and covers all display component clocks (OVL, RDMA, DSI, COLOR, CCORR, AAL, GAMMA).

The vendor display stack (`drivers/misc/mediatek/video/mt6797/`) is a proprietary Android DDP driver tied to SurfaceFlinger. Do not port from it — use it only as a reference for register offsets and DDP topology.

### Files Requiring MT6797 Variants

Four kernel files require new MT6797-specific entries before the DRM driver can be used:

| File | Change Required |
|------|----------------|
| `drivers/gpu/drm/mediatek/mtk_drm_drv.c` | Add `mt6797_mtk_ddp_main[]` path array and `mt6797_mmsys_driver_data` struct; add `of_device_id` entry for `mediatek,mt6797-mmsys` |
| `drivers/phy/mediatek/phy-mtk-mipi-dsi.c` | Add MT6797 MIPITX variant to `mtk_mipi_tx_match[]` (currently covers mt2701, mt8173, mt8183 only) |
| `drivers/gpu/drm/mediatek/mtk_dsi.c` | Add MT6797 DSI controller variant to `mtk_dsi_of_match[]` (currently covers mt2701, mt8173, mt8183, mt8186) |
| `arch/arm64/boot/dts/mediatek/mt6797.dtsi` | Add display pipeline nodes: `disp_ovl0`, `disp_rdma0`, `dsi0`, `mipi_tx0`; `mt6797.dtsi` currently has only the `mmsys` syscon node |

### DDP Topology

The Gemini PDA display path follows the standard MT6797 single-plane path:

```
OVL0 → RDMA0 → COLOR → CCORR → AAL → GAMMA → OD → DITHER → DSC → DSI0
```

This is defined in the vendor DDP driver (`mt6797/ddp_path.c`). The mainline `mtk_ddp_main` array for mt8173 is the closest structural reference.

### MIPITX PHY

The MT6797 MIPITX PHY register layout must be extracted from the vendor driver at `drivers/misc/mediatek/video/mt6797/ddp_dsi.c` and `drivers/misc/mediatek/lcm/` PHY init sequences. The existing mainline `phy-mtk-mipi-dsi.c` uses per-SoC `mtk_mipi_tx_data` structs containing PLL configuration and calibration parameters — MT6797 needs its own struct.

### DTS Additions Required

The Gemini board DTS will need display pipeline nodes matching the upstream bindings. These should follow the pattern in `mt8173-evb.dts` adapted for MT6797 register addresses extracted from the vendor DTS ([`docs/vendor-dtb/gemini_kali_boot.dts`](docs/vendor-dtb/gemini_kali_boot.dts)).

### Reference Implementations

- Closest existing mainline SoC: MT8173 (single DSI, CMD/VDO mode support, similar DDP path)
- Vendor DDP topology: `drivers/misc/mediatek/video/mt6797/ddp_path.c` in 3.18 BSP
- Vendor MIPITX init: `drivers/misc/mediatek/video/mt6797/ddp_dsi.c`
- Mainline pattern reference: `arch/arm64/boot/dts/mediatek/mt8173-evb.dts`

### Implementation Notes

All planned changes are implemented and compile cleanly.

**Patch files:**
- `patches/v6.6/drm/0001-drm-mediatek-add-mt6797-mmsys-ddp-path.patch` — `mtk_drm_drv.c` MT6797 DDP path + mmsys_driver_data
- `patches/v6.6/drm/0002-drm-mediatek-add-mt6797-dsi-driver-data.patch` — `mtk_dsi.c` MT6797 DSI variant
- `patches/v6.6/phy/0003-phy-mediatek-wire-in-mt6797-mipitx.patch` — `phy-mtk-mipi-dsi.h/c` + Makefile wiring
- `patches/v6.6/phy/0004-phy-mediatek-add-mt6797-mipitx-phy-driver.patch` — new `phy-mtk-mipi-dsi-mt6797.c`
- `patches/v6.6/dts/0006-arm64-dts-mediatek-add-mt6797-display-nodes.patch` — `mt6797.dtsi` display pipeline nodes
- `scripts/test-display.sh` — display pipeline validation test

**DDP path implemented:** `OVL0 → OVL_2L0 → RDMA0 → COLOR → CCORR → AAL → GAMMA → OD → DITHER → DSI0`

**MIPITX register layout confirmed from `ddp_reg.h`:**
- PLL at 0x0050 (vs MT8183 at 0x002c)
- Band-gap at 0x0044 (vs MT8183 LANE_CON at 0x000c)
- PLL_PWR at 0x0068, PCW at 0x0058, PCW_CHG at 0x0060

**Display bias:** TPS65132 (I2C1/0x3E). Used via `regulator-fixed` in board DTS for Phase 5. Mainline `tps65132-regulator.c` available for full voltage control later.

### Open Questions

- Dual-DSI not yet implemented. The R63419 panel uses two DSI ports (port0 + port1) for 1440×2560 at full bandwidth. Single-DSI bring-up will work at reduced resolution or reduced lane rate. Full dual-DSI requires `mipi_tx1` node (0x1021e000) and second DSI controller — defer until single-DSI verified working.
- MIPITX PLL PCW calculation and timing values need hardware verification. Current implementation based on register-map analysis; actual PLL lock time and divider encoding may require tuning against real hardware.
- `mediatek,mt6797-disp-od` (over-drive) compatible string not verified against mainline DRM component enum — OD0 component may need to be added to `mtk_ddp_comp.h` if not already present.

---

## R63419 Panel

**Subsystem:** Display Panel  
**hardware.md Action:** Port Driver  
**Status:** Code complete — **compiled as module in full kernel build 2026-06-10** (`DRM_PANEL_RENESAS_R63419=m`); not yet tested on hardware  
**Priority:** Usability Critical — Phase 5 (after display controller)

### Background

The Gemini PDA display is a 5.99-inch Renesas R63419 WQHD (1440×2560) MIPI DSI CMD-mode panel ("Truly Phantom 2K"). The vendor driver lives in the MTK LCM framework (`drivers/misc/mediatek/lcm/r63419_wqhd_truly_phantom_2k_cmd/`) which is an Android-only abstraction that cannot be ported. A new DRM panel driver must be written.

The full panel initialization sequence is available in the vendor DTS (decompiled at [`docs/vendor-dtb/gemini_kali_boot.dts`](docs/vendor-dtb/gemini_kali_boot.dts)) and the LCM source. This is the primary source of truth for the port.

### Closest Mainline References

| Reference Driver | Relevance |
|-----------------|-----------|
| `drivers/gpu/drm/panel/panel-jdi-lt070me05000.c` | CMD-mode DSI panel, identical driver structure |
| `drivers/gpu/drm/panel/panel-jdi-fhd-r63452.c` | Renesas R634xx family (FHD variant of same controller family as R63419) |

The `panel-jdi-lt070me05000.c` is the structural template. It demonstrates:
- `struct jdi_panel` with `mipi_dsi_device`, regulators, reset GPIO, backlight
- `prepare()` / `enable()` / `disable()` / `unprepare()` ops
- MIPI DCS command sequences using `mipi_dsi_dcs_write()`
- Standard `drm_panel` registration

### Panel Parameters

| Parameter | Value |
|-----------|-------|
| Resolution | 1440 × 2560 (from DTS: 0x5a0 × 0xa00) |
| Interface | MIPI DSI CMD mode |
| Controller | Renesas R63419 |
| DSI lanes | 4 (typical for WQHD at this size) |
| Panel name in vendor | `r63419_wqhd_truly_phantom_2k_cmd_ok` |

### Implementation Plan

1. Extract init command sequence from `r63419_wqhd_truly_phantom_2k_cmd/` LCM source
2. Map LCM API calls to MIPI DCS equivalents (`mipi_dsi_generic_write`, `mipi_dsi_dcs_write`)
3. Write driver skeleton based on `panel-jdi-lt070me05000.c`
4. Identify panel power regulators and reset GPIO from vendor DTS
5. Write YAML DT binding under `Documentation/devicetree/bindings/display/panel/`
6. Add board DTS node in Gemini board file

### Power Sequence (Confirmed)

- `AVDD` (+5 V): TPS65132 output; GPIO60 enable (active-high), `regulator-fixed` in DTS
- `AVEE` (−5 V): TPS65132 output; GPIO251 enable (active-high), `regulator-fixed` in DTS
- Reset: GPIO180 (active-low): 1ms high → 10ms low → 10ms high
- TPS65132 at I2C1 (0x11008000), address 0x3E; vendor driver programs 0x0E to registers 0x00/0x01 for ±5V

### Panel Parameters (Confirmed from Vendor LCM Source)

| Parameter | Value | Source |
|-----------|-------|--------|
| Resolution | 1440×2560 | vendor DTS + LCM source |
| DSI mode | CMD mode | `LCM_DSI_CMD_MODE = 1` |
| DSI interface | Dual DSI (port0 + port1) | `LCM_INTERFACE_DSI_DUAL` |
| DSI lanes | 4 per port | `LCM_FOUR_LANE` |
| PLL clock | 423 MHz (CMD mode) | `params->dsi.PLL_CLOCK = 423` |
| Data format | RGB888 | `LCM_DSI_FORMAT_RGB888` |
| Physical size | 74.5 mm × 132.5 mm | `LCM_PHYSICAL_WIDTH/HEIGHT` |
| Lane swap | Yes (port0 and port1 swapped) | `lane_swap[]` table in vendor driver |
| Backlight | CABC via 0x51 register | `lcm_setbacklight_cmdq()` |

### Implementation Notes

Full DRM panel driver written from scratch. Init sequence (`lcm_initialization_setting[]`) extracted verbatim from vendor LCM source and translated to `mipi_dsi_dcs_write_buffer()` calls. Power sequence and panel parameters all confirmed from `r63419_wqhd_truly_phantom_2k_cmd_ok_mt6797.c`.

**Patch files:**
- `patches/v6.6/panel/0005-drm-panel-add-renesas-r63419-wqhd-panel.patch` — new `panel-renesas-r63419.c` + Kconfig + Makefile
- `patches/v6.6/dts/0001-arm64-dts-mediatek-add-gemini-pda-board.patch` — panel node in board DTS (disabled)
- `scripts/test-display.sh` — display + panel validation test

### Open Questions

- Dual-DSI: Panel requires port0 + port1 for full 1440×2560 bandwidth. The current driver is wired for single-DSI only (port0). Single-DSI will either reduce resolution, halve refresh rate, or fail to display — to be determined on hardware. Dual-DSI implementation deferred to after single-DSI verification.
- Lane swap: Vendor driver configures non-trivial lane swap on both ports (`MIPITX_PHY_LANE_*` table). This is a hardware board-level wiring decision and must be reproduced in the MIPITX PHY driver once hardware testing begins.
- UFOE: Vendor driver enables UFOE compression (`ufoe_enable = 1, lr_mode_en = 1`). Mainline MTK DRM driver does not support UFOE. For bring-up, UFOE is not enabled in the DRM driver; this may affect bandwidth but should not prevent basic framebuffer output.

---

## AW9523B Keyboard

**Subsystem:** Keyboard Matrix Controller  
**hardware.md Action:** Port Driver  
**Status:** Code complete — **compiled as module in full kernel build 2026-06-10** (`GPIO_AW9523B=m`; the earlier "compiles" claim predated any real build and hid a fabricated-API bug, since fixed — see findings.md "Full-build validation pass"); DT binding written; keyboard DTS node with full keymap added; not yet tested on hardware. **IRQ blocked by missing EINT support in mainline pinctrl-mt6797 (blockers.md B-11)** — `matrix-keypad` polling is the workaround.  
**Priority:** Usability Critical — Phase 6

### Background

The Gemini PDA physical QWERTY keyboard uses an AWINIC AW9523B GPIO expander / LED driver (I2C `0x5b`, address 0x5b = 0x58 base | AD0=AD1=1) on I2C bus 5 to scan the keyboard matrix. The vendor driver uses a proprietary `mediatek,aw9523_key` binding incompatible with mainline.

**CORRECTION from hardware.md:** AW9523B is not in mainline Linux 6.6. A prior project note claimed "AW9523B GPIO driver mainlined (~6.0)" — this was incorrect. No `aw9523` entries exist in `drivers/gpio/`, `drivers/mfd/`, or any other location in Linux 6.6.

The Gemian project ships a custom Linux input driver for the AW9523B keyboard, which is a Linux input driver (not an Android HAL). This is the best available porting reference.

### Two Porting Paths

#### Path A — AW9523B GPIO Driver + `matrix-keypad` (Recommended)

Write an AW9523B GPIO driver that integrates with standard Linux `gpiolib`, then use the existing `matrix_keypad.c` driver for keyboard scanning.

**Advantages:**
- Clean separation of concerns (GPIO driver vs. keyboard logic)
- `matrix_keypad.c` handles debounce, key maps, and input events natively
- AW9523B GPIO driver is independently upstreamable
- Key mapping lives entirely in DTS

**Structure:**
```
drivers/gpio/gpio-aw9523b.c        ← new: AW9523B gpiolib driver
drivers/input/keyboard/             ← existing: matrix_keypad.c (no changes)
```

**Device Tree (conceptual):**
```dts
aw9523_key: gpio@58 {
    compatible = "awinic,aw9523b";
    reg = <0x58>;
    gpio-controller;
    #gpio-cells = <2>;
    interrupt-controller;
    #interrupt-cells = <2>;
};

keyboard {
    compatible = "gpio-matrix-keypad";
    row-gpios = <&aw9523_key 0 0 &aw9523_key 1 0 ...>;
    col-gpios = <&aw9523_key 8 0 &aw9523_key 9 0 ...>;
    linux,keymap = <...Gemini key mappings...>;
    debounce-delay-ms = <5>;
    col-scan-delay-us = <2>;
};
```

**AW9523B GPIO Driver Checklist (follows Porting Methodology above):**

```
Step 1  Read vendor driver — extract register map, GPIO direction, read/write ops
Step 2  Use pca953x.c or pcf857x.c as structural reference
Step 3  Implement: struct aw9523b_chip, regmap_config, gpiochip_add_data
Step 4  Expose interrupt controller (per-pin IRQ for row scanning)
Step 5  Write YAML DT binding: Documentation/devicetree/bindings/gpio/awinic,aw9523b.yaml
Step 6  Kconfig + Makefile
Step 7  Test: gpiolib shows 16 GPIO lines; row/column state readable
Step 8  Wire up matrix-keypad in DTS, test keyboard
```

#### Path B — Port Gemian Custom Driver (Most Direct)

Port the Gemian keyboard driver directly. It is a Linux input driver targeting the Gemini PDA hardware specifically, not an Android HAL. It handles both AW9523B communication and keyboard matrix scanning in a single driver.

**Advantages:**
- Gemian has already validated key mappings and timing on physical hardware
- Shortest path to a working keyboard

**Disadvantages:**
- Single-purpose driver; less upstreamable
- Key mapping not in DTS (hardcoded in driver or separate header)
- Duplicates matrix scanning logic already in `matrix_keypad.c`

### AW9523B Register Map

| Register | Address | Description |
|----------|---------|-------------|
| `P0_INPUT` | `0x00` | Port 0 input register (GPIO 0–7 read) |
| `P1_INPUT` | `0x01` | Port 1 input register (GPIO 8–15 read) |
| `P0_OUTPUT` | `0x02` | Port 0 output register |
| `P1_OUTPUT` | `0x03` | Port 1 output register |
| `P0_CONFIG` | `0x04` | Port 0 direction (1=input, 0=output) |
| `P1_CONFIG` | `0x05` | Port 1 direction |
| `P0_INT` | `0x06` | Port 0 interrupt enable (0=enabled) |
| `P1_INT` | `0x07` | Port 1 interrupt enable |
| `ID` | `0x10` | Chip ID register (read in probe) |
| `CTL` | `0x11` | Control: ISEL (LED current), GPIO mode select |
| `P0_LED_MODE` | `0x12` | Port 0 LED/GPIO mode per pin |
| `P1_LED_MODE` | `0x13` | Port 1 LED/GPIO mode per pin |
| `SOFT_RESET` | `0x7F` | Write any value to reset chip |

### Recommendation

Start with **Path A** for the long-term goal of a maintainable, upstreamable driver. If Path A is blocked during bring-up, use the Gemian driver temporarily (Path B) to unblock keyboard testing, then replace with Path A before finalising.

### Implementation Notes

Path A chosen and implemented. The AW9523B GPIO driver (`drivers/gpio/gpio-aw9523b.c`) is written and compiles cleanly. The keyboard matrix is wired in DTS as a `gpio-matrix-keypad` child node.

**Confirmed hardware details (from vendor DTS aeon6797_6m_n.dts):**
- AW9523B on I2C bus 5 (0x1101c000), address 0x5b (AD0=1, AD1=1; base 0x58)
- SHDN = GPIO58 (active-low reset)
- INT  = GPIO87 (EINT10, active-low)
- Rows = Port 0 (GPIO 0..7, P0_0..P0_7)
- Cols = Port 1 (GPIO 8..14, P1_0..P1_6)

**Keymap:** 53 keys, extracted from vendor driver `aw9523_key.c`. Full keymap is in `patches/v6.6/dts/0001-arm64-dts-mediatek-add-gemini-pda-board.patch`.

**Patch files:**
- `patches/v6.6/gpio/0001-gpio-add-awinic-aw9523b-gpio-expander.patch`
- `patches/v6.6/dts/0001-arm64-dts-mediatek-add-gemini-pda-board.patch`
- `scripts/test-aw9523b.sh` — driver validation test
- `scripts/test-keyboard.sh` — keyboard matrix interactive test

### Open Questions

- Confirm i2c5 pin mux on Gemini hardware (mainline uses GPIO240/241 for i2c5; Gemini may use different pins — verify once serial console is available).
- Verify key mapping against physical keyboard layout on arrival of FTDI cable.

---

## FUSB301A CC Controller

**Subsystem:** USB-C CC Controller  
**hardware.md Action:** Port Driver  
**Status:** Code complete — **compiled as module in full kernel build 2026-06-10** (`TYPEC_FUSB301A=m`; the prior review's `devm_usb_role_switch_get` "fix" used a nonexistent API — replaced with `usb_role_switch_get` + devm action, see findings.md); DTS node added (disabled); role-decode FIXME still needs the datasheet; not yet tested on hardware  
**Priority:** Usability Critical for full Type-C; USB2 host mode works without it

### Background

The Gemini PDA uses an ON Semiconductor FUSB301A (I2C `0x25`) for USB Type-C CC logic. This chip is CC-only: it detects connector orientation and VBUS presence but does **not** implement Power Delivery negotiation.

**Important distinction:** The mainline FUSB302 driver (`drivers/usb/typec/tcpm/fusb302.c`) is a completely different chip — a full TCPM (USB Type-C Port Manager) with PD support. It is not adaptable for FUSB301A.

### Phase 3 Workaround

USB2 host mode works without the FUSB301A. No orientation detection, fixed polarity, 500 mA default. Sufficient for Phase 3 (FTDI serial console) and Phase 4 (storage).

Add a static USB host mode entry in the DTS:
```dts
usb_con: connector {
    compatible = "usb-a-connector";
    /* or usb-c-connector with power-role = "host" and fixed orientation */
};
```

### Minimal CC Driver (Phase 4+)

The FUSB301A exposes CC detection state via I2C registers. A minimal driver reads these and reports them to the kernel's USB role switch framework.

**Driver responsibilities (minimal):**
1. Probe: read device ID register, verify FUSB301A presence
2. Set up IRQ handler for CC state change
3. On CC event: read status register, determine orientation (CC1 or CC2) and VBUS state
4. Call `usb_role_switch_set_role()` or equivalent to signal USB controller

**Driver does NOT need to implement:**
- Power Delivery state machine
- PD message handling
- Alt-mode (DisplayPort, Thunderbolt)

### Key FUSB301A Registers (from ON Semi application note)

| Register | Address | Description |
|----------|---------|-------------|
| `DEVICE_ID` | `0x01` | Device ID — read in probe to verify |
| `CONTROL` | `0x02` | Mode control: DRP/UFP/DFP |
| `INTERRUPT` | `0x03` | Interrupt status |
| `STATUS` | `0x04` | CC attach status, orientation, VBUS |
| `TYPE` | `0x05` | Attached device type |
| `INT_MASK` | `0x08` | Interrupt mask |

### Implementation Notes

Driver written from scratch using mainline idioms (regmap, devm_*, usb_role_switch). Compiles cleanly against Linux 6.6.

**Confirmed hardware details:**
- Bus: I2C0 (0x11007000), address 0x25
- Confirmed from vendor DTS: aeon6797_6m_n.dts &i2c0 block, fusb301a@25

**Patch files:**
- `patches/v6.6/usb/0001-usb-typec-add-fusb301a-cc-controller.patch`
- DTS node in `patches/v6.6/dts/0001-arm64-dts-mediatek-add-gemini-pda-board.patch` (disabled)

### Open Questions

- FUSB301A IRQ GPIO: not found in vendor DTS. Driver operates poll-less (status read on connect) until IRQ GPIO is identified via hardware probing.
- Orientation switch GPIO: vendor DTS references `fusb301a_sw_en` and `fusb301a_sw_sel` GPIOs (lines 5213–5229 of vendor DTS tmp). These control an external USB switch for CC orientation — need GPIO numbers extracted and wired into DTS before orientation switching works.

---

## MT6351 Fuel Gauge

**Subsystem:** Fuel Gauge / Battery  
**hardware.md Action:** Research Further (defer to Port Driver in Phase 7)  
**Status:** Deferred — charger-only mode initially  
**Priority:** Usability Critical (safe operation); not required for boot

### Background

The MT6351 PMIC contains an integrated coulomb counter. In the Android vendor driver this is exposed via `drivers/misc/mediatek/battery/` — a custom battery meter tightly coupled to the Android power HAL and not portable.

**Mainline status:** No MT6351 fuel gauge or ADC driver exists in Linux 6.6. The `mt6360-adc.c` and `mt6370-adc.c` drivers cover different PMICs. `generic-adc-battery.c` requires an IIO ADC input that MT6351 does not expose in mainline.

### Phase 7 Strategy: Charger-Only + Userspace Monitor

For Phases 3–6, use charger-only mode:
1. Load `rt9467-charger.c` driver (covers RT9466).
2. Do not load any battery driver.
3. System reports `POWER_SUPPLY_STATUS_UNKNOWN` for battery.
4. The RT9466 charger hardware manages voltage and current limits safely.

**Risk:** Without a fuel gauge, the system cannot perform automatic low-battery shutdown. A userspace monitor script is required:

```bash
# Poll charger sysfs for VBUS presence and adapter current
# Trigger graceful shutdown when adapter removed + estimated Vbat < threshold
# (requires RT9466 ADC register access via sysfs or i2c-dev)
```

### Full Fuel Gauge Driver (Phase 7+)

A complete MT6351 fuel gauge requires:
1. **`mt6351-adc.c`** — expose MT6351 PMIC ADC channels via IIO (battery voltage, BATSNS current, temperature). Estimated ~200–500 LOC.
2. **IIO channel binding** — link ADC channel to `generic-adc-battery` or a dedicated MT6351 fuel gauge driver.
3. Alternatively, a standalone `mt6351-fg.c` that reads the coulomb counter directly.

The MT6360 ADC driver (`drivers/iio/adc/mt6360-adc.c`) is the closest structural reference.

### Open Questions

- Identify MT6351 ADC register offsets from vendor PMIC source (`drivers/misc/mediatek/pmic/`).
- Determine whether the MT6351 MFD driver in mainline can be extended to register an ADC sub-device, or whether a standalone driver is needed.
- Assess whether RT9466 registers expose a battery voltage ADC that could serve as a minimal voltage source for userspace.

---

## Novatek Touchscreen

**Subsystem:** Touchscreen  
**hardware.md Action:** Research Further  
**Status:** Blocked on hardware identification  
**Priority:** Usability Critical

### Background

The Gemini PDA uses an unknown Novatek NT touchscreen controller identified at runtime via `nvtpid` probe. The vendor DTS contains `novatek-mp-criteria-nvtpid` — a Novatek multi-point test criteria node that does not reveal the chip model.

The mainline driver `drivers/input/touchscreen/novatek-nvt-ts.c` covers only the NT11205. The NT36523 and NT36672A exist in mainline as DRM display panel drivers (`drivers/gpu/drm/panel/`) — these are MIPI DSI display controllers, not touchscreen ICs.

### Required Action Before Any Driver Work

**Hardware test required.** Boot the device and read the `nvtpid` value at I2C probe time (or extract it from Gemian boot logs). This determines the chip model and the correct driver path.

### Decision Tree

```
nvtpid == NT11205  →  Use mainline novatek-nvt-ts.c as-is
nvtpid == NT36xxx  →  Extend novatek-nvt-ts.c with new chip ID
nvtpid == other    →  Assess; likely extend novatek-nvt-ts.c or write standalone
```

### If Extension Needed

The mainline driver validates chip identity by reading from offset `0x78` (parameters block) and checking `NVT_TS_PARAMS_CHIP_ID` at byte offset `0x0e`. A different NT model would need:
- New chip ID constant
- Updated validation logic in `nvt_ts_identify_chip()` (if models share similar probe protocol)
- Potentially different touch data format in `nvt_ts_work_func()`

### Open Questions

- Extract `nvtpid` value from Gemian or Kali boot logs for the Gemini PDA.
- Confirm I2C address of the touchscreen controller (not recorded in current DTS analysis).
- Determine whether the NT model uses the same MIPI I2C protocol variant as NT11205 or a different one.

---

## MT6797 CONSYS WiFi/BT

**Subsystem:** Wi-Fi / Bluetooth / GPS  
**hardware.md Action:** Port Driver — deferred to Phase 9  
**Status:** Research complete (2026-06-08) — implementation not started  
**Priority:** Phase 9 (Optional Hardware); USB-Ethernet (`xhci-mtk` + USB dongle) is the Phase 8 networking solution

### Architecture

The MT6797X CONSYS is a **hard-IP block integrated into the SoC die**. It is not a discrete external chip. It contains a WiFi MAC/baseband, a BGF block (BT + GPS + FM + ANT), and their shared RF front-end.

```
MT6797X SoC
│
├── AP (ARM Cortex-A72/A53)
│   ├── AHB bus ──────────────────── WiFi MAC/baseband (memory-mapped registers)
│   ├── BTIF (on-chip UART) ─────── CONSYS control CPU + BT/GPS/FM mux (STP framing)
│   └── /dev/mtk_stp_wmt (ioctl) ─── wmt_launcher daemon (firmware + coexistence mgmt)
│
└── CONSYS block
    ├── WiFi MAC (AHB-mapped)
    ├── BT BGF (via BTIF/STP)
    ├── GPS (via BTIF/STP)
    ├── FM radio (via BTIF/STP)
    └── CONSYS control CPU (runs MCU firmware patches)
```

**Key architectural facts:**
- WiFi uses **AHB bus** (NOT SDIO). The gen2 driver registers as a `platform_driver` with `"mediatek,wifi"` compatible and uses AHB memory-mapped register access + PDMA DMA engine.
- BT/GPS/FM are multiplexed over a single BTIF channel using **STP** (Serial Transport Protocol, a proprietary MTK framing layer). STP is a kernel TTY line discipline (`N_MTKSTP`, ID=16).
- The `wmt_launcher` userspace daemon must run before any RF function is usable. It opens `/dev/mtk_stp_wmt` and loads MCU firmware patches into the CONSYS control CPU.

### Why Mainline Drivers Don't Apply

| Mainline driver | Why it doesn't help |
|----------------|---------------------|
| `mt76` | PCIe/USB chips only (MT7603/MT7615/MT7921). No AHB or integrated variants |
| `btmtksdio` | SDIO BT for MT7663/MT7668/MT7921/MT7902. MT6625 not in device table |
| `conninfra` | MT7921-era Filogic PCIe architecture. Completely different from WMT/STP stack |
| `hci_uart` | BTIF is not a standard TTY; STP framing required; WMT must be running first |
| `btmtkuart` | For external UART chips; does not match CONSYS BTIF architecture |

### Vendor Driver Structure

Source: `github.com/gemian/gemini-linux-kernel-3.18`  
Path: `drivers/misc/mediatek/connectivity/`

| Directory | Files | Function |
|-----------|-------|----------|
| `common/common_main/mt6797/` | `mtk_wcn_consys_hw.c` | CONSYS power-on/off: regulators, clocks (CCF), ioremap, GPIO, EMI reserved memory |
| `common/common_main/core/` | 15 .c files (~8–10 KLOC) | WMT core: chip ID probe, firmware patch download, coexistence config |
| `common/common_main/linux/` | 13 .c files (~6–8 KLOC) | Linux glue: chrdevs, STP-BTIF, debug procfs, OS abstraction layer |
| `common/common_detect/` | ~12 files (~3–4 KLOC) | Platform driver DT probe, external chip detection, GPIO setup |
| `wlan/gen2/mgmt/` | ~46 .c files (~30–40 KLOC) | Full 802.11 management stack: scan FSM, AIS FSM, auth, assoc, RSN/WPA, roaming, TDLS, P2P, HS2.0 |
| `wlan/gen2/common/` + `nic/` | ~15 .c files (~8–10 KLOC) | NIC layer, TX/RX, OID, P2P, BOW |
| `wlan/gen2/os/linux/` | ~14 .c files (~10–15 KLOC) | cfg80211 ops, cfg80211_ops table, vendor commands (Google OUI + QCA OUI) |
| `wlan/gen2/hif/ahb/mt6797/` | `ahb.c`, `ahb_pdma.c` | MT6797 AHB + PDMA DMA engine |
| `drv_bt/linux/hci_stp.c` | 1 file | BlueZ path: `hci_alloc_dev` + `hci_register_dev`, routes HCI via STP |
| `bt/stp_chrdev_bt.c` | 1 file | Bluedroid path: `/dev/stpbt` char device |
| `gps/` + `fmradio/` | ~15 files | GPS and FM char devices |

**Total size (gen2 path, excluding gen3):** ~136 .c files, ~75–103 KLOC

### Firmware Requirements

Loaded by `wmt_launcher` daemon from `/system/etc/firmware/`:
- MCU firmware patches: `ROMv3_patch_1_0_hdr.bin`, `ROMv3_patch_1_1_hdr.bin` (MT6797 IC ID 0x0279)
- WMT configuration: `WMT.cfg` / `WMT_SOC.cfg` (at `/system/vendor/firmware/`)
- WiFi firmware config: `wifi_fw.cfg` (at `/vendor/firmware/`)

**Full firmware file inventory must be confirmed by mounting `system.img` in the build VM:**
```bash
sudo mount -o loop,ro /path/to/planet/system.img /mnt/android
find /mnt/android/etc/firmware /mnt/android/vendor/firmware -type f | sort
```

Firmware blobs from the Android system partition must be placed in `/lib/firmware/` of the Linux rootfs for CONSYS to initialise.

### Community Reference

**Best available out-of-tree port:** `github.com/frank-w/BPI-Router-Linux`

The BPI-R2 (Banana Pi R2) uses an external SDIO MT6625 combo chip — the same WiFi/BT core as MT6797 CONSYS, but with an SDIO transport instead of AHB/BTIF. The `wlan_drv_gen2` WiFi driver core is shared; the HIF layer differs.

| Kernel | WiFi | BT | Status |
|--------|------|----|--------|
| 3.18 (vendor) | ✓ | ✓ | Vendor |
| 4.4–5.6 | ✓ | ✓ | frank-w BPI-R2 |
| 5.7–5.15 | partial | **broken** | BT core changes in 5.7; unfixed |
| **6.0+** | **broken** | **broken** | Unidentified kernel API changes; no active fix |

### Porting Strategy (Phase 9)

**Do NOT start from 3.18.** The frank-w BPI-Router-Linux tree already bridges 3.18→5.6. Start there.

1. **Identify the 5.7 BT breakage** — compare BT HCI registration path (`hci_stp.c` or `hci_alloc_dev` API) against `net/bluetooth/` changes between kernel 5.6 and 5.7. This is the first blocker.

2. **Identify the 6.0 WiFi breakage** — diff the frank-w 5.15 tree against 6.0 kernel changes in `net/wireless/` and `lib/` that would affect cfg80211 registration, SDIO subsystem, or the AHB DMA API.

3. **Port CONSYS HW init to 6.6 API** — `mtk_wcn_consys_hw.c` uses: `regulator_*`, `clk_*` (CCF), `devm_pinctrl_*`, `ioremap/readl/writel`, `request_irq`, `of_reserved_mem`. All are stable CCF/regulator framework calls; this component is the least changed.

4. **Port `wmt_launcher`** — The userspace daemon must be compiled for arm64 Linux (not Android libc). It uses `/dev/mtk_stp_wmt` ioctls. A musl libc / glibc build should be straightforward; the binary is available in the Android system partition.

5. **AHB HIF vs SDIO HIF** — The frank-w tree uses the SDIO HIF. For MT6797, the AHB HIF (`hif/ahb/mt6797/`) must be used instead. This is already present in the vendor gen2 driver.

6. **BT path** — Use `hci_stp.c` (BlueZ path) once CONSYS firmware is running. This hooks into standard `hci_core` and should be transparent to BlueZ userspace tools.

### Phase 8 Fallback

USB-Ethernet via USB-C port and `xhci-mtk` is the **definitive Phase 8 networking solution**. It requires no driver porting and works as soon as USB is functional. Options:
- USB Ethernet adapter (CDC-ECM/CDC-NCM class, supported in mainline)
- USB gadget `g_ether` mode (device acts as Ethernet adapter connected to host PC)

WiFi and Bluetooth porting is deferred until the device boots stably and all core milestones (Phases 3–7) are complete.

### Open Questions

- **Firmware inventory:** Mount `system.img` in VM to confirm exact firmware filenames, sizes, and whether NVRAM calibration data (`*.cfg`) is device-specific.
- **wmt_launcher binary:** Confirm whether the binary is present in `system.img` and whether it compiles cleanly with standard glibc for arm64 Linux.
- **6.0 WiFi breakage root cause:** Review Linux 6.0 changelogs for cfg80211, `net/wireless/`, and AHB DMA changes that could affect `wlan_drv_gen2`.
- **5.7 BT breakage root cause:** Review Linux 5.7 changelog for `net/bluetooth/` HCI registration changes affecting `hci_alloc_dev()` / `hci_register_dev()`.
- **MT6797 AHB DMA API:** Confirm whether the MT6797 AHB PDMA engine (`ahb_pdma.c`) uses the standard DMA engine API or a vendor-specific DMA API that needs porting.
