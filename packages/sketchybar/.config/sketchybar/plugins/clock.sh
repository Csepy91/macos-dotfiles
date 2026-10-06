#!/usr/bin/env bash
# Clock + month calendar popup — Cinematic Noir

if [[ "$SENDER" == "mouse.exited.global" ]]; then
  sketchybar --set "$NAME" popup.drawing=off
  exit 0
fi

BAR_FG=""
MUTED_C=""
ACCENT=""
if [[ -f "${HOME}/.config/theme/colors.sh" ]]; then
  # shellcheck disable=SC1091
  source "${HOME}/.config/theme/colors.sh"
  BAR_FG="$(theme_argb "$FG")"
  MUTED_C="$(theme_argb "$MUTED")"
  ACCENT="$(theme_argb "$BLUE_BRIGHT")"
fi

MONO_FONT="Hack Nerd Font:Regular:11.0"
# 20 monospaced columns ("Su Mo Tu We Th Fr Sa") ≈ 140pt at 11px Hack.
ROW_WIDTH=140
TODAY="$(date '+%-d')"
TODAY_FIELD="$(printf '%2d' "$TODAY")"

for i in $(seq 0 12); do
  sketchybar --remove "${NAME}.cal.${i}" 2>/dev/null || true
done

args=(--set "$NAME" label="$(date '+%H:%M')")
idx=0

while IFS= read -r raw || [[ -n "$raw" ]]; do
  # cal(1) pads rows to 22; the real grid is 20 cols (title already centered in that).
  line="$(printf '%-20.20s' "$raw")"
  [[ -z "${line// /}" ]] && continue

  color="$BAR_FG"
  if (( idx == 0 )); then
    color="${ACCENT:-$BAR_FG}"
  elif (( idx == 1 )); then
    color="${MUTED_C:-$BAR_FG}"
  elif [[ "$line" == *"${TODAY_FIELD}"* ]]; then
    color="${ACCENT:-$BAR_FG}"
  else
    color="${MUTED_C:-$BAR_FG}"
  fi

  item="${NAME}.cal.${idx}"
  args+=(
    --add item "$item" "popup.${NAME}"
    --set "$item"
      icon.drawing=off
      icon.padding_left=0
      icon.padding_right=0
      label="$line"
      label.font="$MONO_FONT"
      label.color="$color"
      label.padding_left=0
      label.padding_right=0
      label.align=left
      label.width="$ROW_WIDTH"
      width="$ROW_WIDTH"
      background.drawing=off
      padding_left=10
      padding_right=10
      y_offset=0
      click_script="sketchybar --set ${NAME} popup.drawing=off"
  )
  idx=$((idx + 1))
done < <(cal)

[[ ${#args[@]} -gt 0 ]] && sketchybar "${args[@]}"
