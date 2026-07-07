#!/usr/bin/env python3
"""Patch only the Android boot.img header cmdline field of a known-good
vendor boot.img (e.g. planet/kali_boot.img), leaving kernel and ramdisk
untouched. Used to test whether printk.disable_uart=1 (observed in the LK
boot log's merged cmdline, not present in this header field or the DTB
bootargs) can be overridden at this layer -- see boot.md for the B-13
vendor-log investigation this supports.

Usage:
    patch-vendor-cmdline.py --in planet/kali_boot.img --out OUTPUT/vendor-uart-test.img \\
        --append "printk.disable_uart=0 ignore_loglevel"
"""
import argparse
import struct
import sys

CMDLINE_OFF = 64
CMDLINE_LEN = 512


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--in", dest="inp", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--append", required=True, help="text appended to the existing header cmdline")
    args = ap.parse_args()

    with open(args.inp, "rb") as f:
        data = bytearray(f.read())

    if data[0:8] != b"ANDROID!":
        sys.exit(f"not an Android boot image (magic={bytes(data[0:8])!r})")

    field = bytes(data[CMDLINE_OFF:CMDLINE_OFF + CMDLINE_LEN])
    old = field.split(b"\x00", 1)[0].decode()
    new = (old + " " + args.append).encode()
    if len(new) >= CMDLINE_LEN:
        sys.exit(f"new cmdline too long: {len(new)} >= {CMDLINE_LEN}")

    newfield = new + b"\x00" * (CMDLINE_LEN - len(new))
    data[CMDLINE_OFF:CMDLINE_OFF + CMDLINE_LEN] = newfield

    with open(args.out, "wb") as f:
        f.write(data)

    print(f"wrote {args.out}: {len(data)} bytes")
    print(f"  old cmdline={old!r}")
    print(f"  new cmdline={new.decode()!r}")


if __name__ == "__main__":
    main()
