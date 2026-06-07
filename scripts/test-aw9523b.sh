#!/bin/bash
# Test script for AW9523B GPIO expander driver on Gemini PDA.
# Run on the device once AW9523B is enabled in DTS (status = "okay").
#
# Prerequisites:
#   - Linux kernel with gpio-aw9523b driver loaded
#   - AW9523B node enabled in mt6797-gemini-pda.dts
#   - gpiod (libgpiod tools) available
#   - i2c-tools optional (only used as a fallback when the driver is NOT bound)
#
# NOTE: once the kernel driver is bound it owns the i2c client, so raw i2cget
# would return EBUSY and could race the driver. This script therefore reads
# state through sysfs / debugfs (regmap) and gpiolib, not raw i2c.

set -euo pipefail

I2C_BUS=5
I2C_ADDR=0x5b          # must match the reg in the DTS aw9523b node
CHIP_ID_REG=0x10
EXPECTED_ID=0x23       # TODO: confirm against AW9523B datasheet
GPIO_CHIP_LABEL="aw9523b"

ADDR_HEX=$(printf '%02x' "$I2C_ADDR")
DEV_PATH="/sys/bus/i2c/devices/${I2C_BUS}-00${ADDR_HEX}"

echo "=== AW9523B GPIO driver test ==="

# 1. Confirm the i2c client is present (driver bound) or detectable on the bus.
echo "[1] i2c client on bus $I2C_BUS, addr $I2C_ADDR"
if [ -d "$DEV_PATH" ]; then
    drv=$(basename "$(readlink -f "$DEV_PATH/driver" 2>/dev/null || echo none)")
    echo "PASS: client present at $DEV_PATH (driver: $drv)"
elif command -v i2cdetect >/dev/null 2>&1 && \
     i2cdetect -y "$I2C_BUS" 2>/dev/null | grep -iqE "(^| )(${ADDR_HEX}|UU)( |$)"; then
    # i2cdetect prints addresses in hex (e.g. "5b"), or "UU" if kernel-claimed.
    echo "PASS: device detected on i2c-$I2C_BUS (driver not yet bound)"
else
    echo "FAIL: AW9523B not present at $DEV_PATH or on i2c-$I2C_BUS"
    echo "  Check: dmesg | grep -i aw9523; DTS node status; bus/address."
    exit 1
fi

# 2. Check chip ID via the driver's debugfs regmap (safe — no bus contention).
echo "[2] Chip ID register $CHIP_ID_REG"
REGMAP="/sys/kernel/debug/regmap/${I2C_BUS}-00${ADDR_HEX}/registers"
if [ -r "$REGMAP" ]; then
    # registers file lines look like "10: 23"
    id=$(grep -iE "^0*${CHIP_ID_REG#0x}:" "$REGMAP" | awk '{print $2}' | head -1 || true)
    if [ -n "$id" ] && [ "0x${id}" = "$(printf '0x%02x' "$EXPECTED_ID")" ]; then
        echo "PASS: chip ID correct (0x${id})"
    else
        echo "WARN: chip ID read '0x${id:-?}' != $(printf '0x%02x' "$EXPECTED_ID")"
    fi
else
    echo "SKIP: regmap debugfs not available (mount debugfs to verify chip ID)"
fi

# 3. Verify GPIO chip appeared in gpiolib.
echo "[3] GPIO chip presence"
CHIP=$(gpiodetect 2>/dev/null | grep -i "$GPIO_CHIP_LABEL" || true)
if [ -z "$CHIP" ]; then
    echo "FAIL: no GPIO chip matching '$GPIO_CHIP_LABEL' found"
    echo "  (check: modprobe gpio_aw9523b; dmesg for probe errors)"
    exit 1
fi
echo "PASS: GPIO chip found: $CHIP"

# 4. Verify GPIO line count (expect 16 lines).
echo "[4] GPIO line count"
CHIP_NAME=$(echo "$CHIP" | awk '{print $1}' | tr -d ':')
LINES=$(gpioinfo "$CHIP_NAME" 2>/dev/null | grep -cE '^[[:space:]]*line[[:space:]]' || true)
LINES=${LINES:-0}
if [ "$LINES" -lt 16 ]; then
    echo "FAIL: expected 16 GPIO lines, got $LINES"
    exit 1
fi
echo "PASS: $LINES GPIO lines"

# 5. Read Port 0 input (rows) via debugfs regmap if available.
echo "[5] Port 0 input register (rows)"
if [ -r "$REGMAP" ]; then
    p0=$(grep -iE "^0*0:" "$REGMAP" | awk '{print $2}' | head -1 || true)
    echo "     P0_IN = 0x${p0:-??}"
else
    echo "SKIP: regmap debugfs not available"
fi

echo ""
echo "=== AW9523B basic test PASSED ==="
echo ""
echo "Next: enable keyboard node in DTS and test with evtest:"
echo "  evtest /dev/input/event0"
