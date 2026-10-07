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
| Launcher | **Launcher** (`~/Applications/Launcher.app`) — menu-bar search; see note below |
| skhd | often **missing until you add it** — see below |
| sketchybar | often add via **+** → Go to Folder |
| borders | often add via **+** → Go to Folder |

### skhd does not show up automatically

`skhd` is a CLI binary, not an `.app`. macOS will not list it until you add it
manually (or until it has run once requesting access).

1. Install + start its LaunchAgent (do **not** use `brew services` — skhd has none).
   `--restart-service` fails until the plist exists; use `--start-service` first:

```sh
/opt/homebrew/bin/skhd --install-service   # writes ~/Library/LaunchAgents/com.koekeishiya.skhd.plist
/opt/homebrew/bin/skhd --start-service     # bootstrap + run (also auto-installs if missing)
# later, after config changes:
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

## macOS menu bar (required for sketchybar)

If the system menu bar auto-hides, a click at the top edge summons it and
**destroys sketchybar’s windows** (process stays running, bar gone until restart).
Some apps / OmniWM fill also flash the menu bar when the setting is only
**In Full Screen Only** instead of **Never**.

Check (Never = both of these):

```sh
defaults read NSGlobalDomain _HIHideMenuBar
# false
defaults read NSGlobalDomain AppleMenuBarVisibleInFullscreen
# true  (true = Never; false = In Full Screen Only when hide is false)
```

Fix:

```sh
./scripts/fix-sketchybar-menubar.sh
# or:
defaults write NSGlobalDomain _HIHideMenuBar -bool false
defaults write NSGlobalDomain AppleMenuBarVisibleInFullscreen -bool true
defaults write com.apple.controlcenter AutoHideMenuBarOption -int 3
killall SystemUIServer ControlCenter
brew services restart sketchybar && sleep 1 && bash ~/.config/sketchybar/sketchybarrc
```

Also set **System Settings → Desktop & Dock → Automatically hide and show the
menu bar → Never**.

## OmniWM vs sketchybar / jankyborders

This rice **disables** OmniWM’s built-in borders, workspace bar, and Hidden Bar
(`~/.config/omniwm/settings.toml`). Do not re-enable workspace bar / borders
unless you turn off borders / sketchybar.

## Launcher

Notch-spawned keyboard launcher (`~/Applications/Launcher.app`).

| Hotkey | Action |
| --- | --- |
| `Alt+R` | Toggle Apps mode (Launcher Carbon hotkey) |
| `Alt+Shift+R` | Open Menu Bar Search (`launcher --menu` via skhd) |
| `Tab` / leading `:` | Switch Apps ↔ Menu inside the panel |

`behavior.hotkey` defaults to `"alt+r"`. Keep that chord out of skhdrc to avoid
a double-fire. Grant **Accessibility** to **Launcher** for the hotkey + menu search.

Build / rebuild:

```sh
./scripts/install-launcher.sh
```

Config (hot-reloads): `~/.config/launcher/config.json`

Grant **Accessibility** to **Launcher** so Menu Search can read and activate
menu items. The panel shows a banner if permission is missing.

**Ghost grants after rebuild:** Accessibility is bound to the app’s code
signature, not just its name. Ad-hoc signed builds get a new identity every
`./scripts/install-launcher.sh`, so Settings can still show Launcher enabled
while Menu Search is denied. Fix once:

1. Run `./scripts/install-launcher.sh` — it should print `Signed: dotfiles-Launcher`
   (not `ad-hoc`). The script creates/trusts that cert so rebuilds keep the grant.
2. In **Privacy & Security → Accessibility**, remove every old **Launcher** row.
3. Click **+** → add `~/Applications/Launcher.app` → toggle **on**.
4. `launchctl kickstart -k gui/$(id -u)/com.dotfiles.launcher` (or log out/in).

If install still says `Signed: ad-hoc`, open **Keychain Access**, find
`dotfiles-Launcher`, Get Info → Trust → **Code Signing: Always Trust**, then
re-run the install script and repeat steps 2–4 once.

OmniWM’s built-in palette remains on `Control+Option+Space`. Spotlight
(`Cmd+Space`) is unchanged unless you set Launcher’s `behavior.hotkey` to it.

## CalendarBar

Notch-spawned calendar + agenda (`~/Applications/CalendarBar.app`).

| Trigger | Action |
| --- | --- |
| Sketchybar clock click | Toggle panel (`calendar-bar --toggle`) |
| `calendar-bar --reload` | Re-read `~/.config/calendar/config.json` |

Build / rebuild:

```sh
./scripts/install-calendar-bar.sh
```

Config (hot-reloads): `~/.config/calendar/config.json`

Grant **Calendars** to **CalendarBar** so the agenda can read EventKit events.
The panel shows a clean unauthorized state with a Settings link if permission
is missing.

**Ghost grants after rebuild:** same as Launcher — prefer the
`dotfiles-CalendarBar` signing cert created by the install script, then add
`~/Applications/CalendarBar.app` once under Privacy → Calendars.

## Re-run

```sh
./install.sh --yes
# or
brew bundle --file ~/dotfiles/Brewfile && ./scripts/restow.sh
/opt/homebrew/bin/skhd --install-service
/opt/homebrew/bin/skhd --start-service
```
