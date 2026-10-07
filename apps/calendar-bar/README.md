# CalendarBar (SwiftPM)

Native macOS notch calendar + EventKit agenda for this rice.

## Build

```sh
# From repo root (preferred)
./scripts/install-calendar-bar.sh

# Or manually
cd apps/calendar-bar
swift build -c release
```

Requires macOS 13+, Xcode / CLT, and Calendars privacy access for the agenda.
`./scripts/install-calendar-bar.sh` signs with a stable `dotfiles-CalendarBar`
cert so that grant survives rebuilds (ad-hoc signing does not).

## Layout

| File | Role |
| --- | --- |
| `CalendarApp.swift` | CLI flags, IPC, `NSApplication` agent |
| `ConfigManager.swift` | `~/.config/calendar/config.json` + hot reload |
| `NotchWindow.swift` | Floating `NSPanel` under the notch |
| `CalendarViewModel.swift` | Month grid, navigation, EventKit |
| `CalendarView.swift` | SwiftUI month + agenda bound to theme tokens |
| `Theme.swift` | Config schema + Catppuccin fallback colors |
| `IPCServer.swift` | Unix socket IPC + single-instance ping |

## CLI

```text
calendar-bar --toggle
calendar-bar --reload
```

Sketchybar clock click is wired to `--toggle`.
