#!/usr/bin/env zsh
# Interactive bootstrap: Homebrew packages + GNU Stow configs.
set -euo pipefail

ROOT="${0:A:h}"
cd "$ROOT"

# shellcheck disable=SC1091
source "$ROOT/lib/features.sh"

RED=$'\033[0;31m'
GRN=$'\033[0;32m'
YLW=$'\033[0;33m'
BLU=$'\033[0;34m'
RST=$'\033[0m'

info() { print -r -- "${BLU}==>${RST} $*"; }
ok() { print -r -- "${GRN}✓${RST} $*"; }
warn() { print -r -- "${YLW}!${RST} $*"; }
die() { print -r -- "${RED}error:${RST} $*" >&2; exit 1; }

# --- Preconditions -----------------------------------------------------------

[[ "$(uname -s)" == "Darwin" ]] || die "This installer only supports macOS."
[[ "$(uname -m)" == "arm64" ]] || die "OmniWM and this rice target Apple Silicon (arm64) only."

MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if (( MACOS_MAJOR < 26 )); then
  warn "OmniWM requires macOS 26+. Detected $(sw_vers -productVersion). Continuing, but OmniWM may not run."
fi

USERNAME="$(id -un)"
RAW_HOST="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
HOSTNAME="${RAW_HOST//./-}"

info "User: $USERNAME"
info "Host: $HOSTNAME (from $RAW_HOST)"

# --- Host directory ----------------------------------------------------------

HOST_DIR="$ROOT/hosts/$HOSTNAME"
if [[ ! -d "$HOST_DIR" ]]; then
  info "Creating host config from hosts/default → hosts/$HOSTNAME"
  mkdir -p "$HOST_DIR"
  cp -R "$ROOT/hosts/default/." "$HOST_DIR/"
fi

FEATURES_FILE="$HOST_DIR/features.conf"
features_load "$FEATURES_FILE"

# --- Homebrew ----------------------------------------------------------------

ensure_brew() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    ok "Homebrew present"
    eval "$(/opt/homebrew/bin/brew shellenv)"
    return
  fi
  info "Installing Homebrew…"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
  ok "Homebrew installed"
}

# --- Feature selection -------------------------------------------------------

apply_selection() {
  # $1 = prefix (CLI|RICE|APPS), $2 = newline-separated selected short keys
  local prefix="$1"
  local selected="$2"
  local -a all_keys
  case "$prefix" in
    CLI) all_keys=(bat btop duti eza fd fzf gh git ncdu ripgrep starship tldr uv zoxide yazi) ;;
    RICE) all_keys=(omniwm sketchybar jankyborders skhd ghostty) ;;
    APPS) all_keys=(cursor sublimeText teamviewer transmission iina libreoffice geForceNow) ;;
  esac
  local key
  for key in "${all_keys[@]}"; do
    eval "${prefix}_${key}=false"
  done
  for key in ${(f)selected}; do
    if [[ -z "$key" ]]; then
      continue
    fi
    eval "${prefix}_${key}=true"
  done
}

# Build gum --selected args for enabled flags under PREFIX_*.
# Must use if/fi — `eval '[[ false ]] && …'` returns 1 and trips `set -e`.
gum_selected_args() {
  local prefix="$1"
  shift
  local -a keys=("$@")
  local -a args=()
  local k var
  for k in "${keys[@]}"; do
    var="${prefix}_${k}"
    if [[ "${(P)var}" == "true" ]]; then
      args+=(--selected "$k")
    fi
  done
  print -r -- "${args[@]}"
}

