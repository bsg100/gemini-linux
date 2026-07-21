---
name: gadget-mode
description: Configure the Mac's RNDIS/Ethernet Gadget interface so it can reach the Gemini PDA's left-port USB gadget (usb0, 10.15.19.82). Use when the user wants to SSH/ping the device over USB gadget mode and the interface only has a link-local address, or after reconnecting the left-port cable.
---

# Gadget mode (Mac-side RNDIS setup)

The Gemini's left-port USB gadget interface (`usb0`) is statically addressed
at `10.15.19.82/24` (`/etc/systemd/network/usb0.network` on the device — no
DHCP on that link). The Mac's "RNDIS/Ethernet Gadget" hardware port never
auto-acquires an address on that subnet; it sits at a link-local `169.254.x`
address until manually addressed. See memory `rndis-gadget-ip-config`.

## What this skill does

1. Finds the current "RNDIS/Ethernet Gadget" hardware port (its `enNN` name
   shifts across reconnects/reboots — never assume the last-used name is
   still correct).
2. Adds a static alias `10.15.19.1/24` on that interface if not already
   present.
3. Verifies reachability with a ping to `10.15.19.82`.

## Steps

```bash
# 1. Find the current interface name for "RNDIS/Ethernet Gadget"
networksetup -listallhardwareports
```

Read off the `Device:` line immediately following the
`Hardware Port: RNDIS/Ethernet Gadget` block (e.g. `en12`). If that block is
absent entirely, the Mac doesn't see the gadget at all — check the left-port
USB cable is connected and the device has USB gadget mode active (kernel
cmdline has `g_ether.dev_addr=...`), not a device-side problem to fix here.

```bash
# 2. Check current addressing on that interface
ifconfig <iface> | grep inet
```

If it already shows `inet 10.15.19.1 netmask 0xffffff00`, skip to step 4.

```bash
# 3. Add the static alias (requires sudo — ask the user to confirm/run if
#    the harness prompts for password)
sudo ifconfig <iface> inet 10.15.19.1 netmask 255.255.255.0 alias
```

```bash
# 4. Verify
ping -c2 10.15.19.82
```

On success, `ssh gemini@10.15.19.82` (or `root@`, password `toor`) should
connect immediately — no ARP flush needed.

## Notes

- The interface name is never stable — always re-run
  `networksetup -listallhardwareports` rather than reusing a name from a
  previous session or from memory.
- This only configures the Mac side. If ping still fails after aliasing,
  the problem is device-side (gadget not up, cable, or the device booted
  without `g_ether` — check via the right-port host-mode ethernet link at
  `192.168.100.x` instead, per project memory `right-port-speed-cap` /
  `project_status` B-19).
- `sudo ifconfig` is a network-affecting command — per project feedback
  (`feedback_network_impacting_commands`), flag it before running rather
  than running it silently, since it changes the Mac's own interface state.
