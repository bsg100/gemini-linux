#!/bin/bash
# build-pack.sh — full Gemini kernel build/pack/provenance cycle (run on Mac).
#
# Usage: ./scripts/build-pack.sh <NN> <short-desc> [--dtb-grep <pattern>]
#   e.g. ./scripts/build-pack.sh 32 msdc0-vmmc-supply --dtb-grep vmmc-supply
#
# Does everything up to (but not including) flashing:
#   1. rsync patches/ + configs/ to the VM; drop the disabled display
#      fragment (B-13 guard).
#   2. In the VM: reset kernel tree, apply patches, config, build.
#   3. In the VM: pack new_kali_boot.img; copy .config/System.map to OUTPUT.
#   4. On Mac: create logs/YYYY-MM-DD-NN-<desc>/ provenance dir, copy
#      artifacts, print sha256.
#   5. Verify the packed kernel: banner present, display driver absent;
#      optional DTB grep.
#   6. Print flash + capture commands (absolute paths).
#
# Prereq: the build VM is running (~/gemini-build/vm/start-vm.sh).

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
VM="ssh -p 5522 root@localhost"
OUT="$HOME/gemini-build/OUTPUT"

NN="${1:?usage: build-pack.sh <NN> <short-desc> [--dtb-grep <pattern>]}"
DESC="${2:?usage: build-pack.sh <NN> <short-desc> [--dtb-grep <pattern>]}"
DTB_GREP=""
if [ "${3:-}" = "--dtb-grep" ]; then
    DTB_GREP="${4:?--dtb-grep needs a pattern}"
fi

DATE="$(date +%Y-%m-%d)"
PROV="$REPO/logs/$DATE-$NN-$DESC"
NEXT=$((10#$NN + 1))

echo "==> [1/6] Syncing patches/ and configs/ to VM"
rsync -a --delete "$REPO/patches/" root@localhost:'~/gemini_linux/patches/' -e "ssh -p 5522"
rsync -a "$REPO/configs/" root@localhost:'~/gemini_linux/configs/' -e "ssh -p 5522"
$VM 'rm -f ~/gemini_linux/configs/gemini-display.config'   # B-13 guard

echo "==> [2/6] Reset kernel tree, patch, config, build (VM)"
$VM 'cd ~/linux-6.6 && git checkout -- . && git clean -fdq -- Documentation arch drivers'
$VM 'cd ~/gemini_linux && ./scripts/build.sh patch && ./scripts/build.sh config'
$VM 'cd ~/gemini_linux && ./scripts/build.sh build' 2>&1 | tail -3

echo "==> [3/6] Packing boot image (VM)"
$VM 'python3 ~/gemini_linux/scripts/pack-boot-img.py \
        --reference ~/gemini_linux/planet/kali_boot.img \
        --kernel ~/linux-6.6/arch/arm64/boot/Image.gz \
        --dtb ~/linux-6.6/arch/arm64/boot/dts/mediatek/mt6797-gemini-pda.dtb \
        --out /mnt/host/OUTPUT/new_kali_boot.img \
        --kernel-addr 0x40200000 \
     && cp ~/linux-6.6/.config /mnt/host/OUTPUT/config-latest \
     && cp ~/linux-6.6/System.map /mnt/host/OUTPUT/System.map-latest'

if [ -n "$DTB_GREP" ]; then
    echo "==> DTB grep: '$DTB_GREP'"
    $VM "dtc -I dtb -O dts ~/linux-6.6/arch/arm64/boot/dts/mediatek/mt6797-gemini-pda.dtb 2>/dev/null | grep -n '$DTB_GREP'" \
        || { echo "ERROR: '$DTB_GREP' not found in built DTB"; exit 1; }
fi

echo "==> [4/6] Provenance dir: $PROV"
mkdir -p "$PROV"
cp "$OUT/new_kali_boot.img" "$PROV/"
cp "$OUT/config-latest"     "$PROV/config"
cp "$OUT/System.map-latest" "$PROV/System.map"
shasum -a 256 "$PROV/new_kali_boot.img"

echo "==> [5/6] Verifying packed kernel"
python3 - "$PROV/new_kali_boot.img" <<'EOF'
import re, sys, zlib
d = open(sys.argv[1], 'rb').read()
i = d.find(b'\x1f\x8b\x08')
if i < 0:
    sys.exit("ERROR: no gzip kernel found in image")
k = zlib.decompressobj(31).decompress(d[i:])
m = re.search(rb'#\d+ SMP PREEMPT [^\x00]*UTC \d{4}', k)
if not m:
    sys.exit("ERROR: no kernel banner in decompressed image")
print("    banner:", m.group().decode())
import os
if b'GEMINI-DEBUG' in k:
    if os.environ.get('ALLOW_DEBUG') == '1':
        print("    WARNING: GEMINI-DEBUG instrumentation present (ALLOW_DEBUG=1 — deliberate debug build)")
    else:
        sys.exit("ERROR: GEMINI-DEBUG instrumentation present — debug patches were removed 2026-07-05 (build #39); set ALLOW_DEBUG=1 for a deliberate debug build")
if b'r63419' in k:
    sys.exit("ERROR: display driver present — headless build expected (B-13)")
print("    debug instrumentation absent, display absent: OK")
EOF

echo "==> [6/6] Next steps (do not flash with mtk wl — targeted writes only)"
cat <<EOF

Flash (device in preloader mode):
  /tmp/mtk-venv/bin/python3 ~/mtkclient/mtk.py w boot  $PROV/new_kali_boot.img
  /tmp/mtk-venv/bin/python3 ~/mtkclient/mtk.py w boot2 $PROV/new_kali_boot.img

Capture:
  cd $REPO
  python3 scripts/ftdi-monitor.py --log logs/$DATE-$NEXT-$DESC-boot.log

Then: verify the banner in the capture matches the one above, add a boot.md
entry (link log, sha256, flash commands, outcome), update blockers.md.
EOF
