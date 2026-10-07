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

Rice default: `behavior.hotkey` is `"alt+r"` (Carbon) so OmniWM cannot swallow
the chord. skhd owns `Alt+Shift+R` → Menu Search only — do not also bind
`Alt+R` in skhdrc or toggle will double-fire (show then instantly hide).

## Build / install

```sh
./scripts/install-launcher.sh
```

Installs `~/Applications/Launcher.app`, a `launcher` shim on `PATH`, and loads
the LaunchAgent so the agent is ready for skhd.
