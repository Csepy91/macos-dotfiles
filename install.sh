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
    CLI) all_keys=(bat btop duti eza fd fzf gh git ncdu nvim ripgrep starship tldr uv zoxide yazi) ;;
    RICE) all_keys=(omniwm skhd ghostty launcher calendar bar) ;;
    APPS) all_keys=(cursor sublimeText teamviewer transmission iina libreoffice geForceNow zen) ;;
  esac
  local key
  for key in "${all_keys[@]}"; do
    eval "${prefix}_${key}=false"
  done
  for key in ${(f)selected}; do
    [[ -z "$key" ]] && continue
    # Only accept known keys — never eval gum/fzf error text.
    if (( ${all_keys[(Ie)$key]} )); then
      eval "${prefix}_${key}=true"
    fi
  done
}

# gum's style flags read bare $BORDER as a border *style* enum (rounded/none/…).
# Our theme used to export BORDER=#hex which breaks `gum choose`.
gum_run() {
  env -u BORDER -u BORDER_FOREGROUND -u BORDER_BACKGROUND \
    gum "$@"
}

gum_choose() {
  gum_run choose "$@"
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
  local -a cli_keys=(bat btop duti eza fd fzf gh git ncdu nvim ripgrep starship tldr uv zoxide yazi)
  local -a rice_keys=(omniwm skhd ghostty launcher calendar bar)
  local -a apps_keys=(cursor sublimeText teamviewer transmission iina libreoffice geForceNow zen)
  local sel
  local -a gum_selected

  if (( $+commands[gum] )); then
    info "Select CLI tools (Space toggles, Enter confirms)"
    gum_selected=(${(z)$(gum_selected_args CLI "${cli_keys[@]}")})
    sel="$(gum_choose --no-limit --header "CLI tools" "${gum_selected[@]}" "${cli_keys[@]}" || true)"
    if [[ -n "$sel" ]]; then
      apply_selection CLI "$sel"
    fi

    info "Select rice components"
    gum_selected=(${(z)$(gum_selected_args RICE "${rice_keys[@]}")})
    sel="$(gum_choose --no-limit --header "Rice" "${gum_selected[@]}" "${rice_keys[@]}" || true)"
    if [[ -n "$sel" ]]; then
      apply_selection RICE "$sel"
    fi

    info "Select GUI apps"
    gum_selected=(${(z)$(gum_selected_args APPS "${apps_keys[@]}")})
    sel="$(gum_choose --no-limit --header "GUI apps" "${gum_selected[@]}" "${apps_keys[@]}" || true)"
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
  local -a koekeishiya_formulae=()
  if $RICE_skhd; then
    koekeishiya_formulae+=(skhd)
  fi

  {
    print -r -- "# Generated by ./install.sh — do not edit by hand; re-run the installer."

    if (( ${#koekeishiya_formulae[@]} > 0 )); then
      print -r -- "tap \"koekeishiya/formulae\", trusted: {"
      print -r -- "  formulae: [$(printf '"%s", ' "${koekeishiya_formulae[@]}" | sed 's/, $//')],"
      print -r -- "}"
    fi

    print -r -- ""

    local f
    for f in ${(z)$(features_brew_formulae)}; do
      case "$f" in
        skhd) print -r -- "brew \"koekeishiya/formulae/skhd\", trusted: true" ;;
        *) print -r -- "brew \"$f\"" ;;
      esac
    done

    print -r -- ""
    local c
    for c in ${(z)$(features_brew_casks)}; do
      print -r -- "cask \"$c\""
    done
  } >"$out"
  ok "Brewfile written"
}

# Grant brew tap trust for third-party rice formulae (Homebrew 6+).
# Brewfile trusted: entries cover brew bundle; this covers direct brew installs too.
ensure_brew_trust() {
  if ! brew trust --help &>/dev/null; then
    warn "brew trust unavailable — skipping (upgrade Homebrew if third-party taps fail)"
    return 0
  fi

  info "Trusting third-party formulae for brew bundle…"
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

# Render palette tokens into ~/.config (plain files). Runs after stow.
apply_theme_palette() {
  local palette="cinematic-noir"
  if [[ -f "$HOME/.config/theme/active" ]]; then
    palette="$(<"$HOME/.config/theme/active")"
    palette="${palette%%$'\n'*}"
  fi
  local apply="$HOME/.config/theme/apply.sh"
  if [[ ! -x "$apply" ]]; then
    apply="$ROOT/packages/theme/.config/theme/apply.sh"
  fi
  if [[ ! -f "$apply" ]]; then
    warn "theme apply.sh missing — skip palette render"
    return 0
  fi
  info "Applying theme palette: $palette"
  if zsh "$apply" apply "$palette"; then
    ok "theme apply complete ($palette)"
  else
    warn "theme apply failed — run: theme apply $palette"
  fi
}

stow_packages() {
  local -a pkgs
  pkgs=(${(z)$(features_stow_packages)})
  [[ ${#pkgs[@]} -gt 0 ]] || return 0

  mkdir -p \
    "$HOME/.config" \
    "$HOME/.local/bin" \
    "$HOME/.local/share/zsh/site-functions" \
    "$HOME/Library/LaunchAgents" \
    "$HOME/Library/Logs/omniwm"

  info "Stowing packages → \$HOME: ${pkgs[*]}"
  # Restow so re-runs update links; adopt conflicts only when --adopt is passed.
  # --no-folding: keep real dirs under ~/.config so `theme apply` can write plain
  # generated theme files beside stowed symlinks without dirtying packages/.
  local -a stow_args=(-d "$ROOT/packages" -t "$HOME" -R --no-folding)
  if $STOW_ADOPT; then
    stow_args+=(--adopt)
  fi

  stow "${stow_args[@]}" "${pkgs[@]}"
  ok "stow complete"

  apply_theme_palette

  # Ensure skhd helpers are executable
  if [[ -d "$HOME/.config/skhd" ]]; then
    chmod +x "$HOME/.config/skhd"/*.sh 2>/dev/null || true
  fi
  if [[ -f "$HOME/.local/bin/launcher" ]]; then
    chmod +x "$HOME/.local/bin/launcher"
  fi
  if [[ -f "$HOME/.local/bin/calendar-bar" ]]; then
    chmod +x "$HOME/.local/bin/calendar-bar"
  fi
  if [[ -f "$HOME/.local/bin/bar" ]]; then
    chmod +x "$HOME/.local/bin/bar"
  fi
}

# --- Post-stow CLI setup -----------------------------------------------------

# Returns 0 on yes, 1 on no. Safe under `set -e` when used in `if confirm …; then`.
confirm() {
  local prompt="$1"
  if (( $+commands[gum] )); then
    gum_run confirm --default=false "$prompt"
    return $?
  fi
  local reply
  print -n "$prompt [y/N]: "
  read -r reply || true
  [[ "$reply" == [Yy]* ]]
}

# Write name/email to ~/.gitconfig.local (included by stowed ~/.gitconfig).
# Optional: user can skip; --yes never prompts.
configure_git_identity() {
  if ! $CLI_git; then
    return 0
  fi
  if $NONINTERACTIVE; then
    if [[ -f "$HOME/.gitconfig.local" ]]; then
      ok "git identity present (skipped prompt in --yes mode)"
    else
      warn "Skipping git name/email prompt (--yes) — run: ./install.sh  or edit ~/.gitconfig.local"
    fi
    return 0
  fi

  local name email
  name="$(git config --file "$HOME/.gitconfig.local" user.name 2>/dev/null || true)"
  email="$(git config --file "$HOME/.gitconfig.local" user.email 2>/dev/null || true)"
  [[ -z "$name" ]] && name="$(git config user.name 2>/dev/null || true)"
  [[ -z "$email" ]] && email="$(git config user.email 2>/dev/null || true)"

  local prompt="Configure git user.name and user.email?"
  if [[ -n "$name" && -n "$email" ]]; then
    prompt="Update git identity ($name <$email>)?"
  fi
  if ! confirm "$prompt"; then
    if [[ -n "$name" && -n "$email" ]]; then
      ok "Keeping existing git identity"
    else
      info "Skipping git identity — set later in ~/.gitconfig.local"
    fi
    return 0
  fi

  info "Git identity (stored in ~/.gitconfig.local, not in the repo)"
  if (( $+commands[gum] )); then
    name="$(gum_run input --placeholder "Your Name" --value "${name}" --header "Git user.name" || true)"
    email="$(gum_run input --placeholder "you@example.com" --value "${email}" --header "Git user.email" || true)"
  else
    print -n "Git user.name [${name}]: "
    local reply
    read -r reply || true
    [[ -n "$reply" ]] && name="$reply"
    print -n "Git user.email [${email}]: "
    read -r reply || true
    [[ -n "$reply" ]] && email="$reply"
  fi

  if [[ -z "$name" || -z "$email" ]]; then
    warn "Git name/email incomplete — set later in ~/.gitconfig.local"
    return 0
  fi

  git config --file "$HOME/.gitconfig.local" user.name "$name"
  git config --file "$HOME/.gitconfig.local" user.email "$email"
  ok "git identity: $name <$email>"
}

# Optional: skip if already logged in, or if the user declines. --yes never prompts.
ensure_gh_auth() {
  if ! $CLI_gh; then
    return 0
  fi
  if ! (( $+commands[gh] )); then
    warn "gh selected but not on PATH — skip auth"
    return 0
  fi
  if gh auth status &>/dev/null; then
    ok "gh already authenticated"
    return 0
  fi
  if $NONINTERACTIVE; then
    warn "Skipping gh auth login (--yes) — run: gh auth login"
    return 0
  fi

  if ! confirm "Authenticate with GitHub CLI (gh auth login)?"; then
    info "Skipping gh auth — run: gh auth login"
    return 0
  fi

  info "GitHub CLI login (follow the prompts)…"
  if gh auth login; then
    ok "gh auth complete"
  else
    warn "gh auth login failed — run: gh auth login"
  fi
}

# bat themes and tldr's page DB need a one-shot init after first install / restow.
post_install_cli() {
  if $CLI_bat; then
    if (( $+commands[bat] )); then
      info "Rebuilding bat theme cache…"
      if bat cache --build; then
        ok "bat cache rebuilt"
      else
        warn "bat cache --build failed"
      fi
    else
      warn "bat selected but not on PATH — skip cache rebuild"
    fi
  fi

  if $CLI_tldr; then
    if (( $+commands[tldr] )); then
      # C client (Homebrew tldr): ~/.tldrc/tldr/pages
      # tealdeer / tlrc also accept `tldr --update`; skip if any known cache exists.
      local tldr_cache="${TLDR_CACHE_DIR:-$HOME/.tldrc}"
      if [[ -d "$tldr_cache/tldr/pages" ]] \
        || [[ -d "$HOME/.cache/tealdeer" ]] \
        || [[ -d "$HOME/.cache/tlrc" ]]; then
        ok "tldr cache already present"
      else
        info "Initializing tldr page cache…"
        if tldr --update; then
          ok "tldr cache initialized"
        else
          warn "tldr --update failed — run: tldr --update"
        fi
      fi
    else
      warn "tldr selected but not on PATH — skip init"
    fi
  fi

  if $CLI_duti; then
    local duti_script="$ROOT/scripts/apply-duti.sh"
    [[ -x "$duti_script" ]] || chmod +x "$duti_script"
    if (( $+commands[duti] )); then
      info "Applying default file handlers (Sublime Text / IINA)…"
      "$duti_script" || warn "duti apply failed"
    else
      warn "duti selected but not on PATH — skip handlers"
    fi
  fi

  configure_git_identity
  ensure_gh_auth
}

# Ghostty-backed .app wrappers in ~/Applications (official icons).
install_cli_apps() {
  local script="$ROOT/scripts/install-cli-apps.sh"
  [[ -x "$script" ]] || chmod +x "$script"

  if $CLI_yazi || $CLI_btop; then
    info "Installing CLI app wrappers → ~/Applications"
  fi
  if $CLI_yazi; then
    "$script" yazi || warn "Yazi.app install failed"
  fi
  if $CLI_btop; then
    "$script" btop || warn "Btop.app install failed"
  fi
}

# Notch launcher (SwiftPM) → ~/Applications/Launcher.app + LaunchAgent.
install_launcher_app() {
  if ! $RICE_launcher; then
    return 0
  fi
  local script="$ROOT/scripts/install-launcher.sh"
  [[ -x "$script" ]] || chmod +x "$script"
  info "Building / installing Launcher…"
  if "$script"; then
    ok "Launcher ready (Alt+R via skhd)"
  else
    warn "Launcher install failed — run: ./scripts/install-launcher.sh"
  fi
}

# Notch calendar (SwiftPM) → ~/Applications/CalendarBar.app + LaunchAgent.
install_calendar_bar_app() {
  if ! $RICE_calendar; then
    return 0
  fi
  local script="$ROOT/scripts/install-calendar-bar.sh"
  [[ -x "$script" ]] || chmod +x "$script"
  info "Building / installing CalendarBar…"
  if "$script"; then
    ok "CalendarBar ready (calendar-bar --toggle)"
  else
    warn "CalendarBar install failed — run: ./scripts/install-calendar-bar.sh"
  fi
}

# OmniWM workspace bar (SwiftPM) → ~/Applications/Bar.app + LaunchAgent.
install_bar_app() {
  if ! $RICE_bar; then
    return 0
  fi
  local script="$ROOT/scripts/install-bar.sh"
  [[ -x "$script" ]] || chmod +x "$script"
  info "Building / installing Bar…"
  if "$script"; then
    ok "Bar ready (OmniWM workspace indicator)"
  else
    warn "Bar install failed — run: ./scripts/install-bar.sh"
  fi
}

# --- Wallpaper ---------------------------------------------------------------

apply_wallpaper() {
  local src="$ROOT/configs/wallpapers/default.png"
  if [[ ! -f "$src" ]]; then
    warn "No wallpaper at configs/wallpapers/default.png — skip"
    return 0
  fi

  local dest_dir="$HOME/.config/wallpaper"
  local dest="$dest_dir/default.png"
  mkdir -p "$dest_dir"
  cp -f "$src" "$dest"

  info "Setting desktop wallpaper → $dest"
  if /usr/bin/osascript <<EOF
set img to POSIX file "$dest"
tell application "System Events"
  repeat with d in (a reference to every desktop)
    try
      set picture of d to img
    end try
  end repeat
end tell
EOF
  then
    ok "Wallpaper set on all desktops"
  else
    warn "Could not set wallpaper via System Events"
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
  # Prefer restart so a freshly stowed skhdrc (e.g. Alt+R → launcher) is loaded;
  # --start-service alone is a no-op when skhd is already running.
  "$bin" --install-service 2>/dev/null || true
  if "$bin" --restart-service 2>/dev/null; then
    ok "skhd service restarted"
  elif "$bin" --start-service; then
    ok "skhd service started"
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
  if $RICE_launcher; then
    local label="com.dotfiles.launcher"
    local plist="$HOME/Library/LaunchAgents/${label}.plist"
    if [[ -f "$plist" ]]; then
      launchctl bootout "gui/$(id -u)/${label}" 2>/dev/null || true
      launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null \
        || launchctl load -w "$plist" 2>/dev/null \
        || warn "Could not load Launcher LaunchAgent — run: ./scripts/install-launcher.sh"
    fi
  fi
  if $RICE_calendar; then
    local label="com.dotfiles.calendar-bar"
    local plist="$HOME/Library/LaunchAgents/${label}.plist"
    if [[ -f "$plist" ]]; then
      launchctl bootout "gui/$(id -u)/${label}" 2>/dev/null || true
      launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null \
        || launchctl load -w "$plist" 2>/dev/null \
        || warn "Could not load CalendarBar LaunchAgent — run: ./scripts/install-calendar-bar.sh"
    fi
  fi
  if $RICE_bar; then
    local label="com.dotfiles.bar"
    local plist="$HOME/Library/LaunchAgents/${label}.plist"
    if [[ -f "$plist" ]]; then
      launchctl bootout "gui/$(id -u)/${label}" 2>/dev/null || true
      launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null \
        || launchctl load -w "$plist" 2>/dev/null \
        || warn "Could not load Bar LaunchAgent — run: ./scripts/install-bar.sh"
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
  4. Launch OmniWM, Ghostty, and confirm Bar / skhd are running (OmniWM draws window borders).
  5. Launcher: Alt+R toggles the notch panel; Alt+Shift+R opens Menu Search.
  6. CalendarBar: \`calendar-bar --toggle\` (wire via skhd as needed).
  7. Bar: OmniWM workspace strip (\`./scripts/install-bar.sh\` / \`bar --reload\`).

Useful commands:
  /opt/homebrew/bin/skhd --install-service && /opt/homebrew/bin/skhd --start-service
  /opt/homebrew/bin/skhd --restart-service   # only after the service plist exists
  brew bundle --file $ROOT/Brewfile
  stow -d $ROOT/packages -t \$HOME -R --no-folding zsh theme git ghostty …
  theme apply cinematic-noir      # render palette into ~/.config
  ./scripts/install-cli-apps.sh   # rebuild ~/Applications/{Yazi,Btop}.app
  ./scripts/install-launcher.sh   # rebuild ~/Applications/Launcher.app
  ./scripts/install-calendar-bar.sh  # rebuild ~/Applications/CalendarBar.app
  ./scripts/install-bar.sh        # rebuild ~/Applications/Bar.app (phase 1)
  ./scripts/apply-duti.sh         # re-apply Sublime/IINA default handlers
  gh auth login                   # if skipped during install / --yes
  # git identity: edit ~/.gitconfig.local  (or re-run ./install.sh)
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
  post_install_cli
  install_cli_apps
  install_launcher_app
  install_calendar_bar_app
  install_bar_app
  apply_wallpaper
  start_services
else
  stow_packages
  post_install_cli
  install_cli_apps
  install_launcher_app
  install_calendar_bar_app
  install_bar_app
  apply_wallpaper
  warn "Skipped brew bundle / services (--no-bundle)"
fi

print_next_steps
