# OmniWM app via Homebrew cask (/Applications); HM owns settings + launch agent.
{
  lib,
  config,
  ...
}:
let
  enabled = config.features.rice.omniwm;
  omniwmBin = "/Applications/OmniWM.app/Contents/MacOS/OmniWM";
in
{
  config = lib.mkIf enabled {
    xdg.configFile."omniwm/settings.toml".text = ''
      [general]
      animationsEnabled = true
      defaultLayoutType = "niri"
      hotkeysEnabled = true
      ipcEnabled = true
      updateChecksEnabled = true
      systemHyperTrigger = "None"

      [borders]
      enabled = false

      [workspaceBar]
      enabled = false

      [gaps]
      size = 8.0

      [gaps.outer]
      top = 36.0
      bottom = 8.0
      left = 8.0
      right = 8.0

      [appearance]
      mode = "dark"
    '';

    launchd.agents.omniwm = {
      enable = true;
      config = {
        Program = omniwmBin;
        KeepAlive = true;
        RunAtLoad = true;
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/omniwm/out.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/omniwm/err.log";
      };
    };
  };
}
