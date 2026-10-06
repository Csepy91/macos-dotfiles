# Permissions & post-install checklist

OmniWM, skhd, sketchybar, and jankyborders need macOS privacy grants that
**cannot** be automated. Do these once after `./install.sh`.

## Safari / Finder / Dock / Trackpad

macOS UI preferences are left **manual**. Configure them in System Settings yourself.

Optional Safari tips:

- **Safari → Settings → Advanced → Show features for web developers**
- **Safari → Settings → Advanced → Show full website address**

## After a successful install

Confirm Stow linked configs and Homebrew apps:

```sh
ls -l ~/.zshrc
ls ~/.config/omniwm/settings.toml
ls /Applications/OmniWM.app
brew list --formula sketchybar borders skhd
ls -l /opt/homebrew/bin/skhd
```

Open a **new** terminal tab (so Homebrew is on `PATH`), then check:

```sh
alias ls
which eza
which skhd   # should print /opt/homebrew/bin/skhd
```

If `skhd` is “command not found” in an old shell, use the full path or open a new tab:

```sh
/opt/homebrew/bin/skhd --version
```

If `~/.zshrc` is missing, re-run `./install.sh --yes` or `./scripts/restow.sh`.

## Mission Control (required for OmniWM)

Path: **System Settings → Desktop & Dock → Mission Control**
→ **Displays have separate Spaces** = ON.

## How to open Privacy panes (macOS 26/27)

**Important:** there are two different “Accessibility” screens:

| Place | What it is | Needed for rice? |
| --- | --- | --- |
| **System Settings → Accessibility** | VoiceOver, Zoom, Display size, etc. | No |
| **System Settings → Privacy & Security → Accessibility** | Allow apps to **control the computer** | **Yes** |

You want the second one (privacy permission list with toggles).

### Terminal deep links

```sh
open "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
```

## Accessibility — REQUIRED

Enable for:

| App | How it appears / path |
| --- | --- |
| OmniWM | **OmniWM** |
| skhd | often **missing until you add it** — see below |
| sketchybar | often add via **+** → Go to Folder |
| borders | often add via **+** → Go to Folder |

### skhd does not show up automatically

`skhd` is a CLI binary, not an `.app`. macOS will not list it until you add it
manually (or until it has crashed once requesting access).

1. Start it (Homebrew has **no** `brew services` for skhd):

```sh
/opt/homebrew/bin/skhd --start-service
# or after config changes:
/opt/homebrew/bin/skhd --restart-service
```

2. Open **System Settings → Privacy & Security → Accessibility**
3. Unlock the padlock if present
4. Click **+**
5. Press **Cmd+Shift+G** (Go to Folder)
6. Paste:

```text
/opt/homebrew/bin/skhd
```

7. Toggle **skhd** ON
8. Also add and enable:

```text
/opt/homebrew/bin/sketchybar
/opt/homebrew/bin/borders
```

9. Restart:

```sh
/opt/homebrew/bin/skhd --restart-service
brew services restart sketchybar
brew services restart borders
launchctl kickstart -k "gui/$(id -u)/com.dotfiles.omniwm"
```

## Input Monitoring — REQUIRED for hotkeys

**Privacy & Security → Input Monitoring**

Enable **OmniWM** and **skhd** (add `/opt/homebrew/bin/skhd` with **+** if missing).

## Screen Recording (optional)

**Privacy & Security → Screen & System Audio Recording**

Enable **OmniWM** for Overview thumbnails / capture features.

## Secure Keyboard Entry

Disable **Secure Keyboard Entry** in Terminal/Ghostty menus while testing skhd,
or skhd may not receive key events in that terminal.

## First launch order

1. Grant permissions above as prompts appear
2. Start **OmniWM** (`open -a OmniWM`)
3. Confirm **sketchybar** is visible at the top
4. Confirm **borders** draws on the focused window
5. Test skhd: `Option+Return` → Ghostty, `Option+B` → Safari

## OmniWM vs sketchybar / jankyborders

This rice **disables** OmniWM’s built-in borders and workspace bar
(`~/.config/omniwm/settings.toml`). Do not re-enable them unless you turn off
borders / sketchybar.

## Launcher (deferred)

**Spotlight** (`Cmd+Space`) is the launcher for now.
OmniWM’s command palette (`Ctrl+Option+Space`) still works for windows/apps.

## Re-run

```sh
./install.sh --yes
# or
brew bundle --file ~/dotfiles/Brewfile && ./scripts/restow.sh
/opt/homebrew/bin/skhd --restart-service
```
