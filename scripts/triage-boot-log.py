#!/usr/bin/env python3
"""Compact single-pass triage of a Gemini serial boot log.

Replaces the usual ad-hoc chain of grep/tail calls (banner check, panic
scan, DEVAPC/MPU violation counts, HARVEST- trace counts, reboot
detection, tail) with one pass that prints a short fixed-format report.

Usage: triage-boot-log.py <logfile> [--tail N] [--context N]
"""
import argparse
import re
import sys

PANIC_PATTERNS = [
    (re.compile(rb"Kernel panic"), "Kernel panic"),
    (re.compile(rb"Internal error:"), "Internal error"),
    (re.compile(rb"Unable to handle"), "Unable to handle (fault)"),
    (re.compile(rb"^BUG: failure at", re.M), "BUG: failure"),
    (re.compile(rb"Oops"), "Oops"),
]

MILESTONES = [
    (rb"Preloader Start", "Preloader Start"),
    (rb"Linux version", "Kernel banner"),
    (rb"init: init first stage started", "Android init: first stage"),
    (rb"Welcome to.*Kali|Welcome to.*Debian", "Userspace welcome banner"),
    (rb"systemd\[1\]: Startup finished", "systemd startup finished"),
    (rb"login:", "getty login prompt"),
]


def decode_lines(raw: bytes):
    text = raw.decode("utf-8", errors="replace")
    return text.split("\n")


def find_all(lines, pattern_bytes):
    pat = re.compile(pattern_bytes)
    hits = []
    for i, line in enumerate(lines):
        if pat.search(line.encode("utf-8", errors="replace")):
            hits.append(i)
    return hits


def ts_of(line):
    m = re.match(r"\[\s*(\d+\.\d+)\]", line)
    return m.group(1) if m else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("logfile")
    ap.add_argument("--tail", type=int, default=25)
    ap.add_argument("--context", type=int, default=12)
    args = ap.parse_args()

    with open(args.logfile, "rb") as f:
        raw = f.read()
    lines = decode_lines(raw)
    n = len(lines)

    print(f"=== triage: {args.logfile} ({n} lines, {len(raw)} bytes) ===")

    # Reboot boundaries
    preloader_hits = find_all(lines, rb"Preloader Start")
    banner_hits = find_all(lines, rb"Linux version")
    if len(preloader_hits) > 1:
        print(f"\n[REBOOTS] {len(preloader_hits)} boot cycles detected "
              f"(Preloader Start at lines {[h+1 for h in preloader_hits]})")
    else:
        print("\n[REBOOTS] single boot cycle")

    if banner_hits:
        for h in banner_hits:
            print(f"[BANNER] L{h+1}: {lines[h].strip()}")
    else:
        print("[BANNER] no 'Linux version' line found")

    # Milestones (last boot cycle only, i.e. after the last banner)
    start = banner_hits[-1] if banner_hits else 0
    print("\n[MILESTONES] (last boot cycle)")
    for pat, label in MILESTONES:
        hits = [h for h in find_all(lines, pat) if h >= start]
        if hits:
            ts = ts_of(lines[hits[0]])
            tsinfo = f" t={ts}s" if ts else ""
            print(f"  reached: {label} (L{hits[0]+1}{tsinfo})")
        else:
            print(f"  NOT reached: {label}")

    # Panics
    print("\n[PANIC/BUG SCAN] (last boot cycle)")
    any_panic = False
    for pat, label in PANIC_PATTERNS:
        hits = [h for h in find_all(lines, pat.pattern) if h >= start]
        if hits:
            any_panic = True
            first = hits[0]
            ts = ts_of(lines[first])
            tsinfo = f" t={ts}s" if ts else ""
            print(f"  {label}: {len(hits)} occurrence(s), first at L{first+1}{tsinfo}")
            lo = max(start, first - args.context)
            hi = min(n, first + args.context + 1)
            print(f"  --- context L{lo+1}-{hi} ---")
            for i in range(lo, hi):
                marker = ">>" if i == first else "  "
                print(f"  {marker} {lines[i]}")
            print("  ---")
    if not any_panic:
        print("  none found")

    # Violation counts
    print("\n[VIOLATION COUNTS] (last boot cycle)")
    for pat, label in [(rb"DEVAPC", "DEVAPC"), (rb"MPU violation", "EMI MPU violation")]:
        hits = [h for h in find_all(lines, pat) if h >= start]
        if hits:
            ts = ts_of(lines[hits[0]])
            tsinfo = f" t={ts}s" if ts else ""
            print(f"  {label}: {len(hits)} occurrence(s), first at L{hits[0]+1}{tsinfo}")
        else:
            print(f"  {label}: 0")

    # HARVEST- trace summary
    harvest_types = {}
    for i in range(start, n):
        m = re.search(r"HARVEST-([A-Z-]+)", lines[i])
        if m:
            harvest_types[m.group(1)] = harvest_types.get(m.group(1), 0) + 1
    print("\n[HARVEST TRACE]")
    if harvest_types:
        for k, v in sorted(harvest_types.items()):
            print(f"  HARVEST-{k}: {v}")
    else:
        print("  none")

    # Tail
    print(f"\n[TAIL] last {args.tail} lines")
    for line in lines[-args.tail:]:
        print(f"  {line}")


if __name__ == "__main__":
    main()
