#!/usr/bin/env zsh
# Build ~/Applications/{Yazi,Btop}.app — Ghostty-backed launchers with official icons.
# Yazi: shell wrapper (cwd on quit) then drop to a login shell → Ghostty stays open.
# Btop: runs btop directly; Ghostty quits when btop exits.
set -euo pipefail

ROOT="${0:A:h:h}"
ICONS="$ROOT/assets/app-icons"
DEST="${CLI_APPS_DIR:-$HOME/Applications}"

info() { print -r -- "==> $*"; }
ok() { print -r -- "✓ $*"; }
warn() { print -r -- "! $*" >&2; }

brew_bin() {
  local name="$1"
  if [[ -x "/opt/homebrew/bin/$name" ]]; then
    print -r -- "/opt/homebrew/bin/$name"
  elif [[ -x "/usr/local/bin/$name" ]]; then
    print -r -- "/usr/local/bin/$name"
  elif (( $+commands[$name] )); then
    command -v "$name"
  else
    return 1
  fi
}

# PNG → .icns via iconutil
png_to_icns() {
  local png="$1" icns="$2"
  local iconset="${icns%.icns}.iconset"
  rm -rf "$iconset"
  mkdir -p "$iconset"
  local s
  for s in 16 32 128 256 512; do
    sips -z "$s" "$s" "$png" --out "$iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$png" --out "$iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$iconset" -o "$icns"
  rm -rf "$iconset"
}

write_info_plist() {
  local plist="$1" name="$2" bundle_id="$3"
  cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>${name}</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>${bundle_id}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>${name}</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
EOF
}

install_yazi_app() {
  local yazi
  if ! yazi="$(brew_bin yazi)"; then
    warn "yazi not found — skip Yazi.app"
    return 1
  fi
  [[ -f "$ICONS/yazi.png" ]] || { warn "missing $ICONS/yazi.png"; return 1; }

  local app="$DEST/Yazi.app"
  local contents="$app/Contents"
  local macos="$contents/MacOS"
  local resources="$contents/Resources"
  local script="$resources/run-yazi.sh"

  info "Installing $app"
  rm -rf "$app"
  mkdir -p "$macos" "$resources"

  # Wrapper: cwd-file like the shell `y` function, then keep Ghostty open via login shell.
  cat >"$script" <<EOF
#!/bin/zsh
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:\${PATH}"
YAZI="${yazi}"
tmp="\$(mktemp -t yazi-cwd.XXXXXX)"
"\$YAZI" "\$@" --cwd-file="\$tmp" || true
if cwd="\$(<"\$tmp")" && [[ -n "\$cwd" && -d "\$cwd" ]]; then
  cd -- "\$cwd"
fi
rm -f -- "\$tmp"
exec /bin/zsh -l
EOF
  chmod +x "$script"

  # quit-after=true so this Ghostty instance dies when the login shell exits;
  # the wrapper's `exec zsh` keeps the window open after quitting yazi.
  cat >"$macos/Yazi" <<EOF
#!/bin/zsh
set -euo pipefail
SCRIPT="${script}"
exec /usr/bin/open -na Ghostty.app --args \\
  --title=Yazi \\
  --quit-after-last-window-closed=true \\
  -e "\$SCRIPT"
EOF
  chmod +x "$macos/Yazi"

  write_info_plist "$contents/Info.plist" Yazi com.dotfiles.yazi
  png_to_icns "$ICONS/yazi.png" "$resources/AppIcon.icns"
  ok "Yazi.app → quit yazi drops to Ghostty shell"
}

install_btop_app() {
  local btop
  if ! btop="$(brew_bin btop)"; then
    warn "btop not found — skip Btop.app"
    return 1
  fi
  [[ -f "$ICONS/btop.png" ]] || { warn "missing $ICONS/btop.png"; return 1; }

  local app="$DEST/Btop.app"
  local contents="$app/Contents"
  local macos="$contents/MacOS"
  local resources="$contents/Resources"
  local script="$resources/run-btop.sh"

  info "Installing $app"
  rm -rf "$app"
  mkdir -p "$macos" "$resources"

  cat >"$script" <<EOF
#!/bin/zsh
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:\${PATH}"
exec "${btop}" "\$@"
EOF
  chmod +x "$script"

  cat >"$macos/Btop" <<EOF
#!/bin/zsh
set -euo pipefail
SCRIPT="${script}"
exec /usr/bin/open -na Ghostty.app --args \\
  --title=btop \\
  --quit-after-last-window-closed=true \\
  -e "\$SCRIPT"
EOF
  chmod +x "$macos/Btop"

  write_info_plist "$contents/Info.plist" Btop com.dotfiles.btop
  png_to_icns "$ICONS/btop.png" "$resources/AppIcon.icns"
  ok "Btop.app → quitting btop exits Ghostty"
}

main() {
  if [[ ! -d /Applications/Ghostty.app ]]; then
    warn "Ghostty.app not found in /Applications — CLI apps need Ghostty"
    return 1
  fi
  mkdir -p "$DEST"

  local do_yazi=true do_btop=true
  case "${1:-}" in
    yazi) do_btop=false ;;
    btop) do_yazi=false ;;
    ""|all) ;;
    *) print "Usage: $0 [all|yazi|btop]"; return 1 ;;
  esac

  $do_yazi && install_yazi_app || true
  $do_btop && install_btop_app || true
}

main "$@"
