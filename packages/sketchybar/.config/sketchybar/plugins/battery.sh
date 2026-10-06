#!/usr/bin/env bash
# Battery plugin — Cinematic Noir (amber when low)
PERCENTAGE="$(pmset -g batt | grep -Eo '[0-9]+%' | head -1 | tr -d '%')"
CHARGING="$(pmset -g batt | grep 'AC Power' || true)"
ICON="󰁹"
ICON_COLOR=""
LABEL_COLOR=""

# Optional theme colors when palette is available
if [[ -f "${HOME}/.config/theme/colors.sh" ]]; then
  # shellcheck disable=SC1091
  source "${HOME}/.config/theme/colors.sh"
  ICON_COLOR="$(theme_argb "$MUTED")"
  LABEL_COLOR="$(theme_argb "$FG")"
  if [ -z "$CHARGING" ] && [ "${PERCENTAGE:-100}" -lt 20 ]; then
    ICON_COLOR="$(theme_argb "$AMBER")"
    LABEL_COLOR="$(theme_argb "$AMBER")"
  fi
fi

if [ -n "$CHARGING" ]; then
  ICON="󰂄"
elif [ "${PERCENTAGE:-0}" -lt 20 ]; then
  ICON="󰁺"
elif [ "${PERCENTAGE:-0}" -lt 50 ]; then
  ICON="󰁾"
fi

args=(--set "$NAME" icon="$ICON" label="${PERCENTAGE}%")
[[ -n "$ICON_COLOR" ]] && args+=(icon.color="$ICON_COLOR")
[[ -n "$LABEL_COLOR" ]] && args+=(label.color="$LABEL_COLOR")
sketchybar "${args[@]}"
