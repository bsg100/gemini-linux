# research.md — Research Findings

This document records technical findings, references, and investigation notes that inform implementation decisions. It is the working scratchpad for the project.

---

## MT6797 CONSYS WiFi / Bluetooth / GPS — Deep Research

**Date:** 2026-06-08  
**Sources:** gemian/gemini-linux-kernel-3.18 (GitHub), Re4son/gemini-kali-linux-kernel-3.18 (GitHub), frank-w/BPI-Router-Linux (GitHub), system.img strings analysis, postmarketOS wiki, Linux kernel source

---

### CONSYS Architecture

The MT6797X CONSYS (Connectivity Subsystem) is a **hard-IP block integrated into the SoC die**, not a discrete chip. It contains:
- WiFi MAC/baseband (MT6625-equivalent core)
- Bluetooth (BGF block, MT6632-equivalent)
- GPS
- FM radio
- ANT+

**WiFi transport: AHB bus (memory-mapped), NOT SDIO.** The MT6797 CONSYS WiFi MAC is accessed via AHB registers from the AP. This is confirmed by the vendor driver: `wlan/gen2/hif/ahb/` directory (with `mt6797/ahb_pdma.c`) and the absence of any `sdio.c` in the gen2 HIF layer. The SDIO device ID tables in `hif_sdio.c` are for *external* combo chips (MT6618/6620/6628/6630/6632) only.

**Bluetooth transport: BTIF (on-chip UART).** BT, GPS, FM, and ANT packets are multiplexed over a single physical BTIF channel using the STP (Serial Transport Protocol) framing layer. The BTIF is an on-chip UART peripheral connecting the AP to the CONSYS block.

**Control path: `/dev/mtk_stp_wmt` (char device, major 190).** The WMT (Wireless Management Technology) layer is controlled by a userspace daemon that opens this device and uses ioctls to load firmware patches, configure coexistence, and power functions on/off.

---

### Vendor Driver Structure

Repository: `github.com/gemian/gemini-linux-kernel-3.18`  
Path: `drivers/misc/mediatek/connectivity/`

| Component | Location | Function | Transport |
|-----------|----------|----------|-----------|
| CONSYS HW init | `common/common_main/mt6797/mtk_wcn_consys_hw.c` | Power-on, clocks, resets, EMI | regulator + clk CCF + ioremap |
| WMT core | `common/common_main/core/wmt_*.c` (15 files) | Firmware loading, coexistence, power management | BTIF + /dev/mtk_stp_wmt |
| STP core | `common/common_main/core/stp_core.c` | Packet multiplexer over BTIF | BTIF (kernel ldisc N_MTKSTP=16) |
| BTIF/UART transport | `common/common_main/linux/stp_btif.c` | Physical BTIF channel | On-chip UART |
| WiFi gen2 driver | `wlan/gen2/` (~75 .c files) | 802.11 station + AP mode | AHB memory-mapped |
| WiFi gen2 HIF | `wlan/gen2/hif/ahb/mt6797/ahb_pdma.c` | DMA engine for AHB | MT6797 AHB PDMA |
| BT BlueZ driver | `drv_bt/linux/hci_stp.c` | Standard HCI (hci_alloc_dev + hci_register_dev) | STP → BTIF |
| BT Bluedroid driver | `bt/stp_chrdev_bt.c` | /dev/stpbt char device | STP → BTIF |
| GPS | `gps/stp_chrdev_gps.c` + `gps/gps_emi.c` | /dev/stpgps char device + EMI shared mem | STP → BTIF |

**Kconfig symbols:**
- `CONFIG_MTK_COMBO` — master enable
- `CONFIG_MTK_COMBO_CHIP_CONSYS_6797` — selects MT6797 SoC path
- `CONFIG_MTK_COMBO_WIFI` — WiFi gen2 driver
- `CONFIG_MTK_COMBO_BT` — Bluedroid BT char device
- `CONFIG_MTK_COMBO_BT_HCI` — BlueZ HCI driver
- `CONFIG_MTK_COMBO_GPS` — GPS char device

**WiFi driver:** Registers as `platform_driver`, compatible string `"mediatek,wifi"`. Uses `cfg80211` API (`wiphy_new`, `wiphy_register`, full `cfg80211_ops`). Does NOT use `mac80211` — implements its own 802.11 management stack (~46 files in `mgmt/`). WiFi init is gated through `wmt_chrdev_wifi.c` (`/dev/wmtWifi`): userspace writes `'1'` to power WiFi on via `mtk_wcn_wmt_func_on(WMTDRV_TYPE_WIFI)`.

**BT BlueZ driver (`hci_stp.c`):** Calls `hci_alloc_dev()` → `hci_register_dev()`. Does NOT use `hci_uart` or `btmtksdio`. Routes HCI frames through the WMT/STP infrastructure. Standard BlueZ toolstack works once CONSYS is powered and HCI registered.

**Driver size estimate (gen2 path, excluding gen3):** ~136 .c files, ~75–103 KLOC total.

---

### Firmware Loading

Firmware is loaded by the userspace `wmt_launcher` daemon:

```
Usage: wmt_launcher [-m mode] -p patchfolderpath [-d uartdevicenode] [-b baudrate] [-c uartflowcontrol]
```

- MCU patches: `/system/etc/firmware/` (confirmed from system.img string analysis)
- WMT config: `/system/vendor/firmware/WMT.cfg` or `WMT_SOC.cfg`
- WiFi firmware config: `/vendor/firmware/wifi_fw.cfg`
- ROM patches: `ROMv3_patch_1_0_hdr.bin`, `ROMv3_patch_1_1_hdr.bin` (MT6797 IC ID 0x0279)

**Full firmware inventory requires mounting system.img in the build VM:**
```bash
sudo mount -o loop,ro /path/to/system.img /mnt/android
find /mnt/android/etc/firmware /mnt/android/vendor/firmware -type f | sort
```
The actual WiFi/BT/GPS firmware file names and sizes must be confirmed via this VM procedure.

**Key implication:** Even with a fully working kernel driver, CONSYS will not start without:
1. The `wmt_launcher` binary (or a Linux port)
2. The firmware blobs from `/system/etc/firmware/`
3. Correct privilege / device node setup for `/dev/mtk_stp_wmt`

---

### Mainline Linux Status

| Path | Status | Notes |
|------|--------|-------|
| mt76 | Not applicable | PCIe/USB chips only (MT7603/MT7615/MT7921/MT76x2). No AHB/integrated SDIO variants |
| btmtksdio | Not applicable | Device table: MT7663, MT7668, MT7921, MT7902 only. MT6625 not listed |
| conninfra | Not applicable | MT7921-era Filogic SoC architecture. Completely different from MT6797 WMT/STP stack |
| hci_uart | Not usable standalone | BTIF is not a standard TTY; requires WMT/STP layer on top |
| cfg80211/mac80211 | Irrelevant | WiFi driver uses cfg80211 but owns its own 802.11 management stack |

No mainline driver path exists for MT6797 CONSYS. Zero mainline submissions have ever been made.

---

### Community State

