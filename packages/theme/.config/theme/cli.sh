# CLI tool color application from active palette tokens.
# Sourced from ~/.zshrc after colors.sh. Safe no-ops when tools are absent.

# --- bat ---------------------------------------------------------------------
export BAT_THEME="Dotfiles"

# --- fzf ---------------------------------------------------------------------
if (( $+commands[fzf] )); then
  export FZF_DEFAULT_OPTS="
--color=bg:${BASE},bg+:${SURFACE},fg:${FG},fg+:${FG}
--color=hl:${BLUE_BRIGHT},hl+:${BLUE_BRIGHT}
--color=info:${MUTED},prompt:${BLUE},pointer:${BLUE_BRIGHT}
--color=marker:${AMBER},spinner:${PURPLE},header:${PURPLE}
--color=border:${THEME_BORDER},gutter:${BASE},preview-bg:${SURFACE}
--border=rounded
--height=40%
--layout=reverse"
fi

# --- eza / LS_COLORS ---------------------------------------------------------
# di=dirs, ex=exec, ln=symlink, or=orphan, archives muted yellow
# Keep metadata muted; avoid rainbow file-type soup.
_theme_ls_colors() {
  local di="38;2;$((0x${BLUE_BRIGHT_RGB:0:2}));$((0x${BLUE_BRIGHT_RGB:2:2}));$((0x${BLUE_BRIGHT_RGB:4:2}))"
  local ex="38;2;$((0x${GREEN_RGB:0:2}));$((0x${GREEN_RGB:2:2}));$((0x${GREEN_RGB:4:2}))"
  local ln="38;2;$((0x${PURPLE_RGB:0:2}));$((0x${PURPLE_RGB:2:2}));$((0x${PURPLE_RGB:4:2}))"
  local archive="38;2;$((0x${YELLOW_RGB:0:2}));$((0x${YELLOW_RGB:2:2}));$((0x${YELLOW_RGB:4:2}))"
  local muted="38;2;$((0x${MUTED_RGB:0:2}));$((0x${MUTED_RGB:2:2}));$((0x${MUTED_RGB:4:2}))"
  local or_="38;2;$((0x${RED_RGB:0:2}));$((0x${RED_RGB:2:2}));$((0x${RED_RGB:4:2}))"
  local fi_="38;2;$((0x${FG_RGB:0:2}));$((0x${FG_RGB:2:2}));$((0x${FG_RGB:4:2}))"

  export LS_COLORS="di=${di}:ex=${ex}:ln=${ln}:or=${or_}:fi=${fi_}:ow=${di}:tw=${di}:*.tar=${archive}:*.tgz=${archive}:*.zip=${archive}:*.gz=${archive}:*.bz2=${archive}:*.xz=${archive}:*.7z=${archive}:*.rar=${archive}:*.md=${muted}:*.txt=${muted}:*.log=${muted}"

  # eza uses EZA_COLORS (overrides LS_COLORS keys it understands)
  if (( $+commands[eza] )); then
    export EZA_COLORS="di=${di}:ex=${ex}:ln=${ln}:or=${or_}:ur=${muted}:uw=${muted}:ux=${muted}:ue=${muted}:gr=${muted}:gw=${muted}:gx=${muted}:tr=${muted}:tw=${muted}:tx=${muted}:sn=${muted}:sb=${muted}:uu=${muted}:un=${muted}:gu=${muted}:gn=${muted}:da=${muted}:gm=${archive}:ga=${ex}:gd=${or_}:gv=${archive}:im=${fi_}:vi=${fi_}:mu=${fi_}:lo=${fi_}:sc=${archive}:bu=${archive}:cm=${muted}:mp=${fi_}:in=${muted}:*.tar=${archive}:*.zip=${archive}:*.gz=${archive}:*.xz=${archive}"
  fi
}
_theme_ls_colors
unfunction _theme_ls_colors 2>/dev/null || true

# --- ripgrep -----------------------------------------------------------------
if (( $+commands[rg] )); then
  export RIPGREP_CONFIG_PATH="${HOME}/.config/ripgrep/config"
fi

# --- zsh-autosuggestions -----------------------------------------------------
export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=${MUTED}"

# --- zsh-syntax-highlighting -------------------------------------------------
# Must be set before the plugin is sourced (zshrc sources this file first).
typeset -gA ZSH_HIGHLIGHT_STYLES
ZSH_HIGHLIGHT_STYLES[default]="fg=${FG}"
ZSH_HIGHLIGHT_STYLES[unknown-token]="fg=${RED}"
ZSH_HIGHLIGHT_STYLES[reserved-word]="fg=${PURPLE}"
ZSH_HIGHLIGHT_STYLES[alias]="fg=${BLUE_BRIGHT}"
ZSH_HIGHLIGHT_STYLES[builtin]="fg=${BLUE}"
ZSH_HIGHLIGHT_STYLES[function]="fg=${BLUE_BRIGHT}"
ZSH_HIGHLIGHT_STYLES[command]="fg=${BLUE_BRIGHT}"
ZSH_HIGHLIGHT_STYLES[precommand]="fg=${GREEN},underline"
ZSH_HIGHLIGHT_STYLES[commandseparator]="fg=${MUTED}"
ZSH_HIGHLIGHT_STYLES[hashed-command]="fg=${BLUE_BRIGHT}"
ZSH_HIGHLIGHT_STYLES[path]="fg=${FG}"
ZSH_HIGHLIGHT_STYLES[path_prefix]="fg=${MUTED}"
ZSH_HIGHLIGHT_STYLES[globbing]="fg=${AMBER}"
ZSH_HIGHLIGHT_STYLES[history-expansion]="fg=${PURPLE}"
ZSH_HIGHLIGHT_STYLES[single-hyphen-option]="fg=${MUTED}"
ZSH_HIGHLIGHT_STYLES[double-hyphen-option]="fg=${MUTED}"
ZSH_HIGHLIGHT_STYLES[back-quoted-argument]="fg=${CYAN}"
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]="fg=${GREEN}"
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]="fg=${GREEN}"
ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]="fg=${GREEN}"
ZSH_HIGHLIGHT_STYLES[dollar-double-quoted-argument]="fg=${YELLOW}"
ZSH_HIGHLIGHT_STYLES[assign]="fg=${FG}"
ZSH_HIGHLIGHT_STYLES[redirection]="fg=${AMBER}"
ZSH_HIGHLIGHT_STYLES[comment]="fg=${MUTED}"
ZSH_HIGHLIGHT_STYLES[arg0]="fg=${BLUE_BRIGHT}"
