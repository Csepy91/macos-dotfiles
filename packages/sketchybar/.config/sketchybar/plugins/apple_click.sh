#!/usr/bin/env bash
# Open the native Apple menu (About / System Settings / Restart / Shut Down…).
# Requires Accessibility for osascript / System Events.
osascript <<'APPLESCRIPT'
tell application "System Events"
  set frontApp to first application process whose frontmost is true
  tell frontApp
    click menu bar item "Apple" of menu bar 1
  end tell
end tell
APPLESCRIPT