| Project | Kernel | WiFi | BT | Notes |
|---------|--------|------|----|-------|
| Vendor (Planet/Kali/Gemian) | 3.18 | Working | Working | Full vendor stack + userspace daemon |
| frank-w BPI-R2 | 4.4–4.9 | Working | Working | BPI-R2 uses same MT6625 combo chip (external SDIO, different transport) |
| frank-w BPI-R2 | 5.4 | Working (AP mode) | Partial | ~7MB patch, AP-only mode more stable |
| frank-w BPI-R2 | 5.7–5.15 | WiFi partial | **Broken** | BT core changes in 5.7 broke HCI driver; unfixed |
| frank-w BPI-R2 | **6.0+** | **Broken** | **Broken** | "internal changes in linux which break mt6625 driver" |
| postmarketOS (planet-geminipda) | 3.18 (vendor pkg) | Not working | Not working | Uses vendor kernel; no mainline WiFi attempt |
| Jasu buildroot (gemini-pda-buildroot) | ~4.x mainline | Not attempted | Not attempted | "absolutely huge mega-driver"; serial console only |

**Key finding from frank-w:** The `wlan_drv_gen2` driver last worked on kernel **5.6**. It broke at **5.7** (BT) and **6.0** (WiFi) due to unidentified internal kernel API changes. No community member has fixed these breakages. The BPI-R2 uses an external SDIO MT6625 chip (different transport from MT6797 AHB), but the gen2 driver core is the same.

---

### SDIO Device IDs (External Combo Chips Only)

These IDs appear in `hif_sdio.c` / `stp_sdio.c` — they are for **external** chips, not MT6797 CONSYS:

| Chip | Vendor ID | Device ID |
|------|-----------|-----------|
| MT6618 | 0x037A | 0x6618 |
| MT6619 | 0x037A | 0x6619 |
| MT6620 | 0x037A | 0x6620 |
| MT6628 | 0x037A | 0x6628 |
| MT6630 | 0x037A | 0x6630 |
| MT6632 | 0x037A | 0x6632 / 0x6602 |

MT6797 CONSYS has **no SDIO device ID** — it is AHB memory-mapped.

---

### Porting Strategy Decision

Three possible approaches, in order of increasing effort:

**Option A — USB-Ethernet (Phase 8, recommended):**
- No driver porting required
- USB-C port with `xhci-mtk` + USB Ethernet adapter provides networking for Phase 8
- Avoids the entire CONSYS porting problem

**Option B — Port wlan_drv_gen2 to 6.6 (Phase 9, high effort):**
- Starting point: identify and fix the 5.7 BT breakage and 6.0 WiFi breakage in frank-w's tree
- Do NOT start from 3.18 → 6.6 directly
- Also requires porting `wmt_launcher` userspace daemon
- Firmware blobs must be extracted from system.img and placed in `/lib/firmware/`
- Estimated: 3–6 months with vendor documentation; unknown without

**Option C — Rework to mainline (Phase 9+, very high effort / probably infeasible):**
- Would require rewriting the 802.11 management as mac80211 firmware offload
- No firmware or open spec available
- Not recommended

**Recommendation:** Option A for Phase 8. Option B as a Phase 9 optional milestone after the system boots stably with USB-Ethernet.

### WiFi plan adopted (2026-07-12, user decision)

Staged plan recorded in plan.md Phase 8 ("WiFi plan"). Summary: Stage 0 =
B-18 root cause (prerequisite; five-build single-variable diagnostic
matrix); Stage 1 = Option A realized as **USB dongle WiFi** (mtu3
`dr_mode="host"` + xhci-mtk + mt76, recommended dongle MT7921U, fallback
MT7612U) with gates G1a (right-port enumeration) / G1b (SSH-over-WiFi);
Stage 2 = a **time-boxed CONSYS feasibility spike** (~5 days) that only
proves power-domain/clock/regulator bring-up (chip-ID readback, G2a) and
MCU firmware handshake (G2b), producing a go/no-go on Option B. WiFi only;
BT explicitly out of scope. Corrected measurement: the gen2 WiFi driver is
~150 KLOC incl. headers (whole combo ~314 KLOC), larger than the earlier
"~75–103 KLOC" estimate above.

### CONSYS Stage W0 harvest (2026-07-14 — B-19 parked, CONSYS path activated)

User decision 2026-07-14: B-19 (USB host) is parked; WiFi is now pursued
via CONSYS directly (SSH-over-WiFi would then give a debug channel
independent of the left port, making B-19 *easier* to research later).
Everything below is source-cited from the vendor tree
(`gemini-android-kernel-3.18/kernel-3.18`, cited `K/`) or measured live
over SSH on build #225.

