#!/usr/bin/env zsh
# Build CalendarBar.app (SwiftPM) → ~/Applications, install CLI shim + LaunchAgent.
set -euo pipefail

ROOT="${0:A:h:h}"
SRC="$ROOT/apps/calendar-bar"
DEST_APP="${CALENDAR_BAR_APP_DIR:-$HOME/Applications}/CalendarBar.app"
BIN_DIR="${CALENDAR_BAR_BIN_DIR:-$HOME/.local/bin}"
PLIST_DST="$HOME/Library/LaunchAgents/com.dotfiles.calendar-bar.plist"
LABEL="com.dotfiles.calendar-bar"
EXEC="$DEST_APP/Contents/MacOS/CalendarBar"
# Self-signed identity so Calendar TCC survives rebuilds (adhoc pins cdhash).
CODESIGN_IDENTITY="${CALENDAR_BAR_CODESIGN_IDENTITY:-dotfiles-CalendarBar}"

info() { print -r -- "==> $*"; }
ok() { print -r -- "✓ $*"; }
warn() { print -r -- "! $*" >&2; }
die() { print -r -- "error: $*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "CalendarBar builds only on macOS."
(( $+commands[swift] )) || die "swift not found — install Xcode or the Command Line Tools."

# Stable identity in a dedicated keychain (no Keychain popups on every rebuild).
# shellcheck source=lib/stable-codesign.sh
source "$ROOT/scripts/lib/stable-codesign.sh"

info "Building CalendarBar (release)…"
(
  cd "$SRC"
  swift build -c release --product CalendarBar
)

BIN="$SRC/.build/release/CalendarBar"
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
  if [[ -n "${IDENTITY:-}" ]] \
    && sign_app "$DEST_APP" --entitlements "$SRC/Resources/CalendarBar.entitlements"; then
    SIGNED_WITH="$IDENTITY"
    ok "Signed with $IDENTITY (Calendar grant survives rebuilds)"
  else
    warn "Stable codesign failed — falling back to ad-hoc (Calendar access may reset each rebuild)"
    codesign --force --sign - \
      --entitlements "$SRC/Resources/CalendarBar.entitlements" \
      "$DEST_APP" 2>/dev/null || warn "codesign failed"
  fi
  codesign -d -r- "$DEST_APP" 2>&1 | sed -n 's/^designated => /  DR: /p' || true
fi

if [[ -x /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister ]]; then
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST_APP" 2>/dev/null || true
fi

mkdir -p "$BIN_DIR"
# Prefer the stowed shim from packages/calendar. Only write a fallback when the
# target is missing — never replace an existing regular file (that breaks stow).
if [[ -L "$BIN_DIR/calendar-bar" ]]; then
  ok "CLI → $BIN_DIR/calendar-bar (stowed)"
elif [[ -e "$BIN_DIR/calendar-bar" ]]; then
  warn "CLI shim exists as a regular file at $BIN_DIR/calendar-bar"
  warn "Remove it and restow so packages/calendar can own the link:"
  warn "  rm -f \"$BIN_DIR/calendar-bar\" && ./scripts/restow.sh"
elif [[ -f "$ROOT/packages/calendar/.local/bin/calendar-bar" ]]; then
  warn "No CLI shim yet — stow the calendar package (./install.sh or ./scripts/restow.sh)"
else
  cat >"$BIN_DIR/calendar-bar" <<EOF
#!/bin/sh
exec "$EXEC" "\$@"
EOF
  chmod +x "$BIN_DIR/calendar-bar"
  ok "CLI → $BIN_DIR/calendar-bar (local fallback shim)"
fi

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
	<string>/tmp/calendar-bar.out.log</string>
	<key>StandardErrorPath</key>
	<string>/tmp/calendar-bar.err.log</string>
</dict>
</plist>
EOF

info "Loading LaunchAgent $LABEL"
launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST" 2>/dev/null \
  || launchctl load -w "$PLIST_DST" 2>/dev/null \
  || warn "Could not load LaunchAgent — start manually: open \"$DEST_APP\""

ok "CalendarBar installed"
print -r -- "  App:    $DEST_APP"
print -r -- "  CLI:    calendar-bar --toggle"
print -r -- "  Signed: $SIGNED_WITH"
print -r -- "  Grant Calendars to CalendarBar (see docs/PERMISSIONS.md)"
if [[ "$SIGNED_WITH" != "ad-hoc" ]]; then
  print -r -- "  First time after switching off ad-hoc: remove any old CalendarBar rows in"
  print -r -- "  Privacy → Calendars, then add ~/Applications/CalendarBar.app once."
fi
