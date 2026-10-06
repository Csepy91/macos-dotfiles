# Prefer Homebrew casks for GUI apps (see modules/darwin/homebrew.nix).
# Keep this module for optional nix-only GUI packages.
{ lib, config, pkgs, ... }:
{
  home.packages = lib.optional (
    config.features.apps.libreoffice && builtins.hasAttr "libreoffice-bin" pkgs
  ) pkgs.libreoffice-bin;
}
