{
  lib,
  config,
  ...
}:
let
  # Prefer Stylix palette when enabled; otherwise Catppuccin Mocha fallbacks.
  stylixOn = config.features.rice.stylix && (config.stylix.enable or false);
  active =
    if stylixOn then "0xff${config.lib.stylix.colors.base0D}" else "0xff89b4fa";
  inactive =
    if stylixOn then "0xff${config.lib.stylix.colors.base03}" else "0xff45475a";
in
{
  services.jankyborders = lib.mkIf config.features.rice.jankyborders {
    enable = true;
    settings = {
      style = "round";
      width = 6.0;
      hidpi = "on";
      active_color = active;
      inactive_color = inactive;
    };
  };
}
