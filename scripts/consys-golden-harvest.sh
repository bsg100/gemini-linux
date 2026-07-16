#!/bin/sh
# consys-golden-harvest.sh — dump CONSYS-related registers on the RUNNING
# vendor 3.18 Kali stack (Stage W0b golden reference; research.md §CONSYS).
#
# Usage: run on the device (serial or SSH), once with WiFi OFF and once
# with WiFi ON (ifconfig wlan0 up / nmcli radio wifi on), redirecting
# output to a file each time:
#   sh consys-golden-harvest.sh > /tmp/consys-wifi-off.txt 2>&1
#   <bring WiFi up, confirm scan works>
#   sh consys-golden-harvest.sh > /tmp/consys-wifi-on.txt 2>&1
# Then scp both files off (or paste from serial log).
#
# Register list is source-cited in research.md "CONSYS Stage W0 harvest".
# The CONN-side registers (0x1807xxxx) are only sane to read while the
# CONN domain is powered (PWR_STATUS bit1 = 1); the script checks first
# and skips them if unpowered rather than risking a bus hang.

DEVMEM=""
for c in devmem devmem2 "busybox devmem"; do
    if $c 0x10006180 >/dev/null 2>&1; then DEVMEM="$c"; break; fi
done
[ -z "$DEVMEM" ] && { echo "FATAL: no working devmem/devmem2/busybox devmem"; exit 1; }

rd() { # rd <addr> <label>
    printf '%s %-14s = ' "$1" "$2"
    $DEVMEM "$1" 2>/dev/null || echo "READ-FAILED"
}

echo "=== consys-golden-harvest $(date) ==="
uname -a
echo "--- AP-side (always safe) ---"
rd 0x10006000 SPM_PWRON_CONFG_EN
rd 0x10006180 SPM_PWR_STATUS
rd 0x10006184 SPM_PWR_STATUS_2ND
rd 0x10006280 SPM_CONN_PWR_CON
rd 0x10001220 INFRA_TOPAXI_PROT_EN
rd 0x10001228 INFRA_TOPAXI_PROT_STA1
# Vendor maps "TOPCKGEN_BASE" = 0x10000000 len 0x2000 (spans topckgen AND
# infracfg_ao); offsets 0x1340/0x1350 therefore land at 0x1000134x.
rd 0x10001340 CONSYS_EMI_MAPPING
rd 0x10001350 CONN2AP_SLEEP_MASK
rd 0x10007018 AP_RGU_SWSYSRST

echo "--- CONN domain state check ---"
STATUS=$($DEVMEM 0x10006180)
echo "PWR_STATUS=$STATUS"
case "$STATUS" in
    *[2367ABEFabef])  CONN_ON=1 ;;  # low nibble bit1 set
    *) CONN_ON=0 ;;
esac
echo "CONN powered: $CONN_ON"

if [ "$CONN_ON" = "1" ]; then
    echo "--- CONN-side (powered) ---"
    rd 0x18070008 CONSYS_CHIP_ID        # expect 0x0279
    rd 0x18070110 MCU_CFG_ACR
else
    echo "CONN unpowered - skipping 0x1807xxxx reads"
fi

echo "--- PMIC VCN rails (vendor sysfs, best effort) ---"
for f in /sys/devices/platform/mt-pmic/pmic_access /proc/mtk_pmic_dbg; do
    [ -e "$f" ] && echo "found: $f"
done

echo "--- vendor WMT / WiFi state ---"
lsmod 2>/dev/null | head -20
dmesg | grep -iE "consys|wmt|wlan|WIFI" | tail -60
ls -la /dev/wmtWifi /dev/stpwmt /dev/mtk_stp_wmt 2>/dev/null
cat /proc/net/wireless 2>/dev/null
echo "=== end harvest ==="

# ---- W2/G2b additions (2026-07-14, build #240 session) ----
# Everything below was identified as decisive during the G2b live-debug:
# healthy CPUPCR idle pattern, BTIF host regs while the link works, the
# pwrap DCXO_CONN bridge, and the EMI ctrl window the ROM/FW writes.

echo "--- CPUPCR samples (10x, healthy-idle pattern reference) ---"
if [ "$CONN_ON" = "1" ]; then
    i=0; while [ $i -lt 10 ]; do rd 0x18070160 CPUPCR; i=$((i+1)); done
    rd 0x18070000 MCU_HW_VER
    rd 0x18070004 MCU_FW_VER
    rd 0x18070114 MCU_CFG_0x114
    rd 0x18070120 MCU_CFG_0x120
else
    echo "CONN unpowered - skipped"
fi

echo "--- BTIF host block 0x1100C000 ---"
rd 0x1100C004 BTIF_IER
rd 0x1100C00c BTIF_FAKELCR
rd 0x1100C014 BTIF_LSR
rd 0x1100C048 BTIF_SLEEP_EN
rd 0x1100C04c BTIF_DMA_EN
rd 0x1100C054 BTIF_RTOCNT
rd 0x1100C060 BTIF_TRI_LVL
rd 0x1100C064 BTIF_WAK
rd 0x1100C068 BTIF_WAT_TIME
rd 0x1100C06c BTIF_HANDSHAKE

echo "--- pwrap DCXO_CONN bridge (0x1000D000 base) ---"
rd 0x1000D18C DCXO_ENABLE
rd 0x1000D190 DCXO_CONN_ADR0
rd 0x1000D194 DCXO_CONN_WDATA0
rd 0x1000D198 DCXO_CONN_ADR1
rd 0x1000D19C DCXO_CONN_WDATA1

echo "--- misc AP-side ---"
rd 0x10001f00 AP2CONN_OSC_EN
rd 0x10005600 AP_UART_USB_MUX

echo "--- PMIC DCXO CW00/CW13/CW14 (vendor pmic_access if present) ---"
PA=/sys/devices/platform/mt-pmic/pmic_access
if [ -w "$PA" ]; then
    for r in 0x7000 0x701A 0x701C; do
        echo "$r" > "$PA"; printf 'PMIC %s = ' "$r"; cat "$PA"
    done
else
    echo "pmic_access not writable/found - skipped"
fi

echo "--- EMI ctrl window (first 0x50 bytes at consys EMI base + 0x80000) ---"
EMIMAP=$($DEVMEM 0x10001340 2>/dev/null)
echo "CONSYS_EMI_MAPPING=$EMIMAP"
# remap word: bits[11:0] = phys base >> 20 (bit12 is an enable flag)
base=$(( (EMIMAP & 0xFFF) << 20 ))
printf 'decoded consys EMI base = 0x%x\n' $base
if [ $base -gt 0 ]; then
    o=0
    while [ $o -lt 80 ]; do
        printf '  ctrl+0x%x: ' $o; $DEVMEM $(( base + 0x80000 + o )) 2>/dev/null || echo "READ-FAILED"
        o=$((o+4))
    done
else
    echo "EMI remap not programmed - skipped"
fi
echo "=== end W2 additions ==="
