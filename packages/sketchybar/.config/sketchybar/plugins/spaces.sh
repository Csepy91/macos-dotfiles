#!/usr/bin/env bash
# OmniWM spaces — Cinematic Noir
# Driven by omniwmctl (requires ipcEnabled = true in OmniWM settings).

OMNIWMCTL="${OMNIWMCTL:-/opt/homebrew/bin/omniwmctl}"
JQ="${JQ:-/opt/homebrew/bin/jq}"

ACTIVE_C=""
VISIBLE_C=""
OCCUPIED_C=""
EMPTY_C=""
ACTIVE_BG=""

if [[ -f "${HOME}/.config/theme/colors.sh" ]]; then
  # shellcheck disable=SC1091
  source "${HOME}/.config/theme/colors.sh"
  ACTIVE_C="0xffffffff"
  VISIBLE_C="$(theme_argb "$BLUE")"
  OCCUPIED_C="$(theme_argb "$FG")"
  EMPTY_C="$(theme_argb "$MUTED")"
  ACTIVE_BG="$(theme_argb "$SURFACE_ALT")"
fi

# Match front_app (Hack Bold); always use raw workspace index as the glyph.
SPACE_FONT="Hack Nerd Font:Bold:12.0"

json="$("$OMNIWMCTL" query workspaces \
  --fields raw-name,display-name,is-current,is-visible,window-counts \
  --format json 2>/dev/null)" || exit 0

[[ -n "$json" ]] || exit 0
echo "$json" | "$JQ" -e '.ok == true' >/dev/null 2>&1 || exit 0

args=()
while IFS=$'\t' read -r raw display is_current is_visible total; do
  [[ -n "$raw" ]] || continue
  # Only manage the fixed 1–9 strip; skip renamed/emoji workspaces outside it.
  [[ "$raw" =~ ^[1-9]$ ]] || continue

  name="space.${raw}"
  # Prefer numeric raw name so emoji displayName never blanks the icon.
  icon="$raw"

  if [[ "$is_current" == "true" ]]; then
    color="$ACTIVE_C"
    bg_drawing=on
  elif [[ "$is_visible" == "true" ]]; then
    color="$VISIBLE_C"
    bg_drawing=off
  elif [[ "${total:-0}" -gt 0 ]]; then
    color="$OCCUPIED_C"
    bg_drawing=off
  else
    color="$EMPTY_C"
    bg_drawing=off
  fi

  entry=(
    --set "$name"
    icon="$icon"
    icon.drawing=on
    icon.font="$SPACE_FONT"
    background.drawing="$bg_drawing"
  )
  [[ -n "$color" ]] && entry+=(icon.color="$color")
  [[ -n "$ACTIVE_BG" ]] && entry+=(background.color="$ACTIVE_BG")
  args+=("${entry[@]}")
done < <(echo "$json" | "$JQ" -r '
  .result.payload.workspaces[]?
  | [
      .rawName,
      .displayName,
      (.isCurrent | tostring),
      (.isVisible | tostring),
      (.counts.total // 0)
    ]
  | @tsv
')

[[ ${#args[@]} -gt 0 ]] && sketchybar "${args[@]}"
