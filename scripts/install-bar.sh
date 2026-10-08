#!/usr/bin/env zsh
# Build Bar.app (SwiftPM) → ~/Applications, install CLI shim + LaunchAgent.
set -euo pipefail

ROOT="${0:A:h:h}"
SRC="$ROOT/apps/bar"
DEST_APP="${BAR_APP_DIR:-$HOME/Applications}/Bar.app"
BIN_DIR="${BAR_BIN_DIR:-$HOME/.local/bin}"
PLIST_DST="$HOME/Library/LaunchAgents/com.dotfiles.bar.plist"
LABEL="com.dotfiles.bar"
EXEC="$DEST_APP/Contents/MacOS/Bar"
# Self-signed identity so TCC grants survive rebuilds (adhoc pins cdhash).
CODESIGN_IDENTITY="${BAR_CODESIGN_IDENTITY:-dotfiles-Bar}"

info() { print -r -- "==> $*"; }
ok() { print -r -- "✓ $*"; }
warn() { print -r -- "! $*" >&2; }
die() { print -r -- "error: $*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "Bar builds only on macOS."
(( $+commands[swift] )) || die "swift not found — install Xcode or the Command Line Tools."

# Stable identity in a dedicated keychain (no Keychain popups on every rebuild).
# shellcheck source=lib/stable-codesign.sh
source "$ROOT/scripts/lib/stable-codesign.sh"

info "Building Bar (release)…"
(
  cd "$SRC"
  swift build -c release --product Bar
)

BIN="$SRC/.build/release/Bar"
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
    && sign_app "$DEST_APP" --entitlements "$SRC/Resources/Bar.entitlements"; then
    SIGNED_WITH="$IDENTITY"
    ok "Signed with $IDENTITY"
  else
    warn "Stable codesign failed — falling back to ad-hoc"
    codesign --force --sign - \
      --entitlements "$SRC/Resources/Bar.entitlements" \
      "$DEST_APP" 2>/dev/null || warn "codesign failed"
  fi
  codesign -d -r- "$DEST_APP" 2>&1 | sed -n 's/^designated => /  DR: /p' || true
fi

if [[ -x /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister ]]; then
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST_APP" 2>/dev/null || true
fi

mkdir -p "$BIN_DIR"
# Prefer the stowed shim from packages/bar. Only write a fallback when the
# target is missing — never replace an existing regular file (that breaks stow).
if [[ -L "$BIN_DIR/bar" ]]; then
  ok "CLI → $BIN_DIR/bar (stowed)"
elif [[ -e "$BIN_DIR/bar" ]]; then
  warn "CLI shim exists as a regular file at $BIN_DIR/bar"
  warn "Remove it and restow so packages/bar can own the link:"
  warn "  rm -f \"$BIN_DIR/bar\" && ./scripts/restow.sh"
else
  # Always ensure theme apply / skhd can find `bar` on PATH.
  if [[ -f "$ROOT/packages/bar/.local/bin/bar" ]]; then
    ln -sfn "$ROOT/packages/bar/.local/bin/bar" "$BIN_DIR/bar"
    ok "CLI → $BIN_DIR/bar (linked to packages/bar)"
  else
    cat >"$BIN_DIR/bar" <<EOF
#!/bin/sh
exec "$EXEC" "\$@"
EOF
    chmod +x "$BIN_DIR/bar"
    ok "CLI → $BIN_DIR/bar (local fallback shim)"
  fi
fi

# Seed config when theme apply has not run yet.
CONFIG_DIR="$HOME/.config/bar"
CONFIG_JSON="$CONFIG_DIR/config.json"
if [[ ! -f "$CONFIG_JSON" ]]; then
  mkdir -p "$CONFIG_DIR"
  if [[ -f "$ROOT/packages/bar/.config/bar/config.catppuccin-macchiato.json" ]]; then
    cp "$ROOT/packages/bar/.config/bar/config.catppuccin-macchiato.json" "$CONFIG_JSON"
    ok "Seeded $CONFIG_JSON (Catppuccin Macchiato)"
  fi
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
	<key>StandardOutPath</key>
	<string>/tmp/bar.out.log</string>
	<key>StandardErrorPath</key>
	<string>/tmp/bar.err.log</string>
</dict>
</plist>
EOF

info "Loading LaunchAgent $LABEL"
launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST" 2>/dev/null \
  || launchctl load -w "$PLIST_DST" 2>/dev/null \
  || warn "Could not load LaunchAgent — start manually: open \"$DEST_APP\""

ok "Bar installed"
print -r -- "  App:    $DEST_APP"
print -r -- "  CLI:    bar --omniwm-space 3"
print -r -- "  Signed: $SIGNED_WITH"
print -r -- "  Config: ~/.config/bar/config.json"
