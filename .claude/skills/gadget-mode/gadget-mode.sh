#!/bin/bash
# Configure the Mac's RNDIS/Ethernet Gadget interface to reach the Gemini's
# left-port USB gadget (usb0, 10.15.19.82). See SKILL.md for background.
set -euo pipefail

GADGET_IP=10.15.19.82
ALIAS_IP=10.15.19.1
NETMASK=255.255.255.0

iface=$(networksetup -listallhardwareports | awk '
  /^Hardware Port: RNDIS\/Ethernet Gadget$/ { want=1; next }
  want && /^Device:/ { print $2; exit }
')

if [ -z "$iface" ]; then
  echo "No 'RNDIS/Ethernet Gadget' hardware port found." >&2
  echo "Check the left-port USB cable is connected and the device has g_ether active." >&2
  exit 1
fi

echo "RNDIS/Ethernet Gadget is $iface"

if ifconfig "$iface" | grep -q "inet $ALIAS_IP "; then
  echo "$iface already has $ALIAS_IP"
else
  echo "Adding alias $ALIAS_IP/$NETMASK on $iface (requires sudo)"
  sudo ifconfig "$iface" inet "$ALIAS_IP" netmask "$NETMASK" alias
fi

echo "Pinging $GADGET_IP ..."
if ping -c2 -t2 "$GADGET_IP"; then
  echo "OK: $GADGET_IP reachable via $iface"
else
  echo "$GADGET_IP unreachable — device-side issue, not Mac-side (check usb0/cable)." >&2
  exit 1
fi
