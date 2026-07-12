#!/usr/bin/env python3
"""Scripted (non-interactive) serial console session on the Gemini PDA.

Opens the FTDI port, logs in as root if a login prompt appears, sets a
distinctive shell prompt, then runs each command given on the command line,
waiting for the prompt between commands. Every byte received is appended to
the log file (raw evidence, per project logging rules); per-command output is
also printed to stdout.

Usage:
    python3 scripts/serial-session.py <logfile> '<cmd1>' ['<cmd2>' ...]

Notes:
  - The FTDI port must be free: exit ftdi-monitor.py first (only one process
    can hold /dev/cu.usbserial-*).
  - Credentials: root / toor (fresh Debian 13 rootfs default).
  - Give each command its own quoted argument; compound shell lines
    ('a; b; c') are fine.
  - Exits 1 with the tail of output if no shell prompt could be reached
    (device off, still booting, or port held by another process).
"""
import glob
import re
import sys
import time

import serial

BAUD = 921600
USER = "root"
PASSWORD = "toor"


def find_port():
    ports = glob.glob("/dev/cu.usbserial-*")
    if not ports:
        sys.exit("No /dev/cu.usbserial-* device found — is the FTDI rig connected?")
    return ports[0]


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    logpath, cmds = sys.argv[1], sys.argv[2:]

    s = serial.Serial(find_port(), BAUD, timeout=0.2)
    log = open(logpath, "ab")
    buf = b""

    def pump(sec=0.5):
        nonlocal buf
        end = time.time() + sec
        while time.time() < end:
            d = s.read(4096)
            if d:
                buf += d
                log.write(d)
                log.flush()

    def wait_for(patterns, timeout=15):
        end = time.time() + timeout
        while time.time() < end:
            tail = buf[-2000:].decode(errors="replace")
            for p in patterns:
                if re.search(p, tail):
                    return p
            pump(0.3)
        return None

    def sendline(line):
        s.write(line.encode() + b"\r")
        log.write(("\n>>> SENT: %r\n" % line).encode())
        log.flush()

    # Reach a shell: handle login/password prompts or an already-open shell.
    s.write(b"\r")
    pump(1.5)
    for _ in range(6):
        hit = wait_for([r"login:", r"Password:", r"[#\$] $"], timeout=8)
        if hit is None:
            s.write(b"\r")
            pump(1.5)
            continue
        if "login" in hit:
            buf = b""
            sendline(USER)
        elif "Password" in hit:
            buf = b""
            sendline(PASSWORD)
        else:
            break

    buf = b""
    sendline("PS1='GPROMPT# '")
    if not wait_for([r"GPROMPT# $"], 10):
        print("NO SHELL — last output:")
        print(buf.decode(errors="replace")[-1500:])
        sys.exit(1)

    for c in cmds:
        buf = b""
        sendline(c)
        wait_for([r"GPROMPT# $"], 30)
        time.sleep(0.5)
        pump(1.0)
        print(">>>", c)
        print(buf.decode(errors="replace"))

    s.close()


if __name__ == "__main__":
    main()
