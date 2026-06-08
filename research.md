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