interactive_select() {
  local -a cli_keys=(bat btop duti eza fd fzf gh git ncdu ripgrep starship tldr uv zoxide yazi)
  local -a rice_keys=(omniwm sketchybar jankyborders skhd ghostty)
  local -a apps_keys=(cursor sublimeText teamviewer transmission iina libreoffice geForceNow)
  local sel
  local -a gum_selected

  if (( $+commands[gum] )); then
    info "Select CLI tools (Space toggles, Enter confirms)"
    gum_selected=(${(z)$(gum_selected_args CLI "${cli_keys[@]}")})
    sel="$(gum choose --no-limit --header "CLI tools" "${gum_selected[@]}" "${cli_keys[@]}" || true)"
    if [[ -n "$sel" ]]; then
      apply_selection CLI "$sel"
    fi

    info "Select rice components"
    gum_selected=(${(z)$(gum_selected_args RICE "${rice_keys[@]}")})
    sel="$(gum choose --no-limit --header "Rice" "${gum_selected[@]}" "${rice_keys[@]}" || true)"
    if [[ -n "$sel" ]]; then
      apply_selection RICE "$sel"
    fi

    info "Select GUI apps"
    gum_selected=(${(z)$(gum_selected_args APPS "${apps_keys[@]}")})
    sel="$(gum choose --no-limit --header "GUI apps" "${gum_selected[@]}" "${apps_keys[@]}" || true)"
    if [[ -n "$sel" ]]; then
      apply_selection APPS "$sel"
    fi
  elif (( $+commands[fzf] )); then
    warn "gum not found — using fzf (TAB to multi-select)"
    sel="$(printf '%s\n' "${cli_keys[@]}" | fzf --multi --prompt 'CLI > ' || true)"
    if [[ -n "$sel" ]]; then
      apply_selection CLI "$sel"
    fi
    sel="$(printf '%s\n' "${rice_keys[@]}" | fzf --multi --prompt 'Rice > ' || true)"
    if [[ -n "$sel" ]]; then
      apply_selection RICE "$sel"
    fi
    sel="$(printf '%s\n' "${apps_keys[@]}" | fzf --multi --prompt 'Apps > ' || true)"
    if [[ -n "$sel" ]]; then
      apply_selection APPS "$sel"
    fi
  else
    warn "Neither gum nor fzf found — keeping defaults."
    info "Tip: brew install gum && re-run ./install.sh"
  fi
}

# --- Brewfile + install ------------------------------------------------------

