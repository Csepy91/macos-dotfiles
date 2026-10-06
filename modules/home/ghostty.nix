# Ghostty is installed via Homebrew cask; HM only manages config + Stylix target.
{
  lib,
  config,
  ...
}:
{
  programs.ghostty = lib.mkIf config.features.rice.ghostty {
    enable = true;
    package = null; # installed by homebrew cask "ghostty"
    settings = {
      window-padding-x = 8;
      window-padding-y = 8;
      window-decoration = true;
      confirm-close-surface = false;
      macos-option-as-alt = true;
      font-size = 14;
      cursor-style = "block";
      shell-integration-features = "cursor,sudo,title";
    };
  };
}
