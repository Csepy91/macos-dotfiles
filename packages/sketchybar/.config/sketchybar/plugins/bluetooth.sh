#!/usr/bin/env bash
# Bluetooth status — Cinematic Noir (click toggles power via bluetooth_click.sh)

BLUEUTIL="${BLUEUTIL:-/opt/homebrew/bin/blueutil}"
JQ="${JQ:-/opt/homebrew/bin/jq}"

ICON="󰂲"
LABEL="off"
ICON_COLOR=""
LABEL_COLOR=""

if [[ -f "${HOME}/.config/theme/colors.sh" ]]; then
  # shellcheck disable=SC1091
  source "${HOME}/.config/theme/colors.sh"
  ICON_COLOR="$(theme_argb "$MUTED")"
  LABEL_COLOR="$(theme_argb "$FG")"
fi

if ! command -v "$BLUEUTIL" >/dev/null 2>&1 && ! BLUEUTIL="$(command -v blueutil 2>/dev/null)"; then
  LABEL="n/a"
  args=(--set "$NAME" icon="$ICON" label="$LABEL")
  [[ -n "$ICON_COLOR" ]] && args+=(icon.color="$ICON_COLOR")
  [[ -n "$LABEL_COLOR" ]] && args+=(label.color="$LABEL_COLOR")
  sketchybar "${args[@]}"
  exit 0
fi

POWER="$("$BLUEUTIL" -p 2>/dev/null || echo 0)"

if [[ "$POWER" == "1" ]]; then
  CONN_JSON="$("$BLUEUTIL" --connected --format json 2>/dev/null || echo '[]')"
  CONN_NAME="$(echo "$CONN_JSON" | "$JQ" -r '.[0].name // empty' 2>/dev/null)"
  COUNT="$(echo "$CONN_JSON" | "$JQ" -r 'length // 0' 2>/dev/null)"

  if [[ "${COUNT:-0}" -gt 0 ]]; then
    ICON="󰂱"
    if [[ -n "$CONN_NAME" ]]; then
      # Keep the pill readable.
      if [[ ${#CONN_NAME} -gt 18 ]]; then
        LABEL="${CONN_NAME:0:16}…"
      else
        LABEL="$CONN_NAME"
      fi
    else
      LABEL="on"
    fi
    if [[ -f "${HOME}/.config/theme/colors.sh" ]]; then
      ICON_COLOR="$(theme_argb "$BLUE")"
    fi
  else
    ICON="󰂯"
    LABEL="on"
  fi
else
  ICON="󰂲"
  LABEL="off"
fi

args=(--set "$NAME" icon="$ICON" label="$LABEL")
[[ -n "$ICON_COLOR" ]] && args+=(icon.color="$ICON_COLOR")
[[ -n "$LABEL_COLOR" ]] && args+=(label.color="$LABEL_COLOR")
sketchybar "${args[@]}"
