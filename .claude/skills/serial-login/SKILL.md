---
name: serial-login
description: Log in to the Gemini PDA over the FTDI serial console non-interactively and run shell commands, logging all output. Use when the user has released the FTDI port and wants Claude to drive the device console directly (e.g. panel DCS probes, register dumps, dmesg reads).
---

# Serial login (scripted console session)

Runs commands on the Gemini's serial console via `scripts/serial-session.py`
(pyserial, prompt-driven: handles root/toor login, sets a `GPROMPT# ` sentinel
prompt, waits for it between commands).

## Preconditions

1. **The FTDI port must be free.** Only one process can open
   `/dev/cu.usbserial-*`. If the user is running `ftdi-monitor.py`, ask them
   to exit it first. Check with:
   `lsof /dev/cu.usbserial-* ; ls /dev/cu.usbserial-*`
2. The device must be booted to a login prompt (Debian 13 rootfs on serial
   `ttyS0`). If it's mid-boot, the script will retry for a while but may fail
   with `NO SHELL`.

## Usage

```bash
python3 scripts/serial-session.py logs/YYYY-MM-DD-NN-<desc>-session.log \
    'first command' \
    'second command; dmesg | tail -5'
```

- **Always log under `logs/`** with the standard `YYYY-MM-DD-NN-desc` naming
  (project logging rules: every byte captured is evidence, appended raw).
- One quoted argument per command line; compound `a; b; c` lines are fine.
- Per-command output is echoed to stdout; the log holds the raw stream.
- Prompt-wait timeout is 30 s per command — for long-running commands, wrap
  with `timeout N ...` on the device or split into a poll loop.

## Constraints (standing project rules)

- This skill replaces *interactive* console use only when the user has
  explicitly released the port. Never kill the user's ftdi-monitor to take
  the port.
- Flashing (`mtk w ...`) remains user-run, always.
- Baud 921600, credentials root/toor (fresh Debian 13 rootfs). Port is
  auto-detected (`/dev/cu.usbserial-*`).

## Useful device-side debug interfaces (build-dependent, zz-debug patches)

- `echo "r 0a" > /sys/kernel/debug/gemini_panel_dcs` — DCS read (result in dmesg)
- `echo "23"   > /sys/kernel/debug/gemini_panel_dcs` — DCS write
- `echo 1 > /sys/kernel/debug/gemini_ddp_dump_now` — full DDP/DSI/MIPITX register dump
- `cat /sys/kernel/debug/gpio`, `/sys/kernel/debug/regulator/regulator_summary`
- `modprobe i2c-dev` then `i2cget -y -f 1 0x3e <reg>` — TPS65132 bias readback
