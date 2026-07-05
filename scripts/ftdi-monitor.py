#!/usr/bin/env python3
"""Raw serial monitor for Gemini PDA console bring-up.

Logs every received byte to --log as raw bytes (unmodified — this is the
evidentiary capture). By default, also streams decoded text to the
terminal as it arrives, so you can read the boot log live. Listen-only by
default — safe to leave attached to the Gemini (never transmits toward the
preloader).

    /tmp/ftdi-venv/bin/python scripts/ftdi-monitor.py [--baud 921600] [--beacon]

--hexdump: print timestamped hex + ASCII chunks instead of streamed text.
Slower to read but shows raw byte activity even at the wrong baud rate
(garbage on screen = electrical activity; true silence = wiring problem).
Use this if you suspect a baud/wiring issue rather than a boot log read.

--beacon: transmit a test pattern once per second. ONLY for loopback
testing (D+ pad shorted to D− pad on the breakout) — do NOT use while
wired to the Gemini.

--interactive: full serial terminal — keystrokes are forwarded to the
device (so you can log in and use a shell) while every received byte is
still written raw to --log. Output is rendered as plain text instead of
hex dumps. Exit with Ctrl-]. The port is exclusive, so this replaces
running a separate tty session (screen/minicom) alongside a capture.
Only use once Linux is up — do not type at the preloader/LK.
"""

import argparse
import datetime
import glob
import os
import select
import sys
import time

import serial


def find_port():
    ports = sorted(glob.glob("/dev/cu.usbserial*"))
    if not ports:
        sys.exit("No /dev/cu.usbserial* device found")
    return ports[0]


def interactive(ser, logf):
    """Raw serial terminal: stdin -> serial, serial -> stdout (+ raw log)."""
    import termios
    import tty

    ser.timeout = 0                    # select() gates reads; don't block in read()
    fd = sys.stdin.fileno()
    saved = termios.tcgetattr(fd)
    print("Interactive mode — Ctrl-] to exit.")
    total = 0
    try:
        tty.setraw(fd)
        while True:
            r, _, _ = select.select([fd, ser.fileno()], [], [])
            if fd in r:
                ch = os.read(fd, 1024)
                if b"\x1d" in ch:          # Ctrl-]
                    break
                ser.write(ch)
            if ser.fileno() in r:
                data = ser.read(4096)
                if data:
                    total += len(data)
                    os.write(sys.stdout.fileno(), data)
                    if logf:
                        logf.write(data)
                        logf.flush()
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)
    return total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default=None)
    ap.add_argument("--baud", type=int, default=921600)
    ap.add_argument("--beacon", action="store_true",
                    help="TX test pattern 1/s — loopback test only, never on the Gemini")
    ap.add_argument("--hexdump", action="store_true",
                    help="print timestamped hex+ASCII chunks instead of streamed text "
                         "(useful for wrong-baud/wiring diagnosis; raw --log is unaffected)")
    ap.add_argument("--log", default=None, help="also write raw bytes to this file (truncated by default)")
    ap.add_argument("--append", action="store_true",
                    help="append to --log instead of truncating (resuming an interrupted capture)")
    ap.add_argument("--interactive", action="store_true",
                    help="serial terminal: forward keystrokes to the device, plain-text output, "
                         "raw bytes still logged; Ctrl-] exits (Linux console only, not preloader/LK)")
    args = ap.parse_args()

    if args.beacon and args.interactive:
        sys.exit("--beacon and --interactive are mutually exclusive")

    port = args.port or find_port()
    logf = open(args.log, "ab" if args.append else "wb") if args.log else None
    print(f"Listening on {port} @ {args.baud} baud"
          + (" with TX beacon (loopback mode)" if args.beacon else " (listen-only)")
          + (", hexdump mode" if args.hexdump else ", streaming text"))
    print("Ctrl-C to stop. Waiting for bytes...")

    total = 0
    last_beacon = 0.0
    with serial.Serial(port, args.baud, timeout=0.1) as ser:
        ser.reset_input_buffer()
        if args.interactive:
            total = interactive(ser, logf)
            print(f"\nTotal received: {total} bytes")
            return
        try:
            while True:
                if args.beacon and time.monotonic() - last_beacon >= 1.0:
                    ser.write(b"LOOPBACK-TEST\r\n")
                    last_beacon = time.monotonic()
                data = ser.read(4096)
                if not data:
                    continue
                total += len(data)
                if args.hexdump:
                    ts = datetime.datetime.now().strftime("%H:%M:%S.%f")[:-3]
                    text = data.decode("ascii", errors="replace")
                    print(f"[{ts}] {len(data):4d}B hex: {data[:32].hex(' ')}"
                          + (" ..." if len(data) > 32 else ""))
                    print(f"           ascii: {text!r}")
                else:
                    sys.stdout.write(data.decode("ascii", errors="replace"))
                    sys.stdout.flush()
                if logf:
                    logf.write(data)
                    logf.flush()
        except KeyboardInterrupt:
            pass
    print(f"\nTotal received: {total} bytes")


if __name__ == "__main__":
    main()
