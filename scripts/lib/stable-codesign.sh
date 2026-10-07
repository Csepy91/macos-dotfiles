# Shared stable codesign helper for rice apps (Launcher, CalendarBar, …).
# Sourced by install-*.sh with CODESIGN_IDENTITY and (optionally) LABEL set.
#
# Uses a dedicated keychain with a known password so rebuilds can unlock the
# private key and set the codesign partition ACL without GUI prompts.
#
# Intentionally does NOT call `security add-trusted-cert` — that pops Keychain /
# admin dialogs and is unnecessary for signing. TCC (Accessibility) keys off the
# certificate leaf hash in the signature, which stays stable across rebuilds.

DOTFILES_CODESIGN_KC="${DOTFILES_CODESIGN_KC:-$HOME/Library/Keychains/dotfiles-codesign.keychain-db}"
# Local automation secret only — not used for network auth.
DOTFILES_CODESIGN_KC_PASS="${DOTFILES_CODESIGN_KC_PASS:-dotfiles}"

_codesign_kc_name() {
  print -r -- "$DOTFILES_CODESIGN_KC"
}

_ensure_codesign_keychain() {
  local kc="$(_codesign_kc_name)"
  if [[ ! -f "$kc" ]]; then
    info "Creating codesign keychain: $kc"
    security create-keychain -p "$DOTFILES_CODESIGN_KC_PASS" "$kc" >/dev/null
    security set-keychain-settings -lut 21600 "$kc" >/dev/null 2>&1 || true
  fi

  security unlock-keychain -p "$DOTFILES_CODESIGN_KC_PASS" "$kc" >/dev/null 2>&1 || true

  # Put our keychain first on the user search list so codesign finds the identity.
  local -a existing=()
  local line trimmed
  while IFS= read -r line; do
    trimmed="${line//\"/}"
    trimmed="${trimmed## }"
    trimmed="${trimmed%% }"
    [[ -n "$trimmed" && "$trimmed" != "$kc" ]] && existing+=("$trimmed")
  done < <(security list-keychains -d user 2>/dev/null)

  security list-keychains -d user -s "$kc" "${existing[@]}" >/dev/null 2>&1 || true
}

_cert_in_codesign_keychain() {
  security find-certificate -c "$CODESIGN_IDENTITY" "$(_codesign_kc_name)" >/dev/null 2>&1
}

_allow_codesign_key_use() {
  local kc="$(_codesign_kc_name)"
  security unlock-keychain -p "$DOTFILES_CODESIGN_KC_PASS" "$kc" >/dev/null 2>&1 || true
  # Partition ACL: lets /usr/bin/codesign use the key without "Always Allow" popups.
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
    -k "$DOTFILES_CODESIGN_KC_PASS" "$kc" >/dev/null 2>&1 || true
}

_create_codesign_identity() {
  (( $+commands[openssl] )) || return 1

  info "Creating self-signed code-signing cert: $CODESIGN_IDENTITY"
  local tmp kc
  tmp="$(mktemp -d)"
  kc="$(_codesign_kc_name)"
  _ensure_codesign_keychain

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
  if ! security import "$tmp/cert.p12" -k "$kc" \
      -P dotfiles -A -T /usr/bin/codesign -T /usr/bin/security >/dev/null 2>&1; then
    rm -rf "$tmp"
    return 1
  fi

  _allow_codesign_key_use
  rm -rf "$tmp"

  _cert_in_codesign_keychain && print -r -- "$CODESIGN_IDENTITY"
}

# Print a usable identity name, or return non-zero.
# Does not require the cert to be in the system trust store (avoids GUI prompts).
ensure_codesign_identity() {
  [[ -n "${CODESIGN_IDENTITY:-}" ]] || return 1

  _ensure_codesign_keychain
  if _cert_in_codesign_keychain; then
    _allow_codesign_key_use
    print -r -- "$CODESIGN_IDENTITY"
    return 0
  fi

  local created
  created="$(_create_codesign_identity || true)"
  if [[ -n "$created" ]]; then
    print -r -- "$created"
    return 0
  fi
  return 1
}

# Sign an .app bundle with the stable identity (no ad-hoc).
# Usage: sign_app /path/to/App.app [extra codesign args…]
sign_app() {
  local app="$1"
  shift
  local identity="${IDENTITY:-}"
  [[ -n "$identity" ]] || identity="$(ensure_codesign_identity)" || return 1

  _ensure_codesign_keychain
  _allow_codesign_key_use

  local -a args=(
    --force
    --sign "$identity"
    --keychain "$(_codesign_kc_name)"
  )
  [[ -n "${LABEL:-}" ]] && args+=(--identifier "$LABEL")
  args+=("$@" "$app")
  codesign "${args[@]}"
}
