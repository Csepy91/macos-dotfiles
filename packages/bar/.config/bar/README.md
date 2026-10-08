# Bar

Native OmniWM workspace status bar.

Styles come from `~/.config/bar/config.json`, which is **owned by the theme
engine** (`theme apply <palette>` → `templates/bar.config.json`). Do not stow a
live config — only the Catppuccin Macchiato sidecar is kept here for reference.
Missing file → in-app Catppuccin Macchiato fallback until the next `theme apply`.

`theme apply` also runs `bar --reload` (or talks to `Bar.app` directly) so the
running agent picks up the new palette immediately; the file watcher covers
manual edits too.

## CLI

```sh
bar                         # start agent (LaunchAgent)
bar --omniwm-space 3        # optimistic active workspace + re-query
bar --omniwm-space          # re-query OmniWM
bar --reload                # re-read config.json
bar --refresh               # re-query without reloading config
```

## Build / install

```sh
./scripts/install-bar.sh
```
