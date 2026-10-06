#!/usr/bin/env bash
PERCENTAGE="$(pmset -g batt | grep -Eo '[0-9]+%' | head -1 | tr -d '%')"
CHARGING="$(pmset -g batt | grep 'AC Power' || true)"
ICON="󰁹"
if [ -n "$CHARGING" ]; then
  ICON="󰂄"
elif [ "${PERCENTAGE:-0}" -lt 20 ]; then
  ICON="󰁺"
elif [ "${PERCENTAGE:-0}" -lt 50 ]; then
  ICON="󰁾"
fi
sketchybar --set "$NAME" icon="$ICON" label="${PERCENTAGE}%"
