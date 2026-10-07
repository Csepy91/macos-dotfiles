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

# ---------------------------------------------------------------------------
# Codesigning — prefer a stable self-signed cert over ad-hoc.
# ---------------------------------------------------------------------------
login_keychain() {
  local keychain="$HOME/Library/Keychains/login.keychain-db"
  [[ -f "$keychain" ]] || keychain="$HOME/Library/Keychains/login.keychain"
  print -r -- "$keychain"
}

identity_names_from_find() {
  sed -n 's/.*"\([^"]*\)".*/\1/p'
}

find_codesign_identity() {
  security find-identity -p codesigning -v 2>/dev/null \
    | identity_names_from_find \
    | grep -Fx "$CODESIGN_IDENTITY" \
    | head -1
}

cert_exists() {
  security find-certificate -c "$CODESIGN_IDENTITY" >/dev/null 2>&1
}

trust_codesign_cert() {
  local keychain tmp
  keychain="$(login_keychain)"
  tmp="$(mktemp -d)"
  if ! security find-certificate -c "$CODESIGN_IDENTITY" -p >"$tmp/cert.pem" 2>/dev/null; then
    rm -rf "$tmp"
    return 1
  fi
  security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$tmp/cert.pem" >/dev/null 2>&1 \
    || security add-trusted-cert -d -r trustAsRoot -p codeSign -k "$keychain" "$tmp/cert.pem" >/dev/null 2>&1 \
    || true
  rm -rf "$tmp"
  [[ -n "$(find_codesign_identity || true)" ]]
}

ensure_codesign_identity() {
  local found
  found="$(find_codesign_identity || true)"
  if [[ -n "$found" ]]; then
    print -r -- "$found"
    return 0
  fi

  if cert_exists; then
    info "Trusting existing code-signing cert: $CODESIGN_IDENTITY"
    if trust_codesign_cert; then
      find_codesign_identity
      return 0
    fi
    warn "Could not trust $CODESIGN_IDENTITY — fix in Keychain Access (Get Info → Trust → Code Signing: Always Trust)"
  fi

  (( $+commands[openssl] )) || return 1

  info "Creating self-signed code-signing cert: $CODESIGN_IDENTITY"
  local tmp keychain
  tmp="$(mktemp -d)"
  keychain="$(login_keychain)"

  cat >"$tmp/openssl.cnf" <<EOF
[ req ]
distinguished_name = req_distinguished_name
prompt = no
x509_extensions = codesign_ext

[ req_distinguished_name ]
CN = ${CODESIGN_IDENTITY}

[ codesign_ext ]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF

  if ! openssl req -new -newkey rsa:2048 -x509 -days 3650 -nodes \
      -keyout "$tmp/key.pem" -out "$tmp/cert.pem" \
      -config "$tmp/openssl.cnf" >/dev/null 2>&1; then
    rm -rf "$tmp"
    return 1
  fi
  if ! openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
      -out "$tmp/cert.p12" -passout pass:dotfiles -name "$CODESIGN_IDENTITY" \
      >/dev/null 2>&1; then
    rm -rf "$tmp"
    return 1
  fi
  if ! security import "$tmp/cert.p12" -k "$keychain" \
      -P dotfiles -A -T /usr/bin/codesign -T /usr/bin/security >/dev/null 2>&1; then
    rm -rf "$tmp"
    return 1
  fi
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" \
    "$keychain" >/dev/null 2>&1 || true
  security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$tmp/cert.pem" >/dev/null 2>&1 \
    || security add-trusted-cert -d -r trustAsRoot -p codeSign -k "$keychain" "$tmp/cert.pem" >/dev/null 2>&1 \
    || true
  rm -rf "$tmp"

  find_codesign_identity
}

sign_app() {
  local identity="$1"
  codesign --force --deep --sign "$identity" \
    --identifier "$LABEL" \
    --entitlements "$SRC/Resources/CalendarBar.entitlements" \
    "$DEST_APP"
}

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
  if [[ -n "${IDENTITY:-}" ]]; then
    if sign_app "$IDENTITY"; then
      SIGNED_WITH="$IDENTITY"
      ok "Signed with $IDENTITY (Calendar grant survives rebuilds)"
    else
      warn "Signing with $IDENTITY failed — falling back to ad-hoc"
      codesign --force --deep --sign - \
        --entitlements "$SRC/Resources/CalendarBar.entitlements" \
        "$DEST_APP" 2>/dev/null \
        || warn "codesign failed"
    fi
  else
    warn "No codesign identity — using ad-hoc (Calendar access may reset every rebuild)"
    warn "Create one: Keychain Access → Certificate Assistant → Code Signing → name '$CODESIGN_IDENTITY'"
    codesign --force --deep --sign - \
      --entitlements "$SRC/Resources/CalendarBar.entitlements" \
      "$DEST_APP" 2>/dev/null \
      || warn "codesign failed"
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
