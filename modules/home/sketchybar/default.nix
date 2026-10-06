{
  lib,
  config,
  pkgs,
  ...
}:
let
  stylixOn = config.features.rice.stylix && (config.stylix.enable or false);
  barBg = if stylixOn then "0xff${config.lib.stylix.colors.base00}" else "0xff1e1e2e";
  barFg = if stylixOn then "0xff${config.lib.stylix.colors.base05}" else "0xffcdd6f4";
  accent = if stylixOn then "0xff${config.lib.stylix.colors.base0D}" else "0xff89b4fa";
  pluginDir = "${config.xdg.configHome}/sketchybar/plugins";
in
{
  programs.sketchybar = lib.mkIf config.features.rice.sketchybar {
    enable = true;
    configType = "bash";
    config = ''
      PLUGIN_DIR="${pluginDir}"

      sketchybar --bar \
        height=32 \
        blur_radius=20 \
        position=top \
        sticky=on \
        padding_left=8 \
        padding_right=8 \
        color=${barBg}

      sketchybar --default \
        icon.font="JetBrainsMono Nerd Font:Bold:14.0" \
        label.font="JetBrainsMono Nerd Font:Bold:12.0" \
        icon.color=${barFg} \
        label.color=${barFg} \
        padding_left=4 \
        padding_right=4 \
        background.height=24 \
        background.corner_radius=6

      sketchybar --add item apple.logo left \
        --set apple.logo icon= icon.color=${accent} label.drawing=off

      sketchybar --add item front_app left \
        --set front_app script="$PLUGIN_DIR/front_app.sh" \
                        icon.drawing=off \
        --subscribe front_app front_app_switched

      sketchybar --add item clock right \
        --set clock update_freq=10 script="$PLUGIN_DIR/clock.sh" \
                    icon=󰥔

      sketchybar --add item battery right \
        --set battery update_freq=60 script="$PLUGIN_DIR/battery.sh"

      sketchybar --add item volume right \
        --set volume script="$PLUGIN_DIR/volume.sh" \
        --subscribe volume volume_change

      sketchybar --update
    '';
  };

  xdg.configFile = lib.mkIf config.features.rice.sketchybar {
    "sketchybar/plugins/clock.sh" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        sketchybar --set "$NAME" label="$(date '+%a %d %b %H:%M')"
      '';
    };
    "sketchybar/plugins/battery.sh" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        PERCENTAGE="$(pmset -g batt | grep -Eo '[0-9]+%' | head -1 | tr -d '%')"
        CHARGING="$(pmset -g batt | grep 'AC Power' || true)"
        ICON="󰁹"
        if [ -n "$CHARGING" ]; then
          ICON="󰂄"
        elif [ "''${PERCENTAGE:-0}" -lt 20 ]; then
          ICON="󰁺"
        elif [ "''${PERCENTAGE:-0}" -lt 50 ]; then
          ICON="󰁾"
        fi
        sketchybar --set "$NAME" icon="$ICON" label="''${PERCENTAGE}%"
      '';
    };
    "sketchybar/plugins/volume.sh" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        VOLUME=$(osascript -e 'output volume of (get volume settings)' 2>/dev/null || echo 0)
        MUTED=$(osascript -e 'output muted of (get volume settings)' 2>/dev/null || echo false)
        if [ "$MUTED" = "true" ]; then
          ICON="󰖁"
        else
          ICON="󰕾"
        fi
        sketchybar --set "$NAME" icon="$ICON" label="''${VOLUME}%"
      '';
    };
    "sketchybar/plugins/front_app.sh" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        sketchybar --set "$NAME" label="$INFO"
      '';
    };
  };

  home.packages = lib.mkIf config.features.rice.sketchybar [ pkgs.jq ];
}
