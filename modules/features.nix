# Declares `config.features` for both nix-darwin and Home Manager.
{
  lib,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
  boolOpt =
    default: description:
    mkOption {
      type = types.bool;
      inherit default description;
    };
in
{
  options.features = {
    cli = {
      bat = boolOpt true "Install and configure bat";
      btop = boolOpt true "Install and configure btop";
      duti = boolOpt true "Install duti";
      eza = boolOpt true "Install eza";
      fd = boolOpt true "Install fd";
      fzf = boolOpt true "Install and configure fzf";
      gh = boolOpt true "Install GitHub CLI";
      git = boolOpt true "Configure git";
      ncdu = boolOpt true "Install ncdu";
      ripgrep = boolOpt true "Install ripgrep";
      starship = boolOpt true "Install and configure starship";
      tldr = boolOpt true "Install tldr";
      uv = boolOpt true "Install uv";
      zoxide = boolOpt true "Install and configure zoxide";
      yazi = boolOpt true "Install and configure yazi";
    };

    rice = {
      omniwm = boolOpt true "Enable OmniWM";
      sketchybar = boolOpt true "Enable sketchybar";
      jankyborders = boolOpt true "Enable jankyborders";
      skhd = boolOpt true "Enable skhd for app-launch hotkeys";
      ghostty = boolOpt true "Configure Ghostty (install via Homebrew cask)";
      stylix = boolOpt true "Enable Stylix theming";
    };

    apps = {
      cursor = boolOpt true "Install Cursor";
      sublimeText = boolOpt true "Install Sublime Text";
      teamviewer = boolOpt false "Install TeamViewer";
      transmission = boolOpt true "Install Transmission";
      iina = boolOpt true "Install IINA";
      libreoffice = boolOpt true "Install LibreOffice";
      geForceNow = boolOpt false "Install NVIDIA GeForce NOW";
    };
  };
}
