# Launcher (SwiftPM)

Native macOS notch launcher + menu-bar command palette for this rice.

## Build

```sh
# From repo root (preferred)
./scripts/install-launcher.sh

# Or manually
cd apps/launcher
swift build -c release
```

Requires macOS 13+, Xcode / CLT, and Accessibility for Menu Search.

## Layout

| File | Role |
| --- | --- |
| `LauncherApp.swift` | CLI flags, IPC, `NSApplication` agent |
| `ConfigManager.swift` | `~/.config/launcher/config.json` + hot reload |
| `NotchWindow.swift` | Floating `NSPanel` under the notch |
| `AppScanner.swift` | `/Applications` indexer |
| `MenuBarScanner.swift` | `AXUIElement` menu walk / press |
| `LauncherViewModel.swift` | Fuzzy filter, modes, keyboard |
| `MainView.swift` | SwiftUI UI bound to theme tokens |
| `HotkeyManager.swift` | Carbon global hotkey fallback |
| `IPCServer.swift` | Unix socket for `launcher --toggle` |

## skhd

```text
alt - r : ~/.config/skhd/open-launcher.sh
alt - shift - r : ~/.config/skhd/open-launcher-menu.sh
```
