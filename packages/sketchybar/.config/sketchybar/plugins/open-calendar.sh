#!/usr/bin/env bash
# Toggle the notch CalendarBar panel from the sketchybar clock.
set -euo pipefail

CALENDAR_BAR="${CALENDAR_BAR_BIN:-$HOME/.local/bin/calendar-bar}"

if [[ -x "$CALENDAR_BAR" ]]; then
  exec "$CALENDAR_BAR" --toggle
elif command -v calendar-bar >/dev/null 2>&1; then
  exec calendar-bar --toggle
else
  echo "calendar-bar not found — run ./scripts/install-calendar-bar.sh" >&2
  exit 127
fi