write_brewfile() {
  local out="$ROOT/Brewfile"
  info "Writing $out"

  # Homebrew 6+ requires explicit trust for non-official tap items.
  # Prefer per-item trust over trusting the whole tap.
  # Note: font-sketchybar-app-font is on homebrew/cask (official) — not FelixKratz.
  local -a felix_formulae=() koekeishiya_formulae=()
  if $RICE_sketchybar; then
    felix_formulae+=(sketchybar)
  fi
  if $RICE_jankyborders; then
    felix_formulae+=(borders)
  fi
  if $RICE_skhd; then
    koekeishiya_formulae+=(skhd)
  fi

  {
    print -r -- "# Generated by ./install.sh — do not edit by hand; re-run the installer."

    if (( ${#felix_formulae[@]} > 0 )); then
      print -r -- "tap \"FelixKratz/formulae\", trusted: {"
      print -r -- "  formulae: [$(printf '"%s", ' "${felix_formulae[@]}" | sed 's/, $//')],"
      print -r -- "}"
    fi

    if (( ${#koekeishiya_formulae[@]} > 0 )); then
      print -r -- "tap \"koekeishiya/formulae\", trusted: {"
      print -r -- "  formulae: [$(printf '"%s", ' "${koekeishiya_formulae[@]}" | sed 's/, $//')],"
      print -r -- "}"
    fi

    print -r -- ""

    local f
    for f in ${(z)$(features_brew_formulae)}; do
      case "$f" in
        sketchybar) print -r -- "brew \"FelixKratz/formulae/sketchybar\", trusted: true" ;;
        borders) print -r -- "brew \"FelixKratz/formulae/borders\", trusted: true" ;;
        skhd) print -r -- "brew \"koekeishiya/formulae/skhd\", trusted: true" ;;
        *) print -r -- "brew \"$f\"" ;;
      esac
    done

    print -r -- ""
    local c
    for c in ${(z)$(features_brew_casks)}; do
      # Official homebrew/cask fonts and apps — no FelixKratz qualification.
      print -r -- "cask \"$c\""
    done
  } >"$out"
  ok "Brewfile written"
}

# Grant brew tap trust for third-party rice formulae (Homebrew 6+).
# Brewfile trusted: entries cover brew bundle; this covers direct brew installs too.
ensure_brew_trust() {
  if ! brew trust --help &>/dev/null; then
    warn "brew trust unavailable — skipping (upgrade Homebrew if installs from FelixKratz/formulae fail)"
    return 0
  fi

  info "Trusting third-party formulae for brew bundle…"
  if $RICE_sketchybar; then
    brew trust --formula FelixKratz/formulae/sketchybar || warn "Could not trust sketchybar"
  fi
  if $RICE_jankyborders; then
    brew trust --formula FelixKratz/formulae/borders || warn "Could not trust borders"
  fi
  if $RICE_skhd; then
    brew trust --formula koekeishiya/formulae/skhd || warn "Could not trust skhd"
  fi
  ok "brew trust applied"
}

brew_bundle() {
  ensure_brew_trust
  info "Installing packages with brew bundle…"
  brew bundle --file="$ROOT/Brewfile"
  ok "brew bundle complete"

  # Surface missing rice binaries early (PATH may not include Homebrew yet).
  if $RICE_skhd && ! skhd_bin >/dev/null; then
    warn "skhd was selected but /opt/homebrew/bin/skhd is missing"
    warn "Try: brew install --formula koekeishiya/formulae/skhd"
  fi
}

# --- Stow --------------------------------------------------------------------

stow_packages() {
  local -a pkgs
  pkgs=(${(z)$(features_stow_packages)})
  [[ ${#pkgs[@]} -gt 0 ]] || return 0

  mkdir -p \
    "$HOME/.config" \
    "$HOME/.local/share/zsh/site-functions" \
    "$HOME/Library/LaunchAgents" \
    "$HOME/Library/Logs/omniwm"

  info "Stowing packages → \$HOME: ${pkgs[*]}"
  # Restow so re-runs update links; adopt conflicts only when --adopt is passed.
  local -a stow_args=(-d "$ROOT/packages" -t "$HOME" -R)
  if $STOW_ADOPT; then
    stow_args+=(--adopt)
  fi

  stow "${stow_args[@]}" "${pkgs[@]}"
  ok "stow complete"

  # Ensure sketchybar plugins + bordersrc are executable
  if [[ -d "$HOME/.config/sketchybar/plugins" ]]; then
    chmod +x "$HOME/.config/sketchybar/plugins"/*.sh 2>/dev/null || true
  fi
  if [[ -f "$HOME/.config/sketchybar/sketchybarrc" ]]; then
    chmod +x "$HOME/.config/sketchybar/sketchybarrc"
  fi
  if [[ -f "$HOME/.config/borders/bordersrc" ]]; then
    chmod +x "$HOME/.config/borders/bordersrc"
  fi
}

# --- Services ----------------------------------------------------------------

# Resolve Homebrew skhd binary (not on PATH until brew shellenv / new shell).
skhd_bin() {
  if [[ -x /opt/homebrew/bin/skhd ]]; then
    print -r -- /opt/homebrew/bin/skhd
  elif [[ -x /usr/local/bin/skhd ]]; then
    print -r -- /usr/local/bin/skhd
  elif (( $+commands[skhd] )); then
    command -v skhd
  else
    return 1
  fi
}

start_skhd() {
  local bin
  if ! bin="$(skhd_bin)"; then
    warn "skhd binary not found — run: brew install koekeishiya/formulae/skhd"
    return 1
  fi
  ok "skhd at $bin"

  # skhd manages ~/Library/LaunchAgents/com.koekeishiya.skhd.plist itself.
  # --restart-service requires that plist already; --start-service installs it.
  "$bin" --install-service 2>/dev/null || true
  if "$bin" --start-service; then
    ok "skhd service started"
  elif "$bin" --restart-service; then
    ok "skhd service restarted"
  else
    warn "skhd service failed — try: $bin --install-service && $bin --start-service"
    return 1
  fi

  info "skhd will not appear in Accessibility until it has run once."
  info "If missing: System Settings → Privacy & Security → Accessibility → + → $bin"
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null || true
}

start_services() {
  info "Starting rice services…"

  if $RICE_skhd; then
    start_skhd || true
  fi
  if $RICE_sketchybar; then
    brew services restart sketchybar 2>/dev/null || brew services start sketchybar || warn "sketchybar service failed"
  fi
  if $RICE_jankyborders; then
    brew services restart borders 2>/dev/null || brew services start borders || warn "borders service failed"
  fi
  if $RICE_omniwm; then
    local label="com.dotfiles.omniwm"
    local plist="$HOME/Library/LaunchAgents/${label}.plist"
    if [[ -f "$plist" ]]; then
      launchctl bootout "gui/$(id -u)/${label}" 2>/dev/null || true
      launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null \
        || launchctl load -w "$plist" 2>/dev/null \
        || warn "Could not load OmniWM LaunchAgent — open OmniWM.app manually"
    fi
  fi

  ok "Service start attempted"
}

print_next_steps() {
  cat <<EOF

${GRN}Install finished.${RST}

Next steps:
  1. Read ${BLU}docs/PERMISSIONS.md${RST} and grant Accessibility / Input Monitoring.
  2. skhd is a CLI binary — add ${BLU}/opt/homebrew/bin/skhd${RST} with + if it is missing from the list.
  3. Log out and back in if Mission Control "Displays have separate Spaces" changed.
  4. Launch OmniWM, Ghostty, and confirm sketchybar / borders / skhd are running.
  5. Launcher is Spotlight for now (Cmd+Space).

Useful commands:
  /opt/homebrew/bin/skhd --install-service && /opt/homebrew/bin/skhd --start-service
  /opt/homebrew/bin/skhd --restart-service   # only after the service plist exists
  brew bundle --file $ROOT/Brewfile
  stow -d $ROOT/packages -t \$HOME -R zsh git ghostty …
  ./install.sh          # re-run interactive feature selection

EOF
}

# --- Main --------------------------------------------------------------------

NONINTERACTIVE=false
SKIP_BUNDLE=false
STOW_ADOPT=false
for arg in "$@"; do
  case "$arg" in
    --yes|-y) NONINTERACTIVE=true ;;
    --no-bundle) SKIP_BUNDLE=true ;;
    --adopt) STOW_ADOPT=true ;;
    --help|-h)
      print "Usage: ./install.sh [--yes] [--no-bundle] [--adopt]"
      print "  --yes        Non-interactive; keep current/default feature flags"
      print "  --no-bundle  Write features + Brewfile + stow only (skip brew bundle / services)"
      print "  --adopt      Pass --adopt to stow (take over existing files into the repo)"
      exit 0
      ;;
  esac
done

ensure_brew

if ! (( $+commands[gum] )); then
  info "Installing gum for the interactive picker…"
  brew install gum || warn "Could not install gum"
  export PATH="/opt/homebrew/bin:$PATH"
fi

if ! (( $+commands[stow] )); then
  info "Installing stow…"
  brew install stow
fi

if $NONINTERACTIVE; then
  info "Non-interactive mode — keeping feature flags from $FEATURES_FILE (or defaults)"
else
  interactive_select
fi

features_write "$FEATURES_FILE"
ok "features.conf written"

write_brewfile

if ! $SKIP_BUNDLE; then
  brew_bundle
  stow_packages
  start_services
else
  stow_packages
  warn "Skipped brew bundle / services (--no-bundle)"
fi

print_next_steps
