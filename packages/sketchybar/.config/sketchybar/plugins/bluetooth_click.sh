#!/usr/bin/env bash
# Toggle Bluetooth power, then refresh the sketchybar item.

BLUEUTIL="${BLUEUTIL:-/opt/homebrew/bin/blueutil}"
PLUGIN="${HOME}/.config/sketchybar/plugins/bluetooth.sh"

if ! command -v "$BLUEUTIL" >/dev/null 2>&1 && ! BLUEUTIL="$(command -v blueutil 2>/dev/null)"; then
  exit 0
fi

"$BLUEUTIL" -p toggle >/dev/null
sleep 0.3
NAME="${NAME:-bluetooth}" "$PLUGIN"
