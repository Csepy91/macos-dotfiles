# System-level Stylix (darwin). Home Manager inherits via followSystem.
{
  lib,
  config,
  pkgs,
  self,
  ...
}:
{
  stylix = lib.mkIf config.features.rice.stylix {
    enable = true;
    autoEnable = true;
    homeManagerIntegration = {
      autoImport = true;
      followSystem = true;
    };

    base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";
    image = "${self}/configs/wallpapers/default.png";
    polarity = "dark";

    fonts = {
      serif = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font";
      };
      sansSerif = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font";
      };
      monospace = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font";
      };
      emoji = {
        package = pkgs.noto-fonts-color-emoji;
        name = "Noto Color Emoji";
      };
      sizes = {
        applications = 12;
        desktop = 12;
        popups = 12;
        terminal = 14;
      };
    };

    opacity = {
      terminal = 0.95;
      applications = 1.0;
    };
  };
}
