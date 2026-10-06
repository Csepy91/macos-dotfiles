#!/usr/bin/env zsh
# Interactive bootstrap for this macOS rice flake.
set -euo pipefail

ROOT="${0:A:h}"
cd "$ROOT"

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

FEATURES_FILE="$HOST_DIR/features.nix"

# Feature defaults (zsh associative arrays)
typeset -A CLI RICE APPS
CLI=(
  bat true btop true duti true eza true fd true fzf true
  gh true git true ncdu true ripgrep true starship true
  tldr true uv true zoxide true yazi true
)
RICE=(
  omniwm true sketchybar true jankyborders true skhd true
  ghostty true stylix true
)
APPS=(
  cursor true sublimeText true teamviewer false
  transmission true iina true libreoffice true geForceNow false
)

# --- Nix / Homebrew ----------------------------------------------------------

ensure_nix() {
  if (( $+commands[nix] )); then
    ok "Nix already installed: $(nix --version | head -1)"
    return
  fi
  info "Installing Nix (Determinate Systems installer)…"
  curl --proto '=https' --tlsv1.2 -sSfL https://install.determinate.systems/nix | sh -s -- install --no-confirm
  if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
    # shellcheck disable=SC1091
    source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi
  (( $+commands[nix] )) || die "Nix install finished but nix is not on PATH. Open a new terminal and re-run ./install.sh"
  ok "Nix installed"
}

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
  # $1 = array name (CLI|RICE|APPS), $2 = newline-separated selected keys
  local map_name="$1"
  local selected="$2"
  local key
  for key in ${(kP)map_name}; do
    eval "${map_name}[$key]=false"
  done
  for key in ${(f)selected}; do
    [[ -z "$key" ]] && continue
    eval "${map_name}[$key]=true"
  done
}

interactive_select() {
  local -a cli_keys=(bat btop duti eza fd fzf gh git ncdu ripgrep starship tldr uv zoxide yazi)
  local -a rice_keys=(omniwm sketchybar jankyborders skhd ghostty stylix)
  local -a apps_keys=(cursor sublimeText teamviewer transmission iina libreoffice geForceNow)
  local sel
  local -a gum_selected

  if (( $+commands[gum] )); then
    info "Select CLI tools (Space toggles, Enter confirms)"
    gum_selected=()
    for k in "${cli_keys[@]}"; do
      [[ "${CLI[$k]}" == "true" ]] && gum_selected+=(--selected "$k")
    done
    sel="$(gum choose --no-limit --header "CLI tools" "${gum_selected[@]}" "${cli_keys[@]}" || true)"
    [[ -n "$sel" ]] && apply_selection CLI "$sel"

    info "Select rice components"
    gum_selected=()
    for k in "${rice_keys[@]}"; do
      [[ "${RICE[$k]}" == "true" ]] && gum_selected+=(--selected "$k")
    done
    sel="$(gum choose --no-limit --header "Rice" "${gum_selected[@]}" "${rice_keys[@]}" || true)"
    [[ -n "$sel" ]] && apply_selection RICE "$sel"

    info "Select GUI apps"
    gum_selected=()
    for k in "${apps_keys[@]}"; do
      [[ "${APPS[$k]}" == "true" ]] && gum_selected+=(--selected "$k")
    done
    sel="$(gum choose --no-limit --header "GUI apps" "${gum_selected[@]}" "${apps_keys[@]}" || true)"
    [[ -n "$sel" ]] && apply_selection APPS "$sel"
  elif (( $+commands[fzf] )); then
    warn "gum not found — using fzf (TAB to multi-select)"
    sel="$(printf '%s\n' "${cli_keys[@]}" | fzf --multi --prompt 'CLI > ' || true)"
    [[ -n "$sel" ]] && apply_selection CLI "$sel"
    sel="$(printf '%s\n' "${rice_keys[@]}" | fzf --multi --prompt 'Rice > ' || true)"
    [[ -n "$sel" ]] && apply_selection RICE "$sel"
    sel="$(printf '%s\n' "${apps_keys[@]}" | fzf --multi --prompt 'Apps > ' || true)"
    [[ -n "$sel" ]] && apply_selection APPS "$sel"
  else
    warn "Neither gum nor fzf found — keeping defaults."
    info "Tip: brew install gum && re-run ./install.sh"
  fi
}

bool_nix() {
  [[ "$1" == "true" ]] && print true || print false
}

