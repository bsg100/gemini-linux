#!/usr/bin/env python3
"""Raw serial monitor for Gemini PDA console bring-up.

Logs every received byte with a timestamp, in hex + ASCII, so electrical
activity is visible even if the baud rate is wrong (garbage = activity;
true silence = wiring problem). Listen-only by default — safe to leave
attached to the Gemini (never transmits toward the preloader).

    /tmp/ftdi-venv/bin/python scripts/ftdi-monitor.py [--baud 921600] [--beacon]

--beacon: transmit a test pattern once per second. ONLY for loopback
testing (D+ pad shorted to D− pad on the breakout) — do NOT use while
wired to the Gemini.
"""

import argparse
import datetime
import glob
import sys
import time

import serial


def find_port():
    ports = sorted(glob.glob("/dev/cu.usbserial*"))
    if not ports:
        sys.exit("No /dev/cu.usbserial* device found")
    return ports[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default=None)
    ap.add_argument("--baud", type=int, default=921600)
    ap.add_argument("--beacon", action="store_true",
                    help="TX test pattern 1/s — loopback test only, never on the Gemini")
    ap.add_argument("--log", default=None, help="also write raw bytes to this file (truncated by default)")
    ap.add_argument("--append", action="store_true",
                    help="append to --log instead of truncating (resuming an interrupted capture)")
    args = ap.parse_args()

    port = args.port or find_port()
    logf = open(args.log, "ab" if args.append else "wb") if args.log else None
    print(f"Listening on {port} @ {args.baud} baud"
          + (" with TX beacon (loopback mode)" if args.beacon else " (listen-only)"))
    print("Ctrl-C to stop. Waiting for bytes...")

    total = 0
    last_beacon = 0.0
    with serial.Serial(port, args.baud, timeout=0.1) as ser:
        ser.reset_input_buffer()
        try:
            while True:
                if args.beacon and time.monotonic() - last_beacon >= 1.0:
                    ser.write(b"LOOPBACK-TEST\r\n")
                    last_beacon = time.monotonic()
                data = ser.read(4096)
                if not data:
                    continue
                total += len(data)
                ts = datetime.datetime.now().strftime("%H:%M:%S.%f")[:-3]
                text = data.decode("ascii", errors="replace")
                print(f"[{ts}] {len(data):4d}B hex: {data[:32].hex(' ')}"
                      + (" ..." if len(data) > 32 else ""))
                print(f"           ascii: {text!r}")
                if logf:
                    logf.write(data)
                    logf.flush()
        except KeyboardInterrupt:
            pass
    print(f"\nTotal received: {total} bytes")


if __name__ == "__main__":
    main()
