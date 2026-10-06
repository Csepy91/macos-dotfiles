#!/usr/bin/env bash
# Populate the Wi-Fi SketchyBar popup with scanned networks (select to join).

set -euo pipefail

NAME="${NAME:-wifi}"
PLUGIN_DIR="${HOME}/.config/sketchybar/plugins"

BAR_FG=""
MUTED_C=""
ACCENT=""
PILL_BG=""
if [[ -f "${HOME}/.config/theme/colors.sh" ]]; then
  # shellcheck disable=SC1091
  source "${HOME}/.config/theme/colors.sh"
  BAR_FG="$(theme_argb "$FG")"
  MUTED_C="$(theme_argb "$MUTED")"
  ACCENT="$(theme_argb "$BLUE_BRIGHT")"
  PILL_BG="$(theme_argb "$SURFACE")"
fi

LABEL_FONT="Hack Nerd Font:Bold:12.0"
ICON_FONT="Symbols Nerd Font:Regular:14.0"

WIFI_DEV="$(networksetup -listallhardwareports 2>/dev/null \
  | awk '/Wi-Fi|AirPort/{getline; print $2; exit}')"
IFACE="${WIFI_DEV:-en0}"

# Current SSID (ipconfig still reports it when CoreWLAN ssid() is redacted).
CURRENT="$(ipconfig getsummary "${IFACE}" 2>/dev/null \
  | awk -F ' SSID : ' '/ SSID : /{print $2; exit}')"
CURRENT="${CURRENT:-}"

# Scan: "RSSI<TAB>SECURE|OPEN<TAB>SSID"
SCAN="$(
  /usr/bin/swift - 2>/dev/null <<'SWIFT'
import CoreWLAN
import Foundation

guard let iface = CWWiFiClient.shared().interface(), iface.powerOn() else {
  print("OFF")
  exit(0)
}
do {
  let nets = try iface.scanForNetworks(withName: nil)
  var best: [String: (rssi: Int, open: Bool)] = [:]
  for n in nets {
    guard let ssid = n.ssid, !ssid.isEmpty else { continue }
    let open = n.supportsSecurity(.none)
    let rssi = Int(n.rssiValue)
    if let prev = best[ssid] {
      if rssi > prev.rssi { best[ssid] = (rssi, open) }
    } else {
      best[ssid] = (rssi, open)
    }
  }
  let rows = best.map { ($0.value.rssi, $0.value.open, $0.key) }
    .sorted { $0.0 > $1.0 }
  for (rssi, open, ssid) in rows.prefix(12) {
    let sec = open ? "OPEN" : "SECURE"
    print("\(rssi)\t\(sec)\t\(ssid)")
  }
} catch {
  fputs("scan_error\n", stderr)
  exit(1)
}
SWIFT
)" || SCAN=""

# Clear previous popup rows.
for i in $(seq 0 20); do
  sketchybar --remove "${NAME}.net.${i}" 2>/dev/null || true
done
sketchybar --remove "${NAME}.hdr" 2>/dev/null || true
sketchybar --remove "${NAME}.pwr" 2>/dev/null || true

args=()
idx=0

add_row() {
  local item="$1" icon="$2" label="$3" color="$4" click="${5:-}"
  args+=(
    --add item "$item" "popup.${NAME}"
    --set "$item"
      icon="$icon"
      icon.font="$ICON_FONT"
      icon.color="$color"
      icon.padding_left=8
      icon.padding_right=6
      label="$label"
      label.font="$LABEL_FONT"
      label.color="$color"
      label.padding_left=0
      label.padding_right=12
      background.drawing=off
      padding_left=4
      padding_right=4
  )
  if [[ -n "$click" ]]; then
    args+=(click_script="$click")
  else
    args+=(click_script="sketchybar --set ${NAME} popup.drawing=off")
  fi
}

if [[ "$SCAN" == "OFF" || -z "$SCAN" ]]; then
  add_row "${NAME}.hdr" "󰖪" "Wi-Fi Off" "${MUTED_C:-0xff6d7291}"
  add_row "${NAME}.pwr" "󰐻" "Turn Wi-Fi On" "${BAR_FG:-0xffd0d2df}" \
    "networksetup -setairportpower ${IFACE} on; sketchybar --set ${NAME} popup.drawing=off; ${PLUGIN_DIR}/wifi.sh"
else
  if [[ -n "$CURRENT" ]]; then
    add_row "${NAME}.hdr" "󰖩" "Connected: ${CURRENT}" "${ACCENT:-$BAR_FG}"
  else
    add_row "${NAME}.hdr" "󰖩" "Select a network" "${MUTED_C:-0xff6d7291}"
  fi
  add_row "${NAME}.pwr" "󰖪" "Turn Wi-Fi Off" "${BAR_FG:-0xffd0d2df}" \
    "networksetup -setairportpower ${IFACE} off; sketchybar --set ${NAME} popup.drawing=off; ${PLUGIN_DIR}/wifi.sh"

  while IFS=$'\t' read -r rssi sec ssid; do
    [[ -n "$ssid" ]] || continue
    icon="󰤨"
    if (( rssi <= -80 )); then icon="󰤯"
    elif (( rssi <= -70 )); then icon="󰤟"
    elif (( rssi <= -60 )); then icon="󰤢"
    elif (( rssi <= -50 )); then icon="󰤥"
    fi
    [[ "$sec" == "OPEN" ]] && icon="󰀝"

    color="${BAR_FG:-0xffd0d2df}"
    label="$ssid"
    if [[ -n "$CURRENT" && "$ssid" == "$CURRENT" ]]; then
      color="${ACCENT:-$BAR_FG}"
      label="${ssid}  ✓"
    fi

    # Escape for click_script single-quoted join helper.
    safe_ssid="${ssid//\'/\'\\\'\'}"
    add_row "${NAME}.net.${idx}" "$icon" "$label" "$color" \
      "${PLUGIN_DIR}/wifi_join.sh '${safe_ssid}'; sketchybar --set ${NAME} popup.drawing=off"
    idx=$((idx + 1))
  done <<<"$SCAN"
fi

[[ ${#args[@]} -gt 0 ]] && sketchybar "${args[@]}"
sketchybar --set "$NAME" popup.drawing=on
