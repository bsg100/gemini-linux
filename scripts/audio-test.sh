#!/bin/sh
# audio-test.sh — first-light audio check for the Gemini PDA (build #267+).
# Run on the device as root: ./audio-test.sh
# Steps: verify ASoC card bound -> show codec/AFE dmesg -> unmute obvious
# output controls -> play a 3 s 440 Hz sine on each PCM playback device.
# POSIX sh (dash-safe); no bashisms so it runs on the minbase rootfs.
set -eu

echo "=== 1. Kernel/build ==="
uname -a

echo
echo "=== 2. ASoC card ==="
if ! aplay -l 2>/dev/null | grep -i card; then
    echo "FAIL: no ALSA playback card registered."
    echo "--- dmesg (asoc/afe/6351) ---"
    dmesg | grep -iE "asoc|afe|6351|scpsys|audio" | tail -30
    exit 1
fi

echo
echo "=== 3. Driver bind log ==="
dmesg | grep -iE "asoc|afe|6351" | tail -15 || true

echo
echo "=== 4. Routing (verified working 2026-07-19, build #267) ==="
# DPCM needs the frontend->backend path enabled by mixer, or playback
# fails with "no backend DAIs enabled for Playback_1":
#   DL1 frontend -> ADDA backend switches (mt6797-interconnection),
#   HPL/HPR Mux -> "Audio Playback" (item 2) for headphones
#   (item 1 "LoudSPK Playback" = speaker path, untested amp routing).
CARD=0
amixer -q -c "$CARD" sset 'ADDA_DL_CH1 DL1_CH1' on
amixer -q -c "$CARD" sset 'ADDA_DL_CH2 DL1_CH2' on
amixer -q -c "$CARD" cset name='HPL Mux' 2
amixer -q -c "$CARD" cset name='HPR Mux' 2
echo "routing set: DL1 -> ADDA -> headphone"

echo
echo "=== 5. Playback test (3 s sine per PCM) ==="
# Enumerate playback PCMs on card 0 and try each; success = no error and
# you HEAR a tone (speaker path may need the external amp -- try
# headphones if silent).
aplay -l | awk -v c="$CARD" '$0 ~ "^card "c":" {print $6}' | tr -d ':' | \
while read -r dev; do
    echo "--- hw:${CARD},${dev} ---"
    if speaker-test -D "hw:${CARD},${dev}" -c 2 -t sine -f 440 -l 1 -s 1 \
        >/dev/null 2>&1; then
        echo "PASS: hw:${CARD},${dev} accepted playback (did you hear it?)"
    else
        # retry mono/any-channel via plughw in case hw constraints bite
        if speaker-test -D "plughw:${CARD},${dev}" -c 2 -t sine -f 440 \
            -l 1 -s 1 >/dev/null 2>&1; then
            echo "PASS (plughw): hw:${CARD},${dev}"
        else
            echo "FAIL: hw:${CARD},${dev} would not play"
        fi
    fi
done

echo
echo "=== done. If every PCM PASSed but nothing was audible: plug in ==="
echo "=== headphones and re-run; speaker needs ext-amp routing work.  ==="
