# macOS rice dotfiles

Declarative Apple Silicon macOS rice built on **nix-darwin**, **Home Manager**, and **Stylix**, with **Homebrew** only for GUI casks Nix cannot ship cleanly.

## Stack

| Layer | Tool |
| --- | --- |
| WM | OmniWM (borders/bar disabled) |
| Bar | sketchybar |
| Borders | jankyborders |
| App hotkeys | skhd |
| Terminal | Ghostty (Homebrew cask + HM config) |
| Shell | zsh + starship + plugins |
| Theme | Stylix (Catppuccin Mocha) |
| Launcher | Spotlight (temporary) |

## Requirements

- Apple Silicon (`arm64`)
- macOS 26+ recommended (OmniWM requirement)
- Network for first install

## Quick start

```sh
git clone <this-repo> ~/dotfiles
cd ~/dotfiles
chmod +x install.sh
./install.sh
```

The installer will:

1. Install Nix (if needed) and Homebrew (if needed)
2. Let you toggle CLI tools, rice components, and GUI apps (`gum`)
3. Write `hosts/<hostname>/features.nix`
4. Run `darwin-rebuild switch`

Then follow [docs/PERMISSIONS.md](docs/PERMISSIONS.md).

### Non-interactive

```sh
./install.sh --yes              # defaults + rebuild
./install.sh --yes --no-rebuild # only write features.nix
```

## Layout

See the plan / `modules/` and `hosts/default/`. Feature flags live in each host’s `features.nix`.

## Manual rebuild

```sh
sudo darwin-rebuild switch --flake .#<hostname>
```

Hostname attributes use LocalHostName with dots replaced by `-`.
