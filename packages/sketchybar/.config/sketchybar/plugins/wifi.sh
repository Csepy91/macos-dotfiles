#!/usr/bin/env bash
# Wi-Fi strength + up/down Mbps — Cinematic Noir

if [[ "${SENDER:-}" == "mouse.exited.global" ]]; then
  sketchybar --set "${NAME:-wifi}" popup.drawing=off
  exit 0
fi

CACHE_DIR="${HOME}/.cache/sketchybar"
CACHE_FILE="${CACHE_DIR}/wifi_net"
mkdir -p "${CACHE_DIR}"

ICON="󰖪"
LABEL="offline"
ICON_COLOR=""
LABEL_COLOR=""

if [[ -f "${HOME}/.config/theme/colors.sh" ]]; then
  # shellcheck disable=SC1091
  source "${HOME}/.config/theme/colors.sh"
  ICON_COLOR="$(theme_argb "$MUTED")"
  LABEL_COLOR="$(theme_argb "$FG")"
fi

# Prefer the hardware Wi-Fi device; fall back to the default route iface for counters.
WIFI_DEV="$(networksetup -listallhardwareports 2>/dev/null \
  | awk '/Wi-Fi|AirPort/{getline; print $2; exit}')"
IFACE="${WIFI_DEV:-en0}"

# RSSI via CoreWLAN (~150ms). Prints "off" when disconnected / powered down.
RSSI="$(swift -e '
import CoreWLAN
guard let i = CWWiFiClient.shared().interface(), i.powerOn() else {
  print("off"); exit(0)
}
guard i.ssid() != nil || i.rssiValue() < 0 else {
  print("off"); exit(0)
}
print(i.rssiValue())
' 2>/dev/null)"

if [[ "$RSSI" == "off" || -z "$RSSI" ]]; then
  ICON="󰖪"
  LABEL="offline"
  if [[ -n "$ICON_COLOR" ]]; then
    ICON_COLOR="$(theme_argb "$MUTED")"
  fi
else
  # Strength icons (Nerd Font wifi bars)
  if (( RSSI >= -50 )); then
    ICON="󰤨"
  elif (( RSSI >= -60 )); then
    ICON="󰤥"
  elif (( RSSI >= -70 )); then
    ICON="󰤢"
  elif (( RSSI >= -80 )); then
    ICON="󰤟"
  else
    ICON="󰤯"
  fi

  if (( RSSI < -75 )) && [[ -f "${HOME}/.config/theme/colors.sh" ]]; then
    ICON_COLOR="$(theme_argb "$AMBER")"
  fi

  # Byte counters from the Link row (avoid IPv4/IPv6 duplicates).
  read -r RX TX < <(netstat -ibn 2>/dev/null \
    | awk -v iface="$IFACE" '$1 == iface && $3 ~ /<Link/ { print $7, $10; exit }')
  RX="${RX:-0}"
  TX="${TX:-0}"
  NOW="$(python3 -c 'import time; print(time.time())')"

  DOWN_MBPS="0.0"
  UP_MBPS="0.0"
  if [[ -f "$CACHE_FILE" ]]; then
    read -r PREV_NOW PREV_RX PREV_TX <"$CACHE_FILE" || true
    if [[ -n "${PREV_NOW:-}" && -n "${PREV_RX:-}" && -n "${PREV_TX:-}" ]]; then
      read -r DOWN_MBPS UP_MBPS < <(python3 -c "
prev_now=float('${PREV_NOW}')
now=float('${NOW}')
dt=now-prev_now
if dt <= 0.2:
  print('0.0 0.0')
else:
  down=((int('${RX}')-int('${PREV_RX}'))*8)/(dt*1_000_000)
  up=((int('${TX}')-int('${PREV_TX}'))*8)/(dt*1_000_000)
  if down < 0: down = 0.0
  if up < 0: up = 0.0
  def fmt(v):
    return f'{v:.1f}' if v < 10 else f'{v:.0f}'
  print(fmt(down), fmt(up))
")
    fi
  fi
  printf '%s %s %s\n' "$NOW" "$RX" "$TX" >"$CACHE_FILE"

  LABEL="↓${DOWN_MBPS}Mbps ↑${UP_MBPS}Mbps"
fi

args=(--set "$NAME" icon="$ICON" label="$LABEL")
[[ -n "$ICON_COLOR" ]] && args+=(icon.color="$ICON_COLOR")
[[ -n "$LABEL_COLOR" ]] && args+=(label.color="$LABEL_COLOR")
sketchybar "${args[@]}"
