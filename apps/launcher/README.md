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
`./scripts/install-launcher.sh` signs with a stable `dotfiles-Launcher` cert so
that grant survives rebuilds (ad-hoc signing does not).

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
| `HotkeyManager.swift` | Carbon global hotkey (opt-in; rice uses skhd) |
| `IPCServer.swift` | Unix socket IPC + single-instance ping |

## Hotkeys

`Alt+R` is registered by Launcher itself (`behavior.hotkey` in config.json).
skhd only owns Menu Search:

```text
alt + shift - r : ~/.config/skhd/open-launcher-menu.sh
```
