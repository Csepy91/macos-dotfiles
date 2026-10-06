{
  lib,
  config,
  ...
}:
let
  f = config.features.cli;
in
{
  programs.bat = lib.mkIf f.bat {
    enable = true;
  };

  programs.btop = lib.mkIf f.btop {
    enable = true;
  };

  programs.fzf = lib.mkIf f.fzf {
    enable = true;
    enableZshIntegration = true;
  };

  programs.zoxide = lib.mkIf f.zoxide {
    enable = true;
    enableZshIntegration = true;
  };

  programs.yazi = lib.mkIf f.yazi {
    enable = true;
    enableZshIntegration = true;
    shellWrapperName = "y";
  };

  programs.git = lib.mkIf f.git {
    enable = true;
    settings = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
      core.editor = "nvim";
    };
    # User identity left unset — set in hosts/*/home.nix or locally.
  };

  # HM module installs `gh` and wires zsh completion.
  programs.gh = lib.mkIf f.gh {
    enable = true;
    settings = {
      git_protocol = "https";
    };
  };
}
