#!/bin/zsh
# Fix sketchybar vanishing / menu-bar flashes: set menu bar to Never hide.
set -euo pipefail

# "Never" needs both GlobalPreferences keys. Writing only _HIHideMenuBar=false
# leaves "In Full Screen Only", so OmniWM fill / some apps still show/hide the bar.
defaults write NSGlobalDomain _HIHideMenuBar -bool false
defaults write NSGlobalDomain AppleMenuBarVisibleInFullscreen -bool true
defaults write com.apple.controlcenter AutoHideMenuBarOption -int 3

print -r -- "_HIHideMenuBar=$(defaults read NSGlobalDomain _HIHideMenuBar)"
print -r -- "AppleMenuBarVisibleInFullscreen=$(defaults read NSGlobalDomain AppleMenuBarVisibleInFullscreen)"
print -r -- "AutoHideMenuBarOption=$(defaults read com.apple.controlcenter AutoHideMenuBarOption)"

killall SystemUIServer 2>/dev/null || true
killall ControlCenter 2>/dev/null || true
sleep 1

brew services restart sketchybar
sleep 1
bash "${HOME}/.config/sketchybar/sketchybarrc"
print -r -- "Done. Confirm: System Settings → Desktop & Dock → Automatically hide and show the menu bar → Never."
