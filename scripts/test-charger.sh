#!/bin/bash
# Test script for RT9466/RT9467 battery charger driver on Gemini PDA.
# Run on device once charger node is enabled in DTS.
#
# Prerequisites:
#   - Linux kernel with richtek,rt9467 driver (drivers/power/supply/rt9467.c)
#   - charger node enabled in mt6797-gemini-pda.dts
#   - i2c-tools installed

set -euo pipefail

# NOTE: the DTS currently declares this node compatible = "richtek,rt9467" at
# 0x53. RT9466 is the part normally at 0x53 (RT9467 is usually 0x5b). The
# device ID read below distinguishes them (0x8x = RT9466, 0x9x = RT9467);
# reconcile the DTS compatible/address with whatever ID is reported here.
I2C_BUS=0
I2C_ADDR=0x53
DEV_ID_REG=0x00

ADDR_HEX=$(printf '%02x' "$I2C_ADDR")
DEV_PATH="/sys/bus/i2c/devices/${I2C_BUS}-00${ADDR_HEX}"

echo "=== RT9466/RT9467 charger driver test ==="

# 1. I2C client present (driver bound) or detectable on the bus.
echo "[1] i2c client on bus $I2C_BUS, addr $I2C_ADDR"
if [ -d "$DEV_PATH" ]; then
    echo "PASS: client present at $DEV_PATH"
elif command -v i2cdetect >/dev/null 2>&1 && \
     i2cdetect -y "$I2C_BUS" 2>/dev/null | grep -iqE "(^| )(${ADDR_HEX}|UU)( |$)"; then
    echo "PASS: device detected on i2c-$I2C_BUS"
else
    echo "FAIL: RT9466/RT9467 not present at $DEV_PATH or on i2c-$I2C_BUS"
    exit 1
fi

# 2. Read device ID (best-effort: only when the driver has NOT claimed the bus).
echo "[2] Device ID"
ID=""
if command -v i2cget >/dev/null 2>&1; then
    ID=$(i2cget -y "$I2C_BUS" "$I2C_ADDR" "$DEV_ID_REG" b 2>/dev/null || true)
fi
if [ -n "$ID" ]; then
    ID_DEC=$((ID))
    echo "     Device ID: $ID"
    if [ "$((ID_DEC & 0xF0))" -eq "$((0x80))" ]; then
        echo "     Chip: RT9466"
    elif [ "$((ID_DEC & 0xF0))" -eq "$((0x90))" ]; then
        echo "     Chip: RT9467"
    else
        echo "WARN: unexpected device ID $ID — check compatible string in DTS"
    fi
else
    echo "SKIP: could not read ID over i2c (driver may own the bus); use dmesg"
fi

# 3. Check power_supply sysfs
echo "[3] power_supply subsystem"
PS_PATH=""
for ps in /sys/class/power_supply/*/; do
    TYPE=$(cat "${ps}type" 2>/dev/null || true)
    if [ "$TYPE" = "USB" ] || [ "$TYPE" = "Mains" ]; then
        PS_PATH="$ps"
        break
    fi
done

if [ -z "$PS_PATH" ]; then
    echo "WARN: no USB/Mains power_supply found (charger may not be fully probed)"
    echo "  Check: dmesg | grep -i 'rt9466\|rt9467\|charger'"
else
    echo "PASS: power_supply found at $PS_PATH"
    echo "     status:  $(cat "${PS_PATH}status" 2>/dev/null || echo n/a)"
    echo "     online:  $(cat "${PS_PATH}online" 2>/dev/null || echo n/a)"
fi

# 4. Check for battery power_supply
echo "[4] Battery power_supply"
BAT_PATH=""
for ps in /sys/class/power_supply/*/; do
    TYPE=$(cat "${ps}type" 2>/dev/null || true)
    if [ "$TYPE" = "Battery" ]; then
        BAT_PATH="$ps"
        break
    fi
done

if [ -n "$BAT_PATH" ]; then
    echo "PASS: battery found at $BAT_PATH"
    echo "     capacity: $(cat "${BAT_PATH}capacity" 2>/dev/null || echo n/a)%"
    echo "     status:   $(cat "${BAT_PATH}status" 2>/dev/null || echo n/a)"
else
    echo "INFO: no battery power_supply (fuel gauge not yet enabled)"
fi

echo ""
echo "=== RT9466/RT9467 charger test complete ==="
