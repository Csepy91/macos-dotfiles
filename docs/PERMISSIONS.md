# Permissions & post-install checklist

OmniWM, skhd, sketchybar, and jankyborders need macOS privacy grants that
**cannot** be automated by Nix. Do these once after `./install.sh`.

## Safari / Finder / Dock / Trackpad

macOS UI preferences are left **manual** (not managed by nix-darwin).
Configure them in System Settings yourself.

Optional Safari tips:

- **Safari → Settings → Advanced → Show features for web developers**
- **Safari → Settings → Advanced → Show full website address**

## After a successful rebuild

Confirm Home Manager activated (aliases + configs):

```sh
ls ~/.zshrc
ls ~/.config/omniwm/settings.toml
ls /Applications/OmniWM.app
```

Open a **new** terminal tab, then check:

```sh
alias ls
alias cd
which eza
```

If `~/.zshrc` is still missing, activation did not finish — re-run the rebuild and make sure it completes without `user defaults...` errors.

## Mission Control (required for OmniWM)

**Status on this Mac:** `Displays have separate Spaces` is already **ON** (`spans-displays=0`).

Path if you need to verify: **System Settings → Desktop & Dock → Mission Control**
→ **Displays have separate Spaces** = ON.

## How to open Privacy panes (macOS 26/27)

**Important:** there are two different “Accessibility” screens:

| Place | What it is | Needed for rice? |
| --- | --- | --- |
| **System Settings → Accessibility** | VoiceOver, Zoom, Display size, etc. | No |
| **System Settings → Privacy & Security → Accessibility** | Allow apps to **control the computer** | **Yes** |

You want the second one (privacy permission list with toggles), not the assistive-features page.

### Easiest: search

1. Open **System Settings**
2. Click the **search field** at the top (or press **Cmd+F** / click Search)
3. Type: `control the computer`  
   or: `Privacy Accessibility`
4. Choose the result like **“Allow assistive applications to control the computer”** / **Accessibility** under **Privacy & Security**

### Or browse

1. **System Settings**
2. Left sidebar → scroll near the bottom → **Privacy & Security**  
   (lock icon / shield style section — *not* the top-level **Accessibility** with the blue human icon)
3. In the right pane, scroll the privacy list → **Accessibility**
4. Unlock if needed, then enable apps / use **+**

### Terminal deep links

```sh
open "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
```

Same for Input Monitoring / Screen Recording:

```sh
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
```

## Accessibility — REQUIRED (currently missing for skhd)

`skhd` logs say: `must be run with accessibility access! abort..`
So Accessibility is **not** granted yet (at least for skhd).

Enable for:

| App | How it appears |
| --- | --- |
| OmniWM | **OmniWM** (normal app — should show up) |
| skhd | often **missing until you add it** (nix binary) |
| sketchybar | often missing until added |
| borders | often missing until added |

### If skhd / sketchybar / borders are not in the list

Nix binaries do not always auto-register. Add them manually:

1. Unlock the padlock (bottom left) if present
2. Click **+**
3. Press **Cmd+Shift+G** (Go to Folder)
4. Paste one of these paths and choose the binary:

```text
/etc/profiles/per-user/csepy/bin/skhd
/etc/profiles/per-user/csepy/bin/sketchybar
/etc/profiles/per-user/csepy/bin/borders
```

5. Toggle each entry **ON**
6. Restart the agents:

```sh
launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.skhd"
launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.sketchybar"
launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.jankyborders"
launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.omniwm"
```

## Input Monitoring — REQUIRED for hotkeys

Same **Privacy & Security** page → **Input Monitoring**.

Enable:

- **OmniWM**
- **skhd** (add with **+** and Go to Folder if missing — same path as above)

## Screen Recording (optional)

**Privacy & Security → Screen & System Audio Recording** (label may be “Screen Recording”).

Enable **OmniWM** for Overview thumbnails / capture features.

## Secure Keyboard Entry

Disable **Secure Keyboard Entry** in Terminal/Ghostty menus while testing skhd,
or skhd may not receive key events in that terminal.

## First launch order

1. Grant permissions above as prompts appear
2. Start **OmniWM** (Launchpad / Applications / `open -a OmniWM`)
3. Confirm **sketchybar** is visible at the top (hide the macOS menu bar in System Settings if you want)
4. Confirm **jankyborders** draws a border on the focused window
5. Test skhd: `Option+Return` → Ghostty, `Option+B` → Safari

## OmniWM vs sketchybar / jankyborders

This rice **disables** OmniWM’s built-in borders and workspace bar
(`~/.config/omniwm/settings.toml`). Do not re-enable them unless you turn off
jankyborders / sketchybar.

## Launcher (deferred)

**Spotlight** (`Cmd+Space`) is the launcher for now.
OmniWM’s command palette (`Ctrl+Option+Space`) still works for windows/apps.

A riceable picker (Pounce / macmenu / Sol / Alfred) can be added later as an
optional feature flag without redesigning the stack.

## Rebuild

```sh
sudo darwin-rebuild switch --flake ~/dotfiles#$(scutil --get LocalHostName | tr '.' '-')
# or
./install.sh --yes
```
