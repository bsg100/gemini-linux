#!/usr/bin/env python3
"""FTDI cable loopback test for Gemini PDA serial console bring-up.

Physically jumper the adapter's TX pin to its RX pin, then run:

    /tmp/ftdi-venv/bin/python scripts/test-ftdi-loopback.py [device]

If no device is given, the first /dev/cu.usbserial* port is used.
Tests the Gemini console baud rate (921600) plus common fallbacks, so we
know the adapter can actually sustain the rate the device will use.
"""

import glob
import sys
import time

import serial

BAUDS = [921600, 115200, 9600]
PATTERN = b"GeminiPDA-loopback-0123456789-ABCDEFGHIJKLMNOPQRSTUVWXYZ\r\n"


def find_port():
    ports = sorted(glob.glob("/dev/cu.usbserial*") + glob.glob("/dev/cu.usbmodem*"))
    if not ports:
        sys.exit("No /dev/cu.usbserial* device found — is the FTDI plugged in?")
    if len(ports) > 1:
        print(f"Multiple ports found, using first: {ports}")
    return ports[0]


def test_baud(port, baud):
    with serial.Serial(port, baud, timeout=2) as ser:
        ser.reset_input_buffer()
        ser.write(PATTERN)
        ser.flush()
        time.sleep(0.2)
        rx = ser.read(len(PATTERN))
    if rx == PATTERN:
        print(f"  {baud:>7} baud: PASS ({len(rx)} bytes echoed intact)")
        return True
    if not rx:
        print(f"  {baud:>7} baud: FAIL — nothing received (TX-RX jumper connected?)")
    else:
        print(f"  {baud:>7} baud: FAIL — got {len(rx)} bytes, corrupted: {rx!r}")
    return False


def main():
    port = sys.argv[1] if len(sys.argv) > 1 else find_port()
    print(f"Testing {port} (TX must be jumpered to RX)")
    results = [test_baud(port, b) for b in BAUDS]
    if all(results):
        print("All rates passed — cable is good for the 921600-baud Gemini console.")
    elif results[0]:
        print("921600 passed — good enough for the Gemini console despite other failures.")
    else:
        sys.exit("Loopback failed at 921600 baud — see above.")


if __name__ == "__main__":
    main()
