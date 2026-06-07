#!/bin/bash
# Test display stack bring-up on Gemini PDA (MT6797, R63419 panel)
set -euo pipefail

PASS=0
FAIL=0
WARN=0

pass() { echo "[PASS] $*"; PASS=$((PASS+1)); }
fail() { echo "[FAIL] $*"; FAIL=$((FAIL+1)); }
warn() { echo "[WARN] $*"; WARN=$((WARN+1)); }

echo "=== Display bring-up tests ==="
echo

# 1. Check DRM subsystem loaded
echo "--- DRM / framebuffer ---"
if [ -d /sys/class/drm ]; then
    pass "DRM subsystem present"
else
    fail "DRM subsystem not found (/sys/class/drm missing)"
fi

# 2. Check for card device
CARD=$(ls /sys/class/drm/ 2>/dev/null | grep -E '^card[0-9]+$' | head -1 || true)
if [ -n "$CARD" ]; then
    pass "DRM card found: $CARD"
    echo "    Connectors:"
    ls /sys/class/drm/"$CARD"/ 2>/dev/null | grep -E 'DSI|HDMI|DP' | \
        while read c; do
            STATUS=$(cat /sys/class/drm/"$CARD"/"$c"/status 2>/dev/null || echo unknown)
            echo "      $c: $STATUS"
        done
else
    fail "No DRM card found — DRM driver not probed"
fi

# 3. Check framebuffer device
if ls /dev/fb* >/dev/null 2>&1; then
    pass "Framebuffer device present: $(ls /dev/fb*)"
else
    warn "No framebuffer device — may be normal if DRM-only KMS"
fi

# 4. Check MT6797 MMSYS driver
echo
echo "--- MT6797 MMSYS / display pipeline ---"
if grep -q "mediatek,mt6797-mmsys" /sys/bus/platform/devices/*/of_node/compatible \
        2>/dev/null || \
   ls /sys/bus/platform/drivers/mtk-mmsys/ 2>/dev/null | grep -q .; then
    pass "MMSYS driver bound"
else
    warn "MMSYS driver status unknown — check: ls /sys/bus/platform/drivers/mtk-mmsys/"
fi

# 5. Check DSI device
echo
echo "--- DSI ---"
if ls /sys/bus/platform/devices/1401c000.dsi* 2>/dev/null | grep -q .; then
    pass "DSI device 0x1401c000 found in sysfs"
else
    warn "DSI device not found — may not be enabled in DTS or driver not loaded"
fi

# 6. Check MIPI TX PHY
echo
echo "--- MIPI TX PHY ---"
if ls /sys/bus/platform/devices/10215000.mipi-dphy* 2>/dev/null | grep -q .; then
    pass "MIPI TX PHY device found (0x10215000)"
else
    warn "MIPI TX PHY not found — check DT node or PHY driver"
fi

# 7. Check panel driver
echo
echo "--- R63419 panel ---"
if grep -rq "r63419\|renesas,r63419" /sys/bus/*/devices/*/uevent 2>/dev/null; then
    pass "R63419 panel device found"
else
    warn "R63419 panel not found — expected on DSI bus after display enable"
fi

# 8. Check for display pipeline errors in dmesg
echo
echo "--- Kernel messages ---"
if dmesg 2>/dev/null | grep -qiE "mtk.drm|mtk.dsi|mmsys|r63419"; then
    echo "  Relevant dmesg lines:"
    dmesg 2>/dev/null | grep -iE "mtk.drm|mtk.dsi|mmsys|r63419" | tail -20 | \
        sed 's/^/    /'
else
    warn "No display-related dmesg output found"
fi

# 9. Optionally write to the framebuffer.
# This OVERWRITES whatever is on /dev/fb0 (possibly the live console), so it is
# opt-in via FB_WRITE_TEST=1. It writes only a few KB, so at most a thin band at
# the top of the panel changes — enough to confirm the pipeline accepts writes.
echo
echo "--- Framebuffer write test ---"
if [ "${FB_WRITE_TEST:-0}" != "1" ]; then
    warn "Skipping fb0 write test (set FB_WRITE_TEST=1 to enable; it overwrites the console)"
elif [ -e /dev/fb0 ]; then
    if dd if=/dev/urandom of=/dev/fb0 bs=4096 count=4 2>/dev/null; then
        pass "Framebuffer write OK"
        echo "  A band of random pixels at the top of the panel confirms writes reach fb0"
    else
        fail "Framebuffer write failed"
    fi
else
    warn "No /dev/fb0 — skipping write test"
fi

# Summary
echo
echo "=============================="
echo "Results: PASS=$PASS  WARN=$WARN  FAIL=$FAIL"
echo
if [ "$FAIL" -gt 0 ]; then
    echo "Display bring-up incomplete — see FAIL items above."
    echo "Check dmesg for bind/probe errors from mtk-drm, mtk-dsi, phy-mtk-mipi-dsi."
    exit 1
elif [ "$WARN" -gt 0 ]; then
    echo "Some checks inconclusive — hardware verification required."
    exit 0
else
    echo "All checks passed."
    exit 0
fi
