#!/bin/bash
# Test script for Gemini PDA keyboard matrix via gpio-matrix-keypad + AW9523B.
# Run on device after AW9523B GPIO driver and keyboard DTS node are both enabled.
#
# Prerequisites:
#   - AW9523B GPIO driver test (test-aw9523b.sh) must pass first
#   - keyboard node enabled in DTS
#   - evtest package installed

set -euo pipefail

echo "=== Gemini PDA keyboard matrix test ==="

# 1. Find keyboard input device
echo "[1] Locating keyboard input device"
KBD_DEV=""
for dev in /dev/input/event*; do
    [ -e "$dev" ] || continue
    NAME=$(cat "/sys/class/input/$(basename "$dev")/device/name" 2>/dev/null || true)
    if echo "$NAME" | grep -qi "matrix\|keyboard\|aw9523"; then
        KBD_DEV="$dev"
        echo "     Found: $NAME at $dev"
        break
    fi
done

if [ -z "$KBD_DEV" ]; then
    echo "FAIL: no keyboard input device found"
    echo "  Check: dmesg | grep -i 'matrix\|aw9523\|keyboard'"
    echo "  Check: cat /proc/bus/input/devices"
    exit 1
fi
echo "PASS: keyboard device found at $KBD_DEV"

# 2. Check key capabilities.
# NOTE: under `set -e` a bare failing command aborts the script before any
# `$?` test runs, so the query must be the condition of an `if`.
echo "[2] Key capabilities (EV_KEY must be present)"
if ! evtest --query "$KBD_DEV" EV_KEY KEY_A 2>/dev/null; then
    echo "FAIL: KEY_A not in keyboard capabilities"
    exit 1
fi
echo "PASS: EV_KEY / KEY_A supported"

# 3. Interactive test prompt
echo ""
echo "[3] Interactive key test"
echo "     Press keys on the Gemini keyboard. Ctrl+C to stop."
echo "     Expected: all alpha keys, digits 0-9, space, enter, backspace,"
echo "               arrows, shift, ctrl, alt, fn"
echo ""
evtest "$KBD_DEV"
