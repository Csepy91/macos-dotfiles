# Thin wrapper — sources the active palette, then derives RGB helpers.
# Sourced by shell tools and rice scripts. Do not add tool-specific logic here.

# Resolve via this file’s real path (stow symlink → repo) so all palettes are visible
# even when ~/.config/theme/palettes/ is an older partial directory tree.
_THEME_DIR="${${(%):-%x}:A:h}"
_THEME_ACTIVE_FILE="${HOME}/.config/theme/active"
_THEME_NAME_FALLBACK="cinematic-noir"

if [[ -f "${_THEME_ACTIVE_FILE}" ]]; then
  _THEME_ACTIVE="$(<"${_THEME_ACTIVE_FILE}")"
  _THEME_ACTIVE="${_THEME_ACTIVE%%$'\n'*}"
else
  _THEME_ACTIVE="${_THEME_NAME_FALLBACK}"
fi

_THEME_PALETTE="${_THEME_DIR}/palettes/${_THEME_ACTIVE}/colors.sh"
if [[ ! -f "${_THEME_PALETTE}" ]]; then
  _THEME_ACTIVE="${_THEME_NAME_FALLBACK}"
  _THEME_PALETTE="${_THEME_DIR}/palettes/${_THEME_ACTIVE}/colors.sh"
fi

# shellcheck source=/dev/null
source "${_THEME_PALETTE}"

# --- Hex without '#' (ARGB helpers 0xffRRGGBB) --------------------------------

export BASE_RGB="${BASE#\#}"
export SURFACE_RGB="${SURFACE#\#}"
export SURFACE_ALT_RGB="${SURFACE_ALT#\#}"
export THEME_BORDER_RGB="${THEME_BORDER#\#}"
export FG_RGB="${FG#\#}"
export MUTED_RGB="${MUTED#\#}"
export BLUE_RGB="${BLUE#\#}"
export BLUE_BRIGHT_RGB="${BLUE_BRIGHT#\#}"
export PURPLE_RGB="${PURPLE#\#}"
export AMBER_RGB="${AMBER#\#}"
export RED_RGB="${RED#\#}"
export GREEN_RGB="${GREEN#\#}"
export YELLOW_RGB="${YELLOW#\#}"
export CYAN_RGB="${CYAN#\#}"
export MAGENTA_RGB="${MAGENTA#\#}"
export BLUE_ANSI_RGB="${BLUE_ANSI#\#}"

# Decimal R,G,B CSV (ripgrep --colors)
_theme_rgb_csv() {
  local hex="${1#\#}"
  printf '%d,%d,%d' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}
export PURPLE_RGB_CSV="$(_theme_rgb_csv "$PURPLE")"
export MUTED_RGB_CSV="$(_theme_rgb_csv "$MUTED")"
export BLUE_BRIGHT_RGB_CSV="$(_theme_rgb_csv "$BLUE_BRIGHT")"
unfunction _theme_rgb_csv 2>/dev/null || true

# --- Helpers -----------------------------------------------------------------

# theme_argb "#RRGGBB" → 0xffRRGGBB
theme_argb() {
  local hex="${1#\#}"
  printf '0xff%s' "$hex"
}

unset _THEME_DIR _THEME_ACTIVE_FILE _THEME_NAME_FALLBACK _THEME_ACTIVE _THEME_PALETTE
