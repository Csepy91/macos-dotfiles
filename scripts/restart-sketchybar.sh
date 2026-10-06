#!/bin/zsh
# Restart sketchybar and reload config (run in your terminal).
set -euo pipefail

brew services restart sketchybar
sleep 1
bash "${HOME}/.config/sketchybar/sketchybarrc"
print -r -- "sketchybar restarted."
