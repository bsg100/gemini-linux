#!/usr/bin/env python3
"""Pack a new Android boot.img (v0 header) for the Gemini boot2 partition,
reusing the known-good kali_boot.img's header fields and ramdisk, but with
our Linux 6.6 Image.gz + appended DTB as the kernel blob.

Header layout and field values are sourced from boot.md "Android boot image
header (boot2 / kali_boot.img)" -- verified against planet/kali_boot.img by
direct hex inspection (2026-07-04): standard AOSP v0 header, no MTK wrapper.

Usage:
    pack-boot-img.py --reference planet/kali_boot.img \\
        --kernel OUTPUT/Image.gz --dtb OUTPUT/mt6797-gemini-pda.dtb \\
        --out new_kali_boot.img
"""
import argparse
import struct
import sys

HEADER_SIZE = 608  # up to end of extra_cmdline; rest of page is zero padding


def pad(data: bytes, page_size: int) -> bytes:
    rem = len(data) % page_size
    if rem == 0:
        return data
    return data + b"\x00" * (page_size - rem)


def parse_header(buf: bytes):
    magic = buf[0:8]
    if magic != b"ANDROID!":
        raise ValueError(f"not an Android boot image (magic={magic!r})")
    (kernel_size, kernel_addr,
     ramdisk_size, ramdisk_addr,
     second_size, second_addr,
     tags_addr, page_size,
     header_version, os_version) = struct.unpack_from("<10I", buf, 8)
    name = buf[48:64]
    cmdline = buf[64:576]
    ids = buf[576:608]
    return dict(
        kernel_size=kernel_size, kernel_addr=kernel_addr,
        ramdisk_size=ramdisk_size, ramdisk_addr=ramdisk_addr,
        second_size=second_size, second_addr=second_addr,
        tags_addr=tags_addr, page_size=page_size,
        header_version=header_version, os_version=os_version,
        name=name, cmdline=cmdline, ids=ids,
    )


def extract_ramdisk(buf: bytes, hdr: dict) -> bytes:
    page_size = hdr["page_size"]
    kernel_pages = (hdr["kernel_size"] + page_size - 1) // page_size
    ramdisk_off = page_size + kernel_pages * page_size
    return buf[ramdisk_off:ramdisk_off + hdr["ramdisk_size"]]


def build_header(hdr: dict, new_kernel_size: int) -> bytes:
    h = bytearray(hdr["page_size"])
    h[0:8] = b"ANDROID!"
    struct.pack_into(
        "<10I", h, 8,
        new_kernel_size, hdr["kernel_addr"],
        hdr["ramdisk_size"], hdr["ramdisk_addr"],
        hdr["second_size"], hdr["second_addr"],
        hdr["tags_addr"], hdr["page_size"],
        hdr["header_version"], hdr["os_version"],
    )
    h[48:64] = hdr["name"]
    h[64:576] = hdr["cmdline"]
    h[576:608] = hdr["ids"]
    return bytes(h)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--reference", required=True, help="known-good boot.img to copy header/ramdisk from")
    ap.add_argument("--kernel", required=True, help="Image.gz")
    ap.add_argument("--dtb", required=True, help="board DTB, appended after Image.gz")
    ap.add_argument("--out", required=True)
    ap.add_argument("--kernel-addr", type=lambda s: int(s, 0), default=None,
                     help="override the header's kernel load address (must be 2MB-aligned "
                          "for mainline arm64 kernels -- see boot.md 'Image load offset' finding)")
    args = ap.parse_args()

    with open(args.reference, "rb") as f:
        ref = f.read()
    hdr = parse_header(ref)
    if args.kernel_addr is not None:
        if args.kernel_addr % (2 * 1024 * 1024) != 0:
            sys.exit(f"--kernel-addr 0x{args.kernel_addr:x} is not 2MB-aligned")
        hdr["kernel_addr"] = args.kernel_addr
    ramdisk = extract_ramdisk(ref, hdr)
    if len(ramdisk) != hdr["ramdisk_size"]:
        sys.exit(f"ramdisk extraction size mismatch: got {len(ramdisk)}, expected {hdr['ramdisk_size']}")

    with open(args.kernel, "rb") as f:
        kernel = f.read()
    with open(args.dtb, "rb") as f:
        dtb = f.read()
    kernel_blob = kernel + dtb

    page_size = hdr["page_size"]
    out = bytearray()
    out += build_header(hdr, len(kernel_blob))
    out += pad(kernel_blob, page_size)
    out += pad(ramdisk, page_size)
    # second_size is 0 in the reference image; nothing to append.

    with open(args.out, "wb") as f:
        f.write(out)

    print(f"wrote {args.out}: {len(out)} bytes")
    print(f"  kernel blob: {len(kernel_blob)} bytes (Image.gz {len(kernel)} + dtb {len(dtb)})")
    print(f"  ramdisk: {len(ramdisk)} bytes (copied unchanged from {args.reference})")
    print(f"  page_size={page_size} kernel_addr=0x{hdr['kernel_addr']:x} "
          f"ramdisk_addr=0x{hdr['ramdisk_addr']:x} tags_addr=0x{hdr['tags_addr']:x}")
    print(f"  cmdline={hdr['cmdline'].split(b'\\x00', 1)[0].decode()!r}")


if __name__ == "__main__":
    main()
