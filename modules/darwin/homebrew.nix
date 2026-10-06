{
  lib,
  config,
  pkgs,
  ...
}:
let
  f = config.features;
  mkCasks =
    attrs:
    lib.flatten (
      lib.mapAttrsToList (name: enabled: lib.optional enabled name) attrs
    );
in
{
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "zap";
    };

    taps = [ ];

    brews = [ ];

    casks = mkCasks {
      # Terminal — nixpkgs darwin Ghostty can be awkward; prefer cask.
      ghostty = f.rice.ghostty;

      # Always use the signed Homebrew cask so OmniWM lands in /Applications.
      omniwm = f.rice.omniwm;

      cursor = f.apps.cursor;
      "sublime-text" = f.apps.sublimeText;
      teamviewer = f.apps.teamviewer;
      transmission = f.apps.transmission;
      iina = f.apps.iina;
      # LibreOffice: prefer nix libreoffice-bin in modules/home/gui.nix; cask if absent.
      libreoffice = f.apps.libreoffice && !(builtins.hasAttr "libreoffice-bin" pkgs);
      "nvidia-geforce-now" = f.apps.geForceNow;
    };
  };
}
