#!/usr/bin/env zsh
# Build Launcher.app (SwiftPM) → ~/Applications, install CLI shim + LaunchAgent.
set -euo pipefail

ROOT="${0:A:h:h}"
SRC="$ROOT/apps/launcher"
DEST_APP="${LAUNCHER_APP_DIR:-$HOME/Applications}/Launcher.app"
BIN_DIR="${LAUNCHER_BIN_DIR:-$HOME/.local/bin}"
PLIST_DST="$HOME/Library/LaunchAgents/com.dotfiles.launcher.plist"
LABEL="com.dotfiles.launcher"
EXEC="$DEST_APP/Contents/MacOS/Launcher"
# Self-signed identity so Accessibility TCC survives rebuilds (adhoc pins cdhash).
CODESIGN_IDENTITY="${LAUNCHER_CODESIGN_IDENTITY:-dotfiles-Launcher}"

info() { print -r -- "==> $*"; }
ok() { print -r -- "✓ $*"; }
warn() { print -r -- "! $*" >&2; }
die() { print -r -- "error: $*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "Launcher builds only on macOS."
(( $+commands[swift] )) || die "swift not found — install Xcode or the Command Line Tools."

# Stable identity in a dedicated keychain (no Keychain popups on every rebuild).
# shellcheck source=lib/stable-codesign.sh
source "$ROOT/scripts/lib/stable-codesign.sh"

info "Building Launcher (release)…"
(
  cd "$SRC"
  swift build -c release --product Launcher
)

BIN="$SRC/.build/release/Launcher"
[[ -x "$BIN" ]] || die "Build succeeded but binary missing at $BIN"

info "Assembling $DEST_APP"
rm -rf "$DEST_APP"
mkdir -p "$DEST_APP/Contents/MacOS" "$DEST_APP/Contents/Resources"
cp "$BIN" "$EXEC"
cp "$SRC/Resources/Info.plist" "$DEST_APP/Contents/Info.plist"
xattr -cr "$DEST_APP" 2>/dev/null || true

SIGNED_WITH="ad-hoc"
if (( $+commands[codesign] )); then
  IDENTITY="$(ensure_codesign_identity || true)"
  if [[ -n "${IDENTITY:-}" ]] && sign_app "$DEST_APP"; then
    SIGNED_WITH="$IDENTITY"
    ok "Signed with $IDENTITY (Accessibility grant survives rebuilds)"
  else
    warn "Stable codesign failed — falling back to ad-hoc (Accessibility will reset each rebuild)"
    codesign --force --sign - "$DEST_APP" 2>/dev/null || warn "codesign failed"
  fi
  codesign -d -r- "$DEST_APP" 2>&1 | sed -n 's/^designated => /  DR: /p' || true
fi

# Refresh Launch Services so System Settings can resolve the bundle.
if [[ -x /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister ]]; then
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST_APP" 2>/dev/null || true
fi

mkdir -p "$BIN_DIR"
# Prefer the stowed shim if present; otherwise write one that points at the app.
if [[ ! -e "$BIN_DIR/launcher" ]]; then
  cat >"$BIN_DIR/launcher" <<EOF
#!/bin/sh
exec "$EXEC" "\$@"
EOF
  chmod +x "$BIN_DIR/launcher"
fi
ok "CLI → $BIN_DIR/launcher (stowed or local shim)"

info "Writing LaunchAgent $LABEL"
mkdir -p "$(dirname "$PLIST_DST")"
cat >"$PLIST_DST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>${LABEL}</string>
	<key>AssociatedBundleIdentifiers</key>
	<array>
		<string>${LABEL}</string>
	</array>
	<key>ProgramArguments</key>
	<array>
		<string>${EXEC}</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>ThrottleInterval</key>
	<integer>10</integer>
	<key>StandardOutPath</key>
	<string>/tmp/launcher.out.log</string>
	<key>StandardErrorPath</key>
	<string>/tmp/launcher.err.log</string>
</dict>
</plist>
EOF

info "Loading LaunchAgent $LABEL"
launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST" 2>/dev/null \
  || launchctl load -w "$PLIST_DST" 2>/dev/null \
  || warn "Could not load LaunchAgent — start manually: open \"$DEST_APP\""

ok "Launcher installed"
print -r -- "  App:    $DEST_APP"
print -r -- "  CLI:    launcher --toggle"
print -r -- "  Signed: $SIGNED_WITH"
print -r -- "  Grant Accessibility to Launcher (see docs/PERMISSIONS.md)"
if [[ "$SIGNED_WITH" != "ad-hoc" ]]; then
  print -r -- "  First time after switching off ad-hoc: remove any old Launcher rows in"
  print -r -- "  Accessibility, then add ~/Applications/Launcher.app once."
fi
