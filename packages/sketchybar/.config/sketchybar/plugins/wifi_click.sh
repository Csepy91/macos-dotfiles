#!/usr/bin/env bash
# Open the native macOS Wi-Fi Control Center menu (same as the menu-bar Wi-Fi icon).
# Compiles plugins/wifi_click.swift once into ~/.cache/sketchybar/.

set -euo pipefail

SRC="${HOME}/.config/sketchybar/plugins/wifi_click.swift"
CACHE_DIR="${HOME}/.cache/sketchybar"
BIN="${CACHE_DIR}/wifi_click"

mkdir -p "${CACHE_DIR}"

needs_build=0
if [[ ! -x "$BIN" ]]; then
  needs_build=1
elif [[ "$SRC" -nt "$BIN" ]]; then
  needs_build=1
fi

if [[ "$needs_build" -eq 1 ]]; then
  /usr/bin/swiftc -O \
    -framework Cocoa \
    -framework ApplicationServices \
    -framework CoreGraphics \
    -F /System/Library/PrivateFrameworks \
    -framework SkyLight \
    -o "$BIN" "$SRC"
fi

exec "$BIN"
