# Home Manager Stylix targets (feature-gated).
# Base scheme/fonts/wallpaper come from modules/darwin/stylix.nix via followSystem.
{
  lib,
  config,
  ...
}:
{
  stylix = lib.mkIf config.features.rice.stylix {
    targets = {
      ghostty.enable = config.features.rice.ghostty;
      bat.enable = config.features.cli.bat;
      btop.enable = config.features.cli.btop;
      starship.enable = config.features.cli.starship;
      fzf.enable = config.features.cli.fzf;
      yazi.enable = config.features.cli.yazi;
    };
  };
}
