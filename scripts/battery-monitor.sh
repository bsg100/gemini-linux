#!/bin/bash
# Userspace battery-voltage safety monitor for the Gemini PDA.
#
# The MT6351 PMIC's integrated fuel gauge (coulomb counter + AUXADC) has no
# mainline driver (blockers.md B-12), so there is no "Battery" power_supply
# and no capacity/SoC reporting. The only source of truth is the BQ25896
# charger's own V_BAT ADC, exposed by mainline drivers/power/supply/
# bq25890_charger.c as POWER_SUPPLY_PROP_VOLTAGE_NOW on the
# "bq25890-charger-*" power_supply (type USB, hardware.md Battery Charger
# row; research.md section 8 corrected this from the originally-assumed
# RT9466).
#
# This script polls that node and triggers a graceful shutdown when the
# charger is offline (VBUS/USB not present) and V_BAT drops below a safe
# floor, since there is no in-kernel low-battery shutdown without a fuel
# gauge (driver_ports.md "Risk" note under the MT6351 fuel gauge entry).
#
# Usage: battery-monitor.sh [--threshold-mv N] [--interval-s N] [--dry-run]

set -euo pipefail

THRESHOLD_MV=3400
INTERVAL_S=30
DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --threshold-mv) THRESHOLD_MV="$2"; shift 2 ;;
        --interval-s) INTERVAL_S="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        *) echo "unknown arg: $1" >&2; exit 1 ;;
    esac
done

find_charger_psy() {
    for ps in /sys/class/power_supply/bq25890-charger-*; do
        [ -d "$ps" ] && { echo "$ps"; return 0; }
    done
    return 1
}

PS_PATH=$(find_charger_psy) || {
    echo "battery-monitor: no bq25890-charger-* power_supply found; is the driver bound?" >&2
    exit 1
}

echo "battery-monitor: watching $PS_PATH (threshold ${THRESHOLD_MV}mV, every ${INTERVAL_S}s)"

while true; do
    if [ ! -d "$PS_PATH" ]; then
        PS_PATH=$(find_charger_psy) || {
            echo "battery-monitor: charger power_supply disappeared" >&2
            sleep "$INTERVAL_S"
            continue
        }
    fi

    ONLINE=$(cat "${PS_PATH}/online" 2>/dev/null || echo 0)
    VOLTAGE_UV=$(cat "${PS_PATH}/voltage_now" 2>/dev/null || echo 0)
    VOLTAGE_MV=$((VOLTAGE_UV / 1000))

    if [ "$ONLINE" = "1" ]; then
        : # charging or charger present — never shut down on voltage alone
    elif [ "$VOLTAGE_MV" -gt 0 ] && [ "$VOLTAGE_MV" -lt "$THRESHOLD_MV" ]; then
        logger -t battery-monitor "V_BAT ${VOLTAGE_MV}mV below ${THRESHOLD_MV}mV floor, charger offline — shutting down"
        echo "battery-monitor: V_BAT ${VOLTAGE_MV}mV < ${THRESHOLD_MV}mV, charger offline — shutting down"
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "battery-monitor: --dry-run, not calling shutdown"
        else
            shutdown -h now "battery-monitor: low voltage safety shutdown"
        fi
        exit 0
    fi

    sleep "$INTERVAL_S"
done
