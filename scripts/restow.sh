#!/usr/bin/env zsh
# Restow packages for the current host's feature flags.
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
source "$ROOT/lib/features.sh"

RAW_HOST="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
HOSTNAME="${RAW_HOST//./-}"
FEATURES_FILE="$ROOT/hosts/$HOSTNAME/features.conf"
[[ -f "$FEATURES_FILE" ]] || FEATURES_FILE="$ROOT/hosts/default/features.conf"
features_load "$FEATURES_FILE"

eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || true)"

pkgs=(${(z)$(features_stow_packages)})
mkdir -p "$HOME/.config" "$HOME/.local/bin" "$HOME/Library/LaunchAgents"
stow -d "$ROOT/packages" -t "$HOME" -R "$@" "${pkgs[@]}"
print -r -- "Restowed: ${pkgs[*]}"
