#!/bin/sh
# Open / toggle the notch Launcher (manual / fallback; rice uses Carbon Alt+R).
set -eu

LAUNCHER="${LAUNCHER_BIN:-$HOME/.local/bin/launcher}"
if [ ! -x "$LAUNCHER" ]; then
  if [ -x "$HOME/Applications/Launcher.app/Contents/MacOS/Launcher" ]; then
    LAUNCHER="$HOME/Applications/Launcher.app/Contents/MacOS/Launcher"
  elif command -v launcher >/dev/null 2>&1; then
    LAUNCHER="$(command -v launcher)"
  else
    exit 1
  fi
fi

exec "$LAUNCHER" --toggle
