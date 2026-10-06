#!/usr/bin/env bash
# Join a Wi-Fi network by SSID (uses Keychain password when available).

set -euo pipefail

SSID="${1:-}"
[[ -n "$SSID" ]] || exit 1

WIFI_DEV="$(networksetup -listallhardwareports 2>/dev/null \
  | awk '/Wi-Fi|AirPort/{getline; print $2; exit}')"
IFACE="${WIFI_DEV:-en0}"

# Prefer AirPort network password in Keychain; fall back to empty (open / already preferred).
PASS="$(security find-generic-password -D "AirPort network password" -a "$SSID" -w 2>/dev/null || true)"

if [[ -n "$PASS" ]]; then
  networksetup -setairportnetwork "$IFACE" "$SSID" "$PASS" >/dev/null 2>&1 || true
else
  networksetup -setairportnetwork "$IFACE" "$SSID" >/dev/null 2>&1 || true
fi

# Refresh bar after association settles.
sleep 1
bash "${HOME}/.config/sketchybar/plugins/wifi.sh" || true
