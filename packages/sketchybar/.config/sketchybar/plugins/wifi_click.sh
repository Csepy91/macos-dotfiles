#!/usr/bin/env bash
# Toggle the SketchyBar Wi-Fi network dropdown (replaces Control Center menu,
# which is unavailable while SketchyBar is topmost over the menu bar).

set -euo pipefail

NAME="${NAME:-wifi}"
PLUGIN_DIR="${HOME}/.config/sketchybar/plugins"

drawing="$(sketchybar --query "$NAME" 2>/dev/null \
  | /opt/homebrew/bin/jq -r '.popup.drawing // "off"')"

if [[ "$drawing" == "on" ]]; then
  sketchybar --set "$NAME" popup.drawing=off
  exit 0
fi

# Show a quick "Scanning…" state, then populate.
sketchybar --set "$NAME" popup.drawing=on
NAME="$NAME" bash "${PLUGIN_DIR}/wifi_menu.sh"
