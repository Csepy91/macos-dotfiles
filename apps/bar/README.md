# Bar (SwiftPM)

Native macOS OmniWM workspace indicator for this rice. Shares notch positioning,
Catppuccin theming, JSON hot-reload, and Unix-socket IPC patterns with Launcher /
CalendarBar.

## Build

```sh
# From repo root (preferred)
./scripts/install-bar.sh

# Or manually
cd apps/bar
swift build -c release
```

Requires macOS 13+, Xcode / CLT, and OmniWM with `ipcEnabled = true`.

## Layout

| File | Role |
| --- | --- |
| `BarApp.swift` | CLI flags, IPC, `NSApplication` agent |
| `ConfigManager.swift` | `~/.config/bar/config.json` + hot reload |
| `TopBarWindow.swift` | Full-width top `NSPanel` |
| `OmniWMService.swift` | `omniwmctl` query + subscribe (no polling) |
| `WorkspaceViewModel.swift` | Active / occupied workspace state |
| `WorkspaceBarView.swift` | SwiftUI pills / dots bound to theme tokens |
| `Theme.swift` | Config schema + Catppuccin fallback colors |
| `IPCServer.swift` | Unix socket IPC + single-instance ping |

## CLI

```text
bar --omniwm-space 3
bar --omniwm-space '{"active":"3","occupied":["1","3"]}'
bar --reload
bar --refresh
```

Live updates come from `omniwmctl subscribe active-workspace,windows-changed,layout-changed`.
skhd can also call the CLI or post `com.dotfiles.bar.omniwm-space`.