write_features() {
  info "Writing $FEATURES_FILE"
  cat >"$FEATURES_FILE" <<EOF
# Generated by ./install.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Re-run ./install.sh to change selections, or edit this file by hand.
{
  cli = {
    bat = $(bool_nix "${CLI[bat]}");
    btop = $(bool_nix "${CLI[btop]}");
    duti = $(bool_nix "${CLI[duti]}");
    eza = $(bool_nix "${CLI[eza]}");
    fd = $(bool_nix "${CLI[fd]}");
    fzf = $(bool_nix "${CLI[fzf]}");
    gh = $(bool_nix "${CLI[gh]}");
    git = $(bool_nix "${CLI[git]}");
    ncdu = $(bool_nix "${CLI[ncdu]}");
    ripgrep = $(bool_nix "${CLI[ripgrep]}");
    starship = $(bool_nix "${CLI[starship]}");
    tldr = $(bool_nix "${CLI[tldr]}");
    uv = $(bool_nix "${CLI[uv]}");
    zoxide = $(bool_nix "${CLI[zoxide]}");
    yazi = $(bool_nix "${CLI[yazi]}");
  };

  rice = {
    omniwm = $(bool_nix "${RICE[omniwm]}");
    sketchybar = $(bool_nix "${RICE[sketchybar]}");
    jankyborders = $(bool_nix "${RICE[jankyborders]}");
    skhd = $(bool_nix "${RICE[skhd]}");
    ghostty = $(bool_nix "${RICE[ghostty]}");
    stylix = $(bool_nix "${RICE[stylix]}");
  };

  apps = {
    cursor = $(bool_nix "${APPS[cursor]}");
    sublimeText = $(bool_nix "${APPS[sublimeText]}");
    teamviewer = $(bool_nix "${APPS[teamviewer]}");
    transmission = $(bool_nix "${APPS[transmission]}");
    iina = $(bool_nix "${APPS[iina]}");
    libreoffice = $(bool_nix "${APPS[libreoffice]}");
    geForceNow = $(bool_nix "${APPS[geForceNow]}");
  };
}
EOF
  ok "features.nix written"
}

ensure_flake_host() {
  if grep -q "\"$HOSTNAME\"" "$ROOT/flake.nix"; then
    return
  fi
  info "Adding darwinConfigurations.\"$HOSTNAME\" to flake.nix"
  local tmp
  tmp="$(mktemp)"
  awk -v host="$HOSTNAME" -v user="$USERNAME" '
    /# CURRENT_HOSTS_END/ && !done {
      print "        \"" host "\" = mkDarwin {";
      print "          hostname = \"" host "\";";
      print "          username = \"" user "\";";
      print "          hostPath = ./hosts/" host ";";
      print "        };";
      done=1
    }
    { print }
  ' "$ROOT/flake.nix" >"$tmp"
  mv "$tmp" "$ROOT/flake.nix"
}

rebuild() {
  info "Building and activating nix-darwin configuration…"
  local flake_attr="$HOSTNAME"
  # Activation must run as root on current nix-darwin.
  sudo nix run nix-darwin -- switch --flake "$ROOT#$flake_attr"
  ok "darwin-rebuild switch complete"
}

print_next_steps() {
  cat <<EOF

${GRN}Install finished.${RST}

Next steps:
  1. Read ${BLU}docs/PERMISSIONS.md${RST} and grant Accessibility / Input Monitoring.
  2. Log out and back in if Mission Control "Displays have separate Spaces" changed.
  3. Launch OmniWM, Ghostty, and confirm sketchybar / borders are running.
  4. Launcher is Spotlight for now (Cmd+Space). A riceable picker can be added later.

Useful commands:
  sudo darwin-rebuild switch --flake $ROOT#$HOSTNAME
  ./install.sh          # re-run interactive feature selection

EOF
}

# --- Main --------------------------------------------------------------------

NONINTERACTIVE=false
SKIP_REBUILD=false
for arg in "$@"; do
  case "$arg" in
    --yes|-y) NONINTERACTIVE=true ;;
    --no-rebuild) SKIP_REBUILD=true ;;
    --help|-h)
      print "Usage: ./install.sh [--yes] [--no-rebuild]"
      exit 0
      ;;
  esac
done

ensure_nix
ensure_brew

if ! (( $+commands[gum] )); then
  info "Installing gum for the interactive picker…"
  brew install gum || warn "Could not install gum"
  export PATH="/opt/homebrew/bin:$PATH"
fi

if $NONINTERACTIVE; then
  info "Non-interactive mode — keeping default feature flags"
else
  interactive_select
fi

write_features
ensure_flake_host

if ! $SKIP_REBUILD; then
  rebuild
fi

print_next_steps