**Live state at Linux handoff (measured on #225, devmem):** LK leaves
CONSYS completely untouched — `SPM_CONN_PWR_CON (0x10006280) = 0x0`
(in reset, unpowered), `SPM_PWR_STATUS (0x10006180) = 0x2A00005C` /
`2ND (0x10006184) = 0x2A00004C` (bit 1 CONN clear in both),
`INFRA_TOPAXI_PROT_EN (0x10001220) = 0x000104B8` (CONN bits 2/8 clear —
bus protection not asserted either). Our kernel owns the entire power-on
sequence from cold.

**MTCMOS CONN domain (K/drivers/misc/mediatek/base/power/mt6797/
mt_spm_mtcmos.c:1803 `spm_mtcmos_ctrl_connsys`):**
- **`SPM_CONN_PWR_CON = SPM_BASE + 0x32C`** — MEASURED LIVE 2026-07-14
  (build #234 session): the vendor mt_spm.h:109 define (SPM+0x280) is
  STALE for this silicon — 0x280 reads 0 and silently rejects writes,
  while 0x32C idles at 0x112 (ISO|CLK_DIS|SRAM_PDN off-pattern) and the
  full on-sequence there raises PWR_STATUS bit1 and yields the chip-ID.
  plan.md's original 0x32C claim (matching consys_hw.c's non-API
  fallback comments, "0x1000632c [3]") was right after all.
- sta_mask = **BIT(1)** (`CONN_PWR_STA_MASK`, :1120) in PWR_STATUS
  0x180/0x184; sram_pdn = **BIT(8)** (`CONN_SRAM_PDN`); **no SRAM ack
  wait** in the vendor sequence; bus_prot = **bits 2|8** in
  INFRA_TOPAXI_PROT_EN 0x10001220 / STA1 0x10001228 (`CONN_PROT_MASK`,
  :1149) — same regs mainline `mtk-infracfg.c` already drives. PWR_* bit
  layout identical to mainline scpsys. ⇒ the mainline
  `scp_domain_data_mt6797[]` CONN entry is a straight pattern-copy of the
  MT2701 one (which even shares ctl_offs 0x280 and sta BIT(1)).
- Vendor DTS clock `"conn"` = `<&scpsys SCP_SYS_CONN>` — in 3.18 scpsys
  exposes domains as fake clocks; in mainline this IS the power domain.
  `"bus"` (infra_connmcu_bus) is compiled out for mt6797
  (`CONSYS_AHB_CLK_MAGEMENT = 0`, mtk_wcn_consys_hw.h:42). ⇒ **no
  clk-mt6797 patch needed at all** for power-on.

**Full power-on sequence to chip-ID (K/.../mt6797/mtk_wcn_consys_hw.c
:290-425, CCF path — known-good config has `CONFIG_MTK_CLKMGR` unset):**
1. VCN18 regulator on @1.8V; `udelay(240)`.
2. `co_clock_flag=0` (measured, our `WMT_SOC.cfg`) ⇒ VCN28: set
   RG_VCN28_ON_CTRL=1 (HW control mode) then enable @2.8V.
   (VCN33_BT/WIFI are enabled later by WiFi/BT function-on, not needed
   for chip-ID.)
3. `TOPCKGEN(0x10000000)+0x1350 |= BIT(8)` (CONN2AP sleep mask).
4. AP_RGU (`0x10007000`)+0x18: WDT swsysret bit12 with key `0x88<<24`
   (vendor calls `mtk_wdt_swsysret_config((1<<12),1)`; mainline mtk-wdt
   has no such API — spike driver pokes `0x10007018` directly).
5. `SPM+0x0 (PWRON_CONFG_EN) = 0x0b160001` (SPM project code/key).
6. CONN MTCMOS on (= mainline scpsys domain power_on: prot clear →
   PWR_ON/2ND → ack in 0x180/0x184 bit1 → clk_dis clear → ISO clear →
   RST_B set → SRAM_PDN clear → bus prot release).
7. `udelay(30)`, then poll **chip-ID @ 0x18070008 (CONN_MCU_CONFIG_BASE
   + 0x8), expect 0x0279** (retry ×N, 20ms) — **this is Gate G2a.**
   **G2a PROVEN LIVE BY HAND 2026-07-14** on build #234 over SSH: manual
   devmem MTCMOS sequence at 0x32C (0x116→0x11E→ack in 0x180/0x184 bit1
   →0x10E→0x10C→0x10D→0x00D) then `devmem 0x18070008` = **0x00000279**,
   with VCN rails still OFF and none of the sleep-mask/RGU/PWRON_CONFG_EN
   pokes applied — the MTCMOS + chip-ID path needs none of them.
8. Post-ID: `0x18070110 (MCU_CFG_ACR) |= BIT(18)` (MBIST real-speed);
   AFE/WBG analog trim writes (CONSYS_AFE_REG_SETTING) — deferrable.

**EMI region:** vendor reserved-memory is dynamic — 2 MB, 2 MB-aligned,
`no-map`, alloc-range 0x40000000–0xC0000000 (vendor DTB
`consys-reserve-memory`); the chosen phys base is programmed as
`(base & 0xFFF00000) >> 20` OR'd into `TOPCKGEN+0x1340`
(CONSYS_EMI_MAPPING, consys_hw.c:1035-1041). Coredump view constants:
AP 0x80080000 / FW 0xf0080000 (+0x80000 offset), 343 KB. Not needed for
G2a; needed before MCU firmware download (G2b).

**MT6351 VCN LDO registers (K/.../mt6797/include/mach/upmu_hw.h)** for
the minimal regulator driver (pwrap regmap): `LDO_VCN28_CON0 = 0x0A0C`,
`LDO_VCN18_CON0 = 0x0A52`, `LDO_VCN33_CON0 = 0x0A92`; per-CON0 layout:
ON_CTRL bit0, **EN bit1**, MODE_CTRL/etc. above. Voltages are
fixed-by-strap for VCN18/VCN28 at the values we need (vendor only
set_voltage's them to their nominal 1.8/2.8V); VCN33 vosel checked at
implementation time.

**Firmware extracted 2026-07-14** from the device's Android system
partition (p27, mounted ro over SSH on #225) to `docs/firmware-consys/`:
- `ROMv3_patch_1_0_hdr.bin` 211908 B sha256 `d858642...ff05c57a8`
- `ROMv3_patch_1_1_hdr.bin` 46472 B sha256 `8982bba...105399784`
- `WIFI_RAM_CODE_6797` 451904 B sha256 `c28c50e...a88d840a6`
- `WMT_SOC.cfg` 80 B (`coex_wmt_ant_mode=1`, `wmt_gps_lna_*=0`,
  `co_clock_flag=0`)
- `wmt_launcher` (33296 B) + `wmt_loader` (11064 B) from
  `/system/vendor/bin` — Android bionic binaries, reference only.
No `wifi_fw.cfg` exists on this device. Full hashes:
`shasum -a 256 docs/firmware-consys/*`.

**wifi@180f0000 node (vendor mt6797.dtsi:3768):** IRQ SPI 283 level-low,
clock `<&infrasys INFRA_AP_DMA>` `"wifi-dma"` — relevant at the gen2-port
stage, not for G2a/G2b.

---

# Battery & Charging Research (2026-07-12, for Phase 7 — queued AFTER keyboard completion)

**User observation:** the Gemini charges when booted into Android; unclear
whether it charges under our Linux 6.6.

## Hardware

- **Charger:** Richtek RT9466, I2C addr 0x53 (vendor `rt9466.dtsi`:
  `ichg = 2000000` µA, `aicr = 500000` µA, 12 h safety timer,
  `en_wdt = true`). Vendor driver:
  `gemini-android-kernel-3.18/.../power/mt6797/rt9466.c`.
- **Fuel gauge:** MT6351 PMIC integrated (coulomb counter + AUXADC) — NO
  mainline support at all (hardware.md; B-12 family). Charger-only
  operation + userspace voltage monitoring is the documented minimum.

## What happens today under our Linux (no charger driver)

1. In OUR (Kali-slot) boot chain, **LK itself cannot talk to the RT9466**
   — every capture shows `rt9466_i2c_read_byte: I2CR[0x40] failed`,
   `get primary charger failed`, `pchr_turn_on_charging: enable charging
   failed, ret = -95`. So no software configures the charger before or
   after kernel handoff on the Linux boot path.
2. Therefore charging (if any) runs on **RT9466 power-on hardware
   defaults**: charge enable is default-on in hardware with conservative
   default current/termination, so the device most likely trickle-charges
   — but default safety-timer/WDT behavior is unverified against the
   datasheet, and nothing re-enables charge after faults. This matches
   "charges in Android (vendor driver active), unsure in Linux".
3. **Empirical check available any time** (careful: read-only, and do
   NOT hammer a bus the keypad polls): `i2cget -y -f <bus> 0x53 0x42`
   (CHG_STAT) on the running device, with/without VBUS, would confirm
   charging state definitively. Bus number for 0x53 needs confirming
   from the vendor DTB (not i2c5).

## Mainline path (the Phase 7 plan)

- `drivers/power/supply/rt9467-charger.c` (v6.6) **explicitly supports
  RT9466** (VID 0x8 accepted in probe). DTS: `compatible =
  "richtek,rt9467"` node already drafted in dts/0001 but `disabled`.
- **Blocker: the mainline driver hard-requires its IRQ** —
  `dev_err_probe(-EINVAL, "Failed to get (%s) irq")` for every one of its
  chg IRQs; the RT9466 INT line is GPIO246 → EINT, and pinctrl-mt6797 has
  NO EINT support (**B-11**, same blocker as the keyboard IRQ path).
  Options, in preference order:
  1. **Fix B-11** (EINT in pinctrl-mt6797) — proper fix; also upgrades
     the keyboard to IRQ-driven and unblocks FUSB301A/touchscreen. This
     makes B-11 the natural Phase 7 opener.
  2. Patch rt9467-charger.c to make the IRQ optional + poll attach/EOC
     state (local patch, like the keypad polling one).
- Safety notes for the build: charger-only mode is safe (RT9466 does CV
  termination in hardware); the driver's WDT-kick and safety-timer
  handling replace the vendor equivalents; no fuel gauge = no SoC%, so
  userspace battery display waits for an MT6351 AUXADC driver (~200–500
  LOC, deferred).

**Sequencing (user decision 2026-07-12):** finish the keyboard build
first (Fn layer, keymap verification); battery/charging is the next
build after that.

---

# USB Left-Port PHY & Type-C Harvest (2026-07-14, Stage A of USB plan)

Source-backed register/logic harvest from the vendor 3.18 tree
(`/Volumes/extdata/github/gemini-android-kernel-3.18/kernel-3.18/`, below
cited as `K/`) and the real device DTB
(`docs/vendor-dtb/gemini_kali_boot.dts`, cited as `DTB`). Purpose: replace
every guessed register in the B-19/B-20 work with a cited value.

## 1. U2-PHY usb2uart (the B-15/B-20 "console mux")

The left port's UART/USB console mux is the U2 PHY's usb2uart function
plus ONE AP-side register. Vendor implementation:
`K/drivers/misc/mediatek/mu3phy/mt6797/mtk-phy-asic.c` (guarded by
`CONFIG_MTK_UART_USB_SWITCH=y` — SET in the known-good vendor config,
`docs/vendor-dtb/kali_known_good_kernel.config:1544`).

Register addresses (offsets from `mtk-phy-asic.h:19-39`; physical base =
u2port0 com bank `0x11290800` from our `patches/v6.6/dts/0009` t-phy node,
matching vendor DTB `usb3_sif2@11290000`):

| Register | Phys addr | uart-mode bits (mtk-phy-asic.h:234-269,490-525) |
|---|---|---|
| U3D_U2PHYDTM0 | **0x11290868** | `RG_UART_MODE` [31:30], `FORCE_UART_BIAS_EN` [28], `FORCE_UART_TX_OE` [27], `FORCE_UART_EN` [26], `FORCE_SUSPENDM` [18], `RG_SUSPENDM` [3] |
| U3D_U2PHYDTM1 | **0x1129086C** | `RG_UART_BIAS_EN` [18], `RG_UART_TX_OE` [17], `RG_UART_EN` [16] |
| GPIO MISC mux | **0x10005600** | `0x80` = UART routed to USB D+/D- pads, `0x00` = USB (asic.c:207-208,301,311 — the dump labels it "0x10005600 (GPIO MISC)"; it is in the pinctrl block, NOT the UART) |
| U3D_USBPHYACR6 | 0x11290818 | `RG_USB20_BC11_SW_EN` (cleared before uart switch) |
| U3D_U2PHYACR4 | 0x11290820 | `RG_USB20_DM_100K_EN` [17] (set in uart mode) |

Vendor logic (asic.c):
- `usb_phy_check_in_uart_mode()` (:211-230): in-uart-mode ⇔
  `(DTM0 >> 30) == 1`. **RG_UART_MODE, not FORCE_UART_EN, is the vendor's
  definition of uart mode.**
- `usb_phy_switch_to_uart()` (:232-304): VUSB33/VA10 on → BC11_SW_EN=0 →
  RG_SUSPENDM=1, FORCE_SUSPENDM=1 → **RG_UART_MODE=1** → RG_UART_EN=1,
  FORCE_UART_EN=1, FORCE_UART_TX_OE=1, FORCE_UART_BIAS_EN=1,
  RG_UART_TX_OE=1, RG_UART_BIAS_EN=1 → DM_100K_EN=1 → **0x10005600=0x80**.
- `usb_phy_switch_to_usb()` (:307-322): **0x10005600=0x00** → clear
  FORCE_UART_EN → full `phy_init_soc()` re-init.
- `phy_init_soc()` clears FORCE_UART_EN/RG_UART_EN **only if
  `!in_uart_mode`** (:543-548) — vendor deliberately preserves uart mode
  across PHY re-inits; the switch is manual/persistent (sysfs `portmode`,
  `mu3d/drv/mt_usb.c:483-526`), NOT automatic per-boot.

**Gap vs mainline** `drivers/phy/mediatek/phy-mtk-tphy.c`
`u2_phy_instance_init()` (v6.6, :815-848): mainline clears FORCE_UART_EN
(:823) and RG_UART_EN (:828) but **never clears RG_UART_MODE [31:30] and
never touches 0x10005600**. If LK leaves both set (it runs its console on
this port), the pad routing may remain UART even after mainline tphy init
— candidate root cause for B-20's boot-with-host-attached failure, and
possibly for B-19 host-mode D+/D- deadness too.

Diagnostic devmem set (read-only, safe): `0x11290868`, `0x1129086C`,
`0x10005600` — compare good boot (FTDI protocol) vs broken boot
(Mac-cable-at-power-on).

## 2. Vendor gadget connect logic (mu3d) — what drives "attach"

`K/drivers/misc/mediatek/mu3d/drv/mt_usb.c`:
- `usb_cable_connected()` (:256+): connected ⇔ **PMIC charger detection**
  — `mu3d_hal_get_charger_type()` (BC1.2) ∈ {STANDARD_HOST,
  CHARGING_HOST} AND `upmu_get_rgs_chrdet()` (MT6351 CHRDET) says VBUS
  present. The FUSB301A plays NO role in vendor gadget attach; neither
  does mtu3-internal VBUS sensing.
- `connection_work()` (:84+): polls/reacts, does soft-connect/disconnect.
- At controller init (`mu3d/drv/musb_init.c:714-721`): if PHY is in uart
  mode, the vendor just logs `UART_MODE` and leaves it — gadget then
  simply doesn't work until userspace flips `portmode`. Android's
  always-enumerates behavior implies Android userspace/LK ensures USB
  mode; our kernel must do the equivalent unconditionally.
- `CONFIG_USB_MU3D_DEFAULT_U2_MODE=y` (known-good config:1509): vendor
  ran the left port USB2-only by default.

## 3. FUSB301A — real register map and vendor usage

Real map from `K/drivers/misc/mediatek/usb_c/fusb301/fusb301.h:49-150`
(Fairchild reference header; applies to both fusb301 drivers):

| Reg | Addr | Bits |
|---|---|---|
| DeviceID | 0x01 | VERSION[7:3] REVISION[2:0] |
| **Mode** | **0x02** | SOURCE[0] SOURCE_ACC[1] SINK[2] SINK_ACC[3] DRP[4] DRP_ACC[5] |
| Control | 0x03 | INT_MASK[0] HOST_CUR[2:1] DRPTOGGLE[5:4] |
| Manual | 0x04 | ERROR_REC[0] DISABLED[1] UNATT_SRC[2] UNATT_SNK[3] |
| Reset | 0x05 | SW_RES[0] |
| Mask | 0x10 | M_ATTACH[0] M_DETACH[1] M_BC_LVL[2] M_ACC_CH[3] |
| Status | 0x11 | ATTACH[0] BC_LVL[2:1] VBUSOK[3] ORIENT[5:4] |
| Type | 0x12 | device type decode |
| Interrupt | 0x13 | I_ATTACH[0] I_DETACH[1] ... |

So: **host/DFP = Mode(0x02)=0x01 (SOURCE)**; DRP = 0x10. The old
`patches/v6.6/usb/0001` "regMode=0x04" write was to the Manual register —
now fully explained (B-19's stopping point).

**TWO FUSB301 chips exist** (DTB:3678 vs :3772): `fusb301a@25` on
**i2c0** (11007000, id=0) and `fusb301@25` on **i2c1** (11008000, id=1).
Vendor binds them with different drivers:
- i2c0 chip → `K/.../usb_c/fusb302/usb_typec.c` (compatible
  "mediatek,fusb301a", :331). Init = Mode:=0x01 SOURCE only (:54-68). Its
  IRQ is NOT the FUSB301A INT — it is the **USB1 (right-port) ID pin**,
  EINT 64 debounce 256ms ("mediatek,fusb301a-pin", DTB:5215-5221).
  `fusb300_eint_work()` (:107-168): on ID low, read Status(0x11) ORIENT →
  drive GPIO94 (usb1 VBUS), GPIO70/71 (HDMI lane mux by CC orientation),
  GPIO72 (sw7226, OTG enable) — all right-port/HDMI plumbing, confirming
  boot.md's B-20 finding.
- i2c1 chip → `K/.../usb_c/fusb301/usb_typec.c` (compatible
  "mediatek,fusb301"). Init = Mode:=0x01 SOURCE; its eint work function is
  EMPTY (:93-100) — a stub. No CC-driven switching at all.

**Open question (test live, zero-risk):** which physical port each chip
serves. Our kernel found a chip on i2c0/0x25 (hardware.md), and B-20's
dump of it showed ATTACH/ORIENT tracking the left port — but the vendor
wires the i2c0 chip's logic to right-port muxes. `i2cdetect`/`i2cget` on
both buses while plugging each port resolves this in minutes and MUST be
done before further FUSB301A driver work.

## 4. Vendor host mode on the SSUSB (left) port — it existed

Contrary to B-19's "Android only ever used gadget mode on this port":
known-good config has `CONFIG_USB_XHCI_MTK=y` (:1556) and the DTB has
`usb3_xhci@11270000` with an `usb_iddig_bi_eint` child (EINT 181,
DTB:4379-4392). Vendor host/device switch on SSUSB = **IDDIG ID-pin EINT
181**, not CC logic. Implications for Stage C:
- Left-port host mode is electrically proven (vendor shipped it).
- The trigger the vendor used is the IDDIG line; how IDDIG is generated
  on a Type-C port (FUSB301A? OTG cable detect?) is the key open
  question — find the iddig handler in `K/.../ssusb/` or `xhci/` next.
- Our mainline `dr_mode="otg"` + role-switch approach needs an input the
  vendor got from IDDIG; forcing host role without it may be why G1a saw
  zero connect events even with all GPIOs correct.

## 5. Revalidated-assumption ledger (2026-07-14)

- "PHY stuck in usb2uart on broken boots" — WEAKENED by the genuine #177
  capture (serial dies at 0.454s ⇒ FORCE_UART_EN cleared) but NOT dead:
  mainline leaves RG_UART_MODE + 0x10005600 uncleared, and serial death
  only proves the FORCE bits changed. Devmem dump decides.
- "FUSB301A Mode write 0x04" — resolved wrong; Mode=0x02, SOURCE=0x01.
- "Vendor gadget attach = CC/controller sensing" — wrong; it's PMIC
  BC1.2 + CHRDET (mt_usb.c). Mainline mtu3 without extcon must sense a
  host by D+/D- reset, which fails if pad routing is stuck.
- "Vendor never ran host mode on SSUSB" — wrong; XHCI_MTK=y + IDDIG
  EINT 181.
- "GPIO70/71/72/94 are left-port gadget path" — confirmed wrong (they
  are right-port OTG/HDMI), per fusb302/usb_typec.c:96-156.

## 6. LIVE verification 2026-07-14 (#177 good boot, gadget configured)

PHY/mux registers with gadget WORKING (baseline for the broken-boot diff):
- `U2PHYDTM0(0x11290868) = 0x52000008` → RG_UART_MODE[31:30]=01 (vendor
  would call this "uart mode"!), FORCE_UART_BIAS_EN[28]=1,
  FORCE_UART_EN[26]=0, RG_SUSPENDM[3]=1
- `U2PHYDTM1(0x1129086C) = 0x00043E2E` → RG_UART_BIAS_EN[18]=1,
  RG_UART_EN[16]=0
- `GPIO MISC (0x10005600) = 0x80` → still "UART routing" value
- Conclusion: RG_UART_MODE=1 and MISC=0x80 do NOT by themselves block
  gadget USB. Only the FORCE_/RG_UART_EN bits (cleared by mainline tphy)
  seem to matter for the data path. The broken-boot dump (staged in
  /root/run-once.sh) must show which bits differ.

FUSB301 chips, Mac attached to LEFT port (i2cget -f, DeviceID/Mode/
Control/Manual/Status/Type):
- **i2c0 chip: Status=0x00 Type=0x00 (sees nothing)** — it serves the
  RIGHT port (consistent with §3 vendor wiring).
- **i2c1 chip: Status=0x2b (ATTACH VBUSOK BC_LVL=01 ORIENT=CC2),
  Type=0x08 — the LEFT port's CC controller is the i2c1 chip.**
- Both chips Mode=0x04 (SINK), Control=0x03 (INT_MASK=1, HOST_CUR=01) —
  power-on defaults; nothing in build #177 writes them.

**Consequence for B-19 (Stage C):** every Stage 1 FUSB301A experiment
(ATTACH always 0, "MODE write" tests) talked to the i2c0/right-port chip
while devices were plugged into the left port. ATTACH=0 was the truthful
answer for an empty right port. For left-port host mode the chip to
program is **i2c1 0x25: Mode(0x02)=0x01 (SOURCE)** — and in SINK mode
(current default) a downstream device presenting Rd is invisible, which
is consistent with everything G1a observed.

## 7. Stage C Phase 1 harvest (2026-07-14): IDDIG handler + left-port VBUS source

Source: `K/drivers/misc/mediatek/xhci/xhci-mtk-driver.c` (vendor host-mode
glue) + `K/drivers/misc/mediatek/power/mt6797/rt9466.c/.h`.

**IDDIG (EINT 181) handling** (`xhci-mtk-driver.c`):
- `mtk_xhci_eint_iddig_init()` (:708) reads the `mediatek,usb_iddig_bi_eint`
  DTB node and requests the EINT as `IRQF_TRIGGER_LOW`.
- ISR (:668) just debounces (50ms default) into `mtk_xhci_mode_switch()`
  delaywork (:600-662): on ID **low** → charger-voltage check (>4V ⇒ a
  charger, stay device) else load xhci + `switch_int_to_host`, flip EINT to
  TRIGGER_HIGH to catch unplug; on ID high → unload xhci, back to
  TRIGGER_LOW. Pure level-triggered ID-pin OTG, no CC logic anywhere in the
  host path.
- **Who drives IDDIG low on a Type-C port is still unproven** — the i2c1
  FUSB301's eint work is a stub (§3), and the FUSB301 pinout has no legacy
  ID output, so the likeliest candidates are a board-level wiring of the
  FUSB301 INT_N or a dedicated comparator. Phase 0 live test resolves this
  empirically (watch GPIO181/EINT181 level while attaching a sink with the
  chip in SOURCE mode).

**Left-port host VBUS = RT9466 charger OTG boost, NOT the PMIC.**
`CONFIG_MTK_OTG_PMIC_BOOST_5V` is **not set** in the known-good config
(:1558) — the `mtk_enable_pmic_otg_mode()` MT6351 sequence is dead code on
this device. The shipped path is `mtk_enable_otg_mode()` (:425):
`set_chr_enable_otg(1)` + boost current limit 1500mA → RT9466
`rt_charger_enable_otg()` (:2073):
- Enter hidden mode (password sequence), write HIDDEN_CTRL4 (0x23)=0x7c
  (slew-rate workaround), boost OC limit 500mA,
- **set CHG_CTRL1 (reg 0x01) bit0 OPA_MODE=1** — this is the actual boost
  enable, verify-read after 20ms,
- write HIDDEN_CTRL6 (0x25)=0x00 (workaround), exit hidden mode.
  Disable = clear bit0, 0x23=0x73, 0x25=0x0F.
- RT9466 is at **i2c0 0x53** (DTB:3684, same bus as the right-port
  fusb301a).

**Mainline mapping (excellent fit):** v6.6 `rt9467-charger.c` (covers
RT9466) registers exactly this boost as a regulator —
`usb-otg-vbus-regulator` child node → regulator `rt9476-usb-otg-vbus`
(driver :318-346, binding `richtek,rt9467.yaml`). So Phase 2's clean shape
is: RT9466 node on i2c0 + `usb-otg-vbus-regulator` child, referenced as the
`vbus-supply` of the ssusb/mtu3 node. Caveat: the mainline driver
hard-requires its IRQ (B-11 EINT gap, Phase 7 note) — either patch the IRQ
optional or fix B-11 first.

**Zero-kernel Phase 0 VBUS test:** `i2cset -f -y 0 0x53 0x01` read-modify-
write bit0 (i2cget then i2cset value|0x01) turns the boost on without the
hidden-mode workarounds (they are noise-robustness tweaks, acceptable for a
bench test); clear bit0 to turn off. Combined with i2c1 FUSB301
Mode(0x02)=0x01 SOURCE this exercises the full CC-attach + VBUS-source path
with no kernel changes.

## 8. Stage C Phase 0 LIVE RESULTS (2026-07-14): left-port VBUS chain proven; charger is BQ25896, NOT RT9466

Live probes on build #225 over gadget SSH (staged-script protocol, logs
`logs/2026-07-14-227..230-b19-phase0-*.log`). Headline: **the complete
left-port host-mode power/CC chain works from userspace with zero kernel
changes** — CC attach detection AND 5.0V VBUS sourcing both verified on
real downstream devices (SD reader, MediaTek USB-C ethernet adapter, LEDs
lit).

**Correction to §7 and to Phase 7 research: there is no RT9466 on this
device.** No I2C bus has a device at 0x53; i2c0 0x6b responds with
REG14=0x06 → TI **BQ25896** (PN=000, rev 2). The vendor code's
`CONFIG_MTK_BQ25896_SUPPORT`/`bq25890_otg_en()` branch is the live one
(`charging_hw_bq25890.c`); the RT9466 branch was dead config. Mainline
support is `drivers/power/supply/bq25890_charger.c` (compatible
`ti,bq25896`), which exposes the boost as a `usb-otg-vbus` regulator
(:1223-1229) — still an excellent Phase 2/Phase 7 fit.

**The working recipe (all three required):**
1. FUSB301 (i2c1 0x25) `Mode(0x02)=0x01` SOURCE → Status shows
   ATTACH+orientation for a sink (verified both CC1 and CC2 orientations,
   Type=0x10 SINK).
2. BQ25896 (i2c0 0x6b) `REG03 OTG_CONFIG bit5=1` — **with the I2C watchdog
   disabled first** (`REG07[5:4]=00`, default 0x9d = 40s WD that resets
   REG03 to defaults; explains the OTG bit "clearing itself" in early
   runs). Vendor Android instead kicks the WD continuously.
3. **GPIO107 HIGH** — `GPIO_OTG_DRVVBUS_PIN` in the board dws
   (`aeon6797_6m_n.dws:1561`); wired to the BQ25896 OTG pin (boost is
   pin-AND-register gated, no fault raised when pin low — the silent
   no-boost failure mode). LK hands over GPIO107 as GPIO-mode output LOW.
   devmem: DOUT-set 0x10005134 bit11, clear 0x10005138 bit11.

With all three: REG0B VBUS_STAT=111 (boost mode), REG11 VBUS ADC = 5.0V,
FUSB Status = ATTACH|VBUSOK, adapter LEDs lit. Battery held 4.08V.
Boost config default REG0A=0x73 (4.998V, 1.4A limit) — no change needed.

**Safety notes for Phase 2:** BQ auto-prioritizes a real input when VBUS
appears externally (Mac replug during boost was handled without damage;
one transient BOOST_FAULT latched at hot-unplug, self-cleared). The FUSB
in SOURCE mode while a Mac (another source) is attached drops the gadget
link — restore SINK before reconnecting for SSH.

**Phase 2 design consequence:** DTS = `bq25896@6b` on i2c0 with
`usb-otg-vbus` regulator as `vbus-supply` of the ssusb node; GPIO107
driven high (gpio-hog, or preferably the regulator's enable path if
plumbed); the mainline driver must not leave the 40s watchdog armed
(check its WD handling at probe). IDDIG (EINT 181) remains untested —
still unknown who drives it; may be unnecessary if we use
`role-switch-default-mode="host"` or wire the FUSB301A driver as the
role-switch source.

## Golden-reference extra harvest (vendor Kali 3.18, WiFi up) — 2026-07-15

Opportunistic capture while the vendor stack was live for the B-21 W0b
CONSYS harvest (user suggestion). Raw files:
`logs/2026-07-15-243-goldharvest-extra/` (u2phy dump, i2c device map,
input devices, /proc/interrupts, gpio, pinmux-pins, regulator summary,
USB/touch dmesg grep). Highlights:

### USB (B-19/B-20 reference)
- **U2 PHY u2port0 golden gadget-mode: U2PHYDTM0 (0x11290868) =
  0x56BE00D4, U2PHYDTM1 (0x1129086C) = 0x00053E1A** — the vendor's
  BC1.2-driven session-valid state while enumerated. Compare with our
  phy/0001 forced value (0x3E2E pattern) — full 128-byte block dump in
  `usb-u2phy-u2port0.txt` for any future PHY tuning.
- AP UART/USB mux 0x10005600 = 0x80 (USB mode) — same value we see.

### Full I2C device inventory (vendor bus numbering)
```
i2c0: 0x25 fusb301a (right port CC), 0x31 speaker_amp, 0x53 rt9466(*),
      0x63 strobe_main, 0x6b sw_charger (BQ25896), 0x70 buck_boost
i2c1: 0x25 fusb301 (LEFT port CC), 0x30 msensor_mmc3530, 0x3e lcd_bias
      (TPS65132), 0x48 alsps, 0x5f humidity, 0x68/0x69 bmi160 acc/gyro,
      0x6a/0x6b gsensor/gyro (alt), 0x77 barometer
i2c2: 0x2d camera_main, 0x72 camera_main_af
i2c3: 0x0c camera_sub_af, 0x2c aw9120_led, 0x36 camera_sub,
      0x39 sii9022_hdmi, 0x50 siiedid
i2c4: 0x53 solomon_touch (TOUCHSCREEN), 0x62 cap_touch
i2c5: 0x28 nfc, 0x5b aw9523_key (keyboard GPIO expander)
i2c6: 0x68 vproc_buck   i2c7: 0x1c rt5735-regulator, 0x60 vgpu_buck
i2c8: 0x36 camera_main_hw
```
(*) rt9466@0-0053 is REGISTERED by the vendor kernel but our live scans
found no chip at 0x53 — vendor registers both charger candidates and
lets probe decide; the real charger is sw_charger/BQ25896 at 0x6b.
NOTE vendor bus numbers differ from our DTS numbering (our aw9523b is
"i2c-3" in our numbering = vendor i2c5).

### Touchscreen (Phase 9)
- Controller: **solomon_touch, vendor i2c4 addr 0x53** (Solomon — pairs
  with the SSD2092 panel), plus a cap_touch node at 0x62. Input device
  "mtk-tpd" + raw node under `4-0053`. Probe details in
  `dmesg-usb-touch.txt`, IRQ/EINT in `interrupts.txt`.

### Misc
- HDMI: sii9022 at vendor i2c3 0x39 with EDID EEPROM at 0x50.
- Keyboard LED controller: aw9120 at vendor i2c3 0x2c.
- Sensors (Phase 9): BMI160 acc+gyro, MMC3530 mag, ALSPS, humidity,
  barometer — all vendor i2c1.
- `/sys/class/udc` = musb-hdrc (vendor gadget on right port musb).
- Vendor regulator debugfs was empty (78 bytes) — MTK legacy PMIC
  framework, not the regulator core; VCN rail states not visible there.

### Right-port USB host — vendor architecture (2026-07-15, live on vendor Kali)

**The right port is the Gemini's only working host port on the vendor
stack, and it is served by a SECOND USB controller, not xhci/ssusb:**
`usb1@11200000` (MUSB "FSH" dual-role, banner `MUSBFSH HDRC host driver`,
IRQ GIC 105) with its own PHY SIF at `usb1p_sif@11210000`. Verified live:
SD-reader (`349c:0418`) enumerated at **480 Mbps** on bus 1 (musbfsh),
`sda1` auto-mounted (`/media/root/SDCARD`, FAT). Log:
`logs/2026-07-15-245-vendor-rightport-host-enum.log`.

**Left port host mode is BROKEN even on the vendor kernel:** on ID/CC
attach, `otg_state`→1 and xhci registers (buses 2+3), but the sequence
aborts at `Cannot find usb pinctrl drvvbus_high` (missing pinctrl state =
GPIO107 driver) and — decisively — **U2PHYDTM1 stays 0x00053E2E**, the
forced *device*-session pattern (B-20's value), so xhci can never see a
connect. VBUS chr-det fired once GPIO107 was forced high manually
(`[upmu_is_chr_det] Charger exist but USB is host`) but the charger ADC
read 0 and no enumeration followed. So there is no vendor golden
reference for left-port host mode; the vendor product evidently only
ever supported host on the right port via musbfsh.

**B-19 consequence / new option:** mainline v6.6 has a MediaTek MUSB
glue (`drivers/usb/musb/mediatek.c`, mt8516). Enabling right-port host
via musb@11200000 may be far easier than the left-port ssusb/xhci path,
and leaves the left port free for gadget SSH/serial. Right-port CC is
the i2c0 fusb301a@25. Vendor DT nodes to harvest timing/clock details
from: `usb1@11200000`, `usb1p_sif@11210000` in
`docs/vendor-dtb/gemini_kali_boot.dts`.

**Vendor kernel crash rule (reconfirmed):** reading
`/sys/devices/platform/bq25890-user/bq25890_access` rebooted the device
— never touch vendor `*_access` sysfs nodes (see also pmic_access).

**Right-port live results (same session):** SD reader `349c:0418` →
sda1 FAT mounted; then the USB ethernet adapter — **Realtek RTL8156**
(`0bda:8156`) — enumerated on musbfsh, bound by `cdc_ncm` (its
fallback ECM/NCM interface; the 3.18 kernel has no r8152/8156 driver),
link up 100 Mbit, DHCP lease 192.168.100.138/24. So the "dark LEDs"
earlier were purely the left-port no-VBUS/no-connect issue. For our
6.6 kernel the same dongle would use the mainline `r8152` driver (real
2.5GbE mode) or cdc_ncm. Evidence appended to
`logs/2026-07-15-245-vendor-rightport-host-enum.log`.

### Touchscreen golden harvest (vendor Kali 3.18, live) — 2026-07-15

Raw log: `logs/2026-07-15-246-vendor-touch-harvest.log`.

- **IC/firmware ident (driver `version` sysfs):** IC = SSD **2092** (same
  TDDI chip as the display), panel AUO "599", resolution **1080 x 2160**,
  sense matrix 32 x 18, **10-point** touch, Display Version 0x16,
  vendor driver `ssd20xx` v1.10.
- **Attachment:** vendor i2c4, addr **0x53** (`solomon_touch`); second
  node `cap_touch@0x62` exists but has NO driver bound — ignore it.
  Driver sysfs dir: esdtime/gesture/mptest/ssdtouch/testing/touchmode/
  version + `/proc/AEON_TPD`, `/proc/AEON_TP_FW`.
- **Input path:** events are delivered via the **virtual `mtk-tpd`
  input device** (tpd framework), not the `4-0053/input/input9` node.
- **Protocol (live trace, taps + swipes):** MT **type A** style frames —
  per contact: ABS_MT_TOUCH_MAJOR(48)=1, ABS_MT_POSITION_X(53),
  ABS_MT_POSITION_Y(54), ABS_MT_TRACKING_ID(57)=0, SYN_MT_REPORT;
  BTN_TOUCH(330) 1/0 at contact start/end. No ABS_MT_SLOT seen.
  Observed X values up to ~1862 with Y ~600s — X runs along the LONG
  (2160) axis in the vendor's portrait frame; remap needed for our
  landscape fbcon orientation.
- **Porting notes:** vendor source = `ssd20xx` driver under the 3.18
  reference tree (drivers/input/touchscreen/mediatek/ or similar) — the
  I2C protocol authority. IRQ is an EINT (B-11 gap applies); check if
  polled operation is viable like the keyboard, else wait for Stage B
  EINT support. A mainline `solomon,ssd20xx` driver does not exist in
  v6.6 — this will be a vendor port or new driver (Phase 9).

# WMT Firmware-Push Protocol (2026-07-16, B-21 G2b re-scope — Step 1 deliverable)

Source authority: vendor 3.18 tree
`drivers/misc/mediatek/connectivity/common/common_main/` — `core/wmt_ic_soc.c`
(`mtk_wcn_soc_sw_init()` at ~line 975, `mtk_wcn_soc_patch_dwn()` at ~line
2042), `core/wmt_ctrl.c` (`wmt_ctrl_get_patch_info()`), `core/include/`
(`wmt_core.h` `WMT_PATCH`, `wmt_lib.h` `WMT_PATCH_INFO`), plus MTK's
open-source userspace `stp_uart_launcher.c` (BPI-R2 BSP copy — our extracted
`wmt_launcher` is the same tool).

## Patch file format — our extracted blobs ARE the on-wire format

`WMT_PATCH` header is exactly 28 bytes, followed directly by the downloadable
body (no other container — earlier "ALPS magic at 0x0C" note was off by 4):

| Offset | Size | Field | `ROMv3_patch_1_1_hdr.bin` | `ROMv3_patch_1_0_hdr.bin` |
|---|---|---|---|---|
| 0 | 16 | `ucDateTime` | `20180615091545a\n` | same |
| 16 | 4 | `ucPLat` | `ALPS` | `ALPS` |
| 20 | 2 | `u2HwVer` | `8a 00` (= HW_VER 0x8A00 we read live) | same |
| 22 | 2 | `u2SwVer` | `8a 00` | `8a 00` |
| 24 | 4 | `u4PatchVer` (= launcher "patch info") | `21 00 0a f0` | `22 00 09 00` |

The launcher (`srh_patch`) seeks to offset 22, reads 2 bytes version + 4 bytes
"patch info", and derives:

- `patchNum = info[0] >> 4` (= 2 for both files — total patches)
- `dowloadSeq = info[0] & 0xF` (1_1 → seq **1**, 1_0 → seq **2** — matches the
  observed push order on the vendor stack)
- `addRess[4] = info` with `addRess[0]` zeroed:
  1_1 → `{00,00,0a,f0}`, 1_0 → `{00,00,09,00}`
- version check: low byte of `u2SwVer` must equal low byte of the fw version
  returned by the chip.

It passes `{dowloadSeq, addRess[4], patchName[256]}` per patch to the kernel
via `WMT_IOCTL_SET_PATCH_INFO`; the kernel driver itself never parses
anything beyond the 28-byte header.

## Command sequence (BTIF path of `mtk_wcn_soc_sw_init()`)

All frames below are inner WMT payloads, wrapped in STP framing exactly as
our spike already does. Order, with abort semantics:

1. **`init_table_1_2`**: `WMT_QUERY_STP_CMD` `01 04 01 00 04` →
   expect `WMT_QUERY_STP_EVT_DEFAULT` `02 04 06 00 00 04 11 00 00 00`.
   **Runs pre-patch, in mand mode, and sw_init ABORTS if it fails** — i.e.
   vendor source proves the ROM answers this query before any firmware is
   pushed. (Tension with the B-21 hypothesis-1 conclusion noted below.)
2. `init_table_4`: `WMT_SET_STP_CMD` `01 04 05 00 03 DF 0E 68 01` → evt
   `02 04 02 00 00 03` (enables chip-side full-STP features).
3. Host-side STP switched to `MTKSTP_BTIF_FULL_MODE`, sleep 10ms.
4. `init_table_5`: query again, now expecting `WMT_QUERY_STP_EVT`
   `02 04 06 00 00 04 DF 0E 68 01`.
5. `wmt_power_on_dlm_table` (non-fatal if it fails): three reg-write ops
   (opcode 0x08) to addr `0x80100060`: value 0 mask `0x00000f00`; value 0
   mask `0x000000f0`; value 0 mask `0x00000008`. Evt always
   `02 08 04 00 00 00 00 01`.
6. `set_mcuclk_table_3` (6797-specific, non-fatal): four reg-writes —
   `0x81021110`=0x10000000/mask 0x10000000, `0x8000010c`=0x40/mask 0xc0,
   `0x80021118`=0x07/mask 0x3f, `0x81021100`=0x04/mask 0x07
   (speeds MCU clock up for download). Evt = same 0x08 evt as above.
7. **Per patch, in `dowloadSeq` order (1_1 then 1_0):**
   a. `WMT_PATCH_ADDRESS_CMD` (20 B, reg-write): for icId 0x0279 the addr
      bytes [8..11] are patched to `08 05 09 02` → writes 0 (mask
      0xffffffff) to `0x02090508`. Evt `02 08 04 00 00 00 00 01`.
   b. `WMT_PATCH_P_ADDRESS_CMD` (20 B, reg-write): addr bytes for 6797 =
      `2c 0b 09 02` → `0x02090b2c`; **value bytes [12..15] = the patch's
      `addRess[4]`** (1_1: `00 00 0a f0`, 1_0: `00 00 09 00`), mask
      0xffffffff. Same evt.
   c. Fragment loop: body (file minus 28-byte header) split into 1000-byte
      fragments. Each TX = `WMT_PATCH_CMD` `01 01 <len_lo> <len_hi> <flag>`
      + fragment, where len = 1 + fragSize and flag = 1 (first), 2 (mid),
      3 (last). After each fragment expect `WMT_PATCH_EVT`
      `02 01 01 00 00`. (1_1: 46,444 B body → 47 frags; 1_0: 211,880 B
      body → 212 frags.)
   d. `init_table_3` after each patch: `WMT_RESET_CMD` `01 07 01 00 04` →
      evt `02 07 01 00 00`.
8. `set_mcuclk_table_4` (non-fatal): reg-writes restoring 26 MHz —
   `0x81021100`=0/mask 0x07, `0x8000010c`=0/mask 0xc0, `0x81021110`=0/mask
   0x10000000.

## Implication for G2b

The vendor flow contradicts the strong form of hypothesis 1: the first query
is answered by the **ROM alone** (patch download only happens after it
passes). So a firmware push cannot be what unlocks the query — but
implementing the push path is still the right spike extension: (a) it makes
the re-scoped gate ("handshake + firmware resident") testable end-to-end the
moment the query starts passing, and (b) attempting the later steps (reg-write
ops use a different WMT opcode, 0x08) even after a query timeout tells us
whether the ROM ignores only opcode 0x04 or all BTIF traffic.

## 9. LXQt desktop bring-up (2026-07-19) — userspace only, no kernel/boot change

Working LXQt desktop on the Debian 13 rootfs, launched manually with `startx`
(root; no display manager installed, boot behavior unchanged). All work done
live over SSH (`sshpass -p toor`, usb0 10.15.19.82). Kernel remains build #266.

**Packages:** `lxqt-core openbox xorg xinit` (`--no-install-recommends`), then
the pieces that flag silently omits and which each caused a visible defect:
`breeze-icon-theme lxqt-themes` (no icon theme at all), **`qt6-svg-plugins`**
(see below), `qterminal pcmanfm-qt featherpad lximage-qt lxqt-config`, and
`gvfs gvfs-backends gvfs-fuse udisks2` (desktop Computer/Network icons
returned "operation not permitted" without them; need a fresh session after
install).

**Rotation — DRM path is fatal:** `xrandr --rotate left` on the modesetting
driver issues an atomic commit that wedges mediatek-drm (`flip_done timed
out`, `vblank wait timed out`, `mtk_drm_crtc: new event while there is still
a pending event`); the panel stays dark until reboot. Working config instead
forces the **fbdev** Xorg driver with software shadow rotation:
`/etc/X11/xorg.conf.d/20-gemini-fbdev-rotate.conf` — `Driver "fbdev"`,
`Option "Rotate" "CCW"`. The SSD2092 touchscreen needs an **identity**
libinput calibration matrix — its raw axes already match the rotated
landscape screen (derived empirically via corner mapping).

**Invisible start button root cause:** the mainmenu/fancymenu button rendered
zero visible pixels but was present and clickable (proved with `xdotool`
click + `scrot` screenshot over SSH). Breeze is an all-SVG theme and the Qt6
SVG *icon engine* (`qt6-svg-plugins` → `iconengines/libqsvgicon.so`) was
missing, so every themed icon drew blank (tray showed red-X placeholders).
Panel config was additionally modeled on the known-good 2019 Kali image
(`planet/linux.img`, read on macOS via Homebrew `debugfs`): classic
`mainmenu` first in an explicit `plugins=` list under `[panel1]` in
`~/.config/lxqt/panel.conf`. Note `lxqt-panel` does **not** hot-reload its
config — restart it (with the session's env from
`/proc/$(pgrep lxqt-session)/environ` if done over SSH).

**HiDPI:** 2160×1080 at ~6" needs scaling — `.xinitrc` exports
`QT_SCALE_FACTOR=1.5` and `XCURSOR_SIZE=36`; panel `panelSize=48`,
`iconSize=36`. **Captured into the build 2026-07-20**: `.xinitrc` was
already staged via `rootfs-files/xinitrc` in `mkrootfs.sh`, but
`~/.config/lxqt/panel.conf` was only ever a live edit — every rootfs
reflash silently regenerated stock defaults (`iconSize=22`,
`panelSize=32`, `fancymenu` instead of `mainmenu`) with no error or
warning. Now staged as `rootfs-files/panel.conf` and copied for both
users in `mkrootfs.sh`. Lesson: a finding written here in prose is not
the same as a captured build input — check `mkrootfs.sh`/`rootfs-files/`
directly when verifying a fix survived a reflash, don't just trust that
documenting it here was enough.

**X-exit console damage (recurring):** killing Xorg leaves (a) the
matrix-keypad driver with stuck-pressed keys — new presses are swallowed,
only release events emitted; fix by rebinding: `echo keyboard >
/sys/bus/platform/drivers/matrix-keypad/unbind` then `bind` — and (b) tty1
echo off, where `stty sane` was not sufficient but `systemctl restart
getty@tty1` is. A durable fix candidate: flush pressed-key state in the
`input/0001` polled driver's close/disconnect path.

**Users:** `gemini` user created (uid 1000, groups video/input/audio/plugdev,
password `gemini`, own `.xinitrc`) but has no LXQt config yet — desktop has
only been run as root so far. The rootfs also predated the mkrootfs.sh
gemini-user provisioning, and the baked-in Mac SSH key does not match the
Mac's current key (password auth in use).
