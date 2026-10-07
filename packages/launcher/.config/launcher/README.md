# Launcher

Keyboard-driven app launcher and frontmost-app menu command palette.

Spawns as a floating panel beneath the display notch. Styles hot-reload from
this `config.json`. Built-in fallback theme is Catppuccin Macchiato when the
file is missing; the stowed defaults below follow the rice **Cinematic Noir**
palette (`~/.config/theme/`).

## Keys

| Key | Action |
| --- | --- |
| Type | Fuzzy filter |
| `↑` / `↓` | Move selection |
| `Enter` | Launch / activate |
| `Esc` | Hide |
| `Tab` | Toggle Apps ↔ Menu |
| Leading `:` | Jump to Menu mode |

## CLI (skhd)

```sh
launcher --toggle    # show / hide
launcher --menu      # open in Menu Search
launcher --reload    # re-read config.json
```

Rice default: `behavior.hotkey` is `"off"` so skhd owns `Alt+R` / `Alt+Shift+R`
without a Carbon double-fire. Set e.g. `"cmd+space"` for a standalone global hotkey.

## Build / install

```sh
./scripts/install-launcher.sh
```

Installs `~/Applications/Launcher.app`, a `launcher` shim on `PATH`, and loads
the LaunchAgent so the agent is ready for skhd.
