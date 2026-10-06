# Cinematic Noir — master palette (single source of truth)
# Sourced by shell tools and rice scripts. Do not add tool-specific logic here.
#
# Visual identity: dark cinematic sci-fi — navy / slate blue / muted violet / amber

# --- Master tokens -----------------------------------------------------------

export THEME_NAME="cinematic-noir"

export BASE="#0D0D13"
export SURFACE="#161720"
export SURFACE_ALT="#1D2030"
export BORDER="#30344B"
export FG="#D0D2DF"
export MUTED="#6D7291"
export BLUE="#6672B8"
export BLUE_BRIGHT="#6F78C4"
export PURPLE="#8B68B5"
export AMBER="#B07855"

# Semantic ANSI companions (restrained; used by terminals / diffs / git)
export RED="#A76565"
export GREEN="#668B78"
export YELLOW="#B09A69"
export CYAN="#608D9A"
export MAGENTA="#80639A"
export BLUE_ANSI="#596BA3"

# --- Hex without '#' (SketchyBar / jankyborders 0xffRRGGBB) ------------------

export BASE_RGB="${BASE#\#}"
export SURFACE_RGB="${SURFACE#\#}"
export SURFACE_ALT_RGB="${SURFACE_ALT#\#}"
export BORDER_RGB="${BORDER#\#}"
export FG_RGB="${FG#\#}"
export MUTED_RGB="${MUTED#\#}"
export BLUE_RGB="${BLUE#\#}"
export BLUE_BRIGHT_RGB="${BLUE_BRIGHT#\#}"
export PURPLE_RGB="${PURPLE#\#}"
export AMBER_RGB="${AMBER#\#}"
export RED_RGB="${RED#\#}"
export GREEN_RGB="${GREEN#\#}"
export YELLOW_RGB="${YELLOW#\#}"

# --- Helpers -----------------------------------------------------------------

# theme_argb "#RRGGBB" → 0xffRRGGBB
theme_argb() {
  local hex="${1#\#}"
  printf '0xff%s' "$hex"
}
