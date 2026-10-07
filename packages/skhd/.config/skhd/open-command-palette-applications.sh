#!/bin/sh
# Open OmniWM command palette on the Applications tab (Alt+R via skhd).
# OmniWM 0.7.x IPC only supports `open-command-palette` (no mode argument yet);
# Cmd+5 is the palette's built-in Applications shortcut.

set -eu

OMNIWMCTL="${OMNIWMCTL:-/opt/homebrew/bin/omniwmctl}"
if [ ! -x "$OMNIWMCTL" ]; then
  OMNIWMCTL="$(command -v omniwmctl 2>/dev/null || true)"
fi
[ -n "${OMNIWMCTL:-}" ] && [ -x "$OMNIWMCTL" ] || exit 1

"$OMNIWMCTL" command open-command-palette

# Let the palette take keyboard focus before sending the tab chord.
sleep 0.12

osascript <<'APPLESCRIPT'
tell application "System Events"
  keystroke "5" using command down
end tell
APPLESCRIPT
